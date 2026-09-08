//=============================================================================
// tb_prog_hazard.v — T31：hazard_cover_rom.hex（冒险定向场景）
//   期望：x1=1 x2=2 x3=3 x4=3 x5=4 x6=3 x7=4 x8=8 x9=7 x10=15
//         dmem[0]=3 dmem[4]=4（x9≠99 证明场景4 taken 正确）
//=============================================================================
`timescale 1ns/1ps

module tb_prog_hazard;

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
        $readmemh("hazard_cover_rom.hex", u_cpu.u_imem.mem);
        imem_wen = 0;

        repeat (3) @(posedge clk);
        rst = 0;
        repeat (400) @(posedge clk);
        #1;

        c("x1=1",   u_cpu.u_regfile.x[1]  === 32'd1);
        c("x2=2",   u_cpu.u_regfile.x[2]  === 32'd2);
        c("x3=3",   u_cpu.u_regfile.x[3]  === 32'd3);
        c("x4=3",   u_cpu.u_regfile.x[4]  === 32'd3);
        c("x5=4",   u_cpu.u_regfile.x[5]  === 32'd4);
        c("x6=3",   u_cpu.u_regfile.x[6]  === 32'd3);
        c("x7=4",   u_cpu.u_regfile.x[7]  === 32'd4);
        c("x8=8",   u_cpu.u_regfile.x[8]  === 32'd8);
        c("x9=7(ok path)", u_cpu.u_regfile.x[9] === 32'd7);
        c("x10=15", u_cpu.u_regfile.x[10] === 32'd15);
        c("dmem[0]=3", {u_cpu.u_dmem.mem[3], u_cpu.u_dmem.mem[2],
                        u_cpu.u_dmem.mem[1], u_cpu.u_dmem.mem[0]} === 32'd3);
        c("dmem[4]=4", {u_cpu.u_dmem.mem[7], u_cpu.u_dmem.mem[6],
                        u_cpu.u_dmem.mem[5], u_cpu.u_dmem.mem[4]} === 32'd4);

        if (err == 0) $display("=== ALL PASS ===");
        else          $display("=== FAIL === (%0d/%0d)", err, n);
        $finish;
    end

endmodule
