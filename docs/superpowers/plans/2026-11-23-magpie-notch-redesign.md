# NotchEvery × Magpie 数据与刘海重构实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 NotchEvery 的数据源从 CC Switch SQLite 迁到只读 `~/.config/magpie/` 文件，并把刘海重构为 3 页（今日分布 / 实时流水 / 供应商额度）。

**Architecture:** 纯本地文件直读：`MagpiePaths` 解析白名单路径 → `MagpieUsageReader` 增量 tail JSONL（过滤探活、按 `rid` 去重）→ `MagpieFiles` 解析小 JSON → `MagpieAggregator` 纯函数聚合成 `MagpieSnapshot` → `MagpieStore`（ObservableObject）随面板开合启停、FSEvents + 1.5s 兜底刷新。UI 三页只读 snapshot，零硬编码供应商。

**Tech Stack:** Swift 5 / SwiftUI / AppKit / ServiceManagement / FSEvents / QuickLookThumbnailing；部署目标 macOS 13.0。

**Spec:** `docs/superpowers/specs/2026-11-23-magpie-notch-redesign-design.md`

## Global Constraints

- `MACOSX_DEPLOYMENT_TARGET = 13.0`；禁用 `@Observable`、`.snappy`、`containerRelativeFrame` 等 macOS 14+ API。状态发布用 `ObservableObject` + `@Published`。
- 只读白名单文件：`usage.jsonl`、`routing/YYYY-MM-DD.jsonl`、`masking/YYYY-MM-DD.jsonl`、`quotas.json`、`limit-notices.json`、`plugin-checkin.json`、`providers.json`、`plugin-providers.json`、`plugin-icons.json`、`gateway.json`、`quota-history.json`。
- **严禁读取** `logins.json`、`plugin-auth.json`、`caller-keys.json`、`redact.key`、`settings.json`、`sessions.json`；不请求 `127.0.0.1:3425`。
- 零硬编码供应商枚举：全部基于字符串 ID 动态建组。
- 绝不造假 0：无数据/无刻度显示 `—` / `无刻度`。
- 面板 `.closed`（非虚影）时零定时器、零轮询。
- UI 零 Emoji，全 SF Symbols；数字一律 `.monospacedDigit()`；动画全部尊重 `accessibilityReduceMotion`。
- 统一页面宽 `IslandMetrics.pageWidth = 420`；`IslandMetrics.panelContentInset = 18`（原 32）。
- 新文件入工程：`python3 scripts/add_file_to_project.py <paths...>`；删文件须同步清 `project.pbxproj` 节点。
- 测试命令（签名证书缺失，必须带 `CODE_SIGNING_ALLOWED=NO`）：
  `xcodebuild test -project NotchDrop.xcodeproj -scheme NotchDrop -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`
- 工作分支：`feature/magpie-notch`（从 `main` 切出，逐任务 commit）。基线：`main` 上 108 个测试全绿。

## Review Focus

以下 5 类输入/失败模式最可能咬人，各自在归属任务里有对应测试：

1. `usage.jsonl` 末尾半行（进程崩溃截断）→ offset 只推进到最后一个换行；补齐后该行恰好被读一次（Task 2）。
2. 跨午夜刷新、`routing/`|`masking/` 当日文件尚不存在 → 不得混入昨日数据、不得崩（Task 3）。
3. 小 JSON 写到一半（解析失败）→ 保留上次快照，不得闪 0/清空（Task 3 Store 测试）。
4. `limit-notices.json` 的 `until` 已过期、`limit == 0`、`amount > limit` → 不显示负数与假 0（Task 3 聚合测试）。
5. 长模型名/长供应商名/无物理刘海屏 → 文本截断不撑爆面板（Task 4/6 格式化测试 + 既有 `clampPanelSize` 护栏测试保留）。

---

### Task 1: 依赖清退（Pow / LaunchAtLogin-Modern / LookInside-Release / swift-collections）+ 原生开机自启 + 右键菜单直达

**Files:**
- Create: `NotchDrop/LoginItem.swift`
- Modify: `NotchDrop/AppDelegate.swift:10,36`
- Modify: `NotchDrop/NotchViewModel.swift:4`（删未使用的 `import LaunchAtLogin`）、`:187-192`（删 `showSettings` didSet 段）、`:430-445`（删 `showSettings` 属性和 `notchPop` 调用链之外的部分仅在 Task 7 处理 popping）
- Modify: `NotchDrop/PreferencesWindow.swift:10,104-112,160-172`
- Modify: `NotchDrop/NotchView.swift:129-146`（删 `.popover` 与 `NotchMenuView`；右键菜单改为 设置 / 打开 Magpie / 退出）
- Delete: `NotchDrop/Share.swift`、`NotchDrop/Share+View.swift`、`NotchDrop/NotchMenuView.swift`
- Modify: `NotchDrop.xcodeproj/project.pbxproj`（清 4 个 SPM 引用全部节点 + 3 个已删文件节点）
- Delete: `NotchDrop.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`（4 个包全删后无 SPM 依赖）
- Test: `Tests/TabMetricsTests.swift`（删 `testSettingsDismissedOnClosePreventsGhostPopover`）、Create `Tests/LoginItemTests.swift`

**Interfaces:**
- Produces: `enum LoginItem { static var isEnabled: Bool; static func setEnabled(_: Bool); static var wasLaunchedAtLogin: Bool }`。
  `wasLaunchedAtLogin` 镜像 LaunchAtLogin-Modern 实现：
  ```swift
  let event = NSAppleEventManager.shared().currentAppleEvent
  return event?.eventID == kAEOpenApplication
      && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
  ```

- [ ] **Step 0: 切分支**

```bash
git switch -c feature/magpie-notch
```

- [ ] **Step 1: 写 LoginItem + 失败/通过测试**

`Tests/LoginItemTests.swift`：`testIsEnabledDoesNotCrash`（读取 `LoginItem.isEnabled` 不崩，值为 Bool）、`testWasLaunchedAtLoginFalseInXCTest`（XCTest 环境断言 false）。

