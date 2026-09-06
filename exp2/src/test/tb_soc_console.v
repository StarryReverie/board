//=============================================================================
// tb_soc_console.v — U31 固件版系统级 TB（console_rom.hex：banner+回显）
//   CLKS_PER_BIT=4（bit=40ns）；固件 = exp2/src/test/console.S（U40）
//   验收（tasks.md U31）：
//     P1 banner 23 字节 = "EES-338 RV32I UART OK\r\n"（cap[0..22]）
//     P2 回显往返：注入 0x55 → CPU 回发（cap[23]）
//     P3 长串无死锁：连续 8 字符逐字回显（cap[24..31]）
//     P4 复位重跑一致：rst_n 重启 → banner 再现（cap[32..54]）+ 回显 0x5A
//   串口模型复用 UART IP：监视器 uart_rx（采 CPU TX 输出）、注入器 uart_tx
//=============================================================================
`timescale 1ns/1ps

module tb_soc_console;

    localparam CPB = 4;
    localparam BANNER_LEN = 23;      // "EES-338 RV32I UART OK\r\n"（不含 NUL）

    reg        clk = 0;
    reg        rst_n = 0;
    wire       uart_tx_pin;
    wire       uart_rx_pin;

    integer err = 0;
    integer n   = 0;
    integer i;

    // ---- 期望 banner（console.S 注释同源）----
    reg [7:0] expb [0:22];

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

    // ---- 监视器（uart_rx：采样 CPU TX 输出，捕获字节流）----
    wire       mon_valid;
    wire [7:0] mon_data;
    uart_rx #(.CLKS_PER_BIT(CPB)) u_mon (
        .clk(clk), .rst(rst_i), .clk_en(1'b0),
        .rx(uart_tx_pin), .valid(mon_valid), .data(mon_data)
    );

    reg [7:0] capb [0:127];
    integer   capc = 0;
    always begin
        @(posedge clk);
        #1;
        if (mon_valid && capc < 128) begin
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

    // 等待捕获到至少 k 字节（超时判 FAIL）
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

    // 注入一字节（uart_tx 启动帧）
    task inj_byte;
        input [7:0] d;
        begin
            inj_data = d;
            inj_start = 1;
            while (!inj_busy) @(posedge clk);
            inj_start = 0;
        end
    endtask

    integer j, k;
    initial begin
        // ---- 期望 banner 初始化 ----
        expb[ 0]=8'h45; expb[ 1]=8'h45; expb[ 2]=8'h53; expb[ 3]=8'h2D; // E E S -
        expb[ 4]=8'h33; expb[ 5]=8'h33; expb[ 6]=8'h38; expb[ 7]=8'h20; // 3 3 8 sp
        expb[ 8]=8'h52; expb[ 9]=8'h56; expb[10]=8'h33; expb[11]=8'h32; // R V 3 2
        expb[12]=8'h49; expb[13]=8'h20; expb[14]=8'h55; expb[15]=8'h41; // I sp U A
        expb[16]=8'h52; expb[17]=8'h54; expb[18]=8'h20; expb[19]=8'h4F; // R T sp O
        expb[20]=8'h4B; expb[21]=8'h0D; expb[22]=8'h0A;                 // K CR LF

        // ---- 装载固件镜像（console_rom.hex，字节式 @0）----
        for (i = 0; i < 4096; i = i + 1) u_soc.u_cpu.u_imem.mem[i] = 8'h00;
        $readmemh("console_rom.hex", u_soc.u_cpu.u_imem.mem);

        // ---- 复位释放 ----
        repeat (4) @(posedge clk);
        rst_n = 1;

        // ============ P1: banner（23 字节） ============
        wait_cap(BANNER_LEN, 32'd40000, k);
        c("P1 banner 23B captured", k===1);
        for (j = 0; j < BANNER_LEN; j = j + 1)
            c("P1 banner byte", capb[j]===expb[j]);
        c("P1 cap exact (no extra byte yet)", capc===BANNER_LEN);

        // ============ P2: 回显往返（0x55） ============
        repeat (20) @(posedge clk);
        inj_byte(8'h55);
        wait_cap(BANNER_LEN+1, 32'd20000, k);
        c("P2 echo captured", k===1);
        c("P2 echo = 0x55", capb[BANNER_LEN]===8'h55);

        // ============ P3: 长串 8 字符逐字回显（无死锁） ============
        for (j = 0; j < 8; j = j + 1) begin
            inj_byte(8'h30 + j);                       // '0'..'7'
            wait_cap(BANNER_LEN+1+j+1, 32'd20000, k);
            c("P3 echo captured", k===1);
            c("P3 echo = 0x30+j", capb[BANNER_LEN+1+j]===8'h30+j);
        end

        // ============ P4: 复位重跑一致 ============
        rst_n = 0;
        repeat (8) @(posedge clk);
        rst_n = 1;
        wait_cap(BANNER_LEN*2+9, 32'd40000, k);        // 23×2+9 前序字节
        c("P4 banner2 captured", k===1);
        for (j = 0; j < BANNER_LEN; j = j + 1)
            c("P4 banner byte same", capb[BANNER_LEN+9+j]===expb[j]);
        repeat (20) @(posedge clk);
        inj_byte(8'h5A);                               // 'Z'
        wait_cap(BANNER_LEN*2+10, 32'd20000, k);
        c("P4 echo after reset = 0x5A", k===1 && capb[BANNER_LEN*2+9]===8'h5A);

        if (err == 0) $display("=== ALL PASS ===");
        else          $display("=== FAIL === (%0d/%0d)", err, n);
        $finish;
    end

endmodule
