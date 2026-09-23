# 第一页 5h/周额度双轨切换、第三页网关缓存命中率修正与剪贴板体验加固实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 subagent-driven-development（推荐）或 executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 实现第一页 Antigravity 账号 5h 额度优先与耗尽自动降级周额度展示、修正第三页网关缓存命中率公式，并加固剪贴板图片一次性粘贴成功率、内联清空确认及多条置顶（Pin）免淘汰功能。

**架构：**
1. `QoderLogParser.swift`：将缓存命中率计算修正为标准公式 `cached / tokensIn`。
2. `AntigravityStore.swift`：归一化提取 5h 短周期（Claude/GPT）与周长周期（Gemini）双轨配额，提供 `QuotaDisplayTier` 状态机。
3. `AntigravityAccountsCardView.swift`：圆环显示当前生效额度，降级周额度时点亮琥珀色「周额度」微标并格式化天级倒计时。
4. `ClipboardPaster.swift`：图片写回剪贴板时同时注入 PNG 二进制与 NSImage，并将注入延迟优化至 120ms，保障 100% 单次点击粘贴成功。
5. `ClipboardStore.swift` & `ClipboardZoneView.swift`：支持 `isPinned: Bool` 置顶与 50 条上限免死金牌淘汰保护，顶栏改用原地内联清空确认彻底消灭系统弹窗遮挡。

**技术栈：** Swift 5.9, SwiftUI, AppKit (NSPasteboard, NSHapticFeedbackManager, CGEvent), XCTest.

**规格：** [docs/superpowers/specs/2026-09-23-five-hour-and-weekly-quota-fallback-design.md](docs/superpowers/specs/2026-09-23-five-hour-and-weekly-quota-fallback-design.md)

## 全局约束

- 构建/测试姿势约束：必须使用 `xcodebuild -project NotchDrop.xcodeproj -scheme NotchDrop -derivedDataPath /tmp/nDD CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO` 姿势执行，绝不使用 `-target`。
- 零弹窗约束：绝不允许在面板出现时主动弹出任何系统授权窗口或居中模态遮挡弹窗。
- 零外部依赖：纯原生 Swift / AppKit / SwiftUI 机制，严禁引入未授权第三方库。
- 连续性约束：剪贴板各项操作（点击粘贴、置顶、内联清空确认）绝不关闭刘海窗口。

---

### 任务 1：第三页网关缓存命中率计算修正（QoderLogParser）

**文件：**
- 修改：`NotchDrop/QoderLogParser.swift:94-105`
- 修改：`Tests/QoderLogParserTests.swift:135-144`

- [ ] **步骤 1：编写失败测试用例**

在 `Tests/QoderLogParserTests.swift` 中修改 `testDailyAggCacheRateFormula`：
```swift
    func testDailyAggCacheRateFormula() {
        var agg = QoderAggregator()
        agg.apply(events: [
            // inTokens 是包含 cached 的总输入：inTokens=100, cached=80 -> 缓存率 80 / 100 = 80%
            QoderUsageEvent(dateString: "2026-09-21", model: "a", inTokens: 100, outTokens: 20, cached: 80, reasoning: 0, total: 120, credits: 0.1),
        ], today: "2026-09-21")
        // 标准口径：cacheRate = cached / inTokens = 80/100 = 0.8
        XCTAssertEqual(agg.today.cacheRateFraction, 0.8, accuracy: 1e-9)
    }
```

- [ ] **步骤 2：运行测试验证失败**

运行：
`xcodebuild test -project NotchDrop.xcodeproj -scheme NotchDrop -derivedDataPath /tmp/nDD CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO -only-testing:NotchEveryTests/QoderLogParserTests`
预期：FAIL（计算得 80 / 180 ≈ 0.4444 != 0.8）

- [ ] **步骤 3：编写最小实现修正**

