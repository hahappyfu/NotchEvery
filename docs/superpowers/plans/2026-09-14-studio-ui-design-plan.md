# NotchEvery 工业级 / 产品级 UI 设计实现计划 (Apple Native Studio)

> **面向 AI 代理的工作者：** 必需子技能：使用 subagent-driven-development（推荐）或 executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 统一并全面升级 NotchEvery 的 UI 为 Apple Native Studio 现代工业级美学，贯穿灵动岛三页主面板、独立偏好设置大窗口以及测距校准向导弹窗。

**架构：** 在 `NotchDrop/DesignSystem.swift` 构建单一事实来源设计系统（材质、0.5pt 双层精密描边、状态色标、等宽排版与弹簧动效），并通过纯原生 SwiftUI ViewModifier 渐进注入各模块，无缝继承现有数据存储与尺寸保护机制。

**技术栈：** macOS 26 SDK, SwiftUI, AppKit, Swift 5.9+, XCTest

**规格：** [docs/superpowers/specs/2026-09-14-studio-ui-design.md](docs/superpowers/specs/2026-09-14-studio-ui-design.md)

## 全局约束

- 严格遵循 Apple Native Studio 视觉：深色磨砂亚克力、0.5pt 精密内外微光描边、精密 Bento 微卡片。
- 零额外第三方依赖：纯原生 SwiftUI ViewModifier 与 Shape，严控包体积与 GPU 损耗。
- 零功能衰减：保留所有 `@AppStorage`, `@PublishedPersist` 及 `ConfigStore` 现有键名与数据逻辑。
- 严控尺寸越界：所有灵动岛内部改动必须配合 `zoneSizeReporter()`，不得破坏现有 `ZoneSizeGuardTests`。
- 本地化优先：所有新增文案与状态标签必须完整适配中英双语。

---

### 任务 1：构建基础设计系统 (`DesignSystem.swift`)

**文件：**
- 创建：`NotchDrop/DesignSystem.swift`
- 测试：`Tests/DesignSystemTests.swift`

- [ ] **步骤 1：编写 DesignSystemTests 单元测试**

```swift
import XCTest
import SwiftUI
@testable import NotchEvery

final class DesignSystemTests: XCTestCase {
    func testStudioColorsExist() {
        XCTAssertNotNil(StudioColor.emerald)
        XCTAssertNotNil(StudioColor.amber)
        XCTAssertNotNil(StudioColor.rose)
        XCTAssertNotNil(StudioColor.indigo)
        XCTAssertNotNil(StudioColor.cyan)
    }

    func testStudioSpringTiming() {
        XCTAssertEqual(StudioAnimation.springResponse, 0.32, accuracy: 0.01)
        XCTAssertEqual(StudioAnimation.springDamping, 0.82, accuracy: 0.01)
    }
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：`swift test --filter DesignSystemTests`
预期：FAIL，找不到 `StudioColor` 与 `StudioAnimation`。

- [ ] **步骤 3：编写 DesignSystem.swift 实现代码**

```swift
//
//  DesignSystem.swift
//  NotchEvery
//
//  Apple Native Studio 工业级设计系统：材质、调色盘、微光边框与弹簧动效。
//

import SwiftUI

public enum StudioColor {
    public static let emerald = Color(red: 16/255, green: 185/255, blue: 129/255) // #10B981
    public static let amber   = Color(red: 245/255, green: 158/255, blue: 11/255)  // #F59E0B
    public static let rose    = Color(red: 244/255, green: 63/255, blue: 94/255)   // #F43F5E
    public static let indigo  = Color(red: 99/255, green: 102/255, blue: 241/255)  // #6366F1
    public static let cyan    = Color(red: 6/255, green: 182/255, blue: 212/255)   // #06B6D4
}

public enum StudioMaterial {
    public static let cardBackground = Color.white.opacity(0.05)
    public static let cardHoverBackground = Color.white.opacity(0.09)
    public static let cardSelectedBackground = Color.white.opacity(0.12)
    public static let strokeNormal = Color.white.opacity(0.10)
    public static let strokeHover = Color.white.opacity(0.24)
    public static let strokeActive = Color.white.opacity(0.35)
}

public enum StudioAnimation {
    public static let springResponse: Double = 0.32
    public static let springDamping: Double = 0.82
    public static var interactiveSpring: Animation {
        .spring(response: springResponse, dampingFraction: springDamping)
    }
}

public struct StudioCardModifier: ViewModifier {
    var radius: CGFloat
    var isHovered: Bool
    var isSelected: Bool

