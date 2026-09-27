# 审计发现存档：测试套件（reviewer-tests）

> 审计日期：2026-09；审计方式：全项目基线审计（superpowers requesting-code-review 适配），5 片并行。
> 本文件为中间存档，最终汇总见 audit-2026-09-sep 汇总报告。

## 可运行性结论
NotchEveryTests target 在 xcodeproj 真实存在（project.pbxproj:472-487），Fixtures 三份齐全，昨晚 281 测试全绿记录可佐证本机可跑。约 255 个测试方法（31 文件，2 个空壳）。

## Critical
1. Tests/TrayDropTests.swift:6-12 空壳测试零断言（testExpiredItemIsCleaned、testLoadPartialSuccessKeepsSucceeded 只有 TODO 注释），编译进 bundle 以「通过」计入总数。被测行为在 TrayDrop.swift:65-142 / :118-129 / TrayDrop+DropItem.swift:148-155。最小补测：损坏+完好 JSON fixture 断言 load() 保留完好项；过期记录断言被清理。
2. SignalPipeline.swift（178 行）完全无测试。纯确定性数学（Kalman/IQR/EWLR），全仓库性价比最高空白。补测：固定 now 序列喂稳定 RSSI 断言 accept，野值断言 IQR 剔除、基线不被带偏。
3. SecurityService.swift（188 行）无测试且不可测：单例+private init+硬编码 SecItem+NSAlert.runModal。handlePasswordChanged(:115-132) 分支无法验证；errSecInteractionNotAllowed→coldBoot 映射判错=用户数据不可恢复。补测需先小幅可测化重构（抽注入闭包）。

## Important
4. Tests/ContentZoneSwitcherTests.swift:7,17,25,38,52 + Tests/TabMetricsTests.swift:52 直接改 ConfigStore.shared 全局单例且不恢复（testGatewayZoneExcludedWhenDisabled 设 false 不还原）；NotchViewModel.zoneOrder static 读 ConfigStore.shared（NotchViewModel.swift:355-357）→ 测试顺序依赖。修法：独立 suite 模式或 tearDown 恢复。
5. Tests/AnimationMetricsTests.swift:7,20,28 无参 NotchViewModel() 落入 EventMonitors.shared（其 init 启动 5 个真实全局事件监视器）；notchOpen(.click) 调 NSApp.activate（NotchViewModel.swift:331）。应改 MockEventMonitors + 注入 activateApp 闭包。
6. Tests/AntigravityStoreTests.swift:36-76 testSelectAccountUpdatesMemoryAndDisk flaky：asyncAfter(0.2) 猜写盘时序 + 异步闭包内断言，磁盘慢即假失败、失败时 expectation 永不 fulfill。改轮询模式（仓库已有 waitForPersistedItemCount 先例）。
7. NotchViewModel ghost 收起状态机零覆盖（NotchViewModel.swift:250-264,288-309：scheduleHoverClose 120ms、closeToGhost 两段、ghostGeneration 代际防错）。补测：hoverClose→ghost→reopen，断言旧代际延迟关闭不触发。
8. NotchGeometry/notchOpenedRect（NotchViewModel.swift:37-44）零覆盖：零宽刘海/负缩放/多屏缩放无测试。补测：deviceNotchWidth=0、大缩放 screenRect 断言不产生负宽/越界。
9. ClipboardMonitor 文件复制分支零覆盖（ClipboardMonitor.swift:59-65,88-93）：文件 URL 进剪贴板场景无测试。补测：命名 pasteboard 写文件 URL，断言条目类型正确、重复去重。

## Minor
10. Tests/ScrollSwipeResolverTests.swift:59 注释漂移：「未达阈值 15」实现是 12（ScrollSwipeResolver.swift:8）。
11. Tests/ScrollSwipeResolverTests.swift:44-49 近恒真测试 testEventMonitorsExposeScrollAndArrowSubjects 只有 `_ =` 引用，无断言闭环。
12. Tests/TabMetricsTests.swift:64-68 testOverviewPageSpacingAndPadding 只 XCTAssertNotNil，名不副实。
13. Tests/AntigravityProxyStoreTests.swift:65-67 testDualSourceSwitching 只断言静态默认值，无切换行为。
14. 小缺口：ClipboardPaster isTerminated 守卫（ClipboardPaster.swift:114）；QoderPoolQuotaProber userQuota 缺失路径（:148-152）；QoderLogParser 超长单行 >64KB。
15. NotchDrop/EventMonitors.swift:98-105 MockEventMonitors 住在生产 target 随 App 发布。
16. iMessageNotifierTests 0.5s asyncAfter 时序假设（相比仓库自身 spinMainLoop 轮询模式是回退）；QoderGatewayManagerTests.swift:78 随机端口 40000-49999 理论撞车。

## 优点（供汇总引用）
- 并发测试用 continuation 闸门不用 sleep（GatedCampaignTransport/GatedQuotaTransport）——全仓库最值得推广的模式
- QoderStore.swift:222 objectWillChangeCountForTest 主动防恒真断言
- 真机 bug 回归锁质量高（斜杠日志格式、跨零点桶翻转、WAL 未 checkpoint 可见性、Orb ID 脱敏）
- 隔离手段正确（命名剪贴板+releaseGlobally、独立 suite、临时 SQLite fixture）
- QoderGatewayManager.swift:30-61 显式转换表设计即为了可测
