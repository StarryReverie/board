`timescale 1ns/1ps
//=============================================================================
// reset_sync.v — 复位同步器（板上按键 → core 语义 rst）
//   文档：exp2/doc/modules/soc_top.md（reset_sync 小节）
//   口径：rst_n（低有效按键）→ **异步置位、同步释放**（2 级同步）→
//         rst 异步高有效（对齐计组 core：posedge clk or posedge rst 用法）
//=============================================================================

module reset_sync (
    input  wire clk,
    input  wire rst_n,       // 低有效
    output wire rst          // 异步高有效
);

    reg q1, q2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            q1 <= 1'b1;
            q2 <= 1'b1;
        end else begin
            q1 <= 1'b0;
            q2 <= q1;
        end
    end

    assign rst = q2;

endmodule
