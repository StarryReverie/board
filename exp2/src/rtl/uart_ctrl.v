`timescale 1ns/1ps
//=============================================================================
// uart_ctrl.v — UART MMIO 从机封装（TX/STAT/RX 字槽）
//   文档：exp2/doc/modules/uart_ctrl.md；契约：exp2/doc/interface.md §3
//   口径：
//     - 槽（reg_off，cs_mmio 命中时有效）：
//        00 TX : sw 写低 8 位=待发字节；空闲接受、忙时丢弃（软件轮询保证）；
//               读=0
//        01 STAT: 读 bit0=TX_BUSY、bit1=RX_VALID；写无操作
//        10 RX : 读低 8 位=收到字节并清 RX_VALID（posedge 清，即访存段末沿）；
//               写无操作
//        11/未命中: 读 0、写无操作
//     - 无 FIFO：RX_VALID=1 期间到达的新字节丢弃；
//     - 内部：clk_en 分频（每 CLKS_PER_BIT 个 clk 一脉冲，TX 用）+
//       uart_tx/uart_rx；rx 输入打两拍（在 uart_rx 内）；
//     - TX 触发：写接受（完全空闲：无挂起且非移位忙）→置 pend，待发送
//       空闲且遇 clk_en 脉冲拍启动（start 需在脉冲沿保持，CPU 单拍写请求
//       不可直连）；STAT.TX_BUSY（bit0）= 挂起或移位中——写接受沿即置 1，
//       帧发完清 0（软件据此轮询不会落入"挂起窗口"丢字）。
//=============================================================================

module uart_ctrl #(
    parameter [15:0] CLKS_PER_BIT = 16'd868
) (
    input  wire        clk,
    input  wire        rst,          // 异步高有效
    // ---- MMIO 从机口 ----
    input  wire        cs_mmio,
    input  wire [1:0]  reg_off,      // 00=TX 01=STAT 10=RX 11=保留
    input  wire        we,
    input  wire [31:0] wdata,
    output wire [31:0] rdata,        // 组合读
    // ---- 串行侧 ----
    output wire        uart_tx_pin,
    input  wire        uart_rx_pin
);

    // ---- clk_en 分频（每 bit 时间 1 脉冲）----
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
    wire       tx_accept = cs_mmio && we && (reg_off == 2'b00) &&
                           !tx_busy && !tx_pend;
    wire       tx_fire   = tx_pend && !tx_busy;     // 组合 start（脉冲沿拍采样）

    // ---- RX 寄存器 ----
    reg        rx_valid;                    // RX_VALID
    reg  [7:0] rx_byte;
    wire       rx_clear = cs_mmio && !we && (reg_off == 2'b10) && rx_valid;

    // ---- 组合读（STAT bit0=TX_BUSY：挂起待发或移位中）----
    wire [31:0] rdata_tx   = 32'd0;
    wire [31:0] rdata_stat = {30'b0, rx_valid, tx_busy | tx_pend};
    wire [31:0] rdata_rx   = {24'b0, rx_byte};
    assign rdata = cs_mmio ?
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
