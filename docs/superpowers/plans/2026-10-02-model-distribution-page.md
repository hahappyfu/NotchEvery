# 第一页：今日模型用量与分布实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 subagent-driven-development（推荐）或 executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 将 NotchEvery 第一页彻底替换为「今日模型用量分布」单卡片（410pt 等宽），基于 `~/.cc-switch/cc-switch.db` 聚合今日多模型用量，下线旧版 Antigravity 配额卡与反代看板。

**架构：** 在 `UsageStore` 扩展只读 SQLite 聚合查询，产出结构化 `ModelUsageItem` 列表与总费用；新建 `ModelDistributionCardView` 绘制多色分段比例条与模型排行行；在 `OverviewPageView` 装配并清理废弃卡片文件。

**技术栈：** Swift 5.9, SwiftUI, SQLite3 C API, XCTest

**规格：** [docs/superpowers/specs/2026-10-02-model-distribution-page-design.md](docs/superpowers/specs/2026-10-02-model-distribution-page-design.md)

## 全局约束

- 卡片宽度固定 410pt，与第二页 `TokenZoneView` 严格等宽，禁止切页尺寸抖动。
- 遵循 `DesignSystem.swift` 的 Apple Native Studio 工业级设计系统与调色板规范。
- 保留 `AntigravityStore.swift`，仅移除 `AntigravityAccountsCardView.swift` 和 `AntigravityProxyCardView.swift`。
- 测试验证使用命令：`xcodebuild test -project NotchDrop.xcodeproj -scheme NotchDrop CODE_SIGNING_ALLOWED=NO`。

---

### 任务 1：数据层扩展与聚合查询 (UsageStore)

**文件：**
- 修改：`NotchDrop/UsageStore.swift`
- 修改：`Tests/AntigravityProxyStoreTests.swift`

- [ ] **步骤 1：编写失败的测试**

在 `Tests/AntigravityProxyStoreTests.swift` 中增加针对今日模型聚合查询的单测：

```swift
    func testQueryModelUsagesAggregationAndShare() throws {
        let (url, dbOpt) = try openTempDB(fileName: "test_model_usages.sqlite")
        guard let db = dbOpt else { XCTFail("db open failed"); return }
        defer { sqlite3_close(db); try? FileManager.default.removeItem(at: url) }

        // 插入两条不同模型的数据，一条在今天，一条在昨天
        let now = todayNoonTimestamp
        let yesterday = now - 86400 * 2

        let insertSQL = """
        INSERT INTO proxy_request_logs (request_id, provider_id, app_type, model, input_tokens, output_tokens, cache_read_tokens, total_cost_usd, status_code, latency_ms, created_at)
        VALUES
        ('r1', 'p1', 'claude', 'gemini-3.8-flash', 100, 200, 700, '0.50', 200, 500, \(now)),
        ('r2', 'p1', 'claude', 'glm-5.3-flash', 50, 50, 0, '0.10', 200, 300, \(now)),
        ('r3', 'p1', 'claude', 'deepseek-flash', 1000, 1000, 0, '1.00', 200, 400, \(yesterday));
        """
        XCTAssertEqual(sqlite3_exec(db, insertSQL, nil, nil, nil), SQLITE_OK)

        let startOfDay = Int64(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970)
        let data = UsageStore.fetchData(from: url, startOfDayTimestamp: startOfDay)

        XCTAssertEqual(data.modelUsages.count, 2)
        XCTAssertEqual(data.modelUsages[0].model, "gemini-3.8-flash")
        XCTAssertEqual(data.modelUsages[0].calls, 1)
        XCTAssertEqual(data.modelUsages[0].totalTokens, 1000) // 100 + 200 + 700
        XCTAssertEqual(data.modelUsages[0].cachedTokens, 700)
        XCTAssertEqual(data.modelUsages[0].costUSD, 0.50, accuracy: 0.001)
        XCTAssertEqual(data.modelUsages[0].shareFraction, 1000.0 / 1100.0, accuracy: 0.01)

        XCTAssertEqual(data.modelUsages[1].model, "glm-5.3-flash")
        XCTAssertEqual(data.modelUsages[1].totalTokens, 100)
        XCTAssertEqual(data.modelUsages[1].shareFraction, 100.0 / 1100.0, accuracy: 0.01)
        XCTAssertEqual(data.totalCostTodayUSD, 0.60, accuracy: 0.001)
    }
```

- [ ] **步骤 2：运行测试验证失败**

运行：`xcodebuild test -project NotchDrop.xcodeproj -scheme NotchDrop -only-testing:NotchEveryTests/AntigravityProxyStoreTests/testQueryModelUsagesAggregationAndShare CODE_SIGNING_ALLOWED=NO 2>&1 | tail -10`
预期：编译失败，提示 `modelUsages` / `totalCostTodayUSD` 未定义。

- [ ] **步骤 3：在 UsageStore.swift 中实现模型聚合**