Run: 上述 xcodebuild 命令 → 预期 FAIL（`LoginItem` 不存在）。
实现 `NotchDrop/LoginItem.swift`（`import AppKit; import ServiceManagement`）：`isEnabled = SMAppService.mainApp.status == .enabled`；`setEnabled` 调 `register()`/`unregister()` 并吞错打日志；`wasLaunchedAtLogin` 用上面的镜像实现。跑测试 → PASS。

- [ ] **Step 2: 替换 LaunchAtLogin 引用**

`AppDelegate`：`import LaunchAtLogin` 删除，`LaunchAtLogin.wasLaunchedAtLogin` → `LoginItem.wasLaunchedAtLogin`。
`NotchViewModel`：删除 `import LaunchAtLogin`。
`PreferencesWindow`：删 `import LaunchAtLogin`；新增
```swift
@State private var launchAtLogin = LoginItem.isEnabled
```
`LaunchAtLogin.Toggle { Text("开机自启动") }` → `Toggle("开机自启动", isOn: $launchAtLogin).onChange(of: launchAtLogin) { LoginItem.setEnabled($0) }`（保留 `.toggleStyle(.switch)` 与既有 padding）。

- [ ] **Step 3: 右键菜单直达 + 删中间弹窗**

`NotchView.swift`：
- 删除 `.popover(isPresented: $vm.showSettings, arrowEdge: .top) { ... NotchMenuView ... }` 整段。
- `.contextMenu` 改为三项：`设置` → `vm.notchClose(); PreferencesWindowController.shared.show()`；`打开 Magpie` → `NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/magpie.app"))`；`退出` → `NSApp.terminate(nil)`。
- `NotchViewModel` 删除 `@Published var showSettings` 及其在 `didSet` / `closeToGhost` / `notchClose` 中的 `showSettings = false` 行。
- 删除 `Tests/TabMetricsTests.swift` 中的 `testSettingsDismissedOnClosePreventsGhostPopover`。

- [ ] **Step 4: 删文件 + pbxproj 清退**

```bash
rm NotchDrop/Share.swift NotchDrop/Share+View.swift NotchDrop/NotchMenuView.swift
```
`project.pbxproj` 删除这些所有节点（PBXBuildFile / PBXFileReference / 组 children / Sources phase）：3 个 Swift 文件；8 个 SPM 产品（`Pow`、`LaunchAtLogin`、`LookInsideServer`、`BitCollections`、`Collections`、`DequeModule`、`HashTreeCollections`、`HeapModule`）；4 个 `XCRemoteSwiftPackageReference`（含 `packageReferences` 列表项）与对应 `XCSwiftPackageProductDependency` 段；Frameworks phase 中 8 个产品条目；target 的 `packageProductDependencies` 条目。最后删 `Package.resolved`。

- [ ] **Step 5: 验证清退彻底**

```bash
grep -rn "import Pow\|import LaunchAtLogin\|LaunchAtLogin\.\|LookInside\|OrderedDictionary" NotchDrop/ Tests/ || echo CLEAN
grep -n "Pow\|LaunchAtLogin\|LookInside\|swift-collections" NotchDrop.xcodeproj/project.pbxproj || echo PBX_CLEAN
xcodebuild test -project NotchDrop.xcodeproj -scheme NotchDrop -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```
Expected: `CLEAN`、`PBX_CLEAN`、`** TEST SUCCEEDED **`（107 个测试）。

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "refactor(deps): 清退 4 个 SPM 依赖，开机自启改用 SMAppService，右键菜单直达"
```

---

### Task 2: Magpie 数据引擎核心 — 路径白名单 + JSONL 增量 tail + 探活过滤

**Files:**
- Create: `NotchDrop/MagpiePaths.swift`、`NotchDrop/MagpieModels.swift`、`NotchDrop/MagpieUsageReader.swift`
- Test: `Tests/MagpieUsageReaderTests.swift`
- Modify: `NotchDrop.xcodeproj/project.pbxproj`（用 `scripts/add_file_to_project.py`）

**Interfaces:**
- Produces:
```swift
struct MagpiePaths {
    let root: URL
    static var defaultRoot: URL                     // ~/.config/magpie
    init(root: URL = MagpiePaths.defaultRoot)
    var usageFile: URL
    func routingFile(day: String) -> URL            // routing/<day>.jsonl
    func maskingFile(day: String) -> URL
    var quotasFile, limitNoticesFile, pluginCheckinFile, providersFile,
        pluginProvidersFile, pluginIconsFile, gatewayFile, quotaHistoryFile: URL
    static func dayString(for date: Date, calendar: Calendar = .current) -> String   // "yyyy-MM-dd"
}

struct MagpieUsageRecord: Equatable {
    let id: String            // rid ?? "\(route_id ?? 0)-\(offset)"
    let routeID: Int64?; let time: Date
    let agent, provider, providerAccount, model, req: String
    let served: String?
    let inputTokens, outputTokens, cacheRead, cacheWrite, reasoning: Int
    let durationMs, ttftMs, maskingMs: Int?
    let status: Int?          // 缺省 = nil（聚合层归为异常）
    let handedOn: Bool
}

enum MagpieDate { static func parse(_ raw: String) -> Date? }

