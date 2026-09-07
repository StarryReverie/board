//=============================================================================
// tb_prog_cover.v — T31：instr_cover_rom.hex（26 条指令全覆盖）
//   期望（见 instr_cover.asm 头注）：x1..x25 各值 + dmem[0]=0x12345000
//   结尾为 jalr 自旋（等同 HALT），固定 400 拍后采样。
//=============================================================================
`timescale 1ns/1ps

module tb_prog_cover;

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
        $readmemh("instr_cover_rom.hex", u_cpu.u_imem.mem);
        imem_wen = 0;

        repeat (3) @(posedge clk);
        rst = 0;
        repeat (400) @(posedge clk);
        #1;

        c("x1=3",     u_cpu.u_regfile.x[1]  === 32'd3);
        c("x2=5",     u_cpu.u_regfile.x[2]  === 32'd5);
        c("x3=8(add)",  u_cpu.u_regfile.x[3] === 32'd8);
        c("x4=2(sub)",  u_cpu.u_regfile.x[4] === 32'd2);
        c("x5=1(and)",  u_cpu.u_regfile.x[5] === 32'd1);
        c("x6=7(or)",   u_cpu.u_regfile.x[6] === 32'd7);
        c("x7=6(xor)",  u_cpu.u_regfile.x[7] === 32'd6);
        c("x8=96(sll)", u_cpu.u_regfile.x[8] === 32'd96);
        c("x9=3(srl)",  u_cpu.u_regfile.x[9] === 32'd3);
        c("x10=-8",     u_cpu.u_regfile.x[10] === 32'hFFFFFFF8);
        c("x11=-1(sra)",u_cpu.u_regfile.x[11] === 32'hFFFFFFFF);
        c("x12=1(slt)", u_cpu.u_regfile.x[12] === 32'd1);
        c("x13=0(sltu)",u_cpu.u_regfile.x[13] === 32'd0);
        c("x14=1(slti)",u_cpu.u_regfile.x[14] === 32'd1);
        c("x15=0(sltiu)", u_cpu.u_regfile.x[15] === 32'd0);
        c("x16=12(xori)", u_cpu.u_regfile.x[16] === 32'd12);
        c("x17=19(ori)",  u_cpu.u_regfile.x[17] === 32'd19);
        c("x18=3(andi)",  u_cpu.u_regfile.x[18] === 32'd3);
        c("x19=48(slli)", u_cpu.u_regfile.x[19] === 32'd48);
        c("x20=12(srli)", u_cpu.u_regfile.x[20] === 32'd12);
        c("x21=3(srai)",  u_cpu.u_regfile.x[21] === 32'd3);
        c("x22=-2(srai neg)", u_cpu.u_regfile.x[22] === 32'hFFFFFFFE);
        c("x23=lui",      u_cpu.u_regfile.x[23] === 32'h12345000);
        c("x24=lw",       u_cpu.u_regfile.x[24] === 32'h12345000);
        c("x25=8(sentinel ctrl)", u_cpu.u_regfile.x[25] === 32'd8);
        c("mem[0]=lui",   {u_cpu.u_dmem.mem[3], u_cpu.u_dmem.mem[2],
                           u_cpu.u_dmem.mem[1], u_cpu.u_dmem.mem[0]} === 32'h12345000);

        if (err == 0) $display("=== ALL PASS ===");
        else          $display("=== FAIL === (%0d/%0d)", err, n);
        $finish;
    end

endmodule
