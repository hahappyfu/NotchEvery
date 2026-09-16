# 守护控制可视化滑动量程、SQLite WAL 只读修复与判定日志脱敏实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 subagent-driven-development（推荐）或 executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：**
1. 修复 `UsageStore.swift` 中 SQLite WAL 模式只读打开失败（错误码 14），恢复第 1 页反代看板与第 2 页流水数据显示。
2. 修复 `GuardControlZoneView.swift` 中 `Messages 未授权` 历史错误一直作为判定结果常驻的问题。
3. 将守护控制台的 RSSI 步进器重构为空间物理感、实时信号光标指示、带直观距离与安全互锁的可视化滑动条。

**架构：**
- 数据层：`AntigravityProxyStore` 增加 `file://...?immutable=1` 模式与 URI 打开标志，确保 WAL 并发只读零锁表。
- 逻辑层：`DecisionLogger` 过滤通道通知类事件，确保业务判定卡片只展示锁屏/解锁核心事件；提供系统自动化权限检查与跳转接口。
- UI 层：`GuardControlZoneView.swift` 封装 `GuardSignalRangeSlider`，具备实时信号光标、红绿分区与双滑块互锁。

**技术栈：** macOS 13+ / Swift 5.9 / SwiftUI / SQLite3 URI / CoreBluetooth

**规格：** [docs/superpowers/specs/2026-09-16-guard-slider-and-sqlite-wal-fix-design.md](docs/superpowers/specs/2026-09-16-guard-slider-and-sqlite-wal-fix-design.md)

---

### 任务 1：修复 SQLite WAL 模式下只读打开失败 (TDD)

**文件：**
- 修改：`NotchDrop/UsageStore.swift`
- 测试：`Tests/AntigravityProxyStoreTests.swift`

- [ ] **步骤 1：编写 WAL 模式测试**

在 `Tests/AntigravityProxyStoreTests.swift` 中编写测试用例：
创建启用 `PRAGMA journal_mode=WAL;` 的临时 SQLite 数据库并插入测试数据，验证 `AntigravityProxyStore.fetch` 在 WAL 模式下能够成功读取且不报错误码 14。

- [ ] **步骤 2：运行测试验证失败**

运行测试，验证原有逻辑在 WAL 库上复现报错。

- [ ] **步骤 3：在 AntigravityProxyStore 中使用 immutable=1 打开数据库**

在 `NotchDrop/UsageStore.swift` 的 `AntigravityProxyStore.openReadOnly` 中：
```swift
let uriString = "file://\(url.path)?immutable=1"
let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_FULLMUTEX
guard sqlite3_open_v2(uriString, &db, flags, nil) == SQLITE_OK else {
    // 降级使用普通路径打开
    let fallbackFlags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
    guard sqlite3_open_v2(url.path, &db, fallbackFlags, nil) == SQLITE_OK else {
        sqlite3_close(db)
        return nil
    }
    return db
}
```

- [ ] **步骤 4：运行测试验证通过**

运行：`xcodebuild test -project NotchDrop.xcodeproj -scheme NotchDrop -destination "platform=macOS" -only-testing:NotchEveryTests/AntigravityProxyStoreTests`
预期：PASS。

- [ ] **步骤 5：Commit**

```bash
git add NotchDrop/UsageStore.swift Tests/AntigravityProxyStoreTests.swift
git commit -m "fix(store): 修复 SQLite WAL 模式只读打开错误码 14"
```

---

### 任务 2：修复 Messages 未授权长期常驻并提纯最近判定事件

**文件：**
- 修改：`NotchDrop/GuardControlZoneView.swift`
- 测试：`Tests/DiagnosticsViewTests.swift`

- [ ] **步骤 1：提纯判定卡片事件流过滤**

在 `GuardControlZoneView.swift` 中：
过滤 `logger.events`：
```swift
private var latestCoreEvent: DecisionEvent? {
    logger.events.last(where: { event in
        // 过滤掉非锁屏核心的通道级异步通知失败
        if event.category == .system && event.reason == .iMessageFailed {
            return false
        }
        return true
    })
}
```
并将 `recentJudgementCard` 绑定到 `latestCoreEvent`。

- [ ] **步骤 2：添加系统自动化权限引导条**

若检测到最近有 `iMessageFailed` 且当前用户开启了通知，以柔和的辅助通知形式展示，并提供“去授权”按钮：
调用 `NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)`。

- [ ] **步骤 3：运行测试验证通过**

运行：`xcodebuild test -project NotchDrop.xcodeproj -scheme NotchDrop -destination "platform=macOS" -only-testing:NotchEveryTests/DiagnosticsViewTests`
预期：PASS。

- [ ] **步骤 4：Commit**

```bash
git add NotchDrop/GuardControlZoneView.swift
git commit -m "fix(guard): 提纯判定卡片过滤通知失败并增加系统授权一键直达"
```

---

### 任务 3：设计并实现空间距离与信号可视化滑动条组件

**文件：**
- 修改：`NotchDrop/GuardControlZoneView.swift`

- [ ] **步骤 1：重构 thresholdRow 为 GuardSignalRangeSlider**

在 `GuardControlZoneView.swift` 中：
1. 量程范围：`-95 ... -40`。
2. 直观语义与空间距离映射：
   - `-40 ~ -60 dBm`：靠近解锁区（贴近 ~1米内，翡翠绿）
   - `-60 ~ -80 dBm`：防抖缓冲区（中间过度）
   - `-80 ~ -95 dBm`：离开锁屏区（离座 2米以上，玫红/橙色）
3. 实时信号标针：
   - 读取 `store.rssi`，若存在且有效（如 `-43`），在标尺上方显示一个带翡翠绿微光的动态刻度游标与文本：`当前信号 -43 dBm (已在解锁区)`。
4. 双滑块交互：
   - 上滑块：调节解锁阈值（带文案 `靠近解锁: -60 dBm`）
   - 下滑块：调节锁屏阈值（带文案 `离开锁屏: -85 dBm`）
   - 包含逻辑保护：当用户拖动解锁阈值逼近锁屏阈值时，自动推进锁屏阈值，始终保持 $\ge 3\text{ dBm}$ 安全防抖间隔。

- [ ] **步骤 2：编译项目并运行全量测试**

运行：`xcodebuild test -project NotchDrop.xcodeproj -scheme NotchDrop -destination "platform=macOS"`
预期：423+ 测试全部 PASS，BUILD SUCCEEDED。

- [ ] **步骤 3：Commit**

```bash
git add NotchDrop/GuardControlZoneView.swift
git commit -m "feat(guard): 实现空间测距可视化滑动条与实时信号光标指示"
```

---

### 任务 4：全量集成构建与本地 Release 安装

**文件：** 无文件修改（构建部署）

- [ ] **步骤 1：全量回归测试**
- [ ] **步骤 2：Release 构建、签名并部署到双路径应用目录**
- [ ] **步骤 3：验证应用已成功运行并汇报用户**
