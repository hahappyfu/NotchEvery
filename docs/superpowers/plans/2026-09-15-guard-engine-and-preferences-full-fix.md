# 守护核心引擎、第三页控制台与独立偏好设置全量修复实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 subagent-driven-development（推荐）或 executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 彻底修复 NotchEvery 守护引擎中系统生命周期通知断裂、RSSI 阈值重启丢失及级联改写等核心命脉缺陷；补齐 iMessage 自动化权限沙盒配置与真实通信链路；下线虚假假开关并补全第三页控制台独立闭环；全面加固偏好设置窗口的交互防呆与视觉规范。

**架构：**
1. **系统事件总线接入**：在 `GuardStore` 中统一注册 `DistributedNotificationCenter` 与 `NSWorkspace.notificationCenter`，将系统的锁屏、解锁、屏保、休眠与唤醒事件准确分发至 `FUnManager` 的对应状态机处理器。
2. **配置持久化与互锁防御**：在 `GuardStore` 启动与设备恢复时同步恢复 `lockRSSI` / `unlockRSSI`；解除 `setUnlockRSSI` 对 `lockRSSI` 的强制覆盖，仅在倒挂时施加必要下调保护。
3. **安全沙盒与通信闭环**：在 `NotchDrop.entitlements` 声明 `com.apple.security.automation.apple-events`，在 `Info.plist` 增加 `NSAppleEventsUsageDescription`，纠正 AppleScript 错误文案至 `NotchEvery` 并优化跨进程报错处理。
4. **控制台与偏好设置全链路重构**：第三页下线空头开关 `pauseItunes`，Header 增加真执行与总闸微控；偏好设置增加最小尺寸保护、向导出厂阈值一键重置与日志清空确认。

**技术栈：** Swift 5.9+, SwiftUI, AppKit, Combine, Hardened Runtime, AppleScript / TCC Automation, IOKit / IORegistry.

**规格：** 基于 2026-09-15 四路子智能体地毯式死角审计报告。

## 全局约束
- 编译与运行平台：macOS 14+ (Sonoma), macOS 15+ (Sequoia), macOS 26+ (Tahoe / Liquid Glass)。
- 构建要求：所有修改后必须通过 `xcodebuild test` 全量测试套件，不得产生任何新的 Warning 或 Regression。
- 权限隔离：遵守 Hardened Runtime 安全沙盒准则，不引入私有 API。
- 视觉规范：遵循 Apple Native Studio 工业级设计规范（`StudioColor`, `StudioMaterial`, `StudioAnimation`）。

---

### 任务 1：接入系统生命周期通知与状态机事件总线（P0）

**文件：**
- 修改：`NotchDrop/GuardStore.swift`
- 修改：`NotchDrop/FUnManager.swift`
- 测试：`Tests/GuardStoreTests.swift`

- [ ] **步骤 1：编写失败的单元测试**

在 `Tests/GuardStoreTests.swift` 中编写针对系统通知注册与分发的测试：
```swift
func testSystemScreenLockedNotificationTriggersManager() {
    let store = GuardStore.shared
    store.start()
    // 模拟发出系统锁屏通知
    DistributedNotificationCenter.default().postNotificationName(
        NSNotification.Name("com.apple.screenIsLocked"),
        object: nil,
        userInfo: nil,
        deliverImmediately: true
    )
    // 验证 store.funManager.state.screen 状态正确流转
    XCTAssertTrue(store.funManager.state.isEffectivelyLocked)
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：`xcodebuild test -scheme NotchDrop -destination 'platform=macOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -only-testing:NotchEveryTests/GuardStoreTests/testSystemScreenLockedNotificationTriggersManager`
预期：FAIL，因为 `GuardStore` 尚未监听 `com.apple.screenIsLocked`。

- [ ] **步骤 3：在 GuardStore 中实现完整的生命周期通知监听**

