# 彻底移除 Funlock 模块并纯净化灵动岛 AI 感知看板实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 subagent-driven-development（推荐）或 executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 彻底卸载移除近场守护与自动锁屏模块（Funlock / Guard / DecisionLogger），灵动岛回归经典双页（概览 ↔ Token），初绽开右侧改造为 AI 缓存命中率，清理偏好设置窗口并维护工程与测试完全绿灯。

**架构：** 在 `NotchViewModel` 中将分区枚举收敛为 `.normal` 与 `.token` 双页；在 `NotchRootView` 与 `NotchView` 中移除守护视图分支，重构悬停 Peek 提示为 Token + 缓存命中率；在 `PreferencesWindow` 移除守护相关 Tab；彻底物理删除 Funlock 9 个源码文件与 6 个单测文件，同步清理 Xcode 工程配置。

**技术栈：** Swift 5.9+, SwiftUI, Xcode Project (`project.pbxproj`), XCTest

**规格：** `docs/superpowers/specs/2026-09-17-remove-funlock-module-design.md`

## 全局约束

- 测试运行命令必须带签名绕过参数：
  `xcodebuild test -project NotchDrop.xcodeproj -scheme NotchDrop -destination 'platform=macOS' -derivedDataPath /tmp/nDD CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO`
- 灵动岛只保留 2 个 Tab：`[.normal, .token]`
- 悬停 Peek 提示格式：`今日 {tokens} · {calls} | ⚡️ 缓存 {rate}%`
- 遵循 Karpathy 准则：彻底清理孤儿文件与引用，不遗留悬空代码。

---

### 任务 1：从灵动岛核心视图与 ViewModel 中剥离 Funlock 引用

**文件：**
- 修改：`NotchDrop/NotchViewModel.swift:150-165, 320-335`
- 修改：`NotchDrop/NotchRootView.swift:105-180`
- 修改：`NotchDrop/NotchView.swift:10-25, 190-255`
- 测试：`Tests/TabMetricsTests.swift`

- [ ] **步骤 1：更新 `Tests/TabMetricsTests.swift` 移除对 diagnostics 的断言**
调整 `TabMetricsTests.swift` 中关于 `ContentType` 数量（由 3 变为 2）及映射关系。

- [ ] **步骤 2：更新 `NotchViewModel.swift` 恢复纯净双页**
移除 `ContentType.diagnostics`，`zoneOrder` 改为 `[.normal, .token]`。

- [ ] **步骤 3：更新 `NotchRootView.swift` 移除守护视图与耳区**
移除 `GuardControlZoneView` 分支，移除右耳守护设备判定。

- [ ] **步骤 4：更新 `NotchView.swift` 重构 Peek 提示**
移除 `guardStore` 依赖，将右侧胶囊改造成 `⚡️ 缓存 \(formattedCacheRateText)`。

- [ ] **步骤 5：运行测试验证通过**
运行：`xcodebuild test -project NotchDrop.xcodeproj -scheme NotchDrop -destination 'platform=macOS' -derivedDataPath /tmp/nDD -only-testing:NotchEveryTests/TabMetricsTests CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO`

- [ ] **步骤 6：提交代码**
`git commit -am "refactor(island): 灵动岛收敛为双页制并将初绽开右侧改造成缓存命中率"`

---

### 任务 2：重组与纯净化 PreferencesWindow 偏好设置

**文件：**
- 修改：`NotchDrop/PreferencesWindow.swift`

- [ ] **步骤 1：清理 `PreferencesTab` 与相关视图**
移除 `.guardSecurity` 和 `.diagnostics` 枚举项，移除 `GuardSettingsTab`、`DiagnosticsSettingsTab`、`CalibrationWizardView` 引用。

- [ ] **步骤 2：保留优雅纯粹的「通用」设置**
确保开机自启、触觉反馈、语言设置等核心选项完整可用。

- [ ] **步骤 3：提交代码**
`git commit -am "refactor(settings): 偏好设置窗口移除守护与诊断 Tab"`

---

### 任务 3：物理删除 Funlock 源码与单测，清理 project.pbxproj

**文件：**
- 删除：`NotchDrop/FUn.swift`, `NotchDrop/FUnManager.swift`, `NotchDrop/FUnlockStateMachine.swift`, `NotchDrop/GuardStore.swift`, `NotchDrop/GuardControlZoneView.swift`, `NotchDrop/GuardCardView.swift`, `NotchDrop/GuardLocalization.swift`, `NotchDrop/DecisionLogger.swift`, `NotchDrop/CalibrationWizardView.swift`
- 删除：`Tests/FUnlockTests.swift`, `Tests/FUnlockStateMachineTests.swift`, `Tests/FUnlockDeviceBindingTests.swift`, `Tests/GuardStoreTests.swift`, `Tests/GuardControlZoneViewTests.swift`, `Tests/DecisionLoggerTests.swift`
- 修改：`NotchDrop.xcodeproj/project.pbxproj`

- [ ] **步骤 1：git rm 物理删除上述 15 个文件**
- [ ] **步骤 2：从 `NotchDrop.xcodeproj/project.pbxproj` 移除所有被删文件的 PBXBuildFile 和 PBXFileReference 引用**
- [ ] **步骤 3：验证工程构建无遗漏**
- [ ] **步骤 4：提交代码**
`git commit -am "chore: 彻底删除 Funlock 模块所有源码、测试与工程引用"`

---

### 任务 4：全量验证、测试确认与重新部署

- [ ] **步骤 1：运行全量保留测试套件**
- [ ] **步骤 2：编译并在 `/Applications/NotchEvery.app` 启动最新版本供用户过目**
