# 两页高度终值：探针重测 + 头部行删除

任务 8 文件探针法三次部署实测一致：概览页自然高 105（配额卡环 68+标签+内边距），Token 页自然高 164（KPI 单行 + 表头 + 5 行），dots 行实高 13（VStack 间距 6，内容帧内固定 chrome = 19）。

决定：执行方案 C——删 `NotchView.swift` 头部行挂载（TabBar 任务 5 已删，残留 gear 与任务 6 根齿轮重复、且点之进入空白 settings 页），`HeaderProbe`（tab-pin TEMP）一起删；终值 `.normal: 165, .token: 224`，推导 `H = natural + 19（dots）+ 40（上下 padding）+ 1pt 余量`；`zoneContentHeight` 改为 `zoneOpenedSize.height - spacing * 2`，注释同步。

## Considered Options

- A（`H = natural + 40` → 145/204）：被否——与布局恒等式冲突，窗口底部裁剪 49pt（dots + Token 约 2 行消失）。
- B（保留头部行 → 213/272）：被否——Token 272 远超 210~230，需砍 42pt 内容，毁掉任务 7 刚落地的表。
- 简报字面公式漏了 dots 19，已用 `DOTS-PROBE h=13.0` 纠正为 +60（含 1pt 余量）。

## Consequences

- `headerSlotHeight = 29` 常量与 `zonePanelHeight[.settings] = 284`、`hostedViewHeight = max()` 不动（他人在途测试 hunk 锁定 29/284，最小半径）。
- 概览 165 低于目标区间 210~230：用户已接受，内容就这么多，不加空白硬撑，如实记录。
- Token 224 落在 210~230 区间内。
- 数据源仍 mock，全程未碰。
