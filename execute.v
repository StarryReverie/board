`timescale 1ns/1ps
//=============================================================================
// execute.v — 执行组合：前递 mux + ALU + 目标加法 + 分支判决（EX 段）
//   文档：doc/modules/execute.md（权威）；内例化 alu.v
//   口径：
//     rs1/rs2_fwd = sel(fwd_a/b_sel){reg, EX/MEM, MEM/WB}
//     alu_a/b   = src_a/b 选 {rs_fwd, pc/imm, 0/4}；lui: src_a=0,src_b=imm,op=OR
//     adder_a   = jump==3 ? rs1_fwd : idex_pc；br_target=adder_a+imm（jalr 清 bit0）
//     br_taken  = jump==0 ? 0 : (jump==1 ? (bne?~zero:zero) : 1)
//     wdata     = rs2_fwd（sw 存数，已前递）
//=============================================================================
`include "defines/const_define.v"

module execute (
    input  wire [31:0] rs1_data,     // ID/EX 寄存器读值
    input  wire [31:0] rs2_data,
    input  wire [31:0] ex_fwd_val,   // EX/MEM 前递值（alu_result）
    input  wire [31:0] wb_fwd_val,   // MEM/WB 前递值（wb_data，已含 mem2reg/jal 链接）
    input  wire [1:0]  fwd_a_sel,    // 0=reg 1=EX/MEM 2=MEM/WB
    input  wire [1:0]  fwd_b_sel,
    input  wire [31:0] idex_pc,
    input  wire [31:0] imm,
    input  wire [3:0]  alu_op,
    input  wire [1:0]  src_a,        // 0=rs1_fwd 1=idex_pc 2=0
    input  wire [1:0]  src_b,        // 0=rs2_fwd 1=imm 2=4
    input  wire [1:0]  jump,         // 0=无 1=分支 2=jal 3=jalr
    input  wire        bne,
    output wire [31:0] alu_out,
    output wire [31:0] wdata,
    output wire        zero,
    output wire        of,
    output wire        br_taken,
    output wire [31:0] br_target
);

    reg  [31:0] rs1_fwd;
    reg  [31:0] rs2_fwd;
    reg  [31:0] alu_a;
    reg  [31:0] alu_b;
    wire [31:0] alu_res;
    wire [4:0]  flags;
    wire        zero_s;

    // ---- 目标加法（连续赋值）：jalr 用 rs1_fwd，其余用 pc ----
    wire [31:0] adder_a = (jump == 2'b11) ? rs1_fwd : idex_pc;
    wire [31:0] tgt_raw = adder_a + imm;

    always @(*) begin
        // ---- 前递选源 ----
        case (fwd_a_sel)
            2'b00:   rs1_fwd = rs1_data;
            2'b01:   rs1_fwd = ex_fwd_val;
            2'b10:   rs1_fwd = wb_fwd_val;
            default: rs1_fwd = rs1_data;
        endcase
        case (fwd_b_sel)
            2'b00:   rs2_fwd = rs2_data;
            2'b01:   rs2_fwd = ex_fwd_val;
            2'b10:   rs2_fwd = wb_fwd_val;
            default: rs2_fwd = rs2_data;
        endcase

        // ---- ALU 源选择 ----
        case (src_a)
            2'b00:   alu_a = rs1_fwd;
            2'b01:   alu_a = idex_pc;
            default: alu_a = 32'b0;      // 2'b10 → 0（lui）
        endcase
        case (src_b)
            2'b00:   alu_b = rs2_fwd;
            2'b01:   alu_b = imm;
            default: alu_b = 32'd4;      // 2'b10 → 4（jal/jalr 链接）
        endcase
    end

    assign wdata     = rs2_fwd;
    assign alu_out   = alu_res;
    assign zero      = zero_s;
    assign of        = flags[`OF];

    // jalr 清 bit0（2 字节对齐目标）
    assign br_target = (jump == 2'b11) ? {tgt_raw[31:1], 1'b0} : tgt_raw;

    assign br_taken  = (jump == 2'b00) ? 1'b0 :
                       (jump == 2'b01) ? (bne ? ~zero_s : zero_s) :
                                        1'b1;   // jal / jalr 恒 taken

    alu u_alu (
        .alu_a  (alu_a),
        .alu_b  (alu_b),
        .alu_op (alu_op),
        .alu_out(alu_res),
        .flags  (flags),
        .zero   (zero_s)
    );

endmodule
