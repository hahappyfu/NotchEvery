# 刘海面板重构规格：520 双页滑动（2026-09-08定稿）

## 背景
刚落地的 Token 三区（600宽 + Tab + 高度表，见 ADR-0005）改为 520×210 紧凑双页。方向：混合（视觉重做 + 复用 zone 语义），访谈结论：设置整搬 Popover、手势只留滑动+dots、数据源沿用 mock、第一页左右并排。

## 架构
- `NotchRootView`：520宽容器，右上齿轮（12pt/0.4），底部 `iOSPageIndicator`，中间双页滑动容器。
- `OverviewPageView`：配额卡（收窄）+ 暂存盘（虚线框）左右并排。
- `TokenMonitorPageView`：现有 `TokenZoneView` 升级——KPI 加绿色填充条、用时加微型耗时条、全数字 `monospacedDigit()`。
- `iOSPageIndicator`：可复用；5px 点（0.3）/ 12px 白胶囊，spring 动画，点击切页。
- Zone 语义保留：page↔zone 映射（normal/token）；settings 移出页面，进齿轮 NSPopover（现有设置整套：动作栏 + 卡片 + 版本行，宽跟内容）。

## 交互
- 切页：双指横扫（复用现有三守卫：展开态 + 面板内 + 未拖文件）+ 点 dots，双向同步。
- 删除：NotchTabBar、顶栏点击切区、方向键切区、三区循环（`zoneOrder` 缩为两页映射）。
- 单源状态：pageIndex 驱动 contentType。

## 高度
- 高度表保留，两页探针重测，目标 210~230，第一页优先不压；窗口跟随当前页，hostedViewHeight 取 max，守卫按新表不断言。

## 测试
- 高度表两页断言、page-zone 映射、dots 激活态；探针重测两页自然高。

## 范围外
- cc-switch 数据源接入（另起工单，mock 留缝）。
- 配额/暂存盘内部逻辑不动，只收窄适配 520。
- 不动 unified log、更新机制、签名姿势。
