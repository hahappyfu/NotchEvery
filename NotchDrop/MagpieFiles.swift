//
//  MagpieFiles.swift
//  NotchEvery
//
//  ~/.config/magpie 白名单小 JSON 解析器：解码失败返回 nil（调用方保留旧值），
//  空对象/空数组返回空值。
//

import Foundation

enum MagpieFiles {
    // MARK: - quotas.json

    static func parseQuotas(_ data: Data) -> [MagpieQuotaFileEntry]? {
        if data.isEmpty { return [] }
        guard let raw = try? JSONDecoder().decode([String: QuotaEnvelope].self, from: data) else { return nil }
        return raw.map { key, value -> MagpieQuotaFileEntry in
            let provider = nonEmpty(value.quota?.provider)
                ?? key.split(separator: "/", maxSplits: 1).first.map(String.init)
                ?? ""
            let prefix = provider + "/"
            let account = key.hasPrefix(prefix) ? String(key.dropFirst(prefix.count)) : key
            let windows = (value.quota?.windows ?? []).enumerated().map { index, window in
                MagpieQuotaWindow(
                    name: window.name ?? "",
                    usedPercent: window.used,
                    amount: window.amount,
                    limit: window.limit,
                    unit: window.unit,
                    display: window.display,
                    resetsAt: window.resetsAt.flatMap(MagpieDate.parse),
                    runsOutAt: window.runsOutAt.flatMap(MagpieDate.parse),
                    isAside: value.spans.flatMap { index < $0.count ? $0[index].aside : nil } ?? false
                )
            }
            return MagpieQuotaFileEntry(
                accountKey: key,
                provider: provider,
                account: account,
                name: value.quota?.name,
                icon: value.quota?.icon,
                plan: value.quota?.plan,
                user: value.quota?.user,
                at: value.at.flatMap(MagpieDate.parse),
                windows: windows
            )
        }
        .sorted { $0.accountKey < $1.accountKey }
    }

    // MARK: - limit-notices.json

