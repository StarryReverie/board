//=============================================================================
// tb_prog_board_demo.v — 上板验收程序回归：exp1_board_demo_rom.hex
//   与 pipeline/src/test/exp1_board_demo.asm 的阶段注释逐一对应。
//   验的是"板上 PASS 判据的充分性"：阶段5 对 22 项覆盖结果逐项比较（`xor`/`sub`
//   交替）→ `sltu` 归一 → `add` 累加进失配计数 x31，只有 x31 == 0 才写签名 0x0F；
//   故板上亮 PASS ⇒ lw / load-use 前递 / lui / 移位 / 有符号比较等覆盖项均正确。
//   **不用 `or` 累加**：否则 ALU_OR 自身故障会把失配全部吞掉（见 §5.1 与
//   build/tb_mut_aluor.v 的 ALU 级故障变异）。
//   本 TB 逐一断言全部中间结果与自检链终值，与 .asm 阶段注释一一对应。
//   运行 400 拍后采样（HALT 自循环内；本程序约 150 拍跑完）。
//=============================================================================
`timescale 1ns/1ps

module tb_prog_board_demo;

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
        input [511:0] name;
        input         ok;
        begin
            n = n + 1;
            if (!ok) begin err = err + 1; $display("FAIL: %0d %0s", n, name); end
            else $display("PASS: %0d %0s", n, name);
        end
    endtask

    task chk_word;
        input [31:0] addr;
        input [31:0] expected;
        input [511:0] name;
        begin
            c(name, {u_cpu.u_dmem.mem[addr[11:0]+3], u_cpu.u_dmem.mem[addr[11:0]+2],
                     u_cpu.u_dmem.mem[addr[11:0]+1], u_cpu.u_dmem.mem[addr[11:0]]} === expected);
        end
    endtask

    initial begin
        for (i = 0; i < 4096; i = i + 1) u_cpu.u_imem.mem[i] = 8'h00;
        $readmemh("exp1_board_demo_rom.hex", u_cpu.u_imem.mem);
        imem_wen = 0;

        repeat (3) @(posedge clk);
        rst = 0;
        repeat (400) @(posedge clk);
        #1;

        // ---- 阶段1：ALU 与背靠背前递 ----
        c("x1=10",   u_cpu.u_regfile.x[1]  === 32'd10);
        c("x2=20",   u_cpu.u_regfile.x[2]  === 32'd20);
        c("x3=30",   u_cpu.u_regfile.x[3]  === 32'd30);
        c("x4=10",   u_cpu.u_regfile.x[4]  === 32'd10);
        c("x9=1(sltu)", u_cpu.u_regfile.x[9] === 32'd1);
        c("x10=0x12345000(lui)", u_cpu.u_regfile.x[10] === 32'h12345000);
        c("x11=0x12345(srli)",   u_cpu.u_regfile.x[11] === 32'h00012345);

        // ---- 阶段2：sw→lw 往返 + load-use ----
        c("x12=0x40", u_cpu.u_regfile.x[12] === 32'h40);
        c("x13=30(lw)", u_cpu.u_regfile.x[13] === 32'd30);
        c("x14=40(add after lw)", u_cpu.u_regfile.x[14] === 32'd40);
        c("x15=40(lw)", u_cpu.u_regfile.x[15] === 32'd40);
        c("x16=60(add after lw)", u_cpu.u_regfile.x[16] === 32'd60);
        chk_word(32'h40, 32'd30, "mem[0x40]=30");
        chk_word(32'h44, 32'd40, "mem[0x44]=40");

        // ---- 阶段3：bne 循环 ----
        c("x17=0(loop cnt)", u_cpu.u_regfile.x[17] === 32'd0);
        c("x18=15(loop sum)", u_cpu.u_regfile.x[18] === 32'd15);

        // ---- 阶段4：移位与有/无符号对照 ----
        c("x19=60(slli)", u_cpu.u_regfile.x[19] === 32'd60);
        c("x20=30(srli)", u_cpu.u_regfile.x[20] === 32'd30);
        c("x21=15(srai)", u_cpu.u_regfile.x[21] === 32'd15);
        c("x22=0xFFFFFFF0", u_cpu.u_regfile.x[22] === 32'hFFFFFFF0);
        c("x23=0xFFFFFFFC(srai)", u_cpu.u_regfile.x[23] === 32'hFFFFFFFC);
        c("x24=15(srli)", u_cpu.u_regfile.x[24] === 32'd15);
        c("x25=1(slt neg)", u_cpu.u_regfile.x[25] === 32'd1);
        c("x26=0(sltu neg)", u_cpu.u_regfile.x[26] === 32'd0);

        // ---- 阶段5：逐项自检链（失配计数 → 掩码 → 签名）----
        c("x27=15(sig mask)",     u_cpu.u_regfile.x[27] === 32'd15);
        c("x28=0(last expect)",   u_cpu.u_regfile.x[28] === 32'd0);
        c("x29=0(last mismatch)", u_cpu.u_regfile.x[29] === 32'd0);
        c("x30=0(err copy)",      u_cpu.u_regfile.x[30] === 32'd0);
        c("x31=0(err count)",     u_cpu.u_regfile.x[31] === 32'd0);
        c("x5=0(mask)",     u_cpu.u_regfile.x[5]  === 32'd0);
        c("x6=0(mask)",     u_cpu.u_regfile.x[6]  === 32'd0);
        c("x7=15(sig)",     u_cpu.u_regfile.x[7]  === 32'd15);
        c("x8=15(sig)",     u_cpu.u_regfile.x[8]  === 32'd15);

        // ---- 验收签名（板级 PASS 判据）----
        chk_word(32'h00, 32'h0000000F, "mem[0]=0x0F (ACCEPT SIGNATURE)");

        if (err == 0) $display("=== ALL PASS ===");
        else          $display("=== FAIL === (%0d/%0d)", err, n);
        $finish;
    end

endmodule
