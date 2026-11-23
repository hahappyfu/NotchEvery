# Design System Master: NotchEvery

> **Platform**: macOS 13.0+ 原生 SwiftUI + AppKit（无 WebView、无第三方 UI 框架）
> **Page Override**: 各刘海页规范见 `pages/notch-island.md`（存在时覆盖全局默认值）

## 1. 核心色板（沿用 `NotchDrop/DesignSystem.swift` 与 `ADR-0010`）

| 语义角色 | 取值 | Swift Token / 用途 |
| :--- | :--- | :--- |
| 岛体背景 | `#000000` | 恒黑（不跟随系统浅深色，贴合物理刘海） |
| 卡片底色 | `Color.white.opacity(0.05)` | `StudioMaterial.cardBackground`（悬停 `0.09`、选中 `0.12`） |
| 卡片描边 | `Color.white.opacity(0.10)` | `StudioMaterial.strokeNormal`（`0.5pt`） |
| 主文本 | `Color.white.opacity(0.94)` | 标题、核心数值、模型短名 |
| 次要文本 | `Color.white.opacity(0.68)` | 账号别名、时间戳、行内元信息（深黑底对比度 `>= 4.5:1`） |
| 刻度轴标 | `Color.white.opacity(0.55)` | 柱图时间刻标、次要分隔提示 |
| 正常 / 高缓存 | `#10B981` | `StudioColor.emerald` |
| 信息 / 中缓存 / 脱敏 | `#06B6D4` / `#5AC8FA` | `StudioColor.cyan` |
| 警告 / 限流 / 低缓存 | `#F59E0B` | `StudioColor.amber` |
| 封禁 / 异常 | `#F43F5E` | `StudioColor.rose` |

## 2. 原生排版与间距步进

- **字体**：macOS 系统字体 SF Pro；所有动态数值、百分比、`tok/s`、耗时、倒计时必须使用 `.monospacedDigit()`，杜绝刷新跳动。
- **字号层级**：主数值 `13pt` Bold；卡片标题/行主文本 `11pt` Semibold；次要元信息 `9.5–10pt` Regular/Medium；禁止低于 `9pt` 的不可读字号。
- **间距步进**：`4pt / 8pt / 12pt / 16pt / 18pt`；外层 `panelContentInset = 18pt`，内容页宽 `420pt`–`430pt`（受 `ZoneSizeGuard` `640pt` 上限与屏幕高度 `40%` 约束）。
- **图标纪律**：结构图标一律使用 SF Symbols 或 Magpie 本地厂商图标，禁止使用字符 Emoji。
- **交互与动效**：悬停只改变底色/描边透明度，不做引发布局位移的缩放；所有过渡均需检查 `@Environment(\.accessibilityReduceMotion)`。