在 `NotchDrop/QoderLogParser.swift` 中更新 `QoderDailyAgg.cacheRateFraction`：
```swift
struct QoderDailyAgg: Equatable {
    var calls: Int = 0
    var tokensIn: Int = 0
    var tokensOut: Int = 0
    var cached: Int = 0
    var credits: Double = 0

    /// cacheRate 口径：cached / tokensIn（tokensIn 包含 cached）
    var cacheRateFraction: Double {
        tokensIn > 0 ? min(1.0, max(0.0, Double(cached) / Double(tokensIn))) : 0
    }
}
```

- [ ] **步骤 4：运行测试验证通过**

运行：
`xcodebuild test -project NotchDrop.xcodeproj -scheme NotchDrop -derivedDataPath /tmp/nDD CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO -only-testing:NotchEveryTests/QoderLogParserTests`
预期：PASS

- [ ] **步骤 5：Commit**

```bash
git add NotchDrop/QoderLogParser.swift Tests/QoderLogParserTests.swift
git commit -m "fix(gateway): 修正网关缓存命中率计算公式为 cached/inTokens 标准口径"
```

---

### 任务 2：第一页 Antigravity 5h 额度优先与耗尽自动切换周额度数据层（AntigravityStore）

**文件：**
- 修改：`NotchDrop/AntigravityStore.swift:18-38`
- 修改：`NotchDrop/AntigravityStore.swift:360-400`
- 测试：`Tests/AntigravityStoreTests.swift`

- [ ] **步骤 1：编写 5h 优先与周额度降级测试**

在 `Tests/AntigravityStoreTests.swift` 中添加：
```swift
    func testParseAccountDualTierQuotas() {
        let json = """
        {
            "id": "acc1",
            "email": "test@example.com",
            "quota": {
                "models": [
                    { "name": "claude-sonnet-4-6", "percentage": 85, "reset_time": "2026-09-23T18:00:00Z" },
                    { "name": "gemini-3.8-flash-tiered", "percentage": 25, "reset_time": "2026-09-30T00:00:00Z" }
                ]
            }
        }
        """.data(using: .utf8)!

        let acc = AntigravityStore.parseAccountFile(data: json, currentAccountId: nil)!
        XCTAssertEqual(acc.currentTier, .fiveHour)
        XCTAssertEqual(acc.displayPercentage, 85)

        // 模拟 5h 额度耗尽（0%）
        let jsonExhausted = """
        {
            "id": "acc2",
            "email": "test@example.com",
            "quota": {
                "models": [
                    { "name": "claude-sonnet-4-6", "percentage": 0, "reset_time": "2026-09-23T18:00:00Z" },
                    { "name": "gemini-3.8-flash-tiered", "percentage": 25, "reset_time": "2026-09-30T00:00:00Z" }
                ]
            }
        }
        """.data(using: .utf8)!
        let acc2 = AntigravityStore.parseAccountFile(data: jsonExhausted, currentAccountId: nil)!
        XCTAssertEqual(acc2.currentTier, .weekly)
        XCTAssertEqual(acc2.displayPercentage, 25)
    }
```

- [ ] **步骤 2：运行测试验证失败**

运行：
`xcodebuild test -project NotchDrop.xcodeproj -scheme NotchDrop -derivedDataPath /tmp/nDD CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO -only-testing:NotchEveryTests/AntigravityStoreTests`
预期：FAIL

- [ ] **步骤 3：编写 AntigravityStore 双轨实现**

在 `NotchDrop/AntigravityStore.swift` 中：
1. `AntigravityAccount` 扩展 `fiveHourPercentage: Int?`、`fiveHourResetTime: Date?`、`weeklyPercentage: Int`、`weeklyResetTime: Date?`，并提供 `currentTier`、`displayPercentage`、`displayResetTime`。
2. `parseAccountFile` 时分别提取 Claude/短周期模型与 Gemini/周模型数据。

- [ ] **步骤 4：运行测试验证通过**

运行：
`xcodebuild test -project NotchDrop.xcodeproj -scheme NotchDrop -derivedDataPath /tmp/nDD CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO -only-testing:NotchEveryTests/AntigravityStoreTests`
预期：PASS

- [ ] **步骤 5：Commit**

