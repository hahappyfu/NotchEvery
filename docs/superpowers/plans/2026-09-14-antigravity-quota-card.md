# 首页配额卡换源（Antigravity Tools 4账号池）实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 subagent-driven-development（推荐）或 executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 将 NotchEvery 首页概览中的旧 OpenCodeGo 配额环彻底替换为 Antigravity Tools 本地 4 账号池仪表盘，直观展示各 Gemini 反代账号的额度百分比、活跃状态与重置倒计时。

**架构：** 
- 新建 `NotchDrop/AntigravityStore.swift`：纯本地文件读取单例（无网络开销），利用 libc `getpwuid` 直读 `~/.antigravity_tools/accounts.json` 与 `accounts/*.json`，聚合解析各账号名、当前活跃标记、Gemini 共享配额百分比与 ISO8601 重置时间，主线程去重发布。随面板展开/收起自动启停 15s 轮询。
- 新建 `NotchDrop/AntigravityAccountsCardView.swift`：宽度固定 360pt，顶部展示活跃账号名，中间横向均分 4 账号微型额度环（直径 44pt，语义色着色，当前活跃账号附带强调边框），底部显示就绪或倒计时文本。
- 在 `NotchDrop/OverviewPageView.swift` 中无缝替换 `QuotaCardView`。
- 清理废弃的 `QuotaSnapshot.swift`、`QuotaStore.swift`、`QuotaCardView.swift` 及其单测，更新 Xcode 项目文件引用。

**技术栈：** Swift 5.9, SwiftUI, Combine, XCTest, macOS 13.0+ API。
**测试与验证命令：** `xcodebuild test -project NotchDrop.xcodeproj -scheme NotchDrop -destination 'platform=macOS' -derivedDataPath /tmp/nDD CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO -only-testing:NotchEveryTests/AntigravityStoreTests`

**规格：** `docs/superpowers/specs/2026-09-14-antigravity-quota-and-guard-settings-design.md`

## 全局约束

- 严禁引入任何未预装第三方依赖或直接向外部网络发包，仅读取本地 `~/.antigravity_tools` 目录。
- 遵循 macOS 13+ 兼容性约束，禁止使用 macOS 14+ 独占 API（如 `@Observable`、`.scrollPosition` 等）。
- 视图必须维持固定宽度 360pt，内边距 `horizontal: 18, vertical: 12`，背景采用 `Color.white.opacity(0.06)`，圆角 12pt，与下方 `GuardCardView` 保持完全一致的视觉韵律。
- 遵守 ADHD & Ponytail 规范：最小代码量，复用现有常量与样式，代码先于注释。

---

## 文件结构

- 创建：`NotchDrop/AntigravityStore.swift` —— 账号与配额数据模型、本地 JSON 解析、倒计时格式化、轮询管理。
- 创建：`NotchDrop/AntigravityAccountsCardView.swift` —— 4 账号横向环形仪表盘 SwiftUI 视图。
- 修改：`NotchDrop/OverviewPageView.swift` —— 将 `QuotaCardView` 替换为 `AntigravityAccountsCardView`。
- 创建：`Tests/AntigravityStoreTests.swift` —— 测试 JSON 解析容错、当前活跃账号识别、百分比计算与倒计时文本。
- 删除：`NotchDrop/QuotaSnapshot.swift`、`NotchDrop/QuotaStore.swift`、`NotchDrop/QuotaCardView.swift`、`Tests/QuotaSnapshotTests.swift`。
- 修改：`NotchDrop.xcodeproj/project.pbxproj` —— 更新文件引用与编译目标。

---

### 任务 1：数据层——AntigravityStore 模型、解析器与单测

**文件：**
- 创建：`NotchDrop/AntigravityStore.swift`
- 创建：`Tests/AntigravityStoreTests.swift`
- 修改：`NotchDrop.xcodeproj/project.pbxproj`

- [ ] **步骤 1：编写 AntigravityStoreTests 失败单测**

创建 `Tests/AntigravityStoreTests.swift`：

