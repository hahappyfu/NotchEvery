# 刘海面板 Nook 化动画 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 照抄 Nook 录屏的动画语言：顶栏选项卡条加滑动胶囊（可点且手势联动）、切换内容模糊淡入、面板跟随内容胀缩、展开收起曲线重调。

**架构：** 新建 `NotchTabBar` 分段控件（滑动胶囊用 `matchedGeometryEffect`，点选走已有 `jumpToZone`，复用防双切标记）；`NotchContentView` 的方向滑入过渡换成可动画模糊淡入修饰符；`NotchViewModel` 加分区高度表，面板 frame 与 `notchOpenedRect` 几何跟随当前区；展开收起弹簧与入场延迟重调，以真机手感验收为准。

**技术栈：** SwiftUI（`matchedGeometryEffect`、Animatable 修饰符过渡、`unevenRoundedRectangle` 不变），AppKit（`NSEvent` 不变），`XCTest`（沿用 `Tests/` 目录风格）。

---

## 文件结构

- 新建：`NotchDrop/NotchTabBar.swift` —— 分段选项卡条，滑动胶囊，点选回调。唯一新增视图归宿。
- 新建：`Tests/TabMetricsTests.swift` —— 分区高度表与选项卡标题单测。
- 修改：`NotchDrop/NotchHeaderView.swift` —— 右上角指示器换成居左选项卡条，删除 `PageIndicator`。
- 修改：`NotchDrop/NotchContentView.swift` —— 方向滑入过渡换成模糊淡入过渡。
- 修改：`NotchDrop/NotchViewModel.swift` —— 加 `zoneHeights` 表、`zoneOpenedSize`、`tabTitles`，重调 `openAnimation` / `closeAnimation`。
- 修改：`NotchDrop/NotchView.swift` —— 展开 frame 用分区尺寸，入场延迟重调。
- 修改：`NotchDrop/NotchGeometry`（`NotchViewModel.swift` 内）—— `notchOpenedRect` 跟随当前区尺寸。
- 修改：`NotchDrop/Localizable.xcstrings` —— 加 `TabOverview` / `TabMenu` / `TabSettings` 三键。

窗口是全屏尺寸（`NotchWindowController` 用 `screen.frame` 建窗），胀缩只是 SwiftUI 布局变化，不碰窗口。`StaggeredEntry` 保留，只改延迟。虚影、拖放、守卫、手势解析逻辑一律不动。

---

### 任务 1：选项卡条组件

**文件：**
- 创建：`NotchDrop/NotchTabBar.swift`
- 修改：`NotchDrop/Localizable.xcstrings`
- 测试：真机目视（胶囊滑动、点选高亮），见步骤 4

- [ ] **步骤 1：编写失败的测试**

本任务是纯视图组件，无纯逻辑可单测，测试即编译存在性检查。在 `Tests/TabMetricsTests.swift`（任务 6 建文件，此处先写本任务相关的一条）写入首条用例？不。本任务无测试文件，存在性由步骤 3 的构建验证覆盖，标题键去重由任务 4 的 `testTabTitlesAreDistinct` 覆盖。此处步骤记为：确认 `NotchTabBar` 符号不存在。

运行：`grep -rn "NotchTabBar" NotchDrop/`
预期：FAIL，无命中（exit 1）。

- [ ] **步骤 2：运行测试验证失败**

运行：同步骤 1 命令。
预期：FAIL，无命中。

- [ ] **步骤 3：编写最少实现代码**

创建 `NotchDrop/NotchTabBar.swift`：

```swift
import SwiftUI

/// 分段选项卡条：黑色滑动胶囊跟随选中项，可点直跳
struct NotchTabBar: View {
    let zones: [NotchViewModel.ContentType]
    let current: NotchViewModel.ContentType
    let onJump: (NotchViewModel.ContentType) -> Void
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(zones, id: \.self) { zone in
                Button {
                    onJump(zone)
                } label: {
                    Text(zone.tabTitleKey)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(zone == current ? .white : .secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background {
                            if zone == current {
                                Capsule()
                                    .fill(Color(nsColor: .separatorColor).opacity(0.9))
                                    .matchedGeometryEffect(id: "tabpill", in: pill)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(
            Capsule()
                .fill(Color(nsColor: .separatorColor).opacity(0.35))
        )
    }
}
```

`NotchViewModel.swift` 内 `ContentType` 加标题键（放在 `zoneOrder` 附近）：

```swift
var tabTitleKey: LocalizedStringKey {
    switch self {
    case .normal: "TabOverview"
    case .menu: "TabMenu"
    case .settings: "TabSettings"
    }
}
```

