`timescale 1ns/1ps
//=============================================================================
// imem.v — 指令存储（IF 段，字节数组、组合读 + 预留写口）
//   文档：doc/modules/imem.md；尺寸宏：defines/const_define.v
//   口径：
//     - 字节数组 reg[7:0] mem[0:IMEM_BYTES-1]，小端重组 inst={mem[a+3..a]}；
//     - 读=组合（addr 稳定则 inst 稳定）；越界返回 0（无定义但无害）；
//     - 写口（loader 写口，预留）：posedge clk && imem_wen，4 对齐整字；
//       固化单程序模型下 imem_wen 恒 0，写路径不激活；
//     - 装载：仿真=TB $readmemh（层次引用本实例 mem）；综合=initial 字面量
//       （imem_init.vh，由 verify_hex.py 生成，编译时 -d IMEM_INIT_VH 启用）。
//=============================================================================
`include "defines/const_define.v"

module imem (
    input  wire        clk,         // 写时钟（loader 口，预留）
    input  wire [31:0] addr,        // 取指字节地址（=pc，4 对齐）
    output wire [31:0] inst,        // 组合读
    // ---- loader 写口（预留：固化模型恒 0；恢复在线重载时启用）----
    input  wire        imem_wen,
    input  wire [31:0] imem_waddr,  // 4 对齐
    input  wire [31:0] imem_wdata
);

    localparam [31:0] MEM_BYTES = `IMEM_BYTES;

    reg [7:0] mem [0:`IMEM_BYTES-1];

    // 综合装载：initial 逐字节字面量（imem_init.vh include，由脚本生成）
`ifdef IMEM_INIT_VH
    initial begin
`include "imem_init.vh"
    end
`endif

    // ---- 读（组合，周期内稳定；越界返回 0）----
    wire        in_range = (addr < MEM_BYTES);
    wire [11:0] a        = addr[11:0];          // 容量 4KB，低 12 位索引

    assign inst = in_range ? {mem[a+3], mem[a+2], mem[a+1], mem[a]} : 32'b0;

    // ---- 写（loader 口预留，4 对齐整字、小端落字节）----
    always @(posedge clk) begin
        if (imem_wen && (imem_waddr < MEM_BYTES)) begin
            mem[imem_waddr[11:0]   ] <= imem_wdata[7:0];
            mem[imem_waddr[11:0]+1 ] <= imem_wdata[15:8];
            mem[imem_waddr[11:0]+2 ] <= imem_wdata[23:16];
            mem[imem_waddr[11:0]+3 ] <= imem_wdata[31:24];
        end
    end

endmodule
