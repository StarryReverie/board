`timescale 1ns/1ps
//=============================================================================
// mem_wb.v — MEM/WB 段间寄存器
//   文档：doc/modules/mem_wb.md
//   口径：posedge clk：rst→全 0；否则锁存全部（lw 数据经本寄存器进 WB 与前递）。
//=============================================================================

module mem_wb (
    input  wire        clk,
    input  wire        rst,
    // ---- 输入 ----
    input  wire [31:0] rdata,        // dmem 读回（lw）
    input  wire [31:0] alu_result,
    input  wire [4:0]  rd,
    input  wire        mem_to_reg,
    input  wire        reg_write,
    // ---- 寄存输出 ----
    output reg  [31:0] memwb_rdata,
    output reg  [31:0] memwb_alu_result,
    output reg  [4:0]  memwb_rd,
    output reg         memwb_mem_to_reg,
    output reg         memwb_reg_write
);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            memwb_rdata      <= 32'b0;
            memwb_alu_result <= 32'b0;
            memwb_rd         <= 5'b0;
            memwb_mem_to_reg <= 1'b0;
            memwb_reg_write  <= 1'b0;
        end else begin
            memwb_rdata      <= rdata;
            memwb_alu_result <= alu_result;
            memwb_rd         <= rd;
            memwb_mem_to_reg <= mem_to_reg;
            memwb_reg_write  <= reg_write;
        end
    end

endmodule
