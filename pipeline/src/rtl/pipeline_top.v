`timescale 1ns/1ps
//=============================================================================
// pipeline_top.v — 顶层装配（RV32I 5 级流水线 CPU core）
//   文档：pipeline/doc/modules/pipeline_top.md（端口/互联权威）；pipeline/doc/top_design.md §1–§8
//   构建模式（参数 SOC_BUILD）：
//     SOC_BUILD=0（实验一/默认）：dbus_decode 不例化——dmem.rdata 直连
//       mem_wb.rdata；mmio 总线恒 0（H1–H5 口径不变）；
//     SOC_BUILD=1（实验二 build，T40）：MEM 段例化 dbus_decode（代码在
//       soc/rtl/），rdata 经其 mux、dmem 写门控 we&cs_dmem、mmio 总线
//       穿出（cs_mmio/reg_off/mmio_we/mmio_wdata → uart_ip_top 等从机）。
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
    input  wire [31:0] mmio_rdata,
    // ---- 板级可综合观测口（实验一独立上板用；纯观测，不参与任何逻辑）----
    //   为什么需要：本模块对外原本只有 mmio 输出（实验一恒 0），综合器会判定
    //   "无任何可观测输出" 而把取指/译码/执行/访存整条通路删空。这组端口把已有
    //   内部信号直接引出，既供板级监视器使用，也使综合结果反映真实设计规模。
    //   全部为连续赋值、只读内部信号，**不新增/不改变任何逻辑**。
    output wire [31:0] dbg_pc,           // IF 段 PC
    output wire        dbg_stall,        // load-use 冻结中
    output wire        dbg_br_taken,     // 分支/跳转重定向（taken）
    output wire        dbg_halt,         // 停机自循环：分支目标 == 分支自身（isa §4）
    output wire        dbg_store_valid,  // MEM 段实际写 dmem（= dmem.we）
    output wire [31:0] dbg_store_addr,   // 写地址（= exmem_alu_result）
    output wire [31:0] dbg_store_data,   // 写数据（= exmem_wdata）
    output wire        dbg_wb_we,        // WB 段写回使能
    output wire [4:0]  dbg_wb_rd,        // WB 段写回目的寄存器
    output wire [31:0] dbg_wb_data       // WB 段写回数据
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
            // 数据侧统一编址译码（T40；dbus_decode 代码在 soc/rtl/）
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

    // ================= 板级观测口（只读，纯连线） =================
    assign dbg_pc          = pc;
    assign dbg_stall       = stall;
    assign dbg_br_taken    = br_taken;
    // 停机自循环判据（isa §4：`beq x0,x0,self`）：分支 taken 且**偏移为 0**。
    //   等价性：branch/jal 的目标加法器 A 操作数就是 idex_pc（见 execute.v
    //   `adder_a = (jump==2'b11) ? rs1_fwd : idex_pc`），故
    //       br_target == idex_pc  ⟺  idex_imm == 0        （当 jump != jalr）
    //   故用"零偏移"判据**完全等价**，但把 32 位加法器+32 位比较器从观测路径上拿掉
    //   （直接写 br_target==idex_pc 会让 exmem/idex 寄存器 → 加法器 → 比较器 → 观测触发器
    //    成为全设计最差路径，实测 WNS 因此恶化）。jalr 自环不覆盖——isa §4 的停机约定是
    //   `beq x0,x0,self`，本判据覆盖 branch 与 jal 的零偏移自环，已足够。
    //   注意：本流水线为"未采取预测 + taken 冲刷 2 条"，自循环时 **PC 不是常量**，
    //   而是周期为 3 的 {halt, halt+4, halt+8} 循环；因此"PC 连续不变"不能作为停机判据。
    assign dbg_halt        = br_taken & (idex_jump != 2'b11) & (idex_imm == 32'b0);
    assign dbg_store_valid = dmem_we_int;      // 实验一 = exmem_mem_write；实验二再与 cs_dmem 相与
    assign dbg_store_addr  = exmem_alu_result;
    assign dbg_store_data  = exmem_wdata;
    assign dbg_wb_we       = wb_we;
    assign dbg_wb_rd       = wb_rd;
    assign dbg_wb_data     = wb_data;

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
