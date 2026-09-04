# 刘海黑曜石外壳 + 状态/托盘 Tab 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 刘海外壳锁定纯黑曜石磨砂、自定义 G2 连续轮廓去飞檐，顶栏加状态/托盘胶囊分页并实现拖拽自动切托盘。

**架构：** 状态机只加一个正交维度 `PanelTab`，不动 `status`/`contentType`；几何用新 `NotchShellShape` 一笔画替代两块反角 overlay；材质用新 `obsidian` 修饰符复用现有 `ultraThinMaterial` 链路。

**技术栈：** SwiftUI（macOS 13+）、`xcodebuild -project NotchDrop.xcodeproj -target NotchDrop` 验证构建。

---

## 文件结构

- 修改：`NotchDrop/Glass.swift`——新增 `obsidianCard` / `obsidian(in:)` 黑曜石材质
- 创建：`NotchDrop/NotchShellShape.swift`——顶部贴边 + 底部 26pt 贝塞尔圆角，单一职责
- 修改：`NotchDrop/NotchView.swift`——外壳换新形状与材质、删反角遮罩、内容区加 24pt 摄像头避让
- 修改：`NotchDrop/NotchViewModel.swift`——新增 `PanelTab` 枚举与 `activeTab`，`notchOpenedSize` 高度 160→180
- 修改：`NotchDrop/NotchHeaderView.swift`——左侧双胶囊分段，右侧保持原样
- 修改：`NotchDrop/NotchContentView.swift`——按 `activeTab` 切换状态页/托盘页
- 修改：`NotchDrop/TrayDrop+View.swift`、`NotchDrop/QuotaCardView.swift`——内卡片换黑曜石材质（圆角保持 16pt 不动）

---

### 任务 1：黑曜石材质修饰符

**文件：**
- 修改：`NotchDrop/Glass.swift`（文件末尾追加，不碰现有 `GlassCardModifier`）
- 测试：构建验证

- [ ] **步骤 1：在 `Glass.swift` 末尾追加黑曜石修饰符**

```swift
// MARK: - 黑曜石外壳（浅深色双模式锁死纯黑）

extension View {
    /// 黑曜石卡片：圆角矩形版本（托盘、额度卡等内卡片用）
    func obsidianCard(cornerRadius: CGFloat) -> some View {
        obsidian(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// 黑曜石外壳：任意形状版本（刘海外壳用 NotchShellShape）
    func obsidian<S: Shape>(in shape: S) -> some View {
        self
            .background(shape.fill(Color.black.opacity(0.88)))
            .background(shape.fill(.ultraThinMaterial))
            .overlay(shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8))
    }
}
```

说明：黑底打底保证浅色壁纸不透摄像头黑斑；磨砂叠在黑上保留质感；不再走 `glassEffect` 分支（macOS 26 的 Liquid Glass 会提亮透底，与锁黑冲突，刻意放弃）。

- [ ] **步骤 2：构建验证通过**

运行：`xcodebuild -project NotchDrop.xcodeproj -target NotchDrop -configuration Debug build`
预期：BUILD SUCCEEDED（只加扩展，无调用方，必过）

- [ ] **步骤 3：Commit**

```bash
git add NotchDrop/Glass.swift
git commit -m "feat: 新增黑曜石外壳材质修饰符"
```

---

### 任务 2：自定义外壳几何并替换刘海遮罩

**文件：**
- 创建：`NotchDrop/NotchShellShape.swift`
- 修改：`NotchDrop/NotchView.swift`（`notchCornerRadius`、`notch`、`glassNotchBackground`、`notchBackgroundMaskGroup`、内容区 padding）
- 测试：构建验证

- [ ] **步骤 1：创建 `NotchDrop/NotchShellShape.swift`**