```bash
git add NotchDrop/AntigravityStore.swift Tests/AntigravityStoreTests.swift
git commit -m "feat(antigravity): 实现 5h 短周期额度优先与耗尽自动切换周额度数据层"
```

---

### 任务 3：第一页 3D 账号圆环卡片支持「周额度」微标与天级倒计时呈现

**文件：**
- 修改：`NotchDrop/AntigravityAccountsCardView.swift:270-325`

- [ ] **步骤 1：修改 AntigravityAccountsCardView 卡片排版**

在 `accountColumn(_ account: AntigravityAccount)` 中：
1. 环形百分比文本绑定 `account.displayPercentage`，圆环填充分母绑定 `account.displayPercentage`；
2. 如果 `account.currentTier == .weekly`，在圆环顶部或右上角展示精致的琥珀色微标 `Text("周额度").font(.system(size: 8, weight: .semibold)).padding(.horizontal, 4).padding(.vertical, 1).background(StudioColor.amber.opacity(0.16), in: Capsule()).foregroundStyle(StudioColor.amber)`；
3. 底部倒计时文字使用 `account.displayResetCountdownText`（若为周额度显示如 `周重置 4d2h`）。

- [ ] **步骤 2：全量构建验证**

运行：
`xcodebuild -project NotchDrop.xcodeproj -scheme NotchDrop -configuration Debug -derivedDataPath /tmp/nDD build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO`
预期：BUILD SUCCEEDED

- [ ] **步骤 3：Commit**

```bash
git add NotchDrop/AntigravityAccountsCardView.swift
git commit -m "feat(ui): 在第一页账号卡片呈现周额度降级微标与天级倒计时"
```

---

### 任务 4：剪贴板图片一次性粘贴成功时序加固与多格式写入（ClipboardPaster）

**文件：**
- 修改：`NotchDrop/ClipboardPaster.swift:85-135`
- 修改：`Tests/ClipboardPasterTests.swift`

- [ ] **步骤 1：在测试中追加 PNG 原始数据与 NSImage 双写断言**

检查并更新 `Tests/ClipboardPasterTests.swift`：
断言写入图片时，`pasteboard.data(forType: .png)` 与 `pasteboard.readObjects(forClasses: [NSImage.self])` 均非空。

- [ ] **步骤 2：加固 ClipboardPaster 实现**

在 `NotchDrop/ClipboardPaster.swift` 中：
1. 写回图片时同时提供 `pb.setData(pngData, forType: .png)` 和 `pb.writeObjects([image])`；
2. 注入按键延迟从 `0.06s` 放宽至 `0.12s`（120ms），给系统目标应用充足的前台激活时间窗口；
3. 增加 `guard !target.isTerminated else { return }` 防护。

- [ ] **步骤 3：运行测试验证通过**

运行：
`xcodebuild test -project NotchDrop.xcodeproj -scheme NotchDrop -derivedDataPath /tmp/nDD CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO -only-testing:NotchEveryTests/ClipboardPasterTests`
预期：PASS

- [ ] **步骤 4：Commit**

```bash
git add NotchDrop/ClipboardPaster.swift Tests/ClipboardPasterTests.swift
git commit -m "fix(clipboard): 双写 PNG 原始数据并放宽激活延迟至 120ms 保障一次粘贴成功"
```

---

### 任务 5：剪贴板多条置顶（Pin）功能与 50 条淘汰豁免保护（ClipboardStore & ClipboardZoneView）

**文件：**
- 修改：`NotchDrop/ClipboardStore.swift:9-38`
- 修改：`NotchDrop/ClipboardStore.swift:70-145`
- 修改：`NotchDrop/ClipboardZoneView.swift:150-240`
- 测试：`Tests/ClipboardStoreTests.swift`

- [ ] **步骤 1：编写置顶与豁免淘汰单测**

