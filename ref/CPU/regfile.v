`timescale 1us/1ns

module regfile(
    input wire clk,
    input wire rst,
    input wire [4:0] raddr1,
    input wire [4:0] raddr2,
    input wire [4:0] waddr,
    input wire [31:0] wdata,
    input wire we,
    output wire [31:0] rdata1,
    output wire [31:0] rdata2
);
    reg [31:0] x [31:1]; // 32个32位通用寄存器，x[0]固定为0

    // 读取逻辑
    assign rdata1 = (raddr1 == 5'b0) ? 32'b0 : x[raddr1];
    assign rdata2 = (raddr2 == 5'b0) ? 32'b0 : x[raddr2];

    integer i;
    // 更新逻辑
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 1; i < 32; i = i + 1) begin
                x[i] <= 32'b0;
            end
        end else if (we) begin
            if (waddr != 5'b0) begin
                x[waddr] <= wdata;
            end
        end
    end
endmodule
