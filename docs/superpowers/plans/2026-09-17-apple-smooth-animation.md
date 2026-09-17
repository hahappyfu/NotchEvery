# 苹果原生级丝滑动画体系重构实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 subagent-driven-development（推荐）或 executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 全面优化 NotchEvery 动画体验，升级为对标 Apple 灵动岛的丝滑高刷物理弹簧，收敛全局动画事务，清理视图层脱节动效，并消除 AppKit 窗口冗余重绘导致的掉帧。

**架构：** 在 `NotchViewModel` 中以高精度物理 Spring 取代已废弃的老旧 interactiveSpring，并将开合与切页动作统一纳入全局 `withAnimation` 事务；在 `NotchView` 与 `NotchContentView` 中移除冲突的子级延迟下移，重构切页平滑滑动转场；在 `NotchWindowController` 增加窗口几何判等过滤以避免动画帧内强刷。

**技术栈：** Swift 5.9+, SwiftUI, AppKit (`NSWindow`, `CALayer`), Combine, XCTest

**规格：** `docs/superpowers/specs/2026-09-17-apple-smooth-animation-design.md`

## 全局约束

- 展开动画弹簧：`.spring(response: 0.36, dampingFraction: 0.82, blendDuration: 0.08)`
- 收起动画弹簧：`.spring(response: 0.26, dampingFraction: 1.0, blendDuration: 0.05)`（临界阻尼无回弹）
- 切页动画弹簧：`.spring(response: 0.32, dampingFraction: 0.86)`
- 测试运行姿势：`xcodebuild test -project NotchDrop.xcodeproj -scheme NotchDrop -destination 'platform=macOS' -derivedDataPath /tmp/nDD CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO`
- 遵循 Karpathy 准则：精准修改必要代码，不改变业务状态机逻辑，不破坏现有 440+ 单测。

---

### 任务 1：升级物理弹簧参数与常量体系

**文件：**
- 修改：`NotchDrop/NotchViewModel.swift:210-225`
- 修改：`NotchDrop/DesignSystem.swift:27-35`
- 测试：`Tests/AnimationMetricsTests.swift`

- [ ] **步骤 1：编写针对动画参数与响应特性的单测**

在 `Tests/AnimationMetricsTests.swift` 中编写测试，锁定 `openAnimation`、`closeAnimation`、`pageAnimation` 以及 `StudioAnimation` 的核心配置，确保展开有弹力、收起无震荡。

```swift
import XCTest
import SwiftUI
@testable import NotchEvery

final class AnimationMetricsTests: XCTestCase {
    func testSpringAnimationDefinitionsExist() {
        let vm = NotchViewModel()
        XCTAssertNotNil(vm.openAnimation)
        XCTAssertNotNil(vm.closeAnimation)
        XCTAssertNotNil(vm.pageAnimation)
        XCTAssertNotNil(StudioAnimation.interactiveSpring)
    }

    func testStudioAnimationResponseRange() {
        XCTAssertEqual(StudioAnimation.springResponse, 0.32, accuracy: 0.01)
        XCTAssertEqual(StudioAnimation.springDamping, 0.86, accuracy: 0.01)
    }
}
```

- [ ] **步骤 2：运行单测验证失败（红灯）**

运行：
```bash
xcodebuild test -project NotchDrop.xcodeproj -scheme NotchDrop -destination 'platform=macOS' -derivedDataPath /tmp/nDD -only-testing:NotchEveryTests/AnimationMetricsTests CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```
预期：编译失败或断言失败（`springDamping` 目前是 0.82 而非期望值，或文件不存在）。

- [ ] **步骤 3：更新 `NotchViewModel.swift` 与 `DesignSystem.swift` 弹簧定义**

更新 `NotchDrop/NotchViewModel.swift`：
```swift
    /// 展开弹簧：对齐 Apple 灵动岛原生感（360ms 快速舒展，0.82 阻尼保留微弹水滴感）
    let openAnimation: Animation = .spring(response: 0.36, dampingFraction: 0.82, blendDuration: 0.08)
    /// 收起弹簧：对齐 Apple 原生吸附（260ms 快收，1.0 临界阻尼绝对零反弹）
    let closeAnimation: Animation = .spring(response: 0.26, dampingFraction: 1.0, blendDuration: 0.05)
    /// 切页专用：高抗抖横向位移弹簧（320ms，0.86 阻尼平稳推进）
    let pageAnimation: Animation = .spring(response: 0.32, dampingFraction: 0.86)
```

