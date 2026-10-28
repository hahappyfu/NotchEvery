# 用量指标口径统一、成本移除与格式化修正 设计说明

日期：2026-10-28
状态：待批准（已过一轮外部审核，修订处见 §7）

## 1. 目标与背景

### 1.1 背景

NotchEvery 当前只有两个功能面：第一页「今日模型用量分布」、第二页「本地反代集束请求流水」，外加悬停 Peek 提示条。三者共用 `UsageStore`（数据源 `~/.cc-switch/cc-switch.db`）与 `TokenFormatUtils`（格式化）。

对照 `2026-09-29-cc-switch-usage-store-design.md`（定义「调用次数 = COUNT(*)」）与 `2026-10-02-model-distribution-page-design.md`（定义「卡片头显示全天总 Token」），两份规格各自成立，但从未对齐，导致同一个「今天用了多少」在四处出现三个不同算法。

### 1.2 证据

以用户 2026-10-28 实机截图为例，今日 5 个模型调用次数：

```
1,251 + 837 + 259 + 248 + 201 = 2,796
```

耳区显示 `3,137` 次，差 `341` 次（10.9%）。

### 1.3 目标

1. 定义唯一权威口径，让屏幕上每一个「今日总量」类数字同源。
2. 移除成本（USD）相关的一切显示与字段——当前使用的都是零成本模型，这个信息恒为噪音。
3. 修掉 `TokenFormatUtils` 中可证伪的格式化缺陷。
4. 补两个窗口属性，消除面板闪烁与切换 App 时消失。

### 1.4 非目标

- 不新增第三页、不恢复额度预测/会话监管（相关能力既无 UI 也无落地对象）。
- 不改 `AntigravityStore` 的额度解析逻辑（当前唯一消费者是第二页的邮箱→昵称匹配）。
- 不重写悬停状态机（现有事件驱动两段式 + `ghostGeneration` 代际守卫优于轮询式状态机）。
- 不引入窗口 frame 读回校验（`NotchWindowController.swift:54-57` 已有设前比对，收益边际）。
- 不加 `acceptsFirstMouse`（它是 `NSView` 的方法而非 `NSWindow`，需要额外宿主子类，且未证实存在吞点击问题）。
- 不引入定价表 / 成本重算（既然不用，不做任何替代）。
- **不删除死代码 `formattedCallsText`**（`NotchView.swift:274-283`，全仓无引用），也不动 `TokenSummary.totalTokens` / `cacheRate` 这两个当前无人消费的字段。它们与本设计的口径问题无关，清理属于独立改动，混进来会放大 diff、模糊归因。

## 2. 口径定义（本设计的核心决策）

| 指标 | 口径 | 理由 |
|---|---|---|
| 今日调用次数 | **全部请求行**（`COUNT(*)`，不过滤） | 沿用 09-29 规格。用户关心「今天调了多少次」，失败/零消耗的请求也是真实发生的调用。 |
| 今日总 Token | **仅 `total_tokens > 0` 的行**求和 | 零消耗行贡献恒为 0，加不加数值相同；显式过滤只是让口径与模型列表一致。 |
| 模型列表 | **仅 `total_tokens > 0` 的模型**，按 Token 降序取前 5 | 沿用 `ad75ca0` 的过滤决策。 |
| 活跃模型数 | **`total_tokens > 0` 的不同模型数（不限 5）** | `queryModelUsages` 的 SQL 本身没有 `LIMIT`，但 `UsageStore.swift:383` 在 Swift 层做了 `rows.prefix(5)`，导致 `modelUsages.count` 永远不可能大于 5，属于谎言。 |

推论：耳区的 `3,137` 与模型行次数之和 `2,796` **允许不同**——前者是今日全部请求数，后者只是前 5 个模型的请求数。两者口径不同，不构成矛盾。但**「今日总 Token」「活跃模型数」在全应用内必须只有一个来源**。

## 3. 改动清单

### 3.1 `NotchDrop/UsageStore.swift` — 口径

`UsageData` 增加两个字段：

```swift
public var todayTotalTokens: Int = 0
public var activeModelCount: Int = 0
```

**`UsageStore` 类必须同步加两个 `@Published` 并在 `refresh()` 里做值级去重**——这是 §3.3 的视图能读到它们的前提，漏掉直接编译不过：

