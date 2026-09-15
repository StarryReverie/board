`timescale 1ns/1ps
//=============================================================================
// exp1_reset_sync.v — 实验一独立上板：板上复位键 → core 复位语义
//   文档：pipeline/doc/board_runbook.md §2
//   口径：rst_n（板上按键，**低有效**，P15 带上拉）
//           → **异步置位、同步释放**（STAGES 级同步链）
//           + 可选**释放去抖**（STABLE_CYCLES，2026-09-16 新增）
//           → rst（**异步高有效**，对齐 pipeline_top 的 `posedge clk or posedge rst` 用法）
//   为什么需要同步：板上按键是异步信号，直接接 core 会在释放沿引入亚稳态/竞争；
//     且按键保持期间必须让 core 持续复位（不能只给一个脉冲），否则程序会中途开跑。
//   为什么需要去抖：机械按键**松开瞬间抖动**（0.1–5 ms），不去抖会在抖动窗口内
//     反复置位/释放——正在发的帧被截断、分频节拍错位，接收端读到乱码前缀
//     （现象："按 RESET 后数码管/终端前几字节乱"）。本模块用"连续稳定
//     STABLE_CYCLES 拍才释放"把抖动滤掉；**按下始终立即生效**。
//   行为：
//     按下（rst_n=0）→ 立即 rst=1（异步，与 clk 无关）→ core 全程保持复位；
//     松开（rst_n=1）→ 连续稳定 STABLE_CYCLES 拍后，再经 STAGES 拍同步 → rst=0。
//   STABLE_CYCLES = 0：不去抖，行为与旧版逐拍一致（仿真/单测可用）。
//=============================================================================

module exp1_reset_sync #(
    parameter integer STAGES        = 2,   // 同步链级数（≥2 为常规做法）
    parameter integer STABLE_CYCLES = 0    // 释放去抖：rst_n 需连续稳定高的拍数；0 = 不去抖
) (
    input  wire clk,
    input  wire rst_n,    // 板上按键：低有效
    output wire rst       // core 复位：异步高有效
);

    // ---- 释放去抖计数（任何拉低立即异步清零）----
    localparam integer CW = (STABLE_CYCLES > 1) ? $clog2(STABLE_CYCLES) : 1;
    reg  [CW-1:0] stable_cnt;
    wire          stable_ok = (STABLE_CYCLES <= 0) || (stable_cnt >= STABLE_CYCLES - 1);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)          stable_cnt <= {CW{1'b0}};
        else if (!stable_ok) stable_cnt <= stable_cnt + 1'b1;
    end

    // ---- 同步链：稳定足够久才移入 0 ----
    reg [STAGES-1:0] sync_q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync_q <= {STAGES{1'b1}};                    // 按键按下 → 立即全 1（异步置位）
        end else begin
            sync_q <= {sync_q[STAGES-2:0], ~stable_ok};   // 稳定后逐拍移入 0（同步释放）
        end
    end

    assign rst = sync_q[STAGES-1];

endmodule
