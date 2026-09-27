# FUnlock 架构摸底报告

> 目的：为「把 FUnlock 的功能并入另一个 app」做前期调研。本文只陈述事实与边界，不含产品建议与实现方案。
> 调研对象：`/Users/fupingguo/fuhaha_workspace/FUnlock/`（Swift / macOS / `FUnlock.xcodeproj`）
> 调研方式：只读源码，未修改 FUnlock 任何文件。
> 行号约定：全部为 `wc -l` 得到的行数；行号引用格式 `文件:行`。凡属推断而非直接证据的结论，均显式标注「推测」。

---

## 0. 全局事实

| 项 | 值 | 证据 |
|---|---|---|
| 主 target 源码 | 41 个 `.swift`，合计 **9270 行**（`FUnlock/` 目录，不含 C/ObjC 与 Bridging Header） | `wc -l FUnlock/*.swift` |
| 另有 C/ObjC | `lowlevel.c` 103 行、`lowlevel.h` 9 行、`main.m` 5 行、`MediaRemote.h` 10 行、`FUnlock-Bridging-Header.h` 6 行 | 各文件 |
| 第二个 target | `Launcher`（ObjC，开机自启 helper，非 Swift） | `Launcher/AppDelegate.m` 29 行 |
| 测试 target | `FUnlockTests`，9 个文件，**4902 行**（`FUnlockTests.swift` 单文件 3776 行） | `wc -l FUnlockTests/*.swift` |
| 第三方依赖 | 无（纯系统框架；`package.json` 只有 commitlint/husky 工具链） | `package.json:1-31`；`docs/architecture.md` 亦声明「无第三方库」 |
| 部署目标 | macOS 13.0；`SWIFT_VERSION = 5.0`；`ENABLE_HARDENED_RUNTIME = YES` | `FUnlock.xcodeproj/project.pbxproj:703,622,611` |
| 沙盒 | **未开启沙盒**（pbxproj 中无 `ENABLE_APP_SANDBOX`，entitlements 里无 `com.apple.security.app-sandbox`） | `FUnlock/FUnlock.entitlements:4-7`；`grep SANDBOX project.pbxproj` 无命中 |
| Bundle ID | Release `com.fuhahah.FUnlock`，Debug `com.fuhahah.FUnlock-dev` | `project.pbxproj:818,787` |
| 应用形态 | 菜单栏（agent）应用：`LSUIElement = true` | `FUnlock/Info.plist:27-28` |
| 版本 | 2.8.37 (1343) | `FUnlock/Info.plist:19-22` |
| 本地化 | 8 个 `.lproj`：Base/zh-Hans 各 334 键，ja/de/sv/nb/da/tr 各 281 键 | `FUnlock/*.lproj/Localizable.strings` |

**README 与代码不一致的两处**（供访谈时以代码为准）：

1. README:105 称密码以 `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` 存储；代码实际是 `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`（`FUnlock/SecurityService.swift:36`）。
2. README:244 称测试宿主跳过蓝牙扫描；实际跳过逻辑是 `applicationDidFinishLaunching` 里检测 `XCTestConfigurationFilePath`（`FUnlock/AppDelegate.swift:429`），测试**仍会构造 `FUn`（含 `CBCentralManager`）**（`FUnlockTests/FUnlockTests.swift:898-899`）。

---

## 1. 模块清单

分类口径：
- **A 纯逻辑**：不 import AppKit/Cocoa/SwiftUI 的文件（含只 import Foundation/Combine/系统框架）。
- **B 逻辑但触 AppKit**：非视图代码，但 import Cocoa/SwiftUI 或调用 NSApp/NSAlert/NSWorkspace。
- **C UI 视图/入口**：SwiftUI `View`、菜单栏、窗口、权限引导视图。

### A. 纯逻辑（3504 行）

| 文件 | 行数 | 职责 | 关键类型/函数 | 依赖的系统框架 |
|---|---|---|---|---|
| `FUn.swift` | 1200 | CoreBluetooth 驱动：扫描/连接/读 RSSI、在场与离场判定、锁定时器、心跳、信号超时 | `FUn`（`CBCentralManagerDelegate, CBPeripheralDelegate, ObservableObject`，:128）、`Device`（:53）、`protocol FUnDelegate`（:118） | CoreBluetooth、Combine、os |
| `FUnManager.swift` | 929 | 决策编排层：屏幕/系统事件入口、解锁全流程门控、手动锁保护、冷却/缓冲、更新接线 | `FUnManager`（`@MainActor final class ... ObservableObject`，:88-89）、`ScreenState`（:12）、`LockIntent`（:43）、`LockScreenState`（:63） | Foundation、Combine、**Cocoa**（见 B 类说明） |
| `DecisionLogger.swift` | 334 | 决策事件结构化记录：内存环形缓冲 500 + JSONL 落盘 + 同因合并 + 1MB 轮转 | `DecisionLogger`（:107）、`DecisionEvent`（:78）、`DecisionReason`（:19）、`ActionHint`（:60） | Foundation、Combine |
| `appleDeviceNames.swift` | 221 | Apple 设备型号标识 → 可读名的静态映射表 | `appleDeviceNames: [String:String]`（:1） | 无 |
| `iMessageNotifier.swift` | 193 | 解锁/锁屏事件经 `/usr/bin/osascript` 发 iMessage；30s 按类型防抖；错误码中文化 | `iMessageNotifier`（:7）、`parseScriptError`（:159）、`friendlyError`（:184） | Foundation（子进程） |
| `TelemetryLogger.swift` | 186 | 解锁/锁屏/异常事件写 CSV（`shadow_telemetry.csv`），5MB 熔断 | `TelemetryLogger`（:31）、`TelemetryEvent`（:7） | Foundation |
| `SignalPipeline.swift` | 178 | 信号处理管线：IQR 异常检测 + EWLR 斜率 + 非对称 Kalman + 时间衰减；含线程锁 | `SignalPipeline`（:31）、`SignalDecision`（:19）、`UnfairLock`（:5）、`SignalSource`（:27） | Foundation |
| `FUnlockStateMachine.swift` | 158 | 解锁防抖/降级状态机（Actor 语义，实为 `@MainActor class`） | `FUnlockStateMachine`（:6）、`State`（:10） | Foundation、UserNotifications |
| `ProfileManager.swift` | 130 | 多配置文件 CRUD + JSON 导入导出，持久化到 ConfigStore | `ProfileManager`（:13）、`Profile`（:3） | Foundation |
| `checkUpdate.swift` | 92 | 24h 轮询 GitHub Releases API，semver 比较，发本地通知 | `UpdateChecker`（:3） | Foundation、UserNotifications |
| `QuotaService.swift` | 117 | 读 `~/.clawd/opencode-go-bridge-cache.json` 归一化为套餐余量快照，30s 轮询 | `QuotaService`（:71）、`QuotaSnapshot`（:17） | Foundation、Combine |
| `UpdateDownloader.swift` | 125 | 下载 GitHub Release zip、解压、校验 Bundle ID | `UpdateDownloader`（:3）、`State`（:4） | Foundation（URLSession、unzip 子进程） |
| `LEDeviceInfo.swift` | 96 | 用 SQLite 查 `/Library/Bluetooth/*.db` 把 CBUUID 解析成 MAC/设备名 | `getLEDeviceInfoFromUUID`（:93） | SQLite3 |
| `SignalDataStore.swift` | 83 | 信号采样环形缓冲（容量 300）+ 1s 节流发布给 UI | `SignalDataStore`（:20）、`SignalSample`（:8） | Foundation、Combine |
| `ConfigStore.swift` | 76 | 独立 UserDefaults suite `com.fuhahah.Funlock.config` + 一次性迁移 | `ConfigStore`（:7）、`legacyKeys`（:65-75） | Foundation |
| `IMMessageComposer.swift` | 79 | 纯函数：事件 → 本地化文案；收件人规范化 | `IMMessageComposer`（:14）、`IMEvent`（:8） | Foundation |
| `RingBuffer.swift` | 56 | 定容环形缓冲泛型 | `RingBuffer<T>`（:6） | Foundation |
| `DebugLog.swift` | 50 | 文件日志 `~/Library/Logs/FUnlock/debug.log`（异步队列） | `DebugLog`（:8）、`logDebug`（:4） | Foundation |
| `WiFiMonitor.swift` | 14 | 读当前 Wi-Fi SSID | `WiFiMonitor`（:4） | CoreWLAN |
| `Log.swift` | 12 | os.log 三个 category | `Log.sm/.ble/.dev`（:9-11） | os |

小计 **3504 行**。

### B. 逻辑层但触 AppKit（1851 行）

