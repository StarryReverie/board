`timescale 1ns/1ps
//=============================================================================
// reset_sync.v — 复位同步器（板上按键 → core 语义 rst）
//   文档：soc/doc/modules/soc_top.md（reset_sync 小节）
//   口径：rst_n（低有效按键）→ **异步置位、同步释放**（STAGES 级同步链）
//         + 可选**释放去抖**（STABLE_CYCLES）→ rst 异步高有效
//
//   ---- 为什么要去抖（2026-09-16 新增）----
//   机械按键**松开瞬间会抖动**（典型 0.1–5 ms）。不去抖时，设计会在抖动窗口内被
//   反复置位/释放：正在发送的 UART 帧被**中途截断**（uart_tx 的 tx 是组合输出，
//   复位一到就立刻回空闲高），同时分频计数也被清零导致位节拍错位；接收端会把这
//   几帧读成乱码。实测现象就是"按 RESET 后 banner 前面多出一段乱码、后面正常"。
//
//   ---- 行为 ----
//   置位（按下 rst_n=0）：**立即生效**（异步，与 clk 无关），不受去抖影响；
//   释放（rst_n=1）：需**连续保持高 STABLE_CYCLES 拍**（任何一次拉低都立即清零
//     计数），随后再经 STAGES 拍同步释放。
//   STABLE_CYCLES = 0：完全不去抖 → 行为与旧版**逐拍一致**（既有单测口径不变）。
//   板级顶层按"20 ms × 时钟频率"取值，见 soc_top.v 的 RESET_STABLE_CYCLES。
//=============================================================================

module reset_sync #(
    parameter integer STAGES        = 2,   // 同步链级数（≥2 为常规做法）
    parameter integer STABLE_CYCLES = 0    // 释放去抖：rst_n 需连续稳定高的拍数；0 = 不去抖（同旧版）
) (
    input  wire clk,
    input  wire rst_n,       // 低有效
    output wire rst          // 异步高有效
);

    // ---- 释放去抖计数：任何拉低都异步清零；达门限后 stable_ok 恒 1 ----
    localparam integer CW = (STABLE_CYCLES > 1) ? $clog2(STABLE_CYCLES) : 1;
    reg  [CW-1:0] stable_cnt;
    wire          stable_ok = (STABLE_CYCLES <= 0) || (stable_cnt >= STABLE_CYCLES - 1);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)                    stable_cnt <= {CW{1'b0}};
        else if (!stable_ok)           stable_cnt <= stable_cnt + 1'b1;
    end

    // ---- 同步链：只在"稳定足够久"之后才逐拍移入 0，否则保持断言 ----
    reg [STAGES-1:0] sync_q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync_q <= {STAGES{1'b1}};                    // 按下 → 立即全 1（异步置位）
        end else begin
            sync_q <= {sync_q[STAGES-2:0], ~stable_ok};   // 稳定后才移入 0（同步释放）
        end
    end

    assign rst = sync_q[STAGES-1];

endmodule
