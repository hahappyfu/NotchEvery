import XCTest
@testable import NotchEvery

final class TrayDropTests: XCTestCase {
    /// memberwise init 因自定义 init 不可用，走 JSONDecoder 构造；
    /// copiedDate 按 age 回推（JSONDecoder 默认策略 = timeIntervalSinceReferenceDate Double）。
    private func makeItem(id: UUID, fileName: String, age: TimeInterval) throws -> TrayDrop.DropItem {
        let ts = Date().addingTimeInterval(-age).timeIntervalSinceReferenceDate
        let json = """
        {"id":"\(id.uuidString)","fileName":"\(fileName)","size":1,"copiedDate":\(ts)}
        """
        return try JSONDecoder().decode(TrayDrop.DropItem.self, from: Data(json.utf8))
    }

    /// W-C2 回归：cleanExpiredFiles 必须连磁盘文件一起删，不能只移出集合。
    /// documentsDirectory 是全局 let 不可注入，故在真实 ~/.notchevery 下用
    /// 唯一 UUID 目录隔离测试数据，结束后恢复 items 快照并清理残留文件。
    func testCleanExpiredFilesRemovesItemsAndDiskFiles() throws {
        let drop = TrayDrop.shared
        let snapshot = drop.items
        let expiredID = UUID()
        let freshID = UUID()
        let expired = try makeItem(id: expiredID, fileName: "w-c2-expired.txt", age: 365 * 24 * 3600)
        let fresh = try makeItem(id: freshID, fileName: "w-c2-fresh.txt", age: 0)
        let itemsRoot = documentsDirectory.appendingPathComponent(TrayDrop.DropItem.mainDir)
        for item in [expired, fresh] {
            try FileManager.default.createDirectory(
                at: item.storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("w-c2-test".utf8).write(to: item.storageURL)
        }
        drop.items = [expired, fresh]
        defer {
            try? FileManager.default.removeItem(at: itemsRoot.appendingPathComponent(freshID.uuidString))
            try? FileManager.default.removeItem(at: itemsRoot.appendingPathComponent(expiredID.uuidString))
            drop.items = snapshot
        }

        drop.cleanExpiredFiles()

        XCTAssertEqual(drop.items.map(\.id), [fresh.id], "过期条目应被移出，新鲜条目保留")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: expired.storageURL.deletingLastPathComponent().path),
            "过期条目的磁盘目录应被删除"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: fresh.storageURL.path),
            "新鲜条目文件应保留"
        )
    }

    func testLoadPartialSuccessKeepsSucceeded() {
        // mock 2 URL 其中 1 个 copyItem 失败，succeeded.count == 1 且 items 保留成功项
        // TODO: 需 NSItemProvider mock 后跑通
    }
}