| 文件 | 行数 | 职责 | 触 AppKit 的证据 |
|---|---|---|---|
| `SystemInteractionService.swift` | 523 | 唯一系统副作用出口：锁屏/唤醒/键鼠注入/媒体控制/通知/告警弹窗 | `import Cocoa`（:2）；`NSWorkspace.shared.frontmostApplication`（:48）、`NSAlert`（:478,500,515）、`NSApp.activate`（:485,507,521）、`NSWorkspace.shared.open`（:495） |
| `SecurityService.swift` | 175 | Keychain 存取密码 + 弹窗输入/改密提示 | `import Cocoa`（:2）；`NSAlert`（:112,128）、`NSSecureTextField`（:134）、`NSApp.activate`（:119,137,156） |
| `FUnManager.swift` | 929 | 同 A 类表（此文件同时具备 A/B 属性） | `import Cocoa`（:7）；`NSApp.setActivationPolicy(.regular/.accessory)`（:282,293）、`NSWorkspace.shared.frontmostApplication`（:657） |
| `UpdateInstaller.swift` | 127 | codesign 校验 + TeamID 比对 + bash 安装脚本 + 退出应用 | `import Cocoa`（:1）；`NSApplication.shared.terminate`（:83） |
| `FUnlockUtils.swift` | 97 | 本地化 `t()`、时序埋点、设备图标名、`DecisionEvent` 的 UI 图标/颜色映射 | `import SwiftUI`（:2）；`Color`（:71-80） |

> 说明：`FUnManager.swift` 在 A/B 两处都列出，为避免重复计数，**小计 1851 行**按上表 5 行相加（523+175+127+97 = 922，加上 FUnManager 的 929 共 1851）。A+B 合计 5355 行。

### C. UI 视图与入口（3915 行）

| 文件 | 行数 | 职责 | 关键类型 |
|---|---|---|---|
| `AppDelegate.swift` | 682 | 应用入口：菜单栏图标、NSPopover、设置窗口、全局快捷键、系统通知订阅、权限引导、输入活动监听 | `AppDelegate`（:166）、`InputActivityMonitor`（:21）、`PermissionCheckView`（:104） |
| `OverviewView.swift` | 495 | 总览页：信号盘、阈值滑块/微调、设备搜索与绑定、快捷操作 | `OverviewView`（:7）、`RSSIRange`（:35） |
| `StatsView.swift` | 436 | 统计页：今日/本周计数、信号曲线与斜率曲线（Swift Charts） | `StatsView`（:16）、`StatsCalculator`（:421）、`SignalChartView`（:240） |
| `MenuBarPopover.swift` | 404 | 菜单栏弹出面板：状态卡、信号格、开关、快捷动作、更新状态 | `MenuBarPopoverView`（:9）、`MenuBarAction`（:397） |
| `CalibrationWizardView.swift` | 391 | 阈值校准向导（6 步状态机采样） | `CalibrationWizardView`（:6） |
| `DiagnosticsView.swift` | 340 | 诊断页：决策时间线（按日期分组）+ 过滤器 + 操作建议按钮 + 导出 | `DiagnosticsView`（:20）、`DecisionCategory.filterKey`（:8-18） |
| `MainWindowView.swift` | 244 | 主窗口骨架：`NavigationSplitView` + 7 个 Tab + sheet 管理 + 权限横幅 | `MainWindowView`（:34）、`MenuTab`（:10） |
| `QuotaCard.swift` | 180 | 套餐余量展示卡 + 展示纯函数 | `QuotaCard`（:49）、`quotaColor`（:8） |
| `IMSettingsCard.swift` | 141 | iMessage 设置卡：开关、收件人校验、授权状态、测试按钮 | `IMSettingsCard`（:6） |
| `ConfigSettingsView.swift` | 119 | 配置文件管理页（增删/切换/导入导出） | `ConfigSettingsView`（:5） |
| `AutomationView.swift` | 112 | 脚本事件配置面板（创建示例脚本、跳转 Finder） | `AutomationView`（:7） |
| `OnboardingView.swift` | 104 | 首次启动三步引导 | `OnboardingView`（:7） |
| `SidebarView.swift` | 63 | 分组侧边栏 + 设备状态行 | `SidebarView`（:6） |
| `AboutView.swift` | 48 | 关于页（版本号、跳转 GitHub） | `AboutView`（:3） |
| `NetworkSettingsView.swift` | 38 | Wi-Fi 暂停 / 被动模式设置 | `NetworkSettingsView`（:4） |
| `BasicSettingsView.swift` | 33 | 启用开关 + 开机自启（`SMAppService.mainApp`，:24-25） | `BasicSettingsView`（:5） |
| `UnlockSettingsView.swift` | 32 | 靠近唤醒 / 唤醒不解锁 / 屏保模式 | `UnlockSettingsView`（:4） |
| `LockSettingsView.swift` | 29 | 暂停媒体 / 关闭显示器 / 输入活动暂缓 | `LockSettingsView`（:4） |
| `ToastView.swift` | 24 | 顶部浮动提示 | `ToastView`（:6） |

小计 **3915 行**。A+B+C = 3504 + 1851 + 3915 = **9270** ✅（与总行数吻合）

### D. 非 Swift 资源

| 文件 | 行数 | 职责 |
|---|---|---|
| `lowlevel.c` / `.h` | 103 / 9 | IOPM 断言唤醒显示器、IORegistry 关屏、`SACLockScreenImmediate()`（CGEvent 模拟 ⌃⌘Q 锁屏，:48-102） |
| `MediaRemote.h` | 10 | 私有 `MRMediaRemoteSendCommand` / `MRMediaRemoteGetNowPlayingApplicationIsPlaying` 声明 |
| `Launcher/`（独立 target） | ObjC 29 行 + xib | 开机自启 helper，`LSBackgroundOnly=true`，只负责拉起主应用然后退出（`Launcher/AppDelegate.m:8-24`），随主 app 打进 `Contents/Library/LoginItems`（`project.pbxproj:89`） |

---

## 2. 依赖关系

### 2.1 分层依赖图（箭头 = 依赖）

```
[UI 层 · C 类]
  MainWindowView ──┬─> OverviewView ──> FUnManager / FUn / QuotaService
                   ├─> DiagnosticsView ──> FUnManager / DecisionLogger ──> MenuTab(UI enum)
                   ├─> StatsView ──> SignalDataStore / DecisionLogger / StatsCalculator
                   ├─> ConfigSettingsView ──> ProfileManager ──> FUnManager
                   ├─> CalibrationWizardView / OnboardingView ──> FUnManager
                   └─> MenuBarPopoverView ──> FUnManager / FUn / QuotaService
  AppDelegate ──> FUn(持有) / FUnManager(持有) / InputActivityMonitor / StatusItem+NSPopover
        │              ▲
        │              └── 实现 FUnDelegate（AppDelegate.swift:166，:195-258）
        └──> SystemInteractionService / SecurityService / ScriptRunner(单例)

[决策层 · B 类]
  FUnManager ──> FUn / FUnlockStateMachine / DecisionLogger /
                 SystemInteractionService.shared / SecurityService.shared /
                 ScriptRunner.shared / iMessageNotifier.shared / TelemetryLogger.shared /
                 UpdateChecker + UpdateDownloader ──> UpdateInstaller
  FUnManager ──> OverviewView.RSSIRange.min      ← 逻辑反向依赖 UI（FUnManager.swift:230）
  FUnManager ──> InputActivityMonitor（类型定义在 AppDelegate.swift:21）

[核心层 · A 类]
  FUn ──> SignalPipeline / ConfigStore / SignalDataStore / InputActivityMonitor /
          Log / lockLog / LEDeviceInfo / appleDeviceNames
  FUnlockStateMachine ──> UserNotifications
  DecisionLogger ──> RingBuffer / ConfigStore
  iMessageNotifier ──> IMMessageComposer / ConfigStore
  ProfileManager ──> ConfigStore，且 applyActiveProfile(to: FUnManager)（:54-58）→ 回指决策层

[系统层 · 非 Swift]
  SystemInteractionService ──> funlock_wakeDisplay / funlock_sleepDisplay /
                               SACLockScreenImmediate (lowlevel.c) /
                               MRMediaRemote* (MediaRemote 私有框架)
  SecurityService ──> Security.framework (Keychain)
```

### 2.2 完全不依赖 AppKit/SwiftUI 的模块（可直接搬走）

以下 20 个文件只 import Foundation / Combine / CoreBluetooth / CoreWLAN / SQLite3 / UserNotifications / os，**编译期不需要 AppKit 或 SwiftUI**：

