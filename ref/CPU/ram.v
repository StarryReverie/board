`timescale 1us/1ns

module ram (
    input  wire        clk,
    input  wire [31:0] addr,
    input  wire [31:0] wdata,
    input  wire [3:0]  wmask, // 最多支持写1个字，即4字节
    input  wire        we,
    output wire [31:0] rdata
);
    reg [7:0] mem [0:4095]; // 4KB 可读写内存
    integer i;

    assign rdata = {mem[addr+3], mem[addr+2], mem[addr+1], mem[addr]};

    always @(posedge clk) begin
        if(we) begin
            for(i=0; i<4; i=i+1) begin
                if (wmask[i]) mem[addr+i] <= wdata[8*i +: 8];
            end
        end
    end

endmodule
