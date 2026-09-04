`timescale 1ns/1ps
//=============================================================================
// pipeline_top.v — 顶层装配（实验一 CPU core：RV32I 5 级流水线）
//   文档：doc/modules/pipeline_top.md（端口/互联权威）；doc/top_design.md §1–§8
//   实验一 build：
//     - dbus_decode 不例化：dmem.rdata 直连 mem_wb.rdata（H1–H5 口径不变）；
//     - mmio 总线（cs_mmio/reg_off/mmio_we/mmio_wdata/mmio_rdata）恒 0/悬空，
//       T40（实验二）再启用（先改文档后改代码）；
//     - imem loader 写口：本实验恒 0（固化单程序模型下预留）。
//   冲突策略：前递(EX/MEM、MEM/WB→EX) + load-use 冻结(1 气泡) +
//              分支 EX taken 冲刷 2 条（IF/ID 置 NOP、ID/EX 气泡）。
//=============================================================================
`include "defines/const_define.v"

module pipeline_top (
    input  wire        clk,
    input  wire        rst,            // 异步高有效
    // ---- imem loader 写口（预留，本实验恒 0）----
    input  wire        imem_wen,
    input  wire [31:0] imem_waddr,
    input  wire [31:0] imem_wdata,
    // ---- mmio 总线（实验二启用；实验一恒 0/悬空）----
    output wire        cs_mmio,
    output wire [1:0]  reg_off,
    output wire        mmio_we,
    output wire [31:0] mmio_wdata,
    input  wire [31:0] mmio_rdata
);

    // ================= IF =================
    wire [31:0] pc;
    wire [31:0] inst;
    wire [31:0] ifid_pc, ifid_inst;

    // ================= ID =================
    wire [4:0]  rd, rs1, rs2;
    wire [31:0] imm;
    wire [31:0] rdata1, rdata2;
    wire [3:0]  alu_op;
    wire [1:0]  src_a, src_b;
    wire        mem_read, mem_write, mem_to_reg, reg_write;
    wire [1:0]  jump;
    wire        bne;

    // ================= EX =================
    wire [31:0] idex_pc;
    wire [31:0] idex_rs1_data, idex_rs2_data, idex_imm;
    wire [4:0]  idex_rd, idex_rs1, idex_rs2;
    wire [3:0]  idex_alu_op;
    wire [1:0]  idex_src_a, idex_src_b;
    wire        idex_mem_read, idex_mem_write, idex_mem_to_reg, idex_reg_write;
    wire [1:0]  idex_jump;
    wire        idex_bne;
    wire [31:0] alu_out, ex_wdata;
    wire        ex_zero;                // zero 观测（execute）
    wire        of;                     // of 观测口（层次引用）
    wire        br_taken;
    wire [31:0] br_target;

    // ================= MEM =================
    wire [31:0] exmem_alu_result, exmem_wdata;
    wire [4:0]  exmem_rd;
    wire        exmem_mem_read, exmem_mem_write, exmem_mem_to_reg, exmem_reg_write;
    wire [31:0] dmem_rdata;

    // ================= WB =================
    wire [31:0] memwb_rdata, memwb_alu_result;
    wire [4:0]  memwb_rd;
    wire        memwb_mem_to_reg, memwb_reg_write;
    wire [4:0]  wb_rd;
    wire [31:0] wb_data;
    wire        wb_we;

    // ================= hazard =================
    wire        stall;
    wire [1:0]  fwd_a_sel, fwd_b_sel;

    // ---- 实验一：mmio 总线恒 0（实验二由 dbus_decode 驱动）----
    assign cs_mmio   = 1'b0;
    assign reg_off   = 2'b00;
    assign mmio_we   = 1'b0;
    assign mmio_wdata = 32'b0;

    // ================= 例化 =================
    pc_reg u_pc_reg (
        .clk        (clk),
        .rst        (rst),
        .en         (~stall),
        .pc_src     (br_taken),
        .pc_branch  (br_target),
        .pc         (pc)
    );

    imem u_imem (
        .clk        (clk),
        .addr       (pc),
        .inst       (inst),
        .imem_wen   (imem_wen),
        .imem_waddr (imem_waddr),
        .imem_wdata (imem_wdata)
    );

    if_id u_if_id (
        .clk     (clk),
        .rst     (rst),
        .en      (~stall),
        .flush   (br_taken),
        .inst_in (inst),
        .pc_in   (pc),
        .inst    (ifid_inst),
        .pc      (ifid_pc)
    );

    decode u_decode (
        .inst       (ifid_inst),
        .rd         (rd),
        .rs1        (rs1),
        .rs2        (rs2),
        .imm        (imm),
        .alu_op     (alu_op),
        .src_a      (src_a),
        .src_b      (src_b),
        .mem_read   (mem_read),
        .mem_write  (mem_write),
        .mem_to_reg (mem_to_reg),
        .reg_write  (reg_write),
        .jump       (jump),
        .bne        (bne)
    );

    regfile u_regfile (
        .clk    (clk),
        .rst    (rst),
        .raddr1 (rs1),
        .raddr2 (rs2),
        .waddr  (wb_rd),
        .wdata  (wb_data),
        .we     (wb_we),
        .rdata1 (rdata1),
        .rdata2 (rdata2)
    );

    id_ex u_id_ex (
        .clk            (clk),
        .rst            (rst),
        .bubble         (stall | br_taken),
        .pc             (ifid_pc),
        .rs1_data       (rdata1),
        .rs2_data       (rdata2),
        .imm            (imm),
        .rd             (rd),
        .rs1            (rs1),
        .rs2            (rs2),
        .alu_op         (alu_op),
        .src_a          (src_a),
        .src_b          (src_b),
        .mem_read       (mem_read),
        .mem_write      (mem_write),
        .mem_to_reg     (mem_to_reg),
        .reg_write      (reg_write),
        .jump           (jump),
        .bne            (bne),
        .idex_pc        (idex_pc),
        .idex_rs1_data  (idex_rs1_data),
        .idex_rs2_data  (idex_rs2_data),
        .idex_imm       (idex_imm),
        .idex_rd        (idex_rd),
        .idex_rs1       (idex_rs1),
        .idex_rs2       (idex_rs2),
        .idex_alu_op    (idex_alu_op),
        .idex_src_a     (idex_src_a),
        .idex_src_b     (idex_src_b),
        .idex_mem_read  (idex_mem_read),
        .idex_mem_write (idex_mem_write),
        .idex_mem_to_reg(idex_mem_to_reg),
        .idex_reg_write (idex_reg_write),
        .idex_jump      (idex_jump),
        .idex_bne       (idex_bne)
    );

    execute u_execute (
        .rs1_data   (idex_rs1_data),
        .rs2_data   (idex_rs2_data),
        .ex_fwd_val (exmem_alu_result),
        .wb_fwd_val (wb_data),
        .fwd_a_sel  (fwd_a_sel),
        .fwd_b_sel  (fwd_b_sel),
        .idex_pc    (idex_pc),
        .imm        (idex_imm),
        .alu_op     (idex_alu_op),
        .src_a      (idex_src_a),
        .src_b      (idex_src_b),
        .jump       (idex_jump),
        .bne        (idex_bne),
        .alu_out    (alu_out),
        .wdata      (ex_wdata),
        .zero       (ex_zero),
        .of         (of),
        .br_taken   (br_taken),
        .br_target  (br_target)
    );

    ex_mem u_ex_mem (
        .clk             (clk),
        .rst             (rst),
        .alu_result      (alu_out),
        .wdata           (ex_wdata),
        .rd              (idex_rd),
        .mem_read        (idex_mem_read),
        .mem_write       (idex_mem_write),
        .mem_to_reg      (idex_mem_to_reg),
        .reg_write       (idex_reg_write),
        .exmem_alu_result (exmem_alu_result),
        .exmem_wdata     (exmem_wdata),
        .exmem_rd        (exmem_rd),
        .exmem_mem_read  (exmem_mem_read),
        .exmem_mem_write (exmem_mem_write),
        .exmem_mem_to_reg(exmem_mem_to_reg),
        .exmem_reg_write (exmem_reg_write)
    );

    dmem u_dmem (
        .clk   (clk),
        .addr  (exmem_alu_result),
        .wdata (exmem_wdata),
        .wmask (4'b1111),
        .we    (exmem_mem_write),
        .rdata (dmem_rdata)
    );

    // 实验一：dmem 直连 mem_wb（实验二此处改经 dbus_decode，见 top_design §9.2）
    mem_wb u_mem_wb (
        .clk             (clk),
        .rst             (rst),
        .rdata           (dmem_rdata),
        .alu_result      (exmem_alu_result),
        .rd              (exmem_rd),
        .mem_to_reg      (exmem_mem_to_reg),
        .reg_write       (exmem_reg_write),
        .memwb_rdata     (memwb_rdata),
        .memwb_alu_result(memwb_alu_result),
        .memwb_rd        (memwb_rd),
        .memwb_mem_to_reg(memwb_mem_to_reg),
        .memwb_reg_write (memwb_reg_write)
    );

    wb u_wb (
        .memwb_rd         (memwb_rd),
        .memwb_alu_result (memwb_alu_result),
        .memwb_rdata      (memwb_rdata),
        .memwb_mem_to_reg (memwb_mem_to_reg),
        .memwb_reg_write  (memwb_reg_write),
        .wb_rd            (wb_rd),
        .wb_data          (wb_data),
        .wb_we            (wb_we)
    );

    hazard_unit u_hazard (
        .rs1_id          (rs1),
        .rs2_id          (rs2),
        .idex_mem_read   (idex_mem_read),
        .idex_rd         (idex_rd),
        .idex_rs1        (idex_rs1),
        .idex_rs2        (idex_rs2),
        .exmem_rd        (exmem_rd),
        .exmem_reg_write (exmem_reg_write),
        .exmem_mem_read  (exmem_mem_read),
        .memwb_rd        (memwb_rd),
        .memwb_reg_write (memwb_reg_write),
        .fwd_a_sel       (fwd_a_sel),
        .fwd_b_sel       (fwd_b_sel),
        .stall           (stall)
    );

endmodule