`FUn.swift`(1200)、`SignalPipeline.swift`(178)、`FUnlockStateMachine.swift`(158)、`DecisionLogger.swift`(334)、`appleDeviceNames.swift`(221)、`iMessageNotifier.swift`(193)、`TelemetryLogger.swift`(186)、`ProfileManager.swift`(130)、`checkUpdate.swift`(92)、`QuotaService.swift`(117)、`UpdateDownloader.swift`(125)、`LEDeviceInfo.swift`(96)、`SignalDataStore.swift`(83)、`ConfigStore.swift`(76)、`IMMessageComposer.swift`(79)、`RingBuffer.swift`(56)、`DebugLog.swift`(50)、`WiFiMonitor.swift`(14)、`Log.swift`(12)、`ScriptRunner.swift`(104)

合计 **3504 行**。

需要注意的三处「隐性耦合」：

1. `FUn.swift:136,139-141` 持有并读取 `InputActivityMonitor`，而该类型**定义在 `AppDelegate.swift:21-67`**（该文件 import 了 Cocoa/IOKit.hid）。搬 `FUn.swift` 必须一并搬这个类型或改掉它。
2. `FUnManager.swift:230` 直接引用 `OverviewView.RSSIRange.min`——**决策层引用 SwiftUI 视图里的常量**。
3. `FUnlockUtils.swift:69-96` 给 `DecisionEvent` 扩展了返回 `SwiftUI.Color` 的 `icon` 属性，因此该文件不能脱离 SwiftUI。

### 2.3 依赖 NSStatusItem / NSPopover / 菜单栏形态（搬走必须重写 UI 层）

| 文件 | 行数 | 形态依赖的证据 |
|---|---|---|
| `AppDelegate.swift` | 682 | `NSStatusBar.system.statusItem`（:174）、`NSPopover` + `NSHostingController`（:490-498）、`NSEvent.addGlobalMonitorForEvents` 外部点击收起（:502）、`NSWindow` 设置窗口（:639）、Carbon `RegisterEventHotKey`（:352-367）、`NSApp.setActivationPolicy(.accessory)`（:627）、`updateStatusBarIcon()`（:229-250） |
| `MenuBarPopover.swift` | 404 | 专为 popover 设计的 282pt 定宽面板（:42 `.frame(width: 282)`）+ `MenuBarAction` 枚举（:397-404），动作全部由 AppDelegate 的 `handleMenuBarAction` 消费（`AppDelegate.swift:543-552`） |
| `MainWindowView.swift` + `SidebarView.swift` | 307 | 独立主窗口 + 标签页导航（`NavigationSplitView`，:56-71）；`SidebarView` 以 `MenuTab` 为唯一导航模型 |

另外，`FUnlockStateMachine` 与 `FUnManager` 都**不是** AppKit 形态依赖，但 `FUnManager` 会切换应用激活策略（`NSApp.setActivationPolicy(.regular)` 系统睡眠时 / `.accessory` 唤醒后，:282,293），这是菜单栏 agent 应用的形态假设。

---

## 3. 核心数据流：BLE 广播 → 信号处理 → 状态判定 → 解锁/锁屏

### 3.1 完整调用链

**阶段 1：BLE 采集（文件 `FUn.swift`）**

| 步骤 | 位置 | 说明 |
|---|---|---|
| 1.1 建中心管理器 | `FUn.swift:1194-1199` | `CBCentralManager(delegate: self, queue: bleQueue)`，`bleQueue` 为 `com.funlock.ble`（:131） |
| 1.2 蓝牙状态就绪 | `centralManagerDidUpdateState` `FUn.swift:378-404` | `.poweredOn` → `scanForPeripherals()`；`.poweredOff` → 停所有 timer + 告警回调 |
| 1.3 扫描参数自适应 | `scanForPeripherals` `FUn.swift:216-243` | 无目标/主动模式 `AllowDuplicates=false`；被动模式 `=true` |
| 1.4 发现广播 | `didDiscover` `FUn.swift:911-1001` | 命中 `monitoredUUIDs` → `updateMonitoredPeripheral(rssi)`（:935）；随后按需 `connectMonitoredPeripheral()`（:938） |
| 1.5 主动模式读 RSSI | `didConnect` `FUn.swift:1003-1023` → `didReadRSSI` `FUn.swift:1047-1133` | 连接后停扫描、`peripheral.readRSSI()` 轮询；轮询间隔在 0.5s/2s/8s 间自适应（:1069-1098） |
| 1.6 信号超时兜底 | `resetSignalTimer` `FUn.swift:323-353` | 每 `signalTimeout`(默认 60s) 计数，连续 3 次 → `markSignalLost()` |

**阶段 2：信号处理（`FUn.swift` → `SignalPipeline.swift`）**

| 步骤 | 位置 | 说明 |
|---|---|---|
| 2.1 统一入口 | `updateMonitoredPeripheral` `FUn.swift:673-696` | 依次：`processSignal` → `updateDisplayRSSI` → `checkProximity` → `applyLockTimer` → `ensureHeartbeat` → `resetSignalTimer` |
| 2.2 管线计算 | `processSignal` `FUn.swift:700-732` → `SignalPipeline.process` `SignalPipeline.swift:65-106` | 窗口 1.5s（:40）；S1 IQR 异常检测（:70 / :108-116）；S2 EWLR 加权斜率 + EMA（:73-75 / :118-142）；S3 非对称 Kalman（:78 / :144-166）；S4 自适应时间衰减（:80-97） |
| 2.3 采样入库 | `FUn.swift:723-729` | `SignalDataStore.shared.record(...)`（环形缓冲 300） |
| 2.4 时间衰减兜底 | `decayedEffectiveRSSI` `FUn.swift:414-427` | 6s 内不罚；6–10s 按 0.75 dB/s；>10s 按 1 dB/s 封顶 20 dB；下限 -100 |
| 2.5 上下文快照 | `signalSnapshot()` `FUn.swift:445-456` | 跨线程读取统一走 `SignalSnapshot`（effectiveRSSI/presence/kalman/slope/anomalous/activeModeActive） |

**阶段 3：状态判定（`FUn.swift`）**

| 判定 | 位置 | 条件 |
|---|---|---|
| 在场 / 靠近 | `checkProximity` `FUn.swift:759-805` | `effectiveRSSI >= unlockRSSI` 且 `!presence` → `presence = true`，回调 `updatePresence(true, "close")`（:793） |
| 离场锁定时器 | `applyLockTimer` `FUn.swift:807-843` | `effectiveRSSI < lockThreshold` 且 `presence && proximityTimer == nil` 且过冷静期且无输入活动 → `startLockTimer()` |
| 锁屏超时自适应 | `startLockTimer` `FUn.swift:624-671` + `lockTimeout` `FUn.swift:608-617` | 斜率 ≤ -8 dBm/s → 2.5s；≥ -1 → 基准 5s；中间线性插值 |
| 离场触发 | `startLockTimer` 定时器回调 `FUn.swift:656-667` | 回调时二次校验（信号已恢复 / 输入活动 / 冷静期 → 放弃），否则 `presence=false` + `updatePresence(false, "away")`（:665） |
| 信号丢失 | `markSignalLost` `FUn.swift:357-376` | 3 次连续超时 → `updatePresence(false, "lost")`（:374） |
| 解锁冷静期 | `refreshProximityGrace` / `isWithinLockGracePeriod` `FUn.swift:566-574` | `proximityGracePeriod = 5s`（:214） |
| 心跳兜底 | `ensureHeartbeat` `FUn.swift:488-555` | 每 2/3/8s 主动检查 `eff < threshold && !hasTimer && 过冷静期` → `startLockTimer()`，防丢包 100% 时死锁 |

**阶段 4：决策与执行（`FUnManager.swift` → `SystemInteractionService.swift`）**