```swift
import XCTest
@testable import NotchEvery

final class AntigravityStoreTests: XCTestCase {
    func testFormatCountdown() {
        let now = Date(timeIntervalSince1970: 1789370000)
        // 已过期或就绪
        XCTAssertEqual(AntigravityStore.formatCountdown(from: nil, now: now), "已就绪")
        XCTAssertEqual(AntigravityStore.formatCountdown(from: Date(timeIntervalSince1970: 1789369000), now: now), "已就绪")
        
        // 2小时27分后重置
        let future = Date(timeIntervalSince1970: 1789370000 + 2 * 3600 + 27 * 60)
        XCTAssertEqual(AntigravityStore.formatCountdown(from: future, now: now), "2h27m")
        
        // 45分钟后重置
        let soon = Date(timeIntervalSince1970: 1789370000 + 45 * 60)
        XCTAssertEqual(AntigravityStore.formatCountdown(from: soon, now: now), "45m")
    }

    func testParseAccountDetails() throws {
        let jsonStr = """
        {
          "id": "test-account-1",
          "name": "测试账号",
          "email": "test@example.com",
          "disabled": false,
          "proxy_disabled": false,
          "quota": {
            "models": [
              {
                "name": "gemini-3.1-pro-high",
                "percentage": 85,
                "reset_time": "2026-09-14T15:30:00Z"
              },
              {
                "name": "gemini-3.5-flash-low",
                "percentage": 85,
                "reset_time": "2026-09-14T15:30:00Z"
              }
            ]
          }
        }
        """
        let data = jsonStr.data(using: .utf8)!
        let account = try XCTUnwrap(AntigravityStore.parseAccountFile(data: data, currentAccountId: "test-account-1"))
        
        XCTAssertEqual(account.id, "test-account-1")
        XCTAssertEqual(account.name, "测试账号")
        XCTAssertEqual(account.email, "test@example.com")
        XCTAssertTrue(account.isCurrent)
        XCTAssertFalse(account.isDisabled)
        XCTAssertEqual(account.percentage, 85)
        XCTAssertNotNil(account.resetTime)
    }

    func testParseAccountsIndex() {
        let jsonStr = """
        {
          "version": "2.0",
          "accounts": [
            { "id": "acc-1", "name": "A1" },
            { "id": "acc-2", "name": "A2" }
          ],
          "current_account_id": "acc-2"
        }
        """
        let data = jsonStr.data(using: .utf8)!
        let index = AntigravityStore.parseIndex(data: data)
        XCTAssertEqual(index?.currentAccountId, "acc-2")
        XCTAssertEqual(index?.accountIds, ["acc-1", "acc-2"])
    }
}
```

- [ ] **步骤 2：在 project.pbxproj 中注册 AntigravityStore 与 AntigravityStoreTests**

复用原有 `QuotaStore.swift` 与 `QuotaSnapshotTests.swift` 的 PBX 文件引用节点，保持工程结构稳定：
- `C1D2E3F4A506172839404154`：文件名与路径改为 `AntigravityStore.swift`。
- `7AE10C0220260AB000000C3`：文件名与路径改为 `AntigravityStoreTests.swift`。

- [ ] **步骤 3：实现 AntigravityStore.swift**

创建 `NotchDrop/AntigravityStore.swift`：

