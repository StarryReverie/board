//=============================================================================
// tb_prog_demo.v — 样例程序回归：demo_rom.hex（addi/sw/lw/add/sub/bne/beq）
//   期望（见 demo.asm）：x10(a0)=15  x5(t0)=0  x8(s0)=0x54  x6(t1)=4
//     x7(t2)=1  x28(t3)=1；mem[0]=15、mem[0x40..0x50]={5,4,3,2,1}（字，小端）
//   运行 400 拍后采样（HALT 自循环内）。
//=============================================================================
`timescale 1ns/1ps

module tb_prog_demo;

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

    task chk_word;
        input [31:0] addr;
        input [31:0] expect;
        input [255:0] name;
        begin
            c(name, {u_cpu.u_dmem.mem[addr+3], u_cpu.u_dmem.mem[addr+2],
                     u_cpu.u_dmem.mem[addr+1], u_cpu.u_dmem.mem[addr]} === expect);
        end
    endtask

    initial begin
        for (i = 0; i < 4096; i = i + 1) u_cpu.u_imem.mem[i] = 8'h00;
        $readmemh("demo_rom.hex", u_cpu.u_imem.mem);
        imem_wen = 0;

        repeat (3) @(posedge clk);
        rst = 0;
        repeat (400) @(posedge clk);
        #1;

        c("x10(a0)=15",  u_cpu.u_regfile.x[10] === 32'd15);
        c("x5(t0)=0",    u_cpu.u_regfile.x[5]  === 32'd0);
        c("x8(s0)=0x54", u_cpu.u_regfile.x[8]  === 32'h54);
        c("x6(t1)=4",    u_cpu.u_regfile.x[6]  === 32'd4);
        c("x7(t2)=1",    u_cpu.u_regfile.x[7]  === 32'd1);
        c("x28(t3)=1",   u_cpu.u_regfile.x[28] === 32'd1);

        chk_word(32'h00, 32'd15,  "mem[0]=15");
        chk_word(32'h40, 32'd5,   "mem[0x40]=5");
        chk_word(32'h44, 32'd4,   "mem[0x44]=4");
        chk_word(32'h48, 32'd3,   "mem[0x48]=3");
        chk_word(32'h4C, 32'd2,   "mem[0x4C]=2");
        chk_word(32'h50, 32'd1,   "mem[0x50]=1");

        if (err == 0) $display("=== ALL PASS ===");
        else          $display("=== FAIL === (%0d/%0d)", err, n);
        $finish;
    end

endmodule