    static func parseLimitNotices(_ data: Data) -> [String: MagpieLimitNotice]? {
        if data.isEmpty { return [:] }
        guard let raw = try? JSONDecoder().decode([String: NoticeEnvelope].self, from: data) else { return nil }
        var notices: [String: MagpieLimitNotice] = [:]
        for (key, value) in raw {
            let parts = key.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false)
            notices[key] = MagpieLimitNotice(
                key: value.key,
                provider: parts.first.map(String.init) ?? key,
                account: parts.count > 1 ? String(parts[1]) : "",
                why: value.why,
                status: value.status,
                error: value.error,
                at: value.at.flatMap(MagpieDate.parse),
                until: value.until.flatMap(MagpieDate.parse)
            )
        }
        return notices
    }

    // MARK: - plugin-checkin.json

    static func parseCheckins(_ data: Data) -> [MagpieCheckinFileEntry]? {
        if data.isEmpty { return [] }
        guard let raw = try? JSONDecoder().decode([String: CheckinEnvelope].self, from: data) else { return nil }
        return raw.map { key, value in
            let parts = key.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
            return MagpieCheckinFileEntry(
                provider: parts.first.map(String.init) ?? key,
                slot: parts.count > 1 ? String(parts[1]) : "",
                day: value.day,
                at: value.at.flatMap(MagpieDate.parse),
                outcome: value.outcome,
                credit: value.credit,
                msg: value.msg
            )
        }
        .sorted { ($0.provider, $0.slot) < ($1.provider, $1.slot) }
    }

    // MARK: - providers.json / plugin-providers.json / plugin-icons.json

    static func parseProviders(_ data: Data) -> MagpieProviderCatalog.ProviderPart? {
        if data.isEmpty { return .init(entries: [:], groupNameByProviderRef: [:]) }
        guard let raw = try? JSONDecoder().decode(ProvidersEnvelope.self, from: data) else { return nil }
        var entries: [String: MagpieProviderCatalog.Entry] = [:]
        for provider in raw.providers ?? [] {
            guard let id = nonEmpty(provider.id) else { continue }
            entries[id] = MagpieProviderCatalog.Entry(
                id: id,
                name: provider.name ?? "",
                icon: provider.icon,
                hidden: provider.hidden ?? false,
                disabled: provider.disabled ?? false,
                signedIn: true
            )
        }
        var groups: [String: String] = [:]
        for group in raw.groups ?? [] where group.hidden != true {
            guard let id = nonEmpty(group.id), let name = nonEmpty(group.name) else { continue }
            groups["group/\(id)"] = name
            groups[id] = name
        }
        return MagpieProviderCatalog.ProviderPart(entries: entries, groupNameByProviderRef: groups)
    }

    static func parsePluginProviders(_ data: Data) -> [MagpieProviderCatalog.PluginPart]? {
        if data.isEmpty { return [] }
        guard let raw = try? JSONDecoder().decode([PluginProviderEnvelope].self, from: data) else { return nil }
        return raw.compactMap { plugin in
            guard let id = nonEmpty(plugin.id) else { return nil }
            return MagpieProviderCatalog.PluginPart(
                id: id,
                name: plugin.name ?? "",
                icon: plugin.icon,
                signedIn: plugin.signedIn ?? false
            )
        }
    }

    static func parsePluginIcons(_ data: Data) -> [String: String]? {
        if data.isEmpty { return [:] }
        return try? JSONDecoder().decode([String: String].self, from: data)
    }

    // MARK: - quota-history.json

    static func parseQuotaHistory(_ data: Data) -> [String: [String: [MagpieQuotaPoint]]]? {
        if data.isEmpty { return [:] }
        guard let raw = try? JSONDecoder().decode([String: [String: [QuotaPointEnvelope]]].self, from: data) else { return nil }
        return raw.mapValues { windows in
            windows.mapValues { points in
                points.map { MagpieQuotaPoint(at: $0.at.flatMap(MagpieDate.parse), left: $0.left) }
            }
        }
    }

    // MARK: - gateway.json

    static func parseGateway(_ data: Data) -> MagpieGatewayFile? {
        guard let raw = try? JSONDecoder().decode(GatewayEnvelope.self, from: data) else { return nil }
        return MagpieGatewayFile(
            addr: raw.addr,
            pid: raw.pid,
            version: raw.version,
            started: raw.started.flatMap(MagpieDate.parse)
        )
    }

    // MARK: - routing/YYYY-MM-DD.jsonl

    static func parseRouteIndex(lines: [Data]) -> MagpieRouteIndex {
        var index = MagpieRouteIndex()
        var routeOrder: [Int64] = []
        for line in lines {
            guard let entry = try? JSONDecoder().decode(RoutingLine.self, from: line) else { continue }
            if let id = entry.id, let name = nonEmpty(entry.group?.name) {
                if let position = routeOrder.firstIndex(of: id) {
                    routeOrder.remove(at: position)
                }
                routeOrder.append(id)
                index.groupNameByRouteID[id] = name
                while routeOrder.count > 200 {
                    index.groupNameByRouteID[routeOrder.removeFirst()] = nil
                }
            }
            if let name = nonEmpty(entry.group?.name) {
                if let ref = nonEmpty(entry.group?.ref) {
                    index.groupNameByRef[ref] = name
                    index.groupNameByRef["group/\(ref)"] = name
                }
                if let groupID = nonEmpty(entry.group?.id) {
                    index.groupNameByRef[groupID] = name
                    index.groupNameByRef["group/\(groupID)"] = name
                }
            }
            for order in entry.order ?? [] {
                guard let provider = nonEmpty(order.provider) else { continue }
                index.orderSnapshotsByProvider[provider] = MagpieProviderOrderSnapshot(
                    provider: provider,
                    name: order.name,
                    icon: order.icon,
                    who: order.who,
                    plan: order.plan,
                    unit: order.unit,
                    used: order.used,
                    amount: order.amount,
                    limit: order.limit
                )
            }
        }
        return index
    }

    // MARK: - masking/YYYY-MM-DD.jsonl

    static func decodeMaskingLine(_ data: Data) -> MagpieMaskingEntry? {
        guard let raw = try? JSONDecoder().decode(MaskingLine.self, from: data), let route = raw.route else { return nil }
        return MagpieMaskingEntry(route: route, n: raw.n ?? 0, time: raw.t.flatMap(MagpieDate.parse))
    }

    // MARK: - Helpers

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    // MARK: - JSON envelopes

    private struct QuotaEnvelope: Decodable {
        struct Quota: Decodable {
            struct Window: Decodable {
                let name: String?
                let used: Double?
                let amount: Double?
                let limit: Double?
                let unit: String?
                let display: String?
                let resetsAt: String?
                let runsOutAt: String?
            }

            let provider: String?
            let name: String?
            let icon: String?
            let plan: String?
            let user: String?
            let windows: [Window]?
        }

        struct Span: Decodable {
            let aside: Bool?
        }

        let at: String?
        let quota: Quota?
        let spans: [Span]?
    }

    private struct NoticeEnvelope: Decodable {
        let key: String?
        let why: String?
        let status: Int?
        let error: String?
        let at: String?
        let until: String?
    }

    private struct CheckinEnvelope: Decodable {
        let day: String?
        let at: String?
        let outcome: String?
        let credit: Double?
        let msg: String?
    }

    private struct ProvidersEnvelope: Decodable {
        struct Provider: Decodable {
            let id: String?
            let name: String?
            let icon: String?
            let disabled: Bool?
            let hidden: Bool?
        }

        struct Group: Decodable {
            let id: String?
            let name: String?
            let hidden: Bool?
        }

        let providers: [Provider]?
        let groups: [Group]?
    }

    private struct PluginProviderEnvelope: Decodable {
        let id: String?
        let name: String?
        let icon: String?
        let signedIn: Bool?
    }

    private struct QuotaPointEnvelope: Decodable {
        let at: String?
        let left: Double?
    }

    private struct GatewayEnvelope: Decodable {
        let addr: String?
        let pid: Int32?
        let version: String?
        let started: String?
    }

    private struct RoutingLine: Decodable {
        struct Group: Decodable {
            let id: String?
            let ref: String?
            let name: String?
        }

        struct Order: Decodable {
            let provider: String?
            let name: String?
            let icon: String?
            let who: String?
            let plan: String?
            let unit: String?
            let used: Double?
            let amount: Double?
            let limit: Double?
        }

        let id: Int64?
        let group: Group?
        let order: [Order]?
    }

    private struct MaskingLine: Decodable {
        let route: Int64?
        let n: Int?
        let t: String?
    }
}
