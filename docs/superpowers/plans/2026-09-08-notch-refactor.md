# 刘海双页重构实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 把刘海面板从 600 宽三区 Tab 改成 520 宽双页滑动（概览 + Token），底部 iOS dots，设置收进齿轮 Popover。

**架构：** `NotchRootView` 包双页 + dots + 齿轮；page↔zone 映射复用现有 zone 语义；滑动复用 `ScrollSwipeResolver` 三守卫；高度表保留、两页探针重测。

**技术栈：** SwiftUI（macOS）、XCTest；构建姿势见各任务命令。

---

## 文件结构

- 创建：`NotchDrop/iOSPageIndicator.swift`——纯展示组件，输入总数 + 当前页 + 点击回调。
- 创建：`NotchDrop/NotchRootView.swift`——520 容器、双页滑动、dots、齿轮按钮 + Popover。
- 创建：`NotchDrop/OverviewPageView.swift`——配额卡（收窄调用）+ 暂存盘并排。
- 修改：`NotchDrop/TokenZoneView.swift`——KPI 加绿填充条、用时加耗时条、数字 `monospacedDigit()`（改名 `TokenMonitorPageView.swift` 不做，YAGNI：文件名沿用，类型名沿用）。
- 修改：`NotchDrop/NotchViewModel.swift`——宽 600→520；`zoneOrder` 缩为 `[.normal, .token]`；高度表两页重测值；`pageIndex(for:)` / `zone(for:)` 纯函数；`zoneContentHeight` 公式去掉头部槽（无 Tab 后内容槽 = 面板高 − 上下 padding）。
- 修改：`NotchDrop/NotchContentView.swift`——三分支改两页 + dots 行（或移入 RootView，见任务 2）。
- 修改：`NotchDrop/NotchViewModel+Events.swift`——删方向键切区、删顶栏点击（顶栏点击在 `NotchView`/`NotchHeaderView`，定位后删）。
- 删除：`NotchDrop/NotchTabBar.swift`（无引用后删文件 + pbxproj 去注册）；`TabOverview/TabSettings/TabToken` 本地化键保留（设置 Popover 内仍用标题，无害）。
- 修改：`Tests/TabMetricsTests.swift`、`Tests/ContentZoneSwitcherTests.swift`——宽 520、新表值、page-zone 映射。
- 修改：`CONTEXT.md`（面板/分区行）、新增 ADR（0006-双页）。

## 构建与测试命令（各任务通用）

```bash
xcodebuild -project NotchDrop.xcodeproj -scheme NotchDrop -configuration Debug -derivedDataPath /tmp/nDD-refactor test CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO
```

预期：`TEST SUCCEEDED`。SourceKit 报 `No such module` 属索引塌方，以 scheme 构建为准。新 Swift 文件必须在 `project.pbxproj` 注册 4 处（PBXBuildFile、PBXFileReference、Group、Sources，仿 `TokenZoneView.swift` 的 `F1E2…` 条目），否则 `cannot find in scope`。

---

### Task 1 任务：iOSPageIndicator 组件

**文件：**
- 创建：`NotchDrop/iOSPageIndicator.swift`
- 注册：`NotchDrop.xcodeproj/project.pbxproj`（4 处）

- [ ] **步骤 1：创建组件文件并注册工程**

```swift
//
//  iOSPageIndicator.swift
//  NotchDrop
//
import SwiftUI

/// iOS 主屏风分页指示器：胶囊外壳 + 圆点；激活页为 12pt 白胶囊，其余 5pt 点（0.3）。
struct iOSPageIndicator: View {
    let count: Int
    let current: Int
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .fill(Color.white.opacity(i == current ? 1 : 0.3))
                    .frame(width: i == current ? 12 : 5, height: 5)
                    .onTapGesture { onSelect(i) }
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.black.opacity(0.35)))
    }
}

#Preview {
    VStack(spacing: 8) {
        iOSPageIndicator(count: 2, current: 0) { _ in }
        iOSPageIndicator(count: 2, current: 1) { _ in }
    }
    .padding()
    .background(Color(nsColor: .windowBackgroundColor))
}
```

