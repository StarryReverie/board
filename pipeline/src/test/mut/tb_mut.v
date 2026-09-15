//=============================================================================
// tb_mut.v — 上板自检链的"变异灵敏度"测试（指令级）
//   目的：回答 review 的核心质疑——"某项功能（lw / load-use 前递 / lui /
//   移位 / 有符号比较）坏了，板级签名还会不会误报 0x0F？"
//   做法：逐条把覆盖项对应的指令改成 NOP（或换成错误操作数）→ 跑完程序 →
//   读 dmem[0] 签名。判据：所有变异都必须使签名 ≠ 0x0F（= 板上不会亮 PASS）。
//   说明：位于 test/mut/ 子目录，run_tb.ps1 不采集（不影响 23 项回归计数）。
//   运行：powershell -File pipeline/src/scripts/run_mut.ps1
//=============================================================================
`timescale 1ns/1ps

module tb_mut;

    reg        clk = 0;
    reg        rst = 1;
    reg        imem_wen;
    reg [31:0] imem_waddr, imem_wdata;
    wire       cs_mmio;
    wire [1:0] reg_off;
    wire       mmio_we;
    wire [31:0] mmio_wdata;

    pipeline_top u_cpu (
        .clk (clk), .rst (rst),
        .imem_wen(imem_wen), .imem_waddr(imem_waddr), .imem_wdata(imem_wdata),
        .cs_mmio(cs_mmio), .reg_off(reg_off), .mmio_we(mmio_we),
        .mmio_wdata(mmio_wdata), .mmio_rdata(32'b0)
    );

    always #5 clk = ~clk;

    // ---- 变异表：字节地址（-1 = 不变异） / 替换字 / 说明 ----
    integer     mut_addr [0:31];
    integer     mut_word [0:31];
    reg [255:0] mut_name [0:31];

    integer i, k, nc, ndet, nmiss;
    reg [31:0] sig;

    localparam NOP = 32'h0000_0013;                    // addi x0,x0,0
    localparam SWAP_SLTU = 32'h0160_3D33;              // sltu x26,x0,x22（交换操作数 → 1）

    initial begin
        imem_wen = 0;
        nc = 0;

        mut_addr[nc] = -1;             mut_word[nc] = 32'h0;          mut_name[nc] = "baseline: no mutation";                   nc = nc + 1;
        // ---- stage1: ALU / lui / srli ----
        mut_addr[nc] = 32'h18;         mut_word[nc] = NOP;            mut_name[nc] = "0x18 xor  x7  -> NOP (milestone)";        nc = nc + 1;
        mut_addr[nc] = 32'h1c;         mut_word[nc] = NOP;            mut_name[nc] = "0x1c slt  x8  -> NOP";                    nc = nc + 1;
        mut_addr[nc] = 32'h20;         mut_word[nc] = NOP;            mut_name[nc] = "0x20 sltu x9  -> NOP";                    nc = nc + 1;
        mut_addr[nc] = 32'h24;         mut_word[nc] = NOP;            mut_name[nc] = "0x24 lui  x10 -> NOP";                    nc = nc + 1;
        mut_addr[nc] = 32'h28;         mut_word[nc] = NOP;            mut_name[nc] = "0x28 srli x11 -> NOP";                    nc = nc + 1;
        // ---- stage2: sw->lw round trip + 2 load-use consumers ----
        mut_addr[nc] = 32'h30;         mut_word[nc] = NOP;            mut_name[nc] = "0x30 sw   x3  -> NOP (store)";            nc = nc + 1;
        mut_addr[nc] = 32'h34;         mut_word[nc] = NOP;            mut_name[nc] = "0x34 lw   x13 -> NOP (load)";             nc = nc + 1;
        mut_addr[nc] = 32'h38;         mut_word[nc] = NOP;            mut_name[nc] = "0x38 add  x14 -> NOP (load-use use)";     nc = nc + 1;
        mut_addr[nc] = 32'h40;         mut_word[nc] = NOP;            mut_name[nc] = "0x40 lw   x15 -> NOP (load)";             nc = nc + 1;
        mut_addr[nc] = 32'h44;         mut_word[nc] = NOP;            mut_name[nc] = "0x44 add  x16 -> NOP (load-use use)";     nc = nc + 1;
        // ---- stage3: loop ----
        mut_addr[nc] = 32'h50;         mut_word[nc] = NOP;            mut_name[nc] = "0x50 add  x18 -> NOP (accumulate)";       nc = nc + 1;
        mut_addr[nc] = 32'h54;         mut_word[nc] = NOP;            mut_name[nc] = "0x54 addi x17 -> NOP (no exit: hang)";    nc = nc + 1;
        mut_addr[nc] = 32'h58;         mut_word[nc] = NOP;            mut_name[nc] = "0x58 bne      -> NOP (loop control)";     nc = nc + 1;
        // ---- stage4: shifts + signed/unsigned ----
        mut_addr[nc] = 32'h5c;         mut_word[nc] = NOP;            mut_name[nc] = "0x5c slli x19 -> NOP";                    nc = nc + 1;
        mut_addr[nc] = 32'h60;         mut_word[nc] = NOP;            mut_name[nc] = "0x60 srli x20 -> NOP";                    nc = nc + 1;
        mut_addr[nc] = 32'h64;         mut_word[nc] = NOP;            mut_name[nc] = "0x64 srai x21 -> NOP";                    nc = nc + 1;
        mut_addr[nc] = 32'h6c;         mut_word[nc] = NOP;            mut_name[nc] = "0x6c srai x23 -> NOP (sign keep)";        nc = nc + 1;
        mut_addr[nc] = 32'h70;         mut_word[nc] = NOP;            mut_name[nc] = "0x70 srli x24 -> NOP";                    nc = nc + 1;
        mut_addr[nc] = 32'h74;         mut_word[nc] = NOP;            mut_name[nc] = "0x74 slt  x25 -> NOP";                    nc = nc + 1;
        mut_addr[nc] = 32'h78;         mut_word[nc] = SWAP_SLTU;      mut_name[nc] = "0x78 sltu x26 operand swap";              nc = nc + 1;
        // ---- stage5: 签名生成（挑"一旦被改就会改变正确运行签名"的指令）----
        //   注：`or x31,x31,x30` 这类只在"有错"场景起作用的指令被改掉时，
        //   正确运行的签名不变（等价变异），故不列入；自检机制本身的鲁棒性
        //   由 ALU 级故障矩阵（tb_mut_alu.v）负责验证。
        mut_addr[nc] = 32'h1c8;        mut_word[nc] = NOP;            mut_name[nc] = "0x1c8 addi x27,15 -> NOP (sig const)";    nc = nc + 1;
        mut_addr[nc] = 32'h1dc;        mut_word[nc] = NOP;            mut_name[nc] = "0x1dc srl  x8      -> NOP (2nd mechanism)"; nc = nc + 1;
        mut_addr[nc] = 32'h1e4;        mut_word[nc] = NOP;            mut_name[nc] = "0x1e4 sw   x8,0    -> NOP (signature)";    nc = nc + 1;

        ndet = 0; nmiss = 0;
        for (k = 0; k < nc; k = k + 1) begin
            // 重载 imem 并打入变异
            for (i = 0; i < 4096; i = i + 1) u_cpu.u_imem.mem[i] = 8'h00;
            $readmemh("exp1_board_demo_rom.hex", u_cpu.u_imem.mem);
            if (mut_addr[k] >= 0) begin
                u_cpu.u_imem.mem[mut_addr[k]+0] = mut_word[k][7:0];
                u_cpu.u_imem.mem[mut_addr[k]+1] = mut_word[k][15:8];
                u_cpu.u_imem.mem[mut_addr[k]+2] = mut_word[k][23:16];
                u_cpu.u_imem.mem[mut_addr[k]+3] = mut_word[k][31:24];
            end
            // 清 dmem：避免上一轮留下的 0x0F 造成"假未检出"
            for (i = 0; i < 256; i = i + 1) u_cpu.u_dmem.mem[i] = 8'h00;

            rst = 1; repeat (4) @(posedge clk); rst = 0;
            repeat (400) @(posedge clk);
            #1;

            sig = {u_cpu.u_dmem.mem[3], u_cpu.u_dmem.mem[2],
                   u_cpu.u_dmem.mem[1], u_cpu.u_dmem.mem[0]};

            if (k == 0) begin
                if (sig === 32'h0000_000F) $display("BASE OK   %s  sig=0F", mut_name[k]);
                else begin $display("BASE FAIL %s  sig=%h", mut_name[k], sig); nmiss = nmiss + 1; end
            end else if (^sig === 1'bx) begin
                // sig 含 X/Z（仿真出错/未跑完）：'!==' 对它返回真，会被误记成"检出"，
                // 必须先按"未检出"归类，否则 X 也能凑出 MUTATION ALL PASS。
                nmiss = nmiss + 1;
                $display("INVALID!! %s  sig=%h (含 X/Z，判为未检出)", mut_name[k], sig);
            end else if (sig !== 32'h0000_000F) begin
                ndet = ndet + 1;
                $display("DETECTED  %s  sig=%h", mut_name[k], sig);
            end else begin
                nmiss = nmiss + 1;
                $display("MISSED!!  %s  sig=0F (误报为通过)", mut_name[k]);
            end
        end

        $display("=== mutation test: detected %0d / %0d ; missed %0d ===", ndet, nc-1, nmiss);
        if (nmiss == 0) $display("=== MUTATION ALL PASS ===");
        else            $display("=== MUTATION FAIL ===");
        $finish;
    end

endmodule
