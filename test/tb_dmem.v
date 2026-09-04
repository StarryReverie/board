//=============================================================================
// tb_dmem.v — dmem 单测（doc/modules/dmem.md 验收，T30）
//   sw 后（下拍）lw 同址读回一致；wmask 字节写；组合读旧值/写后新值语义；
//   越界读返回 0、写丢弃；无复位（不复位存储）。
//=============================================================================
`timescale 1ns/1ps

module tb_dmem;

    reg        clk = 0;
    reg  [31:0] addr;
    reg  [31:0] wdata;
    reg  [3:0]  wmask;
    reg         we;
    wire [31:0] rdata;

    integer err = 0;
    integer n   = 0;

    dmem dut (
        .clk   (clk),
        .addr  (addr),
        .wdata (wdata),
        .wmask (wmask),
        .we    (we),
        .rdata (rdata)
    );

    always #5 clk = ~clk;

    task c;
        input [255:0] name;
        input [31:0]  exp;
        begin
            n = n + 1;
            if (rdata !== exp) begin
                err = err + 1;
                $display("FAIL: %0d %0s rdata=%h exp=%h", n, name, rdata, exp);
            end else $display("PASS: %0d %0s rdata=%h", n, name, rdata);
        end
    endtask

    initial begin
        addr = 0; wdata = 0; wmask = 4'b1111; we = 0;

        // 准备 0xC 处旧值 0x11111111（先全字写）
        we = 1; addr = 32'h0000000C; wdata = 32'h11111111;
        @(posedge clk);
        #1 we = 0;
        #1 c("preload old", 32'h11111111);

        // 同拍读=旧值（写尚未生效，sw/lw 须隔拍）
        we = 1; wdata = 32'h22222222;
        #1 c("same-cycle old", 32'h11111111);
        @(posedge clk);              // 写生效
        #1 we = 0;
        #1 c("after-write new", 32'h22222222);

        // 全字写 + 小端读回
        we = 1; addr = 32'h00000000; wdata = 32'h11223344;
        @(posedge clk);
        #1 we = 0;
        #1 c("word little-endian", 32'h11223344);

        // wmask 字节写：0x8 处置 0 后写低 2 字节
        we = 1; addr = 32'h00000008; wdata = 32'h00000000;
        @(posedge clk);
        #1 wdata = 32'hDEADBEEF; wmask = 4'b0011;
        @(posedge clk);
        #1 we = 0; wmask = 4'b1111;
        #1 c("wmask low2", 32'h0000BEEF);

        // 越界：读 0、写丢弃（不回 X 即可）
        addr = 32'h00005000;
        #1 c("oob read 0", 32'h00000000);
        we = 1; wdata = 32'hCAFEBABE; addr = 32'h00005000;
        @(posedge clk);
        #1 we = 0; addr = 32'h00005004;
        #1 c("oob write dropped", 32'h00000000);

        if (err == 0) $display("=== ALL PASS ===");
        else          $display("=== FAIL === (%0d/%0d)", err, n);
        $finish;
    end

endmodule
