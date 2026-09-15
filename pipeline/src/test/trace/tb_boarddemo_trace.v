`timescale 1ns/1ps
//=============================================================================
// tb_boarddemo_trace.v — 逐拍 trace 上板验收程序（演示数字 / 报告证据来源）
//   统计 exp1_board_demo 真实触发的前递/停顿/分支/访存事件，每拍打印一行 TRC。
//   运行：powershell -File pipeline/src/scripts/run_trace_bd.ps1
//         （该 runner 编译本 TB、抓 stdout 到 build/exp1_trace/trace_bd.txt 并汇总）
//   说明：本 TB 不在回归集合内（run_tb.ps1 只收 test 根目录 tb_*.v）。
//=============================================================================
module tb_boarddemo_trace;
    reg clk = 0, rst = 1;
    reg imem_wen = 0;
    reg [31:0] imem_waddr = 0, imem_wdata = 0;
    wire cs_mmio, mmio_we;
    wire [1:0] reg_off;
    wire [31:0] mmio_wdata;
    integer i, e;
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
        for (i = 0; i < 4096; i = i + 1) u_cpu.u_imem.mem[i] = 8'h00;
        $readmemh("exp1_board_demo_rom.hex", u_cpu.u_imem.mem);
        repeat (3) @(posedge clk);
        rst = 0;
        for (e = 1; e <= 160; e = e + 1) begin
            @(posedge clk); #1;
            // 只统计"EX 槽有真实指令"的拍（控制字非全零）
            if (u_cpu.idex_reg_write | u_cpu.idex_mem_write | u_cpu.idex_mem_read |
                u_cpu.idex_bne | (u_cpu.idex_jump != 2'b00) |
                (u_cpu.idex_alu_op != 4'b0000) |
                (u_cpu.idex_src_a != 2'b00) | (u_cpu.idex_src_b != 2'b00)) begin
                $display("TRC: e=%0d pc=%02h fa=%0d fb=%0d stall=%0b br=%0b mw=%0b mr=%0b rw=%0b",
                         e, u_cpu.idex_pc, u_cpu.u_execute.fwd_a_sel, u_cpu.u_execute.fwd_b_sel,
                         u_cpu.stall, u_cpu.br_taken, u_cpu.idex_mem_write,
                         u_cpu.idex_mem_read, u_cpu.idex_reg_write);
            end
        end
        $display("TRC: dmem0=%0d x8=%0d x18=%0d",
                 {u_cpu.u_dmem.mem[3],u_cpu.u_dmem.mem[2],u_cpu.u_dmem.mem[1],u_cpu.u_dmem.mem[0]},
                 u_cpu.u_regfile.x[8], u_cpu.u_regfile.x[18]);
        $finish;
    end
endmodule
