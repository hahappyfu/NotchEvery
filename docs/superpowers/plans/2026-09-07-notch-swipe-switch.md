# 刘海面板手势切换 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 把右上角三个点点击切换改成面板展开时触控板双指左右滑、鼠标横滚、键盘左右键切换，顺序循环，单次只切一区。

**架构：** 纯函数 `ScrollSwipeResolver` 做滑动累积、阈值、冷却、动量过滤（可单测）；`EventMonitors` 只转发原始滚轮增量与左右键事件；`NotchView` 做守卫（展开态、鼠标在面板内、未拖文件）后调 `NotchViewModel` 的区切换方法；顶栏三个点换成可点小圆点指示器；内容区过渡改为按方向的不对称滑入。

**技术栈：** SwiftUI + AppKit（`NSEvent` 滚轮、键码），`Combine`，`XCTest`（沿用 `Tests/` 目录风格）。

---

## 文件结构

- 新建：`NotchDrop/ScrollSwipeResolver.swift` —— 纯值类型，输入滚轮增量，输出切换方向或空。唯一可单测的手势逻辑归宿。
- 新建：`Tests/ScrollSwipeResolverTests.swift` —— 解析器单测。
- 新建：`Tests/ContentZoneSwitcherTests.swift` —— 区顺序与循环单测。
- 修改：`NotchDrop/NotchViewModel.swift` —— 加区顺序表、`nextZone` / `previousZone` / `jumpToZone`、`lastSwipeDirection`、已见提示标记。
- 修改：`NotchDrop/EventMonitors.swift` —— 加滚轮增量与左右键转发，加 `MockEventMonitors` 同名字段。
- 修改：`NotchDrop/NotchViewModel+Events.swift` —— 顶栏点击循环改调 `nextZone`，保持点击兜底。
- 修改：`NotchDrop/NotchView.swift` —— 订阅滚轮与按键，加三重守卫，首次轻提示浮层。
- 修改：`NotchDrop/NotchHeaderView.swift` —— 三个点换成可点小圆点指示器。
- 修改：`NotchDrop/NotchContentView.swift` —— 按 `lastSwipeDirection` 的不对称滑入过渡。

动画曲线沿用现有 `vm.animation`，苹果风顺滑打磨是后续队伍的独立事项，本计划不碰弹簧参数。

---

### 任务 1：区切换核心

**文件：**
- 修改：`NotchDrop/NotchViewModel.swift`
- 测试：`Tests/ContentZoneSwitcherTests.swift`

- [ ] **步骤 1：编写失败的测试**

```swift
import XCTest
@testable import NotchEvery

final class ContentZoneSwitcherTests: XCTestCase {
    func testNextZoneWrapsAround() {
        let vm = NotchViewModel(events: MockEventMonitors())
        vm.jumpToZone(.settings)
        vm.nextZone()
        XCTAssertEqual(vm.contentType, .normal)
    }

    func testPreviousZoneWrapsAround() {
        let vm = NotchViewModel(events: MockEventMonitors())
        vm.jumpToZone(.normal)
        vm.previousZone()
        XCTAssertEqual(vm.contentType, .settings)
    }

    func testNextZoneAdvancesInOrder() {
        let vm = NotchViewModel(events: MockEventMonitors())
        vm.jumpToZone(.normal)
        vm.nextZone()
        XCTAssertEqual(vm.contentType, .menu)
    }

    func testMarkSwipeHintSeenSetsFlag() {
        let vm = NotchViewModel(events: MockEventMonitors())
        XCTAssertFalse(vm.hasSeenSwipeHint)
        vm.markSwipeHintSeen()
        XCTAssertTrue(vm.hasSeenSwipeHint)
    }
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：`xcodebuild -project NotchDrop.xcodeproj -scheme NotchDrop -configuration Debug -derivedDataPath /tmp/nDD build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO`
预期：FAIL，报错 `nextZone` / `previousZone` / `jumpToZone` 未定义（先保证编译错误即失败信号；单测随测试目标现状执行）。

- [ ] **步骤 3：编写最少实现代码**

在 `NotchViewModel.swift` 的 `showSettings()` 附近追加：

```swift
/// 功能区固定顺序：左右滑按此循环
static let zoneOrder: [ContentType] = [.normal, .menu, .settings]