| 步骤 | 位置 | 说明 |
|---|---|---|
| 4.1 回调桥接 | `AppDelegate.updatePresence` `AppDelegate.swift:219-226` | `presence=true → manager.onDeviceApproached()`；`false → manager.onDeviceLeft(reason:)` |
| 4.2 靠近处理 | `onDeviceApproached` `FUnManager.swift:383-409` | 清锁屏通知（:394）→ 阶梯唤醒（`>= preWakeThreshold` 且 displaySleeping 且 wakeOnProximity，:397-403）→ 到位解锁（`>= unlockRSSI` → `attemptAutoUnlock()`，:406-408） |
| 4.3 解锁门控链 | `attemptAutoUnlock` `FUnManager.swift:546-643` | 依次：presence（:552）→ unlockRSSI 未禁用（:553）→ `eff >= unlockRSSI`（:556）→ 状态机 `canAttemptUnlock`（:563）→ 锁屏缓冲 0.8s（:567）→ 解锁冷却 5s（:575）→ Wi-Fi 暂停（:583-590）→ 手动锁保护（:592-596）→ 并行唤醒分支（:599-621）→ `wakeWithoutUnlocking`（:623）→ 显示器仍休眠（:624）→ 屏幕确已锁（:628）→ 延迟 300ms（:631-642） |
| 4.4 取密码 | `tryUnlock` `FUnManager.swift:646-650` → `guardFetchPassword` `FUnManager.swift:653-690` | 屏幕已锁（:660）→ 状态机 `attemptUnlock()`（:663）→ 距上次解锁 > 3s（:667）→ Keychain `fetchPassword`（:672）→ `isSecureToInject`（:686） |
| 4.5 注入与验证 | `performInjectionAndVerify` `FUnManager.swift:693-776` | 置 `isAutoUnlocking = true`（:701）→ `sys.injectPasswordWithPrelude`（:703）→ 失败则 AX 告警（:709-714）→ 成功则 `sys.verifyUnlock` 双保险（:721）→ 成功分支写 iMessage/ScriptRunner/Telemetry/状态机（:726-747）；失败分支计数、3 次后弹密码错误告警（:748-773） |
| 4.6 键鼠注入 | `injectPasswordWithPrelude` `SystemInteractionService.swift:285-300` | 先 `sendShiftKey`（:258-280）作为前奏 → sleep 300ms → `fakeKeyStrokes`（:110-155）；三级降级：`cgSessionEventTap` → `cghidEventTap`（:159-194，每 20 个 UTF-16 码元发一批）→ `osascript System Events`（仅 ASCII，:199-251） |
| 4.7 双保险验证 | `verifyUnlock` `SystemInteractionService.swift:422-467` | `withTaskGroup` 三条并行路径竞速：`waitForUnlockNotification`（:357-397，CGSession 轮询 + `NSWorkspace.didWakeNotification`）、`checkScreenUnlocked`（:401-417，100ms 轮询）、超时任务 |
| 4.8 离场处理 | `onDeviceLeft` `FUnManager.swift:411-453` | 门控：enabled（:418）、`screen == .unlocked`（:419）、lockRSSI 未禁用（:420）、不在解锁冷静期（:423）→ `state.screen = .displaySleeping`（:429）→ `SystemInteractionService.lockOrSaveScreen`（:434，`SystemInteractionService.swift:90-103`）→ 通知/脚本/iMessage/遥测（:436-451） |
| 4.9 真正锁屏 | `SACLockScreenImmediate` `lowlevel.c:48-102` | 用 CGEvent 合成 ⌃⌘Q；事件构造失败时降级为 IORegistry `IORequestIdle` 关屏 |

### 3.2 状态机 `FUnlockStateMachine.swift`

**状态（`FUnlockStateMachine.swift:10-17`）**：`active`、`preWaking`、`readyToUnlock`、`unlocking`、`cooldown`、`degraded`。

**迁移条件（`canTransition`，:64-81）**：

| From → To | 触发点 |
|---|---|
| `.active → .unlocking` | `attemptUnlock()` 通过防抖与降级检查后（:105） |
| `.preWaking → .readyToUnlock` | 白名单允许，但**生产代码无调用点** |
| `.readyToUnlock → .unlocking` | 白名单允许，但**生产代码无调用点** |
| `.unlocking → .active` | `handleUnlockSuccess()`（:129） |
| `.unlocking → .cooldown` | `handleUnlockFailure()` 且失败次数 < 3（:119） |
| `.cooldown → .active` | `handleUnlockSuccess()` / `resetToActive()`（:129,:135） |
| `.active → .preWaking` / `.preWaking → .active` | 白名单允许，**生产代码无调用点** |
| `* → .degraded` | 失败次数 ≥ `maxConsecutiveFailures`(=3)（:99-101, :115-117），并发送本地通知（:145-157） |
| `* → .active` | `resetToActive(clearFailures:)`（:134-140），调用点：`FUnManager.swift:303,325`、`AppDelegate.swift:276`（点通知恢复）、`DiagnosticsView.swift:231`（诊断页按钮） |
| `* → .cooldown` | 同 `.unlocking → .cooldown` |

**关键参数**：`unlockCooldown = 5.0s`（:38）、`failureCooldown = 10.0s`（:39）、`maxConsecutiveFailures = 3`（:40）；`canAttemptUnlock` 要求非 degraded 且不在失败冷却（:51-53）。

> **事实**：`preWaking` 与 `readyToUnlock` 两个状态在生产代码中**永远不会被进入**（全仓 `grep -rn "preWaking|readyToUnlock"` 仅命中状态机自身定义与迁移白名单，以及 `FUnlockStateMachineTests` 的直调 `transition(to:)` 用例）。实际起作用的只有 `active / unlocking / cooldown / degraded` 四态。
> 另注：FUnlock 里存在**两套并行状态表示**——`FUnlockStateMachine`（解锁防抖/降级）与 `FUnManager.LockScreenState`（屏幕/系统/意图，`FUnManager.swift:63-84`），两者互不同步，各管一摊。

---

## 4. 系统交互面

### 4.1 能力清单

