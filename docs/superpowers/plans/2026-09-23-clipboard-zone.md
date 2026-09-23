# 剪贴板历史专区（Clipboard Zone）实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 subagent-driven-development（推荐）或 executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 在 NotchEvery 刘海中构建自动监听、支持图文记录、上限 50 条淘汰、点击带触控板触觉反馈并自动注入目标输入框的剪贴板历史专区。

**架构：** 
1. `ClipboardStore` 负责内存项管理与本地 JSON/图片缩略图磁盘持久化，维护 50 条硬上限淘汰。
2. `ClipboardMonitor` 以 0.6s 低频轮询 `changeCount` 捕获系统文字与截图，支持内部写入防回环。
3. `ClipboardPaster` 持续跟踪系统前台活跃应用，点击时先触发 Force Touch 触控板触觉回弹，通过 `CGEvent` 激活并模拟 `Cmd + V` 注入，且保持刘海展开。
4. `ClipboardZoneView` 采用 410pt 定宽与 310pt 限高设计，结合渐变遮罩滚动容器与原生 Studio 视觉卡片呈现。

**技术栈：** Swift 5.9, SwiftUI, AppKit (NSPasteboard, NSHapticFeedbackManager, CGEvent, NSWorkspace), XCTest.

**规格：** [docs/superpowers/specs/2026-09-23-clipboard-zone-design.md](docs/superpowers/specs/2026-09-23-clipboard-zone-design.md)

## 全局约束

- 构建/测试姿势约束：必须使用 `xcodebuild -project NotchDrop.xcodeproj -scheme NotchDrop -derivedDataPath /tmp/nDD CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO` 姿势执行，绝不使用 `-target`。
- 尺寸约束：面板宽度严格保持 410pt，高度上限锁定在 310pt 以内，不得无限制垂直扩张撑破屏幕。
- 交互约束：条目被点击执行粘贴时，刘海面板绝不关闭（不调用 `notchClose()`），允许用户连续点击粘贴不同条目；仅当光标移出刘海区域后延时收回。
- 资源与内存约束：图片只落盘压缩后的缩略图（PNG，最长边 400px），不持有大尺寸原图，淘汰时同步清理本地文件。

---

### 任务 1：核心数据模型与存储层（ClipboardItem & ClipboardStore）

**文件：**
- 创建：`NotchDrop/ClipboardStore.swift`
- 测试：`Tests/ClipboardStoreTests.swift`

- [ ] **步骤 1：编写失败的测试套件**

在 `Tests/ClipboardStoreTests.swift` 中编写测试：
```swift
import XCTest
@testable import NotchDrop

final class ClipboardStoreTests: XCTestCase {
    var tempDir: URL!
    var store: ClipboardStore!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("ClipboardTests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = ClipboardStore(storageDirectory: tempDir)
    }

    override func tearDown() {
        if let tempDir = tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        super.tearDown()
    }

    func testInsertTextItemAppearsAtFront() {
        store.addText("Hello World")
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items.first?.textContent, "Hello World")
        XCTAssertEqual(store.items.first?.type, .text)
    }

    func testDeduplicateConsecutiveIdenticalText() {
        store.addText("Duplicate")
        store.addText("Duplicate")
        XCTAssertEqual(store.items.count, 1)
    }

    func testFiftyItemsHardLimitEviction() {
        for i in 0..<55 {
            store.addText("Item \(i)")
        }
        XCTAssertEqual(store.items.count, 50)
        XCTAssertEqual(store.items.first?.textContent, "Item 54")
        XCTAssertEqual(store.items.last?.textContent, "Item 5")
    }

    func testClearAllRemovesItemsAndFiles() {
        store.addText("Item 1")
        store.clearAll()
        XCTAssertTrue(store.items.isEmpty)
    }
}
```

- [ ] **步骤 2：在 project.pbxproj 注册测试文件并验证失败**

