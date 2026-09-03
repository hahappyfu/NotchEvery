# 额度状态卡 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 刘海展开面板新增 OpenCode Go 额度卡（5h 大环 + 周/月小字，样式 C），鼠标悬停刘海即展开，数据直读 bridge 缓存 30s 轮询。

**架构：** 新增 `QuotaSnapshot.swift`（模型 + normalize 纯函数，原样移植 EveryPlus）与 `QuotaStore.swift`（30s 轮询单例）；新增 `QuotaCardView.swift`（样式 C 基线）；`NotchContentView` 主行改为额度卡 + 文件区，AirDrop 移入菜单；hover 触发 `notchOpen(.hover)` + 0.15s 防抖收起；沙盒加 `.clawd/` 只读例外。

**技术栈：** Swift 5 / SwiftUI / Combine / os_log / App Sandbox temporary-exception

---

## 文件清单与职责

| 文件 | 职责 |
|------|------|
| 创建 `NotchDrop/QuotaSnapshot.swift` | `QuotaWindow` / `QuotaSnapshot` 模型 + `normalize(_:now:)` 纯函数（无依赖，可单测） |
| 创建 `NotchDrop/QuotaStore.swift` | `QuotaStore` 单例：30s 轮询读缓存，后台读 + 主线程发布 |
| 创建 `NotchDrop/QuotaCardView.swift` | 额度卡视图（样式 C 基线：大环 + 两行小字 + 状态点），纯展示无点击 |
| 创建 `Tests/QuotaSnapshotTests.swift` | normalize 四组单测（占位：待 Test Target 后启用，与 Task 8 前例一致） |
| 修改 `NotchDrop.xcodeproj/project.pbxproj` | 注册 3 个新 Swift 文件到 Sources + Group |
| 修改 `NotchDrop/NotchContentView.swift:17-21` | normal 态主行 `[ShareView, TrayView]` → `[QuotaCardView(180宽), TrayView]` |
| 修改 `NotchDrop/NotchMenuView.swift:14-19` | 菜单行追加第四个 `ShareView(vm:type:.airdrop)` |
| 修改 `NotchDrop/NotchViewModel.swift:68-73` | `OpenReason` 新增 `case hover` |
| 修改 `NotchDrop/NotchViewModel+Events.swift:55-62` | hover 触发改 `notchOpen(.hover)` + 防抖收起 |
| 修改 `NotchDrop/NotchDrop.entitlements` | 加 `.clawd/` home 相对路径只读例外 |

背景文档：规格 `docs/superpowers/specs/2026-09-03-notch-status-bar-design.md`；源逻辑 `EveryPlus/EveryPlus/Plugins/OpenCodeGo/Services/QuotaService.swift`；真机缓存 `~/.clawd/opencode-go-bridge-cache.json`（存在，可实测）。

验证基线（每任务必跑）：

```bash
xcodebuild -project NotchDrop.xcodeproj -scheme NotchDrop -configuration Release clean build \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3
# 预期：** BUILD SUCCEEDED **
```

---

### 任务 1：数据层——QuotaSnapshot + QuotaStore + 入编译

**文件：**
- 创建：`NotchDrop/QuotaSnapshot.swift`
- 创建：`NotchDrop/QuotaStore.swift`
- 创建：`Tests/QuotaSnapshotTests.swift`
- 修改：`NotchDrop.xcodeproj/project.pbxproj`（FileReference + BuildFile + Sources + Group，各 1 处，ID 自拟 24 位 hex，仿照 Glass.swift 的 `A1B2...` 前例）

- [ ] **步骤 1：创建 QuotaSnapshot.swift（模型 + 纯函数）**

