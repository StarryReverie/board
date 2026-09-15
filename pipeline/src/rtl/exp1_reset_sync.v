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
//   STABLE_CYCLES = 0：不去抖，释放时序与旧版逐拍一致（仿真/单测可用）。
//   结构（2026-09-16 review 加固，与 soc/rtl/reset_sync.v 保持同构）：
//     异步级只有 meta_q 一个寄存器；去抖计数与释放链**纯同步**，
//     不再让异步释放沿直入计数器的复位脚（recovery/removal 风险 → 可能提前释放）。
//=============================================================================

module exp1_reset_sync #(
    parameter integer STAGES        = 2,   // 同步链级数（≥2 为常规做法）
    parameter integer STABLE_CYCLES = 0    // 释放去抖：rst_n 需连续稳定高的拍数；0 = 不去抖
) (
    input  wire clk,
    input  wire rst_n,    // 板上按键：低有效
    output wire rst       // core 复位：异步高有效
);

    // ---- 第 1 级：唯一直接接触异步 rst_n 的触发器（异步置位 / 释放）----
    reg meta_q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) meta_q <= 1'b0;      // 按下 → 立即进入"未稳定"
        else        meta_q <= 1'b1;      // 释放沿可能亚稳，但只被下面的同步逻辑采样
    end

    // ---- 释放去抖计数：纯同步清零/递增 ----
    localparam integer CW = (STABLE_CYCLES > 1) ? $clog2(STABLE_CYCLES) : 1;
    reg  [CW-1:0] stable_cnt;
    wire          stable_ok = (STABLE_CYCLES <= 0) || (stable_cnt >= STABLE_CYCLES - 1);

    always @(posedge clk) begin
        if (!meta_q)         stable_cnt <= {CW{1'b0}};
        else if (!stable_ok) stable_cnt <= stable_cnt + 1'b1;
    end

    // ---- 释放同步链：meta_q 之后再 STAGES-1 级（纯同步，无异步复位脚）----
    wire release_ready = stable_ok;
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

    // ---- 输出：异步置位 + 同步释放 ----
    assign rst = ~(rst_n & meta_q & release_ok);

endmodule