```swift
// 声明区：紧随 :104 的 totalCostTodayUSD（该行在 §3.2 被删，新字段顶上来）
@Published public private(set) var todayTotalTokens: Int = 0
@Published public private(set) var activeModelCount: Int = 0

// refresh() 里：紧随 :148 既有的 if 去重块
if self.todayTotalTokens != data.todayTotalTokens { self.todayTotalTokens = data.todayTotalTokens }
if self.activeModelCount != data.activeModelCount { self.activeModelCount = data.activeModelCount }
```

`queryModelUsages` 已在上游算出全量 `dayTotalTokens` 与全部模型行（`:381-382` 的 `rows` 是 `prefix(5)` **之前**的完整结果），返回值由二元组改为**三元组**：

```swift
private static func queryModelUsages(_ db: OpaquePointer, startOfDayTimestamp: Int64)
    -> (items: [ModelUsageItem], dayTotalTokens: Int, activeModelCount: Int)
```

`activeModelCount = rows.count`（`HAVING total_tokens > 0` 已过滤；三列均为 `NOT NULL DEFAULT 0`，NULL 不会误杀合法行）。

配套清理（漏一处就编译失败）：
- `:382` 的 `let totalCost = rows.reduce(0.0) { $0 + $1.cost }` — 删
- `:393` 的 `return (items, totalCost)` — 改为三元组返回
- `:366` 的 `guard ... else { return ([], 0) }` — 改为三元素空返回
- `:351` 函数签名处的 `totalCost` 注释 — 删

`summary.totalTokens` 的字符串计算（`:325-326`）保留不动，仅停止被视图消费。

### 3.2 移除成本（贯穿数据层与视图层）

当前成本算了不少但只渲染两处，删掉是净减负。

**`NotchDrop/UsageStore.swift`**

| 位置 | 处理 |
|---|---|
| `ModelUsageItem.costUSD`（`:25`、`:33`、`:40`） | 删字段与 init 参数 |
| `UsageData.totalCostTodayUSD`（`:67`、`:79`、`:88`） | 删字段与 init 参数 |
| store 的 `@Published totalCostTodayUSD`（`:104`、`:148`、`:204`） | 删（含 `:148` 的去重行） |
| `queryRecent` 的 `CAST(l.total_cost_usd AS REAL)`（`:256`） | 从 SELECT 移除 |
| 同上的读取与构造（`:284` 调用、`:293` `cost:` 实参） | 删 |
| `querySummary` 的 `SUM(CAST(total_cost_usd AS REAL))`（`:309`） | 从 SELECT 移除 |
| 同上的读取与构造（`:331` 调用、`:338` `cost:` 实参） | 删 |
| `queryModelUsages` 的 `SUM(...) as cost`（`:359`） | 从 SELECT 移除 |
| 同上的读取与构造（`:370` 元组元素、`:377` `sqlite3_column_double(stmt, 4)`、`:389` `costUSD: row.cost`） | 删 |
| `formatCost(usd:priced:)`（`:412-417`） | 整函数删除；其调用点 `:284`、`:331` 随上表一并删 |

> **唯一有实际风险的地方**：`queryRecent` 删除 SELECT 列表**中间**的一行后，`status` / `latency` / `providerName` 三列的读取索引需从 `7/8/9` 改为 `6/7/8`（`:279-281`）。改错不会报错，只是静默读串数据（`status` 变成耗时、`accountEmail` 变成状态码）。§4.1 有专门断言兜底。`querySummary` 与 `queryModelUsages` 的成本都在 SELECT 列表**末尾**，删掉不影响前面的列索引。

**`NotchDrop/TokenZoneView.swift`**

- `TokenRequest.cost`（`:20`、`:32`、`:43`）—— 从未被任何视图渲染。
- `TokenSummary.cost`（`:75`、`:77`、`:81`、`:84`）—— 包括 `.empty` 里的 `"$0.00"`。

**`NotchDrop/ModelDistributionCardView.swift`**

- `:99` 页脚整行 `今日花费 $%.2f` 删除。
- `:181-188` 私有 `costText` 计算属性删除。
- `:229-233` 每行右栏的成本 `Text` 删除。

**不补位**：删除后第一页右栏只剩「N 次」、页脚只剩右对齐的「共 N 个活跃模型」。刻意不塞新元素——现有三块内容（模型名 / Token / 占比 / 次数）已经完整，补位属于推测性扩展。若日后觉得右侧空，可考虑把缓存率搬进第一页，但那是独立需求。