pbxproj 注册：仿 TokenZoneView 的 4 行（新 UUID 换掉 `F1E2…` 前缀 mittaka 用 `B7C8…`），分别进 PBXBuildFile、PBXFileReference、Group（NotchTabBar 行下）、Sources。

- [ ] **步骤 2：构建验证通过**

运行：上文构建命令（Debug build 部分即包含编译）。
预期：`BUILD SUCCEEDED`（test 会跑旧测试，与本任务无关）。

- [ ] **步骤 3：Commit**

```bash
git add NotchDrop/iOSPageIndicator.swift NotchDrop.xcodeproj/project.pbxproj
git commit -m "feat: iOS 风格分页指示器组件"
```

---

### Task 2 任务：ViewModel 双页地基（宽/顺序/映射函数）

**文件：**
- 修改：`NotchDrop/NotchViewModel.swift`
- 测试：`Tests/TabMetricsTests.swift`（只改宽断言 600→520，其余高度值本任务不动）

- [ ] **步骤 1：先写映射函数测试（红）**

在 `Tests/TabMetricsTests.swift` 追加：

```swift
func testPageZoneMapping() {
    XCTAssertEqual(NotchViewModel.zoneOrder, [.normal, .token])
    XCTAssertEqual(NotchViewModel.pageIndex(for: .normal), 0)
    XCTAssertEqual(NotchViewModel.pageIndex(for: .token), 1)
    XCTAssertEqual(NotchViewModel.zone(for: 0), .normal)
    XCTAssertEqual(NotchViewModel.zone(for: 1), .token)
}
```

并把该文件内 `600` 字面量断言改为 `520`（`testOverviewSizeLocked`、`testZoneOpenedSizeFollowsCurrentZone`、`testAllZonesShareWidthSoTabBarStaysPut` 三处）。

- [ ] **步骤 2：运行确认红**

运行：通用测试命令。
预期：FAIL（`pageIndex` 不存在；宽断言 520 vs 实现 600）。

- [ ] **步骤 3：最小实现**

`NotchViewModel.swift` 改动 4 处：

```swift
static let zonePanelWidth: CGFloat = 520
static let zoneOrder: [ContentType] = [.normal, .token]

static func pageIndex(for zone: ContentType) -> Int {
    zoneOrder.firstIndex(of: zone) ?? 0
}

static func zone(for page: Int) -> ContentType {
    guard zoneOrder.indices.contains(page) else { return .normal }
    return zoneOrder[page]
}
```

高度表本任务不动（仍是 195/254/284，任务 7 重测），`zoneContentHeight` 公式本任务不动（任务 7 随高度一起改）。

- [ ] **步骤 4：运行确认绿**

运行：通用测试命令。
预期：`TEST SUCCEEDED`。

- [ ] **步骤 5：Commit**

```bash
git add NotchDrop/NotchViewModel.swift Tests/TabMetricsTests.swift
git commit -m "feat: 双页地基（520 宽、两页顺序、page-zone 映射）"
```

---

### Task 3 任务：NotchRootView 外壳（双页 + dots + 齿轮）

**文件：**
- 创建：`NotchDrop/NotchRootView.swift`
- 注册：`project.pbxproj`（4 处）
- 修改：`NotchDrop/NotchContentView.swift`——normal 分支内容搬走（见步骤 3 代码）

- [ ] **步骤 1：创建 RootView（settings 分支先占位）**

