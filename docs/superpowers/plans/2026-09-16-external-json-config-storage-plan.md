# 全量配置外置与统一 JSON 持久化实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 subagent-driven-development（推荐）或 executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 将应用所有配置统一外置持久化至 `~/.notchevery/config.json`，并将托盘、单例锁文件全部收拢至 `~/.notchevery/`，使应用打包重装后配置不丢失、无需重复设置。

**架构：** 在 `AppPaths` 中将全局数据目录重定向到 `~/.notchevery`。重构 `ConfigStore` 存储引擎，将原有的 `UserDefaults` 底层无感替换为原子化写入的 `config.json` 引擎，并保持原有的 50+ 业务接口完全兼容；在首次加载且外部文件不存在时自动从历史 `UserDefaults` 及旧目录无缝迁移。

**技术栈：** Swift 5.9, Foundation, JSONSerialization, XCTest.

**规格：** `docs/superpowers/specs/2026-09-16-external-json-config-storage-design.md`

## 全局约束
- 配置文件落盘路径严格为 `~/.notchevery/config.json`，目录权限 0700，文件权限 0600。
- 业务调用点（`FUn.swift`、`FUnManager.swift`、`GuardControlZoneView.swift`、`PreferencesWindow.swift` 等）API 签名 100% 保持兼容。
- 迁移机制幂等且安全：仅当外部 `config.json` 不存在时做首次迁移；旧数据保留不删，防止异常数据丢失。
- 写入操作必须是线程安全且原子写入（临时文件写入 + replace 原子重命名），避免应用意外被 kill 时导致配置损坏。

---

### 任务 1：路径基础设施重定向至 `~/.notchevery` (`AppPaths.swift`)

**文件：**
- 修改：`NotchDrop/AppPaths.swift`
- 测试：`NotchEveryTests/AppPathsTests.swift`

- [ ] **步骤 1：编写针对外部路径解析的单元测试**

创建 `NotchEveryTests/AppPathsTests.swift`：
```swift
import XCTest
@testable import NotchDrop

final class AppPathsTests: XCTestCase {
    func testDocumentsDirectoryPointsToUserHomeDotNotchEvery() {
        let expectedHome = FileManager.default.homeDirectoryForCurrentUser
        let expected = expectedHome.appendingPathComponent(".notchevery")
        XCTAssertEqual(AppPaths.documentsDirectory.path, expected.path)
    }

    func testConfigDirPointsToDocumentsDirectory() {
        let expected = AppPaths.documentsDirectory.appendingPathComponent("Config")
        XCTAssertEqual(AppPaths.configDir.path, expected.path)
    }

    func testPidFilePointsToDocumentsDirectory() {
        let expected = AppPaths.documentsDirectory.appendingPathComponent("ProcessIdentifier")
        XCTAssertEqual(AppPaths.pidFile.path, expected.path)
    }
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：
```bash
xcodebuild test -project NotchDrop.xcodeproj -scheme NotchEveryTests -only-testing:NotchEveryTests/AppPathsTests
```
预期：FAIL，因为目前 `documentsDirectory` 指向 `~/Documents/NotchEvery`。

- [ ] **步骤 3：修改 `AppPaths.swift` 实现路径重定向**

修改 `NotchDrop/AppPaths.swift`：
```swift
import Foundation

enum AppPaths {
    static var documentsDirectory: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".notchevery")
    }

    static var temporaryDirectory: URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "NotchEvery")
    }

    static var pidFile: URL {
        documentsDirectory.appendingPathComponent("ProcessIdentifier")
    }

    static var configDir: URL {
        documentsDirectory.appendingPathComponent("Config")
    }

    static var configFile: URL {
        documentsDirectory.appendingPathComponent("config.json")
    }
}

