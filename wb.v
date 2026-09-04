`timescale 1ns/1ps
//=============================================================================
// wb.v — 回写选路（WB 段纯组合）
//   文档：doc/modules/wb.md
//   口径：wb_data = memwb_mem_to_reg ? memwb_rdata : memwb_alu_result；
//         同一 wb_data 同时供 regfile 写口与 MEM/WB 前递源（wb_fwd_val）。
//=============================================================================

module wb (
    input  wire [4:0]  memwb_rd,
    input  wire [31:0] memwb_alu_result,
    input  wire [31:0] memwb_rdata,
    input  wire        memwb_mem_to_reg,
    input  wire        memwb_reg_write,
    output wire [4:0]  wb_rd,
    output wire [31:0] wb_data,
    output wire        wb_we
);

    assign wb_rd  = memwb_rd;
    assign wb_we  = memwb_reg_write;
    assign wb_data = memwb_mem_to_reg ? memwb_rdata : memwb_alu_result;

endmodule