enum MagpieUsageReader {
    struct TailState: Equatable { var offset: UInt64; var inode: UInt64; static let empty: TailState }
    /// 增量读取新完整行→解码记录。inode 变或 size < offset 视为轮转，重置 offset；
    /// offset==0 的冷启动只读尾部 maxColdBytes（默认 4MB），从第一个完整行开始。
    /// 只消费到最后一个 "\n"（半行留待下次），offset 只推进到那里。
    static func readNewRecords(file: URL, state: inout TailState, maxColdBytes: Int = 4_000_000) -> [MagpieUsageRecord]
    static func decodeLine(_ data: Data, offset: UInt64) -> MagpieUsageRecord?   // 探活行返回 nil
    static func isProbe(kind: String?, source: String?) -> Bool                    // kind=="provider_test" || source=="probe"
}
```
- 解码用 `JSONDecoder` + 私有 `Decodable` 行类型（CodingKeys 映射 `route_id/cache_read/cache_write/ttft_ms/masking_ms/handed_on`）；过滤探活后构造 `MagpieUsageRecord`。
- `MagpieDate.parse`：把小数秒归一化为 3 位后交给 `ISO8601DateFormatter`（`.withInternetDateTime, .withFractionalSeconds`）；无小数秒回退不带 fractional 的 ISO8601。必须覆盖 `.254077+08:00`、`.35674+08:00`、`.841213+08:00`、`Z` 结尾。

- [ ] **Step 1: 写失败测试 `Tests/MagpieUsageReaderTests.swift`**

用例（fixture 全部写进 `FileManager.temporaryDirectory` 唯一子目录，测试后删除）：
1. `testDecodeBasicLine` — 完整真实行（含 `served/in/out/cache_read/ttft_ms/masking_ms/handed_on/rid/route_id`）全字段断言。
2. `testFilterProbeRows` — `kind:"provider_test"` 与 `source:"probe"` 各一行 → `decodeLine` 返回 nil，普通行非 nil。
3. `testVariableFractionTimestamps` — 5 位、6 位小数秒与 `Z` 结尾均解析成功（断言 `timeIntervalSince1970` 落在同一秒）。
4. `testIDFallsBackToRouteIDOffset` — 无 `rid` 行 → id == `"1795-42"` 形态（按传入 offset 断言）。
5. `testIncrementalTailReadsOnlyNewLines` — 写 2 行 → 读得 2 条 → 追加 1 行 → 再读只回 1 条且 offset == 文件大小。
6. `testPartialLineNotConsumedUntilCompleted` — 写 1 行 + 半行（无 `\n`）→ 只回 1 条；补 `\n` 后 → 回那 1 条且只回一次。
7. `testRotationResetsOffset` — 读完后把文件重写成更短内容 → 再读从头开始且读到新内容。
8. `testColdStartReadsOnlyTailWindow` — `maxColdBytes: 300` 时大文件只回尾部完整行。

Run: xcodebuild 命令 → FAIL（类型不存在）。

- [ ] **Step 2: 实现三个文件**

按 Interfaces 签名实现。要点：
- `TailState` 用 `stat` 取 inode（`st_ino`）与 size；用 `FileHandle` seek/read。
- 冷启动：`startOffset = size > maxColdBytes ? size - maxColdBytes : 0`；若 `> 0`，先跳到其后第一个 `\n`。
- 半行：`data.lastIndex(of: 0x0A)` 之前的字节才消费。
- 探活判定在完整 decode 之前先轻量检查 `kind`/`source` 字段（解码后可判，直接判解码结果即可）。

- [ ] **Step 3: pbxproj 注册 + 跑测试**

```bash
python3 scripts/add_file_to_project.py NotchDrop/MagpiePaths.swift NotchDrop/MagpieModels.swift NotchDrop/MagpieUsageReader.swift Tests/MagpieUsageReaderTests.swift
xcodebuild test ... CODE_SIGNING_ALLOWED=NO
Expected: 115 个测试全绿（107 + 8）
```

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat(magpie): 路径白名单 + JSONL 增量 tail + 探活过滤的用量记录读取器"
```

---

### Task 3: Magpie 聚合层 — 今日口径 / 三维分布 / 额度组 / 告警 / 签到 / 图标 + MagpieStore 门面

**Files:**
- Create: `NotchDrop/MagpieFiles.swift`、`NotchDrop/MagpieAggregator.swift`、`NotchDrop/MagpieStore.swift`、`NotchDrop/MagpieIconResolver.swift`
- Modify: `NotchDrop/MagpieModels.swift`（追加快照类型与 `MagpieRouteIndex` 等）
- Test: `Tests/MagpieFilesTests.swift`、`Tests/MagpieAggregatorTests.swift`、`Tests/MagpieStoreTests.swift`、`Tests/MagpieIconResolverTests.swift`