在 `GuardStore.swift` 中增加系统观察者注册方法并在 `start()` 中调用：
```swift
private var systemObservers: [NSObjectProtocol] = []

private func setupSystemNotifications() {
    guard systemObservers.isEmpty else { return }

    let dnc = DistributedNotificationCenter.default()
    let wsCenter = NSWorkspace.shared.notificationCenter

    // 1. 屏幕锁定与解锁
    systemObservers.append(dnc.addObserver(forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
        self?.funManager.onSystemScreenLocked()
    })
    systemObservers.append(dnc.addObserver(forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
        self?.funManager.onUnlock()
    })

    // 2. 屏幕保护程序
    systemObservers.append(dnc.addObserver(forName: NSNotification.Name("com.apple.screensaver.didstart"), object: nil, queue: .main) { [weak self] _ in
        self?.funManager.onScreensaverStart()
    })
    systemObservers.append(dnc.addObserver(forName: NSNotification.Name("com.apple.screensaver.didstop"), object: nil, queue: .main) { [weak self] _ in
        self?.funManager.onScreensaverStop()
    })

    // 3. 显示器休眠与唤醒
    systemObservers.append(wsCenter.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
        self?.funManager.onDisplaySleep()
    })
    systemObservers.append(wsCenter.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
        self?.funManager.onDisplayWake()
    })

    // 4. 系统睡眠与唤醒
    systemObservers.append(wsCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
        self?.funManager.onSystemSleep()
    })
    systemObservers.append(wsCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
        self?.funManager.onSystemWake()
    })
}
```

- [ ] **步骤 4：运行测试验证通过**

运行：`xcodebuild test -scheme NotchDrop -destination 'platform=macOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -only-testing:NotchEveryTests/GuardStoreTests/testSystemScreenLockedNotificationTriggersManager`
预期：PASS。

- [ ] **步骤 5：Commit**

```bash
git add NotchDrop/GuardStore.swift Tests/GuardStoreTests.swift
git commit -m "fix(guard): 完整接入 DistributedNotificationCenter 与 NSWorkspace 系统生命周期通知"
```

---

### 任务 2：修复 RSSI 阈值重启恢复与非破坏性级联联动（P0）

**文件：**
- 修改：`NotchDrop/GuardStore.swift:195-205`
- 修改：`NotchDrop/FUnManager.swift:230-240`
- 修改：`NotchDrop/FUn.swift:150-160`
- 测试：`Tests/GuardStoreTests.swift`

- [ ] **步骤 1：编写失败的单元测试**

测试 RSSI 阈值持久化恢复与倒挂保护：
```swift
func testThresholdsRestoredFromConfigStoreOnStart() {
    ConfigStore.shared.set(-55, forKey: "unlockRSSI")
    ConfigStore.shared.set(-75, forKey: "lockRSSI")
    let store = GuardStore.shared
    store.restoreThresholds()
    XCTAssertEqual(store.unlockRSSI, -55)
    XCTAssertEqual(store.lockRSSI, -75)
}

func testSetUnlockRSSIDoesNotOverwriteLockRSSIUnlessInverted() {
    let manager = FUnManager()
    manager.setLockRSSI(-75)
    manager.setUnlockRSSI(-65)
    // 之前会由于 -20 gap 被强行改成 -85，现在应保留 -75
    XCTAssertEqual(manager.lockRSSI, -75)
    // 倒挂测试：unlock 降到 -74 时，lock 必须自适应下调到 -76
    manager.setUnlockRSSI(-74)
    XCTAssertEqual(manager.lockRSSI, -76)
}
```

- [ ] **步骤 2：运行测试验证失败**

运行测试，验证旧逻辑会将 `lockRSSI` 覆盖为 `-20` 且恢复逻辑缺失。

- [ ] **步骤 3：实现持久化恢复与非破坏性阈值级联**

1. 在 `GuardStore.swift` 的 `restoreDevice()` 和 `start()` 中补充恢复逻辑：
```swift
func restoreThresholds() {
    let savedUnlock = config.get("unlockRSSI", fallback: -60)
    let savedLock = config.get("lockRSSI", fallback: -80)
    funManager.setUnlockRSSI(savedUnlock)
    funManager.setLockRSSI(savedLock)
    self.unlockRSSI = savedUnlock
    self.lockRSSI = savedLock
}
```
2. 重构 `FUnManager.swift:230-240` 中的 `setUnlockRSSI`：
```swift
func setUnlockRSSI(_ value: Int) {
    unlockRSSI = value
    fun.unlockRSSI = value
    ConfigStore.shared.set(value, forKey: "unlockRSSI")
    if value != FUn.UNLOCK_DISABLED {
        // 仅在 lockRSSI 与 unlockRSSI 倒挂冲突（lock >= unlock - 1）时，才强制下调锁定阈值
        if lockRSSI >= value - 1 {
            setLockRSSI(max(value - 2, -95))
        }
    }
}
```

