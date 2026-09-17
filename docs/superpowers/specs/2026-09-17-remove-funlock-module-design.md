# 彻底移除 Funlock 模块并纯净化灵动岛 AI 感知看板设计规格说明

- **创建日期**：2026-09-17
- **分类**：架构级重构（Architectural Spec）
- **覆盖模块**：`NotchViewModel`, `NotchRootView`, `NotchView`, `PreferencesWindow`, `project.pbxproj`, 守护文件全量移除

---

## 1. 目标与背景

由于近场守护与自动锁屏模块（Funlock / Guard）在实际体验与使用场景中不够理想，决定将其彻底从 NotchEvery 代码库中卸载移除，不再合入主线。
本次重构将 NotchEvery 重新聚焦为纯粹、优雅的 **AI 代理监控与灵动岛工具**。

---

## 2. 详细改造规格

### 2.1 彻底删除 Funlock 相关源文件与测试

删除以下源文件及对应的 Xcode Target 引用：
1. `NotchDrop/FUn.swift`
2. `NotchDrop/FUnManager.swift`
3. `NotchDrop/FUnlockStateMachine.swift`
4. `NotchDrop/GuardStore.swift`
5. `NotchDrop/GuardControlZoneView.swift`
6. `NotchDrop/GuardCardView.swift`
7. `NotchDrop/GuardLocalization.swift`
8. `NotchDrop/DecisionLogger.swift`
9. `NotchDrop/CalibrationWizardView.swift`

删除以下单元测试文件及对应的测试 Target 引用：
1. `Tests/FUnlockTests.swift`
2. `Tests/FUnlockStateMachineTests.swift`
3. `Tests/FUnlockDeviceBindingTests.swift`
4. `Tests/GuardStoreTests.swift`
5. `Tests/GuardControlZoneViewTests.swift`
6. `Tests/DecisionLoggerTests.swift`

---

### 2.2 灵动岛核心架构回归双页制

1. **`NotchViewModel.swift` 分区重置**：
   - `ContentType` 枚举移除 `.diagnostics`，仅保留：
     ```swift
     enum ContentType: Int, Codable, Hashable, Equatable {
         case normal
         case token
     }
     ```
   - 分区顺序收敛为两页：
     ```swift
     static let zoneOrder: [ContentType] = [.normal, .token]
     ```
   - 相应更新分页指示器、页面滑动与快捷键切页。

2. **`NotchRootView.swift` 清理**：
   - 移除 `GuardControlZoneView` 与第三页视图分支；
   - 移除右耳守护设备/信号显示分支（`if vm.contentType == .diagnostics`）；
   - 移除对 `GuardStore` 的任何引用。

3. **`NotchView.swift` 初绽开（Peek 提示）感知重构**：
   - 移除对 `guardStore` 的依赖；
   - 右侧胶囊原蓝牙信号替换为 **AI 缓存命中率**：
     ```swift
     HStack(spacing: 4) {
         Text("⚡️ 缓存 \(formattedCacheRateText)")
             .font(.system(size: 11, weight: .medium))
             .foregroundStyle(StudioColor.cyan)
             .monospacedDigit()
     }
     ```
   - `formattedCacheRateText` 格式化为 `String(format: "%.1f%%", usage.cacheRateFraction * 100)`。

---

### 2.3 偏好设置窗口 (`PreferencesWindow.swift`) 纯净化

1. **移除 Guard 与 Diagnostics 设置 Tab**：
   - `PreferencesTab` 仅保留 `.general`（或者有需要可保留轻量关于页），移除 `guardSecurity` 与 `diagnostics`；
   - 移除 `GuardSettingsTab` 与 `DiagnosticsSettingsTab` 视图定义；
   - 侧边栏及详情页只保留「通用」设置（开机启动、触觉反馈、语言切换、数据源切换）。

---

## 3. 验收标准与测试保障

1. **工程与编译**：
   - `project.pbxproj` 干净无悬空引用；
   - 编译零警告、零报错（Debug & Release）。
2. **测试保障**：
   - 剩余全量测试（Token/Antigravity/Animations/TabMetrics 等）100% 绿灯通过；
3. **视觉与交互**：
   - 灵动岛仅呈现 2 页（概览 ↔ Token），指示器为 2 个点，滑动切页流畅；
   - 悬停初绽开呈现：`今日 xxM · xx次  |  ⚡️ 缓存 xx%`，纯净美观。
