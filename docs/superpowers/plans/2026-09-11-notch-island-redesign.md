# 黑岛重构实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 subagent-driven-development（推荐）或 executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 把 NotchEvery 从「玻璃卡片悬于刘海下方」重构为「纯黑岛从物理刘海无缝长出」的产品级形态（ADR-0010）：三态 morph（闲置=刘海本身 / 悬停 peek / 展开两页）、形状层三合一（自绘 IslandShape）、恒黑配色、模型列宽数据自适应。

**架构：** NotchView 的 material 刘海壳 + NotchRootView 的 0.55 玻璃底 + destinationOut 凹角 hack，合并为单一自绘 `IslandShape`（纯黑填充，顶部凹角 fillet、底部圆角，参数随状态 morph）；内容层去掉自有背景直接坐在岛上；所有随系统变色的语义色换成显式白系；模型列宽由当前 5 行数据实测驱动（钳制 [100,180]pt），走既有 ADR-0008 测量链路收敛。

**技术栈：** SwiftUI（macOS 13+，自绘 Shape，不用 UnevenRoundedRectangle）；xcodebuild 命令行构建。

**规格：** `docs/superpowers/specs/2026-09-11-notch-island-redesign-design.md`（论证依据）；视觉基准 `docs/superpowers/prototypes/2026-09-11-island-form.html` 与 `...-v2.html`（执行者两份都读）；相关 ADR：0010（黑岛形态）、0008（内容驱动尺寸，机制保留）、0009（耳区语义保留）。

## 全局约束

