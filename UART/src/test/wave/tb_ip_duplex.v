`timescale 1ns/1ps
//=============================================================================
// tb_ip_duplex.v — 实验二第 3 项波形 TB（全双工并发 + TX_BUSY 含挂起写接受条件）
//   不在回归集内：位于 UART/src/test/wave/ 子目录（run_soc_tb.ps1 只收 test 根
//   目录的 tb_*.v），由 UART/src/scripts/run_exp2_wave.ps1 单独编译运行。
//   CLKS_PER_BIT=868（真实分频，100 MHz / 115200，位宽 8.68 us）。
//   场景：
//     P7 全双工：RX 注入 0x3C 进行中写 TX=0x5A，tx_busy 与 rx_valid 同现
//        （STAT=2'b11），两路各自完成：TX 帧=0x5A、RX 读回=0x3C。
//     P3 忙写丢弃：空闲写 0xA1 被接受；移位期间写 0xB2 被丢弃（无第二帧，
//        停止位后 12 bit 静默）。
//     putc 连发：连续写 'A'/'B'/'C'，三帧首尾相接、不丢字。
//   产出：ip_duplex.csv（逐跳变事件，渲染 ppt/assets/exp2-duplex.png 用）
//=============================================================================
module tb_ip_duplex;

    localparam integer CPB    = 868;
    localparam integer BIT_NS = CPB * 10;      // 8680 ns

    reg        clk = 0;
    reg        rst = 1;
    reg        cs  = 0;
    reg  [3:0] addr = 0;
    reg        we  = 0;
    reg  [31:0] wdata = 0;
    wire [31:0] rdata;
    wire        uart_tx_pin;
    reg         uart_rx_pin = 1;

    integer err = 0;
    integer n   = 0;
    integer k;
    integer fd;
    reg     log_on = 0;

    reg  [9:0] fd_frame;
    reg        fd_cap_done = 0;
    reg        ov_seen = 0;

    wire overlap = dut.tx_busy & dut.rx_valid;

    uart_ip_top #(.CLKS_PER_BIT(CPB)) dut (
        .clk(clk), .rst(rst),
        .cs(cs), .addr(addr), .we(we), .wdata(wdata),
        .rdata(rdata), .uart_tx_pin(uart_tx_pin), .uart_rx_pin(uart_rx_pin)
    );

    always #5 clk = ~clk;

    always @(posedge clk) if (overlap) ov_seen = 1'b1;

    // ---- 逐跳变事件日志（任何被观测信号变化才写一行，紧凑）----
    //   在 posedge 采样（不加 #1）：读到的是本拍沿之前的值，组合的 tx_accept 因此
    //   反映"写发生那一拍"的真实接受条件（沿后才置位的 tx_pend 不会掩盖它）。
    reg        p_tx = 1'bx, p_rx = 1'bx, p_busy = 1'bx, p_pend = 1'bx;
    reg        p_rxv = 1'bx, p_ov = 1'bx, p_cs = 1'bx, p_we = 1'bx, p_acc = 1'bx;
    reg  [3:0] p_addr = 4'hx;
    reg  [7:0] p_buf  = 8'hxx;
    reg [31:0] p_rd   = 32'hxxxxxxxx, p_wdata = 32'hxxxxxxxx;

    always @(posedge clk) begin
        if (log_on &&
            (uart_tx_pin !== p_tx || uart_rx_pin !== p_rx ||
             dut.tx_busy !== p_busy || dut.tx_pend !== p_pend ||
             dut.rx_valid !== p_rxv || overlap !== p_ov ||
             dut.tx_buf !== p_buf || rdata !== p_rd ||
             cs !== p_cs || we !== p_we || addr !== p_addr || wdata !== p_wdata ||
             dut.tx_accept !== p_acc)) begin
            $fwrite(fd, "%0d,%b,%b,%b,%b,%b,%0d,%0d,%b,%b,%0d,%0d,%b,%b\n",
                $time, uart_tx_pin, uart_rx_pin, dut.tx_busy, dut.tx_pend,
                dut.rx_valid, dut.tx_buf, rdata, cs, we, addr, wdata, overlap,
                dut.tx_accept);
            p_tx = uart_tx_pin; p_rx = uart_rx_pin; p_busy = dut.tx_busy;
            p_pend = dut.tx_pend; p_rxv = dut.rx_valid; p_ov = overlap;
            p_buf = dut.tx_buf; p_rd = rdata; p_cs = cs; p_we = we;
            p_addr = addr; p_wdata = wdata; p_acc = dut.tx_accept;
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

    task bus_idle;
        begin cs <= 0; we <= 0; addr <= 4'h0; wdata <= 0; end
    endtask

    // 写槽：neg 沿置位并保持一个整周期，pos 沿被 DUT 锁存
    task bus_write;
        input [3:0]  off;
        input [31:0] val;
        begin
            @(negedge clk);
            cs <= 1; we <= 1; addr <= off; wdata <= val;
            @(negedge clk);
            bus_idle();
        end
    endtask

    // 组合读槽：保持一个整周期，pos 沿后 #2 采样（读 RX 槽会清 RX_VALID）
    task read_slot;
        input  [3:0]  off;
        output [31:0] val;
        begin
            @(negedge clk);
            cs <= 1; we <= 0; addr <= off;
            @(posedge clk); #2;
            val = rdata;
            @(negedge clk);
            bus_idle();
        end
    endtask

    task wait_busy_hi;
        input  [31:0] max;
        output        seen;
        integer j;
        begin
            seen = 0;
            for (j = 0; j < max; j = j + 1) begin
                @(posedge clk); #1;
                if (dut.tx_busy) begin seen = 1; j = max; end
            end
        end
    endtask

    task wait_busy_lo;
        input  [31:0] max;
        output        seen;
        integer j;
        begin
            seen = 0;
            for (j = 0; j < max; j = j + 1) begin
                @(posedge clk); #1;
                if (!dut.tx_busy) begin seen = 1; j = max; end
            end
        end
    endtask

    task wait_rxv;
        input  [31:0] max;
        output        seen;
        integer j;
        begin
            seen = 0;
            for (j = 0; j < max; j = j + 1) begin
                @(posedge clk); #1;
                if (dut.rx_valid) begin seen = 1; j = max; end
            end
        end
    endtask

    // 以 busy 上升沿为锚，按位中心采样 10 位 TX 帧
    task sample_tx_frame;
        output [9:0] frame;
        integer j;
        begin
            j = 0;
            while (!dut.tx_busy && j < 40000) begin @(posedge clk); #1; j = j + 1; end
            if (j >= 40000) begin
                frame = 10'bz;
            end else begin
                #(CPB*10/2 - 1) frame[0] = uart_tx_pin;
                for (j = 1; j <= 9; j = j + 1) begin
                    #(CPB*10);
                    frame[j] = uart_tx_pin;
                end
            end
        end
    endtask

    // 串行注入：1 起始 + 8 数据 LSB 先 + 1 停止，位宽 = 8680 ns
    task inject_frame;
        input [7:0] by;
        integer j;
        begin
            uart_rx_pin = 1'b0;
            #(BIT_NS);
            for (j = 0; j < 8; j = j + 1) begin
                uart_rx_pin = by[j];
                #(BIT_NS);
            end
            uart_rx_pin = 1'b1;
            #(BIT_NS);
        end
    endtask

    event rx_go, tx_arm;
    initial begin @(rx_go); inject_frame(8'h3C); end
    initial begin @(tx_arm); sample_tx_frame(fd_frame); fd_cap_done = 1'b1; end

    initial begin
        fd = $fopen("ip_duplex.csv", "w");
        $fwrite(fd, "time_ns,uart_tx_pin,uart_rx_pin,tx_busy,tx_pend,rx_valid,tx_buf,rdata,cs,we,addr,wdata,overlap,accept\n");

        repeat (8) @(posedge clk);
        rst = 0;
        #1;
        log_on = 1;

        // ================= P7 全双工 =================
        fd_cap_done = 0;
        -> tx_arm;
        -> rx_go;
        #(BIT_NS * 5);
        bus_write(4'h0, 32'h5A);
        wait_busy_hi(4000, k);   c("P7 tx busy seen", k === 1);
        wait_rxv(40000, k);      c("P7 RX_VALID seen (TX shift)", k === 1);
        c("P7 tx busy during rx valid", dut.tx_busy === 1'b1);
        read_slot(4'h4, wdata);  c("P7 STAT=2'b11 overlap", wdata[1:0] === 2'b11);
        c("overlap ever seen (full-duplex)", ov_seen === 1'b1);
        read_slot(4'h8, wdata);  c("P7 RX byte=0x3C", wdata[7:0] === 8'h3C);
        c("P7 rx_valid cleared", dut.rx_valid === 1'b0);
        wait_busy_lo(40000, k);  c("P7 tx done", k === 1);
        begin : p7_waitcap
            integer jj;
            k = 0;
            for (jj = 0; jj < 40000; jj = jj + 1) begin
                @(posedge clk); #1;
                if (fd_cap_done) begin k = 1; jj = 40000; end
            end
        end
        c("P7 frame capture done", k === 1);
        c("P7 tx frame=0x5A", fd_frame[0] === 1'b0 && fd_frame[8:1] === 8'h5A && fd_frame[9] === 1'b1);

        // ================= P3 忙写丢弃 =================
        bus_write(4'h0, 32'hA1);
        wait_busy_hi(4000, k);   c("P3 busy seen", k === 1);
        bus_write(4'h0, 32'hB2);
        wait_busy_lo(40000, k);  c("P3 cleared", k === 1);
        k = 0;
        begin : p3_scan
            integer kk;
            for (kk = 0; kk < 12; kk = kk + 1) begin
                #(BIT_NS/2);
                if (dut.tx_busy) k = 1;
                if (!uart_tx_pin) k = 1;
                #(BIT_NS/2);
            end
        end
        c("P3 no second frame (drop ok)", k === 0);

        // ================= putc 连发 =================
        bus_write(4'h0, 32'h41);
        sample_tx_frame(fd_frame); c("putc frame ok", fd_frame[8:1] === 8'h41);
        wait_busy_lo(4000, k);
        bus_write(4'h0, 32'h42);
        sample_tx_frame(fd_frame); c("putc frame ok", fd_frame[8:1] === 8'h42);
        wait_busy_lo(4000, k);
        bus_write(4'h0, 32'h43);
        sample_tx_frame(fd_frame); c("putc frame ok", fd_frame[8:1] === 8'h43);
        wait_busy_lo(4000, k);

        log_on = 0;
        $fclose(fd);
        if (err == 0) $display("=== IP DUPLEX DONE ALL PASS ===");
        else          $display("=== IP DUPLEX FAIL === (%0d/%0d)", err, n);
        $finish;
    end

endmodule
