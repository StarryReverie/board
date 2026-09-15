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
//   STABLE_CYCLES = 0：完全不去抖 → 释放时序与旧版**逐拍一致**（既有单测口径不变）。
//   板级顶层按"20 ms × 时钟频率"取值，见 soc_top.v 的 RESET_STABLE_CYCLES。
//
//   ---- 结构：整个"释放"路径都在同步域内（2026-09-16 review 加固）----
//   meta_q：**唯一**直接挂在异步 rst_n 上的触发器（异步置位/释放）。它的释放沿可能
//           落在时钟沿附近而亚稳，但它的输出只被同步逻辑采样，亚稳在第 2 级被"消费"。
//   去抖计数与释放链：**纯同步**（复位脚不带异步 rst_n），不再有"异步释放沿直入
//           FF 复位脚"导致的 recovery/removal 风险——否则计数可能在释放沿附近被
//           采成非零值，提前满足 stable_ok、吃掉去抖时长。
//   输出 rst：异步置位（`!rst_n`，含亚周期毛刺）+ 同步释放（release_ok）。
//=============================================================================

module reset_sync #(
    parameter integer STAGES        = 2,   // 同步链级数（≥2 为常规做法）
    parameter integer STABLE_CYCLES = 0    // 释放去抖：rst_n 需连续稳定高的拍数；0 = 不去抖（同旧版）
) (
    input  wire clk,
    input  wire rst_n,       // 低有效
    output wire rst          // 异步高有效
);

    // ---- 第 1 级：唯一直接接触异步 rst_n 的触发器（异步置位 / 释放）----
    reg meta_q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) meta_q <= 1'b0;      // 按下 → 立即进入"未稳定"
        else        meta_q <= 1'b1;      // 释放沿可能亚稳，但只被下面的同步逻辑采样
    end

    // ---- 释放去抖计数：纯同步清零/递增；达门限后 stable_ok 恒 1 ----
    localparam integer CW = (STABLE_CYCLES > 1) ? $clog2(STABLE_CYCLES) : 1;
    reg  [CW-1:0] stable_cnt;
    wire          stable_ok = (STABLE_CYCLES <= 0) || (stable_cnt >= STABLE_CYCLES - 1);

    always @(posedge clk) begin
        if (!meta_q)         stable_cnt <= {CW{1'b0}};
        else if (!stable_ok) stable_cnt <= stable_cnt + 1'b1;
    end

    // ---- 释放同步链：meta_q 之后再 STAGES-1 级（纯同步，无异步复位脚）----
    wire release_ready = stable_ok;     // 去抖已满足 → 允许开始"移出复位"
    wire release_ok;

    generate
        if (STAGES > 2) begin : g_release_chain
            reg [STAGES-2:0] rel_q;

            always @(posedge clk) begin
                if (!meta_q) rel_q <= {(STAGES-1){1'b0}};
                else         rel_q <= {rel_q[STAGES-3:0], release_ready};
            end

            assign release_ok = rel_q[STAGES-2];
        end else begin : g_release_single
            reg rel_q;

            always @(posedge clk) begin
                if (!meta_q) rel_q <= 1'b0;
                else         rel_q <= release_ready;
            end

            assign release_ok = rel_q;
        end
    endgenerate

    // ---- 输出：异步置位（按下 / 抖动期立即断言）+ 同步释放 ----
    assign rst = ~(rst_n & meta_q & release_ok);

endmodule