```swift
//
//  NotchShellShape.swift
//  NotchDrop
//
//  刘海外壳轮廓：顶部贴边平直（两端 6pt 微过渡），
//  底部两角 26pt 三次贝塞尔逼近曲率连续（squircle 同族曲线）
//

import SwiftUI

struct NotchShellShape: Shape {
    var topMicroRadius: CGFloat = 6
    var bottomRadius: CGFloat = 26

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let tr = min(topMicroRadius, rect.width / 2, rect.height / 2)
        let br = min(bottomRadius, rect.width / 2, rect.height)
        let k = br * 0.52
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        p.addArc(
            center: CGPoint(x: rect.maxX - tr, y: rect.minY + tr),
            radius: tr, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false
        )
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        p.addCurve(
            to: CGPoint(x: rect.maxX - br, y: rect.maxY),
            control1: CGPoint(x: rect.maxX, y: rect.maxY - br + k),
            control2: CGPoint(x: rect.maxX - br + k, y: rect.maxY)
        )
        p.addLine(to: CGPoint(x: rect.minX + br, y: rect.maxY))
        p.addCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - br),
            control1: CGPoint(x: rect.minX + br - k, y: rect.maxY),
            control2: CGPoint(x: rect.minX, y: rect.maxY - br + k)
        )
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tr))
        p.addArc(
            center: CGPoint(x: rect.minX + tr, y: rect.minY + tr),
            radius: tr, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false
        )
        p.closeSubpath()
        return p
    }
}
```

- [ ] **步骤 2：改 `NotchView.swift`——展开圆角 32→26**

```swift
var notchCornerRadius: CGFloat {
    switch vm.status {
    case .closed: 8
    case .opened: 26
    case .popping: 10
    }
}
```

- [ ] **步骤 3：改 `NotchView.swift`——`notch` 用新形状，删遮罩组**

用下面整体替换 `notch`、`glassNotchBackground`、`notchBackgroundMaskGroup` 三块（第 74～142 行）：

```swift
var notch: some View {
    Rectangle()
        .fill(.clear)
        .obsidian(in: NotchShellShape(
            topMicroRadius: vm.status == .opened ? 6 : notchCornerRadius,
            bottomRadius: notchCornerRadius
        ))
        .frame(
            width: notchSize.width,
            height: notchSize.height
        )
        .shadow(
            color: .black.opacity(([.opened, .popping].contains(vm.status)) ? 0.3 : 0),
            radius: 20,
            y: 8
        )
}
```

注意：`frame` 宽度不再加 `notchCornerRadius * 2`（加宽是给已删除的反角 overlay 留的）。`notchBackgroundMaskGroup` 整段删除，约 47 行净删。

- [ ] **步骤 4：改 `NotchView.swift`——内容区 24pt 摄像头避让 + 10pt 同心边距**

把 `body` 里 `.padding(vm.spacing)` 一行替换为：

```swift
.padding(.horizontal, 10)
.padding(.bottom, 10)
.padding(.top, 24)
```

`VStack(spacing: vm.spacing)` 保持不动。24 是硬件摄像头避让高度，10 是同心圆角边距（外壳 26 − 10 = 内卡片 16）。

- [ ] **步骤 5：改 `NotchViewModel.swift`——展开高度 160→180**

```swift
let notchOpenedSize: CGSize = .init(width: 600, height: 180)
```

理由：顶部多出 8pt 避让（24 − 原 16）必须从高度补，否则额度卡（环 68 + 标签 + 内边距 12，共约 105pt）会被压扁。180 − 24 − 10 − 标题 22 − 间距 16 = 108，刚好放下。

- [ ] **步骤 6：构建验证通过**

运行：`xcodebuild -project NotchDrop.xcodeproj -target NotchDrop -configuration Debug build`
预期：BUILD SUCCEEDED；若报 `notchBackgroundMaskGroup` 未定义引用，说明有残留调用，全局搜该名并删干净

- [ ] **步骤 7：Commit**

```bash
git add NotchDrop/NotchShellShape.swift NotchDrop/NotchView.swift NotchDrop/NotchViewModel.swift
git commit -m "feat: 自定义 G2 外壳几何，去飞檐并加摄像头避让"
```

---

### 任务 3：Tab 状态机与拖拽联动

**文件：**
- 修改：`NotchDrop/NotchViewModel.swift`（枚举 + 属性 + 开关重置）
- 修改：`NotchDrop/NotchView.swift`（`dragDetector` 的 `onChange`）
- 测试：构建验证

- [ ] **步骤 1：`NotchViewModel.swift` 加 `PanelTab` 枚举与发布属性**

在 `ContentType` 枚举后追加：

```swift
enum PanelTab: String, Codable, Hashable, Equatable {
    case status
    case tray
}
```

