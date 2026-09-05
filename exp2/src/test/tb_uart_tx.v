//=============================================================================
// tb_uart_tx.v — uart_tx 单测（exp2 U10，doc/modules/uart_tx.md 验收）
//   CPB=8：clk_en 每 8 clk 一个脉冲（1 bit 时间=80ns）
//   帧期望（0x53=0101_0011，LSB 先）：start=0, d0..d7=1,1,0,0,1,0,1,0, stop=1
//   采样方式：clk_en 脉冲沿后 2ns 采样（取新区间稳态值）
//=============================================================================
`timescale 1ns/1ps

module tb_uart_tx;

    localparam CPB = 8;

    reg        clk = 0;
    reg        rst = 1;
    reg        clk_en = 0;
    reg        start = 0;
    reg  [7:0] data = 0;
    wire       busy, done, tx;

    integer err = 0;
    integer n   = 0;
    integer i;

    // ---- 分频：每 CPB 个 clk 产生 1 个 clk_en 脉冲 ----
    reg [15:0] cnt = 0;
    always @(posedge clk) begin
        if (rst) begin
            cnt    <= 0;
            clk_en <= 0;
        end else if (cnt == CPB-1) begin
            cnt    <= 0;
            clk_en <= 1'b1;
        end else begin
            cnt    <= cnt + 1;
            clk_en <= 1'b0;
        end
    end

    always #5 clk = ~clk;

    uart_tx #(.CLKS_PER_BIT(CPB)) dut (
        .clk(clk), .rst(rst), .clk_en(clk_en),
        .start(start), .data(data), .busy(busy), .done(done), .tx(tx)
    );

    task c;
        input [255:0] name;
        input         ok;
        begin
            n = n + 1;
            if (!ok) begin err = err + 1; $display("FAIL: %0d %0s", n, name); end
            else $display("PASS: %0d %0s", n, name);
        end
    endtask

    // ---- 帧采样（沿后 2ns 读稳态；busy 窗口内取 10 个 bit 值）----
    reg [7:0] stream [0:15];
    integer   sidx = 0;
    reg       done_seen = 0;
    always begin
        @(posedge clk);
        #2;
        if (!rst && clk_en && done) done_seen <= 1;
        if (!rst && clk_en && busy && sidx < 10) begin
            stream[sidx] <= tx;
            sidx <= sidx + 1;
        end
    end

    initial begin
        repeat (4) @(posedge clk);
        rst = 0;
        #1 c("reset idle", tx===1'b1 && busy===0 && done===0);

        // ---- 字符 0x53 ----
        data = 8'h53;
        start = 1;
        while (!busy) @(posedge clk);     // 等待接受
        start = 0;
        while (busy) @(posedge clk);      // 等待帧结束
        #1 c("frame done & idle", busy===0 && tx===1'b1);
        c("done seen", done_seen===1'b1);

        // 帧检查（10 个 bit 窗口）
        c("start=0",     stream[0]===8'h00);
        c("d0=1",        stream[1]===8'h01);
        c("d1=1",        stream[2]===8'h01);
        c("d2=0",        stream[3]===8'h00);
        c("d3=0",        stream[4]===8'h00);
        c("d4=1",        stream[5]===8'h01);
        c("d5=0",        stream[6]===8'h00);
        c("d6=1",        stream[7]===8'h01);
        c("d7=0",        stream[8]===8'h00);
        c("stop=1",      stream[9]===8'h01);

        // ---- 忙时 start 忽略：帧中途触发不应打断 ----
        data = 8'hA5;
        sidx = 0; done_seen = 0;
        start = 1;
        while (!busy) @(posedge clk);
        start = 0;
        repeat (3) @(posedge clk);
        start = 1;                        // 忙中再触发
        repeat (3) @(posedge clk);
        start = 0;
        while (busy) @(posedge clk);
        #1 c("busy-ignore ok (idle)", busy===0 && tx===1'b1);
        c("done seen 2nd", done_seen===1'b1);

        // ---- 第二字符可正常发送 ----
        data = 8'hAA;
        sidx = 0; done_seen = 0;
        start = 1;
        while (!busy) @(posedge clk);
        start = 0;
        while (busy) @(posedge clk);
        #1 c("2nd char ok", tx===1'b1 && busy===0);
        c("stream2 d0=0", stream[1]===8'h00);   // 0xAA LSB 先全 0? 0xAA=1010_1010 → d0=0
        c("stream2 d1=1", stream[2]===8'h01);

        if (err == 0) $display("=== ALL PASS ===");
        else          $display("=== FAIL === (%0d/%0d)", err, n);
        $finish;
    end

endmodule
