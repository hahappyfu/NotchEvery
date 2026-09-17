# 第二页用量监控重构为实时请求流（Live Stream）实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 subagent-driven-development（推荐）或 executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 彻底重构 NotchEvery 第二页（TokenZoneView）为「纯净实时流水（Live Stream）」，去除与第一页重复的 KPI 大卡片，采用 3 栏平衡设计，呈现模型徽标、账号标识、带色彩分级的缓存命中率进度条、总 Token 及耗时。

**架构：**
- 数据层：`TokenRequest` 扩充 `cachedTokens: Int` 字段；`UsageStore` 透传 SQLite 流水中的 `cached_tokens`，并提供账号邮箱到账号名称的智能映射。
- 格式化层：`TokenFormatUtils` 提供 `friendlyModelName`（模型短名）和 `cacheRateTier`（命中率色彩分级：高效翠绿、正常青蓝、偏低暖琥珀、0 冷启灰）。
- 表现层：`TokenZoneView` 移除 `summaryBar` 和表头，用纤细微型状态栏与 3 栏网格（左身份、中用量分布、右性能时间）填充横向空间，高度压减 40% 消除下巴空黑与中间空洞。

**技术栈：** Swift 6 / SwiftUI / SQLite3 / XCTest / macOS 14+

**规格文档：** `docs/superpowers/prototypes/2026-09-17-token-page-redesign.html`（经用户审批的高保真原型）

## 全局约束

- 严格遵循 Apple Native Studio 工业级设计规范（`StudioColor`、`StudioMaterial`、`monospacedDigit()`）。
- 单元测试运行必须带编译参数 `CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO` 避开环境证书限制。
- 应用构建输出严格部署至系统 `/Applications/NotchEvery.app`。

---

### 任务 1：纯函数格式化与色彩分级逻辑（TDD）

**文件：**
- 修改：`NotchDrop/TokenFormatUtils.swift`
- 测试：`Tests/TokenFormatUtilsTests.swift`

- [x] **步骤 1：在 `Tests/TokenFormatUtilsTests.swift` 编写失败的测试**

添加对 `friendlyModelName`、`cacheRateTier` 和 `cacheRateFraction` 的测试用例：
```swift
func testFriendlyModelName() {
    XCTAssertEqual(TokenFormatUtils.friendlyModelName("gemini-3.8-flash-high"), "Flash High")
    XCTAssertEqual(TokenFormatUtils.friendlyModelName("gemini-2.5-pro"), "Gemini Pro")
    XCTAssertEqual(TokenFormatUtils.friendlyModelName("claude-3-5-sonnet-20241022"), "Sonnet 3.5")
    XCTAssertEqual(TokenFormatUtils.friendlyModelName("gpt-4o-2024-08-06"), "GPT-4o")
    XCTAssertEqual(TokenFormatUtils.friendlyModelName("custom-model"), "custom-model")
}

func testCacheRateFractionAndTier() {
    let fraction = TokenFormatUtils.cacheRateFraction(cached: 81698, input: 170075)
    XCTAssertEqual(String(format: "%.2f", fraction), "0.48")
    XCTAssertEqual(TokenFormatUtils.cacheRateTier(fraction: 0.78), .high)
    XCTAssertEqual(TokenFormatUtils.cacheRateTier(fraction: 0.48), .medium)
    XCTAssertEqual(TokenFormatUtils.cacheRateTier(fraction: 0.20), .low)
    XCTAssertEqual(TokenFormatUtils.cacheRateTier(fraction: 0.0), .none)
}
```

- [x] **步骤 2：运行测试验证失败**

运行：
```bash
xcodebuild test -project NotchDrop.xcodeproj -scheme NotchDrop -destination 'platform=macOS' -only-testing:NotchEveryTests/TokenFormatUtilsTests CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "Test Case|TEST"
```
预期：FAIL（`friendlyModelName` 等符号未定义）

- [x] **步骤 3：在 `NotchDrop/TokenFormatUtils.swift` 编写实现**

定义 `CacheRateTier` 枚举与对应格式化方法：
```swift
public enum CacheRateTier: Equatable {
    case high    // >= 60% 翠绿
    case medium  // 30% ~ 60% 青蓝
    case low     // > 0% 暖琥珀
    case none    // 0% 灰
}

// 扩展 TokenFormatUtils
public static func friendlyModelName(_ full: String) -> String {
    let lower = full.lowercased()
    if lower.contains("flash-high") { return "Flash High" }
    if lower.contains("flash") { return "Flash" }
    if lower.contains("gemini") && lower.contains("pro") { return "Gemini Pro" }
    if lower.contains("sonnet") { return "Sonnet 3.5" }
    if lower.contains("opus") { return "Opus" }
    if lower.contains("haiku") { return "Haiku" }
    if lower.contains("gpt-4o") { return "GPT-4o" }
    if lower.contains("o1") { return "o1" }
    if lower.contains("o3") { return "o3" }
    return full
}

public static func cacheRateFraction(cached: Int, input: Int) -> Double {
    guard input > 0, cached > 0 else { return 0 }
    return min(1.0, max(0.0, Double(cached) / Double(input)))
}

public static func cacheRateTier(fraction: Double) -> CacheRateTier {
    if fraction >= 0.60 { return .high }
    if fraction >= 0.30 { return .medium }
    if fraction > 0 { return .low }
    return .none
}
```

- [x] **步骤 4：运行测试验证通过**