在 `@Published var contentType` 下一行追加：

```swift
@Published var activeTab: PanelTab = .status
```

- [ ] **步骤 2：开关时重置 Tab**

`notchOpen` 内 `contentType = .normal` 后加一行 `activeTab = .status`；`notchClose` 同样位置加一行 `activeTab = .status`。拖拽离开不切回（用户可能正看托盘，抢回去是打扰）。

- [ ] **步骤 3：`NotchView.swift` 的 `dragDetector.onChange` 改为拖拽联动**

```swift
.onChange(of: dropTargeting) { isTargeted in
    if isTargeted {
        if vm.status == .closed {
            // 文件拖到刘海：先展开
            vm.notchOpen(.drag)
        }
        if vm.activeTab != .tray {
            // 已展开但停在状态页：平滑切到托盘
            withAnimation(vm.animation) { vm.activeTab = .tray }
        }
        vm.hapticSender.send()
    } else if !isTargeted {
        // Close the notch when the dragged item leaves the area
        let mouseLocation: NSPoint = NSEvent.mouseLocation
        if !vm.notchOpenedRect.insetBy(dx: vm.inset, dy: vm.inset).contains(mouseLocation) {
            vm.notchClose()
        }
    }
}
```

注意顺序：先 `notchOpen`（内部重置 `.status`），再置 `.tray`，否则会被重置覆盖。震动沿用 `hapticSender`（已有 0.5s 节流，不会连震）。

- [ ] **步骤 4：构建验证通过**

运行：`xcodebuild -project NotchDrop.xcodeproj -target NotchDrop -configuration Debug build`
预期：BUILD SUCCEEDED

- [ ] **步骤 5：Commit**

```bash
git add NotchDrop/NotchViewModel.swift NotchDrop/NotchView.swift
git commit -m "feat: 主面板状态托盘双 Tab 与拖拽自动切换"
```

---

### 任务 4：顶栏胶囊分段与内容切换

**文件：**
- 修改：`NotchDrop/NotchHeaderView.swift`
- 修改：`NotchDrop/NotchContentView.swift`
- 测试：构建验证

- [ ] **步骤 1：重写 `NotchHeaderView.swift`**

```swift
import SwiftUI

struct NotchHeaderView: View {
    @StateObject var vm: NotchViewModel
    @Namespace private var tabSlider

    var versionText: String {
        let ver = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        return String(format: NSLocalizedString("Version: %@ (Build: %@)", comment: ""), ver, build)
    }

    var body: some View {
        HStack {
            if vm.contentType == .normal {
                tabCapsule
            } else {
                Text(vm.contentType == .settings ? versionText : "NotchEvery")
                    .contentTransition(.numericText())
                    .foregroundStyle(.primary)
            }
            Spacer()
            Image(systemName: "ellipsis")
                .foregroundStyle(.secondary)
        }
        .animation(vm.animation, value: vm.contentType)
        .font(.system(.headline, design: .rounded))
    }

    private var tabCapsule: some View {
        HStack(spacing: 2) {
            tabButton(.status, title: "状态")
            tabButton(.tray, title: "托盘")
        }
        .padding(2)
        .background(Capsule().fill(Color.white.opacity(0.08)))
    }

    private func tabButton(_ tab: NotchViewModel.PanelTab, title: String) -> some View {
        Button {
            withAnimation(vm.animation) { vm.activeTab = tab }
        } label: {
            Text(title)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background {
                    if vm.activeTab == tab {
                        Capsule()
                            .fill(Color.white.opacity(0.14))
                            .matchedGeometryEffect(id: "panelTab", in: tabSlider)
                    }
                }
                .foregroundStyle(vm.activeTab == tab ? .primary : .secondary)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NotchHeaderView(vm: .init())
}
```

菜单/设置态保持原标题，右侧省略号不动。

- [ ] **步骤 2：重写 `NotchContentView.swift` 的 `.normal` 分支**

