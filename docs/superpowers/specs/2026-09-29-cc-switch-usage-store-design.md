# 2026-09-29 第二页用量流水全面切换为 cc-switch 数据源设计

## 1. 背景与目标

### 1.1 背景
NotchEvery 第二页（Token 专区）此前单源读取 Antigravity Tools 本地反代数据库（`~/.antigravity_tools/proxy_logs.db`）。该数据源仅记录走本地 8045 反代并将请求转为 Claude 的部分记录，无法反映经由 `cc-switch` 路由调用的全量多模型生态（如 Google Gemini、通义千问 Qwen、智谱 GLM、DeepSeek 以及 Anthropic Claude 官方源等）。

### 1.2 目标
1. **全面切换数据源**：将 `UsageStore` 单源重定向至 `~/.cc-switch/cc-switch.db`（`proxy_request_logs` 与 `providers` 表），彻底废弃并移除 `AntigravityProxyStore` 日志抓取实现。
2. **多模型全量捕获**：展示经 cc-switch 调用的实际后端模型（`model`），真实反映底层模型走向。
3. **精准指标聚合**：汇总今日总 Token、综合缓存命中率、今日调用次数、今日总花费（USD），并在页脚呈现已省读缓存量与最后请求时间。
4. **耳区联动**：左耳显示当前活跃供应商名称（带绿灯状态点），右耳显示今日调用次数。
5. **健壮只读与零锁争用**：沿用只读探针机制，读 WAL 实时数据优先，受限时平滑降级 `immutable=1`，确保与 cc-switch 写入进程并发安全。

---

## 2. 架构与数据流

```
~/.cc-switch/cc-switch.db (WAL 模式)
          │
          ▼ [3 秒后台轮询]
    CCSwitchUsageStore
  ┌──────────────────────────────────────────────────┐
  │ 1. 探针打开 (Read-Only -> immutable=1 降级)        │
  │ 2. 今日零点起聚合 (COUNT, SUM in/out/cache/cost)  │
  │ 3. 最近 5 条请求 JOIN providers (提取实际 model)   │
  │ 4. 当前活跃供应商查询 (providers.is_current = 1)   │
  └──────────────────────────────────────────────────┘
          │
          ▼ [主线程发布 (值级去重)]
      UsageStore (ObservableObject)
          ├── summary (TokenSummary: Tokens / 缓存率 / 次数 / 开销)
          ├── recentRequests ([TokenRequest]: 5 条实时流水)
          ├── cacheRateFraction (Double: 环/条比例)
          ├── footer (UsageFooter: 缓存节约量 / 尾次请求时间)
          └── providerName / providerId (耳区展示)
          │
     ┌────┴──────────────────────────┐
     ▼                               ▼
NotchRootView (耳区)           TokenZoneView (第二页主体)
```

---

## 3. 数据层详细设计

### 3.1 数据库路径
- 默认路径：`~/.cc-switch/cc-switch.db`。
- 测试与外部注入：支持 `CCSwitchUsageStore.fetch(dbPath: URL, now: Date)`，便于单测使用临时文件。

### 3.2 探针与只读连接策略
```swift
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
```

### 3.3 今日统计聚合 SQL
时间范围：`created_at >= ?`，入参为 `Int64(Calendar.current.startOfDay(for: now).timeIntervalSince1970)`。
```sql
SELECT 
    COUNT(*),
    COALESCE(SUM(input_tokens), 0),
    COALESCE(SUM(output_tokens), 0),
    COALESCE(SUM(cache_read_tokens), 0),
    COALESCE(SUM(CAST(total_cost_usd AS REAL)), 0.0)
FROM proxy_request_logs
WHERE created_at >= ?;
```
- **总 Token** = `SUM(input_tokens) + SUM(output_tokens) + SUM(cache_read_tokens)`，经 `TokenFormatUtils.formatCompactTokens` 格式化为 `12.9M` 等。
- **缓存命中率** = `SUM(cache_read_tokens) / (SUM(input_tokens) + SUM(cache_read_tokens))`。
- **调用次数** = `COUNT(*)`，格式化为 `443次`。
- **今日花费** = `SUM(total_cost_usd)`，格式化为 `$14.59`（若不足 $0.01 保留 4 位小数）。