### 3.3 `NotchDrop/ModelDistributionCardView.swift` — 口径

- `dayTotalTokens` 计算属性（`:17-19`）删除，改用 `usage.todayTotalTokens`。
  - 现状是把 `modelUsages`（已 `prefix(5)`）求和，第 6 个模型起会静默漏算；这是对 10-02 规格「全天总 Token = 所有模型之和」的偏离。
- 页脚活跃模型数改用 `usage.activeModelCount`。**必须同时消除「6 个 vs 5 行」的同屏矛盾**：当 `activeModelCount > 5` 时文案追加限定，否则用户会问第 6 个在哪。

  ```swift
  // activeModelCount > 5 → "共 6 个活跃模型 · 显示前 5"
  // 否则               → "共 5 个活跃模型"
  ```
- 占比文案改用新的 `TokenFormatUtils.percentText(_:)`：非零但四舍五入为 `0.0%` 时输出 `<0.1%`。

> 注：本文件读 `UsageStore.shared` 的局部变量名是 `store`（`ModelDistributionCardView.swift` 内 `@StateObject`），与 `NotchView` 的 `usage` 不同名，各自按本文件既有写法即可。

### 3.4 `NotchDrop/TokenFormatUtils.swift`

**进位跳级**：`formatCompactTokens` 与 `formatCount` 在某一单位下四舍五入后会变成 `1000.0` 时，应升到下一单位。

```
999_960      → "1.0M"    （现在 "1000.0k"）
999_960_000  → "1.0B"    （现在 "1000.0M"）
999_949      → "999.9k"  （不变）
9_999        → "10.0k"   （不变，k 是最小单位，无处可升）
```

实现：单位换算后若 `value >= 999.95` 则升到下一单位。边界取 `999.95` 是因为 `%.1f` 的舍入点在此。

**`formatCount` 现有实现只有 `M` 与 `k` 两个分支**（`TokenFormatUtils.swift:32-41`），没有 `B` 分支。上面 `999_960_000 → "1.0B"` 的用例要求实现先补上 `>= 1_000_000_000` 的 `B` 分支，否则无处可升。

> 已知实情：`formatCount` 当前唯一调用者是 `formattedCallsText`（`NotchView.swift:274`），而后者全仓无引用，是死代码。因此本项改动**在 UI 上的效果为零**，只有单测能观测到。仍然修，是因为它是 public API 且被测试锁定，留着可证伪的缺陷会误导下一个调用者。是否删死代码另议（见 §1.4）。

**占比文案**：

```swift
public static func percentText(_ fraction: Double) -> String
// >0 且 <0.0005 → "<0.1%"
// 其余 → String(format: "%.1f%%", fraction * 100)
```

**模型名去前缀**：`friendlyModelName` 目前只剥 `tiered` 尾段（`:73-75`），`wbintl/deepseek-v4.1-flash` 这类带供应商前缀的名称在 145pt 列里被截成 `wbintl/deepseek-v4.1…`。

新增纯函数，按「本次列表内是否重名」决定是否剥掉 `/` 之前的部分：

```swift
public static func displayModelNames(_ models: [String]) -> [String]
// 对每个 model：候选短名 = 最后一个 "/" 之后的部分
// 若该短名在本批 models 中唯一 → 用短名
// 否则 → 保留原全名
```

这样 `wbintl/deepseek-v4.1` 与 `deepseek-v4.1` 同时存在时两行都保留前缀，不会出现两个一模一样的标签。

**调用点（唯一）**：第一页 `ModelDistributionCardView.swift:198`，把现有的逐个 `friendlyModelName(...)` 改为对本批模型名先跑一次 `displayModelNames`，再取对应下标。第二页 `TokenZoneView.swift:152` **不改**——它列宽不同、且分页展示的是请求流水而非模型榜单，不在本次范围。

### 3.5 `NotchDrop/NotchView.swift`

`formattedTokensText`（`:263-272`）删除。它是恒等函数——`summary.totalTokens` 已是 `"449.6M"` 形态，`Int(clean)` 必然失败，`hasSuffix` 分支原样返回。改为直接 `TokenFormatUtils.formatCompactTokens(usage.todayTotalTokens)`。

> 注意：本文件读 store 的局部变量名是 **`usage`**（`NotchView.swift:12` 的 `@StateObject private var usage = UsageStore.shared`），文件内不存在 `store` 这个名字。

