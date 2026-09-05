`timescale 1ns/1ps
//=============================================================================
// uart_rx.v — 8N1 接收器（UART IP，exp2）
//   文档：exp2/doc/modules/uart_rx.md
//   口径：
//     - 输入 rx 内部打两拍（rx1/rx2）防亚稳态；
//     - 位定时：内部以**系统时钟**计数（参数 CLKS_PER_BIT），
//       起始位下降沿后经 CPB/2 拍到达位中心，此后每 CPB 拍采样下一位中心
//       （clk_en 端口保留以与 uart_tx 接口对齐，本模块内不参与计数）；
//     - 帧：起始位中心复检 → 8 数据位(LSB 先, shift[bit_idx]) → 停止位校验；
//     - 停止位=1：valid 输出 1 拍、data=shift；=0（帧错误）：丢弃不置 valid；
//     - 复位后空闲；短毛刺（<~0.5 bit）在起始复检处被拒。
//=============================================================================

module uart_rx #(
    parameter [15:0] CLKS_PER_BIT = 16'd868
) (
    input  wire       clk,
    input  wire       rst,          // 异步高有效
    input  wire       clk_en,       // 保留（与 uart_tx 同参对齐；内部不参与计数）
    input  wire       rx,
    output reg        valid,        // 收毕脉冲（1 拍）
    output reg  [7:0] data
);

    localparam [1:0] S_IDLE = 2'd0,
                     S_HALF = 2'd1,     // 起始位中心复检
                     S_DATA = 2'd2,
                     S_STOP = 2'd3;
    localparam [15:0] HALF_TICKS = CLKS_PER_BIT >> 1;

    reg        rx1, rx2;
    reg  [1:0] state;
    reg [15:0] cnt;
    reg  [2:0] bit_idx;
    reg  [7:0] shift;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            rx1     <= 1'b1;
            rx2     <= 1'b1;
            state   <= S_IDLE;
            cnt     <= 16'd0;
            bit_idx <= 3'd0;
            shift   <= 8'd0;
            valid   <= 1'b0;
            data    <= 8'd0;
        end else begin
            // 输入两拍同步
            rx1 <= rx;
            rx2 <= rx1;

            valid <= 1'b0;             // 默认无脉冲

            case (state)
                S_IDLE: begin
                    cnt <= 16'd0;
                    if (!rx2) begin
                        state <= S_HALF;      // 下降沿候选
                    end
                end

                S_HALF: begin
                    cnt <= cnt + 16'd1;
                    if (cnt == HALF_TICKS - 16'd1) begin
                        cnt <= 16'd0;
                        if (!rx2) begin        // 中心仍为低：起始位确认
                            state   <= S_DATA;
                            bit_idx <= 3'd0;
                        end else begin         // 毛刺：放弃
                            state <= S_IDLE;
                        end
                    end
                end

                S_DATA: begin
                    cnt <= cnt + 16'd1;
                    if (cnt == CLKS_PER_BIT - 16'd1) begin
                        cnt <= 16'd0;
                        shift[bit_idx] <= rx2;            // 位中心采样，LSB 先
                        if (bit_idx == 3'd7) begin
                            state <= S_STOP;
                        end else begin
                            bit_idx <= bit_idx + 3'd1;
                        end
                    end
                end

                S_STOP: begin
                    cnt <= cnt + 16'd1;
                    if (cnt == CLKS_PER_BIT - 16'd1) begin
                        cnt   <= 16'd0;
                        state <= S_IDLE;
                        if (rx2) begin         // 停止位=1：帧成功
                            valid <= 1'b1;
                            data  <= shift;
                        end
                        // 停止位=0：帧错误，丢弃
                    end
                end
            endcase
        end
    end

endmodule
