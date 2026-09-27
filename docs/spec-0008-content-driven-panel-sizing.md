# SPEC-0008：内容自适应面板

基于 ADR-0008（访谈 8 轮共识）。取代 `zonePanelHeight` 查表：内容量出尺寸，面板跟着走。

> **注记（2026-09-27 审计）**：成功标准中的最小尺寸（本文写 ≥ 320×120，实为 160×60，见 `NotchViewModel.minPanelSize`）与「霜化玻璃 dots」（标准 5）两项已被后续迭代取代，以 ADR-0008 修订注记与代码为准。

## 成功标准

1. 概览/Token 两页不再有固定高度：内容增减时面板宽高跟着变，不裁剪、不留大片空白。
2. 面板尺寸有界：≥ 320×120，≤ 640 宽 × 屏幕高 40%；超限内容在内部滚动/裁剪，外层不动。
3. 顶边中心钉死：尺寸变化只往下和向两侧长；刘海区（物理刘海高 + 8pt）无内容。
4. 分区切换宽高走同一条弹簧曲线（现 `animation`，苹果手感）。
5. 底部 dots 为霜化玻璃悬浮胶囊、严格居中（对照参考图）。
6. 设置 Popover 不动；`headerSlotHeight = 29` 常量保留。

## 非目标

- 设置 Popover 改尺寸；数据源去 mock；新分区；提交合并（等用户拍板）。

## 工单（串行，阻塞边界明确）

### T1 测量驱动：自然尺寸上报（宽+高）
- 内容：`ZoneHeightGuard` 从只量高扩展为量宽+高（`ZoneNaturalSizeKey`，PreferenceKey 取最大合并，`active` 静默语义保留）；各区挂报告器；Debug 断言改为"超最大界才告警"。
- 验证：build 通过；新增/改测试断言测量 key 合并语义。
- 阻塞：无。前置：无。

### T2 面板/窗口跟随测量尺寸
- 内容：删 `zonePanelHeight`、`zonePanelWidth`、`hostedViewHeight`、`zoneContentHeight` 查表语义；`NotchWindowController` 跟随测量尺寸（含钳制 min/max、顶边中心锚定、同一弹簧动画）；`NotchViewModel.zoneOpenedSize` 改为测量值驱动；重写 `TabMetricsTests` 锁死旧高度的断言（改锁钳制边界与跟随关系）。
- 验证：build 通过；测试全过；截图两页无裁剪。
- 阻塞：T1（需要测量值）。

### T3 刘海安全区
- 内容：内容顶边避让 `deviceNotchRect.height + 8pt`（逐屏取值，无刘海屏用现有兜底）；安全区只画背景。
- 验证：截图确认刘海区无文字/控件；换屏（内外屏）取值正确（如只有一屏则代码走读确认）。
- 阻塞：T2（面板 frame 确定后才有地方垫）。

### T4 玻璃 dots 重做
- 内容：`iOSPageIndicator` 去黑底，霜化玻璃胶囊悬浮、两点居中（激活白、非激活 `white 0.35`），与内容拉开间距（对照参考图定）；点击语义不变。
- 验证：截图对照参考图；点击切换仍有效。
- 阻塞：T2（面板宽度不定后才能确认居中）。

### T5 收尾：清理 + 审查 + 验证
- 内容：删 TEMP-DEL 埋点（`TEMP-ringFrame`/`TEMP-panelFrame`）与 DEBUG 强制展开；`CONTEXT.md` 移除高度表词条；code-review 双轴（Standards + Spec）；verification-before-completion（build + 双页截图）。
- 验证：`git diff` 无调试残留；测试全过。
- 阻塞：T1–T4。完成后停下等合并拍板（不自行提交）。

## 依赖关系

T1 → T2 → {T3, T4} → T5。T3/T4 仍串行（单开规则）。
