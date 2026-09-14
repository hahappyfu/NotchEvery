# 守护控制台与独立偏好设置窗口实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 subagent-driven-development（推荐）或 executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 
1. 将刘海第三页从长列表时间线重构为精致紧凑的「守护控制台」（`GuardControlZoneView.swift`），提供常用开关、阈值快捷步进、精简判定卡与向导入口。
2. 创建独立偏好设置窗口（`PreferencesWindowController.swift`），集成 6 大侧边栏 Tab（通用、解锁、锁定、通知与告警、测距校准、完整日志），完整恢复原 FUnlock 的所有能力并与 NotchEvery 统一管理。

**架构：**
- `NotchDrop/GuardControlZoneView.swift`：第三页视图，固定 360pt，内边距 `horizontal: 18, vertical: 12`，绑定 `ConfigStore` 与 `GuardStore`。
- `NotchDrop/CalibrationWizardView.swift`：从 FUnlock 移植并适配 NotchEvery 的 5 步测距校准向导视图。
- `NotchDrop/PreferencesWindow.swift`：标准 macOS 侧边栏设置大窗口（NavigationSplitView），含 General/Unlock/Lock/Notification/Calibration/Diagnostics 6 大分区。
- `NotchDrop/PreferencesWindowController.swift`：NSWindowController 单例管理类，控制窗口居中与唤起。
- 装配：替换 `NotchRootView.swift` 中的第三页 `DiagZoneView` 为 `GuardControlZoneView`；更新右键菜单与第三页底部按钮调用 `PreferencesWindowController.shared.show()`。

**技术栈：** Swift 5.9, SwiftUI, AppKit, XCTest, macOS 13.0+ API。
**测试验证：** `xcodebuild test -project NotchDrop.xcodeproj -scheme NotchDrop -destination 'platform=macOS' -derivedDataPath /tmp/nDD CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO -only-testing:NotchEveryTests`

**规格文档：** `docs/superpowers/specs/2026-09-14-guard-control-and-preferences-window-design.md`

## 全局约束

- 严格遵守 macOS 13+ 约束，禁止使用 macOS 14+ 独占 API。
- 第三页视图宽度必须为 360pt，内边距 `horizontal: 18, vertical: 12`，背景采用 `Color.white.opacity(0.06)`，圆角 12pt。
- 配置项一律读取写入 `ConfigStore.shared.defaults`，保持与系统服务无缝同步。
- 严禁任何形式的占位符与死代码。

---

## 任务结构

### 任务 1：控制台与校准向导——GuardControlZoneView 与 CalibrationWizardView

**文件：**
- 创建：`NotchDrop/CalibrationWizardView.swift`
- 创建：`NotchDrop/GuardControlZoneView.swift`
- 修改：`NotchDrop/NotchRootView.swift`
- 修改：`NotchDrop.xcodeproj/project.pbxproj`

- [ ] **步骤 1：创建 CalibrationWizardView.swift**
从 FUnlock 移植并精简空间校准向导，支持 0 欢迎、1-2 靠近采样、3-4 离席采样、5 结果并自动写盘。

- [ ] **步骤 2：创建 GuardControlZoneView.swift**
实现 2×2 开关、解锁与锁定 RSSI 步进滑块、最近 1~2 条判定精简卡片、启动校准按钮与打开设置按钮。

- [ ] **步骤 3：在 NotchRootView.swift 中接入 GuardControlZoneView**
将 `case .diagnostics: DiagZoneView()` 替换为 `GuardControlZoneView(vm: vm)`，并更新耳区显示文案。

- [ ] **步骤 4：在 project.pbxproj 中注册新建文件并运行单测验证**
运行：`xcodebuild test ... -only-testing:NotchEveryTests`，确保 401 个测试全部绿灯。

- [ ] **步骤 5：Commit**
`git commit -m "feat(guard): 实现第三页守护控制台与测距校准向导"`

---

### 任务 2：独立设置大窗口——PreferencesWindow 与 PreferencesWindowController

**文件：**
- 创建：`NotchDrop/PreferencesWindow.swift`
- 创建：`NotchDrop/PreferencesWindowController.swift`
- 修改：`NotchDrop/NotchMenuView.swift`
- 修改：`NotchDrop/GuardControlZoneView.swift`
- 修改：`NotchDrop.xcodeproj/project.pbxproj`

- [ ] **步骤 1：创建 PreferencesWindow.swift**
实现侧边栏 NavigationSplitView，承载通用、解锁、锁定、通知、校准、日志 6 大 Tab。

- [ ] **步骤 2：创建 PreferencesWindowController.swift**
实现窗口单例控制器，尺寸 680×460，窗口居中且前置。

- [ ] **步骤 3：在右键菜单与第三页底部接线**
点击设置按钮弹出独立窗口，并收起刘海面板。

- [ ] **步骤 4：注册 Xcode 工程、编译与全量测试验证**
运行：`xcodebuild test ...` 确认 100% 通过。

- [ ] **步骤 5：Commit**
`git commit -m "feat(settings): 实现独立侧边栏偏好设置大窗口"`

---

### 任务 3：清理废弃代码、本地 Release 构建与真机验收

**文件：**
- 删除：`NotchDrop/DiagZoneView.swift`
- 修改：`NotchDrop.xcodeproj/project.pbxproj`

- [ ] **步骤 1：删除原 DiagZoneView.swift 并清理工程引用**
- [ ] **步骤 2：全量单测回归与 Release 构建**
- [ ] **步骤 3：安装替换 /Applications/NotchEvery.app 并重启应用**
- [ ] **步骤 4：Commit**
`git commit -m "chore(cleanup): 移除旧诊断长列表视图并完成第二期构建"`