更新 `NotchDrop/DesignSystem.swift`：
```swift
public enum StudioAnimation {
    public static let springResponse: Double = 0.32
    public static let springDamping: Double = 0.86
    public static var interactiveSpring: Animation {
        .spring(response: springResponse, dampingFraction: springDamping)
    }
}
```

- [ ] **步骤 4：运行测试验证通过（绿灯）**

运行：
```bash
xcodebuild test -project NotchDrop.xcodeproj -scheme NotchDrop -destination 'platform=macOS' -derivedDataPath /tmp/nDD -only-testing:NotchEveryTests/AnimationMetricsTests CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```
预期：PASS。

- [ ] **步骤 5：提交代码**

```bash
git add Tests/AnimationMetricsTests.swift NotchDrop/NotchViewModel.swift NotchDrop/DesignSystem.swift
git commit -m "feat(animation): 对齐 Apple 灵动岛高精度物理弹簧参数"
```

---

### 任务 2：统一全局动画事务与驱动时序收敛

**文件：**
- 修改：`NotchDrop/NotchViewModel.swift:255-365`

- [ ] **步骤 1：编写全局动画事务执行测试**

在 `Tests/AnimationMetricsTests.swift` 中增加对 `openFromGhost`、`notchOpen`、`jumpToZone` 触发时 `transitionActive` 行为的测试：

```swift
    func testOpenTriggersTransitionActive() {
        let vm = NotchViewModel()
        XCTAssertFalse(vm.transitionActive)
        vm.notchOpen(.click)
        XCTAssertEqual(vm.status, .opened)
        XCTAssertTrue(vm.transitionActive)
    }

    func testJumpToZoneUpdatesDirection() {
        let vm = NotchViewModel()
        vm.jumpToZone(.token)
        XCTAssertEqual(vm.contentType, .token)
        XCTAssertEqual(vm.lastSwipeDirection, .next)
    }
```

- [ ] **步骤 2：运行测试确认基础行为**

运行：
```bash
xcodebuild test -project NotchDrop.xcodeproj -scheme NotchDrop -destination 'platform=macOS' -derivedDataPath /tmp/nDD -only-testing:NotchEveryTests/AnimationMetricsTests CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

- [ ] **步骤 3：在 `NotchViewModel.swift` 中全面收敛动画事务**

重构 `openFromGhost`、`notchOpen`、`jumpToZone`、`nextZone`、`previousZone`：
1. 在 `openFromGhost()` 中将 `status = .opened` 包裹在 `withAnimation(openAnimation)`；
2. 在 `notchOpen(_ reason: OpenReason)` 的非 hover 分支中，将 `status = .opened` 包裹在 `withAnimation(openAnimation)`；
3. 在 `jumpToZone`、`nextZone`、`previousZone` 中包裹在 `withAnimation(pageAnimation)`；
4. 确保 `transitionActive` 在切页时也短暂激活（350ms 后置 false），防止切页微调尺寸被忽略。

- [ ] **步骤 4：运行测试验证通过**

运行：
```bash
xcodebuild test -project NotchDrop.xcodeproj -scheme NotchDrop -destination 'platform=macOS' -derivedDataPath /tmp/nDD -only-testing:NotchEveryTests/AnimationMetricsTests CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```
预期：PASS。

- [ ] **步骤 5：提交代码**

```bash
git add NotchDrop/NotchViewModel.swift Tests/AnimationMetricsTests.swift
git commit -m "refactor(animation): 统一开合与切页的全局动画事务与时序"
```

---

### 任务 3：清理视图层脱节动效并升级平滑切页转场

**文件：**
- 修改：`NotchDrop/NotchView.swift:65-75, 280-299`
- 修改：`NotchDrop/NotchContentView.swift:28-45`

- [ ] **步骤 1：重构 `NotchContentView.swift` 的切页滑动转场**

将 `zoneSlideNext` 和 `zoneSlidePrevious` 升级为双向平滑滑动对齐，彻底消除移除端瞬间消失或白底闪烁：

```swift
    static var zoneSlideNext: AnyTransition {
        .asymmetric(
            insertion: .offset(x: 28).combined(with: .opacity),
            removal: .offset(x: -20).combined(with: .opacity)
        )
    }

    static var zoneSlidePrevious: AnyTransition {
        .asymmetric(
            insertion: .offset(x: -28).combined(with: .opacity),
            removal: .offset(x: 20).combined(with: .opacity)
        )
    }