### 3.4 最近请求列表 SQL（5条）
```sql
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
```
- 字段映射到 `TokenRequest`：
  - `id`: `l.request_id`
  - `time`: `created_at` 格式化为 `HH:mm`
  - `model`: `l.model`（实际后端模型名）
  - `inputTokens`: `l.input_tokens`
  - `outputTokens`: `l.output_tokens`
  - `cachedTokens`: `l.cache_read_tokens`
  - `cost`: 格式化金额
  - `durationSeconds`: `Double(latency_ms) / 1000.0`
  - `status`: `l.status_code`
  - `accountEmail`: 供应商名称 `COALESCE(p.name, l.provider_id)`

### 3.5 当前活跃供应商查询 SQL（左耳）
```sql
SELECT id, name FROM providers WHERE is_current = 1 ORDER BY (CASE WHEN app_type = 'claude-desktop' THEN 0 ELSE 1 END) LIMIT 1;
```
若 `providers` 中无 `is_current = 1` 记录，则回退取最新一条日志对应的供应商名称。

---

## 4. UI 与格式化适配

### 4.1 模型名称展示
在 `TokenFormatUtils.friendlyModelName` 中支持多模型名称归一化（去除前缀、版本简化，避免列表超宽）：
- 如 `gemini-3.8-flash` → 显示 `gemini-3.8-flash`
- 如 `Qwen3.8-Flash` → 显示 `Qwen3.8-Flash`
- 如 `DeepSeek-V4-Pro` → 显示 `DeepSeek-V4-Pro`
- 如 `claude-sonnet-5` → 显示 `sonnet-5`

### 4.2 供应商与时间布局
在 `TokenRowView` 中：
- 第一列显示模型药丸标签 + 供应商名称（`row.accountEmail`，如"本地反代集束"）。
- 第二行显示请求完成时刻（`row.time`，如 "10:13"）。
- 中栏展示 Token 总和与缓存命中胶囊条。
- 右栏展示单次金额与耗时。

---

## 5. 改动范围与文件清单

1. **`NotchDrop/UsageStore.swift`**：
   - 彻底将 `AntigravityProxyStore` 重构替换为 `CCSwitchUsageStore`。
   - 路径改为 `~/.cc-switch/cc-switch.db`。
   - 实现安全只读与 WAL 探针，执行上述 SQL 查询。
2. **`NotchDrop/TokenFormatUtils.swift`**：
   - 增强模型名称解析，确保第三方模型（Gemini、Qwen、DeepSeek 等）排版友好。
3. **`NotchDrop/TokenZoneView.swift`**：
   - 第一列模型与供应商标签自适应排版。
4. **`Tests/AntigravityProxyStoreTests.swift`**：
   - 重构为 `CCSwitchUsageStoreTests.swift`（并在 `NotchDrop.xcodeproj/project.pbxproj` 中对齐文件名或更新类名），测试 cc-switch 的表结构读写与聚合。

---

## 6. 验证计划

1. **自动化测试**：
   - 运行 `xcodebuild test -scheme NotchDrop -derivedDataPath /tmp/NotchDropDerivedData CODE_SIGNING_ALLOWED=NO -destination 'platform=macOS'`，确保全部测试通过。
2. **真机运行验证**：
   - 构建 Debug 应用部署到 `/Applications/NotchEvery.app`。
   - 展开刘海屏第二页，观察真实拉取出的模型列表（Gemini、Qwen、DeepSeek 等）及顶栏 Tokens、命中率、调用次数、费用是否实时更新。
