# 灵动岛 UI 深度打磨与 Antigravity 3D 众星捧月舞台实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 subagent-driven-development（推荐）或 executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 实现 Antigravity 账号池 3D 众星捧月环形舞台与点击切换，根治超长倒计时截断，彻底解耦首页与第三页双开关文案标签，并修复 TokenZoneView 顶部摘要栏排版挤压。

**架构：**
- 数据层：`AntigravityStore` 扩展 `selectAccount(id:)` 持久化切换能力与长周期倒计时紧凑格式化。
- UI 展示层：`AntigravityAccountsCardView` 实现五元素对称重排算法，利用原生 `rotation3DEffect`、`scaleEffect`、`brightness` 和 `shadow` 渲染 3D 环形内扣舞台。
- 控件与布局层：`GuardCardView` 与 `GuardControlZoneView` 明确分立独立文案标签，第三页顶栏精简防截断；`TokenZoneView` 拆解错位的单行嵌套为舒展的双行 `VStack`。

**技术栈：** macOS 13+ / Swift 5.9 / SwiftUI 4.0 / CoreAnimation 3D Transforms / XCTest

**规格：** [docs/superpowers/specs/2026-09-15-center-stage-and-ui-polish-design.md](docs/superpowers/specs/2026-09-15-center-stage-and-ui-polish-design.md)

## 全局约束

- 严禁引入第三方 UI 库，纯 SwiftUI 与 CoreAnimation 硬件加速。
- 遵循 Apple Native Studio 工业级设计系统，保持极暗黑毛玻璃风格与语义色体系。
- 保持所有已有 417+ 项测试 100% 通过，无回归。

---

### 任务 1：AntigravityStore 紧凑倒计时格式化与账号切换支持

**文件：**
- 修改：`NotchDrop/AntigravityStore.swift`
- 测试：`Tests/AntigravityStoreTests.swift`

- [ ] **步骤 1：编写倒计时紧凑格式化与切换账号测试**

在 `Tests/AntigravityStoreTests.swift` 中添加对超长倒计时（>=48小时显示天数如 `6d5h`、24-48小时显示小时如 `36h`）与 `selectAccount(id:)` 的单测。

```swift
    func testFormatCountdownCompact() {
        let now = Date(timeIntervalSince1970: 1789370000)
        // 149小时20分 -> 格式化为 6d5h
        let longFuture = Date(timeIntervalSince1970: 1789370000 + 149 * 3600 + 20 * 60)
        XCTAssertEqual(AntigravityStore.formatCountdown(from: longFuture, now: now), "6d5h")

        // 36小时10分 -> 格式化为 36h
        let midFuture = Date(timeIntervalSince1970: 1789370000 + 36 * 3600 + 10 * 60)
        XCTAssertEqual(AntigravityStore.formatCountdown(from: midFuture, now: now), "36h")

        // 3小时15分 -> 格式化为 3h15m
        let shortFuture = Date(timeIntervalSince1970: 1789370000 + 3 * 3600 + 15 * 60)
        XCTAssertEqual(AntigravityStore.formatCountdown(from: shortFuture, now: now), "3h15m")
    }
```

- [ ] **步骤 2：运行测试验证失败**

运行：`xcodebuild test -scheme NotchEvery -destination "platform=macOS" -only-testing:NotchEveryTests/AntigravityStoreTests/testFormatCountdownCompact`
预期：FAIL，输出格式不匹配。

- [ ] **步骤 3：在 AntigravityStore.swift 中实现紧凑格式化与 selectAccount**