**Interfaces:**
- Consumes: Task 2 的 `MagpiePaths / MagpieUsageRecord / MagpieUsageReader / MagpieDate`。
- Produces:
```swift
enum DistributionDimension: String, CaseIterable, Identifiable, Hashable { case combo, provider, group
    var id: String { rawValue }; var title: String }   // "模型·提供商" / "提供商" / "Group"

struct DistributionItem: Equatable, Identifiable {
    let id, label: String; let secondaryLabel, detail: String?
    let tokenCount, cacheRead, calls: Int; let shareFraction: Double; let copyText: String }

struct MagpieFlowRow: Equatable, Identifiable {
    let id, agent, provider, account, model, requestedModel: String
    let groupName: String?
    let inputTokens, outputTokens, cacheRead: Int
    let durationMs, ttftMs, maskingMs: Int?
    let status: Int?; let handedOn: Bool; let maskedCount: Int; let time: Date }

enum ProviderLimitState: Equatable { case none, cooling(until: Date), rateLimited, riskBlocked
    var isActive: Bool; var severity: Int }    // riskBlocked 3 > cooling 2 > rateLimited 1 > none 0

struct MagpieWindow: Equatable, Identifiable { let id, name: String; let usedPercent, amount, limit: Double?
    let unit, display: String?; let resetsAt, runsOutAt: Date?; let isAside: Bool; let history: [Double] }

struct MagpieQuotaAccount: Equatable, Identifiable { let id, provider, label: String; let plan: String?
    let windows: [MagpieWindow]; let limitState: ProviderLimitState; let noticeMessage: String?
    let remaining, limit: Double?; let remainingFraction: Double? }

struct MagpieProviderGroup: Equatable, Identifiable { let id, name: String; let icon: String?
    let accounts: [MagpieQuotaAccount]; let limitState: ProviderLimitState
    let totalRemaining, totalLimit, fraction: Double?
    let availableAccounts, exhaustedAccounts: Int; let pendingCheckin: Bool }

struct MagpieCheckinSummary: Equatable { let claimedProviders: Int; let totalCredit: Double
    let pendingProviders: Int; let details: [String] }

enum MagpieGatewayState: Equatable { case online(version: String?); case offline }

struct MagpieSnapshot: Equatable {
    var hasMagpieDirectory: Bool; var todayNetTokens, todayCacheRead: Int; var todayCacheRate: Double?
    var todayRequestCount, todayErrorCount: Int; var todayAverageMs: Double?; var lastRequestAt: Date?
    var recentFlows: [MagpieFlowRow]; var distributions: [DistributionDimension: [DistributionItem]]
    var activeAlertCount, todayMaskedValues, todayMaskedRequests: Int
    var providerGroups: [MagpieProviderGroup]; var checkin: MagpieCheckinSummary
    var gateway: MagpieGatewayState; var refreshedAt: Date
    static let empty: MagpieSnapshot }

struct MagpieRouteIndex: Equatable {
    var groupNameByRouteID: [Int64: String]; var groupNameByRef: [String: String]
    var orderSnapshotsByProvider: [String: MagpieProviderOrderSnapshot] }
struct MagpieProviderOrderSnapshot: Equatable { let provider, name, icon, who, plan, unit: String?
    let used, amount, limit: Double? }

struct MagpieProviderCatalog: Equatable {
    struct Entry: Equatable { let id, name: String; let icon: String?; let hidden, disabled, signedIn: Bool }
    var entries: [String: Entry]; var groupNameByProviderRef: [String: String] }

enum MagpieFiles {
    static func parseQuotas(_ data: Data) -> [MagpieQuotaFileEntry]?
    static func parseLimitNotices(_ data: Data) -> [String: MagpieLimitNotice]?
    static func parseCheckins(_ data: Data) -> [MagpieCheckinFileEntry]?
    static func parseProviders(_ data: Data) -> MagpieProviderCatalog.ProviderPart?
    static func parsePluginProviders(_ data: Data) -> [MagpieProviderCatalog.PluginPart]?
    static func parsePluginIcons(_ data: Data) -> [String: String]?
    static func parseQuotaHistory(_ data: Data) -> [String: [String: [MagpieQuotaPoint]]]?
    static func parseGateway(_ data: Data) -> MagpieGatewayFile?
    static func parseRouteIndex(lines: [Data]) -> MagpieRouteIndex
    static func decodeMaskingLine(_ data: Data) -> MagpieMaskingEntry? }

enum MagpieAggregator {
    static func buildSnapshot(usage: [MagpieUsageRecord], routes: MagpieRouteIndex,
        masking: [MagpieMaskingEntry], quotas: [MagpieQuotaFileEntry],
        notices: [String: MagpieLimitNotice], checkins: [MagpieCheckinFileEntry],
        catalog: MagpieProviderCatalog, gateway: MagpieGatewayFile?,
        quotaHistory: [String: [String: [MagpieQuotaPoint]]],
        hasMagpieDirectory: Bool, now: Date, calendar: Calendar = .current,
        pidAlive: (Int32) -> Bool = { kill($0, 0) == 0 || errno != ESRCH }) -> MagpieSnapshot }
```
- 解析函数返回 `nil` **仅当数据无法解码**（调用方据此保留旧值）；空文件/空 JSON 对象返回空数组/字典。
- `MagpieStore`（ObservableObject 门面）：
```swift
final class MagpieStore: ObservableObject {
    static let shared = MagpieStore()
    @Published private(set) var snapshot: MagpieSnapshot
    @Published var distributionDimension: DistributionDimension   // P1 维度 + 耳区共用（默认 .combo）
    private(set) var isRunning: Bool
    init(paths: MagpiePaths = .init(), calendar: Calendar = .current, now: @escaping () -> Date = Date.init)
    func start(); func stop(); func catchUp() }

final class MagpieDirectoryWatcher {   // FSEvents，递归监听 root
    init(path: URL, queue: DispatchQueue = .main, onChange: @escaping () -> Void)
    func start(); func stop() }
```
- Store 内部：串行 `DispatchQueue(label: "MagpieStore.io")` 读盘+聚合；主线程发布；值级去重（`snapshot != new` 才赋值）。`start()` 幂等：立即 refresh 一次 → 启 1.5s `Timer`（`.common` mode）+ watcher（0.4s 去抖）；`stop()` 全部停、置 `isRunning = false`。跨天检测：每次 refresh 重算 `dayString`，变化时重置 routing/masking tail 状态。小 JSON 解析失败 → 保留上次值；`usage` 只保留今日记录（聚合前裁剪）。

- [ ] **Step 1: 写失败测试（4 个文件）**

`MagpieFilesTests`：quotas（`spans[i].aside` 平行数组、`used` 为百分数、`windows` 缺失容错）、limit-notices（`provider@account` 拆分、`until` 可缺省）、plugin-checkin（`provider|slot` 拆分、outcome 原样）、providers+pluginProviders 名称非空优先合并、routeIndex（`group.name`、同 routeID 覆盖、order 快照按 provider 取最新、`>200` 条裁剪保最近）、gateway、quota-history、损坏 JSON → nil。