### 3.6 `NotchDrop/NotchWindow.swift`

`init` 内追加两个属性（现有 `collectionBehavior` 与 `level` 已与参考实现一致，无需改动）：

```swift
animationBehavior = .none   // 消除 orderFrontRegardless 的系统淡入（「面板闪一下」的成因）
hidesOnDeactivate = false   // NSWindow 默认 true，切换 App 时面板会消失
```

`animationBehavior` 是**整窗**级别的自动动画开关，不只影响 `orderFront`/`orderOut`：Space 切换、进出全屏的系统过渡也会一并变生硬。SwiftUI 内部的 `withAnimation` 不受影响。这是一次权衡——面板闪烁的观感损失大于系统过渡的顺滑度收益，且本窗口本身 `isOpaque=false`、`hasShadow=false`，系统过渡对它本就近乎不可见。实机确认一次；若发现全屏切换生硬到刺眼，回退这一行即可（`hidesOnDeactivate` 独立生效）。

## 4. 测试

### 4.1 新增 `Tests/UsageMetricsTests.swift`

`AntigravityProxyStoreTests.swift` 里的造库辅助（`ccSchema` `:10`、`todayNoonTimestamp` `:35`、`openTempDB` `:39`、`insertLogSQL` `:52`）**全部是 `private`**，跨文件不可见。新文件需自行复制这几段（或在本轮把其中可复用的部分改为 `internal`——二选一，不新建共享测试工具层）。

构造一天内包含「正常行 + 零 token 行 + 6 个模型」的 `proxy_request_logs`，断言：

1. `summary.calls` 计入零 token 行（即等于全部行数，不过滤）。
2. `todayTotalTokens` 等于全部行 `in + out + cached` 之和。
3. `modelUsages.count == 5`，`activeModelCount == 6`。
4. **`shareFraction` 的分母是全量 `dayTotalTokens` 而非 top5 之和**：取一个不在前 5 的模型，断言 `sum(modelUsages.shareFraction) < 1.0`，且其中每个 `item.shareFraction == Double(item.totalTokens) / Double(todayTotalTokens)`。
   - 不能只断言「之和 ≤ 1.0」——若分母误用 top5 之和，和恰为 1.0，断言照样通过，什么都抓不到。
5. **索引左移兜底**（风险表承诺的唯一真实风险点）：插入一条 `status_code` 与 `latency_ms` 取**互不相同且都非零**的行，断言 `recentRequests.first` 的 `status` 与 `durationSeconds` 各自等于插入值。现有测试里 `status` 只出现在建表语句（`AntigravityProxyStoreTests.swift:27`、`:55`），`durationSeconds` 零断言——这一列错位目前没有任何测试能发现。
6. `UsageStore` 的 `@Published` 接入层：断言 `refresh` 后 `store.todayTotalTokens` / `store.activeModelCount` 与 `fetch` 结果一致（覆盖 §3.1 那段「漏了就编译不过」的接线段）。

### 4.2 更新已有测试

- `TokenFormatUtilsTests`：补进位跳级用例（`999_960` / `999_960_000` / `999_949`）、`formatCount` 的 `B` 分支用例、`percentText` 用例、`displayModelNames` 唯一/重名两种用例。
- `AntigravityProxyStoreTests.swift:265`：删除 `totalCostTodayUSD` 断言。
- `AntigravityProxyStoreTests.swift:270-276`：删除整个 `testFormatCostBoundaries`。
- 造表语句里的 `total_cost_usd` 列**保留**——它模拟的是真实 `proxy_request_logs` schema，代码不读它不代表表里不该有。

### 4.3 验证命令

工程是 `NotchDrop.xcodeproj`，共享 scheme 在 `NotchDrop.xcodeproj/xcshareddata/xcschemes/NotchDrop.xcscheme`：

```
xcodebuild test -project NotchDrop.xcodeproj -scheme NotchDrop -destination 'platform=macOS'
```

## 5. 风险

