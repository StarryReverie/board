//=============================================================================
// tb_prog_test1.v — T31 程序回归：test1_rom.hex
//   ori/add/sub/sw/lw/beq(taken & not-taken)；ABI 寄存器终值 + 内存终值
//   期望：t0(x5)=1 tp(x4)=1 t2(x7)=3 s0(x8)=3 s1(x9)=4 a0(x10)=0x100
//         a1(x11)=2 a3(x13)=2 a4(x14)=0 a5(x15)=0xFF a6(x16)=0x100
//         a7(x17)=0xFE；mem[0x100]=3 mem[0x104]=2 mem[0x108]=0xFE
//=============================================================================
`timescale 1ns/1ps

module tb_prog_test1;

    reg        clk = 0;
    reg        rst = 1;
    reg        imem_wen;
    reg [31:0] imem_waddr, imem_wdata;
    wire       cs_mmio;
    wire [1:0] reg_off;
    wire       mmio_we;
    wire [31:0] mmio_wdata;

    integer err = 0;
    integer n   = 0;
    integer i;

    pipeline_top u_cpu (
        .clk (clk), .rst (rst),
        .imem_wen(imem_wen), .imem_waddr(imem_waddr), .imem_wdata(imem_wdata),
        .cs_mmio(cs_mmio), .reg_off(reg_off), .mmio_we(mmio_we),
        .mmio_wdata(mmio_wdata), .mmio_rdata(32'b0)
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

    initial begin
        for (i = 0; i < 4096; i = i + 1) u_cpu.u_imem.mem[i] = 8'h00;
        $readmemh("test1_rom.hex", u_cpu.u_imem.mem);
        imem_wen = 0;

        repeat (3) @(posedge clk);
        rst = 0;
        repeat (400) @(posedge clk);
        #1;

        c("t0=1",   u_cpu.u_regfile.x[5]  === 32'd1);
        c("t1=2",   u_cpu.u_regfile.x[6]  === 32'd2);
        c("t2=3",   u_cpu.u_regfile.x[7]  === 32'd3);
        c("tp=1",   u_cpu.u_regfile.x[4]  === 32'd1);
        c("s0=3",   u_cpu.u_regfile.x[8]  === 32'd3);
        c("s1=4",   u_cpu.u_regfile.x[9]  === 32'd4);
        c("a0=0x100", u_cpu.u_regfile.x[10] === 32'h100);
        c("a1=2",   u_cpu.u_regfile.x[11] === 32'd2);
        c("a3=2",   u_cpu.u_regfile.x[13] === 32'd2);
        c("a4=0",   u_cpu.u_regfile.x[14] === 32'd0);
        c("a5=0xFF(not BD/DE)", u_cpu.u_regfile.x[15] === 32'hFF);
        c("a6=0x100", u_cpu.u_regfile.x[16] === 32'h100);
        c("a7=0xFE", u_cpu.u_regfile.x[17] === 32'hFE);
        c("mem[0x100]=3", {u_cpu.u_dmem.mem[16'h103], u_cpu.u_dmem.mem[16'h102],
                           u_cpu.u_dmem.mem[16'h101], u_cpu.u_dmem.mem[16'h100]} === 32'd3);
        c("mem[0x104]=2", {u_cpu.u_dmem.mem[16'h107], u_cpu.u_dmem.mem[16'h106],
                           u_cpu.u_dmem.mem[16'h105], u_cpu.u_dmem.mem[16'h104]} === 32'd2);
        c("mem[0x108]=0xFE", {u_cpu.u_dmem.mem[16'h10B], u_cpu.u_dmem.mem[16'h10A],
                              u_cpu.u_dmem.mem[16'h109], u_cpu.u_dmem.mem[16'h108]} === 32'hFE);

        if (err == 0) $display("=== ALL PASS ===");
        else          $display("=== FAIL === (%0d/%0d)", err, n);
        $finish;
    end

endmodule