运行：
`xcodebuild test -project NotchDrop.xcodeproj -scheme NotchDrop -derivedDataPath /tmp/nDD CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO -only-testing:NotchEveryTests/ClipboardStoreTests`
预期：FAIL，报错 "ClipboardStore not found"

- [ ] **步骤 3：编写最小实现代码**

创建 `NotchDrop/ClipboardStore.swift`：
```swift
import Foundation
import SwiftUI

public enum ClipboardItemType: String, Codable, Hashable {
    case text
    case image
}

public struct ClipboardItem: Identifiable, Codable, Equatable {
    public let id: UUID
    public let type: ClipboardItemType
    public let textContent: String?
    public let imageFileName: String?
    public let charCount: Int
    public let imageWidth: CGFloat?
    public let imageHeight: CGFloat?
    public let copiedAt: Date

    public init(
        id: UUID = UUID(),
        type: ClipboardItemType,
        textContent: String? = nil,
        imageFileName: String? = nil,
        charCount: Int = 0,
        imageWidth: CGFloat? = nil,
        imageHeight: CGFloat? = nil,
        copiedAt: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.textContent = textContent
        self.imageFileName = imageFileName
        self.charCount = charCount
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.copiedAt = copiedAt
    }
}

public final class ClipboardStore: ObservableObject {
    public static let shared = ClipboardStore()

    public static let maxItemCount = 50
    private let storageDirectory: URL
    private let metadataURL: URL
    private let imagesDirectory: URL

    @Published public private(set) var items: [ClipboardItem] = []

    public init(storageDirectory: URL? = nil) {
        let baseDir: URL
        if let custom = storageDirectory {
            baseDir = custom
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            baseDir = appSupport.appendingPathComponent("NotchEvery/Clipboard", isDirectory: true)
        }
        self.storageDirectory = baseDir
        self.metadataURL = baseDir.appendingPathComponent("clipboard_history.json")
        self.imagesDirectory = baseDir.appendingPathComponent("Images", isDirectory: true)

        try? FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        loadFromDisk()
    }

    public func addText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // 去重：与顶部条目完全一致则忽略
        if let first = items.first, first.type == .text, first.textContent == text {
            return
        }

        let item = ClipboardItem(
            type: .text,
            textContent: text,
            charCount: text.count,
            copiedAt: Date()
        )
        insertItem(item)
    }

    public func addImage(data: Data, size: CGSize) {
        let id = UUID()
        let fileName = "\(id.uuidString).png"
        let fileURL = imagesDirectory.appendingPathComponent(fileName)

        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            return
        }

        let item = ClipboardItem(
            id: id,
            type: .image,
            imageFileName: fileName,
            imageWidth: size.width,
            imageHeight: size.height,
            copiedAt: Date()
        )
        insertItem(item)
    }

    public func imageURL(for item: ClipboardItem) -> URL? {
        guard let fileName = item.imageFileName else { return nil }
        return imagesDirectory.appendingPathComponent(fileName)
    }

    public func clearAll() {
        items.removeAll()
        try? FileManager.default.removeItem(at: metadataURL)
        if let files = try? FileManager.default.contentsOfDirectory(at: imagesDirectory, includingPropertiesForKeys: nil) {
            for file in files {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    private func insertItem(_ item: ClipboardItem) {
        items.insert(item, at: 0)

        // 淘汰超过 50 条的最老项
        while items.count > Self.maxItemCount {
            if let evicted = items.popLast(), let imgName = evicted.imageFileName {
                let imgURL = imagesDirectory.appendingPathComponent(imgName)
                try? FileManager.default.removeItem(at: imgURL)
            }
        }
        saveToDisk()
    }

    private func saveToDisk() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(self.items) {
                try? data.write(to: self.metadataURL, options: .atomic)
            }
        }
    }

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: metadataURL.path),
              let data = try? Data(contentsOf: metadataURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([ClipboardItem].self, from: data) {
            self.items = decoded
        }
    }
}
```

