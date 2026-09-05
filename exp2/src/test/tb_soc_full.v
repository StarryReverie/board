//=============================================================================
// tb_soc_full.v — soc_top 整机系统级验证（进阶验收·仿真正确）
//   CLKS_PER_BIT=4（bit=40ns）
//   程序（机器码由 riscv-none-elf-as 生成，18 条）：
//     发送 'A'（轮询 TX_BUSY）→ 等待 RX_VALID → 读 RX → 回显 → halt
//   串口模型（复用 UART IP）：
//     - 监视器 uart_rx：采样 soc uart_tx_pin，捕获 CPU 发出字节
//     - 注入器 uart_tx：由 TB 控制向 soc uart_rx_pin 发送字节
//   断言：首帧 'A'（0x41）；注入 0x42 后回显帧=0x42。
//=============================================================================
`timescale 1ns/1ps

module tb_soc_full;

    localparam CPB = 4;

    reg        clk = 0;
    reg        rst_n = 0;
    wire       uart_tx_pin;
    wire       uart_rx_pin;      // 注入器驱动

    integer err = 0;
    integer n   = 0;
    integer i;

    soc_top #(.CLKS_PER_BIT(CPB)) u_soc (
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

    task c;
        input [255:0] name;
        input         ok;
        begin
            n = n + 1;
            if (!ok) begin err = err + 1; $display("FAIL: %0d %0s", n, name); end
            else $display("PASS: %0d %0s", n, name);
        end
    endtask

    // 等待捕获到至少 k 字节
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
        // ---- 装载 console 程序（机器码经 as 生成）----
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

        // ---- CPU 应发出 'A' ----
        wait_cap(32'd1, 32'd3000, k); c("char A captured", k===1);
        c("char A = 0x41", capb[0]===8'h41);
        c("tx idle after A", uart_tx_pin===1'b1);

        // ---- 注入 0x42：CPU 应收并回显 ----
        // 等 TX 空闲若干拍，再启动注入帧
        repeat (30) @(posedge clk);
        inj_data = 8'h42;
        inj_start = 1;
        while (!inj_busy) @(posedge clk);
        inj_start = 0;
        wait_cap(32'd2, 32'd3000, k); c("echo char captured", k===1);
        c("echo = 0x42", capb[1]===8'h42);

        if (err == 0) $display("=== ALL PASS ===");
        else          $display("=== FAIL === (%0d/%0d)", err, n);
        $finish;
    end

endmodule
