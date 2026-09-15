`timescale 1ns/1ps
//=============================================================================
// exp1_reset_sync.v — 实验一独立上板：板上复位键 → core 复位语义
//   文档：pipeline/doc/board_runbook.md §2
//   口径：rst_n（板上按键，**低有效**，P15 带上拉）
//           → **异步置位、同步释放**（STAGES 级同步链）
//           → rst（**异步高有效**，对齐 pipeline_top 的 `posedge clk or posedge rst` 用法）
//   为什么需要：板上按键是异步信号，直接接 core 会在释放沿引入亚稳态/竞争；
//     且按键保持期间必须让 core 持续复位（不能只给一个脉冲），否则程序会中途开跑。
//   行为：
//     按下（rst_n=0）→ 立即 rst=1（异步，与 clk 无关）→ core 全程保持复位；
//     松开（rst_n=1）→ 经 STAGES 拍同步后 rst=0 → core 从 PC=0 开始执行。
//=============================================================================

module exp1_reset_sync #(
    parameter integer STAGES = 2          // 同步链级数（≥2 为常规做法）
) (
    input  wire clk,
    input  wire rst_n,    // 板上按键：低有效
    output wire rst       // core 复位：异步高有效
);

    reg [STAGES-1:0] sync_q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync_q <= {STAGES{1'b1}};     // 按键按下 → 立即全 1（异步置位）
        end else begin
            sync_q <= {sync_q[STAGES-2:0], 1'b0};   // 逐拍移入 0（同步释放）
        end
    end

    assign rst = sync_q[STAGES-1];

endmodule
