//
//  QuotaSnapshot.swift
//  NotchEvery
//
//  额度快照模型与归一化（移植自 EveryPlus OpenCodeGo，行为一致）。
//

import Foundation

struct QuotaWindow: Equatable {
    let key: String        // "5h" | "weekly" | "monthly"
    let used: Double
    let limit: Double
    let percent: Double    // 自算 used/limit*100，封顶 100
    let resetAt: Date?
}

struct QuotaSnapshot: Equatable {
    let fetchedAt: Date?
    let expired: Bool      // fetchedAt 缺失或距今 > 10min
    let available: Bool
    let windows: [QuotaWindow]

    static let empty = QuotaSnapshot(fetchedAt: nil, expired: true, available: false, windows: [])

    func window(_ key: String) -> QuotaWindow? {
        windows.first { $0.key == key }
    }
}

extension QuotaSnapshot {
    /// bridge 缓存原始字节归一化为快照；任何异常输入都返回可用结果，绝不抛出。
    /// 注意：缓存内 percent 恒 0（上游 bug），必须自算，不能采信。
    static func normalize(_ data: Data?, now: Date = Date()) -> QuotaSnapshot {
        guard let data, !data.isEmpty,
              let file = try? JSONDecoder().decode(CacheFile.self, from: data),
              let rawQuota = file.quota, !rawQuota.isEmpty
        else { return .empty }

        let fetchedAt = file.at.map { Date(timeIntervalSince1970: $0 / 1000) }
        let expired = fetchedAt.map { now.timeIntervalSince($0) > 600 } ?? true

        let windows = ["5h", "weekly", "monthly"].compactMap { key -> QuotaWindow? in
            guard let w = rawQuota[key],
                  let used = w.used, used.isFinite,
                  let limit = w.limit, limit.isFinite
            else { return nil }
            let percent = limit <= 0 ? 0 : min(100, max(0, used / limit * 100))
            let resetAt = w.resetInSec.map { now.addingTimeInterval($0) }
            return QuotaWindow(key: key, used: used, limit: limit, percent: percent, resetAt: resetAt)
        }
        return QuotaSnapshot(fetchedAt: fetchedAt, expired: expired, available: true, windows: windows)
    }

    private struct CacheFile: Decodable {
        let at: Double?
        let quota: [String: RawWindow]?
    }
    private struct RawWindow: Decodable {
        let used: Double?
        let limit: Double?
        let resetInSec: Double?
    }
}
