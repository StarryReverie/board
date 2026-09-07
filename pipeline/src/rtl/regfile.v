`timescale 1ns/1ps
//=============================================================================
// regfile.v — 寄存器堆（ID 读口 + WB 写口）
//   文档：doc/modules/regfile.md；参考：ref/CPU/regfile.v
//   口径：
//     - reg x[31:1]，x0 恒 0；写 waddr=0 无效；
//     - 写：posedge clk（rst 异步高有效清全 0；we&&waddr!=0 → x[waddr]<=wdata）；
//     - 读：组合 + **读旁路（write-first）**：读口命中当拍写口且 we 时返回 wdata，
//       消除"生产者恰在 WB、消费者同拍在 ID"的陈旧读。
//=============================================================================

module regfile (
    input  wire        clk,
    input  wire        rst,
    input  wire [4:0]  raddr1,
    input  wire [4:0]  raddr2,
    input  wire [4:0]  waddr,
    input  wire [31:0] wdata,
    input  wire        we,
    output wire [31:0] rdata1,
    output wire [31:0] rdata2
);

    reg [31:0] x [31:1];        // x0 恒 0

    integer i;

    // ---- 读（组合 + 旁路）----
    assign rdata1 = (raddr1 == 5'b0) ? 32'b0 :
                    ((we) && (waddr == raddr1)) ? wdata : x[raddr1];
    assign rdata2 = (raddr2 == 5'b0) ? 32'b0 :
                    ((we) && (waddr == raddr2)) ? wdata : x[raddr2];

    // ---- 写（posedge；异步复位清全 0）----
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
