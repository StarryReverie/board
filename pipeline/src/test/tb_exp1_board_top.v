//=============================================================================
// tb_exp1_board_top.v — 实验一独立上板顶层回归（exp1_board_top）
//   验什么：
//     ① 复位同步器：按键保持期间 core 不复位释放（LED1 不亮）；
//     ② 事件锁存：load-use 停顿、分支重定向、dmem 写入三盏灯都点亮；
//     ③ 验收判据：签名 dmem[0]=0x0F 且进入 HALT → LED6(PASS) 亮、LED7(FAIL) 不亮；
//     ④ 显示通路：数码管数据 = 0000000F，且位选到 digit0 时段选译码为 'F'。
//   参数覆写说明：CLK_HZ/超时/扫描分频按"仿真尺度"缩小，只影响板级计时与
//     扫描快慢，不改变任何判据逻辑（判据与真实 100 MHz 构建完全一致）。
//   程序：exp1_board_demo_rom.hex（与 tb_prog_board_demo 同源镜像）
//=============================================================================
`timescale 1ns/1ps

module tb_exp1_board_top;

    reg  clk = 0;
    reg  rst_n = 0;               // 板上按键：低有效（初始按住）

    wire [7:0] led;
    wire [7:0] seg0, seg1, an;

    integer err = 0;
    integer n   = 0;
    integer i;
    integer guard;

    // 仿真尺度参数：1 kHz 等效 → 心跳 500 拍、超时 1500 拍；扫描 2^2=4 拍/位
    exp1_board_top #(
        .CLK_HZ        (1_000),
        .HEART_MS      (500),
        .TIMEOUT_MS    (1500),
        .SEG_EN        (1),
        .SCAN_DIV_BITS (2)
    ) u_board (
        .clk   (clk),
        .rst_n (rst_n),
        .led   (led),
        .seg0  (seg0),
        .seg1  (seg1),
        .an    (an)
    );

    always #5 clk = ~clk;


    task c;
        input [511:0] name;
        input         ok;
        begin
            n = n + 1;
            if (!ok) begin err = err + 1; $display("FAIL: %0d %0s", n, name); end
            else $display("PASS: %0d %0s", n, name);
        end
    endtask

    initial begin
        for (i = 0; i < 4096; i = i + 1) u_board.u_cpu.u_imem.mem[i] = 8'h00;
        $readmemh("exp1_board_demo_rom.hex", u_board.u_cpu.u_imem.mem);

        // ---- ① 按键保持期间 ----
        repeat (40) @(posedge clk);
        #1;
        c("held: LED1(reset_done)=0", led[1] === 1'b0);
        c("held: LED6(PASS)=0",       led[6] === 1'b0);
        c("held: LED7(fault)=0",      led[7] === 1'b0);
        c("held: core rst=1 (async assert)", u_board.rst === 1'b1);

        // 心跳自由运行：40 拍（HEART_MS=500 → 半周期 500 拍）尚未翻转，先看计数器在走
        c("heart counter running", u_board.heart_cnt !== 32'd0);

        // ---- ② 释放按键 → 程序自跑 ----
        rst_n = 1;
        repeat (600) @(posedge clk);
        #1;

        c("released: core rst=0 (sync release)", u_board.rst === 1'b0);
        c("released: LED1(reset_done)=1", led[1] === 1'b1);
        c("released: LED2(cpu_started)=1", led[2] === 1'b1);
        c("released: LED3(load-use stall)=1", led[3] === 1'b1);
        c("released: LED4(branch taken)=1", led[4] === 1'b1);
        c("released: LED5(dmem write)=1", led[5] === 1'b1);

        // ---- ③ 验收判据 ----
        c("signature captured = 0x0000000F", u_board.sig_data === 32'h0000_000F);
        c("HALT detected (dbg_halt latched)", u_board.halt_seen === 1'b1);
        c("LED6 PASS = 1", led[6] === 1'b1);
        c("LED7 fault/timeout = 0", led[7] === 1'b0);

        // 心跳应已翻转（600 拍 > 半周期 500 拍）
        c("heartbeat toggled", u_board.heart === 1'b1);

        // ---- ④ 显示通路 ----
        c("seg display data = 0x0000000F", u_board.disp === 32'h0000_000F);

        // 等位选扫到 digit0（an==8'h01；扫描 4 拍/位，32 拍一帧）
        guard = 0;
        while ((an !== 8'h01) && (guard < 200)) begin
            @(posedge clk);
            guard = guard + 1;
        end
        #1;
        c("an one-hot reached digit0", an === 8'h01);
        c("digit0 nibble = 0xF", u_board.nib === 4'hF);
        c("digit0 segment = 'F' (0x71)", seg0 === 8'h71);
        c("seg1 driven (same bus pattern)", seg1 === seg0);
        c("scan digit unique one-hot", (an & (an - 8'd1)) === 8'd0);

        if (err == 0) $display("=== ALL PASS ===");
        else          $display("=== FAIL === (%0d/%0d)", err, n);
        $finish;
    end

endmodule