/// 最近一次切换方向：内容区不对称过渡用
@Published var lastSwipeDirection: SwipeDirection = .next

func jumpToZone(_ zone: ContentType) {
    lastSwipeDirection = .next
    contentType = zone
}

func nextZone() {
    lastSwipeDirection = .next
    let order = Self.zoneOrder
    let idx = order.firstIndex(of: contentType) ?? 0
    contentType = order[(idx + 1) % order.count]
}

func previousZone() {
    lastSwipeDirection = .previous
    let order = Self.zoneOrder
    let idx = order.firstIndex(of: contentType) ?? 0
    contentType = order[(idx + order.count - 1) % order.count]
}

/// 首次滑动提示是否已展示过：持久化，只打扰一次
@PublishedPersist(key: "hasSeenSwipeHint", defaultValue: false)
var hasSeenSwipeHint: Bool

func markSwipeHintSeen() {
    hasSeenSwipeHint = true
}
```

同时在文件顶部（`ContentType` 上方）加方向类型：

```swift
enum SwipeDirection {
    case next
    case previous
}
```

- [ ] **步骤 4：运行测试验证通过**

运行：同步骤 2 命令。
预期：BUILD SUCCEEDED，且四个用例 PASS。

- [ ] **步骤 5：Commit**

```bash
git add NotchDrop/NotchViewModel.swift Tests/ContentZoneSwitcherTests.swift
git commit -m "feat: 功能区顺序循环切换核心"
```

---

### 任务 2：滑动解析器

**文件：**
- 创建：`NotchDrop/ScrollSwipeResolver.swift`
- 测试：`Tests/ScrollSwipeResolverTests.swift`

- [ ] **步骤 1：编写失败的测试**

```swift
import XCTest
@testable import NotchEvery

final class ScrollSwipeResolverTests: XCTestCase {
    func testLeftSwipeCrossingThresholdGoesNext() {
        var r = ScrollSwipeResolver()
        XCTAssertNil(r.feed(deltaX: -6, hasMomentum: false, now: 0))
        XCTAssertEqual(r.feed(deltaX: -8, hasMomentum: false, now: 0.01), .next)
    }

    func testRightSwipeGoesPrevious() {
        var r = ScrollSwipeResolver()
        XCTAssertEqual(r.feed(deltaX: 14, hasMomentum: false, now: 0), .previous)
    }

    func testMomentumScrollIsIgnored() {
        var r = ScrollSwipeResolver()
        XCTAssertNil(r.feed(deltaX: -50, hasMomentum: true, now: 0))
    }

    func testCooldownAllowsOnlyOneSwitchPerGesture() {
        var r = ScrollSwipeResolver()
        XCTAssertEqual(r.feed(deltaX: -14, hasMomentum: false, now: 0), .next)
        XCTAssertNil(r.feed(deltaX: -14, hasMomentum: false, now: 0.1))
        XCTAssertEqual(r.feed(deltaX: -14, hasMomentum: false, now: 0.5), .next)
    }

