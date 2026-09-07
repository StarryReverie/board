`timescale 1ns/1ps
//=============================================================================
// ex_mem.v — EX/MEM 段间寄存器
//   文档：doc/modules/ex_mem.md
//   口径：posedge clk：rst→全 0；否则锁存全部（分支冲刷不清本寄存器——
//         EX 段指令照常流入，冲刷由后级气泡承接）。
//=============================================================================

module ex_mem (
    input  wire        clk,
    input  wire        rst,
    // ---- 输入 ----
    input  wire [31:0] alu_result,
    input  wire [31:0] wdata,
    input  wire [4:0]  rd,
    input  wire        mem_read,
    input  wire        mem_write,
    input  wire        mem_to_reg,
    input  wire        reg_write,
    // ---- 寄存输出 ----
    output reg  [31:0] exmem_alu_result,
    output reg  [31:0] exmem_wdata,
    output reg  [4:0]  exmem_rd,
    output reg         exmem_mem_read,
    output reg         exmem_mem_write,
    output reg         exmem_mem_to_reg,
    output reg         exmem_reg_write
);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            exmem_alu_result <= 32'b0;
            exmem_wdata      <= 32'b0;
            exmem_rd         <= 5'b0;
            exmem_mem_read   <= 1'b0;
            exmem_mem_write  <= 1'b0;
            exmem_mem_to_reg <= 1'b0;
            exmem_reg_write  <= 1'b0;
        end else begin
            exmem_alu_result <= alu_result;
            exmem_wdata      <= wdata;
            exmem_rd         <= rd;
            exmem_mem_read   <= mem_read;
            exmem_mem_write  <= mem_write;
            exmem_mem_to_reg <= mem_to_reg;
            exmem_reg_write  <= reg_write;
        end
    end

endmodule