- 部署目标 macOS 13：不用 macOS 14+ API（UnevenRoundedRectangle、@Observable、.snappy）；`Text` 上的 `.foregroundStyle(Text + Text)` 合并写法编译失败——多段异色文本必须 HStack 包独立 `Text`。
- 构建姿势：`xcodebuild -project NotchDrop.xcodeproj -scheme NotchDrop -configuration Debug -derivedDataPath /tmp/nDD build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO`；测试加 `test -destination 'platform=macOS'`。
- 构建后必须重启 app（`pkill -f "MacOS/NotchEvery"` 然后 `open /tmp/nDD/Build/Products/Debug/NotchEvery.app`），否则用户看到旧 UI。
- **岛恒黑**：岛内内容不许出现 `.primary` / `.secondary` / `.tertiary` / `Color(nsColor: .separatorColor)` / `Color(nsColor: .windowBackgroundColor)` 等随系统外观变色的语义色（浅色系统下黑底黑字不可见）。允许的色板：`Color.white.opacity(0.92/0.55/0.35/0.12/0.08/0.06)`、`Color.green`(#30d158 系)、`tokenStatusColor` 现有红绿、`Color.black`。
- 视觉任务真机验收：执行者**无权截图**，构建重启后报告「请看 X」+ 对照值，等用户确认再提交。
- 不碰：数据层（UsageStore / QuotaStore / PublishedPersist）、NotchWindow 窗口机制（pinnedContentSize / hostingHeightConstraint）、ADR-0008 测量链路（ZoneSizeGuard / measuredNaturalSize / clampPanelSize）、设置 Popover 与其内容、右键菜单、`iOSPageIndicator`（已是白色系胶囊座，无需改动）。

---

### 任务 0：丢弃被取代的未提交改动（前置，在主检出执行）

**文件：**
- 修改（丢弃）：`NotchDrop/NotchRootView.swift`、`NotchDrop/TokenZoneView.swift`

上一轮的「玻璃上延 + 模型列宽 122pt」微调面向旧玻璃形态，被本次重构整体取代（设计文档已声明，用户已确认）。

- [ ] **步骤 1：确认待丢弃改动范围**

运行：`git diff --stat NotchDrop/NotchRootView.swift NotchDrop/TokenZoneView.swift`
预期：只有这两个文件有改动（NotchRootView +40/-6 左右、TokenZoneView +5/-2 左右）；若出现其他文件改动，停下来报告。

- [ ] **步骤 2：丢弃**

```bash
git checkout -- NotchDrop/NotchRootView.swift NotchDrop/TokenZoneView.swift
git status --short | grep -E "NotchRootView|TokenZoneView"
```

预期：第二条命令无输出（两文件回到 HEAD 干净态）。

（无 commit——丢弃即回到 HEAD。此后按 superpowers-flow 第 3 步创建隔离 worktree 再执行任务 1+。）

---

### 任务 1：IslandShape 与黑岛三态壳体

**文件：**
- 创建：`NotchDrop/IslandShape.swift`
- 创建：`NotchDrop/IslandMetrics.swift`（本任务先放常量，任务 3 补宽度函数）
- 修改：`NotchDrop/NotchView.swift`（重写壳体：删 glassNotchBackground / notchBackgroundMaskGroup / 旧 notchSize / notchCornerRadius / 旧 notch）
- 修改：`NotchDrop/NotchRootView.swift`（删 0.55 玻璃底一行）
- 修改：`NotchDrop.xcodeproj/project.pbxproj`（两个新文件入主 target）

**交付：** 应用跑起来——闲置=与物理刘海完全一致（不可见）；悬停=黑岛从刘海长出（peek，含用量小提示）；展开=黑岛+现有内容（配色仍是旧语义色，任务 2 处理）。视觉基准：原型 ①② 两态与两种展开态的**形状**。

- [ ] **步骤 1：创建 IslandShape.swift**

```swift
//
//  IslandShape.swift
//  NotchEvery
//
//  黑岛形状：顶部贴屏顶 + 左右凹角（concave fillet）、底部圆角。
//  macOS 13 兼容自绘（UnevenRoundedRectangle 需 14+）。
//  filletRadius = 0 时退化为「底部圆角矩形」= 物理刘海同形（闲置态）。
//  参数实现 animatableData：fillet 0↔15 随 morph 平滑生长。
//

import SwiftUI

struct IslandShape: Shape {
    var bottomRadius: CGFloat
    var filletRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(bottomRadius, filletRadius) }
        set {
            bottomRadius = newValue.first
            filletRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = min(filletRadius, rect.width / 4, rect.height / 2)
        let br = min(bottomRadius, rect.width / 2, rect.height / 2)
        let bodyL = rect.minX + r
        let bodyR = rect.maxX - r

        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        if r > 0 {
            // 右凹角：顶边右端 → 右侧边（绕外上角，凹向内）
            p.addArc(center: CGPoint(x: bodyR, y: rect.minY), radius: r,
                     startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        }
        p.addLine(to: CGPoint(x: bodyR, y: rect.maxY - br))
        // 右下圆角
        p.addArc(center: CGPoint(x: bodyR - br, y: rect.maxY - br), radius: br,
                 startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: bodyL + br, y: rect.maxY))
        // 左下圆角
        p.addArc(center: CGPoint(x: bodyL + br, y: rect.maxY - br), radius: br,
                 startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: bodyL, y: rect.minY + r))
        if r > 0 {
            // 左凹角：左侧边 → 顶边左端
            p.addArc(center: CGPoint(x: bodyL, y: rect.minY), radius: r,
                     startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        }
        p.closeSubpath()
        return p
    }
}
```

注意：所有弧的 `startAngle` 都正好落在当前路径点上（addArc 会先补直线到弧起点，角度写错会出现斜线）。

- [ ] **步骤 2：创建 IslandMetrics.swift（本任务仅常量）**

```swift
//
//  IslandMetrics.swift
//  NotchEvery
//
//  黑岛几何与布局度量（纯逻辑，单测覆盖见 IslandMetricsTests）。
//

import AppKit
import SwiftUI

enum IslandMetrics {
    /// 悬停 peek 岛尺寸（原型 350×82，真机以视觉验收微调）
    static let peekSize = CGSize(width: 350, height: 82)
    /// 岛顶凹角半径
    static let filletRadius: CGFloat = 15
    /// 生长/收敛过渡弹簧（数据驱动宽度变化与岛尺寸变化共用）
    static let growSpring: Animation = .spring(response: 0.45, dampingFraction: 0.85)
    /// 模型列宽钳制区间
    static let modelColumnMin: CGFloat = 100
    static let modelColumnMax: CGFloat = 180
}
```

（`AppKit` 为 NSFont、`SwiftUI` 为 Animation/CGSize。）

- [ ] **步骤 3：重写 NotchView 壳体**

删除 `glassNotchBackground`、`notchBackgroundMaskGroup`、旧 `notch`、旧 `notchSize`、旧 `notchCornerRadius` 五个成员；替换为以下内容（其余部分——内容块、scroll/key 处理、contextMenu、dragDetector、StaggeredEntry——保持不动）：

```swift
    /// 岛体尺寸：闲置=物理刘海同形；悬停=peek；展开=内容测量值；popping=微胀
    var islandSize: CGSize {
        let isGhost = vm.hoverGhosting || vm.ghostFading
        switch vm.status {
        case .closed:
            if isGhost { return IslandMetrics.peekSize }
            return CGSize(
                width: max(vm.deviceNotchRect.width - 4, 0),
                height: max(vm.deviceNotchRect.height - 4, 0)
            )
        case .opened:
            return vm.zoneOpenedSize
        case .popping:
            return CGSize(width: vm.deviceNotchRect.width, height: vm.deviceNotchRect.height + 4)
        }
    }

    /// 顶部凹角半径：闲置与 popping 为 0（与刘海同形），悬停/展开出现
    var islandFillet: CGFloat {
        let isGhost = vm.hoverGhosting || vm.ghostFading
        switch vm.status {
        case .closed: return isGhost ? IslandMetrics.filletRadius : 0
        case .opened: return IslandMetrics.filletRadius
        case .popping: return 0
        }
    }

    /// 底部圆角：随状态变化（原型 12 / 20 / 26）
    var islandBottomRadius: CGFloat {
        let isGhost = vm.hoverGhosting || vm.ghostFading
        switch vm.status {
        case .closed: return isGhost ? 20 : 12
        case .opened: return 26
        case .popping: return 10
        }
    }

    var island: some View {
        IslandShape(bottomRadius: islandBottomRadius, filletRadius: islandFillet)
            .fill(Color.black)
            .frame(width: islandSize.width + islandFillet * 2, height: islandSize.height)
            .overlay(alignment: .bottom) {
                if vm.hoverGhosting || vm.ghostFading {
                    peekHint
                        .padding(.bottom, 16)
                        .transition(.opacity)
                }
            }
            .overlay {
                if vm.bridgeSpinning {
                    SpinnerView(size: 16, color: .white)
                        .transition(.opacity)
                }
            }
    }

    /// 悬停 peek 提示：今日用量一行小字（真数据）
    private var peekHint: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(Color.green)
                .frame(width: 7, height: 7)
            Text("\(usage.summary.totalTokens) · \(usage.summary.cacheRate)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.62))
                .monospacedDigit()
                .lineLimit(1)
        }
    }
```

调用处（body 的 ZStack）把 `notch` 换成 `island`，并在 `NotchView` 增加 `@StateObject private var usage = UsageStore.shared`：

```swift
        ZStack(alignment: .top) {
            island
                .zIndex(0)
                .disabled(true)
                .opacity(vm.notchVisible ? 1 : 0.3)
            // ……原有 Group{...} 内容块与手势/菜单/拖拽全部不动……
        }
```

`dragDetector` 里引用 `notchSize` / `notchCornerRadius` 的两处改为 `islandSize` / `islandBottomRadius`。

一并微调：ZStack 外层动画行保持 `value: vm.status` 不变，但加 reduceMotion 门控（补 `@Environment(\.accessibilityReduceMotion) private var reduceMotion`）：

```swift
        .animation(reduceMotion ? nil : (vm.status == .opened ? vm.openAnimation : vm.closeAnimation), value: vm.status)
```

（岛尺寸的数据驱动动画在任务 3 加；本任务只保证状态 morph。）

- [ ] **步骤 4：NotchRootView 去玻璃底**

删除这一行（其余不动）：

```swift
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 20))
```

并把紧邻注释改为：`// 黑岛（ADR-0010）：内容透明直接坐岛上，岛体由 NotchView 的 IslandShape 绘制`。

- [ ] **步骤 5：pbxproj 挂接两个新文件（主 target）**

按既有模式补 4 处（PBXBuildFile / PBXFileReference / NotchDrop group children / Sources build phase），ID 用未占用号段（例：`C1D2E3F4A506172839404301` 为 IslandShape，`...4303` 为 IslandMetrics，fileRef 分别 `...4300` / `...4302`）。

- [ ] **步骤 6：构建验证**

运行：`xcodebuild -project NotchDrop.xcodeproj -scheme NotchDrop -configuration Debug -derivedDataPath /tmp/nDD build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO 2>&1 | grep -E "BUILD|error:"`
预期：`** BUILD SUCCEEDED **`

- [ ] **步骤 7：重启 app 并交用户视觉验收**

```bash
pkill -f "MacOS/NotchEvery"; sleep 1; open /tmp/nDD/Build/Products/Debug/NotchEvery.app
```

请用户看：① 闲置时与物理刘海完全一致（不可见/无缝）；② 悬停时黑岛长出、凹角连接屏顶、底部有「● 数字 · 数字」提示；③ 展开两页形状正确（内容配色偏差已知，任务 2 处理）。**等用户确认后再提交。**

- [ ] **步骤 8：Commit**

```bash
git add NotchDrop/IslandShape.swift NotchDrop/IslandMetrics.swift NotchDrop/NotchView.swift NotchDrop/NotchRootView.swift NotchDrop.xcodeproj/project.pbxproj
git commit -m "feat: 黑岛壳体：IslandShape 三态 morph，形状层三合一（ADR-0010）"
```

---

### 任务 2：内容黑化（显式白系配色）

**文件：**
- 修改：`NotchDrop/TokenZoneView.swift`
- 修改：`NotchDrop/QuotaCardView.swift`
- 修改：`NotchDrop/NotchRootView.swift`（耳区两处）

**交付：** 黑色岛上两页内容在**任意系统外观**下都正确（浅色系统不再黑字压黑底）。替换规则：`.secondary` → `Color.white.opacity(0.55)`；`.primary` → `Color.white.opacity(0.92)`；`.tertiary` → `Color.white.opacity(0.35)`；`Color(nsColor: .separatorColor).opacity(x)` → `Color.white.opacity(0.08~0.12)`。`#Preview` 块不动。

- [ ] **步骤 1：TokenZoneView 全面替换**

逐处替换（行号以当前文件为准，按文本定位）：

| 位置 | 旧 | 新 |
|---|---|---|
| TokenRowView 时间列 | `.foregroundStyle(.secondary)` | `.foregroundStyle(Color.white.opacity(0.55))` |
| TokenRowView 模型列 | `.foregroundStyle(.primary)` | `.foregroundStyle(Color.white.opacity(0.92))` |
| TokenRowView 入/出 | `.foregroundStyle(.secondary)` | `.foregroundStyle(Color.white.opacity(0.55))` |
| TokenRowView 用时 | `.foregroundStyle(.secondary)` | `.foregroundStyle(Color.white.opacity(0.55))` |
| TokenRowView 状态文字 | `row.status >= 400 ? tokenStatusColor(row.status) : .secondary` | `row.status >= 400 ? tokenStatusColor(row.status) : Color.white.opacity(0.55)` |
| TokenRowView hover 底 | `Color.white.opacity(0.04)` | `Color.white.opacity(0.06)` |
| TokenRowView 行分隔线 | `Color(nsColor: .separatorColor).opacity(0.5)` | `Color.white.opacity(0.08)` |
| summaryBar Tokens 标签 | `.foregroundStyle(.secondary)` | `.foregroundStyle(Color.white.opacity(0.55))` |
| summaryBar 卡片底 | `Color.white.opacity(0.04)` | `Color.white.opacity(0.06)` |
| summaryBar 卡片描边 | `Color(nsColor: .separatorColor).opacity(0.5)` | `Color.white.opacity(0.08)` |
| header 文字 | `.foregroundStyle(.secondary)` | `.foregroundStyle(Color.white.opacity(0.55))` |
| header 分隔线 | `Color(nsColor: .separatorColor).opacity(0.5)` | `Color.white.opacity(0.08)` |
| footer 文字 | `.foregroundStyle(.secondary)` | `.foregroundStyle(Color.white.opacity(0.55))` |
| footer 分隔线 | `Color(nsColor: .separatorColor).opacity(0.5)` | `Color.white.opacity(0.08)` |
| RollupText 默认色 | `var color: Color = .primary` | `var color: Color = Color.white.opacity(0.92)` |

- [ ] **步骤 2：QuotaCardView 全面替换**

| 位置 | 旧 | 新 |
|---|---|---|
| row 标题（周/月） | `.foregroundStyle(.secondary)` | `Color.white.opacity(0.55)` |
| 百分比数字 | `.foregroundStyle(.primary)` | `Color.white.opacity(0.92)` |
| `--%` 占位 | `.foregroundStyle(.tertiary)` | `Color.white.opacity(0.35)` |
| miniBar 轨道 | `Color(nsColor: .separatorColor).opacity(0.5)` | `Color.white.opacity(0.12)` |
| ring 轨道（有数据/无数据两处） | `Color(nsColor: .separatorColor).opacity(0.4)` | `Color.white.opacity(0.12)` |
| ring 百分比 | `.foregroundStyle(.primary)` | `Color.white.opacity(0.92)` |
| ring 占位 `--%` | `.foregroundStyle(.tertiary)` | `Color.white.opacity(0.35)` |
| 环下标签（5h） | `.foregroundStyle(.secondary)` | `Color.white.opacity(0.55)` |
| statusLine 圆点 | `Color.secondary` | `Color.white.opacity(0.4)` |
| statusLine 文字 | `.foregroundStyle(.secondary)` | `Color.white.opacity(0.55)` |

- [ ] **步骤 3：NotchRootView 耳区**

- 左耳 provider 名：`.foregroundStyle(.primary)` → `.foregroundStyle(Color.white.opacity(0.92))`
- 右耳调用次数：`RollupText(text: ..., color: .secondary)` → `color: Color.white.opacity(0.55)`

- [ ] **步骤 4：残留扫描**

运行：`grep -n "\.primary\|\.secondary\|\.tertiary\|nsColor:" NotchDrop/TokenZoneView.swift NotchDrop/QuotaCardView.swift NotchDrop/NotchRootView.swift`
预期：仅剩 `#Preview` 块内的引用（若有）；主体代码零命中。

- [ ] **步骤 5：构建 + 重启 + 用户视觉验收**

构建命令同任务 1；重启后请用户看两页内容的可读性与层次（对照原型 ③④）。等确认再提交。

- [ ] **步骤 6：Commit**

```bash
git add NotchDrop/TokenZoneView.swift NotchDrop/QuotaCardView.swift NotchDrop/NotchRootView.swift
git commit -m "feat: 内容黑化：语义色全换显式白系，适配恒黑岛"
```

---

### 任务 3：模型列宽数据自适应（TDD）

**文件：**
- 创建：`Tests/IslandMetricsTests.swift`
- 修改：`NotchDrop/IslandMetrics.swift`（补宽度函数）
- 修改：`NotchDrop/TokenZoneView.swift`（列宽数据驱动 + 过渡动画）
- 修改：`NotchDrop/NotchView.swift`（岛尺寸数据变化走 growSpring）
- 修改：`NotchDrop.xcodeproj/project.pbxproj`（测试文件入 test target）

**交付：** 模型列宽随当前 5 行最长模型名收敛（钳制 [100,180]pt），岛宽随内容 morph；长度相近时宽度稳定。

- [ ] **步骤 1：编写失败的测试**

创建 `Tests/IslandMetricsTests.swift`：

```swift
import XCTest
@testable import NotchEvery

/// 模型列宽自适应：纯函数外部行为（钳制边界与单调性），不测具体像素值。
final class IslandMetricsTests: XCTestCase {
    func testEmptyModelsReturnsMin() {
        XCTAssertEqual(IslandMetrics.modelColumnWidth(for: []), IslandMetrics.modelColumnMin)
    }

    func testShortModelsClampToMin() {
        XCTAssertEqual(
            IslandMetrics.modelColumnWidth(for: ["gpt", "kimi", "qwen-plus"]),
            IslandMetrics.modelColumnMin
        )
    }

    func testVeryLongModelClampsToMax() {
        let long = String(repeating: "very-long-model-name-", count: 5)
        XCTAssertEqual(IslandMetrics.modelColumnWidth(for: [long]), IslandMetrics.modelColumnMax)
    }

    func testWidthMonotonicWithLongerNames() {
        let short = IslandMetrics.modelColumnWidth(for: ["gpt-5"])
        let mid = IslandMetrics.modelColumnWidth(for: ["deepseek-v4-flash-0731"])
        let long = IslandMetrics.modelColumnWidth(for: ["deepseek-ai/deepseek-v4-flash-0731"])
        XCTAssertLessThanOrEqual(short, mid)
        XCTAssertLessThanOrEqual(mid, long)
    }

    func testLongestModelDrivesWidth() {
        let mixed = IslandMetrics.modelColumnWidth(for: ["gpt-5", "qwen-plus-2025-07-14"])
        let onlyLong = IslandMetrics.modelColumnWidth(for: ["qwen-plus-2025-07-14"])
        XCTAssertEqual(mixed, onlyLong)
    }

    func testAlwaysWithinBounds() {
        for sample in [["a"], ["deepseek-v4-flash-vision-exp"], [String(repeating: "x", count: 60)]] {
            let w = IslandMetrics.modelColumnWidth(for: sample)
            XCTAssertGreaterThanOrEqual(w, IslandMetrics.modelColumnMin)
            XCTAssertLessThanOrEqual(w, IslandMetrics.modelColumnMax)
        }
    }
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：`xcodebuild test -project NotchDrop.xcodeproj -scheme NotchDrop -derivedDataPath /tmp/nDD -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO 2>&1 | grep -E "error:|UsageStoreTests|IslandMetricsTests" | head`
预期：编译失败（`modelColumnWidth` / `modelColumnMin` / `modelColumnMax` 未定义）。

- [ ] **步骤 3：实现最小代码**

`IslandMetrics.swift` 头部 `import` 改为 `import AppKit` + `import SwiftUI`，并在 `enum IslandMetrics` 内补：

```swift
    /// 模型列宽：当前行最长模型名实测宽 + 4pt 呼吸，钳制 [min, max]。
    static func modelColumnWidth(for models: [String]) -> CGFloat {
        guard let longest = models.max(by: { textWidth($0) < textWidth($1) }) else {
            return modelColumnMin
        }
        return min(max(textWidth(longest) + 4, modelColumnMin), modelColumnMax)
    }

    private static let modelFont = NSFont.systemFont(ofSize: 11, weight: .semibold)

    private static func textWidth(_ text: String) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: modelFont]).width
    }
