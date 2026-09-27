//
//  PublishedPersistCorruptBackupTests.swift
//  NotchEveryTests
//

import XCTest
@testable import NotchEvery

/// 审计 D-C1：Persist 解码失败时必须先把坏文件备份为 .corrupt.<时间戳>，再回落默认值
final class PublishedPersistCorruptBackupTests: XCTestCase {
    /// 重定向到临时目录的 FileStorage，避免污染真实 Config 目录
    private final class TempFileStorage: FileStorage {
        let baseURL: URL

        init(baseURL: URL) {
            self.baseURL = baseURL
            super.init()
        }

        override func pathForKey(_ key: String) -> URL {
            baseURL.appendingPathComponent(key)
        }
    }

    private struct StubValue: Codable, Equatable {
        var name: String
        var count: Int
    }

    /// 解码失败 → 生成 .corrupt.<时间戳> 备份且内容等于坏 JSON，值回落默认
    func testDecodeFailureBacksUpCorruptFile() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PersistCorruptBackup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let key = "corrupt-backup-test"
        let badData = Data("{not valid json".utf8)
        let storage = TempFileStorage(baseURL: dir)
        try badData.write(to: storage.pathForKey(key), options: .atomic)

        let defaultValue = StubValue(name: "default", count: 0)
        // PublishedPersist 解码逻辑在 Persist.init 内，直接实例化走同一失败分支
        let persist = Persist(key: key, defaultValue: defaultValue, engine: storage)

        XCTAssertEqual(persist.wrappedValue, defaultValue)

        let backups = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasPrefix("\(key).corrupt.") }
        XCTAssertEqual(backups.count, 1, "应恰好生成一个 .corrupt.<时间戳> 备份")
        let backedUp = try Data(contentsOf: dir.appendingPathComponent(backups[0]))
        XCTAssertEqual(backedUp, badData, "备份内容应等于原始坏文件")
    }
}
