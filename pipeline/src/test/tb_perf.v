//=============================================================================
// tb_perf.v — T32 性能测量 TB（pipeline/doc/perf_analysis.md §5）
//   五档程序：PERF_TEST0（默认）/ PERF_TEST1 / PERF_SORT / PERF_COVER /
//             PERF_HAZARD（xvlog -d 选择；run_perf.ps1 逐档编译）
//   规模档（v2.0 §3，同程序三档循环次数，用于验证 CPI 随规模收敛）：
//             PERF_LOOP8 / PERF_LOOP32 / PERF_LOOP128
//   测量（全部经层次引用，RTL 零改动；口径见 pipeline/doc/perf_analysis.md §3）：
//     EX 槽 e = rst 释放后第 e 个 posedge（#1 采样，寄存输出已稳定）
//     真实指令：id_ex 控制字非全零（bubble/复位槽全零，译码全零不可能）
//     伪 NOP：   br_taken 延迟 2 拍命中（flush 注入的 addi x0,x0,0，
//                实测 e_b+2 入 EX——e_b 为分支 EX 槽）
//     停机 h：   首个 EX 真实槽且 idex_pc == end_addr（程序末自旋首执）
//     C_total = h + 2（首自旋的冲刷尾：bubble h+1、伪 NOP h+2）
//     C_fixed = 3（停机自旋 1 拍 + 冲刷尾 2 拍），C_steady = C_total - C_fixed
//     恒等式：   C == IC + (F-1) + L + 2T   （F=首个真实 EX 槽拍号；
//                L=stall 冻结拍数；T=br_taken 重定向数）
//   正确性：每档内嵌 tb_prog_* 同源期望断言（T31 回归口径复用）
//   假定实例名：u_cpu.u_imem/u_regfile/u_dmem；顶层 wire idex_*/stall/br_taken
//   end_addr：最后一个 0x00000063（beq x0,x0,0 自旋）字；无则取最后一个
//             非零字（jalr 自旋，如 instr_cover）——test1 自旋后带死代码，
//             故不可直接取"末尾非零字"
//=============================================================================
`timescale 1ns/1ps

// 看门狗：规模档 IC 更大，需放宽（loop128：IC=1287，停机 h=1797）
`ifdef PERF_LOOP128
    `define PERF_MAXCYC 300000
`elsif PERF_LOOP32
    `define PERF_MAXCYC 100000
`else
    `define PERF_MAXCYC 30000
`endif

`ifdef PERF_LOOP8
    `define PERF_NAME "loop8"
    `define PERF_HEX  "loop_heavy_8_rom.hex"
`elsif PERF_LOOP32
    `define PERF_NAME "loop32"
    `define PERF_HEX  "loop_heavy_32_rom.hex"
`elsif PERF_LOOP128
    `define PERF_NAME "loop128"
    `define PERF_HEX  "loop_heavy_128_rom.hex"
`elsif PERF_TEST1
    `define PERF_NAME "test1"
    `define PERF_HEX  "test1_rom.hex"
`elsif PERF_SORT
    `define PERF_NAME "sort"
    `define PERF_HEX  "test_sort_rom.hex"
`elsif PERF_COVER
    `define PERF_NAME "cover"
    `define PERF_HEX  "instr_cover_rom.hex"
`elsif PERF_HAZARD
    `define PERF_NAME "hazard"
    `define PERF_HEX  "hazard_cover_rom.hex"
`else
    `define PERF_NAME "test0"
    `define PERF_HEX  "test0_rom.hex"