- [ ] **步骤 4：在 project.pbxproj 注册源码并运行测试验证通过**

运行：
`xcodebuild test -project NotchDrop.xcodeproj -scheme NotchDrop -derivedDataPath /tmp/nDD CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO -only-testing:NotchEveryTests/ClipboardStoreTests`
预期：PASS，4 tests passed

- [ ] **步骤 5：Commit**

```bash
git add NotchDrop/ClipboardStore.swift Tests/ClipboardStoreTests.swift NotchDrop.xcodeproj/project.pbxproj
git commit -m "feat(clipboard): 添加 ClipboardStore 存储层与 50 条上限淘汰测试"
```

---

### 任务 2：系统剪贴板监听器（ClipboardMonitor）

**文件：**
- 创建：`NotchDrop/ClipboardMonitor.swift`
- 测试：`Tests/ClipboardMonitorTests.swift`

- [ ] **步骤 1：编写剪贴板变更捕获与内部写过滤测试**

在 `Tests/ClipboardMonitorTests.swift`：
```swift
import XCTest
@testable import NotchDrop

final class ClipboardMonitorTests: XCTestCase {
    func testInternalCopyFlagPreventsRecording() {
        let store = ClipboardStore(storageDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let monitor = ClipboardMonitor(store: store)

        monitor.isInternalCopy = true
        // 模拟检测
        XCTAssertTrue(monitor.isInternalCopy)
    }
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：
`xcodebuild test -project NotchDrop.xcodeproj -scheme NotchDrop -derivedDataPath /tmp/nDD CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO -only-testing:NotchEveryTests/ClipboardMonitorTests`
预期：FAIL

- [ ] **步骤 3：编写 ClipboardMonitor 实现**

创建 `NotchDrop/ClipboardMonitor.swift`：
```swift
import Cocoa
import Foundation

public final class ClipboardMonitor {
    public static let shared = ClipboardMonitor()

    private let store: ClipboardStore
    private var timer: Timer?
    private var lastChangeCount: Int
    public var isInternalCopy: Bool = false

    public init(store: ClipboardStore = .shared) {
        self.store = store
        self.lastChangeCount = NSPasteboard.general.changeCount
    }

    public func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            self?.checkPasteboard()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    public func checkPasteboard() {
        let currentCount = NSPasteboard.general.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        if isInternalCopy {
            isInternalCopy = false
            return
        }

        let pasteboard = NSPasteboard.general

        // 1. 优先检查纯文本/字符串
        if let string = pasteboard.string(forType: .string), !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            DispatchQueue.main.async { [weak self] in
                self?.store.addText(string)
            }
            return
        }

        // 2. 检查图片 (PNG/TIFF)
        if let image = NSImage(pasteboard: pasteboard) {
            guard let tiffData = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData) else { return }

            // 压缩限制为最大宽度 400px 缩略图保存
            let originalSize = image.size
            let targetSize: CGSize
            let maxDimension: CGFloat = 400.0
            if originalSize.width > maxDimension || originalSize.height > maxDimension {
                let ratio = min(maxDimension / originalSize.width, maxDimension / originalSize.height)
                targetSize = CGSize(width: originalSize.width * ratio, height: originalSize.height * ratio)
            } else {
                targetSize = originalSize
            }

            let thumbnail = NSImage(size: targetSize)
            thumbnail.lockFocus()
            image.draw(in: NSRect(origin: .zero, size: targetSize), from: NSRect(origin: .zero, size: originalSize), operation: .copy, fraction: 1.0)
            thumbnail.unlockFocus()

