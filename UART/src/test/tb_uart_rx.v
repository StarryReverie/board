//=============================================================================
// tb_uart_rx.v — uart_rx 单测（exp2 U11，doc/modules/uart_rx.md 验收）
//   CPB=8（1 bit=80ns；clk 周期 10ns）
//   检查：复位空闲；正常帧逐位还原；背靠背两字节；停止位=0 帧错误丢弃；
//         短毛刺不误启动；恢复后继续收。
//   注：rx 驱动与模块检测相对相位随机（≤1 clk），帧长 10 bit 保证中心对齐。
//=============================================================================
`timescale 1ns/1ps

module tb_uart_rx;

    localparam CPB = 8;

    reg        clk = 0;
    reg        rst = 1;
    reg        clk_en = 0;
    reg        rx = 1;
    wire       valid;
    wire [7:0] data;

    integer err = 0;
    integer n   = 0;
    integer k;

    uart_rx #(.CLKS_PER_BIT(CPB)) dut (
        .clk(clk), .rst(rst), .clk_en(clk_en), .rx(rx),
        .valid(valid), .data(data)
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

    // 发送 1 bit（保持给定电平一个位时间）
    task send_bit;
        input b;
        begin
            rx = b;
            #(CPB*10);
        end
    endtask

    // 发送一帧；stop_ok=0 用于帧错误用例
    task send_frame;
        input [7:0] byte;
        input       stop_ok;
        integer bi;
        begin
            send_bit(1'b0);                       // 起始位
            for (bi = 0; bi < 8; bi = bi + 1)
                send_bit(byte[bi]);                // 数据 LSB 先
            send_bit(stop_ok ? 1'b1 : 1'b0);      // 停止位
        end
    endtask

    // ---- valid/data 锁存监视器（沿后 1ns，捕获 1 拍脉冲）----
    reg        valid_lat = 0;
    reg  [7:0] data_lat  = 0;
    always begin
        @(posedge clk);
        #1;
        if (valid) begin
            valid_lat <= 1'b1;
            data_lat  <= data;
        end
    end

    task reset_latch;
        begin
            valid_lat <= 0;
        end
    endtask

    // 等待 valid 锁存（限拍窗口）；返回是否捕获
    task wait_valid;
        output okv;
        integer kk;
        begin
            okv = 0;
            for (kk = 0; kk < CPB*14; kk = kk + 1) begin
                @(posedge clk);
                if (valid_lat) begin okv = 1; kk = CPB*14; end
            end
        end
    endtask

    initial begin
        // 复位
        repeat (4) @(posedge clk);
        rst = 0;
        #1 c("reset idle", valid===0 && data===8'h00);

        // ---- 正常帧 0x53 ----
        reset_latch();
        send_frame(8'h53, 1'b1);
        wait_valid(k);
        c("frame0x53 valid", k===1);
        c("frame0x53 data", data_lat===8'h53);

        // ---- 背靠背 0xA5 -> 0x3C ----
        reset_latch();
        send_frame(8'hA5, 1'b1);
        wait_valid(k);
        c("0xA5 valid", k===1);
        c("0xA5 data", data_lat===8'hA5);

        reset_latch();
        send_frame(8'h3C, 1'b1);
        wait_valid(k);
        c("0x3C valid", k===1);
        c("0x3C data", data_lat===8'h3C);

        // ---- 帧错误（停止位=0）：无 valid ----
        // 注意：stop=0 使线路停低，模块在停止位中心判错回 IDLE 后，剩余低电平
        // 会被当成新起始位候选——TB 须立即把 rx 拉高（真实发送方回空闲），
        // 模块在"起始中心复检"处会因电平为高而拒绝该误触发。
        reset_latch();
        send_frame(8'h55, 1'b0);
        send_bit(1'b1);                            // 立刻回空闲（勿留低电平窗口）
        wait_valid(k);
        c("frame-error no valid", k===0);
        // 状态回 IDLE 后能继续收（证明丢弃路径正确）
        reset_latch();
        send_frame(8'h77, 1'b1);
        wait_valid(k);
        c("recover valid", k===1);
        c("recover data", data_lat===8'h77);

        // ---- 短毛刺（~0.25 bit）不误启动 ----
        reset_latch();
        rx = 0;
        #(CPB*10/4);
        rx = 1;
        #(CPB*10);                                // 回到空闲若干位
        wait_valid(k);
        c("glitch no frame", k===0);
        // 毛刺后仍可正常接收
        reset_latch();
        send_frame(8'h01, 1'b1);
        wait_valid(k);
        c("post-glitch valid", k===1);
        c("post-glitch data", data_lat===8'h01);

        if (err == 0) $display("=== ALL PASS ===");
        else          $display("=== FAIL === (%0d/%0d)", err, n);
        $finish;
    end

endmodule