```swift
//
//  QuotaSnapshot.swift
//  NotchEvery
//
//  额度快照模型与归一化（移植自 EveryPlus OpenCodeGo，行为一致）。
//

import Foundation

struct QuotaWindow: Equatable {
    let key: String        // "5h" | "weekly" | "monthly"
    let used: Double
    let limit: Double
    let percent: Double    // 自算 used/limit*100，封顶 100
    let resetAt: Date?
}

struct QuotaSnapshot: Equatable {
    let fetchedAt: Date?
    let expired: Bool      // fetchedAt 缺失或距今 > 10min
    let available: Bool
    let windows: [QuotaWindow]

    static let empty = QuotaSnapshot(fetchedAt: nil, expired: true, available: false, windows: [])

    func window(_ key: String) -> QuotaWindow? {
        windows.first { $0.key == key }
    }
}

extension QuotaSnapshot {
    /// bridge 缓存原始字节归一化为快照；任何异常输入都返回可用结果，绝不抛出。
    /// 注意：缓存内 percent 恒 0（上游 bug），必须自算，不能采信。
    static func normalize(_ data: Data?, now: Date = Date()) -> QuotaSnapshot {
        guard let data, !data.isEmpty,
              let file = try? JSONDecoder().decode(CacheFile.self, from: data),
              let rawQuota = file.quota, !rawQuota.isEmpty
        else { return .empty }

        let fetchedAt = file.at.map { Date(timeIntervalSince1970: $0 / 1000) }
        let expired = fetchedAt.map { now.timeIntervalSince($0) > 600 } ?? true

        let windows = ["5h", "weekly", "monthly"].compactMap { key -> QuotaWindow? in
            guard let w = rawQuota[key],
                  let used = w.used, used.isFinite,
                  let limit = w.limit, limit.isFinite
            else { return nil }
            let percent = limit <= 0 ? 0 : min(100, max(0, used / limit * 100))
            let resetAt = w.resetInSec.map { now.addingTimeInterval($0) }
            return QuotaWindow(key: key, used: used, limit: limit, percent: percent, resetAt: resetAt)
        }
        return QuotaSnapshot(fetchedAt: fetchedAt, expired: expired, available: true, windows: windows)
    }

    private struct CacheFile: Decodable {
        let at: Double?
        let quota: [String: RawWindow]?
    }
    private struct RawWindow: Decodable {
        let used: Double?
        let limit: Double?
        let resetInSec: Double?
    }
}
```

- [ ] **步骤 2：创建 QuotaStore.swift（轮询单例）**

```swift
//
//  QuotaStore.swift
//  NotchEvery
//
//  额度轮询：读本机 bridge 缓存 → 归一化 → 主线程发布。纯观察者，不碰网络。
//

import Combine
import Foundation
import os.log

private let quotaLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "NotchEvery", category: "QuotaStore")

final class QuotaStore: ObservableObject {
    static let shared = QuotaStore()

    @Published private(set) var snapshot: QuotaSnapshot = .empty

    static let cacheURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".clawd/opencode-go-bridge-cache.json")

    private let interval: TimeInterval
    private var timer: Timer?

    init(interval: TimeInterval = 30) {
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
        quotaLog.info("QuotaStore started, interval \(self.interval)s")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let data = try? Data(contentsOf: Self.cacheURL)
            let next = data.map { QuotaSnapshot.normalize($0, now: Date()) }
            DispatchQueue.main.async { [weak self] in
                guard let self, let next else { return }
                self.snapshot = next
                quotaLog.info("quota refresh: available=\(next.available) expired=\(next.expired) windows=\(next.windows.count)")
            }
        }
    }
}
```

- [ ] **步骤 3：创建 Tests/QuotaSnapshotTests.swift（占位单测）**

```swift
import XCTest
@testable import NotchEvery

// normalize 单测（待 Xcode Test Target 后启用；用例抄 EveryPlus QuotaColdTests）
final class QuotaSnapshotTests: XCTestCase {
    func testEmptyInputReturnsEmpty() {
        XCTAssertEqual(QuotaSnapshot.normalize(nil), .empty)
        XCTAssertEqual(QuotaSnapshot.normalize(Data()), .empty)
    }

    func testIgnoresCachedPercentBug() throws {
        // 缓存 percent 恒 0，used=62 limit=100 → 自算 62
        let json = #"{"at": 1788423000000, "quota": {"5h": {"used": 62, "limit": 100, "percent": 0}}}"#
        let snap = QuotaSnapshot.normalize(json.data(using: .utf8)!, now: Date(timeIntervalSince1970: 1788423000))
        XCTAssertEqual(snap.window("5h")?.percent, 62, accuracy: 0.01)
    }

    func testDropsInvalidWindows() {
        let json = #"{"quota": {"5h": {"used": 1}, "weekly": {"used": 30, "limit": 100}}}"#
        let snap = QuotaSnapshot.normalize(json.data(using: .utf8)!)
        XCTAssertNil(snap.window("5h"))
        XCTAssertNotNil(snap.window("weekly"))
    }

    func testExpiredWhenStale() {
        let json = #"{"at": 1000000000000, "quota": {"5h": {"used": 1, "limit": 2}}}"#
        let snap = QuotaSnapshot.normalize(json.data(using: .utf8)!)
        XCTAssertTrue(snap.expired)
        XCTAssertTrue(snap.available)
    }
}
```