在 `NotchDrop/AntigravityStore.swift` 中更新 `formatCountdown` 并在 `AntigravityStore` 中增加 `selectAccount(id:)`：
```swift
    public static func formatCountdown(from resetTime: Date?, now: Date = Date()) -> String {
        guard let resetTime = resetTime else { return "已就绪" }
        let diff = resetTime.timeIntervalSince(now)
        guard diff > 0 else { return "已就绪" }

        let seconds = Int(diff)
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60

        if hours >= 48 {
            let days = hours / 24
            let remHours = hours % 24
            return "\(days)d\(remHours)h"
        } else if hours >= 24 {
            return "\(hours)h"
        } else if hours > 0 {
            return "\(hours)h\(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "已就绪"
        }
    }

    public func selectAccount(id: String) {
        guard currentAccountId != id else { return }
        currentAccountId = id
        // 乐观更新内存中 isCurrent
        accounts = accounts.map { acc in
            AntigravityAccount(
                id: acc.id,
                name: acc.name,
                email: acc.email,
                isCurrent: acc.id == id,
                isDisabled: acc.isDisabled,
                percentage: acc.percentage,
                resetTime: acc.resetTime
            )
        }

        let dir = baseDir
        DispatchQueue.global(qos: .utility).async {
            let indexFile = dir.appendingPathComponent("accounts.json")
            guard let data = try? Data(contentsOf: indexFile),
                  var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }
            json["current_account_id"] = id
            if let updatedData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]) {
                try? updatedData.write(to: indexFile, options: .atomic)
            }
        }
    }
```

- [ ] **步骤 4：运行测试验证通过**

运行：`xcodebuild test -scheme NotchEvery -destination "platform=macOS" -only-testing:NotchEveryTests/AntigravityStoreTests`
预期：PASS。

- [ ] **步骤 5：Commit**

```bash
git add NotchDrop/AntigravityStore.swift Tests/AntigravityStoreTests.swift
git commit -m "feat(antigravity): 紧凑倒计时格式化与活跃账号持久化切换"
```

---

### 任务 2：TokenZoneView 顶部 KPI 摘要栏布局修复

**文件：**
- 修改：`NotchDrop/TokenZoneView.swift`
- 测试：`Tests/TokenUsageTests.swift` 或 构建编译校验

- [ ] **步骤 1：修复 summaryBar 错位的单行嵌套结构**

在 `NotchDrop/TokenZoneView.swift` 的 `summaryBar` 计算属性中，将第 2 行的 HStack 提取至外层 `VStack` 的第 2 个子项，恢复为规整的上下两行布局：
- 第 1 行：Tokens 总量（左）<---> 缓存命中率与进度条（右）
- 第 2 行：详细命中量（左）<---> 更新时间（右）

- [ ] **步骤 2：编译并验证 UI 结构**

运行：`xcodebuild build -scheme NotchEvery -destination "platform=macOS"`
预期：BUILD SUCCEEDED。

- [ ] **步骤 3：Commit**

```bash
git add NotchDrop/TokenZoneView.swift
git commit -m "fix(ui): 修复 Token 摘要栏嵌套层级恢复两行排版"
```

---

### 任务 3：GuardCardView 与 GuardControlZoneView 双开关文案解耦与顶栏防挤压

**文件：**
- 修改：`NotchDrop/GuardCardView.swift`
- 修改：`NotchDrop/GuardControlZoneView.swift`

- [ ] **步骤 1：重构 GuardCardView 右侧开关组**

在 `NotchDrop/GuardCardView.swift` 中，将并排开关更新为：
```swift
HStack(spacing: 8) {
    HStack(spacing: 4) {
        Text("守护")
            .font(.system(size: 11))
            .foregroundStyle(Color.white.opacity(0.52))
        Toggle("", isOn: Binding(
            get: { store.enabled },
            set: { store.enabled = $0 }
        ))
        .labelsHidden()
        .toggleStyle(.switch)
        .controlSize(.mini)
    }

    HStack(spacing: 4) {
        Text("真执行")
            .font(.system(size: 11))
            .foregroundStyle(Color.white.opacity(0.52))
        Toggle("", isOn: Binding(
            get: { store.realExecution },
            set: { handleRealExecutionToggle($0) }
        ))
        .labelsHidden()
        .toggleStyle(.switch)
        .controlSize(.mini)
    }
}
```

- [ ] **步骤 2：重构 GuardControlZoneView 顶栏**

在 `NotchDrop/GuardControlZoneView.swift` 中：
1. 右侧同样改为 `守护 [开关]  真执行 [开关]`。
2. 移除中间拥挤截断的 `deviceSummary`（右耳已常驻展示设备名与 RSSI），中间保留 `Spacer()`，实现清晰大气的左右两端对齐。

