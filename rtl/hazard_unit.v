`timescale 1ns/1ps
//=============================================================================
// hazard_unit.v — 冲突处理单元（段间协调，纯组合）
//   文档：doc/modules/hazard_unit.md（判定逻辑权威）
//   口径：
//     前递（A/B 同规则，EX/MEM 优先，两个源同时命中取 EX/MEM）：
//       exmem_reg_write && exmem_rd!=0 && !exmem_mem_read && exmem_rd==x → sel=1
//       else memwb_reg_write && memwb_rd!=0 && memwb_rd==x → sel=2，否则 0
//       （EX/MEM 为 load 时不前递：数据未就绪，消费者必已被 load-use 停过）
//     load-use 暂停：stall = idex_mem_read && idex_rd!=0 &&
//                     (idex_rd==rs1_id || idex_rd==rs2_id)
//   分支冲刷 flush_branch 由 execute.br_taken 直接给出（top 层取用），本单元不产。
//=============================================================================

module hazard_unit (
    input  wire [4:0] rs1_id,          // 当前 ID 指令读源（decode 拆解）
    input  wire [4:0] rs2_id,
    input  wire       idex_mem_read,   // EX 段指令是否为 load
    input  wire [4:0] idex_rd,         // EX 段目的寄存器（load-use 判据）
    input  wire [4:0] idex_rs1,        // EX 段读源（前递比较）
    input  wire [4:0] idex_rs2,
    input  wire [4:0] exmem_rd,
    input  wire       exmem_reg_write,
    input  wire       exmem_mem_read,
    input  wire [4:0] memwb_rd,
    input  wire       memwb_reg_write,
    output reg  [1:0] fwd_a_sel,       // 0=reg 1=EX/MEM 2=MEM/WB
    output reg  [1:0] fwd_b_sel,
    output wire       stall            // load-use 冻结
);

    always @(*) begin
        // ---- A 源（idex_rs1）----
        if (exmem_reg_write && exmem_rd != 5'b0 && !exmem_mem_read && exmem_rd == idex_rs1)
            fwd_a_sel = 2'b01;
        else if (memwb_reg_write && memwb_rd != 5'b0 && memwb_rd == idex_rs1)
            fwd_a_sel = 2'b10;
        else
            fwd_a_sel = 2'b00;

        // ---- B 源（idex_rs2）----
        if (exmem_reg_write && exmem_rd != 5'b0 && !exmem_mem_read && exmem_rd == idex_rs2)
            fwd_b_sel = 2'b01;
        else if (memwb_reg_write && memwb_rd != 5'b0 && memwb_rd == idex_rs2)
            fwd_b_sel = 2'b10;
        else
            fwd_b_sel = 2'b00;
    end

    // ---- load-use：ID 指令依赖 EX 段 load 的 rd → 冻结 1 拍（恰 1 气泡）----
    assign stall = idex_mem_read && (idex_rd != 5'b0) &&
                   ((idex_rd == rs1_id) || (idex_rd == rs2_id));

endmodule
