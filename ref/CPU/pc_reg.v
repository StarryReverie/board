`timescale 1us/1ns

module pc_reg(
    input wire clk,
    input wire rst,
    input wire pc_src,
    input wire [31:0] pc_branch,
    output reg [31:0] pc
);
    wire [31:0] pc_pred, pc_next;

    assign pc_pred = pc + 4;
    assign pc_next = pc_src ? pc_branch : pc_pred;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            pc <= 32'b0; // 复位时PC初始化为0
        end else begin
            pc <= pc_next; // 时钟上升沿更新PC值
        end
    end
endmodule