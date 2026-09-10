# 视觉形态重构为纯黑岛（取消玻璃卡片）

面板从「玻璃卡片悬于刘海下方」重构为「纯黑岛从物理刘海无缝长出」：岛恒黑（#000，不跟随系统浅色），贴屏幕顶、与屏顶交接处以凹角连接，闲置态与物理刘海完全一致（应用不可见），悬停/展开为同一形状的 morph 生长。目标是产品级刘海岛观感（对标 boring.notch / NotchNook / Dynamic Lake）；玻璃方向已多轮打磨仍不达标，判定为材质路线问题而非参数问题。

## Considered Options

- 深色玻璃岛：保留材质与通透感，但仍是「卡片贴在刘海下」的分层观感，否决。
- 跟随系统浅色：浅色下白岛方案，与物理刘海（恒黑硬件）割裂，否决。
- 保持现状玻璃卡片微调：用户明确否决（太丑）。

## Consequences

- 形状层三合一：material 刘海壳 + 0.55 实底玻璃 + destinationOut 凹角 hack 合并为单一自绘 IslandShape；实现后 CONTEXT.md「面板/虚影」词条需按黑岛口径更新。
- 应用不再有跟随系统亮色的分支（像硬件，恒暗）。
- ADR-0008 内容驱动尺寸机制保留，并新增「模型列宽按数据自适应（钳制 [100,180]pt）」的数据驱动层。
- 视觉基准：`docs/superpowers/prototypes/2026-09-11-island-form.html`；完整设计见 `docs/superpowers/specs/2026-09-11-notch-island-redesign-design.md`。