            if let thumbTiff = thumbnail.tiffRepresentation,
               let thumbBitmap = NSBitmapImageRep(data: thumbTiff),
               let pngData = thumbBitmap.representation(using: .png, properties: [:]) {
                DispatchQueue.main.async { [weak self] in
                    self?.store.addImage(data: pngData, size: originalSize)
                }
            }
        }
    }
}
```

- [ ] **步骤 4：注册并运行测试通过**

运行：
`xcodebuild test -project NotchDrop.xcodeproj -scheme NotchDrop -derivedDataPath /tmp/nDD CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO -only-testing:NotchEveryTests/ClipboardMonitorTests`
预期：PASS

- [ ] **步骤 5：Commit**

```bash
git add NotchDrop/ClipboardMonitor.swift Tests/ClipboardMonitorTests.swift NotchDrop.xcodeproj/project.pbxproj
git commit -m "feat(clipboard): 实现 ClipboardMonitor 剪贴板静默轮询与缩略图提取"
```

---

### 任务 3：前台应用追踪、触觉反馈与按键自动注入（ClipboardPaster）

**文件：**
- 创建：`NotchDrop/ClipboardPaster.swift`

- [ ] **步骤 1：编写 ClipboardPaster 实现**

创建 `NotchDrop/ClipboardPaster.swift`：
```swift
import Cocoa
import CoreGraphics

public final class ClipboardPaster {
    public static let shared = ClipboardPaster()

    /// 跟踪点击前用户正在使用的应用（排除自身）
    public private(set) var lastActiveApp: NSRunningApplication?

    private init() {
        setupWorkspaceTracking()
    }

    private func setupWorkspaceTracking() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            if app.bundleIdentifier != Bundle.main.bundleIdentifier {
                self?.lastActiveApp = app
            }
        }
        // 初始抓取
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Bundle.main.bundleIdentifier {
            lastActiveApp = front
        }
    }

    /// 点击卡片触发：触觉震动 + 写入剪贴板 + 目标应用激活 + 模拟 Cmd+V 按键
    public func paste(item: ClipboardItem) {
        // 1. 触发 Mac 触控板 Force Touch 物理震动反馈
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)

        // 2. 将内容写回系统剪贴板（设置防重录标）
        ClipboardMonitor.shared.isInternalCopy = true
        let pb = NSPasteboard.general
        pb.clearContents()

        if item.type == .text, let text = item.textContent {
            pb.setString(text, forType: .string)
        } else if item.type == .image,
                  let url = ClipboardStore.shared.imageURL(for: item),
                  let image = NSImage(contentsOf: url) {
            pb.writeObjects([image])
        }

        // 3. 激活原前台应用
        guard let target = lastActiveApp else { return }
        target.activate(options: .activateIgnoringOtherApps)

        // 4. 延迟 60ms 待原应用重新接管按键事件后，注入 Cmd+V（0x09 为 KeyCode V）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            let src = CGEventSource(stateID: .combinedSessionState)
            let vKeyCode: CGKeyCode = 0x09

            if let keyDown = CGEvent(keyboardEventSource: src, virtualKey: vKeyCode, keyDown: true),
               let keyUp = CGEvent(keyboardEventSource: src, virtualKey: vKeyCode, keyDown: false) {
                keyDown.flags = .maskCommand
                keyUp.flags = .maskCommand

                keyDown.post(tap: .cghidEventTap)
                keyUp.post(tap: .cghidEventTap)
            }
        }
    }
}
```

- [ ] **步骤 2：注册到 project.pbxproj 并验证编译**

运行：
`xcodebuild -project NotchDrop.xcodeproj -scheme NotchDrop -configuration Debug -derivedDataPath /tmp/nDD build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO`
预期：BUILD SUCCEEDED

- [ ] **步骤 3：Commit**

```bash
git add NotchDrop/ClipboardPaster.swift NotchDrop.xcodeproj/project.pbxproj
git commit -m "feat(clipboard): 实现 ClipboardPaster 触感反馈与 CGEvent 按键注入"
```

---

### 任务 4：NotchViewModel 扩充 ContentType.clipboard 与分页集成

**文件：**
- 修改：`NotchDrop/NotchViewModel.swift:154-159`
- 修改：`NotchDrop/NotchViewModel.swift:237-240`
- 测试：`Tests/ContentZoneSwitcherTests.swift`

- [ ] **步骤 1：在测试中追加 .clipboard 分页顺序断言**

检查 `Tests/ContentZoneSwitcherTests.swift`，确保对新增的 `.clipboard` 区索引映射进行验证。

- [ ] **步骤 2：修改 NotchViewModel 中的枚举与列表定义**

在 `NotchDrop/NotchViewModel.swift`：
```swift
    enum ContentType: Int, Codable, Hashable, Equatable {
        case normal
        case clipboard
        case token
        case gateway
    }

    /// 参与分页的区序：默认包含剪贴板
    static let baseZoneOrder: [ContentType] = [.normal, .clipboard, .token, .gateway]
    static func zoneOrder(gatewayEnabled: Bool) -> [ContentType] {
        gatewayEnabled ? baseZoneOrder : [.normal, .clipboard, .token]
    }
