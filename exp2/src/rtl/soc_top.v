`timescale 1ns/1ps
//=============================================================================
// soc_top.v — 实验二整机装配（自定义计算机系统）
//   文档：exp2/doc/top_design.md / modules/soc_top.md
//   组成：reset_sync（rst_n→rst 异步高有效）
//         + pipeline_top #(.SOC_BUILD(1))（计组 core，MEM 段含 dbus_decode）
//         + uart_ctrl（全双工 MMIO 从机，MMIO 总线互联）
//   程序固化模型：imem 写口恒 0（.vh 上电自跑；换程序=重综合重烧）
//   引脚：clk(T5)/rst_n(P15)/uart_tx_pin(T4)/uart_rx_pin(N5) —— XDC 见 src/xdc
//   复位极性（RST_ACTIVE_LOW=1 默认低有效，手册未明示 P15 电平）：
//     上板首测若发现极性相反（按键按下=高有效），下板构建把参数置 0 即可
//     （仅顶层反相，reset_sync 与 core 语义不变；仿真默认路径不受影响）
//=============================================================================

module soc_top #(
    parameter [15:0] CLKS_PER_BIT = 16'd868,  // 115200 @ 100MHz
    parameter        RST_ACTIVE_LOW = 1       // 1=rst_n 低有效（默认）
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

    reset_sync u_reset (
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

    uart_ctrl #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_uart (
        .clk         (clk),
        .rst         (rst),
        .cs_mmio     (cs_mmio),
        .reg_off     (reg_off),
        .we          (mmio_we),
        .wdata       (mmio_wdata),
        .rdata       (mmio_rdata),
        .uart_tx_pin (uart_tx_pin),
        .uart_rx_pin (uart_rx_pin)
    );

endmodule
