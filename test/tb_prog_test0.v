//=============================================================================
// tb_prog_test0.v — T31 程序回归：test0_rom.hex（ori/add/sub/sw/lw）
//   期望（见 test0.asm）：x1=1 x2=2 x3=3 x4=1 x5=3 x6=1 x10=0x10；
//   mem[4]=3、mem[0x10]=1。运行 250 拍后采样（HALT 自循环内）。
//=============================================================================
`timescale 1ns/1ps

module tb_prog_test0;

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
        for (i = 0; i < 4096; i = i + 1) u_cpu.u_imem.mem[i] = 8'h00;   // 未用区置 NOP-ish
        $readmemh("test0_rom.hex", u_cpu.u_imem.mem);
        imem_wen = 0;

        repeat (3) @(posedge clk);
        rst = 0;
        repeat (250) @(posedge clk);
        #1;

        c("x1=1",  u_cpu.u_regfile.x[1]  === 32'd1);
        c("x2=2",  u_cpu.u_regfile.x[2]  === 32'd2);
        c("x3=3",  u_cpu.u_regfile.x[3]  === 32'd3);
        c("x4=1",  u_cpu.u_regfile.x[4]  === 32'd1);
        c("x5=3",  u_cpu.u_regfile.x[5]  === 32'd3);
        c("x6=1",  u_cpu.u_regfile.x[6]  === 32'd1);
        c("x10=0x10", u_cpu.u_regfile.x[10] === 32'h10);
        c("mem[4]=3",  {u_cpu.u_dmem.mem[7], u_cpu.u_dmem.mem[6],
                        u_cpu.u_dmem.mem[5], u_cpu.u_dmem.mem[4]} === 32'd3);
        c("mem[0x10]=1", {u_cpu.u_dmem.mem[19], u_cpu.u_dmem.mem[18],
                          u_cpu.u_dmem.mem[17], u_cpu.u_dmem.mem[16]} === 32'd1);

        if (err == 0) $display("=== ALL PASS ===");
        else          $display("=== FAIL === (%0d/%0d)", err, n);
        $finish;
    end

endmodule