| # | 系统能力 | 用途 | 实现文件:行 | 需要的用户授权 |
|---|---|---|---|---|
| 1 | **CoreBluetooth**（`CBCentralManager`/`CBPeripheral`） | 扫描 BLE 广播、连接设备、读 RSSI | `FUn.swift:1198`（初始化）、:216-243、:911-1001、:1047-1133、:1135-1191 | 蓝牙（`NSBluetoothAlwaysUsageDescription`，`Info.plist:29-30`）；运行时用 `CBManager.authorization == .allowedAlways` 判定（`AppDelegate.swift:146,236,653`） |
| 2 | **Accessibility / CGEvent 键鼠注入** | 把密码「打字」进登录窗口 | `SystemInteractionService.swift:110-155,159-194,258-300`；局部 AX 判定 `AXIsProcessTrusted()`（`AppDelegate.swift:145,235,412,652`） | 辅助功能（Accessibility）。请求方式：`AXIsProcessTrustedWithOptions` 带 prompt（`AppDelegate.swift:151-153`）或直接打开系统设置页（:161-164, :417-422） |
| 3 | **IOKit HID（输入活动监听）** | 有键鼠活动时否决锁定 | `InputActivityMonitor` `AppDelegate.swift:21-67`（`IOHIDManager` :38-52，回调过滤 :69-91）；消费点 `FUn.swift:139-141,335,528,641,828` | 输入监控（`NSInputMonitoringUsageDescription`，`Info.plist:33-34`）。注意：代码里**没有单独请求该项**，只在辅助功能已授予时才 `inputMonitor.start()`（`AppDelegate.swift:612-614`） |
| 4 | **Keychain（Security.framework）** | 存/取 Mac 登录密码 | `SecurityService.swift:29-46`（写）、:50-76（读）、:94-101（删） | 无需额外授权；`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`（:36）；冷启动 `errSecInteractionNotAllowed` → `.coldBoot`（:64-66） |
| 5 | **IOKit / IORegistry**（含私有 IODisplayWrangler 属性） | 唤醒显示器、关屏、查询显示器供电 | `lowlevel.c:8-29`（`IOPMAssertionCreateWithName` + `IORequestPowerState`）、:39-46（`IORequestIdle`）、:94-102（关屏兜底）；`SystemInteractionService.swift:60-78` 读 `IOEnginePower` | 无（本机实测不需要额外授权） |
| 6 | **CGEvent 合成 ⌃⌘Q** | 触发系统「锁定屏幕」 | `lowlevel.c:48-92`（`CGEventPost(kCGHIDEventTap, ...)`） | 辅助功能（无权限时事件构造失败并降级关屏，`lowlevel.c:67-75`） |
| 7 | **CGSession / CGSessionCopyCurrentDictionary** | 判定屏幕是否锁定、是否已解锁 | `SystemInteractionService.swift:22-31`、:36-39、:379-383、:404-408 | 无 |
| 8 | **NSWorkspace** | 前台应用判定（是否 loginwindow）、屏保、系统睡眠唤醒通知、打开系统设置 | `SystemInteractionService.swift:48-52`（frontmost 必须是 `com.apple.loginwindow`）、:92-95（启动 ScreenSaver.Engine）、:363-374（`didWakeNotification`）、:495；订阅在 `AppDelegate.swift:561-573` | 无 |
| 9 | **NSRunningApplication** | 检测屏保进程 | `SystemInteractionService.swift:26` | 无 |
| 10 | **私有 MediaRemote**（`MRMediaRemoteSendCommand`） | 锁屏时暂停 / 解锁后恢复播放 | `MediaRemote.h:8-10` 声明；`SystemInteractionService.swift:305-322` | 无；链接方式：`MediaRemote.framework` 直接加入 Frameworks 构建阶段（`project.pbxproj:99` 文件引用、Frameworks phase 内 `MediaRemote.framework in Frameworks`），并配 `SYSTEM_FRAMEWORK_SEARCH_PATHS = $(SYSTEM_LIBRARY_DIR)/PrivateFrameworks`（`project.pbxproj:793-796,823-826`） |
| 11 | **iMessage / AppleScript（外部 osascript 子进程）** | 解锁/锁屏通知发到 Apple Watch | `iMessageNotifier.swift:132-156`（`/usr/bin/osascript` 驱动 Messages）；系统设置页跳转也走 AppleScript（`AppDelegate.swift:161-164`） | 自动化（Automation → 控制 Messages）；错误码 `-1743` 被显式翻译为授权提示（`iMessageNotifier.swift:185-187`）。entitlement `com.apple.security.automation.apple-events`（`FUnlock.entitlements:5-6`） |
| 12 | **Wi-Fi（CoreWLAN）** | 连接指定 SSID 时暂停解锁 | `WiFiMonitor.swift:7-13`；消费点 `FUnManager.swift:583-590` | 无（本机实测读 SSID 不弹窗） |
| 13 | **LaunchAtLogin** | 开机自启 | `SMAppService.mainApp.register()/unregister()`（`BasicSettingsView.swift:22-27`）；启动时同步状态（`AppDelegate.swift:619-622`）。同时存在旧的 `Launcher.app`（打进 `Contents/Library/LoginItems`，`project.pbxproj:89`） | 无额外授权，但会出现在「登录项」列表 |
| 14 | **自研更新（非 Sparkle）** | 每天查 GitHub Release → 下载 zip → codesign 校验 → bash 脚本替换 `/Applications/FUnlock.app` | `checkUpdate.swift:34`（`api.github.com/repos/hahappyfu/FUnlock/releases/latest`）、`UpdateDownloader.swift:35`（release zip URL）、`UpdateInstaller.swift:23-39`（`codesign --verify --deep --strict` + TeamID 比对）、:41-60（安装脚本）、:82-84（自杀退出） | 无；但**强依赖 Team ID `JJYCS98SHK` 一致**（`UpdateInstaller.swift:35-39`） |
| 15 | **UserNotifications** | 锁屏通知、降级通知、更新通知 | `SystemInteractionService.swift:328-345`；`FUnlockStateMachine.swift:145-157`；`checkUpdate.swift:85-91`；授权请求 `AppDelegate.swift:558`；点击路由 `AppDelegate.swift:266-281` | 通知 |
| 16 | **DistributedNotificationCenter** | 监听系统锁屏/解锁/屏保/改密 | `AppDelegate.swift:575-590`（`com.apple.screenIsUnlocked`、`com.apple.screenIsLocked`、`com.apple.screensaver.didstart/didstop`、`com.apple.security.loginwindow.passwordChanged`） | 无 |
| 17 | **Carbon RegisterEventHotKey** | 全局快捷键 ⌘⇧L 立即锁屏 | `AppDelegate.swift:345-388` | 无 |
| 18 | **NSEvent 全局鼠标监听** | 点击 popover 外部时收起 | `AppDelegate.swift:502-506` | 无（仅鼠标事件）；**推测**未来若监听键盘事件会需要输入监控 |
| 19 | **SQLite3 读 `/Library/Bluetooth/*.db`** | CBUUID → MAC/设备名 | `LEDeviceInfo.swift:12,18`（open）、:43,70（参数化查询） | **完全磁盘访问（Full Disk Access）**。证据：本机（macOS 26.6.2）在无 FDA 的 shell 下 `open('/Library/Bluetooth/com.apple.MobileBluetooth.ledevices.paired.db')` 返回 `EPERM: Operation not permitted`，而 `/Library/Preferences/com.apple.Bluetooth.plist` 可直接读（`FUn.swift:40` 读的正是后者）。该项未在 Info.plist/entitlements 中声明，属于运行期 TCC 授权 |
| 20 | **UserDefaults suite** | 全部配置持久化到 `com.fuhahah.Funlock.config` 独立域 | `ConfigStore.swift:11,19`；key 清单 `ConfigStore.swift:65-75` | 无 |
| 21 | **子进程执行** | `osascript`、`/usr/bin/unzip`、`/usr/bin/codesign`、`/bin/bash`、`/bin/chmod`、用户脚本 | `SystemInteractionService.swift:226-232`；`iMessageNotifier.swift:140-142`；`UpdateDownloader.swift:69-76`；`UpdateInstaller.swift:23-28,72-73,89-91,118-126`；`ScriptRunner.swift:92-103` | 无（未沙盒）；脚本目录为 `~/Library/Application Scripts/FUnlock/event`（`ScriptRunner.swift:93-94`） |
| 22 | **提权 helper** | **不存在** —— 全仓无 `SMJobBless` / `AuthorizationExecuteWithPrivileges` / privileged helper | `grep` 无命中 | — |

### 4.2 entitlements 与 Info.plist 相关键

**`FUnlock/FUnlock.entitlements`（全文 8 行）**

```xml
<key>com.apple.security.automation.apple-events</key><true/>   <!-- :5-6 -->
```
无 `com.apple.security.app-sandbox` → **未沙盒**。`Launcher/Launcher.entitlements` 为空 dict（:4）。

**`FUnlock/Info.plist` 相关键**

| 键 | 值/行号 | 作用 |
|---|---|---|
| `LSUIElement` | `true`（:27-28） | 无 Dock 图标的 agent 应用 |
| `NSBluetoothAlwaysUsageDescription` | "Funlock uses Bluetooth to detect devices."（:29-30） | 蓝牙权限文案 |
| `NSInputMonitoringUsageDescription` | "Funlock monitors keyboard and trackpad input to defer locking while you're working."（:33-34） | 输入监控权限文案（代码未主动请求该项） |
| `NSMainNibFile` | `MainMenu`（:35-36） | 主菜单 nib |
| `NSPrincipalClass` | `NSApplication`（:37-38） | — |
| `CFBundleShortVersionString` / `CFBundleVersion` | `2.8.37` / `1343`（:19-22） | 更新比对基准（`checkUpdate.swift:65`） |

**`Launcher/Info.plist`**：`LSBackgroundOnly = true`（:21-22），`CFBundleIdentifier = com.fuhahah.FUnlock.Launcher`（`project.pbxproj:618`）。

---

## 5. 移植难点清单

站在「把它移植进一个只有 SwiftUI 面板、目前零 CoreBluetooth 代码的 app」的角度。