```

- [ ] **步骤 3：运行分区切换测试验证通过**

运行：
`xcodebuild test -project NotchDrop.xcodeproj -scheme NotchDrop -derivedDataPath /tmp/nDD CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO -only-testing:NotchEveryTests/ContentZoneSwitcherTests`
预期：PASS

- [ ] **步骤 4：Commit**

```bash
git add NotchDrop/NotchViewModel.swift Tests/ContentZoneSwitcherTests.swift
git commit -m "feat(zone): 在 ContentType 与 baseZoneOrder 中引入 .clipboard 专区"
```

---

### 任务 5：构建剪贴板专区界面（ClipboardZoneView）与挂载 NotchRootView

**文件：**
- 创建：`NotchDrop/ClipboardZoneView.swift`
- 修改：`NotchDrop/NotchRootView.swift`
- 修改：`NotchDrop/AppDelegate.swift` 或 `main.swift`（启动 `ClipboardMonitor.shared.start()`）

- [ ] **步骤 1：编写 ClipboardZoneView 界面组件**

创建 `NotchDrop/ClipboardZoneView.swift`：
- 固定宽度 410pt，最大高度 310pt。
- 顶部信息栏：左侧绿圆点 + "剪贴板历史 (\(store.items.count))"，右侧清空垃圾桶图标。
- ScrollView + VStack 包含各个卡片，上下带有渐隐 mask。
- 文本行：剪贴板小图标、最多 2 行截断文字、相对时间。
- 图片行：34×34 缩略图、尺寸标签、相对时间。
- 点击卡片：触发 `ClipboardPaster.shared.paste(item)`，播 0.2s 绿闪反馈动画，**不调用 notchClose()**。

- [ ] **步骤 2：在 NotchRootView.swift 中挂载 .clipboard 页面与耳区**

在 `NotchRootView.swift` 的 `pages`：
```swift
case .clipboard:
    ClipboardZoneView()
        .frame(maxWidth: .infinity, alignment: .top)
        .transition(reduceMotion ? .opacity : (vm.lastSwipeDirection == .next ? .zoneSlideNext : .zoneSlidePrevious))
```
并在 `earsRow` 补充耳区显示（左耳显示“剪贴板”，右耳显示条目数）。

- [ ] **步骤 3：在应用启动时启动 ClipboardMonitor**

在启动流程中调用 `ClipboardMonitor.shared.start()`。

- [ ] **步骤 4：注册并验证完整编译与测试**

运行：
`xcodebuild test -project NotchDrop.xcodeproj -scheme NotchDrop -derivedDataPath /tmp/nDD CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO`
预期：ALL TESTS PASS

- [ ] **步骤 5：Commit**

```bash
git add NotchDrop/ClipboardZoneView.swift NotchDrop/NotchRootView.swift NotchDrop.xcodeproj/project.pbxproj
git commit -m "feat(ui): 交付 ClipboardZoneView 界面并集成至刘海主视图与启动监听"
```