注意：`@testable import NotchEvery` 要求 target 名为 NotchEvery——当前 Xcode target 名仍是 `NotchDrop`（私有化时有意保留）。此文件**不入 pbxproj**，仅占位；待 target 重命名或建 Test Target 时把 `NotchEvery` 改为实际模块名后启用。

- [ ] **步骤 4：pbxproj 注册两个 Swift 文件**

```bash
python3 - <<'PY'
pbx = "NotchDrop.xcodeproj/project.pbxproj"
t = open(pbx).read()
pairs = [("C1D2E3F4A506172839404152", "C1D2E3F4A506172839404153", "QuotaSnapshot.swift"),
         ("C1D2E3F4A506172839404154", "C1D2E3F4A506172839404155", "QuotaStore.swift")]
for ref, build, name in pairs:
    assert ref not in t, f"{name} 已注册，跳过"
    t = t.replace("/* End PBXFileReference section */",
        f'\t\t{ref} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {name}; sourceTree = "<group>"; }};\n/* End PBXFileReference section */')
    t = t.replace("/* End PBXBuildFile section */",
        f'\t\t{build} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {ref} /* {name} */; }};\n/* End PBXBuildFile section */')
    t = t.replace("5043819F2C3A8BA1000ED325 /* NotchView.swift */,",
        f"5043819F2C3A8BA1000ED325 /* NotchView.swift */,\n\t\t\t\t{ref} /* {name} */,")
    t = t.replace("5044EEA02C3B116000071C5C /* PublishedPersist.swift in Sources */,",
        f"5044EEA02C3B116000071C5C /* PublishedPersist.swift in Sources */,\n\t\t\t\t{build} /* {name} in Sources */,")
open(pbx, "w").write(t)
print("registered QuotaSnapshot.swift + QuotaStore.swift")
PY
grep -c "QuotaSnapshot.swift\|QuotaStore.swift" NotchDrop.xcodeproj/project.pbxproj
# 预期：6（每文件引用+构建+Sources 共 3 处 × 2 文件）
```

- [ ] **步骤 5：构建验证**

运行：`xcodebuild -project NotchDrop.xcodeproj -scheme NotchDrop -configuration Release clean build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3`
预期：BUILD SUCCEEDED（QuotaStore 尚未被任何视图引用，无行为变化）

- [ ] **步骤 6：Commit**

```bash
git add NotchDrop/QuotaSnapshot.swift NotchDrop/QuotaStore.swift Tests/QuotaSnapshotTests.swift NotchDrop.xcodeproj/project.pbxproj
git commit -m "feat: 额度数据层 QuotaSnapshot+QuotaStore（直读 bridge 缓存）"
```

---

### 任务 2：额度卡视图 + 面板重组 + AirDrop 进菜单

**文件：**
- 创建：`NotchDrop/QuotaCardView.swift`
- 修改：`NotchDrop/NotchContentView.swift:17-21`
- 修改：`NotchDrop/NotchMenuView.swift:14-19`
- 修改：`NotchDrop.xcodeproj/project.pbxproj`（注册 QuotaCardView.swift，同任务 1 手法，ID `C1D2E3F4A506172839404156/57`）

- [ ] **步骤 1：创建 QuotaCardView.swift（样式 C 基线）**

```swift
//
//  QuotaCardView.swift
//  NotchEvery
//
//  额度卡（样式 C：5h 大环 + 周/月小字）。纯展示，点击穿透。
//  像素级打磨（环粗细/阈值配色/字体）由后续前端 skill 迭代，本文件只定骨架。
//

import SwiftUI

struct QuotaCardView: View {
    @StateObject var vm: NotchViewModel
    @StateObject var store = QuotaStore.shared

    /// 用量阈值配色：<70 绿，70–90 橙，≥90 红
    static func ringColor(_ percent: Double) -> Color {
        if percent >= 90 { return .red }
        if percent >= 70 { return .orange }
        return .green
    }

    var body: some View {
        HStack(spacing: 12) {
            ring(size: 76, percent: store.snapshot.window("5h")?.percent, label: "5h")
            VStack(alignment: .leading, spacing: 8) {
                row(key: "weekly", title: "周")
                row(key: "monthly", title: "月")
                statusLine
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .glassCard(cornerRadius: vm.cornerRadius)
        .onAppear { store.start() }
    }

    private func row(key: String, title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            if let w = store.snapshot.window(key) {
                Text("\(Int(w.percent))%")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
            } else {
                Text("--%")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var statusLine: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(store.snapshot.expired ? .orange : .green)
                .frame(width: 6, height: 6)
            if let at = store.snapshot.fetchedAt {
                Text(at, style: .relative)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else {
                Text(store.snapshot.available ? "已过期" : "暂无数据")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func ring(size: CGFloat, percent: Double?, label: String) -> some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.18), lineWidth: 7)
                .frame(width: size, height: size)
            if let percent {
                Circle()
                    .trim(from: 0, to: min(1, max(0, percent / 100)))
                    .stroke(Self.ringColor(percent), lineWidth: 7, lineCap: .round)
                    .rotationEffect(.degrees(-90))
                    .frame(width: size, height: size)
                Text("\(Int(percent))%")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
            } else {
                Text("--%")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
        }
        .overlay(alignment: .bottom) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .offset(y: 12)
        }
    }
}
```