`endif

module tb_perf;

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

    // ---- 性能计数 ----
    integer e;                  // 拍号（rst 释放后第 e 个 posedge）
    integer IC, F_ex, hh, L, R; // 动态指令数/首个真实槽/停机槽/冻结拍/重定向数
    integer C_total, C_steady, C_fixed;
    integer ident_a, ident_b, residual;
    integer end_addr;           // 程序末自旋字节地址
    reg    br_p1, br_p2;        // br_taken 延迟 1/2 拍（伪 NOP 过滤，见下）
    reg    hit;                 // 已检测到停机
    reg    ex_real;             // 当前 EX 槽真实指令（控制字非全零）
    reg    ex_pseudo;           // 当前 EX 槽为 flush 伪 NOP
    integer w;                  // 字扫描索引
    reg [31:0] wordv;
    integer last63, topnz;

    pipeline_top u_cpu (
        .clk (clk), .rst (rst),
        .imem_wen(imem_wen), .imem_waddr(imem_waddr), .imem_wdata(imem_wdata),
        .cs_mmio(cs_mmio), .reg_off(reg_off), .mmio_we(mmio_we),
        .mmio_wdata(mmio_wdata), .mmio_rdata(32'b0)
    );

    always #5 clk = ~clk;

    task chk;
        input [511:0] name;
        input         ok;
        begin
            n = n + 1;
            if (!ok) begin err = err + 1; $display("FAIL: %0d %0s", n, name); end
            else $display("PASS: %0d %0s", n, name);
        end
    endtask

    // ---- 停机器：扫描 imem 已装载镜像 ----
    task find_end;
        begin
            last63 = -1;
            topnz  = -1;
            for (w = 0; w < 1024; w = w + 1) begin
                wordv = {u_cpu.u_imem.mem[4*w+3], u_cpu.u_imem.mem[4*w+2],
                         u_cpu.u_imem.mem[4*w+1], u_cpu.u_imem.mem[4*w]};
                if (wordv != 32'h0) topnz = w;
                if (wordv == 32'h00000063) last63 = w;   // beq x0,x0,0 自旋
            end
            if (last63 >= 0) end_addr = 4*last63;
            else             end_addr = 4*topnz;          // jalr 自旋兜底
        end
    endtask

    initial begin
        // ---- 装载（同 tb_prog_*）----
        for (i = 0; i < 4096; i = i + 1) u_cpu.u_imem.mem[i] = 8'h00;
        $readmemh(`PERF_HEX, u_cpu.u_imem.mem);
        imem_wen = 0;

        // ---- 复位释放，拍号从下一个 posedge 计 1 ----
        repeat (3) @(posedge clk);
        rst = 0;

        IC = 0; F_ex = 0; hh = 0; L = 0; R = 0; hit = 0; br_p1 = 0; br_p2 = 0;
        find_end;

        // 伪 NOP 时序（实测确认）：分支 EX 槽 br_taken=1（e_b）→
        //   e_b+1 id_ex 灌零气泡、if_id 置 NOP(0x13) → e_b+2 伪 NOP 入 EX
        //   （addi x0,x0,0，控制字非零、pc=被冲刷取指地址）。
        // 故伪 NOP 过滤需 br_taken 延迟 2 拍：pseudo@e ⇔ br@(e-2)。
        for (e = 1; e <= `PERF_MAXCYC && !hit; e = e + 1) begin
            @(posedge clk);
            #1;                                   // 采样 EX 槽 e（已锁存）
            ex_real = (u_cpu.idex_mem_read  | u_cpu.idex_mem_write |
                       u_cpu.idex_reg_write | u_cpu.idex_bne |
                       (u_cpu.idex_jump != 2'b00) |
                       (u_cpu.idex_alu_op  != 4'b0000) |
                       (u_cpu.idex_src_a   != 2'b00) |
                       (u_cpu.idex_src_b   != 2'b00));
            ex_pseudo = ex_real & br_p2;          // flush 伪 NOP（br 延迟 2 拍）
            if (ex_real & !ex_pseudo) begin
                if (IC == 0) F_ex = e;
                IC = IC + 1;
                if (u_cpu.idex_pc == end_addr) begin
                    hh = e;                       // 停机指令首执（真实槽）
                    hit = 1;
                end
            end
            if (u_cpu.stall)    L = L + 1;        // 冻结事件（气泡落下一拍）
            if (u_cpu.br_taken) R = R + 1;        // 重定向（含停机自旋本拍）
`ifdef PERF_TRACE
            $display("TRC: e=%0d real=%0b pseudo=%0b stall=%0b br=%0b pc=%0h aluop=%0h rw=%0b mw=%0b mr=%0b j=%0b ic=%0d l=%0d r=%0d hit=%0b",
                     e, ex_real, ex_pseudo, u_cpu.stall, u_cpu.br_taken,
                     u_cpu.idex_pc, u_cpu.idex_alu_op, u_cpu.idex_reg_write,
                     u_cpu.idex_mem_write, u_cpu.idex_mem_read, u_cpu.idex_jump,
                     IC, L, R, hit);
`endif
            br_p2 = br_p1;
            br_p1 = u_cpu.br_taken;
        end

        if (!hit) begin
            $display("PERF_SUMMARY: name=%0s ic=NA c=NA ident=0 ok=0", `PERF_NAME);
            chk("halt detected within PERF_MAXCYC edges", 0);
            $display("=== FAIL === (watchdog)");
            $finish;
        end

        // ---- 停机后稳定窗口（冲刷尾 + 自旋数拍后采样终值）----
        repeat (12) @(posedge clk);

        // ---- 三窗口与恒等式 ----
        C_total = hh + 2;
        C_fixed = 3;
        C_steady = C_total - C_fixed;
        ident_a = (C_total == (IC + (F_ex - 1) + L + 2*R));
        ident_b = (C_steady == (IC + L + 2*R - C_fixed));
        residual = C_steady - (IC + L + 2*R - C_fixed);
        chk("identity A: C_total==IC+(F-1)+L+2T", ident_a);
        chk("identity B: C_steady==IC+L+2T-C_fixed", ident_b);
        chk("steady residual zero", residual == 0);
        $display("INFO: program=%0s ic=%0d f=%0d h=%0d c_total=%0d c_steady=%0d c_fixed=%0d l=%0d t=%0d",
                 `PERF_NAME, IC, F_ex, hh, C_total, C_steady, C_fixed, L, R);

        // ================= 正确性期望（与 tb_prog_* 同源） =================
`ifdef PERF_TEST1
        chk("t0=1",   u_cpu.u_regfile.x[5]  === 32'd1);
        chk("t1=2",   u_cpu.u_regfile.x[6]  === 32'd2);
        chk("t2=3",   u_cpu.u_regfile.x[7]  === 32'd3);
        chk("tp=1",   u_cpu.u_regfile.x[4]  === 32'd1);
        chk("s0=3",   u_cpu.u_regfile.x[8]  === 32'd3);
        chk("s1=4",   u_cpu.u_regfile.x[9]  === 32'd4);
        chk("a0=0x100", u_cpu.u_regfile.x[10] === 32'h100);
        chk("a1=2",   u_cpu.u_regfile.x[11] === 32'd2);
        chk("a3=2",   u_cpu.u_regfile.x[13] === 32'd2);
        chk("a4=0",   u_cpu.u_regfile.x[14] === 32'd0);
        chk("a5=0xFF",u_cpu.u_regfile.x[15] === 32'hFF);
        chk("a6=0x100", u_cpu.u_regfile.x[16] === 32'h100);
        chk("a7=0xFE", u_cpu.u_regfile.x[17] === 32'hFE);
        chk("mem[0x100]=3", {u_cpu.u_dmem.mem[16'h103], u_cpu.u_dmem.mem[16'h102],
                           u_cpu.u_dmem.mem[16'h101], u_cpu.u_dmem.mem[16'h100]} === 32'd3);
        chk("mem[0x104]=2", {u_cpu.u_dmem.mem[16'h107], u_cpu.u_dmem.mem[16'h106],
                           u_cpu.u_dmem.mem[16'h105], u_cpu.u_dmem.mem[16'h104]} === 32'd2);
        chk("mem[0x108]=0xFE", {u_cpu.u_dmem.mem[16'h10B], u_cpu.u_dmem.mem[16'h10A],
                              u_cpu.u_dmem.mem[16'h109], u_cpu.u_dmem.mem[16'h108]} === 32'hFE);
`elsif PERF_SORT
        chk("mem[0x200]=1", {u_cpu.u_dmem.mem[16'h203], u_cpu.u_dmem.mem[16'h202],
                           u_cpu.u_dmem.mem[16'h201], u_cpu.u_dmem.mem[16'h200]} === 32'd1);
        chk("mem[0x204]=2", {u_cpu.u_dmem.mem[16'h207], u_cpu.u_dmem.mem[16'h206],
                           u_cpu.u_dmem.mem[16'h205], u_cpu.u_dmem.mem[16'h204]} === 32'd2);
        chk("mem[0x208]=3", {u_cpu.u_dmem.mem[16'h20B], u_cpu.u_dmem.mem[16'h20A],
                           u_cpu.u_dmem.mem[16'h209], u_cpu.u_dmem.mem[16'h208]} === 32'd3);
        chk("mem[0x20C]=4", {u_cpu.u_dmem.mem[16'h20F], u_cpu.u_dmem.mem[16'h20E],
                           u_cpu.u_dmem.mem[16'h20D], u_cpu.u_dmem.mem[16'h20C]} === 32'd4);
        chk("mem[0x210]=5", {u_cpu.u_dmem.mem[16'h213], u_cpu.u_dmem.mem[16'h212],
                           u_cpu.u_dmem.mem[16'h211], u_cpu.u_dmem.mem[16'h210]} === 32'd5);
        chk("t0=0x200", u_cpu.u_regfile.x[5] === 32'h200);
        chk("t1=4",    u_cpu.u_regfile.x[6] === 32'd4);
        chk("s0=4",    u_cpu.u_regfile.x[8] === 32'd4);
        chk("s1=1",    u_cpu.u_regfile.x[9] === 32'd1);
`elsif PERF_COVER
        chk("x1=3",     u_cpu.u_regfile.x[1]  === 32'd3);
        chk("x2=5",     u_cpu.u_regfile.x[2]  === 32'd5);
        chk("x3=8(add)",u_cpu.u_regfile.x[3]  === 32'd8);
        chk("x4=2(sub)",u_cpu.u_regfile.x[4]  === 32'd2);
        chk("x5=1(and)",u_cpu.u_regfile.x[5]  === 32'd1);
        chk("x6=7(or)", u_cpu.u_regfile.x[6]  === 32'd7);
        chk("x7=6(xor)",u_cpu.u_regfile.x[7]  === 32'd6);
        chk("x8=96(sll)",u_cpu.u_regfile.x[8] === 32'd96);
        chk("x9=3(srl)", u_cpu.u_regfile.x[9] === 32'd3);
        chk("x10=-8",   u_cpu.u_regfile.x[10] === 32'hFFFFFFF8);
        chk("x11=-1(sra)",u_cpu.u_regfile.x[11] === 32'hFFFFFFFF);
        chk("x12=1(slt)",u_cpu.u_regfile.x[12] === 32'd1);
        chk("x13=0(sltu)",u_cpu.u_regfile.x[13] === 32'd0);
        chk("x14=1(slti)",u_cpu.u_regfile.x[14] === 32'd1);
        chk("x15=0(sltiu)",u_cpu.u_regfile.x[15] === 32'd0);
        chk("x16=12(xori)",u_cpu.u_regfile.x[16] === 32'd12);
        chk("x17=19(ori)", u_cpu.u_regfile.x[17] === 32'd19);
        chk("x18=3(andi)",u_cpu.u_regfile.x[18] === 32'd3);
        chk("x19=48(slli)",u_cpu.u_regfile.x[19] === 32'd48);
        chk("x20=12(srli)",u_cpu.u_regfile.x[20] === 32'd12);
        chk("x21=3(srai)", u_cpu.u_regfile.x[21] === 32'd3);
        chk("x22=-2(srai neg)",u_cpu.u_regfile.x[22] === 32'hFFFFFFFE);
        chk("x23=lui",   u_cpu.u_regfile.x[23] === 32'h12345000);
        chk("x24=lw",    u_cpu.u_regfile.x[24] === 32'h12345000);
        chk("x25=8(sentinel)",u_cpu.u_regfile.x[25] === 32'd8);
        chk("mem[0]=lui",{u_cpu.u_dmem.mem[3], u_cpu.u_dmem.mem[2],
                        u_cpu.u_dmem.mem[1], u_cpu.u_dmem.mem[0]} === 32'h12345000);
`elsif PERF_HAZARD
        chk("x1=1",   u_cpu.u_regfile.x[1]  === 32'd1);
        chk("x2=2",   u_cpu.u_regfile.x[2]  === 32'd2);
        chk("x3=3",   u_cpu.u_regfile.x[3]  === 32'd3);
        chk("x4=3",   u_cpu.u_regfile.x[4]  === 32'd3);
        chk("x5=4",   u_cpu.u_regfile.x[5]  === 32'd4);
        chk("x6=3",   u_cpu.u_regfile.x[6]  === 32'd3);
        chk("x7=4",   u_cpu.u_regfile.x[7]  === 32'd4);
        chk("x8=8",   u_cpu.u_regfile.x[8]  === 32'd8);
        chk("x9=7(ok)",u_cpu.u_regfile.x[9] === 32'd7);
        chk("x10=15", u_cpu.u_regfile.x[10] === 32'd15);
        chk("dmem[0]=3",{u_cpu.u_dmem.mem[3], u_cpu.u_dmem.mem[2],
                       u_cpu.u_dmem.mem[1], u_cpu.u_dmem.mem[0]} === 32'd3);
        chk("dmem[4]=4",{u_cpu.u_dmem.mem[7], u_cpu.u_dmem.mem[6],
                       u_cpu.u_dmem.mem[5], u_cpu.u_dmem.mem[4]} === 32'd4);
`elsif PERF_LOOP8
        // 规模档 loop_heavy（pipeline/doc/perf_analysis.md §3）：
        //   仅断言"控制流已正确收敛"——循环计数 x5 归零、dmem[0]/dmem[4] 递增 N 次。
        //   累加寄存器 x8 的期望值此处不断言：该形态命中已知缺陷 L1
        //   （累加寄存器自 RAW × load-use，见 pipeline/doc/known_issues.md），
        //   本档位仅用于 CPI 随规模收敛的测量，不作功能正确性判据。
        chk("x5=0(loop count exhausted)", u_cpu.u_regfile.x[5] === 32'd0);
        chk("dmem[0]=9", {u_cpu.u_dmem.mem[3], u_cpu.u_dmem.mem[2],
                          u_cpu.u_dmem.mem[1], u_cpu.u_dmem.mem[0]} === 32'd9);
        chk("dmem[4]=10", {u_cpu.u_dmem.mem[7], u_cpu.u_dmem.mem[6],
                           u_cpu.u_dmem.mem[5], u_cpu.u_dmem.mem[4]} === 32'd10);
`elsif PERF_LOOP32
        chk("x5=0(loop count exhausted)", u_cpu.u_regfile.x[5] === 32'd0);
        chk("dmem[0]=33", {u_cpu.u_dmem.mem[3], u_cpu.u_dmem.mem[2],
                           u_cpu.u_dmem.mem[1], u_cpu.u_dmem.mem[0]} === 32'd33);
        chk("dmem[4]=34", {u_cpu.u_dmem.mem[7], u_cpu.u_dmem.mem[6],
                           u_cpu.u_dmem.mem[5], u_cpu.u_dmem.mem[4]} === 32'd34);
`elsif PERF_LOOP128
        chk("x5=0(loop count exhausted)", u_cpu.u_regfile.x[5] === 32'd0);
        chk("dmem[0]=129", {u_cpu.u_dmem.mem[3], u_cpu.u_dmem.mem[2],
                            u_cpu.u_dmem.mem[1], u_cpu.u_dmem.mem[0]} === 32'd129);
        chk("dmem[4]=130", {u_cpu.u_dmem.mem[7], u_cpu.u_dmem.mem[6],
                            u_cpu.u_dmem.mem[5], u_cpu.u_dmem.mem[4]} === 32'd130);
`else   // PERF_TEST0（默认）
        chk("x1=1",  u_cpu.u_regfile.x[1]  === 32'd1);
        chk("x2=2",  u_cpu.u_regfile.x[2]  === 32'd2);
        chk("x3=3",  u_cpu.u_regfile.x[3]  === 32'd3);
        chk("x4=1",  u_cpu.u_regfile.x[4]  === 32'd1);
        chk("x5=3",  u_cpu.u_regfile.x[5]  === 32'd3);
        chk("x6=1",  u_cpu.u_regfile.x[6]  === 32'd1);
        chk("x10=0x10", u_cpu.u_regfile.x[10] === 32'h10);
        chk("mem[4]=3",  {u_cpu.u_dmem.mem[7], u_cpu.u_dmem.mem[6],
                        u_cpu.u_dmem.mem[5], u_cpu.u_dmem.mem[4]} === 32'd3);
        chk("mem[0x10]=1", {u_cpu.u_dmem.mem[19], u_cpu.u_dmem.mem[18],
                          u_cpu.u_dmem.mem[17], u_cpu.u_dmem.mem[16]} === 32'd1);
`endif

        // ---- 汇总：放在功能断言之后，ok 才代表整档测试通过 ----
        $display("PERF_SUMMARY: name=%0s ic=%0d f=%0d h=%0d c_total=%0d c_steady=%0d c_fixed=%0d l=%0d t=%0d ident_a=%0d ident_b=%0d residual=%0d ok=%0d",
                 `PERF_NAME, IC, F_ex, hh, C_total, C_steady, C_fixed, L, R,
                 ident_a, ident_b, residual, (err == 0));
        if (err == 0) $display("=== ALL PASS ===");
        else          $display("=== FAIL === (%0d/%0d)", err, n);
        $finish;
    end

endmodule