let documentsDirectory: URL = AppPaths.documentsDirectory
let temporaryDirectory: URL = AppPaths.temporaryDirectory
let pidFile: URL = AppPaths.pidFile
```

- [ ] **步骤 4：运行测试验证通过**

运行：
```bash
xcodebuild test -project NotchDrop.xcodeproj -scheme NotchEveryTests -only-testing:NotchEveryTests/AppPathsTests
```
预期：PASS。

- [ ] **步骤 5：Commit 变更**

```bash
git add NotchDrop/AppPaths.swift NotchEveryTests/AppPathsTests.swift
git commit -m "feat(paths): 将全局数据根目录重定向至 ~/.notchevery"
```

---

### 任务 2：实现 `ConfigStore` 的 JSON 后端与线程安全原子落盘

**文件：**
- 修改：`NotchDrop/ConfigStore.swift`
- 修改：`NotchEveryTests/ConfigStoreTests.swift`

- [ ] **步骤 1：编写 JSON 存储引擎的核心测试**

在 `NotchEveryTests/ConfigStoreTests.swift` 中添加对 JSON 读写和独立测试文件路径的测试：
```swift
func testJSONBackendReadWriteAndPersistence() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    let testConfigFile = tempDir.appendingPathComponent("config.json")
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let store = ConfigStore(configFile: testConfigFile)
    store.set("Apple Watch Series 7", forKey: "deviceName")
    store.set(-65, forKey: "lockRSSI")
    store.set(true, forKey: "wakeOnProximity")

    XCTAssertEqual(store.string(forKey: "deviceName"), "Apple Watch Series 7")
    XCTAssertEqual(store.get("lockRSSI", fallback: 0), -65)
    XCTAssertTrue(store.bool(forKey: "wakeOnProximity"))

    // 重新构造，验证从磁盘文件重新加载
    let store2 = ConfigStore(configFile: testConfigFile)
    XCTAssertEqual(store2.string(forKey: "deviceName"), "Apple Watch Series 7")
    XCTAssertEqual(store2.get("lockRSSI", fallback: 0), -65)
    XCTAssertTrue(store2.bool(forKey: "wakeOnProximity"))
}
```

- [ ] **步骤 2：运行测试验证编译/行为失败**

运行：
```bash
xcodebuild test -project NotchDrop.xcodeproj -scheme NotchEveryTests -only-testing:NotchEveryTests/ConfigStoreTests/testJSONBackendReadWriteAndPersistence
```
预期：编译失败，因为目前 `ConfigStore` 尚未提供 `init(configFile:)`。

- [ ] **步骤 3：重构 `ConfigStore.swift` 支持 JSON 文件持久化与接口兼容**

将 `ConfigStore.swift` 的底层存储从 `UserDefaults` 升级为带锁保护的 JSON 字典后端：
- 内部维护 `private var cache: [String: Any]` 和 `private let lock = NSLock()`。
- `saveToDisk()` 采用原子写入（`Data.write(to:options: .atomic)`）。
- 提供所有原有的 `get/set/object/bool/string/removeObject` 方法。
- 保留 `suiteName` 兼容构造器：在未提供 `configFile` 时默认使用 `AppPaths.configFile`。

- [ ] **步骤 4：运行测试验证通过**

运行：
```bash
xcodebuild test -project NotchDrop.xcodeproj -scheme NotchEveryTests -only-testing:NotchEveryTests/ConfigStoreTests
```
预期：PASS。

- [ ] **步骤 5：Commit 变更**

```bash
git add NotchDrop/ConfigStore.swift NotchEveryTests/ConfigStoreTests.swift
git commit -m "feat(config): 实现 ConfigStore JSON 文件持久化引擎与并发安全机制"
```

---

### 任务 3：实现历史 UserDefaults 自动平滑迁移至 `config.json`

**文件：**
- 修改：`NotchDrop/ConfigStore.swift`
- 测试：`NotchEveryTests/ConfigStoreTests.swift`

- [ ] **步骤 1：编写历史数据自动迁移测试**

在 `NotchEveryTests/ConfigStoreTests.swift` 中编写测试：
```swift
func testMigrateFromUserDefaultsToJSONFile() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    let testConfigFile = tempDir.appendingPathComponent("config.json")
    let testSuite = "test.migration.\(UUID().uuidString)"
    defer {
        try? FileManager.default.removeItem(at: tempDir)
        UserDefaults.standard.removePersistentDomain(forName: testSuite)
    }

    let fakeLegacy = UserDefaults(suiteName: testSuite)!
    fakeLegacy.set("My Test Watch", forKey: "deviceName")
    fakeLegacy.set("-62", forKey: "lockRSSI")
    fakeLegacy.set(true, forKey: "iMessageNotify")

    let store = ConfigStore(configFile: testConfigFile, legacySuiteName: testSuite)
    XCTAssertEqual(store.string(forKey: "deviceName"), "My Test Watch")
    XCTAssertEqual(store.string(forKey: "lockRSSI"), "-62")
    XCTAssertTrue(store.bool(forKey: "iMessageNotify"))
    XCTAssertTrue(FileManager.default.fileExists(atPath: testConfigFile.path))
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：
```bash
xcodebuild test -project NotchDrop.xcodeproj -scheme NotchEveryTests -only-testing:NotchEveryTests/ConfigStoreTests/testMigrateFromUserDefaultsToJSONFile
```
预期：FAIL，迁移逻辑尚未连接到 `configFile` 初始流。

