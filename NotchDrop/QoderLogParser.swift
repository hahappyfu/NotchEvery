//
//  QoderLogParser.swift
//  NotchEvery
//
//  任务 5：qodercn-gateway 日志的增量 tailer + 行解析 + 日界聚合。纯函数层，IO 经参数注入。
//  契约行格式(真实样例)：
//    2026/09/21 10:34:51 remote usage model=qfmodel acct=<脱敏> in=.. out=.. cached=.. reasoning=.. total=.. credits=..
//  日期分隔符是 `/` 不是 `-`：这是 Go 标准库 log 包 LstdFlags 的固定格式（`2009/01/23 01:23:23`），
//  不是我们自己拼的时间戳，改不了；之前正则按 `-` 写、测试样例也照抄成 `-`，两边「错得一致」，
//  真实日志一条都匹配不上，导致「今日请求/今日 credits」恒显示 0（2026-09-22 装机版实测复现）。
//

import Foundation

/// 一条计费用量事件。
struct QoderUsageEvent: Equatable {
    let dateString: String   // 归一化为 YYYY-MM-DD（原始日志是 YYYY/MM/DD，见 parse 里的替换）
    let model: String
    let inTokens: Int
    let outTokens: Int
    let cached: Int
    let reasoning: Int
    let total: Int
    let credits: Double
}

enum QoderLogParser {
    /// 行首时间戳 + remote usage + 各字段。acct 为可选段（旧版可能无）。
    private static let regex = try! NSRegularExpression(
        pattern: #"^(\d{4}/\d{2}/\d{2}) (\d{2}:\d{2}:\d{2}).*remote usage model=(\S+)(?: acct=\S+)? in=(\d+) out=(\d+) cached=(\d+) reasoning=(\d+) total=(\d+) credits=([\d.]+)"#,
        options: []
    )

    /// 解析一行；非 usage 行返回 nil。
    static func parse(_ line: String) -> QoderUsageEvent? {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let m = regex.firstMatch(in: line, options: [], range: range), m.numberOfRanges >= 10 else {
            return nil
        }
        func group(_ i: Int) -> String? {
            guard let r = Range(m.range(at: i), in: line) else { return nil }
            return String(line[r])
        }
        guard let date = group(1), let model = group(3),
              let inT = group(4).flatMap(Int.init), let outT = group(5).flatMap(Int.init),
              let cached = group(6).flatMap(Int.init), let reasoning = group(7).flatMap(Int.init),
              let total = group(8).flatMap(Int.init), let credits = group(9).flatMap(Double.init)
        else { return nil }
        // 归一化成 `yyyy-MM-dd` 再往外传：QoderStore.dayString() 用的是这个格式做「是不是今天」的比较，
        // 如果这里直接透传原始斜杠格式，两边永远不相等，全部事件会被误判成「昨天」，今日计数依然是 0。
        let normalizedDate = date.replacingOccurrences(of: "/", with: "-")
        return QoderUsageEvent(dateString: normalizedDate, model: model, inTokens: inT, outTokens: outT,
                               cached: cached, reasoning: reasoning, total: total, credits: credits)
    }
}

/// 增量读取游标：记录已消费字节偏移。size < offset 视为轮转 → 归零重扫。
struct QoderLogTailer {
    struct Cursor {
        var offset: UInt64 = 0
    }

    /// 从 url 读 cursor.offset 之后的新完整行，推进 cursor，返回解析出的事件。
    /// 尾部残行（无换行）不消费、offset 停在最后一个完整行末尾。
    static func readIncremental(url: URL, cursor: inout Cursor) throws -> [QoderUsageEvent] {
        let fh = try FileHandle(forReadingFrom: url)
        defer { try? fh.close() }
        let size = (try? fh.seekToEndOfFile()) ?? 0

        // 轮转/截断：文件变小 → 从头重扫
        if size < cursor.offset {
            cursor.offset = 0
        }
        if size == cursor.offset { return [] }

        try fh.seek(toOffset: cursor.offset)
        let data = fh.readDataToEndOfFile()
        guard !data.isEmpty else { return [] }

        // 只消费到最后一个换行符；之后的残行留待下次
        guard let lastNL = data.lastIndex(of: 0x0A) else {
            return []  // 整块都是残行，不推进 offset
        }
        let complete = data.subdata(in: data.startIndex..<(lastNL + 1))
        cursor.offset += UInt64(complete.count)

        let text = String(data: complete, encoding: .utf8) ?? ""
        return text.split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { QoderLogParser.parse(String($0)) }
    }
}

/// 单日聚合桶。cacheRate 口径：cached / (in + cached)。
struct QoderDailyAgg: Equatable {
    var calls: Int = 0
    var tokensIn: Int = 0
    var tokensOut: Int = 0
    var cached: Int = 0
    var credits: Double = 0

    var cacheRateFraction: Double {
        let denom = tokensIn + cached
        return denom > 0 ? Double(cached) / Double(denom) : 0
    }
}

/// 按 today 分界聚合：today 计入今日桶，其余归入 yesterday（保留最近一个非今日日的累计）。
struct QoderAggregator {
    var today = QoderDailyAgg()
    var yesterday: QoderDailyAgg?
    /// 上一次 apply 用的日期串，跨零点判定用。没有它的话，连续运行时新一天的事件会继续累加进
    /// 仍装着昨天数据的 today 桶（每个事件只跟 todayStr 比，桶自己从不知道已经跨天了）。
    var currentDay: String?

    mutating func apply(events: [QoderUsageEvent], today todayStr: String) {
        // 日界翻转：today 入参换到新的一天 → 旧 today 桶整体沉为 yesterday，today 清零重新累计。
        // 注意参数 `today` 遮蔽了同名属性，翻转必须写 self.today。
        if let day = currentDay, day != todayStr {
            yesterday = self.today
            self.today = QoderDailyAgg()
        }
        currentDay = todayStr
        for ev in events {
            if ev.dateString == todayStr {
                accumulate(&today, ev)
            } else {
                // 跨日：并入 yesterday（若已有不同日的昨日则覆盖为新出现的更早日，简单取最后一条非今日日）
                var y = yesterday ?? QoderDailyAgg()
                accumulate(&y, ev)
                yesterday = y
            }
        }
    }

    private func accumulate(_ agg: inout QoderDailyAgg, _ ev: QoderUsageEvent) {
        agg.calls += 1
        agg.tokensIn += ev.inTokens
        agg.tokensOut += ev.outTokens
        agg.cached += ev.cached
        agg.credits += ev.credits
    }
}
