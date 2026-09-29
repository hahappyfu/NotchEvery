# 第二页用量流水全面切换为 cc-switch 数据源实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 subagent-driven-development（推荐）或 executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 将 NotchEvery 第二页（Token 专区）的数据源彻底切换至 `~/.cc-switch/cc-switch.db`，实现全量多模型调用捕获与实时统计，展示真实后端模型名称。

**架构：** 在 `NotchDrop/UsageStore.swift` 中用 `CCSwitchUsageStore` 替代原有的 `AntigravityProxyStore`。通过双模式只读探针保证 WAL 实时读取与并发安全，从 `proxy_request_logs` 聚合今日指标并提取最近 5 条真实模型请求（JOIN `providers` 获得供应商名称），主线程值级去重后发布至 UI。

**技术栈：** Swift 5.9, SwiftUI, SQLite3 C API, XCTest, macOS 13+

**规格：** `docs/superpowers/specs/2026-09-29-cc-switch-usage-store-design.md`

## 全局约束
- 数据库连接：只读安全优先，先尝试普通只读打开（`SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX`）并以 `SELECT 1 FROM sqlite_master LIMIT 1` 作为可读性探针；探针失败时平滑降级为 `file://...?immutable=1`。
- 零外部依赖：纯使用系统 `libsqlite3.tbd`，严禁引入第三方 SQLite 包装库。
- 格式化规范：Token 紧凑格式化（12.9M / 850K）、金额 `$X.XX`（不足 $0.01 保留 4 位小数）。
- 测试隔离：数据源路径可注入，单测在独立临时目录中生成 SQLite 数据库并运行。

---

### 任务 1：实现 CCSwitchUsageStore 核心查询与数据解析

**文件：**
- 修改：`NotchDrop/UsageStore.swift`
- 修改：`Tests/AntigravityProxyStoreTests.swift`

- [ ] **步骤 1：编写失败的单元测试**

在 `Tests/AntigravityProxyStoreTests.swift` 中添加针对 `CCSwitchUsageStore` 的测试用例（建表 `proxy_request_logs` 与 `providers`，插入不同模型与时间的记录并校验聚合）：

