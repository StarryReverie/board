`timescale 1ns/1ps
//=============================================================================
// dbus_decode.v — 数据侧总线译码（DMEM/MMIO 选路，纯组合）
//   规范单源：计组 doc/modules/dbus_decode.md（地址分区/时序/验收）
//   代码交付：exp2/src/rtl/（U13）；例化：计组 pipeline_top（SOC_BUILD=1）
//   地址映射（与 isa.md v1.3 / top_design §9.2 一致）：
//     0x0000_0000–0x0000_0FFF  → cs_dmem（数据 RAM）
//     0x0000_4000 + {0x0,0x4,0x8} → cs_mmio（TX/STAT/RX，reg_off=addr[3:2]）
//     其余 → 读 0、写丢弃
//   语义：rdata = cs_dmem? dmem_rdata : cs_mmio? mmio_rdata : 0；
//         写选通由上层取 we & cs_*（本模块仅译码，不门控写数据）。
//=============================================================================

module dbus_decode (
    input  wire [31:0] addr,          // =exmem_alu_result
    input  wire        we,            // =exmem_mem_write（仅作记录，不参与译码）
    input  wire [31:0] dmem_rdata,
    input  wire [31:0] mmio_rdata,
    output wire        cs_dmem,
    output wire        cs_mmio,
    output wire [1:0]  reg_off,       // 00=TX 01=STAT 10=RX 11=保留
    output wire [31:0] rdata
);

    // dmem 低区：< 4096（=DMEM_BYTES 默认，见计组 const_define.v）
    wire in_dmem = (addr < 32'h0000_1000);
    // MMIO 窗口：0x0000_4000–0x0000_400F（三字槽）
    wire in_mmio = (addr >= 32'h0000_4000) && (addr < 32'h0000_4010);

    assign cs_dmem = in_dmem;
    assign cs_mmio = in_mmio;
    assign reg_off = addr[3:2];

    assign rdata = cs_dmem ? dmem_rdata :
                   (cs_mmio ? mmio_rdata : 32'b0);

endmodule
