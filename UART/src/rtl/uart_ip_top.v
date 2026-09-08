`timescale 1ns/1ps
//=============================================================================
// uart_ip_top.v — UART 控制器 IP 顶层（实验二交付物，独立可复用 IP Core）
//   文档：UART/doc/modules/uart_ip_top.md（端口/译码/验收权威）
//         UART/doc/top_design.md（IP 顶层设计）
//   口径：
//     - 独立 IP：寄存器层（分频 + TX 挂起/缓冲 + RX 字节/有效位 + 槽位义，
//       原 uart_ctrl 已并入本模块）与 uart_tx/uart_rx 收发引擎一体例化，
//       对外只暴露一条通用从机总线 + 串行引脚，无任何宿主 CPU 依赖；
//     - 寄存器映射译码由 IP 自含：addr[3:2] → 槽（00=TX 01=STAT 10=RX
//       11=保留）；窗口命中由系统侧译码经 cs 提供（窗口基址为系统级
//       契约，见 interface.md §3：0x0000_4000 + {0x0,0x4,0x8}）；
//     - 时序契约（interface.md §2 硬约束）：读=组合（拍内稳定）、
//       写=末沿锁存、单周期无 wait、未命中读 0/写丢弃；TX_BUSY 含挂起
//       待发；无 FIFO、忙写丢弃；
//     - SoC 集成：soc/rtl/soc_top.v 例化本模块，core 的 mmio 总线
//       （cs_mmio/reg_off）经 {reg_off,2'b00} 适配为 addr[3:0]。
//=============================================================================

module uart_ip_top #(
    parameter [15:0] CLKS_PER_BIT = 16'd868   // 115200 @ 100MHz；仿真可覆盖
) (
    input  wire        clk,
    input  wire        rst,          // 异步高有效
    // ---- 从机总线（IP 自含寄存器映射译码）----
    input  wire        cs,           // 窗口命中（系统侧译码提供；=0 读 0/写丢弃）
    input  wire [3:0]  addr,         // 窗口内字节偏移：0x0=TX 0x4=STAT 0x8=RX（4 对齐）
    input  wire        we,
    input  wire [31:0] wdata,
    output wire [31:0] rdata,        // 组合读（cs=0 或保留槽=0）
    // ---- 串行侧 ----
    output wire        uart_tx_pin,  // 8N1，空闲高
    input  wire        uart_rx_pin   // 输入在 uart_rx 内打两拍
);

    // ---- IP 自含译码：addr[3:2] → 槽（00=TX 01=STAT 10=RX 11=保留）----
    wire [1:0] reg_off = addr[3:2];

    // ---- clk_en 分频（每 bit 时间 1 脉冲，收发共用）----
    reg [15:0] baud_cnt;
    reg        bit_tick;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            baud_cnt <= 16'd0;
            bit_tick <= 1'b0;
        end else if (baud_cnt == CLKS_PER_BIT - 16'd1) begin
            baud_cnt <= 16'd0;
            bit_tick <= 1'b1;
        end else begin
            baud_cnt <= baud_cnt + 16'd1;
            bit_tick <= 1'b0;
        end
    end

    // ---- 收发例化信号（先声明，供下方时序块引用）----
    wire        uart_rx_valid;
    wire [7:0]  uart_rx_data;
    wire        tx_pin;
    wire        tx_busy;
    wire        tx_done;

    // ---- TX 挂起/缓冲 ----
    reg        tx_pend;
    reg  [7:0] tx_buf;
    // 写接受：完全空闲（无挂起、非移位忙）→ 挂起；否则丢弃
    // （挂起期写也丢弃，避免覆盖待发字节——STAT.TX_BUSY 含挂起，软件
    //   按"busy=0 才写"轮询即可防丢字）
    wire       tx_accept = cs && we && (reg_off == 2'b00) &&
                           !tx_busy && !tx_pend;
    wire       tx_fire   = tx_pend && !tx_busy;     // 组合 start（脉冲沿拍采样）

    // ---- RX 寄存器 ----
    reg        rx_valid;                    // RX_VALID
    reg  [7:0] rx_byte;
    wire       rx_clear = cs && !we && (reg_off == 2'b10) && rx_valid;

    // ---- 组合读（STAT bit0=TX_BUSY：挂起待发或移位中）----
    wire [31:0] rdata_tx   = 32'd0;
    wire [31:0] rdata_stat = {30'b0, rx_valid, tx_busy | tx_pend};
    wire [31:0] rdata_rx   = {24'b0, rx_byte};
    assign rdata = cs ?
                   (reg_off == 2'b00) ? rdata_tx :
                   (reg_off == 2'b01) ? rdata_stat :
                   (reg_off == 2'b10) ? rdata_rx   : 32'd0 :
                   32'd0;

    // ---- 时序 ----
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            tx_pend <= 1'b0;
            tx_buf  <= 8'd0;
            rx_valid <= 1'b0;
            rx_byte  <= 8'd0;
        end else begin
            // TX 写接受（忙时丢弃：不置 pend）
            if (tx_accept) begin
                tx_pend <= 1'b1;
                tx_buf  <= wdata[7:0];
            end
            // 发送启动拍：pend 且空闲且遇 bit_tick → uart_tx 同沿接受
            if (bit_tick && tx_pend && !tx_busy) begin
                tx_pend <= 1'b0;
            end
            // RX：收到完整字节（rx_valid 脉冲在 uart_rx 已置 1 一拍后采样）
            if (uart_rx_valid) begin
                if (!rx_valid) begin          // 无 FIFO：忙时丢弃新字节
                    rx_valid <= 1'b1;
                    rx_byte  <= uart_rx_data;
                end
            end
            // 读 RX 槽（访存段末沿清 RX_VALID）
            if (rx_clear) begin
                rx_valid <= 1'b0;
            end
        end
    end

    // ---- 收发例化 ----
    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_tx (
        .clk   (clk),
        .rst   (rst),
        .clk_en(bit_tick),
        .start (tx_fire),
        .data  (tx_buf),
        .busy  (tx_busy),
        .done  (tx_done),
        .tx    (tx_pin)
    );

    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_rx (
        .clk   (clk),
        .rst   (rst),
        .clk_en(bit_tick),
        .rx    (uart_rx_pin),
        .valid (uart_rx_valid),
        .data  (uart_rx_data)
    );

    assign uart_tx_pin = tx_pin;

endmodule