- [ ] **步骤 4：运行测试验证通过**

运行单元测试，确认全部通过。

- [ ] **步骤 5：Commit**

```bash
git add NotchDrop/GuardStore.swift NotchDrop/FUnManager.swift Tests/GuardStoreTests.swift
git commit -m "fix(guard): 修复应用启动时 RSSI 阈值恢复逻辑并优化阈值互锁级联"
```

---

### 任务 3：修复 Hardened Runtime 下 iMessage 权限与跨进程调用（P1）

**文件：**
- 修改：`NotchDrop/NotchDrop.entitlements`
- 修改：`NotchDrop/Info.plist`
- 修改：`NotchDrop/iMessageNotifier.swift:180-200`
- 测试：`Tests/iMessageNotifierTests.swift`

- [ ] **步骤 1：在 Entitlements 与 Info.plist 中添加 AppleEvents 自动化授权**

1. 在 `NotchDrop/NotchDrop.entitlements` 中新增：
```xml
<key>com.apple.security.automation.apple-events</key>
<true/>
```
2. 在 `NotchDrop/Info.plist` 中新增：
```xml
<key>NSAppleEventsUsageDescription</key>
<string>NotchEvery 需要控制“信息”应用，以便在检测到锁屏异常或离席事件时向您的设备发送安全告警通知。</string>
```

- [ ] **步骤 2：优化 AppleScript 执行容错与友好文案**

在 `NotchDrop/iMessageNotifier.swift` 中：
1. 修正文案中的 `Funlock` 旧名字为 `NotchEvery`；
2. 捕获 `-1743`（未授权）、`-1728`（联系人未找到或未建立过会话）提供明确指引：
```swift
static func friendlyError(number: Int, message: String) -> String {
    if number == -1743 {
        return "“信息”应用未授权：请在「系统设置 → 隐私与安全性 → 自动化」中允许 NotchEvery 控制“信息”应用"
    }
    if number == -1728 || message.localizedCaseInsensitiveContains("buddy") {
        return "收件人未建立会话：请先在 Mac 的“信息”应用中与该联系人互发一条消息"
    }
    return "发送失败：\(message)（错误码 \(number)）"
}
```

- [ ] **步骤 3：编写单测验证错误解析**

在 `Tests/iMessageNotifierTests.swift` 中断言 `-1743` 和 `-1728` 返回正确的指导文案，且文案中包含 `NotchEvery`。

- [ ] **步骤 4：运行测试验证通过**

运行：`xcodebuild test -scheme NotchDrop -destination 'platform=macOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -only-testing:NotchEveryTests/iMessageNotifierTests`
预期：PASS。

- [ ] **步骤 5：Commit**

```bash
git add NotchDrop/NotchDrop.entitlements NotchDrop/Info.plist NotchDrop/iMessageNotifier.swift Tests/iMessageNotifierTests.swift
git commit -m "fix(security): 补齐 AppleEvents 自动化权限声明并修正 iMessage 错误提示"
```

---

### 任务 4：第三页守护控制台重构：剔除假开关并补齐双控闭环（P1）

**文件：**
- 修改：`NotchDrop/GuardControlZoneView.swift`
- 修改：`NotchDrop/GuardCardView.swift`

- [ ] **步骤 1：Header 区域补充总控与真执行开关**

在 `GuardControlZoneView.swift` 的 `header` 中，在右侧设备摘要旁加入微型操作开关：
```swift
HStack(spacing: 8) {
    // 现有的雷达呼吸点与状态文字...
    Spacer(minLength: 4)
    Text("真执行")
        .font(.system(size: 11))
        .foregroundStyle(Color.white.opacity(0.52))
    Toggle("", isOn: Binding(
        get: { store.realExecution },
        set: { store.realExecution = $0 }
    ))
    .labelsHidden()
    .toggleStyle(.switch)
    .controlSize(.mini)
    
    Toggle("", isOn: Binding(
        get: { store.enabled },
        set: { store.enabled = $0 }
    ))
    .labelsHidden()
    .toggleStyle(.switch)
    .controlSize(.mini)
}
```

- [ ] **步骤 2：下线 `pauseItunes` 假开关并替换为真实高频开关**

