//=============================================================================
// tb_uart_ip_top.v — uart_ip_top IP 级独立测试（UART U15；UART/doc/modules/uart_ip_top.md 验收）
//   CLKS_PER_BIT=4（bit=40ns）。无任何 CPU 依赖：总线直接驱动、串行帧逐位收发。
//   检查：
//     P1 默认态：各槽读 0 / cs=0 读 0 / TX 引脚空闲高
//     P2 TX 帧级校验：写 TX=0x5A → 下降沿起按位中心采样 10 位 →
//        start=0、数据 LSB 先=0x5A、stop=1；写接受后 STAT.TX_BUSY 即置 1（含挂起）
//     P3 忙写丢弃：发 0xA1 期间写 0xB2 → 停止位后 12 bit 窗口内无第二帧
//     P4 RX：注入 0x3C 帧 → RX_VALID → 读 RX 槽取字节 → 读后清位
//     P5 溢出丢弃：未读期间注入 0x22 → 保留 0x11
//     P6 写 STAT/RX 无操作；保留槽读 0
//     P7 全双工：RX 帧接收进行中写 TX → TX_BUSY 与 RX_VALID 同现（STAT=2'b11），
//        两路各自完成：TX 帧=0x5A、RX 槽读回=0x3C
//   口径：帧捕获按 busy 轮询定位 start 沿（busy 与引脚同沿翻转；检测滞后
//         0–1 拍，采样点仍在各位窗口内），对写沿与分频相位任意组合稳健。
//=============================================================================
`timescale 1ns/1ps

module tb_uart_ip_top;

    localparam CPB = 4;

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

    reg  [9:0] fd_frame;          // 全双工 TX 帧（fork 任务写入）
    reg        fd_cap_done = 0;

    uart_ip_top #(.CLKS_PER_BIT(CPB)) dut (
        .clk(clk), .rst(rst),
        .cs(cs), .addr(addr), .we(we), .wdata(wdata),
        .rdata(rdata), .uart_tx_pin(uart_tx_pin), .uart_rx_pin(uart_rx_pin)
    );

    always #5 clk = ~clk;

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

    // 写槽：保持一个沿（末沿锁存）
    task bus_write;
        input [3:0]  off;
        input [31:0] val;
        begin
            cs <= 1; we <= 1; addr <= off; wdata <= val;
            @(posedge clk);
            #1 bus_idle();
        end
    endtask

    // 组合读槽（置位 2ns 后采样；保持 cs 直到 @(posedge) 后释放，供"读清位"用）
    task read_slot_hold;
        input  [3:0]  off;
        output [31:0] val;
        begin
            cs <= 1; we <= 0; addr <= off;
            #2;
            val = rdata;
        end
    endtask

    // 层次等待：busy 出现
    task wait_busy_hi;
        input  [15:0] maxcyc;
        output        seen;
        integer kk;
        begin
            seen = 0;
            for (kk = 0; kk < maxcyc; kk = kk + 1) begin
                @(posedge clk);
                #1;
                if (dut.tx_busy) begin seen = 1; kk = maxcyc; end
            end
        end
    endtask

    task wait_busy_lo;
        input  [15:0] maxcyc;
        output        seen;
        integer kk;
        begin
            seen = 0;
            for (kk = 0; kk < maxcyc; kk = kk + 1) begin
                @(posedge clk);
                #1;
                if (!dut.tx_busy) begin seen = 1; kk = maxcyc; end
            end
        end
    endtask

    // 层次等待：rx_valid（粘滞位，读 RX 槽后清）置位
    task wait_rxv;
        input  [15:0] maxcyc;
        output        seen;
        integer kk;
        begin
            seen = 0;
            for (kk = 0; kk < maxcyc; kk = kk + 1) begin
                @(posedge clk);
                #1;
                if (dut.rx_valid) begin seen = 1; kk = maxcyc; end
            end
        end
    endtask

    // ---- 串行帧捕获：busy 轮询定位 start 沿，按位中心采样 10 位 ----
    task sample_tx_frame;
        output [9:0] frame;      // [0]=start [8:1]=数据 LSB 先 [9]=stop
        integer i;
        begin
            // busy 与 TX 引脚在 start 沿同拍翻转；轮询滞后 0–1 拍，
            // 采样点相对位中心偏移 ≤10ns，仍在 40ns 位窗内（见文件头口径）
            i = 0;
            while (!dut.tx_busy && i < 400) begin
                @(posedge clk);
                #1;
                i = i + 1;
            end
            if (i >= 400) begin
                frame = 10'bz;                         // 超时：置无效值（断言必 FAIL，不悬挂）
            end else begin
                #(CPB*10/2 - 1) frame[0] = uart_tx_pin;   // start 位中心（滞后 1 拍时 +10ns）
                for (i = 1; i <= 9; i = i + 1) begin
                    #(CPB*10);
                    frame[i] = uart_tx_pin;
                end
            end
        end
    endtask

    // ---- 串行注入（喂 RX 引脚）：1 起始 + 8 数据 LSB 先 + 1 停止 ----
    task inject_frame;
        input [7:0] byte;
        integer bi;
        begin
            uart_rx_pin = 1'b0;
            #(CPB*10);
            for (bi = 0; bi < 8; bi = bi + 1) begin
                uart_rx_pin = byte[bi];
                #(CPB*10);
            end
            uart_rx_pin = 1'b1;
            #(CPB*10);
        end
    endtask

    // ---- P7 并行线程（V2001 无 join_none：独立 initial + 事件武装）----
    // 两线程在 t=0 即挂起于事件等待，主流程到 P7 才触发——无丢失竞态
    event fd_arm;            // 武装 TX 帧捕获
    event fd_rx_go;          // 启动 RX 帧注入
    initial begin
        @fd_arm;
        sample_tx_frame(fd_frame);
        fd_cap_done = 1;
    end
    initial begin
        @fd_rx_go;
        inject_frame(8'h3C);
    end

    initial begin
        repeat (4) @(posedge clk);
        rst = 0;
        #1;

        // ---- P1 默认态：各槽读 0 / cs=0 读 0 / TX 空闲高 ----
        read_slot_hold(4'h0, wdata); c("P1 TX rd=0", wdata===0);
        @(posedge clk); #1 bus_idle();
        read_slot_hold(4'h4, wdata); c("P1 STAT rd=0", wdata===0);
        @(posedge clk); #1 bus_idle();
        read_slot_hold(4'h8, wdata); c("P1 RX rd=0", wdata===0);
        @(posedge clk); #1 bus_idle();
        read_slot_hold(4'hC, wdata); c("P1 rsv rd=0", wdata===0);
        @(posedge clk); #1 bus_idle();
        bus_idle();
        #1 c("P1 cs=0 rd=0", rdata===0);
        c("P1 tx idle high", uart_tx_pin===1'b1);

        // ---- P2 TX 帧级校验：写 0x5A → 挂起态 STAT → 逐位帧捕获 ----
        bus_write(4'h0, 32'h5A);
        // 写锁存后 2ns：STAT.TX_BUSY 即 1（挂起待发或移位中，两种相位均成立）
        read_slot_hold(4'h4, wdata);
        c("P2 STAT busy=1 (含挂起)", wdata[0]===1'b1);
        // busy 轮询帧捕获（对 start 沿相位稳健，见文件头口径）
        sample_tx_frame(fd_frame);
        c("P2 start=0", fd_frame[0]===1'b0);
        c("P2 data=0x5A LSB先", fd_frame[8:1]===8'h5A);
        c("P2 stop=1", fd_frame[9]===1'b1);
        bus_idle();
        wait_busy_lo(40, k); c("P2 busy cleared", k===1);
        #1 c("P2 tx back idle", uart_tx_pin===1'b1);
        read_slot_hold(4'h4, wdata); c("P2 STAT busy=0", wdata[0]===1'b0);
        @(posedge clk); #1 bus_idle();

        // ---- P3 忙写丢弃：发 0xA1 期间写 0xB2 → 无第二帧 ----
        bus_write(4'h0, 32'hA1);
        wait_busy_hi(200, k); c("P3 busy seen", k===1);
        bus_write(4'h0, 32'hB2);          // 忙中写：应丢弃
        wait_busy_lo(80, k); c("P3 cleared", k===1);
        // 停止位后 12 bit 窗口：位中心逐点监视 busy 与引脚，任何活动即失败
        k = 0;
        begin : p3_scan
            integer kk;
            for (kk = 0; kk < 12; kk = kk + 1) begin
                #(CPB*10/2);
                if (dut.tx_busy) k = 1;
                if (!uart_tx_pin)      k = 1;
                #(CPB*10/2);
            end
        end
        c("P3 no second frame (drop ok)", k===0);

        // ---- P4 RX：注入 0x3C → RX_VALID → 读槽取字节 → 读后清位 ----
        inject_frame(8'h3C);
        wait_rxv(80, k); c("P4 RX_VALID seen", k===1);
        read_slot_hold(4'h8, wdata); c("P4 RX byte=0x3C", wdata[7:0]===8'h3C);
        @(posedge clk);                // 读后清位（访存段末沿）
        #1 bus_idle();
        c("P4 rx_valid cleared", dut.rx_valid===0);
        read_slot_hold(4'h4, wdata); c("P4 STAT valid=0", wdata[1]===1'b0);
        @(posedge clk); #1 bus_idle();

        // ---- P5 溢出丢弃：未读期间注入 0x22 → 保留 0x11 ----
        inject_frame(8'h11);
        wait_rxv(80, k); c("P5 0x11 valid", k===1);
        inject_frame(8'h22);           // 未读期间到达
        #(CPB*10*16);                  // 等第二帧处理完
        c("P5 still holds 0x11", dut.rx_valid===1);
        read_slot_hold(4'h8, wdata); c("P5 RX keeps 0x11", wdata[7:0]===8'h11);
        @(posedge clk); #1 bus_idle();
        c("P5 cleared after read", dut.rx_valid===0);

        // ---- P6 写 STAT/RX 无操作 ----
        bus_write(4'h4, 32'hFFFFFFFF);
        c("P6 write STAT noop", dut.rx_valid===0);
        bus_write(4'h8, 32'hFFFFFFFF);
        c("P6 write RX noop", dut.rx_valid===0 && dut.rx_byte===8'h11);

        // ---- P7 全双工：RX 接收进行中启动 TX → 两路同现且各自完成 ----
        fd_cap_done = 0;
        -> fd_arm;                            // 武装 TX 帧捕获线程（等 start 沿）
        -> fd_rx_go;                          // 启动 RX 帧注入线程（并行 400ns）
        #(CPB*10*5);                          // RX 数据位传输中段
        bus_write(4'h0, 32'h5A);              // 此时启动 TX：与 RX 并行
        wait_busy_hi(80, k); c("P7 tx busy seen", k===1);
        wait_rxv(60, k); c("P7 RX_VALID seen (TX 移位中)", k===1);
        c("P7 tx busy during rx valid", dut.tx_busy===1'b1);
        read_slot_hold(4'h4, wdata); c("P7 STAT=2'b11 同现", wdata[1:0]===2'b11);
        @(posedge clk); #1 bus_idle();
        wait_busy_lo(120, k); c("P7 tx done", k===1);
        // 有界轮询 fd_cap_done（任务 input 为值拷贝，不能传信号轮询，故内联）
        begin : p7_waitcap
            integer kk;
            k = 0;
            for (kk = 0; kk < 200; kk = kk + 1) begin
                @(posedge clk);
                #1;
                if (fd_cap_done) begin k = 1; kk = 200; end
            end
        end
        c("P7 frame capture done", k===1);
        c("P7 tx frame=0x5A", fd_frame[0]===1'b0 && fd_frame[8:1]===8'h5A && fd_frame[9]===1'b1);
        read_slot_hold(4'h8, wdata); c("P7 RX byte=0x3C", wdata[7:0]===8'h3C);
        @(posedge clk); #1 bus_idle();
        c("P7 rx_valid cleared", dut.rx_valid===0);

        if (err == 0) $display("=== ALL PASS ===");
        else          $display("=== FAIL === (%0d/%0d)", err, n);
        $finish;
    end

endmodule
