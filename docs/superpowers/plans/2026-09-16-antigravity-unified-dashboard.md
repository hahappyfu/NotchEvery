# Antigravity 全景总览与双数据源适配器实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 subagent-driven-development（推荐）或 executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 将首页底部的冗余守护卡替换为「Antigravity 反代今日看板」；建立双数据源适配器架构，在完整保留旧版 `cc-switch` 数据源的前提下，接入 `Antigravity Tools` 本地反代真实毫秒级流量日志。

**架构：**
- 数据层：原有 `UsageStore.swift` 完整封装保留为 `CCSwitchUsageStore`。新建 `AntigravityProxyStore`，通过 SQLite C API 只读安全模式直读 `~/.antigravity_tools/proxy_logs.db` 与 `token_stats.db`。通过统一门面 `UsageStore` 提供 `activeSource` 切换开关，随时可一键切回 `cc-switch`。
- UI 展示层：新建 `AntigravityProxyCardView.swift` 替换首页底部的 `GuardCardView`，展示今日请求、总 Token、平均响应延迟与缓存命中率。第二页 `TokenZoneView.swift` 保持既有模板不变，平滑由 `UsageStore` 双数据源透明驱动。

**技术栈：** macOS 13+ / Swift 5.9 / SwiftUI 4.0 / SQLite3 C API / XCTest

**规格：** [docs/superpowers/specs/2026-09-16-antigravity-unified-dashboard-design.md](docs/superpowers/specs/2026-09-16-antigravity-unified-dashboard-design.md)

## 全局约束

- 严格保留现有 `cc-switch` 逻辑（代码可被打包引用或一键启用，绝不进行不可逆的硬删除）。
- SQLite 读取必须使用 `SQLITE_OPEN_READONLY` 与 `PRAGMA query_only = ON;`，严禁与外部服务产生写冲突。
- 所有已有 420 项单元测试保持 100% 通过。

---

### 任务 1：数据层双数据源适配器与 AntigravityProxyStore 实现 (TDD)

**文件：**
- 修改：`NotchDrop/UsageStore.swift`
- 创建：`Tests/AntigravityProxyStoreTests.swift`
- 修改：`NotchDrop.xcodeproj/project.pbxproj`

- [ ] **步骤 1：编写 AntigravityProxyStore 测试**

创建 `Tests/AntigravityProxyStoreTests.swift`：
```swift
import XCTest
@testable import NotchEvery

final class AntigravityProxyStoreTests: XCTestCase {
    func testQueryAntigravityProxyLogs() throws {
        // 创建临时数据库模拟 request_logs
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dbURL = tempDir.appendingPathComponent("proxy_logs.db")
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(dbURL.path, &db), SQLITE_OK)

        let createTable = """
        CREATE TABLE request_logs (
            id TEXT PRIMARY KEY,
            timestamp INTEGER,
            method TEXT,
            url TEXT,
            status INTEGER,
            duration INTEGER,
            model TEXT,
            error TEXT,
            request_body TEXT,
            response_body TEXT,
            input_tokens INTEGER,
            output_tokens INTEGER,
            account_email TEXT,
            mapped_model TEXT,
            protocol TEXT,
            client_ip TEXT,
            username TEXT,
            cached_tokens INTEGER
        );
        """
        XCTAssertEqual(sqlite3_exec(db, createTable, nil, nil, nil), SQLITE_OK)

        // 插入两条测试记录
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let insertSQL = """
        INSERT INTO request_logs (id, timestamp, method, url, status, duration, model, input_tokens, output_tokens, cached_tokens, account_email)
        VALUES 
        ('req-1', \(nowMs), 'POST', '/v1', 200, 1500, 'gemini-3.8-flash-high', 1000, 200, 500, 'test1@gmail.com'),
        ('req-2', \(nowMs - 5000), 'POST', '/v1', 200, 2500, 'gemini-3.8-flash-high', 2000, 400, 1000, 'test2@gmail.com');
        """
        XCTAssertEqual(sqlite3_exec(db, insertSQL, nil, nil, nil), SQLITE_OK)
        sqlite3_close(db)

        let store = AntigravityProxyStore(dbPath: dbURL, interval: 60)
        let data = store.fetchSnapshot()

        XCTAssertEqual(data.recentRequests.count, 2)
        XCTAssertEqual(data.recentRequests[0].id, "req-1")
        XCTAssertEqual(data.recentRequests[0].durationSeconds, 1.5)
        XCTAssertEqual(data.recentRequests[0].status, 200)
        XCTAssertEqual(data.recentRequests[0].accountEmail, "test1@gmail.com")
        XCTAssertEqual(data.summary.totalTokens, "3,600")
        XCTAssertEqual(data.summary.calls, "2")
    }

    func testDualSourceSwitching() {
        XCTAssertEqual(UsageStore.activeSource, .antigravityTools)
    }
}
```

- [ ] **步骤 2：在 project.pbxproj 中注册测试文件并验证失败**

运行：`xcodebuild test -project NotchDrop.xcodeproj -scheme NotchDrop -destination "platform=macOS" -only-testing:NotchEveryTests/AntigravityProxyStoreTests`
预期：FAIL，找不到 `AntigravityProxyStore`。

- [ ] **步骤 3：重构 UsageStore.swift 支持双数据源适配器**

在 `NotchDrop/UsageStore.swift` 中：
1. 定义数据源枚举与全局开关：
   ```swift
   public enum UsageDataSourceKind: String, Codable {
       case antigravityTools
       case ccSwitch
   }
   ```
