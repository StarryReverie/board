//=============================================================================
// tb_wb.v — wb 单测（doc/modules/wb.md 验收，T30）
//   mem_to_reg=0 → alu_result；=1 → rdata；rd/we 直通。
//=============================================================================
`timescale 1ns/1ps

module tb_wb;

    reg  [4:0]  memwb_rd;
    reg  [31:0] memwb_alu_result;
    reg  [31:0] memwb_rdata;
    reg         memwb_mem_to_reg;
    reg         memwb_reg_write;
    wire [4:0]  wb_rd;
    wire [31:0] wb_data;
    wire        wb_we;

    integer err = 0;
    integer n   = 0;

    wb dut (
        .memwb_rd         (memwb_rd),
        .memwb_alu_result (memwb_alu_result),
        .memwb_rdata      (memwb_rdata),
        .memwb_mem_to_reg (memwb_mem_to_reg),
        .memwb_reg_write  (memwb_reg_write),
        .wb_rd            (wb_rd),
        .wb_data          (wb_data),
        .wb_we            (wb_we)
    );

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

    initial begin
        memwb_rd = 5'd0; memwb_alu_result = 0; memwb_rdata = 0;
        memwb_mem_to_reg = 0; memwb_reg_write = 0;

        memwb_rd = 5'd12; memwb_alu_result = 32'hA0A0A0A0; memwb_rdata = 32'hB0B0B0B0;
        memwb_mem_to_reg = 0; memwb_reg_write = 1;
        #1 c("sel alu", wb_data==32'hA0A0A0A0);
        c("we/rd passthru", wb_we==1 && wb_rd==5'd12);

        memwb_mem_to_reg = 1; memwb_reg_write = 0;
        #1 c("sel rdata", wb_data==32'hB0B0B0B0);
        c("we clear", wb_we==0);

        memwb_alu_result = 32'h12345678; memwb_rdata = 32'h87654321;
        memwb_mem_to_reg = 0;
        #1 c("sel alu again", wb_data==32'h12345678);

        if (err == 0) $display("=== ALL PASS ===");
        else          $display("=== FAIL === (%0d/%0d)", err, n);
        $finish;
    end

endmodule
