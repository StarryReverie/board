`timescale 1ns/1ps
//=============================================================================
// if_id.v — IF/ID 段间寄存器
//   文档：doc/modules/if_id.md；冲刷置 NOP=`INST_NOP；en=0 保持。
//   时序：posedge clk：rst→全 0；else if(en)：pc<=pc_in，
//         inst<= flush ? `INST_NOP : inst_in。
//=============================================================================
`include "defines/const_define.v"

module if_id (
    input  wire        clk,
    input  wire        rst,        // 异步高有效
    input  wire        en,         // 0=保持（load-use 冻结）；flush 时必为 1
    input  wire        flush,      // 1=置 NOP（分支冲刷）
    input  wire [31:0] inst_in,
    input  wire [31:0] pc_in,
    output reg  [31:0] inst,
    output reg  [31:0] pc
);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            inst <= 32'b0;
            pc   <= 32'b0;
        end else if (en) begin
            pc   <= pc_in;
            inst <= flush ? `INST_NOP : inst_in;
        end
        // en=0：保持
    end

endmodule
