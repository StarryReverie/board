//=============================================================================
// tb_dbus_decode.v — dbus_decode 单测（exp2 U13；计组 dbus_decode.md 验收）
//   低区命中 dmem；窗口 TX/STAT/RX 槽 reg_off 正确；其余读 0；
//   rdata mux（dmem/mmio/0）选通正确；写使能不参与译码。
//=============================================================================
`timescale 1ns/1ps

module tb_dbus_decode;

    reg  [31:0] addr;
    reg         we;
    reg  [31:0] dmem_rdata;
    reg  [31:0] mmio_rdata;
    wire        cs_dmem, cs_mmio;
    wire [1:0]  reg_off;
    wire [31:0] rdata;

    integer err = 0;
    integer n   = 0;

    dbus_decode dut (
        .addr(addr), .we(we),
        .dmem_rdata(dmem_rdata), .mmio_rdata(mmio_rdata),
        .cs_dmem(cs_dmem), .cs_mmio(cs_mmio),
        .reg_off(reg_off), .rdata(rdata)
    );

    task c;
        input [255:0] name;
        input         ok;
        begin
            n = n + 1;
            if (!ok) begin err = err + 1; $display("FAIL: %0d %0s", n, name); end
            else $display("PASS: %0d %0s", n, name);
        end
    endtask

    initial begin
        we = 0; dmem_rdata = 32'hDEADBEEF; mmio_rdata = 32'h00CD00AB;

        // ---- 低区 dmem ----
        addr = 32'h00000000; #1
        c("dmem 0x0", cs_dmem===1 && cs_mmio===0 && rdata===32'hDEADBEEF);
        addr = 32'h00000FFC; #1
        c("dmem 0xFFC", cs_dmem===1 && cs_mmio===0);
        addr = 32'h00001000; #1                       // 边界外（4096）
        c("0x1000 unmapped", cs_dmem===0 && cs_mmio===0 && rdata===32'h0);
        addr = 32'h00003FFF; #1
        c("0x3FFF unmapped", cs_dmem===0 && cs_mmio===0 && rdata===32'h0);

        // ---- MMIO 窗口 ----
        addr = 32'h00004000; #1
        c("mmio TX", cs_mmio===1 && cs_dmem===0 && reg_off===2'b00 && rdata===32'h00CD00AB);
        addr = 32'h00004004; #1
        c("mmio STAT", cs_mmio===1 && reg_off===2'b01);
        addr = 32'h00004008; #1
        c("mmio RX", cs_mmio===1 && reg_off===2'b10);
        addr = 32'h0000400C; #1
        c("mmio rsv", cs_mmio===1 && reg_off===2'b11);
        addr = 32'h00004010; #1
        c("window end", cs_mmio===0 && cs_dmem===0 && rdata===32'h0);
        addr = 32'h00005000; #1
        c("above window", cs_mmio===0 && cs_dmem===0 && rdata===32'h0);

        // ---- 高地址 ----
        addr = 32'h80000000; #1
        c("high addr 0", cs_dmem===0 && cs_mmio===0 && rdata===32'h0);

        // ---- we 不参与译码 ----
        addr = 32'h00004000; we = 1; #1
        c("we irrelevant", cs_mmio===1);
        addr = 32'h00000004; #1
        c("dmem we path", cs_dmem===1);

        if (err == 0) $display("=== ALL PASS ===");
        else          $display("=== FAIL === (%0d/%0d)", err, n);
        $finish;
    end

endmodule