- [ ] **步骤 3：在 `ConfigStore.swift` 中完善历史 `UserDefaults` 数据迁移逻辑**

实现自动检测与迁移：
- 若 `configFile` 不存在，读取 `legacySuiteName`（现行 `com.hahappyfu.NotchEvery.guard`）中所有的键值。
- 将读取到的键值填充进 `cache`，并立即原子写入磁盘生成 `~/.notchevery/config.json`。
- 如果旧域无数据，则使用安全默认值。

- [ ] **步骤 4：运行测试验证通过**

运行：
```bash
xcodebuild test -project NotchDrop.xcodeproj -scheme NotchEveryTests -only-testing:NotchEveryTests/ConfigStoreTests
```
预期：PASS。

- [ ] **步骤 5：Commit 变更**

```bash
git add NotchDrop/ConfigStore.swift NotchEveryTests/ConfigStoreTests.swift
git commit -m "feat(config): 实现从旧 UserDefaults 自动平滑导入 config.json"
```

---

### 任务 4：全局启动流程适配与全量测试验证

**文件：**
- 修改：`NotchDrop/main.swift`
- 验证：所有单元测试

- [ ] **步骤 1：调整 `main.swift` 中目录初始化逻辑**

确保启动时预创建 `~/.notchevery` 目录，并设置权限为 `0700`：
```swift
try? FileManager.default.createDirectory(
    at: AppPaths.documentsDirectory,
    withIntermediateDirectories: true,
    attributes: [.posixPermissions: 0o700]
)
```

- [ ] **步骤 2：运行全量单元测试**

运行：
```bash
xcodebuild test -project NotchDrop.xcodeproj -scheme NotchEveryTests
```
预期：全部通过（438+ 项测试 0 失败）。

- [ ] **步骤 3：本地 Release 构建验证**

运行：
```bash
xcodebuild -project NotchDrop.xcodeproj -scheme NotchDrop -configuration Release -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
```
预期：BUILD SUCCEEDED。

- [ ] **步骤 4：Commit 变更**

```bash
git add NotchDrop/main.swift
git commit -m "feat(main): 适配 ~/.notchevery 目录初始化与权限设置"
```

---

### 任务 5：真实环境验证与上线

- [ ] **步骤 1：部署构建产物至 `/Applications/NotchEvery.app`**
- [ ] **步骤 2：启动应用，验证 `~/.notchevery/config.json` 成功生成并包含现有 Watch 绑定数据**
- [ ] **步骤 3：验证应用在打包重装后配置完好无损**