- [ ] **步骤 2：NotchContentView 主行重组**

```swift
// NotchDrop/NotchContentView.swift:17-21，原：
                HStack(spacing: vm.spacing) {
                    ShareView(vm: vm, type: .airdrop)
                    TrayView(vm: vm)
                }
// 改为：
                HStack(spacing: vm.spacing) {
                    QuotaCardView(vm: vm)
                        .frame(width: 180)
                    TrayView(vm: vm)
                }
```

- [ ] **步骤 3：AirDrop 进菜单（NotchMenuView:14-19）**

```swift
// 原：
        HStack(spacing: vm.spacing) {
            close
            settings
            clear
        }
// 改为：
        HStack(spacing: vm.spacing) {
            close
            settings
            clear
            ShareView(vm: vm, type: .airdrop)
        }
```

`ShareView` 本体零改动（自身 aspectRatio(1) 正方形，与 `GlassButton` 同尺寸语义；onDrop + 点按选文件逻辑照搬）。

- [ ] **步骤 4：构建 + 真机冒烟**

运行：基线构建命令，预期 BUILD SUCCEEDED。

```bash
killall NotchEvery 2>/dev/null; killall NotchDrop 2>/dev/null; sleep 1
open ~/Library/Developer/Xcode/DerivedData/NotchDrop-*/Build/Products/Release/NotchDrop.app; sleep 2
screencapture -x -R 500,0,900,260 /tmp/quota_card_check.png
# 预期：展开面板左侧额度卡显示 5h 真实百分比（与 ~/.clawd 缓存一致），右侧文件区正常；
# 菜单（...→循环到 menu 态）第四格为 AirDrop
log show --predicate 'subsystem == "com.hahappyfu.NotchEvery" AND category == "QuotaStore"' --last 2m 2>&1 | tail -5
# 预期：quota refresh: available=true expired=false windows=3
```

- [ ] **步骤 5：Commit**

```bash
git add NotchDrop/QuotaCardView.swift NotchDrop/NotchContentView.swift NotchDrop/NotchMenuView.swift NotchDrop.xcodeproj/project.pbxproj
git commit -m "feat: 额度卡视图 + 面板重组，AirDrop 进菜单"
```

---

### 任务 3：Hover 全开 + 防抖收起 + 沙盒例外

**文件：**
- 修改：`NotchDrop/NotchViewModel.swift:68-73`（OpenReason 加 hover）
- 修改：`NotchDrop/NotchViewModel+Events.swift:55-62`（触发 + 防抖）
- 修改：`NotchDrop/NotchDrop.entitlements`（加例外）

- [ ] **步骤 1：OpenReason 新增 hover**

```swift
// NotchDrop/NotchViewModel.swift:68-73，原：
    enum OpenReason: String, Codable, Hashable, Equatable {
        case click
        case drag
        case boot
        case unknown
    }
// 改为：
    enum OpenReason: String, Codable, Hashable, Equatable {
        case click
        case drag
        case boot
        case hover
        case unknown
    }
```

- [ ] **步骤 2：hover 触发 + 防抖收起**

```swift
// NotchDrop/NotchViewModel.swift，NotchViewModel 类内新增（放在 hapticSender 声明旁）：
    /// hover 展开后的延迟收起任务（防刘海→面板路径单帧误判闪烁）
    private var hoverCloseWorkItem: DispatchWorkItem?

    func scheduleHoverClose() {
        hoverCloseWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, status == .opened, openReason == .hover else { return }
            notchClose()
        }
        hoverCloseWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    func cancelHoverClose() {
        hoverCloseWorkItem?.cancel()
        hoverCloseWorkItem = nil
    }
```

