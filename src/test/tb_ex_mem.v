//=============================================================================
// tb_ex_mem.v — ex_mem 单测（doc/modules/ex_mem.md 验收，T30）
//   rst 清零；沿沿打入（全部字段）。
//=============================================================================
`timescale 1ns/1ps

module tb_ex_mem;

    reg        clk = 0;
    reg        rst = 1;
    reg  [31:0] alu_result;
    reg  [31:0] wdata;
    reg  [4:0]  rd;
    reg         mem_read, mem_write, mem_to_reg, reg_write;

    wire [31:0] exmem_alu_result, exmem_wdata;
    wire [4:0]  exmem_rd;
    wire        exmem_mem_read, exmem_mem_write, exmem_mem_to_reg, exmem_reg_write;

    integer err = 0;
    integer n   = 0;

    ex_mem dut (
        .clk            (clk),
        .rst            (rst),
        .alu_result     (alu_result),
        .wdata          (wdata),
        .rd             (rd),
        .mem_read       (mem_read),
        .mem_write      (mem_write),
        .mem_to_reg     (mem_to_reg),
        .reg_write      (reg_write),
        .exmem_alu_result(exmem_alu_result),
        .exmem_wdata    (exmem_wdata),
        .exmem_rd       (exmem_rd),
        .exmem_mem_read (exmem_mem_read),
        .exmem_mem_write(exmem_mem_write),
        .exmem_mem_to_reg(exmem_mem_to_reg),
        .exmem_reg_write(exmem_reg_write)
    );

    always #5 clk = ~clk;

    task c;
        input [255:0] name;
        input         ok;
        begin
            n = n + 1;
            if (!ok) begin
                err = err + 1;
                $display("FAIL: %0d %0s", n, name);
            end else $display("PASS: %0d %0s", n, name);
        end
    endtask

    task zero_ok;
        begin
            c("all-zero", exmem_alu_result==0 && exmem_wdata==0 && exmem_rd==0 &&
                          exmem_mem_read==0 && exmem_mem_write==0 &&
                          exmem_mem_to_reg==0 && exmem_reg_write==0);
        end
    endtask

    task latch_ok;
        begin
            c("latch-all", exmem_alu_result==alu_result && exmem_wdata==wdata && exmem_rd==rd &&
                           exmem_mem_read==mem_read && exmem_mem_write==mem_write &&
                           exmem_mem_to_reg==mem_to_reg && exmem_reg_write==reg_write);
        end
    endtask

    initial begin
        alu_result=0; wdata=0; rd=0; mem_read=0; mem_write=0; mem_to_reg=0; reg_write=0;
        #2 zero_ok();
        rst = 0;
        alu_result=32'hDEADBEEF; wdata=32'h12345678; rd=5'd15;
        mem_read=1; mem_write=1; mem_to_reg=1; reg_write=1;
        @(posedge clk);
        #1 latch_ok();
        alu_result=32'h00000001; wdata=32'h00000002; rd=5'd1;
        mem_read=0; mem_write=0; mem_to_reg=0; reg_write=0;
        @(posedge clk);
        #1 latch_ok();
        // 异步复位
        rst = 1;
        #2 zero_ok();

        if (err == 0) $display("=== ALL PASS ===");
        else          $display("=== FAIL === (%0d/%0d)", err, n);
        $finish;
    end

endmodule
