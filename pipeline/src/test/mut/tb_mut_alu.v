//=============================================================================
// tb_mut_alu.v — ALU 级故障变异：自检链是否会被吞掉？
//   背景（PR #11 review）：
//     旧固件用 `or x31, x31, x29` 累加失配项。若 ALU_OR 本身故障（恒 0），
//     该累加恒为 0 → x31 保持 0 → 仍写出 0x0F → 板上假 PASS。
//   做法：把 alu.v 的某个 opcode 强制返回 0（同目录 alu_fault_<op>.v），
//     分别跑「旧固件（or 累加）」与「新固件（sltu 归一 + add 累加）」，
//     读出 dmem[0] 签名。判据：
//       · 旧固件 + ALU_OR 故障 → 期望复现"仍写 0x0F"（假 PASS）
//       · 新固件 + ALU_OR 故障 → 期望签名 ≠ 0x0F（已被检出）
//   机器可读判据：每种 opcode 都会打印 `NEWFAULT_DETECTED`（新固件已检出）或
//     `NEWFAULT_UNDETECTED sig=…`（假 PASS / X-Z）；run_mut_alu.ps1 只看这两行，
//     出现 UNDETECTED 或仿真非零退出即整体失败退出（避免"没跑成"被当成"全检出"）。
//   运行：powershell -File pipeline/src/scripts/run_mut_alu.ps1
//   （旧固件 hex 由 runner 从历史提交提取；取不到时该列无效）
//=============================================================================
`timescale 1ns/1ps

module tb_mut_alu;

    reg        clk = 0;
    reg        rst = 1;
    reg        imem_wen = 0;
    reg [31:0] imem_waddr = 0, imem_wdata = 0;
    wire       cs_mmio, mmio_we;
    wire [1:0] reg_off;
    wire [31:0] mmio_wdata;

    integer i, k, ncase;
    reg [8*40:1] fname [0:3];
    reg [8*40:1] label [0:3];
    reg [31:0]  sig;
    reg         detected;   // 新固件是否"检出"（签名非 0x0F 且无 X/Z）

    always #5 clk = ~clk;

    pipeline_top #(.SOC_BUILD(0)) u_cpu (
        .clk(clk), .rst(rst), .imem_wen(imem_wen), .imem_waddr(imem_waddr),
        .imem_wdata(imem_wdata),
        .cs_mmio(cs_mmio), .reg_off(reg_off), .mmio_we(mmio_we),
        .mmio_wdata(mmio_wdata), .mmio_rdata(32'b0),
        .dbg_pc(), .dbg_stall(), .dbg_br_taken(), .dbg_halt(),
        .dbg_store_valid(), .dbg_store_addr(), .dbg_store_data(),
        .dbg_wb_we(), .dbg_wb_rd(), .dbg_wb_data()
    );

    initial begin
        fname[0] = "or_accum_rom.hex";          label[0] = "OLD firmware (or-accumulate)";
        fname[1] = "exp1_board_demo_rom.hex";   label[1] = "NEW firmware (sltu+add)    ";
        ncase    = 2;

        for (k = 0; k < ncase; k = k + 1) begin
            for (i = 0; i < 4096; i = i + 1) u_cpu.u_imem.mem[i] = 8'h00;
            $readmemh(fname[k], u_cpu.u_imem.mem);
            for (i = 0; i < 256; i = i + 1) u_cpu.u_dmem.mem[i] = 8'h00;

            rst = 1; repeat (4) @(posedge clk); rst = 0;
            repeat (600) @(posedge clk);
            #1;

            sig = {u_cpu.u_dmem.mem[3], u_cpu.u_dmem.mem[2],
                   u_cpu.u_dmem.mem[1], u_cpu.u_dmem.mem[0]};
            $display("ALUFAULT: %s  sig=%h  -> %s", label[k], sig,
                     (sig === 32'h0000_000F) ? "0x0F written (PASS would light)" :
                                               "detected (no PASS)");
            // 机器可读判据（runner 只认这两行）：k=1 是新固件，必须"检出"。
            // 0x0F = 假 PASS；含 X/Z = 仿真异常，同样算未检出。
            if (k == 1) begin
                detected = !((^sig === 1'bx) || (sig === 32'h0000_000F));
                if (detected) $display("NEWFAULT_DETECTED");
                else          $display("NEWFAULT_UNDETECTED sig=%h", sig);
            end
        end
        $finish;
    end

endmodule