```swift
var body: some View {
    ZStack {
        switch vm.contentType {
        case .normal:
            Group {
                if vm.activeTab == .status {
                    HStack(spacing: vm.spacing) {
                        QuotaCardView(vm: vm)
                            .frame(width: 196)
                        Spacer(minLength: 0)
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                } else {
                    TrayView(vm: vm)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                }
            }
            .animation(vm.animation, value: vm.activeTab)
        case .menu:
            NotchMenuView(vm: vm)
                .transition(.scale(scale: 0.8).combined(with: .opacity))
        case .settings:
            NotchSettingsView(vm: vm)
                .transition(.scale(scale: 0.8).combined(with: .opacity))
        }
    }
    .animation(vm.animation, value: vm.contentType)
}
```

`Spacer` 是后续组件插槽位。切换动画与外壳共用 `vm.animation` 同一弹簧，保证同频。

- [ ] **步骤 3：构建验证通过**

运行：`xcodebuild -project NotchDrop.xcodeproj -target NotchDrop -configuration Debug build`
预期：BUILD SUCCEEDED

- [ ] **步骤 4：Commit**

```bash
git add NotchDrop/NotchHeaderView.swift NotchDrop/NotchContentView.swift
git commit -m "feat: 顶栏胶囊分段与状态托盘内容切换"
```

---

### 任务 5：内卡片材质统一与全量验收

**文件：**
- 修改：`NotchDrop/TrayDrop+View.swift`（`panel` 的 `glassCard` → `obsidianCard`）
- 修改：`NotchDrop/QuotaCardView.swift`（`body` 的 `glassCard` → `obsidianCard`）
- 测试：构建 + 目视验收

- [ ] **步骤 1：托盘换黑曜石材质**

`TrayDrop+View.swift` 的 `panel` 里：

```swift
RoundedRectangle(cornerRadius: vm.cornerRadius)
    .fill(.clear)
    .obsidianCard(cornerRadius: vm.cornerRadius)
```

`vm.cornerRadius` 现值即 16（外壳 26 − 边距 10 = 16，同心法则对上，不改值）。

- [ ] **步骤 2：额度卡换黑曜石材质**

`QuotaCardView.swift` 的 `body` 里：

```swift
.padding(12)
.obsidianCard(cornerRadius: vm.cornerRadius)
```

额度卡视觉锁定（7pt 中环、三色阈值、虚线占位）一律不动，只换底。

- [ ] **步骤 3：全量构建**

运行：`xcodebuild -project NotchDrop.xcodeproj -target NotchDrop -configuration Debug build`
预期：BUILD SUCCEEDED，无新增 warning

- [ ] **步骤 4：目视验收（4 项全过才算完）**

1. 浅色壁纸下展开：外壳纯黑，无摄像头黑斑，无浅色透底
2. 展开形态：顶部贴边，两侧无翅膀，底部圆角光滑（200% 截图看无折点）
3. 点胶囊切 Tab：滑块跟随，内容右滑淡入，弹簧与外壳同频
4. 从访达拖文件触刘海：0.3s 内切到托盘，高亮 + 震动一次

- [ ] **步骤 5：Commit**

```bash
git add NotchDrop/TrayDrop+View.swift NotchDrop/QuotaCardView.swift
git commit -m "feat: 内卡片统一黑曜石材质"
```

---

## 自检

1. **规格覆盖度：** 黑曜石锁黑（任务 1、5）→ 去飞檐 32pt（任务 2）→ 顶部贴边 + 底部 26pt 连续（任务 2）→ 24pt 避让（任务 2 步骤 4）→ 同心圆角 16（任务 5，不改值）→ 双胶囊 Tab（任务 4）→ 右侧按钮保留（任务 4 未动）→ 拖拽切托盘 + 高亮震动（任务 3，高亮沿用托盘自带 targeting 描边）→ `PanelTab` 枚举 + 滑动淡入淡出（任务 3、4）。无遗漏。
2. **占位符扫描：** 无待定、无 TODO；数字全部有出处（0.88/0.12/0.8/6/26/24/10/16/180/196）；验证命令均为可直接运行的完整命令。
3. **类型一致性：** `NotchViewModel.PanelTab`（status/tray）→ `activeTab` → `tabButton(_ tab: NotchViewModel.PanelTab` → `vm.activeTab == .tray`，全链一致；`obsidian(in: S: Shape)` 被 `obsidianCard` 与 `NotchView` 两处以 `RoundedRectangle` / `NotchShellShape` 调用，泛型约束一致；`NotchShellShape(topMicroRadius:bottomRadius:)` 初始化参数与定义一致。
