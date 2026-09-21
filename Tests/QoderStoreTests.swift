//
//  QoderStoreTests.swift
//  NotchEveryTests
//
//  任务 6：QoderStore 的解码契约 + isStale 语义 + 发布去重。网络经假 transport 注入，不真联网。
//

import XCTest
@testable import NotchEvery

/// 假 transport：按 URL path 返回预置 Data / 抛错。
private final class FakeTransport: QoderHTTPTransport {
    var quotaData: Data?
    var poolData: Data?
    var shouldFail = false
    func get(url: URL, bearer: String) async throws -> Data {
        if shouldFail { throw URLError(.cannotConnectToHost) }
        if url.path.hasSuffix("/quota") { return quotaData ?? Data() }
        if url.path.hasSuffix("/pool/status") { return poolData ?? Data() }
        return Data()
    }
}

final class QoderStoreTests: XCTestCase {

    private func fixture(_ name: String, _ ext: String) -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().appendingPathComponent("Fixtures/\(name).\(ext)")
        return (try? Data(contentsOf: url)) ?? Data()
    }

    // MARK: - /quota 解码 golden

    func testQuotaDecodesGoldenFields() throws {
        let q = try XCTUnwrap(QoderQuota.decode(fixture("quota", "json")))
        XCTAssertEqual(q.userType, "personal_professional_trial")
        XCTAssertEqual(q.unit, "credits")
        XCTAssertEqual(q.total, 300)
        XCTAssertEqual(q.used, 0)
        XCTAssertEqual(q.remaining, 300)
        XCTAssertFalse(q.isExceeded)
        // reset_at_ms → Date
        XCTAssertEqual(q.resetDate?.timeIntervalSince1970 ?? 0, 1791104839.834, accuracy: 0.5)
    }

    func testQuotaDecodeGarbageReturnsNil() {
        XCTAssertNil(QoderQuota.decode(Data("not json".utf8)))
        XCTAssertNil(QoderQuota.decode(Data()))
    }

    // MARK: - /v1/pool/status 解码 golden（供圆形池）

    func testPoolStatusDecodesMembers() throws {
        let parsed = try XCTUnwrap(QoderPoolStatus.decode(fixture("pool-status", "json")))
        XCTAssertEqual(parsed.totalAccounts, 4)
        XCTAssertEqual(parsed.activeAccounts, 4)
        XCTAssertEqual(parsed.cooledAccounts, 0)
        XCTAssertEqual(parsed.accounts.count, 4)
        XCTAssertTrue(parsed.accounts.allSatisfy { !$0.cooled })
        // sticky 与 accounts 尾号一致校验
        XCTAssertEqual(parsed.stickyUserId, parsed.accounts.last?.userId)
    }

    // MARK: - isStale：连续失败 ≥2 ⇒ stale；成功即清除

    @MainActor
    func testStaleAfterTwoConsecutiveFailures() async {
        let t = FakeTransport()
        t.shouldFail = true
        let store = QoderStore(port: 8096, transport: t)
        await store.refreshNow()
        XCTAssertFalse(store.isQuotaStale, "单次失败不算 stale")
        await store.refreshNow()
        XCTAssertTrue(store.isQuotaStale, "连续两次失败应 stale")

        t.shouldFail = false
        t.quotaData = fixture("quota", "json")
        await store.refreshNow()
        XCTAssertFalse(store.isQuotaStale, "成功后 stale 标志清除")
        XCTAssertNotNil(store.quota)
    }

    // MARK: - 发布去重：同值不重复 publish

    @MainActor
    func testPublishDedupOnIdenticalValue() async {
        let t = FakeTransport()
        t.quotaData = fixture("quota", "json")
        t.poolData = fixture("pool-status", "json")
        let store = QoderStore(port: 8096, transport: t)
        await store.refreshNow()
        let first = store.objectWillChangeCountForTest
        await store.refreshNow()   // 完全相同数据
        XCTAssertEqual(store.objectWillChangeCountForTest, first, "同值不应再次 objectWillChange")
    }
}
