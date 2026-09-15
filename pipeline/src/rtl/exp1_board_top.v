`timescale 1ns/1ps
//=============================================================================
// exp1_board_top.v — 实验一独立上板顶层（不接 UART，不依赖实验二任何模块）
//   文档：pipeline/doc/board_runbook.md（综合/烧录/验收/拍摄/故障定位）
//   结构与验收口径：pipeline/doc/board_runbook.md §2/§5
//     exp1_board_top
//      ├─ exp1_reset_sync      板上按键(低有效) → core 复位(异步高有效/同步释放)
//      ├─ pipeline_top #(.SOC_BUILD(0))   RV32I 五级流水线 core
//      │    程序经 imem 的 `include "imem_init.vh"` 综合期固化（上电自跑）
//      ├─ 事件与结果监视器      PC/停顿/重定向/写存/写回 → 锁存板级状态
//      └─ LED + 数码管显示      8 LED 状态灯 + 8 位数码管显示签名
//   验收判据：dmem[0] 被写入 0x0000000F 且 CPU 进入 HALT 自循环 → LED6(PASS)
//   时钟：100 MHz（T5）；复位：P15 低有效；引脚表见 pipeline/xdc/board_exp1.xdc
//=============================================================================
`include "defines/const_define.v"

module exp1_board_top #(
    // ---- 板级时序参数（默认按 100 MHz 标定）----
    parameter integer CLK_HZ      = 100_000_000,  // 板上晶振频率
    parameter integer HEART_MS    = 500,          // LED0 心跳半周期（ms）
    parameter integer TIMEOUT_MS  = 1500,         // 未出现 PASS 的超时窗口（ms）
    parameter integer SEG_EN      = 1,            // 1=启用数码管扫描；0=仅 LED
    parameter integer SCAN_DIV_BITS = 14          // 每位扫描分频位宽（2^N 拍/位）；仿真可调小
) (
    input  wire        clk,       // T5：100 MHz 晶振
    input  wire        rst_n,     // P15：FPGA_RESET 按键，低有效
    output wire [7:0]  led,       // K2 J2 J3 H4 J4 G3 G4 F6（高电平点亮）
    output wire [7:0]  seg0,      // DN0 段选 {DP,G,F,E,D,C,B,A}（高有效）
    output wire [7:0]  seg1,      // DN1 段选 {DP,G,F,E,D,C,B,A}（高有效）
    output wire [7:0]  an         // 位选 LED_BIT1..8（高有效，one-hot）
);

    // 拍数标定（综合期常量展开，不产生运行期除法）
    localparam [31:0] HEART_END  = (CLK_HZ / 1000) * HEART_MS;      // 心跳半周期拍数
    localparam [31:0] HEART_LAST = HEART_END - 32'd1;
    localparam [31:0] TO_END     = (CLK_HZ / 1000) * TIMEOUT_MS;    // 超时拍数
    localparam [31:0] TO_LAST    = TO_END - 32'd1;

    // ================= 复位 =================
    wire rst;
    exp1_reset_sync #(.STAGES(2)) u_rst_sync (
        .clk   (clk),
        .rst_n (rst_n),
        .rst   (rst)
    );

    // ================= CPU core（实验一模式：mmio 恒 0、imem 写口恒 0）=================
    wire [31:0] dbg_pc, dbg_store_addr, dbg_store_data;
    wire        dbg_stall, dbg_br_taken, dbg_halt, dbg_store_valid;

    pipeline_top #(.SOC_BUILD(0)) u_cpu (
        .clk        (clk),
        .rst        (rst),
        .imem_wen   (1'b0),
        .imem_waddr (32'b0),
        .imem_wdata (32'b0),
        .cs_mmio    (),
        .reg_off    (),
        .mmio_we    (),
        .mmio_wdata (),
        .mmio_rdata (32'b0),
        .dbg_pc          (dbg_pc),
        .dbg_stall       (dbg_stall),
        .dbg_br_taken    (dbg_br_taken),
        .dbg_halt        (dbg_halt),
        .dbg_store_valid (dbg_store_valid),
        .dbg_store_addr  (dbg_store_addr),
        .dbg_store_data  (dbg_store_data),
        // 写回观测口留给 ILA/调试（本顶层 LED 语义用不到 → 空接）
        .dbg_wb_we       (),
        .dbg_wb_rd       (),
        .dbg_wb_data     ()
    );

    // ================= LED0 心跳（自由运行：上电即翻，用于证明时钟/供电/烧录正常）=================
    reg [31:0] heart_cnt;
    reg        heart;

    initial begin
        heart_cnt = 32'd0;
        heart     = 1'b0;
    end

    always @(posedge clk) begin
        if (heart_cnt >= HEART_LAST) begin
            heart_cnt <= 32'd0;
            heart     <= ~heart;
        end else begin
            heart_cnt <= heart_cnt + 32'd1;
        end
    end

    // ================= 观测输入打拍（时序收敛用）=================
    //   为什么打拍：直接把 dbg_* 接进监视器的宽比较器（32 位 !=0、32 位地址比较）会形成
    //   "核心组合锥 → 监视器比较 → 触发器 CE" 的长路径（post-synthesis 估计 WNS −1.44 ns、
    //   238 个端点违例，最差路径 exmem_rd → br_seen/CE）。
    //   先寄存一拍后，监视器的全部比较/锁存都只依赖寄存器输出，板级逻辑退化为 1~2 级 LUT。
    //   代价：板级语义整体滞后 1 拍——对 0.5 s 心跳 / 1.5 s 超时级别完全无影响。
    reg [31:0] q_pc, q_store_addr, q_store_data;
    reg        q_stall, q_br_taken, q_halt, q_store_valid;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            q_pc          <= 32'b0;
            q_store_addr  <= 32'b0;
            q_store_data  <= 32'b0;
            q_stall       <= 1'b0;
            q_br_taken    <= 1'b0;
            q_halt        <= 1'b0;
            q_store_valid <= 1'b0;
        end else begin
            q_pc          <= dbg_pc;
            q_store_addr  <= dbg_store_addr;
            q_store_data  <= dbg_store_data;
            q_stall       <= dbg_stall;
            q_br_taken    <= dbg_br_taken;
            q_halt        <= dbg_halt;
            q_store_valid <= dbg_store_valid;
        end
    end

    // ================= 事件与结果监视器 =================
    //   全部以 rst 清零 ⇒ 每次按键复位后状态与计数从头开始，结果可重复。
    //   输入一律取上一拍的 q_*（见上），避免长组合路径。
    localparam integer TO_W = 32;                    // 超时计数器位宽

    reg        reset_done;      // LED1：复位已释放
    reg        cpu_started;     // LED2：PC 出现过非 0
    reg        stall_seen;      // LED3：见过 load-use 冻结
    reg        br_seen;         // LED4：见过分支/跳转重定向
    reg        store_seen;      // LED5：见过 dmem 写入
    reg        sig_written;     // 验收地址（dmem[0]）被写过
    reg [31:0] sig_data;        // 写入 dmem[0] 的数据（验收签名/显示值）
    reg        halt_seen;       // 已进入 HALT 自循环（dbg_halt 命中）
    reg        pass_r;          // LED6：PASS
    reg        timeout_r;       // LED7：FAIL/超时

    reg [TO_W-1:0] to_cnt;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            reset_done  <= 1'b0;
            cpu_started <= 1'b0;
            stall_seen  <= 1'b0;
            br_seen     <= 1'b0;
            store_seen  <= 1'b0;
            sig_written <= 1'b0;
            sig_data    <= 32'b0;
            halt_seen   <= 1'b0;
            pass_r      <= 1'b0;
            timeout_r   <= 1'b0;
            to_cnt      <= {TO_W{1'b0}};
        end else begin
            reset_done <= 1'b1;                          // 本拍起 core 已在跑

            if (q_pc != 32'h0) cpu_started <= 1'b1;

            if (q_stall)       stall_seen <= 1'b1;
            if (q_br_taken)    br_seen    <= 1'b1;
            if (q_store_valid) store_seen <= 1'b1;

            // HALT：分支 taken 且偏移为 0（"跳到自己"，isa §4 停机约定）。
            //   不能用"PC 连续不变"——本流水线未采取预测 + taken 冲刷 2 条，
            //   自循环时 PC 呈周期 3 的 {halt, halt+4, halt+8} 循环，永远在变。
            if (q_halt) halt_seen <= 1'b1;

            // 验收签名：q_* 是上一拍的 dmem 写口快照，其值与被写进 dmem 的值相同
            //   （dmem 在写使能那一沿写入，这里在下一沿锁存同一组信号）
            if (q_store_valid && (q_store_addr == 32'h0)) begin
                sig_data    <= q_store_data;
                sig_written <= 1'b1;
            end

            // PASS：签名正确 且 已进入 HALT
            if (sig_written && (sig_data == 32'h0000_000F) && halt_seen)
                pass_r <= 1'b1;

            // 超时：PASS 未达而窗口耗尽
            if (!pass_r) begin
                if (to_cnt >= TO_LAST) timeout_r <= 1'b1;
                else                   to_cnt    <= to_cnt + 32'd1;
            end
        end
    end

    // ---- LED 语义（archive 方案 §5）----
    assign led[0] = heart;                     // 时钟心跳
    assign led[1] = reset_done;                // 复位释放完成
    assign led[2] = cpu_started;               // CPU 已开始执行
    assign led[3] = stall_seen;                // 检测到 load-use 停顿
    assign led[4] = br_seen;                   // 检测到分支重定向
    assign led[5] = store_seen;                // 检测到 dmem 写入
    assign led[6] = pass_r;                    // PASS
    assign led[7] = timeout_r & ~pass_r;       // FAIL / 超时

    // ================= 数码管显示（共阴极，段选/位选均高有效）=================
    //   显示内容 = 锁存到的验收签名值（未写前为 0）：
    //     PASS 后读作 0000000F（DN0 组低四位即 000F）
    //   扫描：8 位 one-hot，逐位 2^SCAN_DIV_BITS 拍（默认 2^14 ≈164 µs@100MHz），
    //         整帧 ≈1.31 ms（≈763 Hz，无可见闪烁）
    wire [31:0] disp = sig_written ? sig_data : 32'h0000_0000;

    localparam integer SCAN_W = SCAN_DIV_BITS + 3;   // 3 位 = 8 个位选

    reg [SCAN_W-1:0] scan_cnt;

    always @(posedge clk or posedge rst) begin
        if (rst) scan_cnt <= {SCAN_W{1'b0}};
        else     scan_cnt <= scan_cnt + 1'b1;
    end

    wire [2:0] digit = scan_cnt[SCAN_W-1 : SCAN_DIV_BITS];   // 0..7

    reg [3:0] nib;
    always @(*) begin
        case (digit)
            3'd0:    nib = disp[3:0];
            3'd1:    nib = disp[7:4];
            3'd2:    nib = disp[11:8];
            3'd3:    nib = disp[15:12];
            3'd4:    nib = disp[19:16];
            3'd5:    nib = disp[23:20];
            3'd6:    nib = disp[27:24];
            default: nib = disp[31:28];
        endcase
    end

    // 七段译码：返回值位序 {G,F,E,D,C,B,A}（共阴极高有效）
    function [6:0] hex7;
        input [3:0] v;
        begin
            case (v)
                4'h0:    hex7 = 7'b0111111;
                4'h1:    hex7 = 7'b0000110;
                4'h2:    hex7 = 7'b1011011;
                4'h3:    hex7 = 7'b1001111;
                4'h4:    hex7 = 7'b1100110;
                4'h5:    hex7 = 7'b1101101;
                4'h6:    hex7 = 7'b1111101;
                4'h7:    hex7 = 7'b0000111;
                4'h8:    hex7 = 7'b1111111;
                4'h9:    hex7 = 7'b1101111;
                4'hA:    hex7 = 7'b1110111;
                4'hB:    hex7 = 7'b1111100;
                4'hC:    hex7 = 7'b0111001;
                4'hD:    hex7 = 7'b1011110;
                4'hE:    hex7 = 7'b1111001;
                default: hex7 = 7'b1110001;   // F
            endcase
        end
    endfunction

    // 段选总线：DN0 显示 disp[15:0] 的 4 位十六进制，DN1 显示 disp[31:16]
    //   位序 {DP,G,F,E,D,C,B,A}，DP 不用（恒 0）
    wire [7:0] seg_act = {1'b0, hex7(nib)};

    // 位选：one-hot，digit=0 → an[0]
    reg [7:0] an_onehot;
    always @(*) begin
        an_onehot = 8'b0000_0001 << digit;
    end
    assign seg0 = SEG_EN ? seg_act : 8'b0;
    assign seg1 = SEG_EN ? seg_act : 8'b0;
    assign an   = SEG_EN ? an_onehot : 8'b0;

endmodule