```swift
//
//  AntigravityStore.swift
//  NotchEvery
//
//  Antigravity Tools 账号池与配额本地数据源（直读 ~/.antigravity_tools）。
//

import Combine
import Foundation
import os.log

private let antiLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "NotchEvery", category: "AntigravityStore")

struct AntigravityAccount: Identifiable, Equatable {
    let id: String
    let name: String
    let email: String
    let isCurrent: Bool
    let isDisabled: Bool
    let percentage: Int
    let resetTime: Date?
    let resetCountdownText: String
}

struct AntigravityIndex: Equatable {
    let currentAccountId: String?
    let accountIds: [String]
}

final class AntigravityStore: ObservableObject {
    static let shared = AntigravityStore()

    @Published private(set) var accounts: [AntigravityAccount] = []
    @Published private(set) var currentAccountId: String?

    static let defaultBaseDir: URL = {
        let base: URL
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            base = URL(fileURLWithPath: String(cString: dir))
        } else {
            base = FileManager.default.homeDirectoryForCurrentUser
        }
        return base.appendingPathComponent(".antigravity_tools")
    }()

    private let baseDir: URL
    private let interval: TimeInterval
    private var timer: Timer?
    private var refreshing = false

    init(baseDir: URL = AntigravityStore.defaultBaseDir, interval: TimeInterval = 15) {
        self.baseDir = baseDir
        self.interval = interval
    }

    func start() {
        guard timer == nil else { return }
        refresh()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        antiLog.info("AntigravityStore started, interval \(self.interval)s")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

#if DEBUG
    func seedForPreview(accounts: [AntigravityAccount], currentId: String? = nil) {
        self.accounts = accounts
        self.currentAccountId = currentId
    }
#endif

    func refresh() {
        guard !refreshing else { return }
        refreshing = true
        let dir = baseDir
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let parsed = Self.fetchAccounts(from: dir)
            DispatchQueue.main.async {
                guard let self else { return }
                self.refreshing = false
                if self.accounts != parsed.accounts {
                    self.accounts = parsed.accounts
                }
                if self.currentAccountId != parsed.currentId {
                    self.currentAccountId = parsed.currentId
                }
                antiLog.info("AntigravityStore refreshed: \(parsed.accounts.count) accounts, current: \(parsed.currentId ?? "none")")
            }
        }
    }

    static func fetchAccounts(from baseDir: URL, now: Date = Date()) -> (accounts: [AntigravityAccount], currentId: String?) {
        let indexURL = baseDir.appendingPathComponent("accounts.json")
        guard let indexData = try? Data(contentsOf: indexURL),
              let index = parseIndex(data: indexData) else {
            return ([], nil)
        }

        let accountsDir = baseDir.appendingPathComponent("accounts")
        var result: [AntigravityAccount] = []

        for id in index.accountIds {
            let fileURL = accountsDir.appendingPathComponent("\(id).json")
            guard let data = try? Data(contentsOf: fileURL),
                  let acc = parseAccountFile(data: data, currentAccountId: index.currentAccountId, now: now) else {
                continue
            }
            result.append(acc)
        }

        return (result, index.currentAccountId)
    }

    static func parseIndex(data: Data) -> AntigravityIndex? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let currentId = obj["current_account_id"] as? String
        var ids: [String] = []
        if let list = obj["accounts"] as? [[String: Any]] {
            for item in list {
                if let id = item["id"] as? String {
                    ids.append(id)
                }
            }
        }
        return AntigravityIndex(currentAccountId: currentId, accountIds: ids)
    }

    static func parseAccountFile(data: Data, currentAccountId: String?, now: Date = Date()) -> AntigravityAccount? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = obj["id"] as? String else { return nil }

        let name = obj["name"] as? String ?? (obj["email"] as? String ?? "未命名")
        let email = obj["email"] as? String ?? ""
        let disabled = (obj["disabled"] as? Bool) ?? false
        let proxyDisabled = (obj["proxy_disabled"] as? Bool) ?? false
        let isDisabled = disabled || proxyDisabled

        var geminiPct = 100
        var resetDate: Date?

        if let quota = obj["quota"] as? [String: Any],
           let models = quota["models"] as? [[String: Any]] {
            let geminiModels = models.filter { m in
                let mName = (m["name"] as? String ?? "").lowercased()
                return mName.contains("gemini")
            }
            let targetModels = geminiModels.isEmpty ? models : geminiModels
            if let first = targetModels.first {
                geminiPct = (first["percentage"] as? Int) ?? 100
                if let resetStr = first["reset_time"] as? String {
                    resetDate = parseISO8601(resetStr)
                }
            }
        }

        let isCurrent = (id == currentAccountId)
        let countdown = formatCountdown(from: resetDate, now: now)

        return AntigravityAccount(
            id: id,
            name: name,
            email: email,
            isCurrent: isCurrent,
            isDisabled: isDisabled,
            percentage: max(0, min(100, geminiPct)),
            resetTime: resetDate,
            resetCountdownText: countdown
        )
    }

    static func formatCountdown(from resetTime: Date?, now: Date = Date()) -> String {
        guard let resetTime else { return "已就绪" }
        let diff = resetTime.timeIntervalSince(now)
        if diff <= 0 { return "已就绪" }
        let hours = Int(diff) / 3600
        let minutes = (Int(diff) % 3600) / 60
        if hours > 0 {
            return "\(hours)h\(minutes)m"
        } else {
            return "\(max(1, minutes))m"
        }
    }

    private static func parseISO8601(_ str: String) -> Date? {
        if #available(macOS 10.12, *) {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = f.date(from: str) { return d }
            f.formatOptions = [.withInternetDateTime]
            return f.date(from: str)
        }
        return nil
    }
}
```

