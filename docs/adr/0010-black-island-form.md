# 视觉形态重构为纯黑岛（取消玻璃卡片）

面板从「玻璃卡片悬于刘海下方」重构为「纯黑岛从物理刘海向下长出」：岛恒黑（#000，不跟随系统浅色），贴屏幕顶，闲置态与物理刘海完全一致（应用不可见），悬停/展开为同一形状的 morph 生长。目标是产品级刘海岛观感（对标 boring.notch / NotchNook / Dynamic Lake）；玻璃方向已多轮打磨仍不达标，判定为材质路线问题而非参数问题。

> 修订（2026-09-11 实施收尾）：设计原定「凹角（concave fillet）」与屏顶交接——排查证明 macOS 26 的 SwiftUI 对 concave 渲染（自绘路径/Canvas/挖口/mask 溢出）在本机全线不可用（连参考项目原版亦失效，实测存档于 SDD 账本）。最终形态为**凸圆角**（`RoundedRectangle`，四角同径、随状态 13/26pt）。

## Considered Options

- 深色玻璃岛：保留材质与通透感，但仍是「卡片贴在刘海下」的分层观感，否决。
- 跟随系统浅色：浅色下白岛方案，与物理刘海（恒黑硬件）割裂，否决。
- 保持现状玻璃卡片微调：用户明确否决（太丑）。

## Consequences

- 形状层三合一：material 刘海壳 + 0.55 实底玻璃 + destinationOut 凹角 hack 合并为单一黑色圆角岛体（实施收尾定为 `RoundedRectangle` 凸圆角，自绘 `IslandShape` 方案因 macOS 26 concave 渲染失效而废弃并删除）；CONTEXT.md「面板/虚影」词条已按黑岛口径更新。
- 应用不再有跟随系统亮色的分支（像硬件，恒暗）。
- ADR-0008 内容驱动尺寸机制保留，并新增「模型列宽按数据自适应（钳制 [100,180]pt）」的数据驱动层。
- 视觉基准：`docs/superpowers/prototypes/2026-09-11-island-form.html`；完整设计见 `docs/superpowers/specs/2026-09-11-notch-island-redesign-design.md`。