```swift
//
//  NotchRootView.swift
//  NotchDrop
//
import SwiftUI

/// 520 双页外壳：滑动切页 + dots + 右上齿轮（设置 Popover 在任务 6 接）。
struct NotchRootView: View {
    @StateObject var vm: NotchViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                pages
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.primary.opacity(0.4))
                }
                .buttonStyle(.plain)
                .padding(6)
            }
            iOSPageIndicator(count: 2, current: NotchViewModel.pageIndex(for: vm.contentType)) {
                vm.jumpToZone(NotchViewModel.zone(for: $0))
            }
        }
        .frame(width: NotchViewModel.zonePanelWidth)
    }

    private var pages: some View {
        ZStack(alignment: .topLeading) {
            switch vm.contentType {
            case .normal:
                OverviewPageView(vm: vm)
                    .zoneHeightReporter(active: vm.contentType == .normal)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .transition(reduceMotion ? .opacity : .blurFade)
            case .token:
                TokenZoneView()
                    .zoneHeightReporter(active: vm.contentType == .token)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .transition(reduceMotion ? .opacity : .blurFade)
            case .settings:
                Color.clear
            }
        }
        .animation(vm.animation, value: vm.contentType)
    }
}
```

注：`OverviewPageView` 在任务 4 创建，本任务先建空壳使编译通过：

```swift
struct OverviewPageView: View {
    @StateObject var vm: NotchViewModel
    var body: some View { Color.clear }
}
```

——先与 RootView 同文件，任务 4 拆出去（避免本任务编译红）。

- [ ] **步骤 2：构建通过**

运行：通用测试命令。
预期：`BUILD SUCCEEDED`（旧测试中与高度/顺序相关的会红？本任务没改高度表，`ContentZoneSwitcherTests.testPreviousZoneWrapsAround` 期待 normal←→settings 回绕会红——允许红，任务 5 统一改测试；记录红项）。

- [ ] **步骤 3：Commit**

```bash
git add NotchDrop/NotchRootView.swift NotchDrop.xcodeproj/project.pbxproj
git commit -m "feat: 双页外壳（dots + 齿轮占位）"
```

---

### Task 4 任务：OverviewPageView（配额收窄 + 暂存盘并排）

**文件：**
- 修改：`NotchDrop/NotchRootView.swift`——删文件内空壳
- 创建：`NotchDrop/OverviewPageView.swift`
- 注册：`project.pbxproj`（4 处）

- [ ] **步骤 1：拆出独立文件，左右并排**

```swift
//
//  OverviewPageView.swift
//  NotchDrop
//
import SwiftUI

/// 第一页：配额卡（收窄）+ 暂存盘并排。
struct OverviewPageView: View {
    @StateObject var vm: NotchViewModel

    var body: some View {
        HStack(spacing: 12) {
            QuotaCardView(vm: vm)
                .frame(width: 150)
            Divider()
            TrayView(vm: vm)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
```

配额卡宽度推导：520 − 面板边距 32 − 间距 12 − 暂存盘最小 280 ≈ 196，取 150 留余（任务 7 探针后微调）。

- [ ] **步骤 2：构建通过**

运行：通用测试命令。
预期：`BUILD SUCCEEDED`。

- [ ] **步骤 3：Commit**

```bash
git add NotchDrop/OverviewPageView.swift NotchDrop/NotchRootView.swift NotchDrop.xcodeproj/project.pbxproj
git commit -m "feat: 概览页（配额收窄 + 暂存盘并排）"
```

---

### Task 5 任务：手势收敛 + 测试同步 + 删 TabBar

**文件：**
- 修改：`NotchDrop/NotchViewModel+Events.swift`——删方向键切区段
- 修改：顶栏点击处（`grep -rn "nextZone\|previousZone" NotchDrop/NotchView.swift NotchDrop/NotchHeaderView.swift` 定位后删顶栏点击分支，保留悬停/虚影逻辑）
- 修改：`Tests/ContentZoneSwitcherTests.swift`——三区回绕改两页
- 删除：`NotchDrop/NotchTabBar.swift` + pbxproj 去 4 行注册
- 修改：`NotchDrop/NotchHeaderView.swift`——TabBar 改齿轮？不：齿轮已在 RootView，HeaderView  calls `NotchTabBar` 处改为 `EmptyView`（HeaderView 文件保留，避免改窗口装配）

- [ ] **步骤 1：先改测试（红）**

