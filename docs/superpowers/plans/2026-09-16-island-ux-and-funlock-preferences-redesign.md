# 灵动岛感知重构、动画排卡、第三页排版重塑与 FUnlock 偏好体系实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 subagent-driven-development（推荐）或 executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 解决初绽开裸数字可读性差、开合/切页动画卡顿、第三页尺寸跳变截断，以及重构偏好设置窗口并补全 FUnlock 遗漏的蓝牙设备扫描配对功能。

**架构：**
- 初绽开：新增 `TokenFormatUtils` 将裸数字转为紧凑 M/k 人类易读单位，构建左反代看板、右守护感知的双模态胶囊；
- 动画治理：清除多重动画闭包嵌套，移除后台/常驻的 `repeatForever` 循环，并将 RSSI 高频广播隔离为局部游标刷新；
- 第三页重塑：宽度统一为 520pt 对齐概览页，横向舒展 2×2 开关与空间测距轨道，总高收敛防截断；
- 偏好设置：收拢右键重复菜单，提纯 3 大核心 Tab（通用、近场守护、安全日志），全面补齐蓝牙设备发现与绑定列表。

**技术栈：** Swift 5.9+, SwiftUI, AppKit, CoreBluetooth, XCTest

**规格：** `docs/superpowers/specs/2026-09-16-island-ux-and-funlock-preferences-redesign.md`

## 全局约束
- 部署目标：macOS 13.0
- 视觉与设计系统：沿用 `StudioColor`, `StudioMaterial`, `studioCard` 修饰符
- 编码规范：简单直接（Karpathy / Ponytail），严禁无测试直接声明成功
- 验证基准：每次修改必须通过 `swift test`，且代码可顺利 release 构建

---

### 任务 1：初绽开（Peek）数据格式化与双模态感知重构

**文件：**
- 创建：`NotchDrop/TokenFormatUtils.swift`
- 修改：`NotchDrop/NotchView.swift:201-213`
- 修改：`NotchDrop/NotchViewModel.swift:256-270`
- 测试：`Tests/TokenFormatUtilsTests.swift`

- [ ] **步骤 1：编写 Token 与请求数紧凑格式化的失败测试**

```swift
import XCTest
@testable import NotchDrop

final class TokenFormatUtilsTests: XCTestCase {
    func testFormatCompactTokens() {
        XCTAssertEqual(TokenFormatUtils.formatTokens(0), "0 Tokens")
        XCTAssertEqual(TokenFormatUtils.formatTokens(999), "999 Tokens")
        XCTAssertEqual(TokenFormatUtils.formatTokens(1_200), "1.2k Tokens")
        XCTAssertEqual(TokenFormatUtils.formatTokens(70_494_437), "70.5M Tokens")
        XCTAssertEqual(TokenFormatUtils.formatTokens(1_000_000_000), "1.0B Tokens")
    }

    func testFormatCompactCount() {
        XCTAssertEqual(TokenFormatUtils.formatCount(0), "0")
        XCTAssertEqual(TokenFormatUtils.formatCount(89), "89")
        XCTAssertEqual(TokenFormatUtils.formatCount(2_412), "2.4k")
    }
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：`swift test --filter TokenFormatUtilsTests`
预期：FAIL，找不到 `TokenFormatUtils`

- [ ] **步骤 3：编写 TokenFormatUtils 纯函数实现**

```swift
// NotchDrop/TokenFormatUtils.swift
import Foundation

public enum TokenFormatUtils {
    public static func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000_000 {
            return String(format: "%.1fB Tokens", Double(count) / 1_000_000_000.0)
        } else if count >= 1_000_000 {
            return String(format: "%.1fM Tokens", Double(count) / 1_000_000.0)
        } else if count >= 1_000 {
            return String(format: "%.1fk Tokens", Double(count) / 1_000.0)
        } else {
            return "\(count) Tokens"
        }
    }

    public static func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000.0)
        } else if count >= 1_000 {
            return String(format: "%.1fk", Double(count) / 1_000.0)
        } else {
            return "\(count)"
        }
    }
}
```

- [ ] **步骤 4：重构 NotchView.peekHint 双模态布局并移除菊花旋转**

在 `NotchDrop/NotchView.swift` 中：
1. 替换 `peekHint` 为双模态视图（左反代用量，右守护状态）：
```swift
    private var peekHint: some View {
        HStack(spacing: 8) {
            // 左侧：Antigravity 反代核心看板
            HStack(spacing: 5) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                let tokensStr = TokenFormatUtils.formatTokens(usage.summary.totalTokensRaw)
                let callsStr = TokenFormatUtils.formatCount(usage.summary.callsRaw)
                Text("今日 \(tokensStr) · \(callsStr) 请求")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.90))
                    .monospacedDigit()
            }

            Rectangle()
                .fill(Color.white.opacity(0.18))
                .frame(width: 1, height: 10)

            // 右侧：近场守护感知
            HStack(spacing: 5) {
                if GuardStore.shared.enabled {
                    if let rssi = GuardStore.shared.rssi {
                        Text("⌚️ \(rssi)dBm · 安全")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(StudioColor.emerald)
                    } else {
                        Text("⌚️ 搜寻中")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.white.opacity(0.55))
                    }
                } else {
                    Text("🛡️ 空跑")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.45))
                }
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 4)
    }