```

（`modelColumnMin` / `modelColumnMax` 任务 1 已加。）

- [ ] **步骤 4：pbxproj 挂接测试文件（test target）**

按既有模式补 4 处（PBXBuildFile / PBXFileReference / Tests group children / test target Sources），ID 例：`7AE10C0220260AB000000D9`（BuildFile）/ `7AE10C0220260AB000000C9`（fileRef）。

- [ ] **步骤 5：运行测试验证通过**

运行同步骤 2（去掉 grep 过滤可直接看 Test Suite 摘要）。
预期：`IslandMetricsTests` 6 用例全过，其余套件零回归。

- [ ] **步骤 6：TokenZoneView 接入数据驱动列宽**

把 `private let modelW: CGFloat = 122` 替换为（并删注释中"122"表述）：

```swift
    /// 自适应列宽：随当前 5 行数据收敛（钳制见 IslandMetrics）
    private var modelW: CGFloat {
        IslandMetrics.modelColumnWidth(for: store.recentRequests.prefix(5).map(\.model))
    }
```

表格容器（header + 行的 VStack，即任务 2 后的结构）加过渡动画：

```swift
            .animation(reduceMotion ? nil : IslandMetrics.growSpring, value: modelW)
```

（`reduceMotion` 用 TokenZoneView 已有的 `@Environment(\.accessibilityReduceMotion)`。）

- [ ] **步骤 7：NotchView 岛尺寸数据变化走同款弹簧**

在 `island` 视图链末尾（`.overlay { bridgeSpinner }` 之后）加：

```swift
            .animation(reduceMotion ? nil : IslandMetrics.growSpring, value: islandSize)
