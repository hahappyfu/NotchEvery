import XCTest
@testable import NotchEvery

final class MagpieUsageReaderTests: XCTestCase {
    private var dir: URL!
    private var file: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("MagpieReaderTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        file = dir.appendingPathComponent("usage.jsonl")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        dir = nil
        file = nil
    }

    private func write(_ text: String) throws {
        try text.write(to: file, atomically: false, encoding: .utf8)
    }

    private func append(_ text: String) throws {
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
        try handle.close()
    }

    private var basicLine: String {
        #"{"route_id":1795409334679,"t":"2026-11-23T15:14:06.480483+08:00","agent":"claude","provider":"codearts","providerAccount":"iam::x","model":"deepseek-v4.1-flash","req":"group/deepflash","served":"deepseek-v4.1-flash","in":1082,"out":172,"cache_read":93440,"cache_write":0,"reasoning":116,"ms":3598,"ttft_ms":2665,"masking_ms":150,"status":200,"rid":"445db8aa925d0f07c2d53acdec32a51d","handed_on":true}"#
    }

    // 1. 完整行解码
    func testDecodeBasicLine() throws {
        let data = Data(basicLine.utf8)
        let record = try XCTUnwrap(MagpieUsageReader.decodeLine(data, offset: 0))
        XCTAssertEqual(record.id, "445db8aa925d0f07c2d53acdec32a51d")
        XCTAssertEqual(record.routeID, 1_795_409_334_679)
        XCTAssertEqual(record.agent, "claude")
        XCTAssertEqual(record.provider, "codearts")
        XCTAssertEqual(record.providerAccount, "iam::x")
        XCTAssertEqual(record.model, "deepseek-v4.1-flash")
        XCTAssertEqual(record.served, "deepseek-v4.1-flash")
        XCTAssertEqual(record.req, "group/deepflash")
        XCTAssertEqual(record.inputTokens, 1082)
        XCTAssertEqual(record.outputTokens, 172)
        XCTAssertEqual(record.cacheRead, 93440)
        XCTAssertEqual(record.cacheWrite, 0)
        XCTAssertEqual(record.reasoning, 116)
        XCTAssertEqual(record.durationMs, 3598)
        XCTAssertEqual(record.ttftMs, 2665)
        XCTAssertEqual(record.maskingMs, 150)
        XCTAssertEqual(record.status, 200)
        XCTAssertTrue(record.handedOn)
        XCTAssertNotNil(MagpieDate.parse("2026-11-23T15:14:06.480483+08:00"))
    }

