//
//  QoderLogParserTests.swift
//  NotchEveryTests
//
//  任务 5：网关日志增量 tailer + 日界聚合的纯函数测试。锚点 = Tests/Fixtures/qoder-gateway.log。
//

import XCTest
@testable import NotchEvery

final class QoderLogParserTests: XCTestCase {

    private func fixtureURL() -> URL {
        // 测试宿主里通过 Bundle(for:) 或仓库相对路径定位；用源码目录回推最稳。
        let src = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tests/
            .appendingPathComponent("Fixtures/qoder-gateway.log")
        return src
    }

    // MARK: - 单行解析

    func testParseUsageLineExtractsAllFields() throws {
        let line = "2026-09-21 10:34:51 remote usage model=qfmodel acct=01a****4a9 in=147002 out=345 cached=146673 reasoning=0 total=147347 credits=0.3557"
        let ev = try XCTUnwrap(QoderLogParser.parse(line))
        XCTAssertEqual(ev.model, "qfmodel")
        XCTAssertEqual(ev.inTokens, 147002)
        XCTAssertEqual(ev.outTokens, 345)
        XCTAssertEqual(ev.cached, 146673)
        XCTAssertEqual(ev.reasoning, 0)
        XCTAssertEqual(ev.total, 147347)
        XCTAssertEqual(ev.credits, 0.3557, accuracy: 1e-9)
        XCTAssertEqual(ev.dateString, "2026-09-21")
    }

    func testNonMatchingLinesIgnored() {
        XCTAssertNil(QoderLogParser.parse("2026-09-20 21:19:30 qodercn-gateway listening on http://127.0.0.1:8096"))
        XCTAssertNil(QoderLogParser.parse("2026-09-21 09:12:44 [pool] retiring acct=x (zero quota)"))
        XCTAssertNil(QoderLogParser.parse(""))
        XCTAssertNil(QoderLogParser.parse("garbage without timestamp"))
    }

    // MARK: - 增量读取：只消费新追加字节

    func testIncrementalOnlyConsumesNewBytes() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("qgw-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let base = "2026-09-21 10:00:00 remote usage model=a acct=x in=1 out=1 cached=0 reasoning=0 total=2 credits=0.1\n"
        try base.write(to: tmp, atomically: true, encoding: .utf8)

        var cursor = QoderLogTailer.Cursor()
        let first = try QoderLogTailer.readIncremental(url: tmp, cursor: &cursor)
        XCTAssertEqual(first.count, 1)

        // 无追加 → 第二次读到 0
        let second = try QoderLogTailer.readIncremental(url: tmp, cursor: &cursor)
        XCTAssertEqual(second.count, 0)

        // 追加一行 → 第三次只读到新的那行
        let extra = "2026-09-21 10:00:05 remote usage model=b acct=y in=5 out=5 cached=0 reasoning=0 total=10 credits=0.2\n"
        let fh = try FileHandle(forWritingTo: tmp); fh.seekToEndOfFile(); fh.write(Data(extra.utf8)); try fh.close()
        let third = try QoderLogTailer.readIncremental(url: tmp, cursor: &cursor)
        XCTAssertEqual(third.count, 1)
        XCTAssertEqual(third.first?.model, "b")
    }

    func testPartialTrailingLineNotConsumed() throws {
        // 尾部残行（无换行）不应被当成事件消费，且下次补齐后应能读到
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("qgw-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let full = "2026-09-21 10:00:00 remote usage model=a acct=x in=1 out=1 cached=0 reasoning=0 total=2 credits=0.1\n"
        let partial = "2026-09-21 10:00:09 remote usage model=c acct=z in=9 out=9 cached=0 reasoning=0 total=18 credi"
        try (full + partial).write(to: tmp, atomically: true, encoding: .utf8)

        var cursor = QoderLogTailer.Cursor()
        let r1 = try QoderLogTailer.readIncremental(url: tmp, cursor: &cursor)
        XCTAssertEqual(r1.count, 1, "残行不应计入")
        XCTAssertEqual(r1.first?.model, "a")

        let fh = try FileHandle(forWritingTo: tmp); fh.seekToEndOfFile()
        fh.write(Data("ts=100 credits=0.3\n".utf8)); try fh.close()
        let r2 = try QoderLogTailer.readIncremental(url: tmp, cursor: &cursor)
        XCTAssertEqual(r2.count, 1)
        XCTAssertEqual(r2.first?.model, "c")
    }

    // MARK: - 日界聚合

    func testDayRollResetsAggregatesAndKeepsYesterday() {
        let todayEvents = [
            QoderUsageEvent(dateString: "2026-09-21", model: "a", inTokens: 100, outTokens: 10, cached: 50, reasoning: 0, total: 110, credits: 1.0),
            QoderUsageEvent(dateString: "2026-09-21", model: "b", inTokens: 200, outTokens: 20, cached: 0, reasoning: 5, total: 225, credits: 2.0),
        ]
        let yestEvents = [
            QoderUsageEvent(dateString: "2026-09-20", model: "a", inTokens: 1000, outTokens: 100, cached: 900, reasoning: 0, total: 1100, credits: 5.0),
        ]
        var agg = QoderAggregator()
        agg.apply(events: yestEvents + todayEvents, today: "2026-09-21")

        XCTAssertEqual(agg.today.calls, 2)
        XCTAssertEqual(agg.today.tokensIn, 300)
        XCTAssertEqual(agg.today.credits, 3.0, accuracy: 1e-9)
        XCTAssertEqual(agg.yesterday?.calls, 1)
        XCTAssertEqual(agg.yesterday?.tokensIn, 1000)
    }

    func testCacheRateFollowsFixedFormula() {
        // cacheRate = cached / (in + cached)? 与 TokenFormatUtils 口径一致 —— 这里锁定一个明确公式：cached/total
        var agg = QoderAggregator()
        agg.apply(events: [
            QoderUsageEvent(dateString: "2026-09-21", model: "a", inTokens: 100, outTokens: 0, cached: 300, reasoning: 0, total: 400, credits: 0),
        ], today: "2026-09-21")
        // 约定：cacheRate = cached / (in + cached) = 300/400 = 0.75
        XCTAssertEqual(agg.today.cacheRateFraction, 0.75, accuracy: 1e-9)
    }

    // MARK: - 轮转检测（size 变小 → offset 归零重扫）

    func testRotationDetectedViaShrinkResetsOffset() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("qgw-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let big = String(repeating: "noise line not usage\n", count: 50)
        try big.write(to: tmp, atomically: true, encoding: .utf8)
        var cursor = QoderLogTailer.Cursor()
        _ = try QoderLogTailer.readIncremental(url: tmp, cursor: &cursor)
        XCTAssertGreaterThan(cursor.offset, 0)

        // 模拟 logrotate：文件被替换成更小内容
        let small = "2026-09-21 11:00:00 remote usage model=z acct=k in=1 out=1 cached=0 reasoning=0 total=2 credits=0.1\n"
        try small.write(to: tmp, atomically: true, encoding: .utf8)
        let after = try QoderLogTailer.readIncremental(url: tmp, cursor: &cursor)
        XCTAssertEqual(after.count, 1, "轮转后应从零重扫并读到新行")
        XCTAssertEqual(after.first?.model, "z")
    }
}
