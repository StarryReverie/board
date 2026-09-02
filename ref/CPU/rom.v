`timescale 1us/1ns

module rom (
    input  wire [31:0] addr,
    output wire [31:0] instr
);
    reg [7:0] mem [0:4095];      // 4KB只读内存，按字节组织

    // 小端序
    assign instr = {mem[addr+3], mem[addr+2], mem[addr+1], mem[addr]};
endmodule