```

并在重启后**重点观察切页手感**：岛宽在概览⇄Token 间现在也走 growSpring（原为瞬变）。若手感回退（相对窗口的"滑下来"感复现），改为仅数据路径动画（把该 animation 挂到 TokenZoneView 内容层已足够）——此点是本任务视觉验收的必看项。

- [ ] **步骤 8：构建 + 重启 + 用户视觉验收**

验收点：① Token 页模型名完整显示且列宽随数据；② 用不同模型名（如切到 muse-spark 批次的记录）时岛宽会呼吸且不抖动刺眼；③ 切页手感无回退。等确认再提交。

- [ ] **步骤 9：Commit**

```bash
git add NotchDrop/IslandMetrics.swift NotchDrop/TokenZoneView.swift NotchDrop/NotchView.swift Tests/IslandMetricsTests.swift NotchDrop.xcodeproj/project.pbxproj
git commit -m "feat: 模型列宽数据自适应（钳制 100-180pt）+ 单测；岛宽随内容 morph"
```

---

### 任务 4：抛光、清理与文档同步

**文件：**
- 修改：`NotchDrop/NotchView.swift`（peek 提示淡入）
- 修改：`CONTEXT.md`（词条口径）
- 检查：全仓残留

**交付：** 收尾质量项与文档一致性。

- [ ] **步骤 1：peek 提示淡入动画**

`peekHint` 外层 overlay 的 `if` 内加：

```swift
                    .opacity(vm.hoverGhosting || vm.ghostFading ? 1 : 0)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: vm.hoverGhosting)