    func testBelowThresholdAccumulates() {
        var r = ScrollSwipeResolver()
        XCTAssertNil(r.feed(deltaX: -5, hasMomentum: false, now: 0))
        XCTAssertNil(r.feed(deltaX: -5, hasMomentum: false, now: 0.01))
        XCTAssertEqual(r.feed(deltaX: -5, hasMomentum: false, now: 0.02), .next)
    }
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：同任务 1 步骤 2 命令。
预期：FAIL，`ScrollSwipeResolver` 未定义。

- [ ] **步骤 3：编写最少实现代码**

创建 `NotchDrop/ScrollSwipeResolver.swift`：

```swift
import Foundation

/// 滚轮手势解析器：纯值类型，无 AppKit 依赖，可单测。
/// 方向约定：手指左滑（增量为负）= 下一区，和浏览器前进手势一致；
/// 导航手势不跟随自然滚动方向取反，原样用增量符号。
struct ScrollSwipeResolver {
    /// 触发一次切换需要的累积位移
    var threshold: CGFloat = 12
    /// 两次切换的最短间隔，抬手一次只切一区
    var cooldown: TimeInterval = 0.35

    private var accumulated: CGFloat = 0
    private var lastAccepted: TimeInterval = -.infinity

    mutating func feed(deltaX: CGFloat, hasMomentum: Bool, now: TimeInterval) -> SwipeDirection? {
        // 惯性动量是手指已离开后的余波，不计入
        guard !hasMomentum else { return nil }
        accumulated += deltaX
        guard abs(accumulated) >= threshold else { return nil }
        // 冷却期内不接受第二次切换
        guard now - lastAccepted >= cooldown else { return nil }
        lastAccepted = now
        let direction: SwipeDirection = accumulated < 0 ? .next : .previous
        accumulated = 0
        return direction
    }

    mutating func reset() {
        accumulated = 0
    }
}
```

- [ ] **步骤 4：运行测试验证通过**

运行：同任务 1 步骤 2 命令。
预期：BUILD SUCCEEDED，五个用例 PASS。

- [ ] **步骤 5：Commit**

```bash
git add NotchDrop/ScrollSwipeResolver.swift Tests/ScrollSwipeResolverTests.swift
git commit -m "feat: 滑动解析器阈值冷却与动量过滤"
```

---

### 任务 3：事件接入

**文件：**
- 修改：`NotchDrop/EventMonitors.swift`

- [ ] **步骤 1：编写失败的测试**

本任务无新增纯逻辑，测试即编译存在性检查。在 `Tests/ScrollSwipeResolverTests.swift` 末尾追加：

```swift
func testEventMonitorsExposeScrollAndArrowSubjects() {
    let mocks = MockEventMonitors()
    // 编译即通过：原始增量与左右键必须存在
    _ = mocks.scrollDelta
    _ = mocks.arrowKey
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：同任务 1 步骤 2 命令。
预期：FAIL，`scrollDelta` / `arrowKey` 未定义。

- [ ] **步骤 3：编写最少实现代码**

`EventMonitorsProtocol` 追加：

```swift
/// 原始滚轮增量：正=右滑，负=左滑；调用方用 ScrollSwipeResolver 解析
var scrollDelta: PassthroughSubject<ScrollDelta, Never> { get }
/// 左右键：.leftBackward = 左键上一区，.rightForward = 右键下一区
var arrowKey: PassthroughSubject<ArrowDirection, Never> { get }
```

`EventMonitors.swift` 顶部加两个小类型：

```swift
struct ScrollDelta {
    let deltaX: CGFloat
    let hasMomentum: Bool
    let timestamp: TimeInterval
}

enum ArrowDirection {
    case leftBackward
    case rightForward
}
```

`EventMonitors` 类追加字段与监听（放在 `init` 末尾，`optionKeyPressEvent.start()` 之后）：

```swift
let scrollDelta: PassthroughSubject<ScrollDelta, Never> = .init()
let arrowKey: PassthroughSubject<ArrowDirection, Never> = .init()
private var scrollEvent: EventMonitor!
private var keyDownEvent: EventMonitor!
```

`init` 内追加：

```swift
scrollEvent = EventMonitor(mask: .scrollWheel) { [weak self] event in
    guard let self, let event else { return }
    // 只收精确滚轮（触控板与横滚轮）；传统滚轮一格步进也带精确增量，直接收
    self.scrollDelta.send(ScrollDelta(
        deltaX: event.scrollingDeltaX,
        hasMomentum: event.momentumPhase != .none,
        timestamp: event.timestamp
    ))
}
scrollEvent.start()

keyDownEvent = EventMonitor(mask: .keyDown) { [weak self] event in
    guard let self, let event else { return }
    // 123=左，124=右；不吞事件，只转发
    if event.keyCode == 123 {
        self.arrowKey.send(.leftBackward)
    } else if event.keyCode == 124 {
        self.arrowKey.send(.rightForward)
    }
}
keyDownEvent.start()
```

`MockEventMonitors` 追加同名字段：

```swift
let scrollDelta: PassthroughSubject<ScrollDelta, Never> = .init()
let arrowKey: PassthroughSubject<ArrowDirection, Never> = .init()
```

- [ ] **步骤 4：运行测试验证通过**

运行：同任务 1 步骤 2 命令。
预期：BUILD SUCCEEDED。

- [ ] **步骤 5：Commit**

```bash
git add NotchDrop/EventMonitors.swift Tests/ScrollSwipeResolverTests.swift
git commit -m "feat: 转发滚轮增量与左右键事件"
```

---

### 任务 4：视图接线与守卫

**文件：**
- 修改：`NotchDrop/NotchView.swift`
- 修改：`NotchDrop/NotchViewModel+Events.swift`

- [ ] **步骤 1：编写失败的测试**

守卫逻辑依赖鼠标位置与拖放状态，走真机手动验证（见步骤 4）。本步骤先改顶栏点击循环，复用任务 1 的单测做回归网：`Tests/ContentZoneSwitcherTests.swift` 已覆盖 `nextZone` 循环语义，无需新文件。

- [ ] **步骤 2：运行现有测试确认基线**

运行：同任务 1 步骤 2 命令。
预期：BUILD SUCCEEDED，任务 1 的三个用例 PASS。

- [ ] **步骤 3：编写最少实现代码**

`NotchViewModel+Events.swift` 第 29–37 行的顶栏点击循环替换为：

```swift
} else if headlineOpenedRect.contains(mouseLocation) {
    // 顶栏点击：下一区，和右滑手势同一语义
    nextZone()
}
```

`NotchView.swift` 追加状态与订阅。先加字段：

```swift
@State private var swipeResolver = ScrollSwipeResolver()
```

在 `body` 的展开内容 `Group` 上（`.allowsHitTesting` 那一组之后）追加订阅：

```swift
.onReceive(vm.events.scrollDelta) { delta in
    // 三重守卫：展开态、鼠标在面板内、未拖文件
    guard vm.status == .opened else { return }
    guard vm.notchOpenedRect.contains(NSEvent.mouseLocation) else { return }
    guard !dropTargeting else { return }
    guard let direction = swipeResolver.feed(
        deltaX: delta.deltaX,
        hasMomentum: delta.hasMomentum,
        now: delta.timestamp
    ) else { return }
    if direction == .next {
        vm.nextZone()
    } else {
        vm.previousZone()
    }
    vm.markSwipeHintSeen()
}
.onReceive(vm.events.arrowKey) { key in
    guard vm.status == .opened else { return }
    guard vm.notchOpenedRect.contains(NSEvent.mouseLocation) else { return }
    guard !dropTargeting else { return }
    if key == .rightForward {
        vm.nextZone()
    } else {
        vm.previousZone()
    }
    vm.markSwipeHintSeen()
}
```

`vm.events` 需要可访问：`NotchViewModel` 当前没有存 `events` 字段。`init` 改成记住传入的监听器：

```swift
private let eventsHolder: (any EventMonitorsProtocol)?

