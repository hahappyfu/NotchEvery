//
//  MagpieUsageReader.swift
//  NotchEvery
//
//  usage.jsonl 增量读取：按字节 offset 只消费完整行、轮转自动重读、
//  冷启动只读尾部窗口，并过滤 Magpie 内部探活行（kind == provider_test / source == probe）。
//

import Foundation

// MARK: - 时间解析（RFC3339 变长小数秒）

enum MagpieDate {
    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plainFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parse(_ raw: String) -> Date? {
        if let date = fractionalFormatter.date(from: raw) { return date }
        if let date = plainFormatter.date(from: raw) { return date }
        // ISO8601DateFormatter 的小数秒要求恰好 3 位：把变长小数归一化后重试
        if let normalized = normalizeFractionalSeconds(raw),
           let date = fractionalFormatter.date(from: normalized)
        {
            return date
        }
        return nil
    }

    static func normalizeFractionalSeconds(_ raw: String) -> String? {
        guard let dot = raw.firstIndex(of: ".") else { return nil }
        var index = raw.index(after: dot)
        var digits = ""
        while index < raw.endIndex, raw[index].isNumber {
            digits.append(raw[index])
            index = raw.index(after: index)
        }
        guard !digits.isEmpty else { return nil }
        let millis = digits.count >= 3
            ? String(digits.prefix(3))
            : digits + String(repeating: "0", count: 3 - digits.count)
        return String(raw[..<dot]) + "." + millis + String(raw[index...])
    }
}

// MARK: - 增量读取器

enum MagpieUsageReader {
    struct TailState: Equatable {
        var offset: UInt64 = 0
        var inode: UInt64 = 0
        static let empty = TailState()
    }

    /// 内部探活行：kind == provider_test 或 source == probe（不污染流水与错误计数）。
    static func isProbe(kind: String?, source: String?) -> Bool {
        kind == "provider_test" || source == "probe"
    }

    static func decodeLine(_ data: Data, offset: UInt64) -> MagpieUsageRecord? {
        guard let line = try? JSONDecoder().decode(UsageLine.self, from: data) else { return nil }
        if isProbe(kind: line.kind, source: line.source) { return nil }
        guard let rawTime = line.t, let time = MagpieDate.parse(rawTime) else { return nil }
        return MagpieUsageRecord(
            id: line.rid ?? "\(line.routeID ?? 0)-\(offset)",
            routeID: line.routeID,
            time: time,
            agent: line.agent ?? "",
            provider: line.provider ?? "",
            providerAccount: line.providerAccount ?? "",
            model: line.model ?? "",
            served: line.served,
            req: line.req ?? "",
            inputTokens: line.inbound ?? 0,
            outputTokens: line.out ?? 0,
            cacheRead: line.cacheRead ?? 0,
            cacheWrite: line.cacheWrite ?? 0,
            reasoning: line.reasoning ?? 0,
            durationMs: line.ms,
            ttftMs: line.ttftMs,
            maskingMs: line.maskingMs,
            status: line.status,
            handedOn: line.handedOn ?? false,
            flowMs: line.flowMs,
            tries: line.tries ?? 1
        )
    }

    /// 增量读取：返回新解码的完整行记录；state 只推进到最后一个换行。
    static func readNewRecords(
        file: URL,
        state: inout TailState,
        maxColdBytes: Int = 4_000_000
    ) -> [MagpieUsageRecord] {
        var st = stat()
        guard lstat(file.path, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG else { return [] }
        let inode = UInt64(st.st_ino)
        let size = UInt64(max(0, st.st_size))

        if state.inode == 0 {
            state.inode = inode
        } else if state.inode != inode || size < state.offset {
            state = TailState(offset: 0, inode: inode)
        }
        guard size > state.offset else { return [] }

        var readStart = state.offset
        var skipToNewline = false
        if readStart == 0, size > UInt64(maxColdBytes) {
            readStart = size - UInt64(maxColdBytes)
            skipToNewline = true
        }

        guard let handle = try? FileHandle(forReadingFrom: file) else { return [] }
        defer { try? handle.close() }
        do { try handle.seek(toOffset: readStart) } catch { return [] }
        guard var body = try? handle.readToEnd(), !body.isEmpty else { return [] }

        if skipToNewline {
            guard let newline = body.firstIndex(of: 0x0A) else { return [] }
            readStart += UInt64(body.distance(from: body.startIndex, to: newline) + 1)
            body = Data(body[(newline + 1)...])
        }
        guard let lastNewline = body.lastIndex(of: 0x0A) else { return [] }
        let consumed = body[...lastNewline]
        state.offset = readStart + UInt64(consumed.count)

        var records: [MagpieUsageRecord] = []
        var lineOffset = readStart
        for line in consumed.dropLast().split(separator: 0x0A, omittingEmptySubsequences: false) {
            if !line.isEmpty, let record = decodeLine(Data(line), offset: lineOffset) {
                records.append(record)
            }
            lineOffset += UInt64(line.count) + 1
        }
        return records
    }

    // MARK: - 行解码

    private struct UsageLine: Decodable {
        let routeID: Int64?
        let t: String?
        let agent: String?
        let provider: String?
        let providerAccount: String?
        let model: String?
        let req: String?
        let served: String?
        let inbound: Int?
        let out: Int?
        let cacheRead: Int?
        let cacheWrite: Int?
        let reasoning: Int?
        let ms: Int?
        let ttftMs: Int?
        let flowMs: Int?
        let maskingMs: Int?
        let tries: Int?
        let status: Int?
        let rid: String?
        let handedOn: Bool?
        let kind: String?
        let source: String?

        enum CodingKeys: String, CodingKey {
            case routeID = "route_id"
            case t, agent, provider, providerAccount, model, req, served, out, reasoning, ms, status, rid, kind, source
            case inbound = "in"
            case cacheRead = "cache_read"
            case cacheWrite = "cache_write"
            case ttftMs = "ttft_ms"
            case flowMs = "flow_ms"
            case maskingMs = "masking_ms"
            case tries
            case handedOn = "handed_on"
        }
    }
}
