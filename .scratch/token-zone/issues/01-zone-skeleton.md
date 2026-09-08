# 01-zone-skeleton：token 分区骨架 + 请求表格（mock）

## 目标
切出第三区并能看：Token Tab 可进，5 行 6 列请求表格 mock 渲染，不溢出。

## 改动
- `NotchViewModel.ContentType` 加 `.token`（tabTitleKey "Token"）；`zoneOrder` 加 `.token`；`zonePanelHeight` 加 `.token` 初值（先估 260，03 工单实测后定）。
- 新文件 `NotchDrop/TokenZoneView.swift`：`TokenRequest` mock 模型（time/model/input/output/duration/cost/status/cached，截图同构 6 行取 5）+ 表格视图（VStack 行，不用 List）。
- `NotchContentView` 加 `case .token` 分支 + `zoneHeightReporter(active:)`；`NotchTabBar` 加第三段。
- 状态丸配色复用 `QuotaCardView.ringColor` 语义（本文件内小函数，不改 QuotaCard）。

## 验证
- Debug 编译过；切 token 区守卫不断言；窗口高度跟随变化。
- 表值测试：`zonePanelHeight` 含 `.token`。

## 阻塞
- 被阻塞：无。阻塞：02。
