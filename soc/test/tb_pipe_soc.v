//=============================================================================
// tb_pipe_soc.v — pipeline_top 实验二 build（SOC_BUILD=1）集成验证（计组 T40）
//   验证 dbus_decode 装入 MEM 段后：
//     - sw 命中 MMIO 窗口 → mmio 总线穿出（哑从机捕获 wdata）
//     - lw 读 MMIO 槽 → mmio_rdata 回读进 regfile
//     - 低地址仍走 dmem（读写不受影响）
//   哑从机：STAT(off=01) 恒返回 0x000000CD；TX 写捕获到 cap。
//   程序：lui x1,0x4000；写 TX=0xAB；读 STAT→x3；写 dmem[8]=7；读回 x5；
//         读 TX(off=00)→x6（应 0）
//=============================================================================
`timescale 1ns/1ps

module tb_pipe_soc;

    reg        clk = 0;
    reg        rst = 1;
    reg        imem_wen;
    reg [31:0] imem_waddr, imem_wdata;
    wire       cs_mmio;
    wire [1:0] reg_off;
    wire       mmio_we;
    wire [31:0] mmio_wdata;
    wire [31:0] mmio_rdata;

    integer err = 0;
    integer n   = 0;
    integer i;

    wire [7:0] tx_cap;

    pipeline_top #(.SOC_BUILD(1)) u_cpu (
        .clk (clk), .rst (rst),
        .imem_wen(imem_wen), .imem_waddr(imem_waddr), .imem_wdata(imem_wdata),
        .cs_mmio(cs_mmio), .reg_off(reg_off), .mmio_we(mmio_we),
        .mmio_wdata(mmio_wdata), .mmio_rdata(mmio_rdata)
    );

    // 哑 MMIO 从机：STAT 恒 0xCD；捕获 TX 写
    mmio_slave_stub u_slave (
        .clk(clk),
        .cs(cs_mmio), .off(reg_off), .we(mmio_we), .wdata(mmio_wdata),
        .rdata(mmio_rdata), .cap(tx_cap)
    );

    always #5 clk = ~clk;


    task c;
        input [255:0] name;
        input         ok;
        begin
            n = n + 1;
            if (!ok) begin err = err + 1; $display("FAIL: %0d %0s", n, name); end
            else $display("PASS: %0d %0s", n, name);
        end
    endtask

    task load_word;
        input [31:0] wa;
        input [31:0] wd;
        begin
            u_cpu.u_imem.mem[wa  ] = wd[7:0];
            u_cpu.u_imem.mem[wa+1] = wd[15:8];
            u_cpu.u_imem.mem[wa+2] = wd[23:16];
            u_cpu.u_imem.mem[wa+3] = wd[31:24];
        end
    endtask

    initial begin
        for (i = 0; i < 4096; i = i + 1) u_cpu.u_imem.mem[i] = 8'h00;
        imem_wen = 0;

        // ---- 程序（内嵌机器码）----
        load_word(32'h00, 32'h000040B7);   // lui  x1, 0x4        (x1=0x4000)
        load_word(32'h04, 32'h0AB00113);   // addi x2, x0, 0xAB
        load_word(32'h08, 32'h0020A023);   // sw   x2, 0(x1)      → TX 槽
        load_word(32'h0C, 32'h0040A183);   // lw   x3, 4(x1)      → STAT 槽(哑:0xCD)
        load_word(32'h10, 32'h0000A303);   // lw   x6, 0(x1)      → TX 槽读（应 0）
        load_word(32'h14, 32'h00700213);   // addi x4, x0, 7
        load_word(32'h18, 32'h00402423);   // sw   x4, 8(x0)      → dmem（机器码经 as 校验）
        load_word(32'h1C, 32'h00802283);   // lw   x5, 8(x0)      ← dmem
        load_word(32'h20, 32'h00000063);   // halt 自循环
        for (i = 9; i < 16; i = i + 1) load_word(i*4, 32'h00000013);

        repeat (3) @(posedge clk);
        rst = 0;
        repeat (500) @(posedge clk);
        #1;

        c("x2=0xAB (alu)",    u_cpu.u_regfile.x[2]  === 32'hAB);
        c("x3=0xCD (mmio rd)",u_cpu.u_regfile.x[3]  === 32'hCD);
        c("x6=0 (TX rd=0)",   u_cpu.u_regfile.x[6]  === 32'h0);
        c("tx_cap=0xAB",      tx_cap === 8'hAB);
        c("x5=7 (dmem rd)",   u_cpu.u_regfile.x[5]  === 32'd7);
        c("dmem[8]=7",        {u_cpu.u_dmem.mem[11], u_cpu.u_dmem.mem[10],
                               u_cpu.u_dmem.mem[9],  u_cpu.u_dmem.mem[8]} === 32'd7);

        if (err == 0) $display("=== ALL PASS ===");
        else          $display("=== FAIL === (%0d/%0d)", err, n);
        $finish;
    end

endmodule

// ---- 哑 MMIO 从机（仅本 TB）----
module mmio_slave_stub (
    input  wire        clk,
    input  wire        cs,
    input  wire [1:0]  off,
    input  wire        we,
    input  wire [31:0] wdata,
    output reg  [31:0] rdata,     // 组合读
    output reg  [7:0]  cap        // TX 写捕获
);
    always @(*) begin
        if (cs && !we) begin
            case (off)
                2'b01: rdata = 32'h000000CD;   // STAT 哑值
                default: rdata = 32'b0;
            endcase
        end else begin
            rdata = 32'b0;
        end
    end

    always @(posedge clk) begin
        if (cs && we && off == 2'b00)
            cap <= wdata[7:0];
    end
endmodule
