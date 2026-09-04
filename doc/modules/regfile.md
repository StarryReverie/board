# regfile 模块文档（寄存器堆：ID 读口 + WB 写口）

- `rtl/regfile.v`。参考 `ref/CPU/regfile.v`；改造：新增 **读旁路（write-first）**，消除 WB/ID 同拍写读陈旧。

## 端口
| 方向 | 名称 | 位宽 | 说明 |
|---|---|---|---|
| in | clk / rst | 1 | rst 异步高有效清全 0 |
| in | raddr1 / raddr2 | 5 | 读地址（decode 的 rs1/rs2） |
| in | waddr | 5 | 写地址（WB 的 rd） |
| in | wdata | 32 | 写数据（wb_data） |
| in | we | 1 | 写使能（wb_we） |
| out | rdata1 / rdata2 | 32 | 读数据 |

## 功能/时序
- `reg [31:0] x[1:31]`，x0 恒 0；写 waddr=0 无效。
- 写：posedge clk（rst 清零；we 且 waddr≠0 → x[waddr]<=wdata）。
- 读（组合 + 旁路）：
  - `rdata1 = (raddr1==0) ? 0 : (we && waddr==raddr1 && raddr1!=0) ? wdata : x[raddr1]`（rdata2 同理）。
- 时序说明：读在 ID 段、写在 WB 段末沿；"写回恰在 WB、消费者恰在 ID"同拍时旁路返回当拍 wdata，避免陈旧值进 ID/EX（其余 RAW 由前递覆盖，见 hazard_unit）。

## 连接
- raddr ← decode.rs1/rs2；写口 ← wb(wb_rd/wb_data/wb_we)；rdata → id_ex.rs1_data/rs2_data。

## 验收
- 复位全 0；写后读一致；x0 读恒 0 / 写 x0 无效；旁路：同拍 we=1 写 rd 与读 rd 相同返回 wdata。
