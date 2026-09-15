`timescale 1ns/1ps
//=============================================================================
// soc_top.v — 整个项目的顶层装配（自定义计算机系统，两课共建）
//   文档：soc/doc/top_design.md / soc/doc/modules/soc_top.md
//   组成：reset_sync（rst_n→rst 异步高有效）
//         + pipeline_top #(.SOC_BUILD(1))（计组 core，MEM 段含 dbus_decode）
//         + uart_ip_top（实验二 UART 控制器 IP 顶层，MMIO 总线互联）
//   mmio 总线适配：core 穿出 cs_mmio/reg_off[1:0] → IP 的 cs/addr[3:0]
//         （addr={reg_off,2'b00}，槽译码在 IP 内部自含）
//   程序固化模型：imem 写口恒 0（.vh 上电自跑；换程序=重综合重烧）
//   引脚：clk(T5)/rst_n(P15)/uart_tx_pin(T4)/uart_rx_pin(N5) —— XDC 见 soc/xdc
//   复位极性（RST_ACTIVE_LOW=1 默认低有效；2026-09-14 实验一在同一块板上实测确认 P15 低有效）：
//     若换板实测极性相反（按键按下=高有效），下板构建把参数置 0 即可
//     （仅顶层反相，reset_sync 与 core 语义不变）
//   复位释放去抖（RESET_STABLE_CYCLES，默认 20 ms @100 MHz）：
//     机械按键松开瞬间抖动会让设计在抖动窗口内反复置位/释放 → 正在发送的 UART 帧
//     被截断、位节拍错位 → 终端出现"乱码前缀"。这里要求 rst_n 连续稳定 20 ms 才释放
//     （按下始终立即生效）；实测与仿真用例见 tb_reset_sync / tb_soc_console（P5）。
//=============================================================================

module soc_top #(
    parameter [15:0] CLKS_PER_BIT = 16'd868,  // 115200 @ 100MHz
    parameter        RST_ACTIVE_LOW = 1,      // 1=rst_n 低有效（默认）
    parameter integer RESET_STABLE_CYCLES = 2_000_000
                                              // 复位**释放去抖**：rst_n 需连续稳定高的拍数
                                              //   = 20 ms @100 MHz（滤掉按键松开抖动导致的
                                              //   "按 RESET 后 banner 乱码前缀"，原理见
                                              //   reset_sync.v 头注）；仿真 TB 可覆盖为小值/0
) (
    input  wire clk,
    input  wire rst_n,           // 板上复位键（极性见 RST_ACTIVE_LOW）
    output wire uart_tx_pin,
    input  wire uart_rx_pin
);

    wire        rst;
    wire        rst_pin;
    wire        cs_mmio;
    wire [1:0]  reg_off;
    wire        mmio_we;
    wire [31:0] mmio_wdata;
    wire [31:0] mmio_rdata;

    assign rst_pin = RST_ACTIVE_LOW ? rst_n : ~rst_n;

    reset_sync #(
        .STAGES        (2),
        .STABLE_CYCLES (RESET_STABLE_CYCLES)
    ) u_reset (
        .clk   (clk),
        .rst_n (rst_pin),
        .rst   (rst)
    );

    pipeline_top #(.SOC_BUILD(1)) u_cpu (
        .clk        (clk),
        .rst        (rst),
        .imem_wen   (1'b0),
        .imem_waddr (32'b0),
        .imem_wdata (32'b0),
        .cs_mmio    (cs_mmio),
        .reg_off    (reg_off),
        .mmio_we    (mmio_we),
        .mmio_wdata (mmio_wdata),
        .mmio_rdata (mmio_rdata)
    );

    uart_ip_top #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_uart (
        .clk         (clk),
        .rst         (rst),
        .cs          (cs_mmio),
        .addr        ({reg_off, 2'b00}),
        .we          (mmio_we),
        .wdata       (mmio_wdata),
        .rdata       (mmio_rdata),
        .uart_tx_pin (uart_tx_pin),
        .uart_rx_pin (uart_rx_pin)
    );

endmodule
