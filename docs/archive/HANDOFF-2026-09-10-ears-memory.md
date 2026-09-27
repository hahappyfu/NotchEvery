# 给 DeepSeek 的交接文档（2026-09-10）

> 直接背景：macOS 刘海面板应用 NotchEvery。用户已用 Claude 对完图片、定完共识，本任务只做开发规划与实现。词汇以 `CONTEXT.md` 为准，决策见 `docs/adr/0009-notch-ears-per-zone.md`。

## 1. 图片文字版（Claude 已识别，原图 DeepSeek 不可见）

- **图一 Token 页现状**：面板是浅灰玻璃卡片，底部大圆角，顶部贴菜单栏。顶部一整条空白带（现在只画背景不放字）。下方 KPI 行 `Tokens 38.8M / 缓存命中率 94.6%(+绿条) / 调用 527次 + 齿轮`。再下是请求表，表头 `时间 / 模型 / 入/出 / 用时 / 状态`，5 行如 `14:46 opus-5 524/283 26.8s 200`，其中一行 `14:39 … 429` 红色。
- **图二 概览额度块目标**：左侧大圆环 `0.2%`、下标 `5h`、环顶绿点；右侧两行 `周 + 绿条 20%`、`月 + 红条 92%`；底部 `● 4时47分后重置`。第一页改版目标就是只留这个块、居中。
- **图三 右键菜单**：双指触碰（右键）在面板上呼出的原生小菜单，只有 `设置 / 退出` 两项，浮在额度页上。就是这个弹出很卡。

## 2. 已定共识（实现时照做）

1. 旧「刘海安全区」拆为 **中央禁放区**（挖槽宽＋边距，高＝刘海高＋8pt，只画背景）与 **耳区**（两边可用，各分区自定单行内容、超长截断，高度跨页保留，空白页亦占位）。
2. 概览页耳区留空只画背景；Token 页左耳 `总量·命中率`（如 `38.8M · 94.6%`）、右耳 `调用次数`（如 `527次`）。
3. Token 页原 KPI 行删掉（与耳区重复）；右上齿轮删掉，设置只走右键菜单；概览页暂存盘删掉，只剩额度块居中。
4. **记忆模式（本次运行内）**：收起不重置分区，展开恢复上次所在页；重启回概览，无需持久化；所有收起方式一视同仁。

## 3. 执行任务清单

- [ ] A. 耳区实现（左右耳按分区供内容，单行截断，跨页等高占位）＋删 Token KPI 行＋删右上齿轮（右键菜单接设置）＋概览页删暂存盘只留额度块居中。
- [ ] B. Bug：切页时额度环大数字闪一下残影。嫌疑：`NotchRootView.pages` 的 `zoneSlideNext/Previous` 过渡与 `QuotaCardView` 内 `percent` 的 0.4s 动画、`miniBar` 的 0.3s 动画重叠。
- [ ] C. 优化：双指右键菜单（设置／退出）弹出很卡。
- [ ] D. 记忆模式：去掉 `notchClose()` 与 `notchOpen()` 里 `contentType = .normal` 的重置（含 hover 虚影路径），初值保持 `.normal`。

## 4. 代码入口

- `NotchDrop/NotchViewModel.swift`：`notchOpen`（约 216 行）、`notchClose`（约 235 行）含重置；`pageAnimation` 约 146 行。
- `NotchDrop/NotchRootView.swift`：右上齿轮＋Popover（12–37 行）、`pages` 切页（50–69 行）。
- `NotchDrop/TokenZoneView.swift`：`kpiRow`（102–114 行，待删）。
- `NotchDrop/OverviewPageView.swift`：`HStack { QuotaCardView + TrayView }`（11–23 行，Tray 待删）。
- `NotchDrop/QuotaCardView.swift`：`ring`（123–166 行）、`miniBar`（74–89 行）。
- 右键菜单实现本次未定位，建议顺着 `NSMenu / rightMouseDown` 查。