`Localizable.xcstrings` 按 `SwipeHint` 现有格式追加三键（en / zh-Hans / zh-Hant）：

- `TabOverview`：en "Overview"，zh-Hans "概览"，zh-Hant "概覽"
- `TabMenu`：en "Menu"，zh-Hans "菜单"，zh-Hant "菜單"
- `TabSettings`：en "Settings"，zh-Hans "设置"，zh-Hant "設置"

- [ ] **步骤 4：运行验证**

运行：`xcodebuild -project NotchDrop.xcodeproj -scheme NotchDrop -configuration Debug -derivedDataPath /tmp/nDD build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO`
预期：BUILD SUCCEEDED。
真机目视（无条件则如实声明转验收）：选项卡三段，选中黑胶囊，点选滑动跟手。

- [ ] **步骤 5：Commit**

```bash
git add NotchDrop/NotchTabBar.swift NotchDrop/NotchViewModel.swift NotchDrop/Localizable.xcstrings
git commit -m "feat: 选项卡条组件与三区标题"
```

---

### 任务 2：顶栏接入选项卡

**文件：**
- 修改：`NotchDrop/NotchHeaderView.swift`

- [ ] **步骤 1：编写失败的测试**

纯外观变更，真机目视验证，无新单测文件。先确认基线可构建。

运行：同任务 1 步骤 4 命令。
预期：BUILD SUCCEEDED。

- [ ] **步骤 2：确认基线可构建**

运行：同上。
预期：BUILD SUCCEEDED。

- [ ] **步骤 3：编写最少实现代码**

`NotchHeaderView.swift` 的 `body` 改为选项卡居左：

```swift
var body: some View {
    HStack {
        NotchTabBar(
            zones: NotchViewModel.zoneOrder,
            current: vm.contentType,
            onJump: { vm.jumpToZone($0) }
        )
        Spacer()
    }
    .animation(vm.animation, value: vm.contentType)
    .font(.system(.headline, design: .rounded))
}
```

删除文件内的 `PageIndicator` 结构体（如仍存在则整段删掉，不留孤儿代码）。标题文字（`NotchEvery` / 版本号）在设置区不再显示，标题信息由选项卡承担；`versionText` 如无他用一并删除。

注意：点选仍走 `jumpToZone`，防双切标记（`suppressHeadlineClickOnce`）继续有效，不要动 `NotchViewModel+Events.swift`。

- [ ] **步骤 4：运行验证**

运行：同任务 1 步骤 4 命令，预期 BUILD SUCCEEDED。
真机目视：顶栏左侧三段选项卡，点选胶囊滑动，滑动手势时胶囊联动（同一 `contentType` 驱动）。

- [ ] **步骤 5：Commit**

```bash
git add NotchDrop/NotchHeaderView.swift
git commit -m "feat: 顶栏接入居左选项卡条"
```

---

### 任务 3：切换过渡换模糊淡入

**文件：**
- 修改：`NotchDrop/NotchContentView.swift`

- [ ] **步骤 1：编写失败的测试**

纯过渡变更，真机目视验证，无新单测文件。先确认基线可构建。

运行：同任务 1 步骤 4 命令。
预期：BUILD SUCCEEDED。

- [ ] **步骤 2：确认基线可构建**

运行：同上。
预期：BUILD SUCCEEDED。

- [ ] **步骤 3：编写最少实现代码**

`NotchContentView.swift` 改为：

```swift
struct NotchContentView: View {
    @StateObject var vm: NotchViewModel

    var body: some View {
        ZStack {
            switch vm.contentType {
            case .normal:
                HStack(spacing: vm.spacing) {
                    QuotaCardView(vm: vm)
                        .frame(width: 196)
                    TrayView(vm: vm)
                }
                .transition(.blurFade)
            case .menu:
                NotchMenuView(vm: vm)
                    .transition(.blurFade)
            case .settings:
                NotchSettingsView(vm: vm)
                    .transition(.blurFade)
            }
        }
        .animation(vm.animation, value: vm.contentType)
    }
}

/// 模糊淡入过渡：出现时 blur 6→0 + 透明度 + 轻微放大，消失时反向快退
struct BlurFadeModifier: ViewModifier, Animatable {
    var amount: CGFloat

    var animatableData: CGFloat {
        get { amount }
        set { amount = newValue }
    }

    func body(content: Content) -> some View {
        content
            .opacity(1 - amount)
            .blur(radius: 6 * amount)
            .scaleEffect(1 - 0.02 * amount)
    }
}

extension AnyTransition {
    static var blurFade: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: BlurFadeModifier(amount: 1), identity: BlurFadeModifier(amount: 0)),
            removal: .modifier(active: BlurFadeModifier(amount: 1), identity: BlurFadeModifier(amount: 0))
        )
    }
}
```

