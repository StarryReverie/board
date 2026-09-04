//=============================================================================
// tb_hazard_unit.v — hazard_unit 单测（doc/modules/hazard_unit.md 验收，T30）
//   前递：EX/MEM 命中 sel=1、MEM/WB 命中 sel=2、双命中 EX/MEM 优先、
//   EX/MEM 为 load 不前递、reg_write=0 不前递、rd=0 不前递；
//   load-use：idex load 命中 ID rs1/rs2 → stall，rd=0 不 stall。
//=============================================================================
`timescale 1ns/1ps

module tb_hazard_unit;

    reg  [4:0] rs1_id, rs2_id;
    reg        idex_mem_read;
    reg  [4:0] idex_rd, idex_rs1, idex_rs2;
    reg  [4:0] exmem_rd;
    reg        exmem_reg_write, exmem_mem_read;
    reg  [4:0] memwb_rd;
    reg        memwb_reg_write;
    wire [1:0] fwd_a_sel, fwd_b_sel;
    wire       stall;

    integer err = 0;
    integer n   = 0;

    hazard_unit dut (
        .rs1_id          (rs1_id),
        .rs2_id          (rs2_id),
        .idex_mem_read   (idex_mem_read),
        .idex_rd         (idex_rd),
        .idex_rs1        (idex_rs1),
        .idex_rs2        (idex_rs2),
        .exmem_rd        (exmem_rd),
        .exmem_reg_write (exmem_reg_write),
        .exmem_mem_read  (exmem_mem_read),
        .memwb_rd        (memwb_rd),
        .memwb_reg_write (memwb_reg_write),
        .fwd_a_sel       (fwd_a_sel),
        .fwd_b_sel       (fwd_b_sel),
        .stall           (stall)
    );

    task c;
        input [255:0] name;
        input         ok;
        begin
            n = n + 1;
            if (!ok) begin
                err = err + 1;
                $display("FAIL: %0d %0s (a=%0d b=%0d stall=%b)", n, name, fwd_a_sel, fwd_b_sel, stall);
            end else $display("PASS: %0d %0s (a=%0d b=%0d stall=%b)", n, name, fwd_a_sel, fwd_b_sel, stall);
        end
    endtask

    task t;
        input [4:0] e_rs1_id, e_rs2_id;
        input       e_idex_mr;
        input [4:0] e_idex_rd;
        input [4:0] e_idex_rs1, e_idex_rs2;
        input [4:0] e_exmem_rd;
        input       e_exmem_rw, e_exmem_mr;
        input [4:0] e_memwb_rd;
        input       e_memwb_rw;
        begin
            rs1_id=e_rs1_id; rs2_id=e_rs2_id; idex_mem_read=e_idex_mr;
            idex_rd=e_idex_rd; idex_rs1=e_idex_rs1; idex_rs2=e_idex_rs2;
            exmem_rd=e_exmem_rd; exmem_reg_write=e_exmem_rw; exmem_mem_read=e_exmem_mr;
            memwb_rd=e_memwb_rd; memwb_reg_write=e_memwb_rw;
            #1;
        end
    endtask

    initial begin
        t(1, 2, 0, 0, 3, 4, 5, 0, 0, 6, 0);
        c("no-match sel0", fwd_a_sel==0 && fwd_b_sel==0 && stall==0);

        // EX/MEM 命中 A 源（idex_rs1=3 匹配 exmem_rd=3）
        t(1, 2, 0, 0, 3, 4, 3, 1, 0, 6, 0);
        c("exmem->A sel1", fwd_a_sel==1 && fwd_b_sel==0);

        // MEM/WB 命中 B 源（仅 memwb_rd=4 == idex_rs2）
        t(1, 2, 0, 0, 3, 4, 9, 0, 0, 4, 1);
        c("memwb->B sel2", fwd_a_sel==0 && fwd_b_sel==2);

        // 双命中：EX/MEM 优先（两处都 rd=3）
        t(1, 2, 0, 0, 3, 4, 3, 1, 0, 3, 1);
        c("dual-hit exmem prio", fwd_a_sel==1);

        // EX/MEM 为 load：不前递（即使 rd 匹配），memwb 不匹配 → 0
        t(1, 2, 0, 0, 3, 4, 3, 1, 1, 6, 0);
        c("exmem-load no fwd", fwd_a_sel==0 && fwd_b_sel==0);

        // reg_write=0 / rd=0：不前递
        t(1, 2, 0, 0, 3, 4, 3, 0, 0, 6, 0);
        c("rw0 no fwd", fwd_a_sel==0);
        t(1, 2, 0, 0, 3, 4, 0, 1, 0, 6, 0);
        c("rd0 no fwd", fwd_a_sel==0);

        // MEM/WB 回写 rd=0 亦不前递
        t(1, 2, 0, 0, 3, 4, 9, 0, 0, 0, 1);
        c("memwb rd0 no fwd", fwd_b_sel==0);

        // load-use：EX 段 load rd=5 == ID rs1_id → stall=1（A/B 前递对非 load 无影响）
        t(5, 6, 1, 5, 1, 2, 9, 0, 0, 6, 0);
        c("load-use rs1 stall", stall==1);
        t(5, 5, 1, 5, 1, 2, 9, 0, 0, 6, 0);
        c("load-use rs2 stall", stall==1);
        // rd=0 的 load 不 stall
        t(5, 6, 1, 0, 1, 2, 9, 0, 0, 6, 0);
        c("load rd0 no stall", stall==0);
        // 非 load 不 stall
        t(5, 6, 0, 5, 1, 2, 9, 0, 0, 6, 0);
        c("non-load no stall", stall==0);

        if (err == 0) $display("=== ALL PASS ===");
        else          $display("=== FAIL === (%0d/%0d)", err, n);
        $finish;
    end

endmodule