`MagpieAggregatorTests`（核心，≥14 例）：
1. `testTodayOnlyFiltering` — 昨日记录不计入净 Token/请求数/平均耗时/lastRequestAt。
2. `testNetTokensAndCacheRate` — net = in+out；cacheRate = cacheRead/(in+cacheRead)；分母 0 → nil。
3. `testErrorCountExcludesCancelledAndHandedOn` — 499、`handed_on:true`、`status:nil` 规则：499 与 handedOn 不计，nil 计。
4. `testAverageMsOnlyCompletedToday`。
5. `testComboDistribution` — 键 `(provider, served ?? model)`、token 降序、shareFraction 全量分母。
6. `testProviderDistributionWithAccountAndModelCounts` — detail "2 账号 · 3 模型"。
7. `testGroupDistributionNamePriority` — routing 命中 > providers.json groups > "直连调用"。
8. `testActiveNoticeCount` — `until` nil / 过期 / 未来 三种计数。
9. `testProviderMergeIncludesCatalogPluginAndRoutingOnly` — hidden/disabled 排除；routing-only 渠道（无 quotas）也成组；名称优先级 name(非空) > plugin > quotas > id。
10. `testMainWindowSkipsAsideAndRemainingMath` — `aside` 过滤回退 `windows.first`；`remaining = max(0, limit-(amount ?? limit*used/100))`；`limit nil` → remainingFraction = max(0,1-used/100)；`used` 也 nil → `remainingFraction == nil`（无刻度）；`amount > limit` → remaining 0 不为负；`limit == 0` → 不计入总量。
11. `testGroupTotalsAndAccountAvailability` — totalRemaining/totalLimit/available/exhausted。
12. `testProviderSortingWeights` — 正常 < 有告警 < 耗尽 < 无刻度，同档按名。
13. `testCheckinClaimedDoneAndPending` — `claimed`+`done` 均计；`ineligible` 不计；`day != today` 不计；quotas 窗口名含 "今日未签" → pendingCheckin。
14. `testGatewayOnlineUsesInjectedPidAlive`。
15. `testMaskingSumsAndDistinctRoutes`。
16. `testQuotaHistoryJoinsWindowSparkline` — `<provider>|<account>` + 窗口名匹配，取最近 20 点。

`MagpieStoreTests`（fixture 目录注入）：
1. `testStartPublishesFixtureSnapshot` — 临时目录写今日 usage 一行 → `start()` → expectation 等 `snapshot.todayRequestCount == 1`。
2. `testStopHaltsTimersAndIsIdempotent` — `start()` → `isRunning == true`；再 `start()` 不重复；`stop()` → false；再 `stop()` 不崩。
3. `testCorruptSmallJSONKeepsPreviousSnapshot` — 先正常 refresh（providers 有值）→ 写坏 `quotas.json` → `catchUp()` → providerGroups 不清空不闪零。
4. `testMissingRoutingAndMaskingFilesDoNotCrash` — 目录只有 usage.jsonl。
5. `testMidnightRolloverPrunesYesterday` — `now` 注入为昨天 23:59 构建 snapshot，再注入今天 00:01 空目录 → 今日计数归零。
6. `testNoMagpieDirectory` — 不存在的 root → `hasMagpieDirectory == false`，其余为 empty 值。

`MagpieIconResolverTests`：
1. `testCandidateURLsOrder` — `file:x.svg` → cache 先、config icons 后；非 `file:` 先查 iconsMap 间接映射。
2. `testFallbackInitialAndDeterministicColor` — 同名同色、首字母大写。

Run: xcodebuild → FAIL（类型不存在）。

- [ ] **Step 2: 实现（按签名）**

关键口径（逐条落到代码）：
- 今日 = `calendar.startOfDay(for: now)` 起；聚合前裁掉旧记录。
- `recentFlows`：今日非探活按 time 降序取 5；`maskedCount` 由 masking 按 routeID 求和；`groupName` 解析同分布口径；`model = served ?? model`。
- `todayAverageMs`：今日非探活有 `durationMs` 记录均值；无 → nil。
- `activeAlertCount`：`until == nil || until! > now` 的条数。
- `ProviderLimitState.resolve(notice, now)`：`until > now → .cooling`；否则 `status 403/405 → .riskBlocked`；否则 `status 429 || why == "rate" → .rateLimited`；否则 `.none`。
- 分组 `limitState` = 各账号最严重（severity 最大）。
- `pendingCheckin`：任一窗口 `name/display` 含 "今日未签"。
- 图标 resolver：`NSImage(contentsOf:)` + `NSCache`；SVG 走 `QLThumbnailGenerator` 异步生成 32×32；兜底哈希渐变 + 首字母（`providerID` 的稳定哈希取色相）。

- [ ] **Step 3: pbxproj 注册 + 全量测试**

```bash
python3 scripts/add_file_to_project.py NotchDrop/MagpieFiles.swift NotchDrop/MagpieAggregator.swift \
  NotchDrop/MagpieStore.swift NotchDrop/MagpieIconResolver.swift \
  Tests/MagpieFilesTests.swift Tests/MagpieAggregatorTests.swift Tests/MagpieStoreTests.swift Tests/MagpieIconResolverTests.swift
xcodebuild test ... CODE_SIGNING_ALLOWED=NO
Expected: 全绿（新增 ≥30 例）
```

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat(magpie): 聚合层与 MagpieStore 门面（三维分布/额度组/告警/签到/图标）"
```

---

### Task 4: 第 1 页 — 今日用量分布（OverviewDistributionView）+ 页枚举更名

**Files:**
- Create: `NotchDrop/OverviewDistributionView.swift`、`NotchDrop/ProviderIconView.swift`、`NotchDrop/CopyFeedback.swift`
- Delete: `NotchDrop/OverviewPageView.swift`、`NotchDrop/ModelDistributionCardView.swift`
- Modify: `NotchDrop/NotchViewModel.swift`（`ContentType.normal → .overview`；`zoneOrder = [.overview, .token]`）
- Modify: `NotchDrop/NotchRootView.swift`（PageTransitionWrapper 分支、MagpieStore 生命周期）
- Modify: `NotchDrop/IslandMetrics.swift`（`panelContentInset = 18`；新增 `pageWidth: CGFloat = 420`）
- Modify: `Tests/ArrowKeyZoneSwitchTests.swift`、`Tests/ContentZoneSwitcherTests.swift`、`Tests/TabMetricsTests.swift`（`.normal → .overview`）
- Test: `Tests/CopyFeedbackTests.swift`、`Tests/MagpieStoreTests.swift` 不变；`Tests/TabMetricsTests` 增视图冒烟

**Interfaces:**
- Consumes: `MagpieStore.shared.snapshot`、`MagpieStore.shared.distributionDimension`、`DistributionItem`、`TokenFormatUtils`、`ProviderIconView`。
- Produces:
```swift
struct OverviewDistributionView: View { init(store: MagpieStore = .shared) }
struct ProviderIconView: View {          // 动态图标：PNG/WebP/JPG 同步，SVG 异步，失败渐变首字母
    init(icon: String?, providerID: String, size: CGFloat = 14) }