```swift
func testNextZoneWrapsAround() {
    let vm = NotchViewModel(events: MockEventMonitors())
    vm.jumpToZone(.token)
    vm.nextZone()
    XCTAssertEqual(vm.contentType, .normal)
}

func testPreviousZoneWrapsAround() {
    let vm = NotchViewModel(events: MockEventMonitors())
    vm.jumpToZone(.normal)
    vm.previousZone()
    XCTAssertEqual(vm.contentType, .token)
}

func testNextZoneAdvancesInOrder() {
    let vm = NotchViewModel(events: MockEventMonitors())
    vm.jumpToZone(.normal)
    vm.nextZone()
    XCTAssertEqual(vm.contentType, .token)
}
```

- [ ] **步骤 2：运行确认红**

运行：通用测试命令。
预期：FAIL（实现仍是三区顺序或尚有旧引用）。

- [ ] **步骤 3：删方向键/顶栏/TabBar**

方向键段在 `NotchView.swift:119-127`（`.onKeyPress` 内 `nextZone/previousZone`）整段删，保留 `markSwipeHintSeen`？该调用与滑动提示强相关，手势保留则保留调用——只删切区分支：

```swift
// 删除前
if key == .rightForward {
    vm.nextZone()
} else {
    vm.previousZone()
}
// 删除后（整段 if 删掉，markSwipeHintSeen 保留）
```

`Events` 文件同理删 optionKeyPress 订阅（如存在切区逻辑，先 grep 确认）。顶栏点击：`NotchHeaderView`/`NotchView` 中 `onTapGesture` 切区的那一处删。滑动（ScrollSwipeResolver → next/previousZone）在两页顺序下自动正确，不动。

`NotchTabBar.swift` 文件删除 + pbxproj 4 行移除；`NotchHeaderView` 中 `NotchTabBar(...)` 换 `EmptyView()`。

- [ ] **步骤 4：运行确认绿**

运行：通用测试命令。
预期：`TEST SUCCEEDED`。

- [ ] **步骤 5：Commit**

```bash
git add NotchDrop/Tests Tests/ContentZoneSwitcherTests.swift NotchDrop/NotchTabBar.swift NotchDrop/NotchHeaderView.swift NotchDrop/NotchView.swift NotchDrop/NotchViewModel+Events.swift NotchDrop.xcodeproj/project.pbxproj
git commit -m "feat: 手势收敛两页，删 TabBar/方向键/顶栏点击"
```

（注：`git add` 路径按实际修改裁剪，只加改了的文件。）

---

### Task 6 任务：齿轮设置 Popover（整搬）

**文件：**
- 修改：`NotchDrop/NotchRootView.swift`——齿轮按钮挂 `.popover`

- [ ] **步骤 1：挂 Popover**

```swift
.popover(isPresented: $showSettings, arrowEdge: .top) {
    VStack(alignment: .leading, spacing: 8) {
        NotchMenuView(vm: vm)
        NotchSettingsView(vm: vm)
        Text("NotchEvery \(appVersion)")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
    }
    .padding(12)
    .frame(minWidth: 300)
}
```

挂在齿轮 `Button` 后。`appVersion` 沿用 `NotchContentView` 处的同名全局（已存在）。

- [ ] **步骤 2：构建通过**

运行：通用测试命令。
预期：`BUILD SUCCEEDED` + `TEST SUCCEEDED`。

- [ ] **步骤 3：Commit**

```bash
git add NotchDrop/NotchRootView.swift
git commit -m "feat: 齿轮设置 Popover（整搬设置区）"
```

---

### Task 7 任务：Token 页 KPI 升级

**文件：**
- 修改：`NotchDrop/TokenZoneView.swift`

- [ ] **步骤 1：KPI 绿填充条 + 耗时条 + monospacedDigit**

KPI 行追加缓存率填充条（`kpiItem` 加 `fraction: Double?` 参数，为 nil 不画）：

```swift
private func kpiItem(label: String, value: String, valueColor: Color = .primary, fraction: Double? = nil) -> some View {
    HStack(spacing: 4) {
        Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
        Text(value).fontWeight(.semibold).foregroundStyle(valueColor)
            .monospacedDigit()
        if let fraction {
            Capsule()
                .fill(Color.green)
                .frame(width: 28 * fraction, height: 4)
        }
    }
}
```