将 2×2 网格中的“离开暂停音乐”替换为已在底层深度支持的“屏保替代熄屏 (`screensaver`)”：
```swift
HStack(spacing: 12) {
    toggleItem("接近唤醒屏幕", isOn: $wakeOnProximity)
    toggleItem("离开立即熄屏", isOn: $sleepDisplay)
}
HStack(spacing: 12) {
    toggleItem("屏保替代熄屏", isOn: $screensaver)
    toggleItem("键鼠活动保护", isOn: $lockOnIdle)
}
```

- [ ] **步骤 3：修复 toggleItem 整卡点击与 Toggle 控件双重冲突**

给内部的 `Toggle` 添加 `.allowsHitTesting(false)`，统一由外层卡片的 `.onTapGesture` 独占响应点击，消除状态弹回原状的 bug。

- [ ] **步骤 4：优化雷达呼吸动画生命周期**

不再在 `onAppear` 中永久 repeatForever，改为在切换出视图或刘海收起时重置状态，防止后台空耗 CPU/GPU。

- [ ] **步骤 5：验证构建与渲染**

运行 `xcodebuild -scheme NotchDrop -destination 'platform=macOS' build` 确保无编译错误。

- [ ] **步骤 6：Commit**

```bash
git add NotchDrop/GuardControlZoneView.swift
git commit -m "feat(ui): 守护控制台补齐总控开关、下线假开关并优化手势命中"
```

---

### 任务 5：独立偏好设置大窗口交互打磨与防呆加固（P2）

**文件：**
- 修改：`NotchDrop/PreferencesWindow.swift`
- 修改：`NotchDrop/PreferencesWindowController.swift`
- 修改：`NotchDrop/TrayDrop.swift`

- [ ] **步骤 1：偏好设置锁定 Tab 移除 `pauseItunes` 假开关**

在 `PreferencesWindow.swift:333-376` (`LockSettingsTab`) 中删除“锁屏时暂停媒体播放”Toggle 及其说明文案，保持界面与底层能力的 100% 诚实。

- [ ] **步骤 2：暂存区自定义时长输入防呆**

1. 在 `PreferencesWindow.swift:215` 为 `TextField` 的 `NumberFormatter` 设置 `minimum = 1`，`maximum = 999`；
2. 在 `TrayDrop.swift` 计算保留间隔时增加安全保护：`max(customStorageTime, 1)`，防止用户输入 0 或负数导致文件被瞬间物理清空。

- [ ] **步骤 3：测距校准 Tab 增加一键恢复出厂推荐阈值按钮**

在 `CalibrationSettingsTab` 卡片右上角增加“恢复默认”操作按钮：
```swift
Button("恢复推荐值") {
    withAnimation(StudioAnimation.interactiveSpring) {
        store.setUnlockRSSI(-60)
        store.setLockRSSI(-70)
    }
}
.font(.system(size: 11))
.buttonStyle(.plain)
.foregroundStyle(Color.accentColor)
```

- [ ] **步骤 4：诊断日志清空历史增加二次确认防误触 Alert**

为清空按钮添加 `.confirmationDialog` 或 `.alert`，确认后才执行 `logger.clear()`。

- [ ] **步骤 5：偏好设置窗口设置最小尺寸约束**

在 `PreferencesWindowController.swift:15-27` 中显式设置：
```swift
window.minSize = NSSize(width: 650, height: 440)
```
防止用户拖拽窗口至过小尺寸导致 NavigationSplitView 挤压错位。

- [ ] **步骤 6：全量测试套件验证**

运行项目全量单元测试与构建验证：
```bash
xcodebuild test -scheme NotchDrop -destination 'platform=macOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

- [ ] **步骤 7：Commit**

```bash
git add NotchDrop/PreferencesWindow.swift NotchDrop/PreferencesWindowController.swift NotchDrop/TrayDrop.swift
git commit -m "fix(preferences): 强化偏好设置交互防呆、增加出厂阈值恢复并约束窗口尺寸"
```

---

### 任务 6：全量回归与真实运行验证（P0）

**文件：**
- 全量工程

- [ ] **步骤 1：全量编译验证**
运行：`xcodebuild -scheme NotchDrop -destination 'platform=macOS' -configuration Release CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO clean build`
确保编译零错误。

- [ ] **步骤 2：全量单元测试验证**
运行全量测试用例，确保全部通过。

- [ ] **步骤 3：安装并在本地启动最新构建**
部署到应用目录并运行，供真机交互过目。