@MainActor final class CopyFeedback: ObservableObject {
    @Published private(set) var copiedID: String?
    init(resetDelay: TimeInterval = 1.5, pasteboard: NSPasteboard = .general)
    func copy(_ text: String, id: String) }   // 写剪贴板 + 置 copiedID + resetDelay 后清空
```

- [ ] **Step 1: 写失败测试**

`CopyFeedbackTests`：`testCopyWritesPasteboardAndSetsID`（自建 `NSPasteboard.withUniqueName()`）、`testCopiedIDResetsAfterDelay`（`resetDelay: 0.02` + expectation）。
`TabMetricsTests` 更新：`testPageZoneMapping` 改 `.overview`；新增 `testOverviewDistributionViewInstantiates`（临时空目录 `MagpieStore(paths: .init(root: temp))` → 建视图不崩）。

Run → FAIL。

- [ ] **Step 2: 实现页面**

`OverviewDistributionView`（宽 `IslandMetrics.pageWidth`）：
- 顶栏：绿点 + "今日用量分布" + 三段切换胶囊（`.combo/.provider/.group`，绑定 `store.distributionDimension`）+ 右侧净 Token `formatCompactTokens(...)`，无数据 `—`。
- `SegmentedProportionBar`（私有，复用旧调色板 `distributionPaletteColor(for:)`：emerald / 天空蓝 / 紫 / amber / 白 0.35）。
- Top 5 行：`.combo` = 模型徽标 + 提供商淡青标签；`.provider` = `ProviderIconView` + 名 + detail；`.group` = Group 名 + 命中提供商标签；右侧 `占比% · 净 Token · 缓存 XX%`（分级色）。
- 三态空态：无目录 / 有请求无可统计 / 今日暂无记录。
- 底栏：`缓存命中 X.XM` + `shield.lefthalf.filled` + `今日脱敏 N 项 (M 次)`。
- 行点击：`CopyFeedback.copy(item.copyText, id:)`；复制成功行尾显示 `checkmark` + `已复制` 1.5s。
- `TokenFormatUtils.displayModelNames` + `friendlyModelName` 沿用。

- [ ] **Step 3: 页枚举更名 + 接线**

`ContentType: Int` 保持 2 例但 `normal → overview`（`case overview, token`）；全仓 `\.normal` 引用同步；`NotchRootView` 分支 `.overview → OverviewDistributionView()`；`onAppear/onChange` 增加 `MagpieStore.shared.start()/stop()`（保留 UsageStore/AntigravityStore 生命周期到 Task 7）；删 `OverviewPageView.swift`、`ModelDistributionCardView.swift` 并在 pbxproj 删节点；`IslandMetrics` 两处常量更新。

- [ ] **Step 4: 注册 + 全量测试**

```bash
python3 scripts/add_file_to_project.py NotchDrop/OverviewDistributionView.swift NotchDrop/ProviderIconView.swift NotchDrop/CopyFeedback.swift Tests/CopyFeedbackTests.swift
xcodebuild test ... CODE_SIGNING_ALLOWED=NO
Expected: 全绿
```

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(ui): 第 1 页切换为 Magpie 今日用量三维分布（模型·提供商/提供商/Group）"
```

---

### Task 5: 第 2 页 — 实时流水（暂停定格 / 点击复制 / 新行绿闪）

**Files:**
- Create: `NotchDrop/FlowPauseController.swift`
- Rewrite: `NotchDrop/TokenZoneView.swift`
- Modify: `NotchDrop/UsageStore.swift`（把 `TokenRequest`、`TokenSummary` 两个模型 struct 原样搬入本文件，Task 7 随 UsageStore 一起删除）
- Test: `Tests/FlowPauseControllerTests.swift`

**Interfaces:**
- Consumes: `MagpieFlowRow`、`MagpieStore.snapshot`、`CopyFeedback`。
- Produces:
```swift
struct FlowPauseController: Equatable {
    private(set) var isPaused: Bool
    private(set) var frozenRows: [MagpieFlowRow]   // 暂停时冻结的最近 5 条
    private(set) var missedCount: Int              // 暂停期间新增条数（去重累计）
    private(set) var gapCount: Int                 // 待读队列溢出丢弃条数（跨恢复保留）
    mutating func pause(liveRows: [MagpieFlowRow])
    mutating func receive(liveRows: [MagpieFlowRow])   // 暂停中调用；队列上限 200，溢出丢最旧 + gapCount += 1
    mutating func resume(liveRows: [MagpieFlowRow]) -> Int   // 返回 gapCount（调用方展示后决定何时清）
    static let pendingCapacity = 200 }
struct TokenZoneView: View { init(store: MagpieStore = .shared) }
```

- [ ] **Step 1: 写失败测试 `FlowPauseControllerTests`**

1. `testPauseFreezesRows` — pause 后 `frozenRows == liveRows`、`isPaused`。
2. `testReceiveAccumulatesMissedAndDedupes` — 新行计入 missedCount，重复 id 不重复计。
3. `testQueueOverflowIncrementsGap` — 塞 250 条新行 → gapCount == 50、队列 ≤ 200。
4. `testResumeReturnsGapAndUnfreezes` — resume 返回 gapCount；`isPaused == false`；gapCount 保留。
5. `testReceiveWhileNotPausedIsNoop`。

Run → FAIL。

- [ ] **Step 2: 实现控制器 + 页面**

