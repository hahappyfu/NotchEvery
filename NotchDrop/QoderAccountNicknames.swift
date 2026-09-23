//
//  QoderAccountNicknames.swift
//  NotchEvery
//
//  账号池昵称：给每个 Qoder 号分配一个三国人物名，替代难以记忆的脱敏尾号（a4a9 / a201 …）。
//  分配结果按 userId 持久化，同一个号的名字终生不变；名单用尽则回落到调用方给的尾号。
//

import Foundation

/// 三国人物名单。**全部取 2 字**：Orb 直径仅 48pt、字号 11，3 字会被挤扁。
/// 顺序即分配优先级。往名单里追加名字只影响此后新加入的账号——
/// 已分配的名字早已落盘，不会因为改名单而重新洗牌。
enum QoderNicknameRoster {
    static let names: [String] = [
        "刘备", "关羽", "张飞", "赵云", "马超", "黄忠",
        "曹操", "张辽", "许褚", "典韦",
        "孙权", "周瑜", "吕蒙", "陆逊",
        "吕布", "貂蝉", "袁绍", "庞统", "华佗", "董卓",
    ]
}

/// 账号 → 昵称的持久化分配表。
@MainActor
final class QoderAccountNicknames {
    static let shared = QoderAccountNicknames()

    private static let storageKey = "QoderAccountNicknames"

    private let defaults: UserDefaults

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? .standard
    }

    /// 取该账号的昵称。首次见到某个 userId 时，从名单里挑一个尚未被占用的名字并落盘；
    /// 之后每次都返回同一个名字（即使账号池顺序变化、App 重启也不变）。
    /// 名单用尽（账号数超过名单长度）时返回 `fallback`——不重名，也不崩溃。
    func name(for userId: String, fallback: String) -> String {
        guard !userId.isEmpty else { return fallback }

        var assignments = storedAssignments()
        if let existing = assignments[userId] { return existing }

        let taken = Set(assignments.values)
        guard let pick = QoderNicknameRoster.names.first(where: { !taken.contains($0) }) else {
            return fallback
        }
        assignments[userId] = pick
        defaults.set(assignments, forKey: Self.storageKey)
        return pick
    }

    private func storedAssignments() -> [String: String] {
        defaults.dictionary(forKey: Self.storageKey) as? [String: String] ?? [:]
    }
}
