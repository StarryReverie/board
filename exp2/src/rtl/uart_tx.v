`timescale 1ns/1ps
//=============================================================================
// uart_tx.v — 8N1 发送器（UART IP，exp2）
//   文档：exp2/doc/modules/uart_tx.md
//   口径：
//     - 帧：1 起始 + 8 数据(LSB 先) + 1 停止，无校验；
//     - 节拍：clk_en = **每 bit 时间一个脉冲**（外部分频产生，
//       脉冲间隔=CLKS_PER_BIT 个系统时钟，115200@100MHz → 868）；
//       本模块每个 clk_en 脉冲推进一个 bit 阶段；
//     - 接受：start && !busy（busy=state!=IDLE，组合）时锁存开始；
//     - done 在停止位完成脉冲拍输出 1 拍；
//     - tx：空闲/停止=1、起始=0、数据=shift[0]（LSB 先）。
//=============================================================================

module uart_tx #(
    parameter [15:0] CLKS_PER_BIT = 16'd868   // 仅信息性：脉冲间隔由外部分频决定
) (
    input  wire       clk,
    input  wire       rst,          // 异步高有效
    input  wire       clk_en,       // bit 节拍脉冲（每 bit 时间 1 拍）
    input  wire       start,
    input  wire [7:0] data,
    output wire       busy,         // 组合：=state!=IDLE
    output wire       done,
    output wire       tx
);

    localparam [1:0] S_IDLE  = 2'd0,
                     S_START = 2'd1,
                     S_DATA  = 2'd2,
                     S_STOP  = 2'd3;

    reg  [1:0] state;
    reg [2:0]  bit_idx;
    reg [7:0]  shift;

    assign tx = (state == S_IDLE || state == S_STOP) ? 1'b1 :
                (state == S_START)                   ? 1'b0 :
                                                       shift[0];

    assign busy = (state != S_IDLE);
    assign done = clk_en && (state == S_STOP);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state   <= S_IDLE;
            bit_idx <= 3'd0;
            shift   <= 8'd0;
        end else if (clk_en) begin
            case (state)
                S_IDLE: begin
                    bit_idx <= 3'd0;
                    if (start) begin
                        state <= S_START;
                        shift <= data;
                    end
                end
                S_START: begin
                    state <= S_DATA;              // 起始位 1 个 bit 时间
                end
                S_DATA: begin
                    if (bit_idx == 3'd7) begin
                        state <= S_STOP;
                    end else begin
                        bit_idx <= bit_idx + 3'd1;
                        shift   <= {1'b0, shift[7:1]};   // 下一位移到 LSB
                    end
                end
                S_STOP: begin
                    state <= S_IDLE;              // 停止位 1 个 bit 时间，done 同拍
                end
            endcase
        end
    end

endmodule
