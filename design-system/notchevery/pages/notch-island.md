# NotchEvery · 黑岛刘海页面规范（Option 1 瘦身版）

> 基于 `../MASTER.md`，锁定 3 页刘海卡片的组件约束、信息密度与可访问性。

## 1. 第 1 页：今日用量（`OverviewDistributionView`）
- **顶部单行总览**：精简为一行紧凑汇总（`总净 Token` · `缓存命中率` · `脱敏 N` + 异常/重试简标），不做四格大 KPI 堆砌，避免与下方排行重复。
- **24h 分时堆叠柱图**：高度 `28pt`，下方附 `00 / 06 / 12 / 18 / 24` 刻标；支持悬停显示该小时读数（`HH:00 · X Tokens · 主力提供商`），不可仅靠颜色区分。
- **维度切换与 Top 5**：右上角三段切换 **`模型·提供商` | `提供商` | `Group`**；行内统一 `.monospacedDigit()` 展示 `净Token · tok/s · 缓存%`（或 `首字 TTFT`）。

## 2. 第 2 页：实时流水（`TokenZoneView`）
- **无拓扑图，高度全数留给流水**：不渲染曲线流向拓扑图，保持 Live Bar + **最近 5 笔 2 行式路由流水**，确保展开面板不拥挤。
- **Live Bar**：状态点 + `今天 N 次` + 汇总/暂停状态 + `pause.circle` / `play.circle.fill` 按钮。
- **单行 2 行式排版**：
  - 首行：`[Agent 胶囊]` + `group/xxx`（或模型）+ 右对齐 `HH:mm:ss`；
  - 次行：`厂商图标 + 提供商 · 账号别名 · 模型短名` + 右对齐 `总Token · 耗时 · tok/s · lock.shield.fill N(若有) · 状态点`。
- **动效**：新行插入用纯 SwiftUI `withAnimation` 绿闪；`accessibilityReduceMotion` 下直接呈现终态。

## 3. 第 3 页：供应商额度（`ProviderQuotaZoneView`）
- **折叠态（默认每家 1 行）**：状态点 + 厂商图标 + 提供商名 + `N 账号` / `429` / `冷却至 HH:mm` 微标 + 横向水位条 + `剩余 / 上限`（无刻度渠道画虚线轨道并显示「无刻度」）。
- **手风琴展开态**：每次展开所选供应商下账号卡——左区显示 `accountNames` 别名 + 套餐 + `quota-history` 虚线 Sparkline + `重置 MM/dd · 预计 Xh 耗尽`；右区横向排列 `1–3` 枚 `26pt` 百分比小圆环（`2.5pt` 描边，12 点顺时针，内嵌 `.monospacedDigit()` 百分比）。
- **受限滚动**：列表外层使用最高 `220pt` 的 `ScrollView`，绝不撑破屏幕 `40%` 高度上限。