```swift
func testCCSwitchUsageStoreQueryAndSummary() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let dbURL = tempDir.appendingPathComponent("cc-switch.db")
    var db: OpaquePointer?
    XCTAssertEqual(sqlite3_open(dbURL.path, &db), SQLITE_OK)

    let createTables = """
    CREATE TABLE providers (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        app_type TEXT NOT NULL,
        is_current BOOLEAN NOT NULL DEFAULT 0
    );
    CREATE TABLE proxy_request_logs (
        request_id TEXT PRIMARY KEY,
        provider_id TEXT NOT NULL,
        app_type TEXT NOT NULL,
        model TEXT NOT NULL,
        request_model TEXT,
        input_tokens INTEGER NOT NULL DEFAULT 0,
        output_tokens INTEGER NOT NULL DEFAULT 0,
        cache_read_tokens INTEGER NOT NULL DEFAULT 0,
        total_cost_usd TEXT NOT NULL DEFAULT '0',
        status_code INTEGER NOT NULL DEFAULT 200,
        latency_ms INTEGER NOT NULL DEFAULT 1000,
        duration_ms INTEGER,
        created_at INTEGER NOT NULL
    );
    INSERT INTO providers (id, name, app_type, is_current) VALUES ('p1', '本地反代集束', 'claude-desktop', 1);
    """
    XCTAssertEqual(sqlite3_exec(db, createTables, nil, nil, nil), SQLITE_OK)

    let now = Date()
    let nowTimestamp = Int64(now.timeIntervalSince1970)
    let yesterdayTimestamp = nowTimestamp - 86400 * 2

    let insertLogs = """
    INSERT INTO proxy_request_logs 
    (request_id, provider_id, app_type, model, request_model, input_tokens, output_tokens, cache_read_tokens, total_cost_usd, status_code, latency_ms, created_at)
    VALUES 
    ('req-1', 'p1', 'claude-desktop', 'gemini-3.8-flash', 'claude-opus-5', 2000, 100, 8000, '0.015', 200, 3200, \(nowTimestamp)),
    ('req-2', 'p1', 'claude-desktop', 'Qwen3.8-Flash', 'claude-sonnet-5', 4000, 200, 6000, '0.008', 200, 1500, \(nowTimestamp - 10)),
    ('req-old', 'p1', 'claude-desktop', 'deepseek-v3', 'claude-sonnet-5', 5000, 500, 1000, '0.010', 200, 2000, \(yesterdayTimestamp));
    """
    XCTAssertEqual(sqlite3_exec(db, insertLogs, nil, nil, nil), SQLITE_OK)
    sqlite3_close(db)

    let data = CCSwitchUsageStore.fetch(dbPath: dbURL, now: now)
    XCTAssertEqual(data.providerName, "本地反代集束")
    XCTAssertEqual(data.summary.calls, "2次")
    XCTAssertEqual(data.recentRequests.count, 2)
    XCTAssertEqual(data.recentRequests[0].model, "gemini-3.8-flash")
    XCTAssertEqual(data.recentRequests[0].accountEmail, "本地反代集束")
    XCTAssertEqual(data.recentRequests[0].inputTokens, 2000)
    XCTAssertEqual(data.recentRequests[0].outputTokens, 100)
    XCTAssertEqual(data.recentRequests[0].cachedTokens, 8000)
    XCTAssertEqual(data.recentRequests[1].model, "Qwen3.8-Flash")
    XCTAssertEqual(data.footer.cacheReadTotal, 14000)
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：
`xcodebuild test -scheme NotchDrop -derivedDataPath /tmp/NotchDropDerivedData CODE_SIGNING_ALLOWED=NO -destination 'platform=macOS' -only-testing:NotchEveryTests/AntigravityProxyStoreTests/testCCSwitchUsageStoreQueryAndSummary`
预期：编译失败，报错 "Cannot find 'CCSwitchUsageStore' in scope"。

- [ ] **步骤 3：编写 CCSwitchUsageStore 实现**

在 `NotchDrop/UsageStore.swift` 中实现 `CCSwitchUsageStore`，替换 `AntigravityProxyStore`：

```swift
public enum CCSwitchUsageStore {
    public static let defaultDBPath: URL = {
        let base: URL
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            base = URL(fileURLWithPath: String(cString: dir))
        } else {
            base = FileManager.default.homeDirectoryForCurrentUser
        }
        return base.appendingPathComponent(".cc-switch/cc-switch.db")
    }()

    public static func fetch(dbPath: URL = defaultDBPath, now: Date = Date()) -> UsageData {
        guard let db = openReadOnly(dbPath) else { return .empty }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 500)

        let startOfDay = Calendar.current.startOfDay(for: now)
        let startOfDayTimestamp = Int64(startOfDay.timeIntervalSince1970)

        var data = UsageData()
        let (provName, provId) = queryCurrentProvider(db)
        data.providerName = provName
        data.providerId = provId
        data.recentRequests = queryRecent(db)
        
        // 若当前未查到 is_current 供应商，回退取最近一次请求的供应商名
        if data.providerName == nil, let latest = data.recentRequests.first {
            data.providerName = latest.accountEmail
        }

        let summaryTuple = querySummary(db, startOfDayTimestamp: startOfDayTimestamp)
        data.summary = summaryTuple.summary
        data.cacheRateFraction = summaryTuple.cacheRateFraction
        data.footer = UsageFooter(
            cacheReadTotal: summaryTuple.cacheReadTotal,
            lastRequestAt: queryLastRequestTime(db)
        )

        return data
    }

    private static func openReadOnly(_ url: URL) -> OpaquePointer? {
        var db: OpaquePointer?
        let readOnlyFlags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        var canRead = false
        if sqlite3_open_v2(url.path, &db, readOnlyFlags, nil) == SQLITE_OK {
            var probe: OpaquePointer?
            if sqlite3_prepare_v2(db, "SELECT 1 FROM sqlite_master LIMIT 1;", -1, &probe, nil) == SQLITE_OK {
                sqlite3_finalize(probe)
                canRead = true
            }
        }

        if !canRead {
            if let db = db { sqlite3_close(db) }
            db = nil
            let uriFlags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_FULLMUTEX
            guard sqlite3_open_v2("file://\(url.path)?immutable=1", &db, uriFlags, nil) == SQLITE_OK else {
                return nil
            }
        }
        sqlite3_exec(db, "PRAGMA query_only = ON;", nil, nil, nil)
        return db
    }

    private static func prepare(_ db: OpaquePointer, _ sql: String) -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }
        return stmt
    }

    private static func text(_ stmt: OpaquePointer, _ col: Int32) -> String {
        guard let cStr = sqlite3_column_text(stmt, col) else { return "" }
        return String(cString: cStr)
    }

    private static func queryRecent(_ db: OpaquePointer) -> [TokenRequest] {
        let sql = """
        SELECT 
            l.request_id,
            l.created_at,
            l.model,
            l.input_tokens,
            l.output_tokens,
            l.cache_read_tokens,
            CAST(l.total_cost_usd AS REAL),
            l.status_code,
            COALESCE(l.latency_ms, l.duration_ms, 0),
            COALESCE(p.name, l.provider_id)
        FROM proxy_request_logs l
        LEFT JOIN providers p ON p.id = l.provider_id
        ORDER BY l.created_at DESC
        LIMIT 5;
        """
        guard let stmt = prepare(db, sql) else { return [] }
        defer { sqlite3_finalize(stmt) }

        var list: [TokenRequest] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let reqId = text(stmt, 0)
            let createdAt = sqlite3_column_int64(stmt, 1)
            let model = text(stmt, 2)
            let inTokens = Int(sqlite3_column_int64(stmt, 3))
            let outTokens = Int(sqlite3_column_int64(stmt, 4))
            let cachedTokens = Int(sqlite3_column_int64(stmt, 5))
            let costUSD = sqlite3_column_double(stmt, 6)
            let status = Int(sqlite3_column_int(stmt, 7))
            let latencyMs = sqlite3_column_double(stmt, 8)
            let provName = text(stmt, 9)

            let timeStr = timeFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(createdAt)))
            let costStr = formatCost(usd: costUSD, priced: true)

            list.append(TokenRequest(
                id: reqId,
                time: timeStr,
                model: model,
                inputTokens: inTokens,
                outputTokens: outTokens,
                durationSeconds: latencyMs / 1000.0,
                cost: costStr,
                status: status,
                accountEmail: provName.isEmpty ? nil : provName,
                cachedTokens: cachedTokens
            ))
        }
        return list
    }

    private static func querySummary(_ db: OpaquePointer, startOfDayTimestamp: Int64) -> (summary: TokenSummary, cacheRateFraction: Double, cacheReadTotal: Int) {
        let sql = """
        SELECT 
            COUNT(*),
            COALESCE(SUM(input_tokens), 0),
            COALESCE(SUM(output_tokens), 0),
            COALESCE(SUM(cache_read_tokens), 0),
            COALESCE(SUM(CAST(total_cost_usd AS REAL)), 0.0)
        FROM proxy_request_logs
        WHERE created_at >= ?;
        """
        guard let stmt = prepare(db, sql) else { return (.empty, 0, 0) }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, startOfDayTimestamp)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return (.empty, 0, 0) }

        let callsCount = Int(sqlite3_column_int64(stmt, 0))
        let inTotal = Int(sqlite3_column_int64(stmt, 1))
        let outTotal = Int(sqlite3_column_int64(stmt, 2))
        let cacheReadTotal = Int(sqlite3_column_int64(stmt, 3))
        let costTotalUSD = sqlite3_column_double(stmt, 4)

        let totalTokens = inTotal + outTotal + cacheReadTotal
        let totalTokensStr = TokenFormatUtils.formatCompactTokens(totalTokens)

        let denominator = inTotal + cacheReadTotal
        let fraction = denominator > 0 ? Double(cacheReadTotal) / Double(denominator) : 0
        let cacheRateStr = String(format: "%.1f%%", fraction * 100)
        let costStr = formatCost(usd: costTotalUSD, priced: true)
        let callsStr = "\(callsCount)次"

        let summary = TokenSummary(
            totalTokens: totalTokensStr,
            cacheRate: cacheRateStr,
            calls: callsStr,
            cost: costStr
        )
        return (summary, fraction, cacheReadTotal)
    }

    private static func queryLastRequestTime(_ db: OpaquePointer) -> Date? {
        let sql = "SELECT created_at FROM proxy_request_logs ORDER BY created_at DESC LIMIT 1"
        guard let stmt = prepare(db, sql) else { return nil }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(stmt, 0)))
    }

    private static func queryCurrentProvider(_ db: OpaquePointer) -> (name: String?, id: String?) {
        let sql = "SELECT id, name FROM providers WHERE is_current = 1 ORDER BY (CASE WHEN app_type = 'claude-desktop' THEN 0 ELSE 1 END) LIMIT 1"
        guard let stmt = prepare(db, sql) else { return (nil, nil) }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return (nil, nil) }
        let idStr = text(stmt, 0)
        let nameStr = text(stmt, 1)
        return (nameStr.isEmpty ? nil : nameStr, idStr.isEmpty ? nil : idStr)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    public static func formatCost(usd: Double, priced: Bool) -> String {
        guard priced else { return "未定价" }
        if usd >= 0.01 { return String(format: "$%.2f", usd) }
        if usd > 0 { return String(format: "$%.4f", usd) }
        return "$0.00"
    }
}
```

- [ ] **步骤 4：运行测试验证通过**

运行：
`xcodebuild test -scheme NotchDrop -derivedDataPath /tmp/NotchDropDerivedData CODE_SIGNING_ALLOWED=NO -destination 'platform=macOS' -only-testing:NotchEveryTests/AntigravityProxyStoreTests/testCCSwitchUsageStoreQueryAndSummary`
预期：PASS。

---

### 任务 2：将 UsageStore 主线程单例全面切换为 CCSwitchUsageStore

**文件：**
- 修改：`NotchDrop/UsageStore.swift`
- 修改：`Tests/AntigravityProxyStoreTests.swift`

- [ ] **步骤 1：更新测试用例适配 CCSwitchUsageStore**

更新 `Tests/AntigravityProxyStoreTests.swift` 中剩余的 WAL 探针与缺少数据库的测试用例，完全断开对 `AntigravityProxyStore` 的依赖：
- `testMissingDatabaseReturnsEmpty` 测试 `CCSwitchUsageStore.fetch(dbPath: missingURL)` 返回 `.empty`。
- `testWALModeReadOnlyAccess` 测试在 WAL 模式下 `CCSwitchUsageStore` 读出正确数据。
- 移除不再需要的旧 `AntigravityProxyStore` 测试代码。

- [ ] **步骤 2：在 UsageStore.refresh 中切换数据源**

在 `NotchDrop/UsageStore.swift` 的 `refresh()` 中：
```swift
DispatchQueue.global(qos: .utility).async { [weak self] in
    let data = CCSwitchUsageStore.fetch(dbPath: CCSwitchUsageStore.defaultDBPath)
    DispatchQueue.main.async {
        guard let self = self else { return }
        self.refreshing = false
        if self.recentRequests != data.recentRequests { self.recentRequests = data.recentRequests }
        if self.summary != data.summary { self.summary = data.summary }
        if self.cacheRateFraction != data.cacheRateFraction { self.cacheRateFraction = data.cacheRateFraction }
        if self.footer != data.footer { self.footer = data.footer }
        if self.providerName != data.providerName { self.providerName = data.providerName }
        if self.providerId != data.providerId { self.providerId = data.providerId }
    }
}
```
删除旧的 `AntigravityProxyStore` 类定义。

- [ ] **步骤 3：运行测试验证**

运行：
`xcodebuild test -scheme NotchDrop -derivedDataPath /tmp/NotchDropDerivedData CODE_SIGNING_ALLOWED=NO -destination 'platform=macOS' -only-testing:NotchEveryTests/AntigravityProxyStoreTests`
预期：PASS。

---

### 任务 3：TokenFormatUtils 与 TokenZoneView 多模型展示增强

**文件：**
- 修改：`NotchDrop/TokenFormatUtils.swift`
- 修改：`NotchDrop/TokenZoneView.swift`
- 修改：`Tests/TokenFormatUtilsTests.swift`（如有对应单测）

- [ ] **步骤 1：增强 TokenFormatUtils.friendlyModelName**

在 `NotchDrop/TokenFormatUtils.swift` 中，添加对第三方常见多模型名称的归一化与友好展示（去除冗余前缀，保留清晰标识）：
- `gemini-3.8-flash` → `gemini-3.8-flash`
- `gemini-3.7-flash-tiered` → `gemini-3.7-flash`
- `Qwen3.8-Flash` → `Qwen3.8-Flash`
- `DeepSeek-V4-Pro` → `DeepSeek-V4-Pro`
- `glm-5.3-flash` → `glm-5.3-flash`
- `claude-sonnet-5` → `sonnet-5`
- `claude-opus-5` → `opus-5`
- `claude-haiku-4-5` → `haiku-4.5`

- [ ] **步骤 2：优化 TokenRowView 第一列布局**

在 `NotchDrop/TokenZoneView.swift` 中：
- 模型名称胶囊：文本字号 10，保持紧凑，超长截断（`lineLimit(1)`）。
- 供应商名称（`friendlyAccountName`）：文本字号 10.5，超长自动截断不换行。
- 第一列宽度（`colIdentityW`）保持 140pt，两行结构清晰（行 1: `[模型] 供应商`，行 2: `时间`）。

- [ ] **步骤 3：运行全量单元测试**

运行：
`xcodebuild test -scheme NotchDrop -derivedDataPath /tmp/NotchDropDerivedData CODE_SIGNING_ALLOWED=NO -destination 'platform=macOS'`
预期：全部测试用例通过（PASS）。

---

### 任务 4：构建、本地部署与真机刘海屏视觉验证

**文件：**
- 部署目标：`/Applications/NotchEvery.app`

- [ ] **步骤 1：执行 Debug 版本构建**

运行：
```bash
xcodebuild build -scheme NotchDrop -configuration Debug -derivedDataPath /tmp/NotchDropBuild CODE_SIGNING_ALLOWED=NO
```
预期：`** BUILD SUCCEEDED **`。

- [ ] **步骤 2：部署并重启 NotchEvery**

运行：
```bash
pkill -x NotchEvery || true
sleep 1
rm -rf /Applications/NotchEvery.app
cp -R /tmp/NotchDropBuild/Build/Products/Debug/NotchEvery.app /Applications/NotchEvery.app
rm -rf /tmp/NotchDropBuild
open /Applications/NotchEvery.app
```
预期：新实例启动，PID 正常。

- [ ] **步骤 3：真机视觉验证**
- 在屏幕刘海处展开面板，滑动至第二页（Token 专区）。
- 确认列表中出现来自 `~/.cc-switch/cc-switch.db` 的各模型真实请求（Gemini、Qwen、DeepSeek 等）。
- 确认左耳显示当前活跃供应商（带绿点），右耳显示今日请求数，数据随请求实时更新。