// init 内 setupCancellables 之前加：
self.eventsHolder = events
var events: any EventMonitorsProtocol { eventsHolder ?? EventMonitors.shared }
```

注意：`NotchViewModel` 是 `NSObject` 子类，加 `private let` 存储属性要在 `super.init()` 之前赋值。为避开初始化顺序麻烦，改用隐式解包可选：

```swift
private var eventsBox: (any EventMonitorsProtocol)!
var events: any EventMonitorsProtocol { eventsBox ?? EventMonitors.shared }
```

`init` 内 `super.init()` 之后、`setupCancellables` 之前加 `self.eventsBox = events ?? EventMonitors.shared`。

- [ ] **步骤 4：运行验证**

运行：同任务 1 步骤 2 命令，预期 BUILD SUCCEEDED。
真机手动：展开面板，触控板双指左右滑各一次，确认每次只切一区；按住文件拖到面板上时滑动，确认不切换；键盘左右键各按一次，确认切换；鼠标移到面板外滑动，确认不切换。

- [ ] **步骤 5：Commit**

```bash
git add NotchDrop/NotchView.swift NotchDrop/NotchViewModel.swift NotchDrop/NotchViewModel+Events.swift
git commit -m "feat: 面板手势接线与三重守卫"
```

---

### 任务 5：顶栏指示器

**文件：**
- 修改：`NotchDrop/NotchHeaderView.swift`

- [ ] **步骤 1：编写失败的测试**

纯外观变更，真机目视验证，无新单测文件。

- [ ] **步骤 2：确认基线可构建**

运行：同任务 1 步骤 2 命令。
预期：BUILD SUCCEEDED。

- [ ] **步骤 3：编写最少实现代码**

`NotchHeaderView.swift` 第 25–26 行的省略号图标替换为：

```swift
PageIndicator(current: vm.contentType, onJump: { vm.jumpToZone($0) })
```

文件末尾追加：

```swift
/// 小圆点指示器：当前位置实心高亮，可点直跳
private struct PageIndicator: View {
    let current: NotchViewModel.ContentType
    let onJump: (NotchViewModel.ContentType) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(NotchViewModel.zoneOrder, id: \.self) { zone in
                Circle()
                    .fill(zone == current ? Color.primary : Color.secondary.opacity(0.35))
                    .frame(width: 6, height: 6)
                    .contentShape(Rectangle().inset(by: -6))
                    .onTapGesture { onJump(zone) }
            }
        }
    }
}
```

- [ ] **步骤 4：运行验证**

运行：同任务 1 步骤 2 命令，预期 BUILD SUCCEEDED。
真机目视：展开面板，右上角是三个小圆点，当前区高亮；点任意圆点直跳对应区。

- [ ] **步骤 5：Commit**

```bash
git add NotchDrop/NotchHeaderView.swift
git commit -m "feat: 顶栏三个点换成可点指示器"
```

---

### 任务 6：内容区方向过渡

**文件：**
- 修改：`NotchDrop/NotchContentView.swift`

- [ ] **步骤 1：编写失败的测试**

纯过渡变更，真机目视验证，无新单测文件。

- [ ] **步骤 2：确认基线可构建**

运行：同任务 1 步骤 2 命令。
预期：BUILD SUCCEEDED。

- [ ] **步骤 3：编写最少实现代码**

`NotchContentView.swift` 的 `body` 改为按方向的不对称过渡：

```swift
var body: some View {
    ZStack {
        switch vm.contentType {
        case .normal:
            HStack(spacing: vm.spacing) {
                QuotaCardView(vm: vm)
                    .frame(width: 196)
                TrayView(vm: vm)
            }
            .transition(slideTransition)
        case .menu:
            NotchMenuView(vm: vm)
                .transition(slideTransition)
        case .settings:
            NotchSettingsView(vm: vm)
                .transition(slideTransition)
        }
    }
    .animation(vm.animation, value: vm.contentType)
}

