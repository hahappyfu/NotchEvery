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
