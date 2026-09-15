# Antigravity 全景总览与原生反代流量日志换源设计规格

- **日期**：2026-09-16
- **分类**：架构级（Architectural）重塑
- **范围**：
  1. 首页底栏重塑：移除冗余的「守护卡（GuardCardView）」，新建「Antigravity 反代今日看板（AntigravityProxyCardView）」
  2. 第二页数据源换源：重构 `UsageStore.swift`，从旧 `cc-switch.db` 彻底切换到原生的 `~/.antigravity_tools/proxy_logs.db` 与 `token_stats.db`
  3. `TokenZoneView.swift` 适配展示：支持展示真实耗时、HTTP 状态、缓存命中及发起账号（邮箱简写/名字）
  4. 守护控制台纯净化：第一页不再包含守护组件，所有守护逻辑收敛于第三页 `GuardControlZoneView.swift`

---

## 1. 架构目标与动机

1. **心智统一**：
   - 目前首页上半部分是 Antigravity 5 账号池，下半部分是 Guard 守护卡，第二页是 cc-switch 数据源，生态割裂。
   - 改造后：整个灵动岛前两页彻底成为专为 AI 开发者定制的 **Antigravity 原生仪表盘**（第 1 页：5 账号立体配额 + 反代今日看板；第 2 页：反代真实调用流流水表；第 3 页：系统守护控制台）。
2. **数据质量跃升**：
   - 彻底摒弃 cc-switch 间接推导的旧指标。
   - 直读本地运行的 `Antigravity Tools.app` 核心数据库：
     - `~/.antigravity_tools/proxy_logs.db`（`request_logs` 表，毫秒级真实请求流水）
     - `~/.antigravity_tools/token_stats.db`（`token_usage` 表，今日按时段与账号统计）
     - `~/.antigravity_tools/gui_config.json`（反代端口、运行状态与调度策略）

---

## 2. 模块 1：首页下半部——Antigravity 反代今日看板 (`AntigravityProxyCardView.swift`)

### 2.1 替换点
在 `NotchDrop/OverviewPageView.swift` 中：
- 移除 `GuardCardView(vm: vm)`
- 引入 `AntigravityProxyCardView(vm: vm)`

### 2.2 视觉与指标设计 (Apple Native Studio Bento)
宽度固定 360pt，内边距与上方 3D 舞台卡片保持一致（横向 18pt，纵向 12pt）。

- **顶栏 (Header)**：
  - 左侧：`🟢 本地反代 · 8045 端口`（读取配置中 `proxy.port`，配合小绿点表示运行中）
  - 右侧：`今日累计` 标签
- **主体三列 Bento 微卡 (Metric Tiles)**：
  1. **请求次数 (Requests)**：展示今日总请求数（例如 `1,284` 次），单日增量高亮。
  2. **总吞吐 (Tokens)**：展示今日消耗总 Token（例如 `142.6M`），带输入/输出比例微型进度条。
  3. **平均延迟 (Latency)**：展示今日请求平均响应耗时（例如 `280ms` 或 `1.2s`），反应网络质量。
- **底栏微信息 (Footer)**：
  - 左侧：今日缓存命中 Token 数及命中率胶囊（例如 `缓存命中率 42.8%`）。
  - 右侧：最近一次请求时间（例如 `10秒前` 或 `00:44`）。

---

## 3. 模块 2：数据层重构——`UsageStore.swift` 换源 Antigravity 原生数据库

### 3.1 数据源与只读安全设计
- **主数据库**：`~/.antigravity_tools/proxy_logs.db`
- **安全模式**：
  - 使用 SQLite 官方 C API：`sqlite3_open_v2(..., &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil)`
  - 执行 `PRAGMA query_only = ON;` 与 `PRAGMA busy_timeout = 1000;`
  - 绝对不与正在高速写日志的 `antigravity-tools` 产生任何锁表冲突。

### 3.2 字段映射模型 (`TokenRequest`)
- `id`: `request_logs.id` (TEXT)
- `time`: `timestamp`（毫秒时间戳转换本地时间 `HH:mm:ss`）
- `model`: `model`（过滤空值，若空回退为 `gemini-pro`）
- `inputTokens`: `input_tokens`
- `outputTokens`: `output_tokens`
- `durationSeconds`: `Double(duration) / 1000.0`（真实毫秒转秒）
- `status`: `status`（真实 HTTP 状态码 200 / 429 / 500 等）
- `cachedTokens`: `cached_tokens`
- `accountEmail`: `account_email`（可选映射为账号池昵称，如 `傅哈哈`）

### 3.3 今日聚合算法 (Today KPI)
通过当天的零点时间戳 `Date.startOfDay.timeIntervalSince1970 * 1000` 聚合：
```sql
SELECT 
    COUNT(*),
    COALESCE(SUM(input_tokens), 0),
    COALESCE(SUM(output_tokens), 0),
    COALESCE(SUM(cached_tokens), 0),
    COALESCE(AVG(duration), 0)
FROM request_logs
WHERE timestamp >= ? AND model != ''
```

---

## 4. 模块 3：UI 展示层联动升级 (`TokenZoneView.swift`)

1. **左耳 / 右耳更新**：
   - 灵动岛左耳（Token 页）：显示 `本地反代 :8045`。
   - 灵动岛右耳（Token 页）：显示 `今日请求 \(calls) 次`。
2. **请求流水列表更新**：
   - 前 5 条最新真实请求，实时渲染真实的 `duration`（例如 `1.2s`、`21.6s`）与真实的 `status`。
   - 鼠标悬停支持展示该请求所使用的账号（`account_email`）。
3. **状态色调**：
   - 200 正常绿色小圆点。
   - 429 限流 / 500 错误玫瑰红（`StudioColor.rose`）高亮。

---

## 5. 验证与回归保证

1. **数据库并发测试**：验证在 `proxy_logs.db` 存在并发写入时，`UsageStore` 只读拉取完全安全且耗时小于 10ms。
2. **全量单测覆盖**：更新 `TokenUsageTests.swift` 等已有测试用例，保证测试套件全量 420+ 项通过。
3. **真机直观体验**：编译运行后，第一页同时展示上方「5 账号 3D 舞台」和下方「本地反代今日吞吐看板」；第二页展示原生毫秒级流水。