    // 2. 探活行过滤
    func testFilterProbeRows() {
        let probeKind = Data(#"{"t":"2026-11-23T11:04:53.064462+08:00","provider":"x","kind":"provider_test"}"#.utf8)
        let probeSource = Data(#"{"t":"2026-11-23T11:04:53.064462+08:00","provider":"x","source":"probe"}"#.utf8)
        XCTAssertNil(MagpieUsageReader.decodeLine(probeKind, offset: 0))
        XCTAssertNil(MagpieUsageReader.decodeLine(probeSource, offset: 0))
        XCTAssertNotNil(MagpieUsageReader.decodeLine(Data(basicLine.utf8), offset: 0))
    }

    // 3. 变长小数秒
    func testVariableFractionTimestamps() throws {
        let dates = try ["2026-11-23T15:14:06.254077+08:00",
                         "2026-11-23T15:14:06.35674+08:00",
                         "2026-11-23T15:14:06.841213+08:00",
                         "2026-11-23T07:14:06.123Z"]
            .map { try XCTUnwrap(MagpieDate.parse($0)) }
        let cal = Calendar(identifier: .gregorian)
        for date in dates.prefix(3) {
            XCTAssertEqual(cal.component(.second, from: date), 6)
        }
        XCTAssertNotNil(MagpieDate.parse("2026-11-23T15:14:06+08:00"))
    }

    // 4. 无 rid 时按 routeID-offset 生成 id
    func testIDFallsBackToRouteIDOffset() throws {
        let line = #"{"route_id":1795,"t":"2026-11-23T15:14:06+08:00","provider":"p"}"#
        let record = try XCTUnwrap(MagpieUsageReader.decodeLine(Data(line.utf8), offset: 42))
        XCTAssertEqual(record.id, "1795-42")
    }

    // 5. 增量只读新行
    func testIncrementalTailReadsOnlyNewLines() throws {
        try write([basicLine, basicLine].joined(separator: "\n") + "\n")
        var state = MagpieUsageReader.TailState.empty
        let first = MagpieUsageReader.readNewRecords(file: file, state: &state)
        XCTAssertEqual(first.count, 2)
        XCTAssertEqual(state.offset, UInt64((try Data(contentsOf: file)).count))

        try append(basicLine + "\n")
        let second = MagpieUsageReader.readNewRecords(file: file, state: &state)
        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(state.offset, UInt64((try Data(contentsOf: file)).count))

        let third = MagpieUsageReader.readNewRecords(file: file, state: &state)
        XCTAssertTrue(third.isEmpty)
    }

    // 6. 半行不消费，补齐后恰好读一次
    func testPartialLineNotConsumedUntilCompleted() throws {
        let half = String(basicLine.prefix(40))
        try write(basicLine + "\n" + half)
        var state = MagpieUsageReader.TailState.empty
        XCTAssertEqual(MagpieUsageReader.readNewRecords(file: file, state: &state).count, 1)

        try append(String(basicLine.dropFirst(40)) + "\n")
        let completed = MagpieUsageReader.readNewRecords(file: file, state: &state)
        XCTAssertEqual(completed.count, 1)
        XCTAssertEqual(completed.first?.routeID, 1_795_409_334_679)
        XCTAssertTrue(MagpieUsageReader.readNewRecords(file: file, state: &state).isEmpty)
    }

    // 7. 轮转/截断自动重读
    func testRotationResetsOffset() throws {
        try write([basicLine, basicLine].joined(separator: "\n") + "\n")
        var state = MagpieUsageReader.TailState.empty
        XCTAssertEqual(MagpieUsageReader.readNewRecords(file: file, state: &state).count, 2)

        let rotated = #"{"route_id":7,"t":"2026-11-23T16:00:00+08:00","provider":"new"}"# + "\n"
        try rotated.write(to: file, atomically: false, encoding: .utf8)
        let after = MagpieUsageReader.readNewRecords(file: file, state: &state)
        XCTAssertEqual(after.count, 1)
        XCTAssertEqual(after.first?.routeID, 7)
    }

    // 8. 冷启动只读尾部窗口
    func testColdStartReadsOnlyTailWindow() throws {
        let lines = (0..<10).map { i in
            #"{"route_id":\#(i),"t":"2026-11-23T15:00:00+08:00","provider":"p","pad":"\#(String(repeating: "x", count: 60))"}"#
        }
        try write(lines.joined(separator: "\n") + "\n")
        var state = MagpieUsageReader.TailState.empty
        let records = MagpieUsageReader.readNewRecords(file: file, state: &state, maxColdBytes: 350)
        XCTAssertFalse(records.isEmpty)
        XCTAssertLessThan(records.count, 10)
        // 必须是从完整行开始的尾部
        XCTAssertTrue(records.map(\.routeID).compactMap { $0 } == Array(9 - (records.count - 1)...9).map(Int64.init))
    }

    // A3: 解码 flow_ms / tries，缺省 tries 为 1。
    func testDecodeThroughputAndTriesFields() throws {
        let line = #"{"t":"2026-11-23T10:00:00+08:00","provider":"p","in":10,"out":20,"flow_ms":150,"tries":3,"status":200}"#
        let record = try XCTUnwrap(MagpieUsageReader.decodeLine(Data(line.utf8), offset: 0))
        XCTAssertEqual(record.flowMs, 150)
        XCTAssertEqual(record.tries, 3)
        let plain = try XCTUnwrap(MagpieUsageReader.decodeLine(Data(#"{"t":"2026-11-23T10:00:00+08:00"}"#.utf8), offset: 0))
        XCTAssertNil(plain.flowMs)
        XCTAssertEqual(plain.tries, 1)
    }
}