在 `Tests/ClipboardStoreTests.swift` 中编写测试：
```swift
    func testTogglePinPreservesItemAcrossEviction() {
        store.addText("Important Item")
        guard let id = store.items.first?.id else { return XCTFail() }
        store.togglePin(id: id)
        XCTAssertTrue(store.items.first?.isPinned == true)

        // 插入 55 条新项目
        for i in 0..<55 {
            store.addText("Normal Item \(i)")
        }

        // 置顶项目即使超出 50 条上限，也绝对不被淘汰，且保持在最顶部
        XCTAssertEqual(store.items.count, 50)
        XCTAssertTrue(store.items.contains { $0.id == id })
        XCTAssertEqual(store.items.first?.id, id, "置顶项应始终排在最前面")
    }
```

- [ ] **步骤 2：运行测试验证失败**

运行：
`xcodebuild test -project NotchDrop.xcodeproj -scheme NotchDrop -derivedDataPath /tmp/nDD CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO -only-testing:NotchEveryTests/ClipboardStoreTests`
预期：FAIL

- [ ] **步骤 3：编写置顶与免淘汰实现**

1. `ClipboardItem` 增加 `public var isPinned: Bool = false`；
2. `ClipboardStore` 增加 `togglePin(id: UUID)`；
3. `insertItem` 淘汰时遍历排除 `isPinned == true` 项，仅移除最老未置顶条目；
4. 列表排序：`isPinned == true` 项按置顶时间置顶，普通项在其后；
5. `ClipboardRowView` 悬停展示图钉图标，点击切换置顶态，置顶时图钉高亮常驻。

- [ ] **步骤 4：运行测试验证通过**

运行：
`xcodebuild test -project NotchDrop.xcodeproj -scheme NotchDrop -derivedDataPath /tmp/nDD CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO -only-testing:NotchEveryTests/ClipboardStoreTests`
预期：PASS

- [ ] **步骤 5：Commit**

```bash
git add NotchDrop/ClipboardStore.swift NotchDrop/ClipboardZoneView.swift Tests/ClipboardStoreTests.swift
git commit -m "feat(clipboard): 支持多条内容置顶与 50 条自动淘汰豁免保护"
```

---

### 任务 6：剪贴板内联清空确认（消灭系统弹窗遮挡）

**文件：**
- 修改：`NotchDrop/ClipboardZoneView.swift:40-75`

- [ ] **步骤 1：重构清空操作为原地内联确认胶囊**

在 `ClipboardZoneView.swift` 中：
1. 引入 `@State private var isConfirmingClear = false`；
2. 彻底删除 `confirmClear()` 中的 `NSAlert` 模态弹窗调用；
3. 点击「清空」时，原地动画平滑展开为 `HStack(spacing: 4) { Button("确认清空") { store.clearAll(); isConfirmingClear = false }, Button("取消") { isConfirmingClear = false } }`；
4. 附带 3 秒后未操作自动收起动画复位。

- [ ] **步骤 2：全量构建验证**

运行：
`xcodebuild -project NotchDrop.xcodeproj -scheme NotchDrop -configuration Debug -derivedDataPath /tmp/nDD build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO`
预期：BUILD SUCCEEDED

- [ ] **步骤 3：Commit**

```bash
git add NotchDrop/ClipboardZoneView.swift
git commit -m "fix(ui): 剪贴板清空采用原地内联确认，彻底消灭系统弹窗被刘海遮挡问题"
```

---

### 任务 7：全工程构建、全量回归测试通过与真机部署验证

- [ ] **步骤 1：全量运行测试套件**

运行：
`xcodebuild test -project NotchDrop.xcodeproj -scheme NotchDrop -derivedDataPath /tmp/nDD CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO`
预期：ALL 274+ TESTS SUCCEEDED (0 failures)

- [ ] **步骤 2：编译安装并部署至系统应用目录重启**

运行：
```bash
xcodebuild -project NotchDrop.xcodeproj -scheme NotchDrop -configuration Debug -derivedDataPath /tmp/nDD build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO && \
pkill -x NotchEvery || true && \
sleep 1 && \
rm -rf /Applications/NotchEvery.app && \
cp -R /tmp/nDD/Build/Products/Debug/NotchEvery.app /Applications/ && \
open /Applications/NotchEvery.app
```
预期：NotchEvery 成功启动并运行。