`TokenZoneView`（宽 `IslandMetrics.pageWidth`）：
- Live Bar：状态点 + "最近 5 笔流水" + 右侧状态文案（暂停优先 `已暂停 · M 条未读`，gap>0 追加 `缺口 G`；正常 `N 请求 · E 错 · 均耗时`）+ 右端 `pause.fill`/`play.fill` 按钮。
- 单行三栏（左 145 / 中 175 / 右 70）：
  - 左：`ProviderIconView` + `friendlyModelName(served ?? model)`；副行 `provider · groupName(或 直连) · agent`。
  - 中：净 Token + `缓存 XX%`（无命中显示 `入 X · 出 Y`）；3pt 缓存条；`入 X · 出 Y` + `maskedCount > 0` 时 `shield` + N。
  - 右：总耗时 `X.Xs` + 状态点（200 emerald / 499 灰 / 429 amber / ≥400 rose）；副行 `TTFT X.Xs` 优先，否则 `HH:mm:ss`；失败行 `HTTP <status>`；`handedOn` 行 `已切备用`。
- 新行绿闪：纯 `withAnimation` + `@State flashOpacity`，`reduceMotion` 时跳过；沿用 `lastFirstID` 首帧不闪。
- 行点击逐笔复制排查摘要：`"\(time) \(provider)@\(account) \(model) \(status) \(durationMs)ms ttft=\(ttftMs) rid=\(id)"`，`CopyFeedback` 反馈。
- 暂停时展示 `pause.frozenRows`，恢复时展示 `snapshot.recentFlows`。

- [ ] **Step 3: 注册 + 全量测试**