2. 将既有 `UsageStore` 原有私有查询逻辑归拢为 `CCSwitchUsageStore`，保留全部原始函数与静态逻辑。
3. 新增 `AntigravityProxyStore`，直读 `proxy_logs.db`，实现 `fetchSnapshot()`，安全映射为 `TokenRequest` 与 `TokenSummary`。
4. 在 `UsageStore` 主单例中依据 `activeSource`（默认为 `.antigravityTools`）分发数据刷新：
   ```swift
   public static var activeSource: UsageDataSourceKind = .antigravityTools
   ```

- [ ] **步骤 4：运行测试验证通过**

运行：`xcodebuild test -project NotchDrop.xcodeproj -scheme NotchDrop -destination "platform=macOS" -only-testing:NotchEveryTests/AntigravityProxyStoreTests`
预期：PASS。

- [ ] **步骤 5：Commit**

```bash
git add NotchDrop/UsageStore.swift Tests/AntigravityProxyStoreTests.swift NotchDrop.xcodeproj/project.pbxproj
git commit -m "feat(usage): 实现双数据源适配器与 AntigravityProxyStore 原生日志直读"
```

---

### 任务 2：创建 AntigravityProxyCardView 首页反代看板组件

**文件：**
- 创建：`NotchDrop/AntigravityProxyCardView.swift`
- 修改：`NotchDrop.xcodeproj/project.pbxproj`

- [ ] **步骤 1：实现 AntigravityProxyCardView**

创建 `NotchDrop/AntigravityProxyCardView.swift`：
```swift
import SwiftUI

struct AntigravityProxyCardView: View {
    @StateObject var vm: NotchViewModel
    @StateObject var store = UsageStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            metricsGrid
            footer
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(width: 360)
        .onAppear { store.start() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(StudioColor.emerald)
                .frame(width: 7, height: 7)
            Text("本地反代 · \(store.providerName ?? "8045 端口")")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.92))
            Spacer()
            Text("今日看板")
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.52))
        }
    }

    private var metricsGrid: some View {
        HStack(spacing: 8) {
            metricTile(title: "今日请求", value: store.summary.calls, unit: "次")
            metricTile(title: "今日消耗", value: store.summary.totalTokens, unit: "")
            metricTile(title: "平均延迟", value: store.averageLatencyText, unit: "")
        }
    }

    private func metricTile(title: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10.5, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.55))
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.white.opacity(0.55))
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .studioCard(radius: 8)
    }

    private var footer: some View {
        HStack {
            Text("缓存命中率 \(store.summary.cacheRate)")
                .font(.system(size: 10.5))
                .foregroundStyle(StudioColor.emerald)
            Spacer()
            if let lastAt = store.footer.lastRequestAt {
                Text("最近调用 \(timeString(lastAt))")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.white.opacity(0.45))
            }
        }
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }
}
```

- [ ] **步骤 2：在 project.pbxproj 中注册 AntigravityProxyCardView.swift 并编译验证**

运行：`xcodebuild build -project NotchDrop.xcodeproj -scheme NotchDrop -destination "platform=macOS"`
预期：BUILD SUCCEEDED。

- [ ] **步骤 3：Commit**

```bash
git add NotchDrop/AntigravityProxyCardView.swift NotchDrop.xcodeproj/project.pbxproj
git commit -m "feat(ui): 创建 AntigravityProxyCardView 本地反代今日看板"
```

---

### 任务 3：首页 OverviewPageView 换源接入与耳朵联动

**文件：**
- 修改：`NotchDrop/OverviewPageView.swift`
- 修改：`NotchDrop/NotchRootView.swift`

- [ ] **步骤 1：在 OverviewPageView 中将 GuardCardView 替换为 AntigravityProxyCardView**

在 `NotchDrop/OverviewPageView.swift` 中：
```swift
struct OverviewPageView: View {
    @StateObject var vm: NotchViewModel

    var body: some View {
        VStack(spacing: 10) {
            AntigravityAccountsCardView(vm: vm)
                .padding(.horizontal, 14)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            AntigravityProxyCardView(vm: vm)
                .padding(.horizontal, 14)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
```

- [ ] **步骤 2：更新 NotchRootView 左右耳联动**

在 `NotchDrop/NotchRootView.swift` 中，确认 `leftEarPill` 在 `token` 页展示 `本地反代 :8045`，`rightEarPill` 展示今日请求次数。

- [ ] **步骤 3：运行全量单元测试**

运行：`xcodebuild test -project NotchDrop.xcodeproj -scheme NotchDrop -destination "platform=macOS"`
预期：PASS（0 失败）。

- [ ] **步骤 4：Commit**

```bash
git add NotchDrop/OverviewPageView.swift NotchDrop/NotchRootView.swift
git commit -m "feat(ui): 首页底栏换源为 AntigravityProxyCardView 并适配刘海耳"
```

---

### 任务 4：全量集成验证与本地 Release 安装

**文件：** 无文件修改（构建与部署验证）

- [ ] **步骤 1：全量回归测试套件**

运行：`xcodebuild test -project NotchDrop.xcodeproj -scheme NotchDrop -destination "platform=macOS" CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO`
预期：420+ 项测试全部 PASS，0 failures。

- [ ] **步骤 2：Release 编译与重签名安装**

```bash
xcodebuild -project NotchDrop.xcodeproj -scheme NotchDrop -configuration Release -derivedDataPath build clean build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
pkill -f NotchEvery || true
codesign --force --deep --sign - build/Build/Products/Release/NotchEvery.app
rm -rf /Applications/NotchEvery.app
cp -R build/Build/Products/Release/NotchEvery.app /Applications/
rm -rf ~/Applications/NotchEvery.app
cp -R build/Build/Products/Release/NotchEvery.app ~/Applications/
open /Applications/NotchEvery.app
```

- [ ] **步骤 3：验证应用已成功运行并汇报用户**
