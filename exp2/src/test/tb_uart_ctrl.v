//=============================================================================
// tb_uart_ctrl.v — uart_ctrl 单测（exp2 U12；interface.md §3 / uart_ctrl.md）
//   CLKS_PER_BIT=4（bit=40ns）。事件等待用层次信号（确定性），
//   总线语义用定点读（组合值在置位后 2ns 采样）。
//   检查：默认槽读 0；写 TX 触发发送（STAT.TX_BUSY 翻转）；忙时写丢弃；
//         RX 收字节（STAT.RX_VALID）→ 读槽取字节 → 读后清位；
//         未读期间新字节丢弃（保留首字节）；写 STAT/RX 无操作。
//=============================================================================
`timescale 1ns/1ps

module tb_uart_ctrl;

    localparam CPB = 4;

    reg        clk = 0;
    reg        rst = 1;
    reg        cs_mmio = 0;
    reg  [1:0] reg_off = 0;
    reg        we = 0;
    reg  [31:0] wdata = 0;
    wire [31:0] rdata;
    wire       uart_tx_pin;
    reg        uart_rx_pin = 1;

    integer err = 0;
    integer n   = 0;
    integer k;

    uart_ctrl #(.CLKS_PER_BIT(CPB)) dut (
        .clk(clk), .rst(rst),
        .cs_mmio(cs_mmio), .reg_off(reg_off), .we(we), .wdata(wdata),
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
        begin cs_mmio <= 0; we <= 0; reg_off <= 0; wdata <= 0; end
    endtask

    // 写槽：保持一个沿（末沿锁存）
    task bus_write;
        input [1:0] slot;
        input [31:0] val;
        begin
            cs_mmio <= 1; we <= 1; reg_off <= slot; wdata <= val;
            @(posedge clk);
            #1 bus_idle();
        end
    endtask

    // 组合读槽（置位 2ns 后采样；保持 cs 直到 @(posedge) 后释放，供"读清位"用）
    task read_slot_hold;
        input [1:0] slot;
        output [31:0] val;
        begin
            cs_mmio <= 1; we <= 0; reg_off <= slot;
            #2;
            val = rdata;
        end
    endtask

    // 层次等待：busy 出现
    task wait_busy_hi;
        input [15:0] maxcyc;
        output seen;
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
        input [15:0] maxcyc;
        output seen;
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

    // 层次等待：rx_valid 置位
    task wait_rxv;
        input [15:0] maxcyc;
        output seen;
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

    // ---- 串行发送（喂 RX 引脚）----
    task sbit;
        input b;
        begin uart_rx_pin = b; #(CPB*10); end
    endtask
    task send_byte;
        input [7:0] byte;
        integer bi;
        begin
            sbit(1'b0);
            for (bi = 0; bi < 8; bi = bi + 1) sbit(byte[bi]);
            sbit(1'b1);
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        rst = 0;
        #1;

        // ---- 默认读：各槽 0 / cs=0 读 0 / TX 空闲 ----
        read_slot_hold(2'b00, wdata); c("TX rd=0", wdata===0);
        @(posedge clk); #1 bus_idle();
        read_slot_hold(2'b01, wdata); c("STAT rd=0", wdata===0);
        @(posedge clk); #1 bus_idle();
        read_slot_hold(2'b10, wdata); c("RX rd=0", wdata===0);
        @(posedge clk); #1 bus_idle();
        read_slot_hold(2'b11, wdata); c("rsv rd=0", wdata===0);
        @(posedge clk); #1 bus_idle();
        bus_idle();
        #1 c("cs=0 rd=0", rdata===0);
        c("tx idle high", uart_tx_pin===1'b1);

        // ---- 写 TX（空闲接受）→ busy 出现/消失，STAT 位正确 ----
        bus_write(2'b00, 32'h5A);
        wait_busy_hi(200, k); c("busy seen", k===1);
        read_slot_hold(2'b01, wdata); c("STAT busy=1", wdata[0]===1'b1);
        @(posedge clk); #1 bus_idle();
        wait_busy_lo(80, k); c("busy cleared", k===1);
        #1 c("tx back idle", uart_tx_pin===1'b1);
        read_slot_hold(2'b01, wdata); c("STAT busy=0", wdata[0]===1'b0);
        @(posedge clk); #1 bus_idle();

        // ---- 忙时写 TX 丢弃（不产生第二帧）----
        bus_write(2'b00, 32'hA1);
        wait_busy_hi(80, k); c("2nd busy seen", k===1);
        bus_write(2'b00, 32'hB2);          // 忙中写：应丢弃
        wait_busy_lo(80, k); c("2nd cleared", k===1);
        // 再等 12 个 bit 时间，确认没有新的 busy（未误发）
        #(CPB*10*12);
        c("no second frame (drop ok)", dut.tx_busy===0 && uart_tx_pin===1'b1);

        // ---- RX：收 0x3C → RX_VALID 置位 → 读槽取字节 → 读后清位 ----
        send_byte(8'h3C);
        wait_rxv(80, k); c("RX_VALID seen", k===1);
        read_slot_hold(2'b10, wdata); c("RX byte=0x3C", wdata[7:0]===8'h3C);
        @(posedge clk);                    // 读后清位（访存段末沿）
        #1 bus_idle();
        c("rx_valid cleared", dut.rx_valid===0);
        read_slot_hold(2'b01, wdata); c("STAT valid=0", wdata[1]===1'b0);
        @(posedge clk); #1 bus_idle();

        // ---- 溢出丢弃：未读期间第二字节被丢，保留 0x11 ----
        send_byte(8'h11);
        wait_rxv(80, k); c("0x11 valid", k===1);
        send_byte(8'h22);                  // 未读期间到达
        #(CPB*10*16);                      // 等第二帧处理完
        c("still holds 0x11", dut.rx_valid===1);
        read_slot_hold(2'b10, wdata); c("RX keeps 0x11", wdata[7:0]===8'h11);
        @(posedge clk); #1 bus_idle();
        c("cleared after read", dut.rx_valid===0);

        // ---- 写 STAT/RX 无操作 ----
        bus_write(2'b01, 32'hFFFFFFFF);
        c("write STAT noop", dut.rx_valid===0);
        bus_write(2'b10, 32'hFFFFFFFF);
        c("write RX noop", dut.rx_valid===0 && dut.rx_byte===8'h11);

        if (err == 0) $display("=== ALL PASS ===");
        else          $display("=== FAIL === (%0d/%0d)", err, n);
        $finish;
    end

endmodule
