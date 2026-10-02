# 第一页：今日模型用量与分布设计规格说明

## 1. 目标与背景

### 1.1 背景
NotchEvery 原第一页包含 Antigravity 账号配额卡与本地反代看板组件，随着反代理服务全面迁入 `fuckharness`，旧看板已丧失独立价值。第三页 Qoder 废弃后，面板收敛为双页外壳：
- **第一页（新）**：今日模型消耗占比与分布（宏观分布视图）。
- **第二页（现）**：实时请求流水表（微观实时视图）。

### 1.2 目标
1. 第一页彻底替换为单张卡片 `ModelDistributionCardView`（宽度 410pt，与第二页 410pt 严格等宽，滑动切页尺寸平滑无抖动）。
2. 从 `~/.cc-switch/cc-switch.db` 的 `proxy_request_logs` 聚合今日（从 00:00 至今）全量多模型的用量。
3. 提供类似 macOS 存储空间条的多色分段占比条，配合模型排行明细列表，直观展现主力模型 Token 消耗、占比及调用频次。

---

## 2. 数据层设计 (UsageStore)

### 2.1 数据结构
```swift
public struct ModelUsageItem: Identifiable, Equatable {
    public var id: String { model }
    public let model: String              // 原始模型名
    public let calls: Int                 // 今日调用次数
    public let totalTokens: Int           // 总消耗 Token (input + output + cached)
    public let cachedTokens: Int          // 命中缓存 Token
    public let costUSD: Double            // 预估花费美元
    public let shareFraction: Double      // 占全天总消耗比例 (0.0 ... 1.0)
}
```

在 `UsageData` 中增加：
```swift
public var modelUsages: [ModelUsageItem] = []
public var totalCostTodayUSD: Double = 0.0
```

在 `UsageStore` 中发布：
```swift
@Published public private(set) var modelUsages: [ModelUsageItem] = []
@Published public private(set) var totalCostTodayUSD: Double = 0.0
```

### 2.2 SQL 查询
在现有只读 SQLite 连接上执行：
```sql
SELECT
    l.model,
    COUNT(*) as calls,
    SUM(l.input_tokens + l.output_tokens + l.cache_read_tokens) as total_tokens,
    SUM(l.cache_read_tokens) as cached_tokens,
    SUM(CAST(l.total_cost_usd AS REAL)) as cost
FROM proxy_request_logs l
WHERE l.created_at >= ?
GROUP BY l.model
ORDER BY total_tokens DESC
LIMIT 5;
```
参数：`startOfDayTimestamp`（本地时间当天 00:00:00 的 Unix 时间戳，秒级）。

计算全天总 Token（所有模型 `total_tokens` 之和），从而得出每个模型的 `shareFraction = Double(total_tokens) / Double(max(1, dayTotalTokens))`。

---

## 3. UI 视图设计 (ModelDistributionCardView)

### 3.1 尺寸规范
- 整体宽度：410pt（与 `TokenZoneView` 宽度 410pt 一致）。
- 外壳材质：遵循 `DesignSystem.swift` 的 Studio 规范，圆角 12pt，边框 `Color.white.opacity(0.035)`，背景透明自适应黑岛。

### 3.2 布局分层
1. **Header**：
   - 左侧：翡翠绿圆点（6pt）+ 标题「今日模型用量分布」（11.5pt，semibold，white 0.88）。
   - 右侧：今日总消耗 `TokenFormatUtils.formatCompactTokens(dayTotalTokens) + " Tokens"`（11pt，monospacedDigit，secondary）。
2. **多色分段比例条 (Segmented Proportion Bar)**：
   - 宽度：410 - 20 = 390pt，高度：6pt，圆角：3pt。
   - 调色板映射：
     - Index 0: `StudioColor.emerald` (翡翠绿)
     - Index 1: `Color(red: 90/255, green: 200/255, blue: 250/255)` (科技青蓝)
     - Index 2: `Color(red: 175/255, green: 82/255, blue: 222/255)` (紫罗兰)
     - Index 3: `StudioColor.amber` (琥珀金)
     - 其它/其余: `Color.white.opacity(0.3)`
   - 各段按 `shareFraction * totalWidth` 分配宽度，最小保证 4pt，带 1.5pt 间隔。
3. **模型排行列表 (Top 5)**：
   - 垂直间距：6pt。
   - 每行结构：
     - **左栏**（定宽 150pt）：模型颜色圆点 + `TokenFormatUtils.friendlyModelName(item.model)` 胶囊徽标。
     - **中栏**（定宽 130pt）：`TokenFormatUtils.formatCompactTokens(item.totalTokens)` + 占比百分比（如 `49.6%`）。
     - **右栏**（定宽 90pt，右对齐）：调用次数（如 `202 次`）+ 预估费用（如 `$9.19`）。
   - 单行悬停时展示背景微高亮 `StudioMaterial.cardHoverBackground`。
4. **Footer**：
   - 左侧：`今日预估花费 $\(String(format: "%.2f", totalCostTodayUSD))`（10pt，secondary）。
   - 右侧：`活跃模型数 \(modelUsages.count) 个`（10pt，secondary）。

---

## 4. 页面集成与清理

1. `OverviewPageView.swift`：
   - 移除 `AntigravityAccountsCardView` 和 `AntigravityProxyCardView` 引用。
   - 直接渲染 `ModelDistributionCardView()`。
2. 清理废弃卡片：
   - 废弃/移除 `AntigravityAccountsCardView.swift` 和 `AntigravityProxyCardView.swift`。
   - 检查并保留 `AntigravityStore.swift`（因第二页用于邮箱到昵称的匹配）。

---

## 5. 测试策略

1. **单元测试 (`UsageStoreTests.swift`)**：
   - 验证 `queryModelUsages` 能正确从模拟内存 SQLite 库解析出模型列表。
   - 验证 `shareFraction` 比例计算准确且总和在 0.0~1.0 之间。
   - 验证无今日数据时优雅回退为空数组。
2. **构建与运行测试**：
   - 运行全量 `xcodebuild test` 确保无符号冲突与回归。