```swift
// NotchDrop/NotchViewModel+Events.swift:55-62，原：
        events.mouseLocation
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mouseLocation in
                guard let self else { return }
                let aboutToOpen = deviceNotchRect.insetBy(dx: inset, dy: inset).contains(mouseLocation)
                if status == .closed, aboutToOpen { notchPop() }
                if status == .popping, !aboutToOpen { notchClose() }
            }
            .store(in: &cancellables)
// 改为：
        events.mouseLocation
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mouseLocation in
                guard let self else { return }
                let aboutToOpen = deviceNotchRect.insetBy(dx: inset, dy: inset).contains(mouseLocation)
                if status == .closed, aboutToOpen { notchOpen(.hover) }
                if status == .popping, !aboutToOpen { notchClose() }
                // hover 展开态：离开面板区延迟收起，移回取消
                if status == .opened, openReason == .hover {
                    if notchOpenedRect.contains(mouseLocation) {
                        cancelHoverClose()
                    } else {
                        scheduleHoverClose()
                    }
                }
            }
            .store(in: &cancellables)
```

语义守恒说明：click/drag/boot 展开不受影响（`openReason == .hover` 限定）；`popping` 仍专供拖文件预备态；点击空白收起（mouseDown 管道）不动。

- [ ] **步骤 3：沙盒例外**

```xml
<!-- NotchDrop/NotchDrop.entitlements 的 <dict> 内追加 -->
	<key>com.apple.security.temporary-exception.files.home-relative-path.read-only</key>
	<array>
		<string>.clawd/</string>
	</array>
```

```bash
plutil -p NotchDrop/NotchDrop.entitlements | grep -A2 "temporary-exception"
# 预期：[".clawd/"]
```

- [ ] **步骤 4：构建 + 行为验证**

运行：基线构建命令，预期 BUILD SUCCEEDED。

```bash
open ~/Library/Developer/Xcode/DerivedData/NotchDrop-*/Build/Products/Release/NotchDrop.app; sleep 2
# 手工：鼠标从屏幕下方快速划过刘海 → 面板展开显示额度卡；鼠标移开 → 约0.15s后收起无闪烁；
# 点击刘海 → 展开后鼠标移开不自动收起（click 语义守恒）；拖文件悬停 → popping/全开链路如前
screencapture -x -R 500,0,900,260 /tmp/quota_hover_check.png
# 预期：hover 展开态截图含额度卡 + 文件区
```

- [ ] **步骤 5：Commit**

```bash
git add NotchDrop/NotchViewModel.swift NotchDrop/NotchViewModel+Events.swift NotchDrop/NotchDrop.entitlements
git commit -m "feat: hover 悬停全开 + 防抖收起 + bridge 缓存沙盒例外"
```

---

## 全量回归（任务 3 之后）

- [ ] 基线构建 BUILD SUCCEEDED 且零新增 warning（`CLANG_WARN_UNGUARDED_AVAILABILITY=YES_AGGRESSIVE` 下）
- [ ] 冒烟：hover 展开/收起、额度三窗口数字与缓存一致、过期标（改缓存 at 为旧时间戳验证）、菜单 AirDrop 可选文件发送、文件拖入暂存、Option 删除、明暗外观
- [ ] `codegraph index` 刷新（预期 31 文件）

---

## 自检

- [x] **规格覆盖度：** §1 布局→任务 2（卡宽 180、AirDrop 进菜单、normal 态限定）；§2 数据流→任务 1（normalize 原样移植、Detail 不搬、30s/common 模式、旧数据+过期标语义）；§3 hover→任务 3（`.hover`、防抖 0.15s、popping 保留）；§4 错误处理→任务 1/3（静默保留+os_log、无数据 `--%`、轮询自愈）；§5 范围外→均未进入任务（视觉细化留后续、前 C 方向不搭、方案 C 否决、target 不改名）。样式 C 锁定→任务 2 步骤 1。
- [x] **占位符扫描：** 无 TODO/待定；"后续前端 skill"只出现在任务 2 步骤 1 的注释一行且骨架代码完整，不构成缺失；`@testable import NotchEvery` 的模块名问题已在任务 1 步骤 3 用注意段写明改法。
- [x] **类型一致性：** `QuotaWindow`/`QuotaSnapshot`/`QuotaStore.shared`/`QuotaCardView(vm:)`/`store.snapshot.window(_:)`/`ringColor(_:)` 在任务 1→2 引用一致；`notchOpen(.hover)` 依赖任务 3 步骤 1 的 enum 新增，顺序正确（任务 3 内聚）；`glassCard(cornerRadius:)` 沿用既有 `Glass.swift` API；entitlement key 与 §2.4 一字不差。