调用处缓存率传 `fraction: 0.946`。行文本统一加 `.monospacedDigit()`（行级 `HStack` 加一次即可，header 不必）。用时列加耗时条：相对 60s 归一的 24pt 底条：

```swift
// duration 格内叠条（示例，列宽内）
.background(alignment: .bottomLeading) {
    Capsule().fill(Color.accentColor.opacity(0.5))
        .frame(width: min(1, durationSeconds / 60) * 44, height: 3)
}
```

`durationSeconds` 从 `duration` 解析（去 "s" 转 Double，mock 恒合法；解析失败按 0）。

- [ ] **步骤 2：构建 + 测试绿**

运行：通用测试命令。
预期：`TEST SUCCEEDED`。

- [ ] **步骤 3：Commit**

```bash
git add NotchDrop/TokenZoneView.swift
git commit -m "feat: Token 页 KPI 绿条/耗时条/等宽数字"
```

---

### Task 8 任务：两页探针重测 + 高度表终值 + 收尾

**文件：**
- 修改：`NotchDrop/NotchViewModel.swift`（高度表两页终值 + `zoneContentHeight` 公式去头部槽）
- 修改：`Tests/TabMetricsTests.swift`（新表值断言）
- 修改：`CONTEXT.md`、`docs/adr/0006-notchy-two-pages.md`（新建）

- [ ] **步骤 1：探针实测（沿用文件探针法）**

`NotchContentView` 的 `onPreferenceChange` 临时加（定值后删）：

```swift
let line = "PAGE-PROBE page=\(vm.contentType) natural=\(natural)\n"
let url = URL(fileURLWithPath: "/tmp/page-probe-seq.txt")
if let h = try? FileHandle(forWritingTo: url) { try? h.seekToEnd(); try? h.write(contentsOf: Data(line.utf8)); try? h.close() } else { try? line.write(to: url, atomically: true, encoding: .utf8) }
```

Release 构建部署、重启应用、首开展开两页（切页一次保证两行都写），读 `/tmp/page-probe-seq.txt` 得两页 natural。

- [ ] **步骤 2：定终值并改公式**

面板高 = natural + 上下 padding（当前 `spacing * 3` 含已死的头部槽 29，改为 `spacing * 2`，注释同步）。hostedViewHeight 取 max 不动。测试断言同步新值。目标区间 210~230，超了先压内容（配额卡宽/行 pad）不加表。

- [ ] **步骤 3：删探针、写 ADR-0006、更新 CONTEXT**

ADR 记录：去 Tab、page-zone 映射、两页终值、删了什么、数据源仍 mock。CONTEXT 面板/分区/选项卡三行同步（宽 520、两页、无 Tab）。

- [ ] **步骤 4：全量验证**

运行：通用测试命令（Debug）+ Release 构建。
预期：`TEST SUCCEEDED` + `BUILD SUCCEEDED`。部署重启验证 RUNNING（沿用探针部署流程）。

- [ ] **步骤 5：Commit**

```bash
git add NotchDrop/NotchViewModel.swift Tests/TabMetricsTests.swift CONTEXT.md docs/adr/0006-notchy-two-pages.md
git commit -m "feat: 两页高度终值 + 文档收尾"
```

---

## 自检

1. **规格覆盖度：** 520 宽→任务 2；双页滑动 + dots→任务 3/1；齿轮 Popover 整搬→任务 6；Token KPI 升级（绿条/耗时条/等宽）→任务 7；概览并排→任务 4；手势收敛→任务 5；高度重测 210~230→任务 8；mock 不动→全程未碰数据源。✓
2. **占位符扫描：** 无 TODO/待定；任务 5 的 `git add` 注明按实际裁剪（非占位，防多加）；任务 3 允许红项已写明是哪条及去向。✓
3. **类型一致性：** `pageIndex(for:)`/`zone(for:)` 在任务 2 定义，任务 3 调用一致；`OverviewPageView(vm:)` 初始化器一致；`appVersion` 沿用既有全局。✓