| 风险 | 处理 |
|---|---|
| `queryRecent` 删列后索引错位，静默读串数据 | 唯一真实风险点，§3.2 已单列标注；§4.1 断言 5 用互不相同的 `status_code` / `latency_ms` 兜底 |
| §3.1 漏加 `@Published` 或 `refresh()` 去重，视图读不到新字段 | §4.1 断言 6 覆盖接入层；这属于编译期或首个断言即暴露，不会漏到线上 |
| 页脚「6 个活跃模型」与列表 5 行同屏矛盾 | §3.3 已定文案：超出 5 时追加「· 显示前 5」 |
| `activeModelCount` 因 NULL 误杀合法模型行 | 三列均为 `NOT NULL DEFAULT 0`（真实库与 fixture 一致），不会发生；若将来列变可空，`COALESCE(SUM(...))` 包在外层会让行级 NULL 被 SUM 静默跳过，届时改为 `SUM(COALESCE(col, 0))` |
| `displayModelNames` 去重逻辑引入歧义 | 纯函数 + 单测锁定；重名时回退全名，不猜 |
| `animationBehavior = .none` 让 Space 切换 / 全屏过渡变生硬 | 整窗级开关，已在上文声明取舍；实机确认一次，不合适单独回退这一行 |
| `hidesOnDeactivate = false` 使面板在其他 App 全屏时仍可见 | 现有 `collectionBehavior` 已含 `.fullScreenAuxiliary`，行为一致；实机确认一次 |
| 卡片头数字在本次改动后可能变大（若今日确有 >5 个模型） | 这不是回归，是修正——之前漏算 |
| 删除 `TokenSummary.cost` 破坏 `TokenZoneView.empty` | 已在 §3.2 列出 `:84`；`.empty` 的其余字段不变 |
| `cache_creation_tokens` 列不参与 `total_tokens` | 既存行为（`UsageStore.swift:357` 只算 input+output+cache_read），本次不改。既然要定义唯一口径，此处按现状写明：缓存写入不计入 Token 统计 |

## 6. 备选方案（已否决）

- **保留成本字段、只隐藏 UI**：用户明确「用不到」，留着字段等于留着将来有人重新接上的机会，也留着三个 SQL 的无谓 `CAST` 聚合。
- **改 SQL 一次查全所有模型再在视图取前 5**：与 §3.1 等价但把截断逻辑推给视图，`activeModelCount` 反而要在视图里算，不如数据层一次给全。
- **只统一视图层，不动 `UsageData`**：最小改动，但每个新视图都要重新推导一遍口径，问题会复发。
- **模型名一律剥前缀**：实现最简单，但两个供应商供同名模型时标签撞车。
- **给 `NSHostingView` 加子类实现 `acceptsFirstMouse`**：改动面大且未证实有问题，列为后续可选项。

## 7. 本轮修订记录（对照审核意见）

已采纳：
1. `activeModelCount` 的理由从「SQL 层已 `prefix(5)`」改为「SQL 无 LIMIT，`UsageStore.swift:383` 的 Swift 层 `prefix(5)`」——原表述与 §3.1「`:381-382` 的 rows 是 `prefix(5)` 之前」自相矛盾。
2. §3.1 补 `UsageStore` 类的两个 `@Published` 与 `refresh()` 去重——原文只给 `UsageData` 加字段，照做编译不过。
3. 「四元组」改为「三元组」——原返回是二元组，删 totalCost 后是三元组。
4. §3.5 的 `store.todayTotalTokens` 改为 `usage.todayTotalTokens`——`NotchView.swift:12` 的变量名是 `usage`。
5. §3.2 补齐 `formatCost` 的调用点与 `cost:` 实参位置、`:366` 空返回、`:382` `totalCost`、`:393` 返回语句、`:351` 注释。
6. §4.3 验证命令由 `NotchEvery.xcodeproj/NotchEvery` 改为 `NotchDrop.xcodeproj/NotchDrop`。
7. §3.4 指明 `formatCount` 缺 `B` 分支，需先补。
8. §4.1 断言 4 由「之和 ≤ 1.0」改为分母校验——原断言抓不到分母误用。
9. §4.1 补「辅助函数全是 private，需复制」与索引左移断言、`@Published` 接入层断言。
10. §3.3 补「6 个活跃模型 vs 5 行」的同屏矛盾处理。
11. §3.4 指明 `displayModelNames` 的唯一调用点是第一页，第二页不动。
12. §5 补 `animationBehavior` 是整窗级开关、`cache_creation_tokens` 不计入。

未采纳：
- 「全仓无任何 `.xcscheme`，scheme 未共享」——实查存在 `NotchDrop.xcodeproj/xcshareddata/xcschemes/NotchDrop.xcscheme`，只是名字是 `NotchDrop` 不是 `NotchEvery`。命令已按实际情况修正。
