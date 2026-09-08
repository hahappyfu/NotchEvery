# 03-height-tests：高度实测落表 + 测试 + 清理

## 目标
token 区高度从估算变实测，测试锁表，删一次性原型。

## 改动
- 实测 token 区内容自然高（探针/TEMP-DIAG 量一次），更新 `zonePanelHeight[.token]` 到实测值；`hostedViewHeight` 重算（仍取 max）。
- 补表值测试（`.token` 条目存在且 = 实测值）；状态丸阈值小测试。
- 删 `.scratch/token-zone-prototype.html`；ADR-0005 补实测值。
- 移除本次引入的 TEMP 诊断代码（只清理自己造的）。

## 验证
- Debug + Release 编译过；三区各切一遍守卫不断言；测试全绿。

## 阻塞
- 被 02 阻塞。后接：数据源接入工单（另起，不在本次）。