任务 6 的方向滑入过渡（`slideTransition`）整段删除，不留孤儿代码。`lastSwipeDirection` 的读写保留（`jumpToZone` / 手势仍在写，将来可能再用），只删过渡消费处。

- [ ] **步骤 4：运行验证**

运行：同任务 1 步骤 4 命令，预期 BUILD SUCCEEDED。
真机目视：切换时旧内容模糊淡出、新内容模糊淡入带轻微放大，无方向滑动，无闪烁；开减少动态效果时直接显示（过渡不播放）。

- [ ] **步骤 5：Commit**

```bash
git add NotchDrop/NotchContentView.swift
git commit -m "feat: 切换过渡换模糊淡入"
```

---

### 任务 4：分区尺寸与胀缩

**文件：**
- 修改：`NotchDrop/NotchViewModel.swift`（含 `NotchGeometry`）
- 修改：`NotchDrop/NotchView.swift`

- [ ] **步骤 1：编写失败的测试**

创建 `Tests/TabMetricsTests.swift`：

```swift
import XCTest
@testable import NotchEvery

final class TabMetricsTests: XCTestCase {
    func testZoneHeightsCoverAllZones() {
        for zone in NotchViewModel.zoneOrder {
            XCTAssertNotNil(NotchViewModel.zoneHeights[zone], "\(zone) 缺少高度")
        }
    }

    func testOverviewSizeLocked() {
        let vm = NotchViewModel(events: MockEventMonitors())
        vm.jumpToZone(.normal)
        XCTAssertEqual(vm.zoneOpenedSize, CGSize(width: 600, height: 160))
    }

    func testZoneOpenedSizeFollowsCurrentZone() {
        let vm = NotchViewModel(events: MockEventMonitors())
        vm.jumpToZone(.menu)
        XCTAssertEqual(vm.zoneOpenedSize.height, NotchViewModel.zoneHeights[.menu])
        vm.jumpToZone(.settings)
        XCTAssertEqual(vm.zoneOpenedSize.height, NotchViewModel.zoneHeights[.settings])
    }

    func testTabTitlesAreDistinct() {
        let keys = NotchViewModel.zoneOrder.map { String(describing: $0.tabTitleKey) }
        XCTAssertEqual(Set(keys).count, keys.count)
    }
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：同任务 1 步骤 4 命令。
预期：FAIL，`zoneHeights` / `zoneOpenedSize` / `tabTitleKey` 未定义（`tabTitleKey` 在任务 1 已定义，`zoneHeights` 与 `zoneOpenedSize` 未定义）。

- [ ] **步骤 3：编写最少实现代码**

`NotchViewModel.swift` 在 `zoneOrder` 附近追加：

```swift
/// 分区高度表：宽固定 600，高跟随内容；概览 160 锁定不动
static let zoneHeights: [ContentType: CGFloat] = [
    .normal: 160,
    .menu: 150,
    .settings: 190,
]