| # | 难点 | 事实与证据 | 风险性质 |
|---|---|---|---|
| 1 | **应用形态不同：菜单栏 agent vs 面板 app** | FUnlock 靠 `LSUIElement=true`（`Info.plist:27`）+ `NSApp.setActivationPolicy(.accessory)`（`AppDelegate.swift:627`）常驻无窗口运行；系统睡眠时还会切到 `.regular`（`FUnManager.swift:282`）再切回（:293）。解锁注入要求「屏幕锁着但进程活着」——被锁屏后 app 是否仍在前台/被挂起，取决于宿主 app 的形态 | 高 |
| 2 | **密码注入对「前台是 loginwindow」的强依赖** | `isSecureToInject` 要求 `NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.loginwindow"`（`SystemInteractionService.swift:48-52`），否则直接放弃注入。注入前还要求 `CGSessionScreenIsLocked == 1`（:22-31）。注意 `FUnManager.swift:657` 也只是**打印** frontmost，判定在 SystemInteractionService | 高 |
| 3 | **三级注入降级链全部依赖辅助功能权限** | `fakeKeyStrokes` 先用 `cgSessionEventTap`、再用 `cghidEventTap`（`SystemInteractionService.swift:110-155`），第三级落到 `osascript` 驱动 System Events（:199-251，仅 ASCII 密码）。任一权限缺失即静默失败，代码用「是否成功 post 事件」判断（:181,192），失败转 AX 告警（`FUnManager.swift:709-714`） | 高 |
| 4 | **权限申请时机有明确的顺序耦合** | 输入活动监听被刻意延迟到辅助功能已授予之后才 `start()`，注释两次写明是为规避 macOS Sequoia TCC 崩溃（`AppDelegate.swift:463-464, 611-614`）。同时 `NSPopover`/`NSWindow` 也延迟到下一个 RunLoop 创建，注释为规避 TCC 框架崩溃（:477-482） | 高 |
| 5 | **TCC 按签名身份记账，ad-hoc 签名会导致授权失效** | README:256-274 明确记录：`CODE_SIGNING_ALLOWED=NO` 产生 `Signature=adhoc / TeamIdentifier=not set`，`AXIsProcessTrusted()` 恒为 false，表现为「重启后辅助功能权限被重置」；正确做法是走 `DEVELOPMENT_TEAM = JJYCS98SHK` 自动签名（`project.pbxproj:778`(Debug) / `:809`(Release)）。**并入另一个 app 后 TCC 身份会变成宿主 app 的身份，已授权的 FUnlock 条目不会继承** | 高 |
| 6 | **完全磁盘访问需求（读 `/Library/Bluetooth`）** | `LEDeviceInfo.swift:12,18` 打开 `/Library/Bluetooth/*.db`。本机实测：无 FDA 的进程对该目录返回 `EPERM`；同一份代码里 `FUn.swift:40` 读的 `/Library/Preferences/com.apple.Bluetooth.plist` 则不需要 FDA。这条路径**只用于显示设备名/MAC**，不是解锁判定的必要环节（调用点 `FUn.swift:965-973`，失败时 fallback 到 `readBluetoothDevice`） | 中 |
| 7 | **私有 API 面** | ① `MediaRemote.framework` 的 `MRMediaRemoteSendCommand`/`MRMediaRemoteGetNowPlayingApplicationIsPlaying`（`MediaRemote.h:8-10`，`SystemInteractionService.swift:307-321`）靠 `PrivateFrameworks` 搜索路径链接（`project.pbxproj:797-800`）；② IORegistry 私有属性 `IORequestPowerState`/`IORequestIdle`（`lowlevel.c:24-28, 41-45`）；③ `CGSessionCopyCurrentDictionary`（`SystemInteractionService.swift:23,379,404`）。这些都不在公开 API 契约内，且与 App Store 审核不兼容（本 app 未沙盒、走 DMG 分发） | 中 |
| 8 | **全局状态与单例遍布，且配置域固定** | `ConfigStore.shared` 固定 suite `com.fuhahah.Funlock.config`（`ConfigStore.swift:11`），并带一次性从 `UserDefaults.standard` 搬迁的逻辑（:26-37）；单例还有 `DecisionLogger.shared`（`DecisionLogger.swift:108`）、`ScriptRunner.shared`（`ScriptRunner.swift:5`）、`SystemInteractionService.shared`（`SystemInteractionService.swift:9`）、`SecurityService.shared`（`SecurityService.swift:22`）、`SignalDataStore.shared`（`SignalDataStore.swift:21`）、`iMessageNotifier.shared`（`iMessageNotifier.swift:13`）、`TelemetryLogger.shared`（`TelemetryLogger.swift:32`）、`ProfileManager.shared`（`ProfileManager.swift:14`）、`WiFiMonitor.shared`（`WiFiMonitor.swift:5`） | 中 |
| 9 | **持久化位置写死在用户目录，且带产品名** | `~/Library/Logs/FUnlock/`（`DebugLog.swift:13`、`FUnlockUtils.swift:16`、`DecisionLogger.swift:135`、`TelemetryLogger.swift:85`）、`~/Library/Application Support/FUnlock/events.log`（`ScriptRunner.swift:65-67`）、`~/Library/Application Scripts/FUnlock/event`（`ScriptRunner.swift:93-94`、`AutomationView.swift:11`）、`/tmp/FUnlock-update`（`UpdateDownloader.swift:15`、`UpdateInstaller.swift:62`） | 中 |
| 10 | **Keychain 条目的 service 是 bundle id** | `kSecAttrService: Bundle.main.bundleIdentifier ?? "FUnlock"`（`SecurityService.swift:34,54,98`）。并入宿主后 bundle id 变化 → **旧密码条目读不到**；同时 `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`（:36）会触发冷启动不可读分支（:64-66） | 中 |
| 11 | **决策层反向依赖 UI 类型** | `FUnManager.swift:230` 引用 `OverviewView.RSSIRange.min`（视图文件里的常量）。搬 FUnManager 必须连视图或改掉这行；`DecisionLogger.swift:64` 的 `ActionHint.goToTab(String)` 注释也绑定 `MenuTab.rawValue` | 低 |
| 12 | **解锁逻辑散落在两个文件、两套状态模型** | `FUn.swift` 负责 presence/lock timer（:759-843），`FUnManager.swift` 负责解锁门控（:546-690）；两者用 `FUnDelegate`（`FUn.swift:118-126`）与 `signalSnapshot`（:445）通信。`FUnlockStateMachine` 与 `FUnManager.LockScreenState` 互不同步，且状态机有两个死状态（见 §3.2） | 中 |
| 13 | **macOS 版本与框架要求** | 部署目标 13.0（`project.pbxproj:703`）；`SMAppService`（`BasicSettingsView.swift:22`）、Swift Charts（`StatsView.swift:237`）、`@available(macOS 13.0, *)` 守卫（`AppDelegate.swift:493`）都要求 13+；`NSHostingController.sizingOptions` 亦为 13+ API | 低 |
| 14 | **代码签名/沙盒约束** | 未沙盒（无 `com.apple.security.app-sandbox`）+ `ENABLE_HARDENED_RUNTIME = YES`（`project.pbxproj:779,810`）。若宿主 app 已开启沙盒，则第 19 项（读 `/Library/Bluetooth`）、子进程执行（`osascript`/`unzip`/`codesign`/`bash`）、写 `~/Library/Logs` 与 `~/Library/Application Scripts` 全部需要额外 entitlement 或改路径 | 高（若宿主沙盒） |
| 15 | **自研更新器与绑定 `/Applications/FUnlock.app`** | `UpdateInstaller.swift:44` 硬编码 `APP="/Applications/FUnlock.app"`，并要求下载包 TeamID 与当前 app 一致（:35-39）；`UpdateDownloader.swift:90` 校验 `CFBundleIdentifier == com.fuhahah.FUnlock`。并入宿主后这套机制整体不适用 | 低（可丢弃） |
| 16 | **测试可验证性依赖 `@testable import` 与测试宿主** | 测试 target 的 `TEST_HOST` 就是 FUnlock.app 本身（`project.pbxproj:855`），`BUNDLE_LOADER = $(TEST_HOST)`（:833）；大量用例直接构造 `FUn`（含真实 `CBCentralManager`，`FUnlockTests.swift:898`）。搬到宿主后测试需要重新建立宿主/权限环境 | 中 |

---

## 6. 可丢弃清单

判据：与「靠近解锁 / 离开锁屏」这条主链（§3）无必然关系。

| 可丢弃项 | 涉及文件（行数） | 小计 | 占总源码比 | 证据 |
|---|---|---|---|---|
| 诊断页（决策时间线、过滤器、操作建议、导出） | `DiagnosticsView.swift`(340) + `DecisionLogger.swift`(334) | 674 | 7.3% | 页面本身仅被 `MainWindowView.swift:171-173` 以 1 个 Tab 挂载；`DecisionLogger` 的写入点全部是「记录」语义（`FUnManager.swift:141-176`），不影响决策 |
| 统计页（信号曲线 / 斜率曲线 / 计数） | `StatsView.swift`(436) + `SignalDataStore.swift`(83) | 519 | 5.6% | `StatsView` 仅由 `MainWindowView.swift:148-150` 的 sheet 打开；`SignalDataStore` 仅写采样（`FUn.swift:723-729`）与读展示 |
| 可视化校准向导 | `CalibrationWizardView.swift`(391) | 391 | 4.2% | 只是产出阈值的一层 UI 包装（`MainWindowView.swift:136-138`）；等价能力在 `OverviewView` 的滑块/微调里已存在（`OverviewView.swift:230-233`） |
| iMessage/Apple Watch 通知 | `iMessageNotifier.swift`(193) + `IMMessageComposer.swift`(79) + `IMSettingsCard.swift`(141) | 413 | 4.5% | 唯一消费点 `FUnManager.swift:441`（锁屏）与 `:732`（解锁），失败静默丢弃（`iMessageNotifier.swift:79-81`） |
| 自动更新（自研，非 Sparkle） | `checkUpdate.swift`(92) + `UpdateDownloader.swift`(125) + `UpdateInstaller.swift`(127) | 344 | 3.7% | 接线在 `FUnManager.swift:195-207`，触发点 `FUnManager.swift:343`（每次解锁后检查）与 `AppDelegate.swift:318-328` |
| 套餐余量显示（与解锁无关的第三方功能） | `QuotaService.swift`(117) + `QuotaCard.swift`(180) | 297 | 3.2% | 读 `~/.clawd/opencode-go-bridge-cache.json`（`QuotaService.swift:74-75`），展示于菜单栏面板（`MenuBarPopover.swift:36`）与总览页（`OverviewView.swift:70`） |
| 多配置文件 | `ProfileManager.swift`(130) + `ConfigSettingsView.swift`(119) | 249 | 2.7% | 只做阈值组合的存取与切换（`ProfileManager.swift:54-58`） |
| 脚本事件（`away`/`lost`/`unlocked`/`intruded`） | `ScriptRunner.swift`(104) + `AutomationView.swift`(112) | 216 | 2.3% | 调用点：`FUnManager.swift:338-339,437-438,734-736`，全部是旁路副作用 |
| 形子模式遥测 CSV | `TelemetryLogger.swift`(186) | 186 | 2.0% | 调用点 `FUnManager.swift:443-451,737-745,890-898`，只写不读 |
| 首次引导 / 关于 / Toast | `OnboardingView.swift`(104) + `AboutView.swift`(48) + `ToastView.swift`(24) | 176 | 1.9% | 纯展示层 |
| 多语言资源（8 语言，334/281 键） | `*.lproj/Localizable.strings` | — | 资源，非源码行 | 全仓字符串走 `t()` → `NSLocalizedString`（`FUnlockUtils.swift:4-6`） |
| 开机自启 | `BasicSettingsView.swift:21-28` + `Launcher/` target | ~15 行 Swift + 独立 target | <1% | `SMAppService.mainApp`；`Launcher` 仅拉起主 app 后自退（`Launcher/AppDelegate.m:8-24`） |

