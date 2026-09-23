import XCTest
@testable import NotchEvery

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

    // MARK: - Helpers

    /// 生成确定性字节模式作为图片数据（store 只负责落盘，不做 PNG 解码，无需真实 PNG）
    private func makeImageData(seed: UInt8 = 0, length: Int = 64) -> Data {
        Data((0..<length).map { UInt8((Int($0) + Int(seed)) % 256) })
    }

    /// 轮询 metadata 文件，等待后台串行队列把至少 `expected` 条数据落盘
    @discardableResult
    private func waitForPersistedItemCount(_ expected: Int, timeout: TimeInterval = 5.0) -> [ClipboardItem]? {
        let url = tempDir.appendingPathComponent("clipboard_history.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let deadline = Date().addingTimeInterval(timeout)
        var lastDecoded: [ClipboardItem]?
        while Date() < deadline {
            if let data = try? Data(contentsOf: url),
               let items = try? decoder.decode([ClipboardItem].self, from: data) {
                lastDecoded = items
                if items.count == expected { return items }
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return lastDecoded
    }

    // MARK: - Text

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

    func testMultiDeviceSyncDeduplication() {
        // 多端云同步基础场景：A → B → C 连续同步收录
        store.addText("Sync A")
        store.addText("Sync B")
        store.addText("Sync C")
        XCTAssertEqual(store.items.count, 3)

        // 首尾空白差异（换行/空格）规范化后视为同一文本，命中前 3 项即去重
        store.addText(" \nSync A\n ")
        XCTAssertEqual(store.items.count, 3, "首尾空白差异应被规范化后认定为多端同步重复")

        // 滑动窗口：插入 D 后 A 滑出前 3 项，此时再次同步 A 应正常收录
        store.addText("Sync D")
        XCTAssertEqual(store.items.count, 4)
        store.addText("Sync A")
        XCTAssertEqual(store.items.count, 5, "已滑出前 3 项窗口的旧文本应允许重新收录")
        XCTAssertEqual(store.items.first?.textContent, "Sync A")

        // 命中窗口内最新条目（带空白差异）同样按重复丢弃
        store.addText("\nSync A\n")
        XCTAssertEqual(store.items.count, 5, "窗口内文本带首尾空白再次同步时不应新增重复条目")
    }

    func testFiftyItemsHardLimitEviction() {
        for i in 0..<55 {
            store.addText("Item \(i)")
        }
        XCTAssertEqual(store.items.count, 50)
        XCTAssertEqual(store.items.first?.textContent, "Item 54")
        XCTAssertEqual(store.items.last?.textContent, "Item 5")
    }

    // MARK: - Image

    func testDeduplicateConsecutiveIdenticalImage() {
        let data = makeImageData(seed: 5)
        store.addImage(data: data, size: CGSize(width: 10, height: 10))
        store.addImage(data: data, size: CGSize(width: 10, height: 10))
        XCTAssertEqual(store.items.count, 1)

        // 不同字节的图片应正常插入
        store.addImage(data: makeImageData(seed: 6), size: CGSize(width: 10, height: 10))
        XCTAssertEqual(store.items.count, 2)
    }

    func testImageFileDeletedWhenEvicted() {
        store.addImage(data: makeImageData(seed: 7), size: CGSize(width: 10, height: 10))
        guard let imageItem = store.items.first else { return XCTFail("图片条目未插入") }
        guard let fileURL = store.imageURL(for: imageItem) else { return XCTFail("图片 URL 为空") }
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        // 再插入 50 条文本，把最老的图片条挤出上限
        for i in 0..<50 {
            store.addText("Text \(i)")
        }

        XCTAssertEqual(store.items.count, 50)
        XCTAssertFalse(store.items.contains { $0.type == .image })
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path), "被淘汰图片的物理文件应同步删除")
    }

    // MARK: - Pin

    func testTogglePinPreservesItemAcrossEviction() {
        store.addText("Important Item")
        guard let id = store.items.first?.id else { return XCTFail("首条未插入") }
        store.togglePin(id: id)
        XCTAssertTrue(store.items.first?.isPinned == true)
        XCTAssertEqual(store.items.first?.id, id)

        // 插入 55 条新条目：置顶项绝对豁免 50 条上限淘汰，且始终排在最前面
        for i in 0..<55 {
            store.addText("Normal Item \(i)")
        }

        XCTAssertEqual(store.items.count, 50)
        XCTAssertTrue(store.items.contains { $0.id == id }, "置顶项必须豁免淘汰")
        XCTAssertEqual(store.items.first?.id, id, "置顶项应始终排在最前面")

        // 被淘汰的应全部是最老的非置顶项（Item 0 ~ Item 5），非置顶区保持复制时间倒序
        let unpinned = store.items.filter { !$0.isPinned }
        XCTAssertEqual(unpinned.count, 49)
        XCTAssertEqual(unpinned.first?.textContent, "Normal Item 54")
        XCTAssertEqual(unpinned.last?.textContent, "Normal Item 6")
        XCTAssertFalse(store.items.contains { $0.textContent == "Normal Item 0" }, "最老的非置顶项应被淘汰")

        // 置顶状态随元数据持久化：重载后仍保持置顶与置顶排序
        let persisted = waitForPersistedItemCount(50)
        XCTAssertEqual(persisted?.first?.id, id)
        XCTAssertEqual(persisted?.first?.isPinned, true, "isPinned 应序列化落盘")

        let reloaded = ClipboardStore(storageDirectory: tempDir)
        XCTAssertEqual(reloaded.items.first?.id, id, "重载后置顶项应仍在最前")
        XCTAssertTrue(reloaded.items.first?.isPinned == true)
        XCTAssertEqual(reloaded.items.count, 50)
    }

    func testDecodingLegacyMetadataWithoutPinFieldDefaultsToUnpinned() {
        // 旧版本数据没有 isPinned 字段：解码时应默认非置顶，不得整体解码失败
        let legacy: [[String: Any]] = [
            [
                "id": UUID().uuidString,
                "type": "text",
                "textContent": "Legacy Item",
                "charCount": 11,
                "copiedAt": "2026-09-23T00:00:00Z",
            ]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: legacy) else {
            return XCTFail("JSON 构造失败")
        }
        try? data.write(to: tempDir.appendingPathComponent("clipboard_history.json"))

        let reloaded = ClipboardStore(storageDirectory: tempDir)
        XCTAssertEqual(reloaded.items.count, 1)
        XCTAssertEqual(reloaded.items.first?.textContent, "Legacy Item")
        XCTAssertEqual(reloaded.items.first?.isPinned, false, "缺失 isPinned 字段时应默认非置顶")
    }

    // MARK: - Clear

    func testClearAllRemovesItemsAndFiles() {
        store.addText("Item 1")
        store.addImage(data: makeImageData(seed: 2), size: CGSize(width: 10, height: 10))
        waitForPersistedItemCount(2)

        store.clearAll()

        XCTAssertTrue(store.items.isEmpty)
        let metadataURL = tempDir.appendingPathComponent("clipboard_history.json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: metadataURL.path), "clearAll 后 metadata 文件应被删除")
        let imagesDir = tempDir.appendingPathComponent("Images")
        let remaining = (try? FileManager.default.contentsOfDirectory(at: imagesDir, includingPropertiesForKeys: nil)) ?? []
        XCTAssertTrue(remaining.isEmpty, "clearAll 后 Images 目录应为空")
    }

    // MARK: - Persistence

    func testPersistenceRoundTripRestoresItems() {
        let imgData = makeImageData(seed: 3)
        store.addText("Round Trip A")
        store.addText("Round Trip B")
        store.addImage(data: imgData, size: CGSize(width: 20, height: 15))

        let persisted = waitForPersistedItemCount(3)
        XCTAssertEqual(persisted?.count, 3, "写入后应落盘 3 条数据")

        let reloaded = ClipboardStore(storageDirectory: tempDir)
        XCTAssertEqual(reloaded.items.count, 3)
        XCTAssertEqual(reloaded.items[0].type, .image)
        XCTAssertEqual(reloaded.items[1].textContent, "Round Trip B")
        XCTAssertEqual(reloaded.items[2].textContent, "Round Trip A")

        guard let url = reloaded.imageURL(for: reloaded.items[0]) else { return XCTFail("重载后图片 URL 为空") }
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(try? Data(contentsOf: url), imgData)
    }

    func testLoadTruncatesOverLimitItems() {
        // 手工构造磁盘上 60 条数据（最新在前），验证加载时截断保留最新 50 条
        let items = (0..<60).reversed().map { i in
            ClipboardItem(type: .text, textContent: "Persist \(i)", charCount: 8)
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(items) {
            try? data.write(to: tempDir.appendingPathComponent("clipboard_history.json"))
        }

        let reloaded = ClipboardStore(storageDirectory: tempDir)
        XCTAssertEqual(reloaded.items.count, 50)
        XCTAssertEqual(reloaded.items.first?.textContent, "Persist 59")
        XCTAssertEqual(reloaded.items.last?.textContent, "Persist 10")
    }
}
