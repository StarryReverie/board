`timescale 1ns/1ps
//=============================================================================
// pc_reg.v — 程序计数器（IF 段）
//   文档：doc/modules/pc_reg.md；参考：ref/CPU/pc_reg.v
//   口径：pc_next = pc_src ? pc_branch : pc+4；
//         posedge clk：rst→pc<=0；else if(en) pc<=pc_next（en=0 暂停保持）。
//   复位：异步高有效（posedge rst 写法，对齐参考工程）。
//=============================================================================

module pc_reg (
    input  wire        clk,
    input  wire        rst,
    input  wire        en,
    input  wire        pc_src,
    input  wire [31:0] pc_branch,
    output reg  [31:0] pc
);

    wire [31:0] pc_pred;
    wire [31:0] pc_next;

    assign pc_pred = pc + 32'd4;
    assign pc_next = pc_src ? pc_branch : pc_pred;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            pc <= 32'b0;
        end else if (en) begin
            pc <= pc_next;
        end
        // en=0：保持（load-use 冻结）
    end

endmodule
