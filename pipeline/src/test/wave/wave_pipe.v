//=============================================================================
// wave_pipe.v — 实验一关键波形采样 TB（plan.md 四项仿真）
//   与 run_tb.ps1 的 tb_*.v 回归集隔离：位于 test/wave/ 子目录、不以 tb_ 开头，
//   由 scripts/run_wave.ps1 单独编译运行；RTL 零改动（信号经 u_cpu 层次引用）。
//   三段程序：
//     cover    = instr_cover_rom.hex  → 项1 五级流水线运行总览
//     hazard   = hazard_cover_rom.hex → 项2 前递(场景1)/项3 load-use/项4 分支冲刷
//     priority = fwd_priority_rom.hex → 项2 双命中 EX/MEM 优先级
//   每拍（posedge 后 #1）采样全部信号：
//     * wave_<phase>.csv  逐拍数值（渲染器输入）
//     * wave_<phase>.vcd  标准 VCD（xsim $dumpvars 只写初值，故 TB 侧自写）
//     * wave_marks.csv    四项关键拍号
//   内嵌验收断言（与 tb_prog_cover / tb_prog_hazard 同源 + priority 新场景）。
//=============================================================================
`timescale 1ns/1ps

module wave_pipe;

    reg        clk = 0;
    reg        rst = 1;
    reg        imem_wen = 0;
    reg [31:0] imem_waddr = 0, imem_wdata = 0;
    wire       cs_mmio;
    wire [1:0] reg_off;
    wire       mmio_we;
    wire [31:0] mmio_wdata;

    integer err = 0;
    integer n   = 0;
    integer i;
    integer cyc;

    pipeline_top u_cpu (
        .clk (clk), .rst (rst),
        .imem_wen(imem_wen), .imem_waddr(imem_waddr), .imem_wdata(imem_wdata),
        .cs_mmio(cs_mmio), .reg_off(reg_off), .mmio_we(mmio_we),
        .mmio_wdata(mmio_wdata), .mmio_rdata(32'b0)
    );

    always #5 clk = ~clk;

    // ---- 采样信号别名（全部为 pipeline_top 顶层 wire / execute 内部前递值）----
    wire [31:0] w_pc      = u_cpu.pc;
    wire [31:0] w_if      = u_cpu.inst;
    wire [31:0] w_id      = u_cpu.ifid_inst;
    wire [31:0] w_idex_pc = u_cpu.idex_pc;
    wire [4:0]  w_idex_rd = u_cpu.idex_rd;
    wire [3:0]  w_idex_op = u_cpu.idex_alu_op;
    wire [31:0] w_idex_rs1= u_cpu.idex_rs1_data;
    wire [31:0] w_alu_a   = u_cpu.u_execute.alu_a;
    wire [31:0] w_alu_b   = u_cpu.u_execute.alu_b;
    wire [31:0] w_alu_out = u_cpu.alu_out;
    wire [31:0] w_exmem   = u_cpu.exmem_alu_result;
    wire [4:0]  w_memwb_rd= u_cpu.memwb_rd;
    wire [31:0] w_memwb_d = u_cpu.memwb_rdata;
    wire        w_wb_we   = u_cpu.wb_we;
    wire [4:0]  w_wb_rd   = u_cpu.wb_rd;
    wire [31:0] w_wb_data = u_cpu.wb_data;
    wire        w_stall   = u_cpu.stall;
    wire        w_br      = u_cpu.br_taken;
    wire [31:0] w_br_tgt  = u_cpu.br_target;
    wire [1:0]  w_fa      = u_cpu.fwd_a_sel;
    wire [1:0]  w_fb      = u_cpu.fwd_b_sel;

    // ---- 影子级指令字（IF/ID/EX/MEM/WB；气泡置 0）----
    reg [31:0] ex_inst, mem_inst, wb_inst;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            ex_inst  <= 32'b0;
            mem_inst <= 32'b0;
            wb_inst  <= 32'b0;
        end else begin
            ex_inst  <= (w_stall | w_br) ? 32'b0 : w_id;
            mem_inst <= ex_inst;
            wb_inst  <= mem_inst;
        end
    end

    task c;
        input [255:0] name;
        input         ok;
        begin
            n = n + 1;
            if (!ok) begin err = err + 1; $display("FAIL: %0d %0s", n, name); end
            else $display("PASS: %0d %0s", n, name);
        end
    endtask

    // ---- CSV ----
    task csv_hdr;
        input integer fd;
        begin
            $fwrite(fd, "cycle,pc,if_inst,id_inst,ex_inst,mem_inst,wb_inst,idex_pc,idex_rd,idex_op,idex_rs1,alu_a,alu_b,alu_out,exmem_alu,memwb_rd,memwb_rdata,wb_we,wb_rd,wb_data,stall,br_taken,br_target,fwd_a,fwd_b\n");
        end
    endtask

    task csv_row;
        input integer fd;
        input integer cy;
        begin
            $fwrite(fd, "%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d\n",
                cy, w_pc, w_if, w_id, ex_inst, mem_inst, wb_inst, w_idex_pc,
                w_idex_rd, w_idex_op, w_idex_rs1, w_alu_a, w_alu_b, w_alu_out,
                w_exmem, w_memwb_rd, w_memwb_d, w_wb_we, w_wb_rd, w_wb_data,
                w_stall, w_br, w_br_tgt, w_fa, w_fb);
        end
    endtask

    // ---- VCD ----
    task vcd_hdr;
        input integer fd;
        begin
            $fwrite(fd, "$date\n  2026-09-13\n$end\n");
            $fwrite(fd, "$version\n  wave_pipe tb-sampled\n$end\n");
            $fwrite(fd, "$timescale 1ns $end\n");
            $fwrite(fd, "$scope module wave $end\n");
            $fwrite(fd, "$var wire 32 a pc $end\n");
            $fwrite(fd, "$var wire 32 b if_inst $end\n");
            $fwrite(fd, "$var wire 32 c id_inst $end\n");
            $fwrite(fd, "$var wire 32 d ex_inst $end\n");
            $fwrite(fd, "$var wire 32 e mem_inst $end\n");
            $fwrite(fd, "$var wire 32 f wb_inst $end\n");
            $fwrite(fd, "$var wire 32 g idex_pc $end\n");
            $fwrite(fd, "$var wire 5 h idex_rd $end\n");
            $fwrite(fd, "$var wire 4 i idex_op $end\n");
            $fwrite(fd, "$var wire 32 j idex_rs1 $end\n");
            $fwrite(fd, "$var wire 32 k alu_a $end\n");
            $fwrite(fd, "$var wire 32 l alu_b $end\n");
            $fwrite(fd, "$var wire 32 m alu_out $end\n");
            $fwrite(fd, "$var wire 32 n exmem_alu $end\n");
            $fwrite(fd, "$var wire 5 o memwb_rd $end\n");
            $fwrite(fd, "$var wire 32 p memwb_rdata $end\n");
            $fwrite(fd, "$var wire 1 q wb_we $end\n");
            $fwrite(fd, "$var wire 5 r wb_rd $end\n");
            $fwrite(fd, "$var wire 32 s wb_data $end\n");
            $fwrite(fd, "$var wire 1 t stall $end\n");
            $fwrite(fd, "$var wire 1 u br_taken $end\n");
            $fwrite(fd, "$var wire 32 v br_target $end\n");
            $fwrite(fd, "$var wire 2 w fwd_a_sel $end\n");
            $fwrite(fd, "$var wire 2 x fwd_b_sel $end\n");
            $fwrite(fd, "$var wire 1 y clk $end\n");
            $fwrite(fd, "$upscope $end\n$enddefinitions $end\n");
        end
    endtask

    task vcd_row;
        input integer fd;
        input integer cy;
        begin
            $fwrite(fd, "#%0d\n1y\n", $time - 1);
            $fwrite(fd, "#%0d\n", $time);
            $fwrite(fd, "b%b a\n", w_pc);
            $fwrite(fd, "b%b b\n", w_if);
            $fwrite(fd, "b%b c\n", w_id);
            $fwrite(fd, "b%b d\n", ex_inst);
            $fwrite(fd, "b%b e\n", mem_inst);
            $fwrite(fd, "b%b f\n", wb_inst);
            $fwrite(fd, "b%b g\n", w_idex_pc);
            $fwrite(fd, "b%b h\n", w_idex_rd);
            $fwrite(fd, "b%b i\n", w_idex_op);
            $fwrite(fd, "b%b j\n", w_idex_rs1);
            $fwrite(fd, "b%b k\n", w_alu_a);
            $fwrite(fd, "b%b l\n", w_alu_b);
            $fwrite(fd, "b%b m\n", w_alu_out);
            $fwrite(fd, "b%b n\n", w_exmem);
            $fwrite(fd, "b%b o\n", w_memwb_rd);
            $fwrite(fd, "b%b p\n", w_memwb_d);
            $fwrite(fd, "%b q\n", w_wb_we);
            $fwrite(fd, "b%b r\n", w_wb_rd);
            $fwrite(fd, "b%b s\n", w_wb_data);
            $fwrite(fd, "%b t\n", w_stall);
            $fwrite(fd, "%b u\n", w_br);
            $fwrite(fd, "b%b v\n", w_br_tgt);
            $fwrite(fd, "b%b w\n", w_fa);
            $fwrite(fd, "b%b x\n", w_fb);
            $fwrite(fd, "#%0d\n0y\n", $time + 4);
        end
    endtask

    integer fc, fv, fm;
    integer m1, m2, m2b, m3, m4;

    initial begin
        imem_wen = 0;
        m1 = -1; m2 = -1; m2b = -1; m3 = -1; m4 = -1;
        fm = $fopen("wave_marks.csv", "w");
        $fwrite(fm, "item,phase,cycle,desc\n");

        // ================= 阶段 1：instr_cover（项1）=================
        for (i = 0; i < 4096; i = i + 1) u_cpu.u_imem.mem[i] = 8'h00;
        $readmemh("instr_cover_rom.hex", u_cpu.u_imem.mem);
        fc = $fopen("wave_cover.csv", "w"); csv_hdr(fc);
        fv = $fopen("wave_cover.vcd", "w"); vcd_hdr(fv);
        rst = 1; repeat (3) @(posedge clk); rst = 0;
        for (cyc = 1; cyc <= 80; cyc = cyc + 1) begin
            @(posedge clk); #1;
            csv_row(fc, cyc);
            vcd_row(fv, cyc);
            if (m1 < 0 && w_wb_we) begin
                m1 = cyc;
                $fwrite(fm, "1,cover,%0d,first WB valid (5 stages filled)\n", cyc);
                $display("WAVE_TIME: item=1 cycle=%0d time=%0d", cyc, $time);
            end
        end
        $fclose(fc); $fclose(fv);

        c("cover x1=3",     u_cpu.u_regfile.x[1]  === 32'd3);
        c("cover x2=5",     u_cpu.u_regfile.x[2]  === 32'd5);
        c("cover x3=8",     u_cpu.u_regfile.x[3]  === 32'd8);
        c("cover x4=2",     u_cpu.u_regfile.x[4]  === 32'd2);
        c("cover x5=1",     u_cpu.u_regfile.x[5]  === 32'd1);
        c("cover x6=7",     u_cpu.u_regfile.x[6]  === 32'd7);
        c("cover x7=6",     u_cpu.u_regfile.x[7]  === 32'd6);
        c("cover x8=96",    u_cpu.u_regfile.x[8]  === 32'd96);
        c("cover x9=3",     u_cpu.u_regfile.x[9]  === 32'd3);
        c("cover x10=-8",   u_cpu.u_regfile.x[10] === 32'hFFFFFFF8);
        c("cover x11=-1",   u_cpu.u_regfile.x[11] === 32'hFFFFFFFF);
        c("cover x12=1",    u_cpu.u_regfile.x[12] === 32'd1);
        c("cover x13=0",    u_cpu.u_regfile.x[13] === 32'd0);
        c("cover x14=1",    u_cpu.u_regfile.x[14] === 32'd1);
        c("cover x15=0",    u_cpu.u_regfile.x[15] === 32'd0);
        c("cover x16=12",   u_cpu.u_regfile.x[16] === 32'd12);
        c("cover x17=19",   u_cpu.u_regfile.x[17] === 32'd19);
        c("cover x18=3",    u_cpu.u_regfile.x[18] === 32'd3);
        c("cover x19=48",   u_cpu.u_regfile.x[19] === 32'd48);
        c("cover x20=12",   u_cpu.u_regfile.x[20] === 32'd12);
        c("cover x21=3",    u_cpu.u_regfile.x[21] === 32'd3);
        c("cover x22=-2",   u_cpu.u_regfile.x[22] === 32'hFFFFFFFE);
        c("cover x23=lui",  u_cpu.u_regfile.x[23] === 32'h12345000);
        c("cover x24=lw",   u_cpu.u_regfile.x[24] === 32'h12345000);
        c("cover x25=8",    u_cpu.u_regfile.x[25] === 32'd8);
        c("cover mem[0]",   {u_cpu.u_dmem.mem[3], u_cpu.u_dmem.mem[2],
                             u_cpu.u_dmem.mem[1], u_cpu.u_dmem.mem[0]} === 32'h12345000);

        // ================= 阶段 2：hazard_cover（项2/3/4）=================
        for (i = 0; i < 4096; i = i + 1) u_cpu.u_imem.mem[i] = 8'h00;
        $readmemh("hazard_cover_rom.hex", u_cpu.u_imem.mem);
        fc = $fopen("wave_hazard.csv", "w"); csv_hdr(fc);
        fv = $fopen("wave_hazard.vcd", "w"); vcd_hdr(fv);
        rst = 1; repeat (3) @(posedge clk); rst = 0;
        for (cyc = 1; cyc <= 80; cyc = cyc + 1) begin
            @(posedge clk); #1;
            csv_row(fc, cyc);
            vcd_row(fv, cyc);
            if (m2 < 0 && (w_fa == 2'b01) && (w_fb == 2'b10)) begin
                m2 = cyc;
                $fwrite(fm, "2,hazard,%0d,scene1 add x3: fwdA=EX/MEM fwdB=MEM/WB\n", cyc);
                $display("WAVE_TIME: item=2 cycle=%0d time=%0d", cyc, $time);
            end
            if (m3 < 0 && w_stall) begin
                m3 = cyc;
                $fwrite(fm, "3,hazard,%0d,load-use stall pulse\n", cyc);
                $display("WAVE_TIME: item=3 cycle=%0d time=%0d", cyc, $time);
            end
            if (m4 < 0 && w_br) begin
                m4 = cyc;
                $fwrite(fm, "4,hazard,%0d,beq taken (flush)\n", cyc);
                $display("WAVE_TIME: item=4 cycle=%0d time=%0d", cyc, $time);
            end
        end
        $fclose(fc); $fclose(fv);

        c("hazard x1=1",   u_cpu.u_regfile.x[1]  === 32'd1);
        c("hazard x2=2",   u_cpu.u_regfile.x[2]  === 32'd2);
        c("hazard x3=3",   u_cpu.u_regfile.x[3]  === 32'd3);
        c("hazard x4=3",   u_cpu.u_regfile.x[4]  === 32'd3);
        c("hazard x5=4",   u_cpu.u_regfile.x[5]  === 32'd4);
        c("hazard x6=3",   u_cpu.u_regfile.x[6]  === 32'd3);
        c("hazard x7=4",   u_cpu.u_regfile.x[7]  === 32'd4);
        c("hazard x8=8",   u_cpu.u_regfile.x[8]  === 32'd8);
        c("hazard x9=7",   u_cpu.u_regfile.x[9]  === 32'd7);
        c("hazard x10=15", u_cpu.u_regfile.x[10] === 32'd15);
        c("hazard dmem[0]", {u_cpu.u_dmem.mem[3], u_cpu.u_dmem.mem[2],
                             u_cpu.u_dmem.mem[1], u_cpu.u_dmem.mem[0]} === 32'd3);
        c("hazard dmem[4]", {u_cpu.u_dmem.mem[7], u_cpu.u_dmem.mem[6],
                             u_cpu.u_dmem.mem[5], u_cpu.u_dmem.mem[4]} === 32'd4);

        // ================= 阶段 3：fwd_priority（项2 优先级）=================
        for (i = 0; i < 4096; i = i + 1) u_cpu.u_imem.mem[i] = 8'h00;
        $readmemh("fwd_priority_rom.hex", u_cpu.u_imem.mem);
        fc = $fopen("wave_priority.csv", "w"); csv_hdr(fc);
        fv = $fopen("wave_priority.vcd", "w"); vcd_hdr(fv);
        rst = 1; repeat (3) @(posedge clk); rst = 0;
        for (cyc = 1; cyc <= 60; cyc = cyc + 1) begin
            @(posedge clk); #1;
            csv_row(fc, cyc);
            vcd_row(fv, cyc);
            if (m2b < 0 && (w_fa == 2'b01) && (w_memwb_rd == 5'd11)) begin
                m2b = cyc;
                $fwrite(fm, "2b,priority,%0d,dual-hit x11: pick EX/MEM over MEM/WB\n", cyc);
                $display("WAVE_TIME: item=2b cycle=%0d time=%0d", cyc, $time);
            end
        end
        $fclose(fc); $fclose(fv);

        c("prio x11=2", u_cpu.u_regfile.x[11] === 32'd2);
        c("prio x12=2 (EX/MEM priority)", u_cpu.u_regfile.x[12] === 32'd2);
        c("prio x13=4 (MEM/WB fwd)", u_cpu.u_regfile.x[13] === 32'd4);
        c("prio x14=0", u_cpu.u_regfile.x[14] === 32'd0);

        $display("WAVE_MARKS: item1=%0d item2=%0d item2b=%0d item3=%0d item4=%0d",
                 m1, m2, m2b, m3, m4);
        $fclose(fm);

        if (err == 0) $display("=== ALL PASS ===");
        else          $display("=== FAIL === (%0d/%0d)", err, n);
        $finish;
    end

endmodule