运行：
```bash
xcodebuild test -project NotchDrop.xcodeproj -scheme NotchDrop -destination 'platform=macOS' -only-testing:NotchEveryTests/TokenFormatUtilsTests CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "Test Case|TEST"
```
预期：`** TEST SUCCEEDED **`

- [x] **步骤 5：Commit**

```bash
git add NotchDrop/TokenFormatUtils.swift Tests/TokenFormatUtilsTests.swift
git commit -m "feat(token): add friendly model name and cache rate tier utils"
```

---

### 任务 2：数据管道透传 `cachedTokens` 与账号别名映射

**文件：**
- 修改：`NotchDrop/TokenZoneView.swift`
- 修改：`NotchDrop/UsageStore.swift`
- 修改：`Tests/AntigravityProxyStoreTests.swift`（若受构造器变更影响）

- [x] **步骤 1：更新 `TokenRequest` 数据结构**

在 `NotchDrop/TokenZoneView.swift` 中为 `TokenRequest` 新增 `public let cachedTokens: Int` 属性，并在 `init` 中赋予默认值 `cachedTokens: Int = 0` 保证兼容性。

- [x] **步骤 2：在 `UsageStore.swift` 中解析并填充 `cachedTokens`**

在 `AntigravityProxyStore.queryRecent` 中解析 SQLite 查询结果的 `cached_tokens`：
```swift
let cachedTokens = Int(sqlite3_column_int64(stmt, 9))
```
并在实例化 `TokenRequest` 时传入 `cachedTokens: cachedTokens`。

- [x] **步骤 3：运行数据层测试验证**

运行：
```bash
xcodebuild test -project NotchDrop.xcodeproj -scheme NotchDrop -destination 'platform=macOS' -only-testing:NotchEveryTests/AntigravityProxyStoreTests CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "Test Case|TEST"
```
预期：`** TEST SUCCEEDED **`

- [x] **步骤 4：Commit**

```bash
git add NotchDrop/TokenZoneView.swift NotchDrop/UsageStore.swift Tests/AntigravityProxyStoreTests.swift
git commit -m "feat(store): plumb cachedTokens through TokenRequest from proxy logs"
```

---

### 任务 3：`TokenZoneView` 视图层 3 栏平衡设计与去重重构

**文件：**
- 修改：`NotchDrop/TokenZoneView.swift`

- [ ] **步骤 1：移除冗余 `summaryBar` 与旧 `header`**

删除 `TokenZoneView` 顶部的 `summaryBar`（KPI 卡片，彻底消除与第一页大盘的重复）和旧平铺表头 `header`。

- [ ] **步骤 2：构建微型状态条 `liveBar`**

在顶部增加仅占 20pt 高度的 `liveBar`：
- 左侧：脉冲呼吸绿点 + 文字 "最近 5 笔请求流水"
- 右侧：文字 "模型/账号 · 用量分布 · 耗时"（或 "自动刷新 · 刚刚"）

- [ ] **步骤 3：重构 `TokenRowView` 为 3 栏平衡布局**

使用 `HStack(spacing: 8)` 组织三栏：
1. **左栏（身份）`colIdentity`（定宽约 130pt，左对齐）**：
   - 顶部：`TokenFormatUtils.friendlyModelName(row.model)` 紧凑徽标 + 账号名称（从 `AntigravityStore.shared.accounts` 查找匹配 `row.accountEmail` 的别名，若无则取邮箱前缀）
   - 底部：账号邮箱前缀或调用时间
2. **中栏（Token 分布与缓存比例）`colTokens`（弹性撑满，填补中间空白）**：
   - 顶部：总 Token（如 `170k`）+ 缓存命中率文字（如 `缓存 48%`，根据 `cacheRateTier` 映射为翠绿/青蓝/琥珀/灰）
   - 中间：纤细胶囊进度条（高 3px，底轨深灰透明，填色由 `cacheRateTier` 决定）
   - 底部：`入 170.1k` · `出 80`
3. **右栏（性能与时间）`colTiming`（定宽约 60pt，右对齐）**：
   - 顶部：耗时 `6.9s` + 状态呼吸圆点（200 绿点，>=400 红点+错误码）
   - 底部：时间 `20:53`

- [ ] **步骤 4：运行项目构建验证编译无误**

运行：
```bash
xcodebuild build -project NotchDrop.xcodeproj -scheme NotchDrop -destination 'platform=macOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -n 10
```
预期：`** BUILD SUCCEEDED **`

- [ ] **步骤 5：Commit**

```bash
git add NotchDrop/TokenZoneView.swift
git commit -m "feat(ui): redesign TokenZoneView to 3-column live stream layout"
```

---

### 任务 4：全量回归测试、安装部署与真机视觉验收

**文件：**
- 修改：无代码变更（部署与验证）

- [ ] **步骤 1：运行全量单元测试**

运行：
```bash
xcodebuild test -project NotchDrop.xcodeproj -scheme NotchDrop -destination 'platform=macOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -n 15
```
预期：`** TEST SUCCEEDED **`

- [ ] **步骤 2：构建 Release 归档并安装到 `/Applications/NotchEvery.app`**

```bash
xcodebuild -project NotchDrop.xcodeproj -scheme NotchDrop -configuration Release -derivedDataPath ./build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
killall NotchEvery || true
rm -rf /Applications/NotchEvery.app
cp -R ./build/Build/Products/Release/NotchEvery.app /Applications/
open /Applications/NotchEvery.app
```

- [ ] **步骤 3：请用户真机过目第二页视觉效果**

用户展开刘海滑到第二页，确认中间不再空洞、高度大幅降低且色彩分级清晰生效。
