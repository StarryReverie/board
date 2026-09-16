`timescale 1ns/1ps
//=============================================================================
// tb_wave_soc.v — 实验二第 4 项波形 TB（统一编址 MMIO + UART 回显全链路）
//   不在回归集内：位于 soc/test/wave/ 子目录（run_soc_tb.ps1 只收 test 根目录的
//   tb_*.v），由 UART/src/scripts/run_exp2_wave.ps1 单独编译运行。
//   CLKS_PER_BIT=4（1 位 = 40 ns，整段仿真约 2 us，便于一张图讲完全链路；
//   真实分频 868 的时序证据见实验二第 1 项）。
//   程序与 soc/test/tb_soc_full.v 同源（18 条）：发 'A' → 注入 0x42 → 读回 → 回显。
//   逐拍记录：uart_tx_pin / uart_rx_pin / cs_mmio / reg_off / mmio_we / mmio_wdata /
//             mmio_rdata / pc / MEM address / tx_busy / monitor valid,data。
//   产出：wave_soc.csv（渲染 ppt/assets/exp2-mmio.png 用）
//=============================================================================
module tb_wave_soc;

    localparam CPB = 4;

    reg        clk = 0;
    reg        rst_n = 0;
    wire       uart_tx_pin;
    wire       uart_rx_pin;      // 注入器驱动

    integer err = 0;
    integer n   = 0;
    integer i;
    integer fd;
    reg     log_on = 0;

    soc_top #(.CLKS_PER_BIT(CPB), .RESET_STABLE_CYCLES(8)) u_soc (
        .clk(clk), .rst_n(rst_n),
        .uart_tx_pin(uart_tx_pin), .uart_rx_pin(uart_rx_pin)
    );

    always #5 clk = ~clk;

    // ---- 注入器 tick（每 CPB clk 一脉冲）----
    reg [15:0] bcnt = 0;
    reg        btick = 0;
    always @(posedge clk) begin
        if (bcnt == CPB-1) begin bcnt <= 0; btick <= 1; end
        else begin bcnt <= bcnt + 1; btick <= 0; end
    end

    // ---- 注入器（uart_tx：向 CPU RX 发字节）----
    reg        inj_start = 0;
    reg  [7:0] inj_data = 0;
    wire       inj_busy;
    wire       inj_tx;
    wire       rst_i = ~rst_n;
    uart_tx #(.CLKS_PER_BIT(CPB)) u_inj (
        .clk(clk), .rst(rst_i), .clk_en(btick),
        .start(inj_start), .data(inj_data),
        .busy(inj_busy), .done(), .tx(inj_tx)
    );
    assign uart_rx_pin = inj_tx;

    // ---- 监视器（uart_rx：采样 soc TX 输出）----
    wire       mon_valid;
    wire [7:0] mon_data;
    uart_rx #(.CLKS_PER_BIT(CPB)) u_mon (
        .clk(clk), .rst(rst_i), .clk_en(1'b0),
        .rx(uart_tx_pin), .valid(mon_valid), .data(mon_data)
    );

    // ---- 捕获 ----
    reg [7:0] capb [0:7];
    integer   capc = 0;
    always begin
        @(posedge clk);
        #1;
        if (mon_valid && capc < 8) begin
            capb[capc] <= mon_data;
            capc <= capc + 1;
        end
    end

    // ---- 逐拍 CSV ----
    always @(posedge clk) begin
        #1;
        if (log_on) begin
            $fwrite(fd, "%0d,%b,%b,%b,%0d,%b,%0d,%0d,%0d,%0d,%b,%b,%0d\n",
                $time, uart_tx_pin, uart_rx_pin, u_soc.cs_mmio, u_soc.reg_off,
                u_soc.mmio_we, u_soc.mmio_wdata, u_soc.mmio_rdata,
                u_soc.u_cpu.pc, u_soc.u_cpu.exmem_alu_result, u_soc.u_uart.tx_busy,
                mon_valid, mon_data);
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

    task wait_cap;
        input [31:0] k;
        input [31:0] maxcyc;
        output seen;
        integer kk;
        begin
            seen = 0;
            for (kk = 0; kk < maxcyc; kk = kk + 1) begin
                @(posedge clk);
                #1;
                if (capc >= k) begin seen = 1; kk = maxcyc; end
            end
        end
    endtask

    task load_word;
        input [31:0] wa;
        input [31:0] wd;
        begin
            u_soc.u_cpu.u_imem.mem[wa  ] = wd[7:0];
            u_soc.u_cpu.u_imem.mem[wa+1] = wd[15:8];
            u_soc.u_cpu.u_imem.mem[wa+2] = wd[23:16];
            u_soc.u_cpu.u_imem.mem[wa+3] = wd[31:24];
        end
    endtask

    integer k;
    initial begin
        fd = $fopen("wave_soc.csv", "w");
        $fwrite(fd, "time_ns,uart_tx_pin,uart_rx_pin,cs_mmio,reg_off,mmio_we,mmio_wdata,mmio_rdata,pc,mem_addr,tx_busy,mon_valid,mon_data\n");

        // ---- 装载 console 程序（与 tb_soc_full.v 同源）----
        for (i = 0; i < 4096; i = i + 1) u_soc.u_cpu.u_imem.mem[i] = 8'h00;
        load_word(32'h00, 32'h000040B7);  // lui  x1,0x4
        load_word(32'h04, 32'h04100113);  // addi x2,x0,'A'
        load_word(32'h08, 32'h0040A183);  // wait_tx1: lw x3,4(x1)
        load_word(32'h0C, 32'h0011F193);  // andi x3,x3,1
        load_word(32'h10, 32'hFE019CE3);  // bne  x3,x0,wait_tx1
        load_word(32'h14, 32'h0020A023);  // sw   x2,0(x1)
        load_word(32'h18, 32'h0040A183);  // wait_idle: lw x3,4(x1)
        load_word(32'h1C, 32'h0011F193);  // andi x3,x3,1
        load_word(32'h20, 32'hFE019CE3);  // bne  x3,x0,wait_idle
        load_word(32'h24, 32'h0040A183);  // wait_rx: lw x3,4(x1)
        load_word(32'h28, 32'h0021F193);  // andi x3,x3,2
        load_word(32'h2C, 32'hFE018CE3);  // beq  x3,x0,wait_rx
        load_word(32'h30, 32'h0080A203);  // lw   x4,8(x1)
        load_word(32'h34, 32'h0040A183);  // wait_tx2: lw x3,4(x1)
        load_word(32'h38, 32'h0011F193);  // andi x3,x3,1
        load_word(32'h3C, 32'hFE019CE3);  // bne  x3,x0,wait_tx2
        load_word(32'h40, 32'h0040A023);  // sw   x4,0(x1)
        load_word(32'h44, 32'h00000063);  // halt

        // ---- 复位释放 ----
        repeat (4) @(posedge clk);
        rst_n = 1;
        log_on = 1;

        // ---- CPU 应发出 'A' ----
        wait_cap(32'd1, 32'd3000, k); c("char A captured", k===1);
        c("char A = 0x41", capb[0]===8'h41);
        c("tx idle after A", uart_tx_pin===1'b1);

        // ---- 注入 0x42：CPU 应收并回显 ----
        repeat (30) @(posedge clk);
        inj_data = 8'h42;
        inj_start = 1;
        while (!inj_busy) @(posedge clk);
        inj_start = 0;
        wait_cap(32'd2, 32'd3000, k); c("echo char captured", k===1);
        c("echo = 0x42", capb[1]===8'h42);

        log_on = 0;
        $fclose(fd);
        if (err == 0) $display("=== WAVE SOC DONE ALL PASS ===");
        else          $display("=== WAVE SOC FAIL === (%0d/%0d)", err, n);
        $finish;
    end

endmodule
