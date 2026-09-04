`timescale 1ns/1ps
//=============================================================================
// dmem.v — 数据存储（MEM 段：同步写/组合读）
//   文档：doc/modules/dmem.md；尺寸宏：defines/const_define.v
//   口径：
//     - 字节数组 reg[7:0] mem[0:DMEM_BYTES-1]，小端；wmask 字节写（sw 全字）；
//     - 写=posedge clk；读=组合（周期内稳定，mem_wb 末沿捕获）；
//     - 读写同拍同址：先出旧值（读在写生效前）→ lw 须晚于 sw 一拍；
//     - 复位不清存储（数据由程序自初始化）；越界读返回 0、写丢弃。
//=============================================================================
`include "defines/const_define.v"

module dmem (
    input  wire        clk,
    input  wire [31:0] addr,
    input  wire [31:0] wdata,
    input  wire [3:0]  wmask,        // 字节写使能（默认 4'b1111）
    input  wire        we,
    output wire [31:0] rdata
);

    localparam [31:0] MEM_BYTES = `DMEM_BYTES;

    reg [7:0] mem [0:`DMEM_BYTES-1];

    integer i;

    // ---- 读（组合；越界返回 0）----
    wire        in_range = (addr < MEM_BYTES);
    wire [11:0] a        = addr[11:0];

    assign rdata = in_range ? {mem[a+3], mem[a+2], mem[a+1], mem[a]} : 32'b0;

    // ---- 写（同步，末沿生效；wmask 字节使能）----
    always @(posedge clk) begin
        if (we && in_range) begin
            for (i = 0; i < 4; i = i + 1) begin
                if (wmask[i]) begin
                    mem[a + i] <= wdata[i*8 +: 8];
                end
            end
        end
    end

endmodule
