// TimingLog.swift
// 高频时序埋点：按完整消息限流并缓存文件句柄，避免拖慢主线程。
//
// 来源：由 FUnlock 的 FUnlockUtils.swift 提取而来（工单 01，见 .scratch/funlock-merge/）。
// 原文件把四类关注点混在一起；本文件只承载逻辑层需要的 timingLog()（Foundation-only）。
// 写入路径仍为 ~/Library/Logs/FUnlock/timing.log，日志路径改写随工单 02 落地。
// 逻辑逐字未改。

import Foundation

// MARK: - 时序埋点（限流 + 句柄缓存）

private let timingLock = NSLock()
private var timingFileHandle: FileHandle?
private var lastTimingWriteByType: [String: Date] = [:]

private var timingLogDirectory: URL {
    let home = FileManager.default.homeDirectoryForCurrentUser
    return home.appendingPathComponent("Library/Logs/FUnlock")
}

private var timingLogFileURL: URL {
    timingLogDirectory.appendingPathComponent("timing.log")
}

private let timingDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    return f
}()

/// 时序埋点：按完整消息限流，同文案 1 秒最多写 1 条；
/// 文件句柄缓存复用，避免高频开/关文件拖慢主线程。
/// 写入 ~/Library/Logs/FUnlock/timing.log
func timingLog(_ msg: String) {
    timingLock.lock()
    defer { timingLock.unlock() }
    let now = Date()
    if let last = lastTimingWriteByType[msg], now.timeIntervalSince(last) < 1.0 {
        return
    }
    lastTimingWriteByType[msg] = now
    let ts = timingDateFormatter.string(from: now)
    let line = "[\(ts)] \(msg)\n"
    let url = timingLogFileURL
    try? FileManager.default.createDirectory(at: timingLogDirectory, withIntermediateDirectories: true)
    if timingFileHandle == nil || !FileManager.default.fileExists(atPath: url.path) {
        timingFileHandle = try? FileHandle(forWritingTo: url)
    }
    if let fh = timingFileHandle {
        fh.seekToEndOfFile()
        fh.write(line.data(using: .utf8)!)
    } else {
        try? line.write(to: url, atomically: true, encoding: .utf8)
        timingFileHandle = try? FileHandle(forWritingTo: url)
    }
}

/// 按设备名推断设备图标（Apple Watch / AirPods / iPad / Mac / iPhone 等）