/// 当前区分辨率：宽 600 锁死，高查表
var zoneOpenedSize: CGSize {
    CGSize(width: 600, height: Self.zoneHeights[contentType] ?? 160)
}
```

菜单与设置高度初始值按内容量出：读 `NotchMenuView`（一行四个正方形按钮，宽 600 面板内边距与间距决定按钮边长）与 `NotchSettingsView`（两行控件叠高）估算，保证内容不裁剪；取值理由写进报告。真机验收时若裁剪或留白过大，随手感微调（只改数字，不改机制）。

`NotchGeometry` 改为跟随当前区，并删除被替代的常量。先 grep 确认 `notchOpenedSize` 的全部引用就是以下四处（几何计算、`NotchView` 的 `.opened` 分支、第 77 行 frame、第 115 行过渡偏移），然后四处全换成 `zoneOpenedSize`，最后删除 `notchOpenedSize` 常量定义，不留孤儿代码：

```swift
var geometry: NotchGeometry {
    NotchGeometry(
        deviceNotchRect: deviceNotchRect,
        screenRect: screenRect,
        notchOpenedSize: zoneOpenedSize,
        inset: inset
    )
}
```

`NotchView.swift` 的 `notchSize` 方法 `.opened` 分支改为 `return vm.zoneOpenedSize`（否则外壳保持 600x160 与内容脱节）；第 115 行过渡偏移改为 `-vm.zoneOpenedSize.height / 2`。第 77 行展开 frame 改为：

```swift
.frame(maxWidth: vm.zoneOpenedSize.width, maxHeight: vm.zoneOpenedSize.height)
```

并在该 frame 上加尺寸动画（切换分区时胀缩）：

```swift
.animation(vm.animation, value: vm.contentType)
```

- [ ] **步骤 4：运行测试验证通过**

运行：同任务 1 步骤 4 命令。
预期：BUILD SUCCEEDED（用例随测试目标现状执行）。
真机目视：切区时面板高跟着胀缩，全程动画无跳变；鼠标守卫与拖放区域跟随新尺寸（面板外滑动不切换）。

- [ ] **步骤 5：Commit**

```bash
git add NotchDrop/NotchViewModel.swift NotchDrop/NotchView.swift Tests/TabMetricsTests.swift
git commit -m "feat: 分区尺寸表与面板胀缩"
```

---

### 任务 5：展开收起曲线重调

**文件：**
- 修改：`NotchDrop/NotchViewModel.swift`
- 修改：`NotchDrop/NotchView.swift`

- [ ] **步骤 1：编写失败的测试**

弹簧参数无单测意义上的对错，验收是真机手感。先确认基线可构建。

运行：同任务 1 步骤 4 命令。
预期：BUILD SUCCEEDED。

- [ ] **步骤 2：确认基线可构建**

运行：同上。
预期：BUILD SUCCEEDED。

- [ ] **步骤 3：编写最少实现代码**

`NotchViewModel.swift` 的两条弹簧换成起点值：

```swift
/// 展开弹簧：Nook 式快长轻微过冲
let openAnimation: Animation = .spring(response: 0.3, dampingFraction: 0.8)
/// 收起弹簧：无过冲快退，比展开稍快
let closeAnimation: Animation = .spring(response: 0.22, dampingFraction: 1.0)
```

`NotchView.swift` 入场延迟收紧（内容更快跟上生长）：

```swift
NotchHeaderView(vm: vm)
    .modifier(StaggeredEntry(delay: 0.06))
NotchContentView(vm: vm)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .modifier(StaggeredEntry(delay: 0.14))
```

以上三处数字是起点，允许按手感微调一轮（只改数字，不换曲线类型、不加新参数），调过的值与理由写进报告。虚影、拖放、守卫逻辑不动。

- [ ] **步骤 4：运行验证**

运行：同任务 1 步骤 4 命令，预期 BUILD SUCCEEDED。
真机手感（无条件则如实声明转用户验收）：展开像从刘海长出来、无卡顿无过大回弹；收起干脆；内容入场比面板慢半拍。

- [ ] **步骤 5：Commit**

```bash
git add NotchDrop/NotchViewModel.swift NotchDrop/NotchView.swift
git commit -m "feat: 展开收起曲线重调"
```

---

### 任务 6：单测与回归验证

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

- [ ] **步骤 3：真机手感清单**

逐项确认（无真机条件则如实声明，转用户验收）：选项卡点选胶囊滑动、滑动手势胶囊联动、切换模糊淡入无闪烁、面板胀缩跟手、展开生长顺滑、首次提示如常、右键菜单可用。

- [ ] **步骤 4：Commit（仅当有修正时）**

```bash
git add -A
git commit -m "fix: Nook 化动画回归修正"
```

无修正则跳过本步骤，保持工作区干净。

---

## 自检

**1. 规格覆盖度：** 选项卡条加胶囊→任务 1；居左接入→任务 2；点選手势联动（同一 contentType 驱动加防双切复用）→任务 1/2；模糊淡入→任务 3；面板胀缩→任务 4；展开收起重调→任务 5；手感验收→任务 6。标题本地化→任务 1。尺寸不动（宽 600 锁死、概览 160 锁定）→任务 4。

**2. 占位符扫描：** 无待定、无后续实现；每步都有确切代码与命令；`tabTitleKey` 在任务 1 定义、任务 2/4 与测试复用同名；`zoneHeights` / `zoneOpenedSize` 在任务 4 定义、测试与视图同名消费；`blurFade` 在任务 3 定义并消费。菜单/设置高度初始值由实现者按视图代码量出并在报告中记录理由，不是待定，是工程取值。

**3. 类型一致性：** `zoneOrder` / `jumpToZone` / `suppressHeadlineClickOnce` 沿用已冻结接口；`BlurFadeModifier` 的 `Animatable` 协议写法自包含；`zoneOpenedSize` 始终返回宽 600；测试断言的键名与实现一致。
