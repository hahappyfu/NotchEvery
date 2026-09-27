# 审计发现存档：UI 视图/动效层（reviewer-ui，opus）

> 中间存档；最终汇总见总报告。23 文件全审。

## Critical
1. **SmoothNotchShape.swift:46-49,85-93,108-116 贝塞尔路径自相交叉**：展开态 filletBlend=64（:188）+ bottomRadius=26（:50）之和 90pt；当 rect.height<90（展开动画中间帧、最小高度保底 60pt）时 Step2 终点 y > Step3 起点 y，路径倒退自交 → GPU 填充缠绕规则破坏 → 边缘撕裂/倒角反转/黑斑。触发：每次展开动画中间帧。
2. **NotchViewModel+Events.swift:33,58-64 虚影热区只查物理刘海**：悬停/点击判定硬编码 deviceNotchRect.contains；Peek 岛体 380×82 但有效区仅物理挖槽（46pt），光标下移看 peekHint 即触发 300ms 收起、点击下半岛体无法展开。
3. **NotchView.swift:131-137 键盘方向键切页实质损坏**：.onReceive(vm.events.arrowKey) 参数忽略为 `_`，只 markSwipeHintSeen()，不调 nextZone()/previousZone()。EventMonitors.swift:45,89,91 已完整捕获 Left/Right。领域规范明确约定的键盘切页完全不生效。
4. **NotchViewModel.swift:120,177-178,193-194 切页高度记忆被前一页污染**：切页恢复目标分区只恢复 width，height 取旧页 measuredNaturalSize.height；didSet(:117-123) 只要 width>0 就写 lastZoneSize → 高页(334pt)切低页(120pt)时高度锁死在 334pt。
5. **NotchRootView.swift:33-43 + NotchViewModel.swift:335-348 + NotchView.swift:61 设置 Popover 宿主被条件渲染摘除**：Popover 挂在 NotchRootView 上而它仅 status==.opened 时存在；设置展开时点击外部收起 → 视图树卸载、NSPopover 被强制关闭（AppKit 异常）；且 notchClose 不重置 showSettings → 下次展开自动幽灵弹窗。

## Important
1. IslandMetrics.swift:21-32 + NotchView.swift:208-236 无刘海屏 peekSize 等比缩到 200pt，peekHint 固定文本 220-250pt 溢出黑岛两翼（Mac mini/Studio/外接屏场景）。
2. NotchRootView.swift:62-76,81-128 16 寸真机耳区每侧仅 54.5pt，左耳「Claude Desktop」/右耳「请求次数 45 次」必重度截断。
3. NotchView.swift:75 + NotchRootView.swift:29,75 刘海避让边距二次叠加：Root 已按 notchSafeAreaTop 避让，NotchView 又加 .padding(.top,12) → 耳区从 y=12 排到 y=66，物理刘海 0-46，垂直错位 20pt。
4. TokenZoneView.swift:126-128,219,239-244 单行三列定宽+边距合计 420pt 超出 410pt 卡片边框，两端各溢 5pt 压边框。
5. NotchRootView.swift:138,143,147,151 + NotchViewModel.swift:371,379,390,399 快速连扫 lastSwipeDirection 突变重写在途退场 Transition → 动画反向抽搐。
6. ClipboardZoneView.swift:224-228 3D 机械滚轮硬编码 120pt 视口中心；条目<3 时单卡初始即歪 5.7° 缩 97%。
7. ClipboardZoneView.swift:277,322-324 置顶图钉 Image.onTapGesture 不消费事件击穿触发外层 paste() → 意外覆盖粘贴到前台应用。
8. NotchContentView.swift:17 + NotchRootView.swift:155 + NotchViewModel.swift:77-81,225 双重切页动画竞争：外层 extraBounce 0.25 破坏高阻尼无过冲约定。
9. NotchRootView.swift:115,124 + TokenZoneView.swift:193,216,235,271 恒黑底 .tertiary 小字对比度 2.3:1，远低于 WCAG AA 4.5:1，日间几乎不可见。
10. GearHapticFeedback.swift:49,53-59 触觉引擎每次滚动/切页强夺 makeKey() 抢前台应用焦点。

## Minor
1. 死代码滞留：SpinnerView.swift（39 行无调用、缺 repeatForever）、NotchViewModel.swift:218 bridgeSpinning 孤儿、Glass.swift（52 行无调用+幻想法 #available(macOS 26)与 ADR-0010 冲突）、NotchSettingsView.swift（126 行整文件死代码）、PermissionGuide.swift（仅测试用）、PreferencesWindow.swift:188-229 旧托盘存储卡片。
2. @StateObject 滥用：Share+View.swift:24、NotchContentView.swift:12、OverviewPageView.swift:9、NotchMenuView.swift:11 对父级传入 vm 用 @StateObject（新实例不响应）；NotchView.swift:12、AntigravityAccountsCardView.swift:13、TokenZoneView.swift:259 直接绑全局单例破坏注入。
3. AntigravityProxyCardView.swift:90-94 每次渲染重建 DateFormatter（应 static let）。
4. iOSPageIndicator.swift:16-38 点击热区 18pt 重叠 8pt；白色描边底座与规范「无 dock 底座」偏差。
5. TokenZoneView.swift:285-295 非滚动列表误加边缘淡出遮罩，第 5 行底部被截断。
6. NotchView.swift:167,200 island/notchBackground 双层冗余同尺寸 frame。

## 优点（供汇总）
- SmoothNotchShape 正向连续贝塞尔替代反向挖切遮罩，消灭亚像素抗锯齿白边
- ZoneSizeGuard/ZoneNaturalSizeKey 严格落实 ADR-0008
- ScrollSwipeResolver 纯值类型 + 1.2 倍仲裁 + 防抖冷却；GearHapticFeedback 双脉冲拟真
- NotchView.notchBackground 顶边对齐避免 NSHostingView 中心锚定甩出屏幕
- NotchWindow 锁死 darkAqua 根治黑字黑底对比度灾难
