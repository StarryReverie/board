`timescale 1us/1ns
`include "defines/const_define.v"

module alu (
    input  wire [31:0] alu_a,
    input  wire [31:0] alu_b,
    input  wire [3:0]  alu_op,
    output wire [31:0] alu_out,
    output wire [4:0]  flags
);
    reg [32:0] result;

    always @(*) begin
        result = 33'b0;
        case (alu_op)
            `ALU_ADD:  result = {1'b0, alu_a} + {1'b0, alu_b};
            `ALU_SUB:  result = {1'b0, alu_a} - {1'b0, alu_b};
            `ALU_SLT:  result = $signed(alu_a) < $signed(alu_b);
            `ALU_AND:  result = alu_a & alu_b;
            `ALU_OR:   result = alu_a | alu_b;
            `ALU_XOR:  result = alu_a ^ alu_b;
            `ALU_SLL:  result = alu_a << alu_b[4:0];
            `ALU_SRL:  result = alu_a >> alu_b[4:0];
            `ALU_SRA:  result = $signed(alu_a) >>> alu_b[4:0];
            `ALU_SLTU: result = alu_a < alu_b;
            default:   result = 33'b0;
        endcase
    end


    assign alu_out = result[31:0];

    assign flags[`CF] = result[32];
    assign flags[`ZF] = (result[31:0] == 32'b0);
    assign flags[`SF] = result[31];
    assign flags[`PF] = ~^result[7:0];
    assign flags[`OF] = (alu_op == `ALU_ADD) ? ((alu_a[31] == alu_b[31]) && (result[31] != alu_a[31])) :
                        (alu_op == `ALU_SUB) ? ((alu_a[31] != alu_b[31]) && (result[31] == alu_b[31])) :
                        1'b0;

endmodule