/// 下一区从右侧滑入，上一区从左侧滑入，淡入淡出叠加
private var slideTransition: AnyTransition {
    if vm.lastSwipeDirection == .next {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    } else {
        .asymmetric(
            insertion: .move(edge: .leading).combined(with: .opacity),
            removal: .move(edge: .trailing).combined(with: .opacity)
        )
    }
}
```

注意：`slideTransition` 读 `vm.lastSwipeDirection`，过渡方向与手势一致。动画曲线仍用 `vm.animation`，顺滑打磨留给后续队伍。

- [ ] **步骤 4：运行验证**

运行：同任务 1 步骤 2 命令，预期 BUILD SUCCEEDED。
真机目视：左滑新内容从右侧进来，右滑从左侧进来，无闪烁跳变；开减少动态效果时直接显示。

- [ ] **步骤 5：Commit**

```bash
git add NotchDrop/NotchContentView.swift
git commit -m "feat: 内容区按手势方向滑入"
```

---

### 任务 7：首次轻提示

**文件：**
- 修改：`NotchDrop/NotchView.swift`

（提示标记 `hasSeenSwipeHint` 与 `markSwipeHintSeen` 已在任务 1 落地，本任务只加浮层。）

- [ ] **步骤 1：确认标记逻辑已覆盖**

`markSwipeHintSeen` 与 `hasSeenSwipeHint` 已在任务 1 落地并由 `testMarkSwipeHintSeenSetsFlag` 覆盖，本任务只加提示浮层，无新增逻辑，无新用例文件。

- [ ] **步骤 2：确认基线可构建**

运行：同任务 1 步骤 2 命令。
预期：BUILD SUCCEEDED。

- [ ] **步骤 3：编写最少实现代码**

`NotchView.swift` 展开内容 `VStack` 内、`NotchContentView` 之后追加：

```swift
if !vm.hasSeenSwipeHint {
    Text("左右滑动切换功能区")
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .transition(.opacity)
        .task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            vm.markSwipeHintSeen()
        }
}
```

首次成功滑动时任务 4 的订阅已调 `markSwipeHintSeen`，提示即消失；3 秒无操作也自动消失且不再出现。

- [ ] **步骤 4：运行测试验证通过**

运行：同任务 1 步骤 2 命令。
预期：BUILD SUCCEEDED，任务 1 的四个用例 PASS。
真机目视：首次展开面板底部有浅灰提示，3 秒后消失；杀进程重开不再出现。

- [ ] **步骤 5：Commit**

```bash
git add NotchDrop/NotchView.swift
git commit -m "feat: 首次滑动轻提示"
```

---

### 任务 8：回归验证

- [ ] **步骤 1：全量构建**

运行：

```bash
xcodebuild -project NotchDrop.xcodeproj -scheme NotchDrop -configuration Debug -derivedDataPath /tmp/nDD build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO
```

预期：BUILD SUCCEEDED。

- [ ] **步骤 2：发布构建**

运行：

```bash
xcodebuild -project NotchDrop.xcodeproj -scheme NotchDrop -configuration Release -derivedDataPath /tmp/nDDR build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO
```

预期：BUILD SUCCEEDED。

- [ ] **步骤 3：真机回归清单**

逐项确认：虚影悬停展开正常；拖文件展开与禁用切换；顶栏点击切下一区；指示器直跳；左右滑各一次只切一区且方向正确；首次提示出现并消失；右键菜单设置与退出可用。

- [ ] **步骤 4：Commit（仅当有修正时）**

```bash
git add -A
git commit -m "fix: 手势切换回归修正"
```

无修正则跳过本步骤，保持工作区干净。

---

## 自检

**1. 规格覆盖度：** 多设备可切→任务 3 转发加任务 4 接线；悬停语义（展开鼠标在上即可）→任务 4 守卫；顺序循环→任务 1；指示器可点→任务 5；单次一区→任务 2 冷却；拖文件不切→任务 4 守卫；首次轻提示→任务 7；默认开无开关→全计划无开关代码，符合；苹果风顺滑→明确留给后续队伍，本计划只做方向正确的基础过渡（任务 6）。

**2. 占位符扫描：** 无待定、无后续实现、无适当的错误处理式空话；每步都有确切代码与命令；无类似任务 N 的引用；`ScrollDelta`、`ArrowDirection`、`SwipeDirection`、`zoneOrder`、`events`、`markSwipeHintSeen` 均在首次使用的任务中定义，后续直接复用，命名一致。

**3. 类型一致性：** `SwipeDirection.next/previous` 在任务 1 定义，任务 2/4/6 同名复用；`ScrollDelta(deltaX:hasMomentum:timestamp:)` 在任务 3 定义，任务 4 按同名字段消费；`vm.events` 在任务 4 定义访问器，任务 4 内使用一致。