```bash
python3 scripts/add_file_to_project.py NotchDrop/FlowPauseController.swift Tests/FlowPauseControllerTests.swift
xcodebuild test ... CODE_SIGNING_ALLOWED=NO
Expected: 全绿
```

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat(ui): 第 2 页实时流水接入 Magpie，新增暂停定格/缺口计数/点击复制"
```

---

### Task 6: 第 3 页 — 供应商额度与限流状态（手风琴 + 水位条 + 签到 + 网关）

**Files:**
- Create: `NotchDrop/ProviderQuotaZoneView.swift`、`NotchDrop/ProviderQuotaFormat.swift`
- Modify: `NotchDrop/NotchViewModel.swift`（`case providers`；`zoneOrder = [.overview, .token, .providers]`）
- Modify: `NotchDrop/NotchRootView.swift`（PageTransitionWrapper `.providers` 分支）
- Modify: `Tests/ArrowKeyZoneSwitchTests.swift`、`Tests/ContentZoneSwitcherTests.swift`、`Tests/TabMetricsTests.swift`（三页断言）
- Test: `Tests/ProviderQuotaFormatTests.swift`

**Interfaces:**
- Consumes: `MagpieProviderGroup`、`MagpieSnapshot`、`ProviderIconView`、`IslandMetrics.pageWidth`。
- Produces:
```swift
struct ProviderQuotaZoneView: View { init(store: MagpieStore = .shared) }
enum ProviderQuotaFormat {
    static func remainingText(_ group: MagpieProviderGroup) -> String       // "88 / 4600" | "余 13%" | "无刻度"
    static func noticeBadge(_ state: ProviderLimitState, now: Date, timeZone: TimeZone) -> String?
        // "403 风控" | "429 限流" | "冷却至 HH:mm" | nil
    static func countdown(_ date: Date, now: Date) -> String                // "12h 过期" | "34m 过期" | "已过期"
    static func accountSummary(_ group: MagpieProviderGroup) -> String?     // "1 号可用 · 2 号耗尽" | nil（单账号返回 nil）
    static func checkinText(_ checkin: MagpieCheckinSummary) -> String      // "今日签到：4 家已领 +400" | "今日暂无签到"
    static func gatewayText(_ state: MagpieGatewayState) -> String          // "Magpie :3425 在线 v0.1.4692" | "网关未运行"
}
```

- [ ] **Step 1: 写失败测试 `ProviderQuotaFormatTests`**

覆盖：剩余文案三态（有 limit / 仅百分比 / 无刻度）、告警徽标四态、倒计时三态（小时/分钟/已过期）、多账号摘要与单账号 nil、签到文案（含 0 → "今日暂无签到"）、网关文案。另在 `TabMetricsTests`/`ContentZoneSwitcherTests` 更新三页顺序断言（`[.overview, .token, .providers]`，`.providers` 越界回 `.overview` 规则保持）。

Run → FAIL。

- [ ] **Step 2: 实现**

`ProviderQuotaZoneView`（宽 `IslandMetrics.pageWidth`）：
- 顶栏：状态点（有活跃告警 → amber/rose）+ "供应商额度与积分" + 右侧 `点击行展开明细` 或 `N 家受限`。
- `ScrollView` 限制 `maxHeight: 220`，行间距 4。
- 折叠行（每家 1 行）：状态点 + `ProviderIconView` + 名称 +（`N 账号` 徽标，>1 时）+（限流/冷却徽标）+ 右侧水位条（`Capsule` 背景 + 前景按 fraction，无刻度画全灰）+ `剩余/上限` 或 `余 XX%` 或 `无刻度`；副行：`countdown(runsOutAt)` / `accountSummary` / "可签到"。
- 手风琴：`@State expandedProviderID: String?`，点击行切换（同时只展开一家）；展开区列账号：脱敏 `label` + `plan` + 每窗口一行（名称 + 水位条 + `used/limit` + `resetsAt`/`runsOutAt`）+ `noticeMessage` 截断 2 行 + 主窗口 `Sparkline(history:)`（纯 `Path`，最近 20 点）。
- 底栏：`checkinText` + 网关状态（绿点/灰点 + `gatewayText`）。
- 空态：无 `providerGroups` → "未检测到供应商数据"。

- [ ] **Step 3: 三页接线**

`ContentType` 增 `case providers`（`Int` rawValue 3）；`zoneOrder` 三页；`NotchRootView` 加分支；`SmoothPageIndicator` 自动跟随 `zoneOrder.count`。

- [ ] **Step 4: 注册 + 全量测试 + Commit**

```bash
python3 scripts/add_file_to_project.py NotchDrop/ProviderQuotaZoneView.swift NotchDrop/ProviderQuotaFormat.swift Tests/ProviderQuotaFormatTests.swift
xcodebuild test ... CODE_SIGNING_ALLOWED=NO
git add -A && git commit -m "feat(ui): 第 3 页供应商额度与限流状态（手风琴明细/水位条/签到/网关）"
```

---

### Task 7: 清退旧数据层 + 耳区/Peek 按页渲染 + 设置页数据源 + 最终验证

**Files:**
- Delete: `NotchDrop/UsageStore.swift`、`NotchDrop/AntigravityStore.swift`、`Tests/UsageMetricsTests.swift`、`Tests/AntigravityStoreTests.swift`、`Tests/AntigravityProxyStoreTests.swift`
- Modify: `NotchDrop/NotchView.swift`（删 drag/popping/usage；Peek 改 Magpie）
- Modify: `NotchDrop/NotchViewModel.swift`（删 `Status.popping`、`notchPop`、`dropDetectorRange`）
- Modify: `NotchDrop/NotchViewModel+Events.swift`（删 popping 分支与 haptic filter）
- Modify: `NotchDrop/NotchRootView.swift`（删旧 Store 生命周期；三页耳区；hover catch-up）
- Modify: `NotchDrop/PreferencesWindow.swift`（"反代数据源" → `Magpie (~/.config/magpie)` + 网关状态行）
- Create: `NotchDrop/EarSummary.swift`
- Modify: `NotchDrop.xcodeproj/project.pbxproj`（删 `libsqlite3.tbd` 与全部已删文件节点）
- Test: `Tests/EarSummaryTests.swift`

**Interfaces:**
- Consumes: `MagpieStore.snapshot`、`MagpieStore.distributionDimension`、`DistributionDimension`。
- Produces:
```swift
enum EarSummary {
    static func overviewLeft(dimension: DistributionDimension, snapshot: MagpieSnapshot) -> String?
    static func overviewRight(snapshot: MagpieSnapshot, calendar: Calendar = .current) -> (time: String?, alerts: Int)
    static func flowLeft(snapshot: MagpieSnapshot) -> String?          // 最近一笔 provider 名
    static func flowRight(snapshot: MagpieSnapshot) -> (requests: String, alerts: Int)
    static func providersLeft(snapshot: MagpieSnapshot) -> (text: String, hasAlert: Bool)
    static func providersRight(snapshot: MagpieSnapshot) -> (checkin: String?, alerts: Int)
}
```

- [ ] **Step 1: 写失败测试 `EarSummaryTests`**

三页耳区各断言：P1 左耳随 dimension 变（`3 个活跃组合` / `2 家提供商` / `1 个路由组`），右耳 `HH:mm` 与 alerts；P2 左右；P3 左耳告警态（`2 家受限`）与正常态（`2 家供应商`）、右耳签到 `+400`；无数据 → nil / 0。

- [ ] **Step 2: Peek + 耳区 + 生命周期**

- `NotchView` Peek：左 = 状态点（活跃告警 amber/rose，否则 emerald）+ `最近 provider · friendlyModelName(model)`；右 = 今日净 Token + `· XX.X%`（cyan 缓存率）+ alerts>0 时 `exclamationmark.triangle` + N。空态：无目录 → "等待 Magpie 数据"；有目录 0 请求 → "Magpie 就绪 · 今日 0 请求"。删除 `usage` StateObject 与所有 `usage.*` 引用。
- `NotchRootView`：删除 UsageStore/AntigravityStore 生命周期；`MagpieStore` 生命周期补齐：`.onChange(of: vm.hoverGhosting)` 为 true 时 `MagpieStore.shared.catchUp()`；三页耳区按 `EarSummary` 渲染、等高占位；`⚠ N` 可点 → `vm.jumpToZone(.providers)`。
- 删除 `Status.popping`、`notchPop()`、`dropDetectorRange`、`dragDetector`、`dropTargeting`；事件层同步收敛。

- [ ] **Step 3: 设置页 + 工程清理**

- `PreferencesWindow` "关于与状态"：`反代数据源` → `Magpie (~/.config/magpie)`；新增一行 `网关` → 绿点 + `:3425 在线` / 灰点 `未运行`（读 `MagpieStore.shared.snapshot.gateway`）。
- pbxproj：删 `libsqlite3.tbd`（PBXFileReference/PBXBuildFile/Frameworks/组）及 Task 1/4/7 所有已删文件节点；删已删测试文件节点。

- [ ] **Step 4: 最终全量验证**

```bash
xcodebuild test -project NotchDrop.xcodeproj -scheme NotchDrop -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
Expected: ** TEST SUCCEEDED **（全绿）
xcodebuild build -project NotchDrop.xcodeproj -scheme NotchDrop -configuration Release -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
Expected: ** BUILD SUCCEEDED **
grep -rn "SQLite3\|UsageStore\|AntigravityStore\|import Pow\|LaunchAtLogin\|libsqlite3" NotchDrop/ Tests/ NotchDrop.xcodeproj/project.pbxproj || echo LEGACY_CLEAN
Expected: LEGACY_CLEAN
```

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "refactor: 清退 CC Switch/Antigravity 旧数据层，三页耳区与 Peek 接入 Magpie"
```

---

## Self-Review 记录

- **Spec 覆盖**：§5.1 文件白名单与 schema → Task 2/3；§5.2 增量与防空转 → Task 2/3；§5.3 口径（net/cache/探活/499/handed_on/⚠N）→ Task 3；§5.3 三维聚合 → Task 3；§5.3 额度组 → Task 3；§5.3 图标 → Task 3/4；§6.1 页面结构 → Task 4/5/6；§6.2 Peek → Task 7；§6.3 耳区 → Task 7；§6.4 三页 → Task 4/5/6；§6.5 设置/菜单/删除/依赖 → Task 1/7。非目标（BallPit、HTTP API、写操作）全篇未触碰。
- **类型一致性**：`MagpieSnapshot` 字段在 Task 3 定义、Task 4/5/6/7 消费；`DistributionDimension` 定义于 Task 3，Task 4/7 使用；`ProviderIconView` Task 4 定义、Task 6 使用。
- **未覆盖预留**：`quota-history` 只做主窗口 sparkline；`pendingCheckin` 只做提示不推断积分数（数据源无此字段）。