- [ ] **步骤 4：运行测试确认通过**

运行测试：
```bash
xcodebuild test -project NotchDrop.xcodeproj -scheme NotchDrop -destination 'platform=macOS' -derivedDataPath /tmp/nDD CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO -only-testing:NotchEveryTests/AntigravityStoreTests
```
预期：TEST SUCCEEDED，3 个测试全部通过。

- [ ] **步骤 5：Commit 数据层变更**

```bash
git add NotchDrop/AntigravityStore.swift Tests/AntigravityStoreTests.swift NotchDrop.xcodeproj/project.pbxproj
git commit -m "feat(antigravity): 新增 AntigravityStore 数据源与解析单测"
```

---

### 任务 2：UI 层——AntigravityAccountsCardView 与页面接入

**文件：**
- 创建：`NotchDrop/AntigravityAccountsCardView.swift`
- 修改：`NotchDrop/OverviewPageView.swift`
- 修改：`NotchDrop.xcodeproj/project.pbxproj`

- [ ] **步骤 1：创建 AntigravityAccountsCardView.swift**

创建 `NotchDrop/AntigravityAccountsCardView.swift`：

```swift
//
//  AntigravityAccountsCardView.swift
//  NotchDrop
//
//  首页 Antigravity 4账号池仪表盘（替换旧 OpenCodeGo 配额卡）。
//  宽度固定 360pt，内边距与 GuardCardView 严格一致，不撑大面板。
//

import SwiftUI

struct AntigravityAccountsCardView: View {
    @StateObject var vm: NotchViewModel
    @StateObject var store = AntigravityStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static func ringColor(_ percent: Int, isDisabled: Bool) -> Color {
        if isDisabled { return Color.white.opacity(0.2) }
        if percent >= 70 { return Color(red: 0.16, green: 0.75, blue: 0.38) }
        if percent >= 30 { return Color.orange }
        return Color(red: 0.85, green: 0.25, blue: 0.2)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            accountsRow
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(width: 360)
        .onAppear { store.start() }
        .onChange(of: vm.status) { status in
            if status == .closed {
                store.stop()
            } else {
                store.start()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(red: 0.16, green: 0.75, blue: 0.38))
                .frame(width: 7, height: 7)
            Text("Antigravity 账号池")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.92))
            Spacer(minLength: 8)
            if let current = store.accounts.first(where: { $0.isCurrent }) {
                Text("当前: \(current.name)")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .lineLimit(1)
            }
        }
    }

    private var accountsRow: some View {
        HStack(spacing: 8) {
            if store.accounts.isEmpty {
                Text("未检测到本地 Antigravity 账号")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.white.opacity(0.4))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                ForEach(store.accounts) { account in
                    accountColumn(account)
                }
            }
        }
    }

    private func accountColumn(_ account: AntigravityAccount) -> some View {
        VStack(spacing: 5) {
            Text(account.name)
                .font(.system(size: 11, weight: account.isCurrent ? .semibold : .regular))
                .foregroundStyle(account.isCurrent ? Color.white.opacity(0.95) : Color.white.opacity(0.65))
                .lineLimit(1)
                .truncationMode(.tail)

            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.10), lineWidth: 3.5)
                    .frame(width: 44, height: 44)

                Circle()
                    .trim(from: 0, to: CGFloat(min(100, max(0, account.percentage))) / 100.0)
                    .stroke(
                        Self.ringColor(account.percentage, isDisabled: account.isDisabled),
                        style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 44, height: 44)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: account.percentage)

                Text("\(account.percentage)%")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(account.isDisabled ? Color.white.opacity(0.35) : Color.white.opacity(0.92))
            }
            .overlay(
                Group {
                    if account.isCurrent {
                        Circle()
                            .stroke(Color(red: 0.16, green: 0.75, blue: 0.38).opacity(0.4), lineWidth: 1.5)
                            .frame(width: 52, height: 52)
                    }
                }
            )

            Text(account.percentage == 100 ? "已就绪" : account.resetCountdownText)
                .font(.system(size: 10))
                .foregroundStyle(account.percentage == 100 ? Color(red: 0.16, green: 0.75, blue: 0.38) : Color.white.opacity(0.45))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

#if DEBUG
#Preview {
    AntigravityAccountsCardView(vm: .init())
        .padding()
        .background(Color.black)
        .onAppear {
            AntigravityStore.shared.seedForPreview(accounts: [
                .init(id: "1", name: "傅谷歌", email: "g@m.com", isCurrent: false, isDisabled: false, percentage: 100, resetTime: nil, resetCountdownText: "已就绪"),
                .init(id: "2", name: "傅哈哈", email: "h@m.com", isCurrent: true, isDisabled: false, percentage: 26, resetTime: nil, resetCountdownText: "1h14m"),
                .init(id: "3", name: "傅嘿嘿", email: "hh@m.com", isCurrent: false, isDisabled: false, percentage: 100, resetTime: nil, resetCountdownText: "已就绪"),
                .init(id: "4", name: "傅嚯嚯", email: "ho@m.com", isCurrent: false, isDisabled: false, percentage: 100, resetTime: nil, resetCountdownText: "已就绪")
            ], currentId: "2")
        }
}
#endif
```