    public func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(isSelected ? StudioMaterial.cardSelectedBackground : (isHovered ? StudioMaterial.cardHoverBackground : StudioMaterial.cardBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        isSelected ? StudioMaterial.strokeActive : (isHovered ? StudioMaterial.strokeHover : StudioMaterial.strokeNormal),
                        lineWidth: 0.5
                    )
            )
    }
}

public extension View {
    func studioCard(radius: CGFloat = 10, isHovered: Bool = false, isSelected: Bool = false) -> some View {
        modifier(StudioCardModifier(radius: radius, isHovered: isHovered, isSelected: isSelected))
    }

    func studioPillBadge(color: Color) -> some View {
        self
            .font(.system(size: 10, weight: .medium).monospacedDigit())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.16), in: Capsule())
            .overlay(Capsule().strokeBorder(color.opacity(0.32), lineWidth: 0.5))
            .foregroundStyle(color)
    }
}
```

- [ ] **步骤 4：运行测试验证通过**

运行：`swift test --filter DesignSystemTests`
预期：PASS

- [ ] **步骤 5：Commit 基础设计系统**

```bash
git add NotchDrop/DesignSystem.swift Tests/DesignSystemTests.swift
git commit -m "feat(design): 建立 Apple Native Studio 基础设计系统与单元测试"
```

---

### 任务 2：重塑灵动岛第 1 页：配额与账号池仪表盘 (`AntigravityAccountsCardView.swift` & `TokenZoneView.swift`)

**文件：**
- 修改：`NotchDrop/AntigravityAccountsCardView.swift`
- 修改：`NotchDrop/TokenZoneView.swift`

- [ ] **步骤 1：为 AntigravityAccountsCardView 引入微型 Bento 与等宽倒计时芯片**

修改 `NotchDrop/AntigravityAccountsCardView.swift`：
1. 替换 `ringColor` 为 `StudioColor` 调色盘平滑映射。
2. 将 4 账号列包裹在 `.studioCard(radius: 8, isSelected: account.isCurrent)` 中，当前使用账号提供内敛微光。
3. 倒计时数字应用 `.monospacedDigit()` 与胶囊排版。

- [ ] **步骤 2：为 TokenZoneView 升级等宽数字与单像素卡片行质感**

修改 `NotchDrop/TokenZoneView.swift`：
1. 列表表头与数据行采用 `StudioMaterial.strokeNormal` 0.5pt 分隔线。
2. 耗时与 Token 统计数值全部采用 `.monospacedDigit()`。
3. 悬停行背景使用 `StudioMaterial.cardHoverBackground`。

- [ ] **步骤 3：验证编译与单测**

运行：`swift test --filter ZoneSizeGuardTests`
预期：PASS（尺寸测量保持稳定符合预期）

- [ ] **步骤 4：Commit 配额与仪表盘升级**

```bash
git add NotchDrop/AntigravityAccountsCardView.swift NotchDrop/TokenZoneView.swift
git commit -m "feat(ui): 升级第 1 页配额卡与用量仪表盘为 Studio Bento 风格"
```

---

### 任务 3：重塑灵动岛第 2 页：文件托盘空态与文件卡片浮起高光 (`TrayDrop+DropItemView.swift` & `TrayDropView.swift`)

**文件：**
- 修改：`NotchDrop/TrayDrop+DropItemView.swift`
- 修改：`NotchDrop/TrayDrop+View.swift`（或托盘主视图）

- [ ] **步骤 1：文件卡片升级 0.5pt 高光边框与 Lift Effect**

修改 `NotchDrop/TrayDrop+DropItemView.swift`：
1. `cardBackground` 迁移至 `studioCard(radius: 12, isHovered: hover)`，移除生硬白色描边。
2. 悬停 scale 配合 `StudioAnimation.interactiveSpring`，增加 1px 微发光阴影提升悬停手感。
3. 文件名增加 `.monospacedDigit()` 优化长文件名换行显示。

- [ ] **步骤 2：托盘空态与底栏微胶囊按钮**

修改托盘主视图：
1. 拖拽悬停引导框增加动态边框呼吸光泽。
2. 底栏清空与打包按钮采用 `.studioCard(radius: 6)` 胶囊微按钮。

- [ ] **步骤 3：验证编译与单测**

运行：`swift test`
预期：PASS

- [ ] **步骤 4：Commit 托盘视觉升级**

```bash
git add NotchDrop/TrayDrop+DropItemView.swift NotchDrop/TrayDrop+View.swift
git commit -m "feat(ui): 升级第 2 页文件托盘为 Studio 微光悬浮卡片"
```

---

### 任务 4：重塑灵动岛第 3 页：守护控制台雷达呼吸环与 2x2 交互卡片 (`GuardControlZoneView.swift`)

**文件：**
- 修改：`NotchDrop/GuardControlZoneView.swift`

- [ ] **步骤 1：状态 Header 引入雷达呼吸环**

在 `GuardControlZoneView.swift` 的 `header` 状态圆点外层增加 `Circle().stroke(pulseColor.opacity(pulseOpacity), lineWidth: 1.5)` 呼吸微动效，直观传达守护运行状态。

- [ ] **步骤 2：2x2 行为开关与步进器卡片化**

1. 将原生 `Toggle` 封装在 `.studioCard(radius: 10, isSelected: isOn)` 中，点击整个卡片区域即切换，并伴随 `StudioAnimation.interactiveSpring`。
2. 步进器升级为居中等宽数字 + 两侧微型 `[ - ]` `[ + ]` 胶囊按钮。
3. 底部“偏好设置”与“校准向导”入口改为双胶囊磨砂按钮。

- [ ] **步骤 3：验证编译与单测**

运行：`swift test --filter DiagTimelineTests`
预期：PASS

- [ ] **步骤 4：Commit 守护控制台升级**

```bash
git add NotchDrop/GuardControlZoneView.swift
git commit -m "feat(ui): 升级第 3 页守护控制台为 Studio 交互卡片与雷达呼吸环"
```

---

### 任务 5：重构独立偏好设置大窗口架构与侧边栏 (`PreferencesWindow.swift`)

**文件：**
- 修改：`NotchDrop/PreferencesWindow.swift`

- [ ] **步骤 1：重构左侧边栏 System Settings 质感**

在 `PreferencesWindow.swift` 中：
1. `PreferencesTab` 每个枚举项赋予专有彩色底板背景色（如通用灰色、解锁绿色、锁定橙色、通知红色、校准蓝色、诊断紫色）。
2. 侧边栏列表项采用彩色圆角小方块图标 + 选中流动胶囊底色。

- [ ] **步骤 2：定义统一 `StudioSectionGroup` 替换原生 Form**

实现卡片式分组容器 `StudioSectionGroup`：
```swift
struct StudioSectionGroup<Content: View>: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                content()
            }
            .studioCard(radius: 10)
        }
        .padding(.horizontal)
    }
}
```

- [ ] **步骤 3：重构通用、解锁、锁定 Tab 布局**

全面接入 `StudioSectionGroup`，行与行之间增加 0.5pt 分隔线，开关右对齐，带来如同 macOS Sequoia 系统偏好设置的利落感。

- [ ] **步骤 4：验证编译通过**

运行：`swift test`
预期：PASS

- [ ] **步骤 5：Commit 偏好设置架构升级**

```bash
git add NotchDrop/PreferencesWindow.swift
git commit -m "feat(ui): 升级独立偏好设置大窗口为 System Settings 现代卡片布局"
```

---

### 任务 6：精修诊断日志时序与测距校准向导 (`PreferencesWindow.swift` & `CalibrationWizardView.swift`)

**文件：**
- 修改：`NotchDrop/PreferencesWindow.swift`（Diagnostics Tab & Calibration Tab）
- 修改：`NotchDrop/CalibrationWizardView.swift`

- [ ] **步骤 1：诊断日志时序卡片与工具栏升级**

1. 诊断记录行改用微型时序小卡片，不同理由（近距/离开/防误触）打上 `StudioColor` 专属徽标。
2. 顶部工具栏胶囊化，增强搜索过滤与一键清理体验。

- [ ] **步骤 2：校准向导升级流线型步进器与雷达光晕**

修改 `NotchDrop/CalibrationWizardView.swift`：
1. 步骤数字（1 → 2 → 3）用平滑进度连线贯穿。
2. 测距雷达圆环在信号强时由 `StudioColor.cyan` 渐变为 `StudioColor.emerald`，采样过程进度圈增加平滑渐变呼吸。

- [ ] **步骤 3：验证编译与测试**

运行：`swift test`
预期：全部单元测试 PASS

- [ ] **步骤 4：Commit 诊断与向导精修**

```bash
git add NotchDrop/PreferencesWindow.swift NotchDrop/CalibrationWizardView.swift
git commit -m "feat(ui): 升级诊断日志时序卡片与校准向导雷达动效"
```

---

### 任务 7：全局回归验证与构建清理

**文件：**
- 检查：所有修改的视图与测试

- [ ] **步骤 1：运行全套单元测试**

运行：`swift test`
预期：PASS，所有现有单元测试与新增设计系统测试 100% 通过。

- [ ] **步骤 2：检查 git diff 确保无孤儿与残留调试代码**

运行：`git status`
预期：工作区干净，仅包含规划范围内的修改。

- [ ] **步骤 3：提交最终汇总记录**

```bash
git commit --allow-empty -m "chore(release): 完成 Apple Native Studio 全量工业级 UI 美化"
```