1. 在 `UsageStore.swift` 增加数据结构：
```swift
public struct ModelUsageItem: Identifiable, Equatable {
    public var id: String { model }
    public let model: String
    public let calls: Int
    public let totalTokens: Int
    public let cachedTokens: Int
    public let costUSD: Double
    public let shareFraction: Double

    public init(
        model: String,
        calls: Int,
        totalTokens: Int,
        cachedTokens: Int,
        costUSD: Double,
        shareFraction: Double
    ) {
        self.model = model
        self.calls = calls
        self.totalTokens = totalTokens
        self.cachedTokens = cachedTokens
        self.costUSD = costUSD
        self.shareFraction = shareFraction
    }
}
```
2. 在 `UsageData` 中增加字段：
```swift
public var modelUsages: [ModelUsageItem] = []
public var totalCostTodayUSD: Double = 0.0
```
3. 在 `UsageStore` 主类中增加 `@Published` 属性并在 `fetch()` 中赋值：
```swift
@Published public private(set) var modelUsages: [ModelUsageItem] = []
@Published public private(set) var totalCostTodayUSD: Double = 0.0
```
4. 实现 `queryModelUsages(_ db: OpaquePointer, startOfDayTimestamp: Int64) -> (items: [ModelUsageItem], totalCost: Double)`：
执行 SQL 查询，计算全天总 Token 并按占比分配 `shareFraction`。

- [ ] **步骤 4：运行测试验证通过**

运行：`xcodebuild test -project NotchDrop.xcodeproj -scheme NotchDrop CODE_SIGNING_ALLOWED=NO 2>&1 | tail -10`
预期：TEST SUCCEEDED。

- [ ] **步骤 5：Commit**

```bash
git add NotchDrop/UsageStore.swift Tests/AntigravityProxyStoreTests.swift
git commit -m "feat(usage): UsageStore 新增今日模型用量与分布数据聚合查询"
```

---

### 任务 2：创建今日模型分布卡片视图 (ModelDistributionCardView)

**文件：**
- 创建：`NotchDrop/ModelDistributionCardView.swift`
- 修改：`NotchDrop.xcodeproj/project.pbxproj`

- [ ] **步骤 1：创建 ModelDistributionCardView.swift 源码**

实现包含多色分段比例条、模型排行明细列表、费用汇总 Footer 的完整视图组件：
- 宽度锁定 410pt。
- 顶部 Header 显示今日活跃状态与总 Token。
- 分段条根据 `modelUsages` 的 `shareFraction` 计算几何宽度，映射 4 组 Studio 配色（绿、青蓝、紫罗兰、琥珀金）。
- 列表支持悬停微高亮、友好模型名胶囊展示。
- 当 `modelUsages.isEmpty` 时展示优雅的空状态文案。

- [ ] **步骤 2：将新文件添加至 Xcode 项目工程**

运行 Python 脚本或 `scripts/add_file_to_project.py`，向 `NotchDrop.xcodeproj/project.pbxproj` 注入 `ModelDistributionCardView.swift` 引用和构建文件。

- [ ] **步骤 3：编译并运行全量单测验证构建无误**

运行：`xcodebuild test -project NotchDrop.xcodeproj -scheme NotchDrop CODE_SIGNING_ALLOWED=NO 2>&1 | tail -10`
预期：TEST SUCCEEDED。

- [ ] **步骤 4：Commit**

```bash
git add NotchDrop/ModelDistributionCardView.swift NotchDrop.xcodeproj/project.pbxproj
git commit -m "feat(ui): 新增 ModelDistributionCardView 今日模型用量分布卡片"
```

---

### 任务 3：第一页视图集成与旧组件下线清理

**文件：**
- 修改：`NotchDrop/OverviewPageView.swift`
- 删除：`NotchDrop/AntigravityAccountsCardView.swift`
- 删除：`NotchDrop/AntigravityProxyCardView.swift`
- 修改：`NotchDrop.xcodeproj/project.pbxproj`

- [ ] **步骤 1：更新 OverviewPageView.swift**

将 `OverviewPageView.swift` 的 body 替换为纯净的 `ModelDistributionCardView(vm: vm)`，移除对两张旧卡片的引用。

- [ ] **步骤 2：删除旧卡片并清理 project.pbxproj**

删除 `NotchDrop/AntigravityAccountsCardView.swift` 和 `NotchDrop/AntigravityProxyCardView.swift`。
在 `project.pbxproj` 中移除两文件的 PBXBuildFile、PBXFileReference 以及 PBXGroup 项。

- [ ] **步骤 3：运行全量编译与单测确认无遗留引用**

运行：`xcodebuild test -project NotchDrop.xcodeproj -scheme NotchDrop CODE_SIGNING_ALLOWED=NO 2>&1 | tail -15`
预期：TEST SUCCEEDED，所有测试通过。

- [ ] **步骤 4：Commit**

```bash
git add -A
git commit -m "refactor(views): 第一页全面切换为模型用量分布卡，下线旧版 Antigravity 看板卡片"
```