```

- [ ] **步骤 2：残留清理扫描**

运行：`grep -rn "glassNotchBackground\|notchBackgroundMaskGroup\|PanelGlassShape\|glassCard\|windowBackgroundColor" NotchDrop/ | grep -v TrayDrop`
预期：仅剩 `Glass.swift`（glassCard 定义，TrayDrop 仍在用，非本次范围）；壳体相关零命中。

- [ ] **步骤 3：CONTEXT.md 词条更新**

- **面板（Panel）** 词条改为：`展开态下用户看到的整块黑色岛体，从物理刘海无缝长出（2026-09-11 黑岛重构，见 ADR-0010）。顶边贴屏幕顶、与屏顶交接处为凹角，恒黑不跟随系统深浅色。尺寸跟随当前分区内容自然大小（宽高自适应，有界，见 ADR-0008）。_Avoid_: 玻璃卡片（旧形态已废）`
- **虚影（Ghost）** 词条改为：`鼠标悬停刘海时出现的过渡态：黑岛稍稍长大（peek 尺寸）并显示今日用量小提示；点击或拖入文件后才完整展开。_Avoid_: 舌头（旧虚影形态已废）`
- 其余词条（耳区/禁放区/分区/指示器）不动。

- [ ] **步骤 4：全量测试 + 构建**

```bash
xcodebuild test -project NotchDrop.xcodeproj -scheme NotchDrop -derivedDataPath /tmp/nDD -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO 2>&1 | grep -E "Test Suite .* (passed|failed)|TEST (SUCCEEDED|FAILED)" | tail -8
```
预期：全绿（含 IslandMetricsTests 6 例、UsageStoreTests 10 例）。

- [ ] **步骤 5：重启 app，最终整体验收（用户）**

逐项对照原型：闲置 / 悬停 peek / 概览 / Token × 深浅壁纸；数据刷新 3s 宽度稳定；reduceMotion（系统设置开启后）各态无位移动画。

- [ ] **步骤 6：Commit**

```bash
git add NotchDrop/NotchView.swift CONTEXT.md
git commit -m "feat: peek 提示淡入；CONTEXT.md 黑岛词条同步"
```

---

## 验证总表

| 任务 | 验证命令/方式 | 预期 |
|---|---|---|
| 0 | `git status --short` | 两旧文件无改动 |
| 1 | build + 真机三态 | 黑岛形态成立，用户确认 |
| 2 | build + 真机两页 | 黑底可读，浅色系统不黑字 |
| 3 | `xcodebuild test` | IslandMetricsTests 6/6 + 零回归 |
| 4 | 全量 test + 真机 | 全绿 + 终验通过 |

## 已知风险与调试点

- **切页手感**（任务 3 步骤 7）：岛宽从瞬变改 growSpring 是行为变化，视觉验收不通过就退回瞬变（内容层动画已够）。
- **凹角几何**：`addArc` 的 startAngle 必须落在当前点上，否则出现斜线——构建后看一眼悬停态即知。
- **非刘海屏**：deviceNotchRect 回落到 150×28 假刘海，闲置态即假刘海形状，属预期。
- **peek 尺寸**：350×82 为原型比例折算值，真机可能需按实际刘海宽微调（IslandMetrics.peekSize 单点改）。