```

- [ ] **步骤 2：移除 `NotchView.swift` 中的 `StaggeredEntry` 延迟下移动画**

1. 将 `NotchContentView(vm: vm).modifier(StaggeredEntry(delay: 0.06))` 替换为直接呈现 `NotchContentView(vm: vm)`，使内容与黑色灵动岛背景以相同的顶对齐锚点自然舒展放大：
```swift
    .transition(
        .scale(scale: 0.94, anchor: .top).combined(with: .opacity)
    )
```
2. 清理废弃的 `StaggeredEntry` 结构体，消除内层多余的 `withAnimation(.easeOut.delay)`。

- [ ] **步骤 3：运行全量回归测试**

运行：
```bash
xcodebuild test -project NotchDrop.xcodeproj -scheme NotchDrop -destination 'platform=macOS' -derivedDataPath /tmp/nDD -only-testing:NotchEveryTests/TabMetricsTests CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```
预期：PASS。

- [ ] **步骤 4：提交代码**

```bash
git add NotchDrop/NotchView.swift NotchDrop/NotchContentView.swift
git commit -m "fix(ui): 消除内容入场延迟断层并优化双向平滑切页转场"
```

---

### 任务 4：AppKit 窗口图层与 setFrame 防抖调优

**文件：**
- 修改：`NotchDrop/NotchWindowController.swift:35-59`
- 修改：`NotchDrop/NotchWindow.swift:20-50`

- [ ] **步骤 1：在 `NotchWindowController.swift` 增加 setFrame 防抖判等**

在 `NotchWindowController.swift` 的 sink 监听中：
```swift
let target = CGRect(
    x: screen.frame.origin.x,
    y: screen.frame.origin.y + screen.frame.height - height,
    width: screen.frame.width,
    height: height
)
if abs(window.frame.origin.x - target.origin.x) > 0.5 ||
   abs(window.frame.origin.y - target.origin.y) > 0.5 ||
   abs(window.frame.size.width - target.size.width) > 0.5 ||
   abs(window.frame.size.height - target.size.height) > 0.5 {
    self?.hostingHeightConstraint?.constant = height
    window.setFrame(target, display: true)
    notchTimingMark("setFrame h=\(Int(height))")
}
```

- [ ] **步骤 2：优化 `NotchWindow` 图层与刷新率**

在 `NotchWindow.swift` 的 `init` 中，确保图层启用硬件加速与合成优化：
```swift
contentView?.wantsLayer = true
contentView?.layer?.drawsAsynchronously = true
```

- [ ] **步骤 3：运行全量单测验证**

运行：
```bash
xcodebuild test -project NotchDrop.xcodeproj -scheme NotchDrop -destination 'platform=macOS' -derivedDataPath /tmp/nDD -only-testing:NotchEveryTests/TabMetricsTests CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```
预期：PASS。

- [ ] **步骤 4：提交代码**

```bash
git add NotchDrop/NotchWindowController.swift NotchDrop/NotchWindow.swift
git commit -m "perf(window): 增加窗口 setFrame 判等防抖并开启异步绘制"
```

---

### 任务 5：全量验证与真机运行确认

- [ ] **步骤 1：运行全量单元测试**
运行全量测试套件，确保没有回归缺陷。
- [ ] **步骤 2：编译运行 Debug App 实例供真机视效过目**
编译安装并重新拉起应用，让用户真机确认丝滑度和手感。