**只留核心的粗略体量对比**

| 口径 | 行数 | 占比 |
|---|---|---|
| 全部 Swift 源码 | 9270 | 100% |
| 上表可丢弃项合计（不含本地化资源与 Launcher target） | **3465** | **37.4%** |
| 保留的核心（含决策/信号/系统交互/配置/日志，即 9270 − 3465） | **5805** | **62.6%** |
| 其中「零 AppKit 依赖」的纯逻辑 | 3504 | 37.8% |
| 其中 UI 视图与入口（C 类） | 3915 | 42.2% |

> 另一角度：若目标宿主已有自己的 SwiftUI 面板，则 C 类 3915 行（含 682 行菜单栏/窗口/权限引导入口）中的绝大部分需要重写或丢弃；`MenuBarPopover.swift`(404) 是纯菜单栏形态产物，`SidebarView.swift`(63) + `MainWindowView.swift`(244) 是宿主面板天然替代的对象。

---

## 7. 测试现状

### 7.1 规模

| 文件 | 行数 | 测试类 / 用例数 | 覆盖对象 |
|---|---|---|---|
| `FUnlockTests.swift` | 3776 | 33 个类 / 274 个用例 | 见下表 |
| `FUnlockStateMachineTests.swift` | 365 | 42 个用例（4 个类） | `FUnlockStateMachine` 全量迁移/防抖/降级/通知/时间衰减 |
| `iMessageNotifierTests.swift` | 201 | 16 | 错误码映射、防抖、开关、测试发送 |
| `DecisionLoggerTests.swift` | 186 | 12 | 记录/合并/容量/持久化/轮转/清空/键白名单 |
| `QuotaTests.swift` | 144 | 16 | 归一化纯函数、边界、展示函数 |
| `IMMessageComposerTests.swift` | 106 | 17 | 文案组合、收件人规范化 |
| `ConfigStoreTests.swift` | 68 | 3 | 迁移与读写 |
| `ReasonActionMappingTests.swift` | 32 | 3 | `DecisionReason` ↔ 文案/动作映射完整性 |
| `DiagnosticsViewTests.swift` | 24 | 3 | `DecisionEvent.screenLabel` / `timeString` |
| 合计 | **4902**（含 9 个文件） | **386 个用例** | — |

### 7.2 `FUnlockTests.swift` 的类分布（用例数）

`FUnlockTests`(21) `LockScreenStateTests`(17) `LockIntentTests`(4) `SystemPowerStateTests`(3) `WakePhaseTests`(1) `MediaPlaybackStateTests`(1) `ScreenStateTests`(4) `UnlockAttemptWindowTests`(6) `UnlockedAtTests`(4) `StateTransitionSequenceTests`(8) `ScriptRunnerDedupTests`(14) `FUnManagerCooldownTests`(18) `ScriptRunnerEventLoggingTests`(3) `InjectionPreludeTests`(7) `TelemetryLoggerFormatTests`(24) `LegacyCompatibilityTests`(27) `FUnManagerStateMachineIntegrationTests`(2) `DualVerificationTests`(16) `SmoothedRSSITests`(5) `StaircaseThresholdTests`(7) `PreWakeStaircaseTests`(13) `KeychainSecurityTests`(15) `UserInterventionTests`(8) `FullUnlockFlowIntegrationTests`(4) `PowerStateScanControlIntegrationTests`(5) `PasswordChangeDegradationRecoveryIntegrationTests`(6) `LockUnlockEfficiencyTests`(8) `MenuBarPopoverViewTests`(7) `StatsCalculatorTests`(4) `ProfileImportExportTests`(6) `FUnManagerThresholdLinkTests`(3) `FUnProximityGraceTests`(2) `ManualLockThrottleTests`(1)

### 7.3 是否有测试保护（按模块）

| 模块 | 测试保护 | 证据 |
|---|---|---|
| `SignalPipeline`（Kalman/IQR/斜率/衰减） | ✅ 强 | `FUnlockTests.swift:8-174`（13 个用例，全部为纯计算直调 `pipeline.process`） |
| `FUnlockStateMachine` | ✅ 强 | `FUnlockStateMachineTests.swift` 全文件（含注入时间源 `nowProvider` 的冷却测试 :222-260） |
| `FUnManager` 冷却/缓冲/门控 | ✅ 中 | `FUnlockTests.swift:891-1040`（18 例）、`FUnManagerThresholdLinkTests`(:3670)、`ManualLockThrottleTests`(:3733)、`FUnProximityGraceTests`(:3707) |
| 解锁全流程（含注入前奏、双保险、降级恢复） | ✅ 中（可注入替身） | `InjectionPreludeTests`(:1098)、`DualVerificationTests`(:1998)、`FullUnlockFlowIntegrationTests`(:2891)、`PasswordChangeDegradationRecoveryIntegrationTests`(:3210) |
| `FUn`（CoreBluetooth 驱动本体） | ⚠️ 仅局部 | 有 `FUnProximityGraceTests`（grace 期纯逻辑）；**未发现对 `didDiscover`/`didReadRSSI`/`updateMonitoredPeripheral` 的用例**（全仓无 CBCentralManager 替身/协议抽象） |
| `SystemInteractionService` | ⚠️ 间接 | 双保险验证的可测版本 `verifyUnlock(timeout:notificationTimeout:waitForNotification:checkUnlocked:)`（`SystemInteractionService.swift:441-467`）接受闭包替身，被 `DualVerificationTests` 使用；**CGEvent 注入本身无测试** |
| `SecurityService`（Keychain） | ✅ 中 | `KeychainSecurityTests`(:2627) 15 例 |
| Keychain 冷启动分支 | ⚠️ | `.coldBoot` 分支（`SecurityService.swift:64-66`）需要真实 `errSecInteractionNotAllowed`，**推测**靠模拟返回码覆盖 |
| `DecisionLogger` / `TelemetryLogger` | ✅ 强 | 各自独立测试文件 + `TelemetryLoggerFormatTests`(24 例，含测试目录注入 `TelemetryLogger.testLogDirectory` `:40`) |
| `iMessageNotifier` / `IMMessageComposer` | ✅ 强 | 独立测试文件；`iMessageNotifier.scriptRunner` 注入点（`iMessageNotifier.swift:29`）专为单测设计 |
| `ProfileManager` 导入导出 | ✅ | `ProfileImportExportTests`(:3581) |
| `ConfigStore` | ✅ 弱（3 例） | `ConfigStoreTests.swift` |
| 更新链（`UpdateChecker`/`Downloader`/`Installer`） | ❌ 无 | 无对应测试文件 |
| 脚本执行真实副作用（`ScriptRunner.runScript`） | ❌ 无 | 只有日志格式与去重测试（`ScriptRunnerDedupTests`、`ScriptRunnerEventLoggingTests`） |
| `LEDeviceInfo` / `WiFiMonitor` / `QuotaService.refresh` 的真实读盘 | ❌ 无 | `QuotaTests` 只测 `normalize`/`publish` 纯函数（`QuotaService.swift:31,101`） |

### 7.4 测试与 UI 的耦合度