- [ ] **步骤 3：编译与回归测试**

运行：`xcodebuild test -scheme NotchEvery -destination "platform=macOS" -only-testing:NotchEveryTests/DiagnosticsViewTests`
预期：PASS。

- [ ] **步骤 4：Commit**

```bash
git add NotchDrop/GuardCardView.swift NotchDrop/GuardControlZoneView.swift
git commit -m "fix(ui): 解耦守护与真执行双开关文案标签并舒展顶栏布局"
```

---

### 任务 4：AntigravityAccountsCardView 3D 众星捧月立体环形舞台实现

**文件：**
- 修改：`NotchDrop/AntigravityAccountsCardView.swift`

- [ ] **步骤 1：实现对称重排纯函数与三维空间投影变换计算**

在 `NotchDrop/AntigravityAccountsCardView.swift` 中：
1. 编写纯函数 `static func symmetricRearrange(accounts: [AntigravityAccount]) -> [(account: AntigravityAccount, logicalDistance: Int)]`。
   - 当前账号居中（`logicalDistance = 0`）。
   - 其余账号按配额降序在两侧对称排布（距离分别为 `-2, -1, 1, 2`）。
2. 在 `accountColumn` 外套入 3D 空间变换 Modifier：
   - 偏转角：`Double(d) * -12.0`（外翼 `±22°`，次翼 `±12°`，中心 `0°`）。
   - 透视：`perspective: 0.45`。
   - 尺寸：中心 `scaleEffect(1.08)`，次翼 `0.95`，外翼 `0.88`。
   - 纵深：中心 `zIndex(3)`，次翼 `zIndex(2)`，外翼 `zIndex(1)`。
   - 浮空与阴影：中心 `offset(y: -3)`，深景深阴影；两侧压暗 `brightness(-0.10 * Double(abs(d)))`。
3. 添加点击交互：点击非中心账号卡片调用 `store.selectAccount(id: account.id)`，配合 `.animation(StudioAnimation.interactiveSpring, value: store.currentAccountId)` 实现平滑旋转滑入中心。
4. 倒计时徽章字号优化为 9.5pt，并添加 `.minimumScaleFactor(0.75)`。

- [ ] **步骤 2：编译项目并运行测试**

运行：`xcodebuild test -scheme NotchEvery -destination "platform=macOS"`
预期：417+ 测试全部 PASS，BUILD SUCCEEDED。

- [ ] **步骤 3：Commit**

```bash
git add NotchDrop/AntigravityAccountsCardView.swift
git commit -m "feat(antigravity): 实现 3D 众星捧月环形舞台与平滑切换交互"
```

---

### 任务 5：全量集成构建与真机安装验证

**文件：** 无文件修改（纯构建与安装验证）

- [ ] **步骤 1：运行完整单元测试套件**

运行：`xcodebuild test -scheme NotchEvery -destination "platform=macOS"`
预期：417+ 项测试 0 失败。

- [ ] **步骤 2：打包 Release 并安装到本机**

执行标准安装流程：
```bash
xcodebuild -project NotchDrop.xcodeproj -scheme NotchEvery -configuration Release -derivedDataPath build clean build
killall NotchEvery || true
codesign --force --deep --sign - build/Build/Products/Release/NotchEvery.app
rm -rf ~/Applications/NotchEvery.app
cp -R build/Build/Products/Release/NotchEvery.app ~/Applications/
open ~/Applications/NotchEvery.app
```

- [ ] **步骤 3：汇报验收与视觉过目**

提示用户真机划过刘海检查：
1. 首页 Antigravity 账号池是否呈现「当前账号居中凸起、两侧向内立体微倾」的 3D 舞台质感；
2. 点击侧翼账号是否平滑滑入中心成为当前账号；
3. 超长倒计时是否显示为 `6d5h` 无截断；
4. 首页与第三页开关是否清晰标明 `守护` 与 `真执行`；
5. 第二页 Token 摘要栏是否恢复清晰的两行排版。
