`timescale 1ns/1ps
//=============================================================================
// id_ex.v — ID/EX 段间寄存器
//   文档：doc/modules/id_ex.md
//   口径：posedge clk：rst→全 0；else if(bubble)→全 0（灌气泡，load-use/
//         分支冲刷后丢弃 ID 指令）；else→锁存全部输入。无独立 en（气泡=清零）。
//   输出为寄存输出（idex_*），供 execute / hazard_unit。
//=============================================================================

module id_ex (
    input  wire        clk,
    input  wire        rst,          // 异步高有效
    input  wire        bubble,       // 1=本拍全 0（气泡）
    // ---- 输入 ----
    input  wire [31:0] pc,
    input  wire [31:0] rs1_data,
    input  wire [31:0] rs2_data,
    input  wire [31:0] imm,
    input  wire [4:0]  rd,
    input  wire [4:0]  rs1,
    input  wire [4:0]  rs2,
    input  wire [3:0]  alu_op,
    input  wire [1:0]  src_a,
    input  wire [1:0]  src_b,
    input  wire        mem_read,
    input  wire        mem_write,
    input  wire        mem_to_reg,
    input  wire        reg_write,
    input  wire [1:0]  jump,
    input  wire        bne,
    // ---- 寄存输出 ----
    output reg  [31:0] idex_pc,
    output reg  [31:0] idex_rs1_data,
    output reg  [31:0] idex_rs2_data,
    output reg  [31:0] idex_imm,
    output reg  [4:0]  idex_rd,
    output reg  [4:0]  idex_rs1,
    output reg  [4:0]  idex_rs2,
    output reg  [3:0]  idex_alu_op,
    output reg  [1:0]  idex_src_a,
    output reg  [1:0]  idex_src_b,
    output reg         idex_mem_read,
    output reg         idex_mem_write,
    output reg         idex_mem_to_reg,
    output reg         idex_reg_write,
    output reg  [1:0]  idex_jump,
    output reg         idex_bne
);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            idex_pc          <= 32'b0;
            idex_rs1_data    <= 32'b0;
            idex_rs2_data    <= 32'b0;
            idex_imm         <= 32'b0;
            idex_rd          <= 5'b0;
            idex_rs1         <= 5'b0;
            idex_rs2         <= 5'b0;
            idex_alu_op      <= 4'b0;
            idex_src_a       <= 2'b0;
            idex_src_b       <= 2'b0;
            idex_mem_read    <= 1'b0;
            idex_mem_write   <= 1'b0;
            idex_mem_to_reg  <= 1'b0;
            idex_reg_write   <= 1'b0;
            idex_jump        <= 2'b0;
            idex_bne         <= 1'b0;
        end else if (bubble) begin
            idex_pc          <= 32'b0;
            idex_rs1_data    <= 32'b0;
            idex_rs2_data    <= 32'b0;
            idex_imm         <= 32'b0;
            idex_rd          <= 5'b0;
            idex_rs1         <= 5'b0;
            idex_rs2         <= 5'b0;
            idex_alu_op      <= 4'b0;
            idex_src_a       <= 2'b0;
            idex_src_b       <= 2'b0;
            idex_mem_read    <= 1'b0;
            idex_mem_write   <= 1'b0;
            idex_mem_to_reg  <= 1'b0;
            idex_reg_write   <= 1'b0;
            idex_jump        <= 2'b0;
            idex_bne         <= 1'b0;
        end else begin
            idex_pc          <= pc;
            idex_rs1_data    <= rs1_data;
            idex_rs2_data    <= rs2_data;
            idex_imm         <= imm;
            idex_rd          <= rd;
            idex_rs1         <= rs1;
            idex_rs2         <= rs2;
            idex_alu_op      <= alu_op;
            idex_src_a       <= src_a;
            idex_src_b       <= src_b;
            idex_mem_read    <= mem_read;
            idex_mem_write   <= mem_write;
            idex_mem_to_reg  <= mem_to_reg;
            idex_reg_write   <= reg_write;
            idex_jump        <= jump;
            idex_bne         <= bne;
        end
    end

endmodule
