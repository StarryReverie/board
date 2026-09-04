//=============================================================================
// tb_regfile.v — regfile 单测（doc/modules/regfile.md 验收，T30）
//   复位全 0；写后读一致；x0 读恒 0/写 x0 无效；读旁路（write-first）：
//   当拍 we=1 且写口==读口时返回 wdata（不等时钟沿）。
//=============================================================================
`timescale 1ns/1ps

module tb_regfile;

    reg        clk = 0;
    reg        rst = 1;
    reg  [4:0] raddr1;
    reg  [4:0] raddr2;
    reg  [4:0] waddr;
    reg  [31:0] wdata;
    reg        we;
    wire [31:0] rdata1;
    wire [31:0] rdata2;

    integer err = 0;
    integer n   = 0;

    regfile dut (
        .clk    (clk),
        .rst    (rst),
        .raddr1 (raddr1),
        .raddr2 (raddr2),
        .waddr  (waddr),
        .wdata  (wdata),
        .we     (we),
        .rdata1 (rdata1),
        .rdata2 (rdata2)
    );

    always #5 clk = ~clk;

    task chk;
        input [31:0] e1;
        input [31:0] e2;
        input [255:0] name;   // 仅用于可读性
        begin
            n = n + 1;
            if (rdata1 !== e1 || rdata2 !== e2) begin
                err = err + 1;
                $display("FAIL: %0d %0s rdata1=%h rdata2=%h exp1=%h exp2=%h", n, name, rdata1, rdata2, e1, e2);
            end else begin
                $display("PASS: %0d %0s rdata1=%h rdata2=%h", n, name, rdata1, rdata2);
            end
        end
    endtask

    initial begin
        raddr1 = 0; raddr2 = 0; waddr = 0; wdata = 0; we = 0;

        // 复位后全 0
        #2 rst = 0;
        #1 raddr1 = 5'd5; raddr2 = 5'd7;
        #1 chk(32'h0, 32'h0, "reset-zero");

        // 写 x5 = 0x12345678（沿后生效；撤 we 须错开沿，避免竞争）
        we = 1; waddr = 5'd5; wdata = 32'h12345678;
        @(posedge clk);
        #1 we = 0;
        #1 raddr1 = 5'd5;
        #1 chk(32'h12345678, 32'h0, "write-x5-read");

        // 写 x7 后双口读
        we = 1; waddr = 5'd7; wdata = 32'hA5A5A5A5;
        @(posedge clk);
        #1 we = 0;
        #1 raddr1 = 5'd7; raddr2 = 5'd5;
        #1 chk(32'hA5A5A5A5, 32'h12345678, "dual-read");

        // 读旁路：we=1 且 waddr==raddr1（当拍、未到沿）→ 返回 wdata
        we = 1; waddr = 5'd9; wdata = 32'hBEEFBEEF;
        raddr1 = 5'd9; raddr2 = 5'd5;
        #1 chk(32'hBEEFBEEF, 32'h12345678, "bypass-write-first");
        // 旁路数据在沿后被真正写入（继续读仍一致）
        @(posedge clk);
        #1 we = 0;
        #1 chk(32'hBEEFBEEF, 32'h12345678, "bypass-then-store");

        // 写 x0 无效：we=1 waddr=0，读 x0 恒 0；且不污染
        we = 1; waddr = 5'd0; wdata = 32'hFFFFFFFF;
        raddr1 = 5'd0;
        #1 chk(32'h0, 32'h12345678, "x0-write-ignored-read0");
        @(posedge clk);
        #1 we = 0;
        #1 chk(32'h0, 32'h12345678, "x0-still-zero");

        // 异步复位清全 0
        rst = 1;
        raddr1 = 5'd5; raddr2 = 5'd9;
        #2 chk(32'h0, 32'h0, "async-reset-clear");

        if (err == 0) $display("=== ALL PASS ===");
        else          $display("=== FAIL === (%0d/%0d)", err, n);
        $finish;
    end

endmodule