结论：**耦合很弱**，测试基本不构造真实 SwiftUI 视图。

- 与视图相关的用例只有 3 处，且都是**视图里的 static 纯函数**，不渲染视图：
  - `MenuBarPopoverViewTests`（`FUnlockTests.swift:3498-3545`）直接调 `MenuBarPopoverView.signalBars/signalLevel/signalText` 静态方法（视图定义在 `MenuBarPopover.swift:99-107,193`）。
  - `DiagnosticsViewTests.swift:6-23` 调 `DecisionEvent.screenLabel` 与 `DiagnosticsView.timeString`。
  - `QuotaTests.swift:114-143` 调 `quotaColor`/`humanizeReset`/`timeAgoText`（`QuotaCard.swift:8-47`）。
- 其余用例面向模型/纯函数/服务，通过 `@testable import FUnlock` 直接访问 internal 成员。
- 但有**测试宿主耦合**：`TEST_HOST` 指向 FUnlock.app 自身（`project.pbxproj:855`），`AppDelegate.applicationDidFinishLaunching` 靠环境变量 `XCTestConfigurationFilePath` 提前返回以隔离副作用（`AppDelegate.swift:429`）；多个用例会真实构造 `FUn`（`FUnlockTests.swift:898`），即在测试进程里创建 `CBCentralManager`（`FUn.swift:1198`）。

### 7.5 移植后能否验证正确性

- **可以原样验证**（无系统依赖）：`SignalPipeline`、`FUnlockStateMachine`、`DecisionLogger`、`RingBuffer`、`ConfigStore`、`IMMessageComposer`、`ProfileManager`、`QuotaSnapshot.normalize` 等纯逻辑——它们对应的用例不依赖宿主 app。
- **需要重建环境**：`FUnManager` 相关用例依赖 `FUn` 实例与 `ConfigStore.shared`；`InjectionPreludeTests`/`DualVerificationTests` 依赖 `SystemInteractionService` 的可测闭包版本；`KeychainSecurityTests` 依赖真实 Keychain。
- **无法用现有测试覆盖**：CoreBluetooth 回调链（`didDiscover`/`didReadRSSI`/`updateMonitoredPeripheral` 的在场/锁屏判定）、CGEvent 实际注入结果、TCC 权限行为、`/Library/Bluetooth` 读取。

---

## 一页速览

### 核心可移植模块（零 AppKit/SwiftUI 依赖，共 20 个文件）

| 文件 | 行数 | 备注 |
|---|---|---|
| `FUn.swift` | 1200 | 需一并处理对 `InputActivityMonitor`（定义在 `AppDelegate.swift:21`）的依赖 |
| `DecisionLogger.swift` | 334 | |
| `appleDeviceNames.swift` | 221 | 纯数据表 |
| `iMessageNotifier.swift` | 193 | |
| `TelemetryLogger.swift` | 186 | |
| `SignalPipeline.swift` | 178 | 含 `UnfairLock` |
| `FUnlockStateMachine.swift` | 158 | |
| `ProfileManager.swift` | 130 | 依赖 `FUnManager`（`applyActiveProfile`，:54-58） |
| `UpdateDownloader.swift` | 125 | |
| `QuotaService.swift` | 117 | 与解锁无关的第三方功能 |
| `ScriptRunner.swift` | 104 | |
| `LEDeviceInfo.swift` | 96 | 需完全磁盘访问 |
| `checkUpdate.swift` | 92 | |
| `SignalDataStore.swift` | 83 | |
| `IMMessageComposer.swift` | 79 | |
| `ConfigStore.swift` | 76 | 固定 suite 名 `com.fuhahah.Funlock.config`（:11） |
| `RingBuffer.swift` | 56 | |
| `DebugLog.swift` | 50 | |
| `WiFiMonitor.swift` | 14 | |
| `Log.swift` | 12 | |
| **小计** | **3504** | **37.8% 的 Swift 源码** |

### 逻辑层但触 AppKit 的模块（不可直接编译进无 AppKit 环境）

| 文件 | 行数 | 触 AppKit 的点 |
|---|---|---|
| `FUnManager.swift` | 929 | `NSApp.setActivationPolicy`（:282,293）、`NSWorkspace`（:657）、引用 `OverviewView.RSSIRange`（:230） |
| `SystemInteractionService.swift` | 523 | `NSWorkspace`/`NSAlert`/`NSApp`（:48,92-95,478,485,495,500-521） |
| `SecurityService.swift` | 175 | `NSAlert`/`NSSecureTextField`/`NSApp`（:112-145,156） |
| `UpdateInstaller.swift` | 127 | `NSApplication.shared.terminate`（:83） |
| `FUnlockUtils.swift` | 97 | `import SwiftUI` + `Color`（:71-80） |
| **小计** | **1851** | **20.0%** |

### UI 强耦合模块（搬走需重写 UI 层）

| 文件 | 行数 | 形态耦合 |
|---|---|---|
| `AppDelegate.swift` | 682 | `NSStatusItem`(:174)、`NSPopover`(:490-498)、`NSWindow`(:639)、Carbon 热键(:352-367)、`NSEvent` 全局监听(:502)、权限引导视图(:104-159) |
| `OverviewView.swift` | 495 | SwiftUI 总览页 |
| `StatsView.swift` | 436 | SwiftUI 统计页 + Swift Charts |
| `MenuBarPopover.swift` | 404 | 282pt 菜单栏面板（:42）+ 菜单动作枚举(:397) |
| `CalibrationWizardView.swift` | 391 | SwiftUI 校准向导 |
| `DiagnosticsView.swift` | 340 | SwiftUI 诊断页 |
| `MainWindowView.swift` | 244 | `NavigationSplitView` + `MenuTab`(:10) |
| `QuotaCard.swift` | 180 | SwiftUI 卡片 |
| `IMSettingsCard.swift` | 141 | SwiftUI 卡片 |
| `ConfigSettingsView.swift` | 119 | SwiftUI 设置页 |
| `AutomationView.swift` | 112 | SwiftUI 面板 |
| `OnboardingView.swift` | 104 | SwiftUI 引导 |
| `SidebarView.swift` | 63 | 侧边栏 + `MenuTab` |
| `AboutView.swift` | 48 | SwiftUI 关于页 |
| `NetworkSettingsView.swift` | 38 | SwiftUI 设置页 |
| `BasicSettingsView.swift` | 33 | SwiftUI + `SMAppService` |
| `UnlockSettingsView.swift` | 32 | SwiftUI 设置页 |
| `LockSettingsView.swift` | 29 | SwiftUI 设置页 |
| `ToastView.swift` | 24 | SwiftUI 组件 |
| **小计** | **3915** | **42.2%** |

> 另有非 Swift 资产：`lowlevel.c`(103) + `MediaRemote.h`(10) + `Launcher` target（ObjC 29 行）+ 8 套 `.lproj` 本地化资源（334/281 键）。

### 三个最大的移植风险（按证据强度排序）

1. **权限与签名身份不可继承**：辅助功能/输入监控/自动化/完全磁盘访问全部按「应用签名身份」记账。README:256-274 记录了 ad-hoc 签名导致 `AXIsProcessTrusted()` 恒 false 的实例；entitlements 只有 `com.apple.security.automation.apple-events`（`FUnlock.entitlements:5-6`），未沙盒；而解锁能力依赖 `AXIsProcessTrusted`（`AppDelegate.swift:412`）+ `isSecureToInject` 要求前台为 loginwindow（`SystemInteractionService.swift:48-52`）。
2. **应用形态差异：无窗口常驻 agent vs SwiftUI 面板**：FUnlock 依赖 `LSUIElement`（`Info.plist:27`）与 `NSApp.setActivationPolicy`（`FUnManager.swift:282,293`、`AppDelegate.swift:627`）在锁屏状态下继续跑 BLE 与定时器；`AppDelegate.swift` 682 行里绝大部分是菜单栏/窗口/权限引导形态代码，且输入监听与窗口创建都被刻意延迟以规避 TCC 崩溃（:463-464,477-482,611-614）。
3. **密码注入链与私有 API 的脆弱性**：三级降级注入（`SystemInteractionService.swift:110-155,199-251`）与 `SACLockScreenImmediate`（`lowlevel.c:48-102`）全部依赖 CGEvent 辅助功能权限；媒体控制走私有 `MediaRemote`（`MediaRemote.h:8-10`）、唤醒/关屏走 IORegistry 私有属性（`lowlevel.c:24-28,41-45`）。这些路径失败时多为静默降级（`SystemInteractionService.swift:181,192`；`lowlevel.c:67-75`），且现有测试完全没有覆盖（见 §7.3）。
