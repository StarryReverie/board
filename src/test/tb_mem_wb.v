//=============================================================================
// tb_mem_wb.v — mem_wb 单测（doc/modules/mem_wb.md 验收，T30）
//   rst 清零；沿沿打入（含 lw 读回数据 rdata）。
//=============================================================================
`timescale 1ns/1ps

module tb_mem_wb;

    reg        clk = 0;
    reg        rst = 1;
    reg  [31:0] rdata;
    reg  [31:0] alu_result;
    reg  [4:0]  rd;
    reg         mem_to_reg, reg_write;

    wire [31:0] memwb_rdata, memwb_alu_result;
    wire [4:0]  memwb_rd;
    wire        memwb_mem_to_reg, memwb_reg_write;

    integer err = 0;
    integer n   = 0;

    mem_wb dut (
        .clk            (clk),
        .rst            (rst),
        .rdata          (rdata),
        .alu_result     (alu_result),
        .rd             (rd),
        .mem_to_reg     (mem_to_reg),
        .reg_write      (reg_write),
        .memwb_rdata    (memwb_rdata),
        .memwb_alu_result(memwb_alu_result),
        .memwb_rd       (memwb_rd),
        .memwb_mem_to_reg(memwb_mem_to_reg),
        .memwb_reg_write(memwb_reg_write)
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
            c("all-zero", memwb_rdata==0 && memwb_alu_result==0 && memwb_rd==0 &&
                          memwb_mem_to_reg==0 && memwb_reg_write==0);
        end
    endtask

    task latch_ok;
        begin
            c("latch-all", memwb_rdata==rdata && memwb_alu_result==alu_result &&
                           memwb_rd==rd && memwb_mem_to_reg==mem_to_reg &&
                           memwb_reg_write==reg_write);
        end
    endtask

    initial begin
        rdata=0; alu_result=0; rd=0; mem_to_reg=0; reg_write=0;
        #2 zero_ok();
        rst = 0;
        rdata=32'h0A0B0C0D; alu_result=32'h10000000; rd=5'd20; mem_to_reg=1; reg_write=1;
        @(posedge clk);
        #1 latch_ok();
        rdata=32'h00000000; alu_result=32'h00000004; rd=5'd0; mem_to_reg=0; reg_write=0;
        @(posedge clk);
        #1 latch_ok();
        rst = 1;
        #2 zero_ok();

        if (err == 0) $display("=== ALL PASS ===");
        else          $display("=== FAIL === (%0d/%0d)", err, n);
        $finish;
    end

endmodule