```
2. 在 `NotchViewModel.swift` 的 `openFromGhost()` 中移除 `bridgeSpinning = true` 及延迟重置，消灭展开时的菊花离屏渲染。

- [ ] **步骤 5：运行测试验证通过**

运行：`swift test --filter TokenFormatUtilsTests`
预期：PASS

- [ ] **步骤 6：Commit 任务 1**

```bash
git add NotchDrop/TokenFormatUtils.swift NotchDrop/NotchView.swift NotchDrop/NotchViewModel.swift Tests/TokenFormatUtilsTests.swift
git commit -m "feat(peek): 初绽开双模态感知重构与 Token 紧凑格式化"
```

---

### 任务 2：主副动画链路去重与高频重绘隔离（消灭卡顿）

**文件：**
- 修改：`NotchDrop/NotchView.swift:126-128, 195-200`
- 修改：`NotchDrop/GuardControlZoneView.swift:51-55, 164-185, 295-318`

- [ ] **步骤 1：梳理并收敛 NotchView 动画主驱动**

1. 检查 `NotchView.swift`：
   - 移除外层 `ZStack` 上的 `.animation(..., value: vm.status)`；
   - 仅保留 `islandSize` 上的过渡期动画：
```swift
.animation(reduceMotion ? nil : (vm.transitionActive ? (vm.status == .opened ? vm.openAnimation : vm.closeAnimation) : nil), value: islandSize)
```
2. 确保切页、开合各自独立，绝不发生两层以上 `interactiveSpring` 叠加。

- [ ] **步骤 2：停用 repeatForever 循环呼吸与高频全树重绘**

1. 在 `GuardControlZoneView.swift` 中：
   - 彻底移除 `startPulseAnimation` / `stopPulseAnimation` 里的 `repeatForever` 循环（常驻动画严重耗电并拉低全局 FPS）。
   - 将指示灯改为柔和的稳态点亮 + 状态色彩绑定。
2. 将 `GuardSignalRangeSlider` 内的 `spatialTrackView` 实时游标指针抽离为独立的轻量观察 Subview：
   - 当 `store.rssi` 频繁跳动时，仅让游标指针和头部 dBm 文本做轻量刷新，绝不触发整个 `GuardControlZoneView` 的重新计算。

- [ ] **步骤 3：全量编译并执行测试套件**

运行：`swift test`
预期：所有现有测试通过，无编译警告

- [ ] **步骤 4：Commit 任务 2**

```bash
git add NotchDrop/NotchView.swift NotchDrop/GuardControlZoneView.swift
git commit -m "perf(animation): 收敛单主动画驱动并剥离高频重绘消灭卡顿"
```

---

### 任务 3：第三页（GuardControlZoneView）520pt 等宽重塑与高度收敛

**文件：**
- 修改：`NotchDrop/GuardControlZoneView.swift:20-35, 61-75`
- 测试：`Tests/GuardControlZoneViewTests.swift`

- [ ] **步骤 1：编写 520pt 布局参数验证测试**

在 `Tests/GuardControlZoneViewTests.swift` 中新增测试：
```swift
func testPreferredWidthIs520() {
    XCTAssertEqual(GuardControlLayout.preferredWidth, 520, "第三页宽度必须与第一页 520pt 等宽对齐")
    XCTAssertGreaterThan(GuardControlLayout.toggleColumnWidth, 230, "开关卡片单列可用宽度必须大于 230pt 保证排版舒展")
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：`swift test --filter testPreferredWidthIs520`
预期：FAIL，当前为 390pt

- [ ] **步骤 3：重塑 GuardControlZoneView 尺寸与垂直排版**

1. 修改 `GuardControlLayout`：
```swift
enum GuardControlLayout {
    static let preferredWidth: CGFloat = 520
    static let horizontalPadding: CGFloat = 16
    static let verticalPadding: CGFloat = 10
    static let toggleGridSpacing: CGFloat = 10
    static let toggleCardFontSize: CGFloat = 12
    static let judgementDetailLineLimit: Int = 2

    static var toggleColumnWidth: CGFloat {
        let available = preferredWidth - (horizontalPadding * 2) - toggleGridSpacing
        return available / 2
    }
}
```
2. 优化各 Section 垂直堆叠间距（`spacing: 8`），将整个容器最大自然高度控制在 310pt，杜绝触底裁剪。
3. 让 `GuardSignalRangeSlider` 在 520pt 宽度下充分展开，双滑块操控轨道更加舒展。

- [ ] **步骤 4：运行测试验证通过**

运行：`swift test --filter testPreferredWidthIs520`
预期：PASS

- [ ] **步骤 5：Commit 任务 3**

```bash
git add NotchDrop/GuardControlZoneView.swift Tests/GuardControlZoneViewTests.swift
git commit -m "feat(ui): 第三页守护控制台等宽 520pt 重构并收敛高度防溢出"
```

---

### 任务 4：完整 FUnlock 偏好设置体系重构（补全设备配对 + 3 Tab 架构）

**文件：**
- 修改：`NotchDrop/NotchRootView.swift:32-42`
- 修改：`NotchDrop/NotchMenuView.swift:10-25`
- 重构：`NotchDrop/PreferencesWindow.swift`
- 修改：`NotchDrop/FUnManager.swift`（若需暴露更友好的设备绑定辅助方法）
- 测试：`Tests/FUnlockDeviceBindingTests.swift`

- [ ] **步骤 1：清理右键冗余表单，恢复轻量菜单定位**

在 `NotchRootView.swift` 中：
- popover 内仅保留纯净的 `NotchMenuView(vm: vm)` 与版本号，移除重复嵌入的 `NotchSettingsView`。

- [ ] **步骤 2：编写设备扫描与绑定逻辑的单元测试**

```swift
import XCTest
@testable import NotchDrop

final class FUnlockDeviceBindingTests: XCTestCase {
    func testDeviceBindingUpdatesMonitoredDevice() {
        let fun = FUn()
        let manager = FUnManager(fun: fun)
        let testUUID = UUID()
        manager.bindDevice(uuid: testUUID, name: "Apple Watch of Test")
        XCTAssertEqual(manager.monitoredDeviceName, "Apple Watch of Test")
    }
}
```

- [ ] **步骤 3：在 FUnManager 中完善设备绑定接口**

在 `FUnManager.swift` 中添加：
```swift
func bindDevice(uuid: UUID, name: String) {
    monitoredDeviceName = name
    ConfigStore.shared.set(uuid.uuidString, forKey: "monitoredDeviceUUID")
    ConfigStore.shared.set(name, forKey: "monitoredDeviceName")
    startMonitor(uuid: uuid)
}

func unbindDevice() {
    monitoredDeviceName = nil
    ConfigStore.shared.set("", forKey: "monitoredDeviceUUID")
    ConfigStore.shared.set("", forKey: "monitoredDeviceName")
    fun.stopScanning()
}
```

- [ ] **步骤 4：全面重构 PreferencesWindow 为三大核心 Tab 并落地设备绑定 UI**

在 `PreferencesWindow.swift` 中：
1. 枚举收拢为 3 个 Tab：
```swift
enum PreferencesTab: String, CaseIterable, Identifiable {
    case general = "通用"
    case guardSecurity = "近场守护"
    case diagnostics = "安全与日志"
}
```
2. 在 `guardSecurity`（近场守护）页面的第一块，补齐 **设备管理卡片**：
   - 显示当前绑定的设备名（如“Apple Watch Series 9”）、信号、解绑按钮；
   - 若未绑定或想切换，展示“扫描附近设备”列表，列出周围可用的 BLE 设备并支持一键配对；
   - 依次展示“核心模式与钥匙串密码”、“空间距离与阈值滑块”、“动作策略与防误锁”。
3. 在 `diagnostics`（安全与日志）页面中整合 iMessage 远程告警与决策审计流水线。

- [ ] **步骤 5：运行测试验证通过**

运行：`swift test --filter FUnlockDeviceBindingTests`
预期：PASS

- [ ] **步骤 6：Commit 任务 4**

```bash
git add NotchDrop/NotchRootView.swift NotchDrop/PreferencesWindow.swift NotchDrop/FUnManager.swift Tests/FUnlockDeviceBindingTests.swift
git commit -m "feat(settings): 偏好设置三大 Tab 重组并补齐 FUnlock 蓝牙设备配对体系"
```

---

### 任务 5：全量集成验证与真机交付

**文件：** 全部变更文件

- [ ] **步骤 1：运行全量单元测试套件**

运行：`swift test`
预期：所有测试 0 失败通过

- [ ] **步骤 2：Release 编译与安装**

运行：
```bash
./build-and-install.sh
```
预期：Release build 成功并重启应用生效

- [ ] **步骤 3：请用户真机过目验收**

引导用户实机体验：
1. 鼠标悬停刘海查看初绽开双模态可读性；
2. 体验展开、收起与横向切页动画的丝滑度；
3. 滑动至第三页检查 520pt 舒展排版与有无截断；
4. 右键打开偏好设置，检查全新三大 Tab 及蓝牙设备扫描配对功能。