- [ ] **步骤 2：在 project.pbxproj 中注册 AntigravityAccountsCardView.swift**

将原有 `C1D2E3F4A506172839404156`（`QuotaCardView.swift`）的文件名与路径更新为 `AntigravityAccountsCardView.swift`。

- [ ] **步骤 3：在 OverviewPageView.swift 中替换视图**

编辑 `NotchDrop/OverviewPageView.swift`：
将 `QuotaCardView(vm: vm)` 替换为 `AntigravityAccountsCardView(vm: vm)`。

- [ ] **步骤 4：构建与单元测试验证**

运行：
```bash
xcodebuild test -project NotchDrop.xcodeproj -scheme NotchDrop -destination 'platform=macOS' -derivedDataPath /tmp/nDD CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO -only-testing:NotchEveryTests
```
预期：BUILD SUCCEEDED，401+ 单测全部通过。

- [ ] **步骤 5：Commit 视图接入变更**

```bash
git add NotchDrop/AntigravityAccountsCardView.swift NotchDrop/OverviewPageView.swift NotchDrop.xcodeproj/project.pbxproj
git commit -m "feat(antigravity): 接入 AntigravityAccountsCardView 替换首页配额卡"
```

---

### 任务 3：清理废弃代码与全量回归验证

**文件：**
- 删除：`NotchDrop/QuotaSnapshot.swift`
- 删除：`NotchDrop/QuotaStore.swift`
- 删除：`NotchDrop/QuotaCardView.swift`
- 删除：`Tests/QuotaSnapshotTests.swift`
- 修改：`NotchDrop.xcodeproj/project.pbxproj`

- [ ] **步骤 1：删除废弃文件并在 project.pbxproj 中移除 QuotaSnapshot 引用**

从文件系统删除：
```bash
rm -f NotchDrop/QuotaSnapshot.swift NotchDrop/QuotaStore.swift NotchDrop/QuotaCardView.swift Tests/QuotaSnapshotTests.swift
```
在 `NotchDrop.xcodeproj/project.pbxproj` 中移除 `C1D2E3F4A506172839404152` 与 `C1D2E3F4A506172839404153`（原 `QuotaSnapshot.swift` 的 BuildFile 与 FileReference）。

- [ ] **步骤 2：全量测试与构建验证**

运行：
```bash
xcodebuild test -project NotchDrop.xcodeproj -scheme NotchDrop -destination 'platform=macOS' -derivedDataPath /tmp/nDD CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO -only-testing:NotchEveryTests
```
预期：0 个错误，所有单元测试全部通过。

- [ ] **步骤 3：构建并重启本地调试实例供真机目测**

编译并运行主程序验证：
```bash
xcodebuild -project NotchDrop.xcodeproj -scheme NotchDrop -configuration Debug -derivedDataPath /tmp/nDD build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO
killall NotchEvery NotchDrop 2>/dev/null || true
open /tmp/nDD/Build/Products/Debug/NotchDrop.app
```

- [ ] **步骤 4：Commit 清理与收尾**

```bash
git add NotchDrop.xcodeproj/project.pbxproj
git rm -f NotchDrop/QuotaSnapshot.swift NotchDrop/QuotaStore.swift NotchDrop/QuotaCardView.swift Tests/QuotaSnapshotTests.swift
git commit -m "chore(antigravity): 彻底移除废弃的 OpenCodeGo 配额模块"
```
