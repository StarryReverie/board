`timescale 1ns/1ps
//=============================================================================
// pipeline_top.v — 顶层装配（RV32I 5 级流水线 CPU core）
//   文档：doc/modules/pipeline_top.md（端口/互联权威）；doc/top_design.md §1–§8
//   构建模式（参数 SOC_BUILD）：
//     SOC_BUILD=0（实验一/默认）：dbus_decode 不例化——dmem.rdata 直连
//       mem_wb.rdata；mmio 总线恒 0（H1–H5 口径不变）；
//     SOC_BUILD=1（实验二 build，T40）：MEM 段例化 dbus_decode（代码在
//       exp2/src/rtl/），rdata 经其 mux、dmem 写门控 we&cs_dmem、mmio 总线
//       穿出（cs_mmio/reg_off/mmio_we/mmio_wdata → uart_ctrl 等从机）。
//   冲突策略：前递(EX/MEM、MEM/WB→EX) + load-use 冻结(1 气泡) +
//              分支 EX taken 冲刷 2 条（IF/ID 置 NOP、ID/EX 气泡）。
//=============================================================================
`include "defines/const_define.v"

module pipeline_top #(
    parameter SOC_BUILD = 0
) (
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

    // ---- 访存出口（两种 build 二选一，见 generate 段）----
    wire [31:0] mem_rdata_sel;   // → mem_wb.rdata
    wire        dmem_we_int;     // → dmem.we
    wire        cs_dmem_i, cs_mmio_i;
    wire [1:0]  reg_off_i;

    generate
        if (SOC_BUILD == 1) begin : soc_build
            // 数据侧统一编址译码（T40；dbus_decode 代码在 exp2/src/rtl/）
            dbus_decode u_dbus (
                .addr       (exmem_alu_result),
                .we         (exmem_mem_write),
                .dmem_rdata (dmem_rdata),
                .mmio_rdata (mmio_rdata),
                .cs_dmem    (cs_dmem_i),
                .cs_mmio    (cs_mmio_i),
                .reg_off    (reg_off_i),
                .rdata      (mem_rdata_sel)
            );
            assign dmem_we_int = exmem_mem_write & cs_dmem_i;
            assign cs_mmio     = cs_mmio_i;
            assign reg_off     = reg_off_i;
            assign mmio_we     = exmem_mem_write & cs_mmio_i;
            assign mmio_wdata  = exmem_wdata;
        end else begin : std_build
            // 实验一：dmem 直连，mmio 恒 0
            assign mem_rdata_sel = dmem_rdata;
            assign dmem_we_int   = exmem_mem_write;
            assign cs_mmio       = 1'b0;
            assign reg_off       = 2'b00;
            assign mmio_we       = 1'b0;
            assign mmio_wdata    = 32'b0;
        end
    endgenerate

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
        .we    (dmem_we_int),
        .rdata (dmem_rdata)
    );

    // 访存数据进 WB：rdata 经 mem_rdata_sel（实验一=dmem 直连；SOC=dbus mux）
    mem_wb u_mem_wb (
        .clk             (clk),
        .rst             (rst),
        .rdata           (mem_rdata_sel),
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
