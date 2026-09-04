`timescale 1ns/1ps
//=============================================================================
// decode.v — 主译码 + 立即数扩展（ID 段纯组合）
//   文档：doc/modules/decode.md（26 行真值表为权威）；宏：defines/*.v
//   口径：
//     - 未知/非法编码控制全 0（reg_write=0 ⇒ 等效 NOP，无副作用）；
//     - rd/rs1/rs2 恒为字段拆解值（reg_write=0 时无写/无冒险影响）；
//     - 非移位立即数一律符号扩展；移位 imm={27'b0,inst[24:20]}；
//     - lui：src_a=0,src_b=imm,op=OR；jal/jalr：src_a=pc,src_b=4,op=ADD；
//     - jump：0=无 1=分支 2=jal 3=jalr；bne=1 表示 bne。
//=============================================================================
`include "defines/instr_define.v"
`include "defines/const_define.v"

module decode (
    input  wire [31:0] inst,
    output wire [4:0]  rd,          // 字段拆解
    output wire [4:0]  rs1,
    output wire [4:0]  rs2,
    output reg  [31:0] imm,
    output reg  [3:0]  alu_op,
    output reg  [1:0]  src_a,       // 0=rs1_fwd 1=idex_pc 2=0
    output reg  [1:0]  src_b,       // 0=rs2_fwd 1=imm 2=4
    output reg         mem_read,
    output reg         mem_write,
    output reg         mem_to_reg,
    output reg         reg_write,
    output reg  [1:0]  jump,        // 0/1/2/3
    output reg         bne
);

    wire [6:0] opcode = inst[6:0];
    wire [2:0] funct3 = inst[14:12];
    wire [4:0] rs1_f  = inst[19:15];
    wire [4:0] rs2_f  = inst[24:20];
    wire [6:0] funct7 = inst[31:25];

    // ---- 五型立即数与 shamt ----
    wire [31:0] imm_i = {{20{inst[31]}}, inst[31:20]};
    wire [31:0] imm_s = {{20{inst[31]}}, inst[31:25], inst[11:7]};
    wire [31:0] imm_b = {{19{inst[31]}}, inst[31], inst[7], inst[30:25], inst[11:8], 1'b0};
    wire [31:0] imm_u = {inst[31:12], 12'b0};
    wire [31:0] imm_j = {{11{inst[31]}}, inst[31], inst[19:12], inst[20], inst[30:21], 1'b0};
    wire [31:0] shamt = {27'b0, inst[24:20]};

    // ---- 指令合法性（译码收口用）----
    wire r10_valid = (opcode == `OP_R_TYPE) && (
        ({funct7, funct3} == {`F7_ADD,     `F3_ADD_SUB}) ||
        ({funct7, funct3} == {`F7_SUB_SRA, `F3_ADD_SUB}) ||
        ({funct7, funct3} == {`F7_ADD,     `F3_SLL})     ||
        ({funct7, funct3} == {`F7_ADD,     `F3_SLT})     ||
        ({funct7, funct3} == {`F7_ADD,     `F3_SLTU})    ||
        ({funct7, funct3} == {`F7_ADD,     `F3_XOR})     ||
        ({funct7, funct3} == {`F7_ADD,     `F3_SRL_SRA}) ||
        ({funct7, funct3} == {`F7_SUB_SRA, `F3_SRL_SRA}) ||
        ({funct7, funct3} == {`F7_ADD,     `F3_OR})      ||
        ({funct7, funct3} == {`F7_ADD,     `F3_AND})
    );
    wire i9_valid = (opcode == `OP_I_TYPE) && (
        (funct3 == 3'b000) ||
        (funct3 == 3'b001 && funct7 == `F7_ADD) ||
        (funct3 == 3'b010) ||
        (funct3 == 3'b011) ||
        (funct3 == 3'b100) ||
        (funct3 == 3'b101 && (funct7 == `F7_ADD || funct7 == `F7_SUB_SRA)) ||
        (funct3 == 3'b110) ||
        (funct3 == 3'b111)
    );
    wire lw_valid    = (opcode == `OP_LW) && (funct3 == `F3_LW_SW);
    wire sw_valid    = (opcode == `OP_SW) && (funct3 == `F3_LW_SW);
    wire beq_valid   = (opcode == `OP_BRANCH) && (funct3 == `F3_ADD_SUB);
    wire bne_valid   = (opcode == `OP_BRANCH) && (funct3 == `F3_BNE);
    wire jal_valid   = (opcode == `OP_JAL);
    wire jalr_valid  = (opcode == `OP_JALR) && (funct3 == 3'b000);
    wire lui_valid   = (opcode == `OP_LUI);

    wire op_writes   = r10_valid | i9_valid | lw_valid | jal_valid | jalr_valid | lui_valid;

    assign rd  = inst[11:7];
    assign rs1 = rs1_f;
    assign rs2 = rs2_f;

    always @(*) begin
        // ---- 默认全 0 ----
        imm        = 32'b0;
        alu_op     = `ALU_ADD;
        src_a      = 2'b00;
        src_b      = 2'b00;
        mem_read   = 1'b0;
        mem_write  = 1'b0;
        mem_to_reg = 1'b0;
        reg_write  = 1'b0;
        jump       = 2'b00;
        bne        = 1'b0;

        case (opcode)
            `OP_R_TYPE: begin
                case ({funct7, funct3})
                    {`F7_ADD,     `F3_ADD_SUB} : alu_op = `ALU_ADD;
                    {`F7_SUB_SRA, `F3_ADD_SUB} : alu_op = `ALU_SUB;
                    {`F7_ADD,     `F3_SLL}     : alu_op = `ALU_SLL;
                    {`F7_ADD,     `F3_SLT}     : alu_op = `ALU_SLT;
                    {`F7_ADD,     `F3_SLTU}    : alu_op = `ALU_SLTU;
                    {`F7_ADD,     `F3_XOR}     : alu_op = `ALU_XOR;
                    {`F7_ADD,     `F3_SRL_SRA} : alu_op = `ALU_SRL;
                    {`F7_SUB_SRA, `F3_SRL_SRA} : alu_op = `ALU_SRA;
                    {`F7_ADD,     `F3_OR}      : alu_op = `ALU_OR;
                    {`F7_ADD,     `F3_AND}     : alu_op = `ALU_AND;
                    default: ;                 // 非法组合：reg_write 已为 0
                endcase
            end

            `OP_I_TYPE: begin
                src_b = 2'b01;
                case (funct3)
                    3'b000: begin imm = imm_i; alu_op = `ALU_ADD; end
                    3'b001: begin if (funct7 == `F7_ADD) begin imm = shamt; alu_op = `ALU_SLL; end end
                    3'b010: begin imm = imm_i; alu_op = `ALU_SLT; end
                    3'b011: begin imm = imm_i; alu_op = `ALU_SLTU; end
                    3'b100: begin imm = imm_i; alu_op = `ALU_XOR; end
                    3'b101: begin
                        if      (funct7 == `F7_ADD)     begin imm = shamt; alu_op = `ALU_SRL; end
                        else if (funct7 == `F7_SUB_SRA) begin imm = shamt; alu_op = `ALU_SRA; end
                    end
                    3'b110: begin imm = imm_i; alu_op = `ALU_OR; end
                    3'b111: begin imm = imm_i; alu_op = `ALU_AND; end
                    default: ;
                endcase
            end

            `OP_LW: begin
                imm = imm_i; alu_op = `ALU_ADD; src_b = 2'b01;
            end

            `OP_SW: begin
                imm = imm_s; alu_op = `ALU_ADD; src_b = 2'b01;
            end

            `OP_BRANCH: begin
                imm = imm_b;
                case (funct3)
                    `F3_ADD_SUB: begin alu_op = `ALU_SUB; jump = 2'b01; bne = 1'b0; end  // beq
                    `F3_BNE:     begin alu_op = `ALU_SUB; jump = 2'b01; bne = 1'b1; end  // bne
                    default: ;
                endcase
            end

            `OP_JAL: begin
                imm = imm_j;
                alu_op = `ALU_ADD; src_a = 2'b01; src_b = 2'b10;   // pc+4 链接
                jump = 2'b10;
            end

            `OP_JALR: begin
                if (funct3 == 3'b000) begin
                    imm = imm_i;
                    alu_op = `ALU_ADD; src_a = 2'b01; src_b = 2'b10;   // pc+4 链接
                    jump = 2'b11;
                end
            end

            `OP_LUI: begin
                imm = imm_u; alu_op = `ALU_OR; src_a = 2'b10; src_b = 2'b01;
            end

            default: ;
        endcase

        // ---- 收口：合法写回/访存控制 ----
        reg_write  = op_writes;
        mem_read   = lw_valid;
        mem_write  = sw_valid;
        mem_to_reg = lw_valid;
    end

endmodule
