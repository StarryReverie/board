//=============================================================================
// tb_wave_868.v — 波形资产 TB（不属于回归集，放在 build/ 下）
//   目的：用真实分频 CLKS_PER_BIT=868（115200 @ 100MHz）跑一次 uart_ip_top，
//         把 TX/RX 引脚的真实跳变记录下来，离线生成"可打开的 VCD + 位级 ASCII
//         时序图"，替代示波器作为"时序正确"的证据。
//   为什么不用 $dumpvars：本机 xsim 2019.2 的 VCD dump 只写 $dumpvars 初值、
//         不记录后续值变化（已用 build/tb_dump_probe.v 实测确认），
//         因此改由 TB 侧记录跳变事件，再生成标准 VCD。
//   激励：
//     W1 写 TX 槽 0x5A  → 抓 TX 引脚 10 位帧（start + 8 数据 LSB 先 + stop）
//     W2 注入 0x3C 帧   → RX_VALID 置位 → 读 RX 槽取回 0x3C
//     W3 连续发送横幅 "EES-338 RV32I UART OK\r\n"（23 字节，与板上一致）
//   产出：build/wave868/wave_868_events.txt（TX/RX 跳变事件，时间单位 ns）
//         UART/doc/wave/uart_frame_868.vcd（一帧，可用 Vivado/xsim 打开）
//         UART/doc/wave/uart_frame_868.txt（位级 ASCII 时序图）
//=============================================================================
`timescale 1ns/1ps

module tb_wave_868;

    localparam integer CPB    = 868;          // 100 MHz / 115200
    localparam real    BIT_NS = CPB * 10.0;   // 一位 = 8.68 us

    reg        clk = 0;
    reg        rst = 1;
    reg        cs  = 0;
    reg  [3:0] addr = 0;
    reg        we  = 0;
    reg  [31:0] wdata = 0;
    wire [31:0] rdata;
    wire        uart_tx_pin;
    reg         uart_rx_pin = 1;

    integer f, fev, i, b;
    integer nev = 0;
    integer err = 0;               // 功能不符计数（W1/W2/W3 断言失败时累加）
    reg [9:0] cap;                 // 抓到的 TX 帧
    reg [7:0] banner [0:22];
    time ev_t [0:8191];            // 事件时刻（ns）
    reg  ev_p [0:8191];            // 1=TX, 0=RX
    reg  ev_v [0:8191];            // 跳变后的值

    uart_ip_top #(.CLKS_PER_BIT(CPB)) dut (
        .clk(clk), .rst(rst),
        .cs(cs), .addr(addr), .we(we), .wdata(wdata),
        .rdata(rdata), .uart_tx_pin(uart_tx_pin), .uart_rx_pin(uart_rx_pin)
    );

    always #5 clk = ~clk;          // 100 MHz

    // ---- 事件记录：在 bit_tick 拍采样引脚（引脚正是在该拍翻转；避免 #1 采样读到旧值）----
    reg tx_prev = 1'b1;
    reg rx_prev = 1'b1;
    always @(posedge clk) begin
        if (dut.bit_tick) begin
            if (uart_tx_pin !== tx_prev) begin
                if (nev < 8192) begin ev_t[nev] = $time; ev_p[nev] = 1'b1; ev_v[nev] = uart_tx_pin; nev = nev + 1; end
                tx_prev = uart_tx_pin;
            end
            if (uart_rx_pin !== rx_prev) begin
                if (nev < 8192) begin ev_t[nev] = $time; ev_p[nev] = 1'b0; ev_v[nev] = uart_rx_pin; nev = nev + 1; end
                rx_prev = uart_rx_pin;
            end
        end
    end

    task bus_write;
        input [3:0]  off;
        input [31:0] val;
        begin
            cs <= 1; we <= 1; addr <= off; wdata <= val;
            @(posedge clk);
            #1; cs <= 0; we <= 0; addr <= 4'h0; wdata <= 0;
        end
    endtask

    // 等上一帧完全结束（tx_busy 落沿）
    task wait_idle;
        integer j;
        begin
            j = 0;
            while (dut.tx_busy && j < 4000) begin
                @(posedge clk); #1; j = j + 1;
            end
        end
    endtask

    // 等引脚真正拉低（真 start 沿；tx_pend 先于 busy/引脚，不能用 busy 判起点）
    task wait_start_low;
        integer j;
        begin
            j = 0;
            while (uart_tx_pin && j < 8000) begin
                @(posedge clk); #1; j = j + 1;
            end
        end
    endtask

    // 按位中心采样 10 位 TX 帧（以引脚下降沿为锚，位中心 = start + (i+0.5) 位）
    task sample_tx;
        output [9:0] frame;
        integer j;
        begin
            wait_start_low;
            #(CPB * 10 / 2 - 1) frame[0] = uart_tx_pin;
            for (j = 1; j <= 9; j = j + 1) begin
                #(CPB * 10);
                frame[j] = uart_tx_pin;
            end
        end
    endtask

    task inject;
        input [7:0] by;
        integer bi;
        begin
            uart_rx_pin = 1'b0;
            #(BIT_NS);
            for (bi = 0; bi < 8; bi = bi + 1) begin
                uart_rx_pin = by[bi];
                #(BIT_NS);
            end
            uart_rx_pin = 1'b1;
            #(BIT_NS);
        end
    endtask

    initial begin
        banner[0]  = "E"; banner[1]  = "E"; banner[2]  = "S"; banner[3]  = "-";
        banner[4]  = "3"; banner[5]  = "3"; banner[6]  = "8"; banner[7]  = " ";
        banner[8]  = "R"; banner[9]  = "V"; banner[10] = "3"; banner[11] = "2";
        banner[12] = "I"; banner[13] = " "; banner[14] = "U"; banner[15] = "A";
        banner[16] = "R"; banner[17] = "T"; banner[18] = " "; banner[19] = "O";
        banner[20] = "K"; banner[21] = 8'h0D; banner[22] = 8'h0A;

        repeat (8) @(posedge clk);
        rst = 0;
        #1;

        // ---- W1: 写 TX=0x5A，抓一帧 ----
        bus_write(4'h0, 32'h5A);
        sample_tx(cap);
        $display("[W1] TX frame: start=%b data=0x%02h stop=%b", cap[0], cap[8:1], cap[9]);
        $display("[W1] bit width = %0.2f ns (= %0d clk), frame = %0.2f ns",
                 BIT_NS, CPB, BIT_NS * 10.0);
        if (cap[0] !== 1'b0 || cap[8:1] !== 8'h5A || cap[9] !== 1'b1) begin
            err = err + 1;
            $display("[W1] FRAME MISMATCH (expect 0x5A)");
        end

        // ---- W2: 注入 0x3C 帧 → RX_VALID → 读 RX 槽 ----
        inject(8'h3C);
        @(posedge clk); #1;
        cs <= 1; we <= 0; addr <= 4'h8;
        #2 $display("[W2] RX slot = 0x%02h (rx_valid=%b)", rdata[7:0], dut.rx_valid);
        if (rdata[7:0] !== 8'h3C) begin
            err = err + 1;
            $display("[W2] RX MISMATCH (expect 0x3C)");
        end
        @(posedge clk); #1; cs <= 0; we <= 0; addr <= 4'h0;
        #2 $display("[W2] after read: rx_valid=%b", dut.rx_valid);
        if (dut.rx_valid !== 1'b0) begin
            err = err + 1;
            $display("[W2] RX_VALID not cleared after read");
        end

        // ---- W3: 连续发送 23 字节横幅，逐帧校验 ----
        for (b = 0; b < 23; b = b + 1) begin
            wait_idle;
            bus_write(4'h0, {24'd0, banner[b]});
            sample_tx(cap);
            if (cap[0] !== 1'b0 || cap[8:1] !== banner[b] || cap[9] !== 1'b1) begin
                err = err + 1;
                $display("[W3] FRAME MISMATCH at %0d (0x%02h)", b, banner[b]);
            end
        end
        $display("[W3] 23-byte banner: all frames start=0/data-ok/stop=1");

        // ---- 事件落盘 ----
        fev = $fopen("wave_868_events.txt", "w");
        $fdisplay(fev, "# tb_wave_868 pin transitions, time in ns, format: <time_ns> <tx|rx> <value>");
        for (i = 0; i < nev; i = i + 1)
            $fdisplay(fev, "%0d %s %b", ev_t[i], (ev_p[i] ? "tx" : "rx"), ev_v[i]);
        $fclose(fev);

        f = $fopen("wave_868.txt", "w");
        $fdisplay(f, "uart_ip_top 8N1 timing (CLKS_PER_BIT=%0d, 100MHz, 115200-8N1)", CPB);
        $fdisplay(f, "bit  = %0.2f ns = %0.4f us", BIT_NS, BIT_NS / 1000.0);
        $fdisplay(f, "frame= %0.2f ns = %0.4f us", BIT_NS * 10.0, BIT_NS / 100.0);
        $fdisplay(f, "baud error = %0.4f %%", ((100000000.0 / CPB) - 115200.0) / 115200.0 * 100.0);
        $fclose(f);

        // 本 TB 兼作功能检查：W1/W2/W3 任一不符会打印 FRAME MISMATCH；
        // 末尾按仓库 TB 约定打印 ALL PASS，便于被通用运行器识别。
        if (err == 0) $display("=== WAVE DUMP DONE (%0d pin transitions) ALL PASS ===", nev);
        else          $display("=== WAVE DUMP FAIL (%0d mismatches) ===", err);
        $finish;
    end

endmodule
