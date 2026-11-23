//
//  MagpieAggregator.swift
//  NotchEvery
//
//  纯函数聚合：今日口径 / 三维分布 / 供应商额度组 / 告警 / 签到 / 网关。
//

import Foundation

enum MagpieAggregator {
    static func buildSnapshot(
        usage: [MagpieUsageRecord],
        routes: MagpieRouteIndex,
        masking: [MagpieMaskingEntry],
        quotas: [MagpieQuotaFileEntry],
        notices: [String: MagpieLimitNotice],
        checkins: [MagpieCheckinFileEntry],
        catalog: MagpieProviderCatalog,
        gateway: MagpieGatewayFile?,
        quotaHistory: [String: [String: [MagpieQuotaPoint]]],
        hasMagpieDirectory: Bool,
        now: Date,
        calendar: Calendar = .current,
        pidAlive: (Int32) -> Bool = { kill($0, 0) == 0 || errno != ESRCH }
    ) -> MagpieSnapshot {
        let today = usage.filter { calendar.isDate($0.time, inSameDayAs: now) }
        let inputTokens = today.reduce(0) { $0 + $1.inputTokens }
        let cacheRead = today.reduce(0) { $0 + $1.cacheRead }
        let cacheDenominator = inputTokens + cacheRead
        let durations = today.compactMap(\.durationMs)
        let names = displayNames(catalog: catalog, quotas: quotas, routes: routes)
        let maskedByRoute = masking.reduce(into: [Int64: Int]()) { $0[$1.route, default: 0] += $1.n }
        let eligible = today.filter(countsForDistribution)

        var distributions: [DistributionDimension: [DistributionItem]] = [:]
        distributions[.combo] = comboItems(eligible, names: names)
        distributions[.provider] = providerItems(eligible, names: names)
        distributions[.group] = groupItems(eligible, routes: routes, catalog: catalog, names: names)

        let groups = providerGroups(
            quotas: quotas,
            notices: notices,
            catalog: catalog,
            routes: routes,
            quotaHistory: quotaHistory,
            now: now,
            names: names
        )

        let recentFlows = today
            .sorted { $0.time != $1.time ? $0.time > $1.time : $0.id < $1.id }
            .prefix(5)
            .map { record in
                MagpieFlowRow(
                    id: record.id,
                    agent: record.agent,
                    provider: names[record.provider] ?? record.provider,
                    account: record.providerAccount,
                    model: record.served ?? record.model,
                    requestedModel: record.model,
                    groupName: groupName(for: record, routes: routes, catalog: catalog),
                    inputTokens: record.inputTokens,
                    outputTokens: record.outputTokens,
                    cacheRead: record.cacheRead,
                    durationMs: record.durationMs,
                    ttftMs: record.ttftMs,
                    maskingMs: record.maskingMs,
                    status: record.status,
                    handedOn: record.handedOn,
                    maskedCount: record.routeID.map { maskedByRoute[$0] ?? 0 } ?? 0,
                    time: record.time
                )
            }

        return MagpieSnapshot(
            hasMagpieDirectory: hasMagpieDirectory,
            todayNetTokens: today.reduce(0) { $0 + $1.inputTokens + $1.outputTokens },
            todayCacheRead: cacheRead,
            todayCacheRate: cacheDenominator > 0 ? Double(cacheRead) / Double(cacheDenominator) : nil,
            todayRequestCount: today.count,
            todayErrorCount: today.filter(isUpstreamError).count,
            todayAverageMs: durations.isEmpty ? nil : Double(durations.reduce(0, +)) / Double(durations.count),
            lastRequestAt: today.map(\.time).max(),
            recentFlows: recentFlows,
            distributions: distributions,
            activeAlertCount: notices.values.filter { notice in
                guard let until = notice.until else { return true }
                return until > now
            }.count,
            todayMaskedValues: masking.reduce(0) { $0 + $1.n },
            todayMaskedRequests: Set(masking.filter { $0.n > 0 }.map(\.route)).count,
            providerGroups: groups,
            checkin: checkinSummary(checkins: checkins, groups: groups, now: now, calendar: calendar),
            gateway: gatewayState(gateway, pidAlive: pidAlive),
            refreshedAt: now
        )
    }

    // MARK: - 今日口径

    private static func countsForDistribution(_ record: MagpieUsageRecord) -> Bool {
        record.status == 200 || record.inputTokens + record.outputTokens + record.cacheRead > 0
    }

    private static func isUpstreamError(_ record: MagpieUsageRecord) -> Bool {
        if record.handedOn { return false }
        guard let status = record.status else { return true }
        return status >= 400 && status != 499
    }

    // MARK: - 名称解析

    private static func displayNames(
        catalog: MagpieProviderCatalog,
        quotas: [MagpieQuotaFileEntry],
        routes: MagpieRouteIndex
    ) -> [String: String] {
        var names: [String: String] = [:]
        for (id, entry) in catalog.entries where !entry.name.isEmpty {
            names[id] = entry.name
        }
        for quota in quotas where names[quota.provider] == nil {
            if let name = quota.name, !name.isEmpty { names[quota.provider] = name }
        }
        for (provider, snapshot) in routes.orderSnapshotsByProvider where names[provider] == nil {
            if let name = snapshot.name, !name.isEmpty { names[provider] = name }
        }
        return names
    }

    private static func groupName(
        for record: MagpieUsageRecord,
        routes: MagpieRouteIndex,
        catalog: MagpieProviderCatalog
    ) -> String? {
        if let routeID = record.routeID, let name = routes.groupNameByRouteID[routeID], !name.isEmpty {
            return name
        }
        guard !record.req.isEmpty else { return nil }
        if let name = routes.groupNameByRef[record.req], !name.isEmpty { return name }
        if let name = catalog.groupNameByProviderRef[record.req], !name.isEmpty { return name }
        return nil
    }

    // MARK: - 三维分布

    private struct RawItem {
        let id: String
        let label: String
        let secondaryLabel: String?
        let detail: String?
        let tokens: Int
        let cache: Int
        let calls: Int
        let copyText: String
    }

    private static func finish(_ raw: [RawItem]) -> [DistributionItem] {
        let total = raw.reduce(0) { $0 + $1.tokens }
        return raw.map { item in
            DistributionItem(
                id: item.id,
                label: item.label,
                secondaryLabel: item.secondaryLabel,
                detail: item.detail,
                tokenCount: item.tokens,
                cacheRead: item.cache,
                calls: item.calls,
                shareFraction: total > 0 ? Double(item.tokens) / Double(total) : 0,
                copyText: item.copyText
            )
        }
        .sorted { $0.tokenCount != $1.tokenCount ? $0.tokenCount > $1.tokenCount : $0.label < $1.label }
    }

    private static func comboItems(_ records: [MagpieUsageRecord], names: [String: String]) -> [DistributionItem] {
        struct Bucket {
            var tokens = 0
            var cache = 0
            var calls = 0
        }
        var buckets: [String: Bucket] = [:]
        var models: [String: String] = [:]
        var providers: [String: String] = [:]
        for record in records {
            let model = record.served ?? record.model
            let key = record.provider + "\u{1}" + model
            buckets[key, default: Bucket()].tokens += record.inputTokens + record.outputTokens
            buckets[key, default: Bucket()].cache += record.cacheRead
            buckets[key, default: Bucket()].calls += 1
            models[key] = model
            providers[key] = record.provider
        }
        return finish(buckets.map { key, bucket in
            let provider = providers[key] ?? ""
            let model = models[key] ?? ""
            return RawItem(
                id: "combo|\(key)",
                label: model,
                secondaryLabel: names[provider] ?? provider,
                detail: nil,
                tokens: bucket.tokens,
                cache: bucket.cache,
                calls: bucket.calls,
                copyText: "\(provider)/\(model)"
            )
        })
    }

    private static func providerItems(_ records: [MagpieUsageRecord], names: [String: String]) -> [DistributionItem] {
        struct Bucket {
            var tokens = 0
            var cache = 0
            var calls = 0
            var accounts: Set<String> = []
            var models: Set<String> = []
        }
        var buckets: [String: Bucket] = [:]
        for record in records {
            buckets[record.provider, default: Bucket()].tokens += record.inputTokens + record.outputTokens
            buckets[record.provider, default: Bucket()].cache += record.cacheRead
            buckets[record.provider, default: Bucket()].calls += 1
            if !record.providerAccount.isEmpty {
                buckets[record.provider, default: Bucket()].accounts.insert(record.providerAccount)
            }
            let model = record.served ?? record.model
            if !model.isEmpty {
                buckets[record.provider, default: Bucket()].models.insert(model)
            }
        }
        return finish(buckets.map { provider, bucket in
            RawItem(
                id: "provider|\(provider)",
                label: names[provider] ?? provider,
                secondaryLabel: nil,
                detail: "\(bucket.accounts.count) 账号 · \(bucket.models.count) 模型",
                tokens: bucket.tokens,
                cache: bucket.cache,
                calls: bucket.calls,
                copyText: provider
            )
        })
    }

    private static func groupItems(
        _ records: [MagpieUsageRecord],
        routes: MagpieRouteIndex,
        catalog: MagpieProviderCatalog,
        names: [String: String]
    ) -> [DistributionItem] {
        struct Bucket {
            let label: String
            let isDirect: Bool
            var tokens = 0
            var cache = 0
            var calls = 0
            var providerTokens: [String: Int] = [:]
            var topTokens = -1
            var topModel = ""
            var req = ""
        }
        var buckets: [String: Bucket] = [:]
        for record in records {
            let identity = groupIdentity(record, routes: routes, catalog: catalog)
            var bucket = buckets[identity.key] ?? Bucket(label: identity.label, isDirect: identity.isDirect)
            let tokens = record.inputTokens + record.outputTokens
            bucket.tokens += tokens
            bucket.cache += record.cacheRead
            bucket.calls += 1
            bucket.providerTokens[record.provider, default: 0] += tokens
            if tokens > bucket.topTokens {
                bucket.topTokens = tokens
                bucket.topModel = record.served ?? record.model
                bucket.req = record.req
            }
            buckets[identity.key] = bucket
        }
        return finish(buckets.map { key, bucket in
            let topProvider = bucket.providerTokens.max { left, right in
                left.value != right.value ? left.value < right.value : left.key > right.key
            }?.key
            let secondary: String?
            if bucket.isDirect {
                secondary = bucket.topModel
            } else {
                secondary = topProvider.map { names[$0] ?? $0 }
            }
            let copy = bucket.req.isEmpty
                ? (bucket.isDirect ? bucket.topModel : bucket.label)
                : bucket.req
            return RawItem(
                id: key,
                label: bucket.label,
                secondaryLabel: secondary,
                detail: nil,
                tokens: bucket.tokens,
                cache: bucket.cache,
                calls: bucket.calls,
                copyText: copy
            )
        })
    }

    private static func groupIdentity(
        _ record: MagpieUsageRecord,
        routes: MagpieRouteIndex,
        catalog: MagpieProviderCatalog
    ) -> (key: String, label: String, isDirect: Bool) {
        if let name = groupName(for: record, routes: routes, catalog: catalog) {
            return ("group|" + name, name, false)
        }
        if record.req.hasPrefix("group/") {
            let ref = String(record.req.dropFirst("group/".count))
            let label = ref.isEmpty ? record.req : ref
            return ("group|" + label, label, false)
        }
        let directKey = record.req.isEmpty ? record.model : record.req
        return ("direct|" + directKey, "直连调用", true)
    }

    // MARK: - 供应商额度组

    private static func providerGroups(
        quotas: [MagpieQuotaFileEntry],
        notices: [String: MagpieLimitNotice],
        catalog: MagpieProviderCatalog,
        routes: MagpieRouteIndex,
        quotaHistory: [String: [String: [MagpieQuotaPoint]]],
        now: Date,
        names: [String: String]
    ) -> [MagpieProviderGroup] {
        var accountsByProvider: [String: [MagpieQuotaAccount]] = [:]
        var quotaProviders: Set<String> = []
        for quota in quotas {
            quotaProviders.insert(quota.provider)
            accountsByProvider[quota.provider, default: []].append(
                makeAccount(
                    quota: quota,
                    notice: notice(for: quota.provider, account: quota.account, notices: notices),
                    quotaHistory: quotaHistory,
                    now: now
                )
            )
        }
        for (provider, snapshot) in routes.orderSnapshotsByProvider where !quotaProviders.contains(provider) {
            let account = preferredLabel(user: snapshot.who, account: provider)
            accountsByProvider[provider, default: []].append(
                makeAccount(
                    provider: provider,
                    snapshot: snapshot,
                    accountLabel: account,
                    notice: notice(for: provider, account: account, notices: notices),
                    now: now
                )
            )
        }

        var providerIDs = Set(accountsByProvider.keys)
        for (id, entry) in catalog.entries where !entry.hidden && !entry.disabled && entry.signedIn {
            providerIDs.insert(id)
        }
        let excluded = Set(catalog.entries.values.filter { $0.hidden || $0.disabled }.map(\.id))
        providerIDs.subtract(excluded)

        let groups = providerIDs.map { provider -> MagpieProviderGroup in
            let accounts = (accountsByProvider[provider] ?? []).sorted { $0.id < $1.id }
            let limited = accounts.filter { ($0.limit ?? 0) > 0 }
            let totalLimit: Double? = limited.isEmpty ? nil : limited.reduce(0) { $0 + ($1.limit ?? 0) }
            let totalRemaining: Double? = limited.isEmpty ? nil :
                limited.allSatisfy { $0.remaining != nil }
                    ? limited.reduce(0) { $0 + ($1.remaining ?? 0) }
                    : nil
            let fraction: Double? = {
                guard let totalLimit, totalLimit > 0, let totalRemaining else { return nil }
                return totalRemaining / totalLimit
            }()
            let quotaIcon = quotas.first(where: { $0.provider == provider })?.icon
            let orderIcon = routes.orderSnapshotsByProvider[provider]?.icon
            return MagpieProviderGroup(
                id: provider,
                name: names[provider] ?? provider,
                icon: firstNonEmpty(catalog.entries[provider]?.icon, quotaIcon, orderIcon),
                accounts: accounts,
                limitState: accounts.map(\.limitState).max { $0.severity < $1.severity } ?? .none,
                totalRemaining: totalRemaining,
                totalLimit: totalLimit,
                fraction: fraction,
                availableAccounts: accounts.filter { ($0.remaining ?? 0) > 0 }.count,
                exhaustedAccounts: accounts.filter { ($0.limit ?? 0) > 0 && ($0.remaining ?? 1) <= 0 }.count,
                pendingCheckin: accounts.contains { account in
                    account.windows.contains { window in
                        window.name.contains("今日未签") || (window.display?.contains("今日未签") ?? false)
                    }
                }
            )
        }
        return groups.sorted { left, right in
            let leftWeight = sortWeight(left)
            let rightWeight = sortWeight(right)
            return leftWeight != rightWeight ? leftWeight < rightWeight : left.name < right.name
        }
    }

    private static func makeAccount(
        quota: MagpieQuotaFileEntry,
        notice: MagpieLimitNotice?,
        quotaHistory: [String: [String: [MagpieQuotaPoint]]],
        now: Date
    ) -> MagpieQuotaAccount {
        let history = quotaHistory["\(quota.provider)|\(quota.account)"]
        let windows = quota.windows.enumerated().map { index, window in
            MagpieWindow(
                id: "\(quota.accountKey)#\(index)",
                name: window.name,
                usedPercent: window.usedPercent,
                amount: window.amount,
                limit: window.limit,
                unit: window.unit,
                display: window.display,
                resetsAt: window.resetsAt,
                runsOutAt: window.runsOutAt,
                isAside: window.isAside,
                history: historyValues(history?[window.name])
            )
        }
        let main = windows.first(where: { !$0.isAside }) ?? windows.first
        let amounts = remainingAmounts(limit: main?.limit, usedPercent: main?.usedPercent, amount: main?.amount)
        return MagpieQuotaAccount(
            id: quota.accountKey,
            provider: quota.provider,
            label: preferredLabel(user: quota.user, account: quota.account),
            plan: quota.plan,
            windows: windows,
            limitState: ProviderLimitState.resolve(notice, now: now),
            noticeMessage: activeNoticeMessage(notice, now: now),
            remaining: amounts.remaining,
            limit: amounts.limit,
            remainingFraction: amounts.fraction
        )
    }

    private static func makeAccount(
        provider: String,
        snapshot: MagpieProviderOrderSnapshot,
        accountLabel: String,
        notice: MagpieLimitNotice?,
        now: Date
    ) -> MagpieQuotaAccount {
        let amounts = remainingAmounts(limit: snapshot.limit, usedPercent: snapshot.used, amount: snapshot.amount)
        return MagpieQuotaAccount(
            id: "\(provider)|\(accountLabel)",
            provider: provider,
            label: accountLabel,
            plan: snapshot.plan,
            windows: [],
            limitState: ProviderLimitState.resolve(notice, now: now),
            noticeMessage: activeNoticeMessage(notice, now: now),
            remaining: amounts.remaining,
            limit: amounts.limit,
            remainingFraction: amounts.fraction
        )
    }

    private static func remainingAmounts(
        limit: Double?,
        usedPercent: Double?,
        amount: Double?
    ) -> (remaining: Double?, limit: Double?, fraction: Double?) {
        guard let limit else {
            guard let usedPercent else { return (nil, nil, nil) }
            return (nil, nil, max(0, 1 - usedPercent / 100))
        }
        guard limit > 0 else {
            guard let usedPercent else { return (0, limit, nil) }
            return (0, limit, max(0, 1 - usedPercent / 100))
        }
        let usedAmount: Double?
        if let amount {
            usedAmount = amount
        } else if let usedPercent {
            usedAmount = limit * usedPercent / 100
        } else {
            usedAmount = nil
        }
        guard let usedAmount else { return (nil, limit, nil) }
        let remaining = max(0, limit - usedAmount)
        return (remaining, limit, max(0, remaining / limit))
    }

    private static func sortWeight(_ group: MagpieProviderGroup) -> Int {
        guard group.totalLimit != nil else { return 3 }
        let hasRemaining = group.availableAccounts > 0 && (group.totalRemaining ?? 0) > 0
        guard hasRemaining else { return 2 }
        return group.limitState.isActive ? 1 : 0
    }

    private static func notice(
        for provider: String,
        account: String,
        notices: [String: MagpieLimitNotice]
    ) -> MagpieLimitNotice? {
        if let exact = notices["\(provider)@\(account)"] { return exact }
        return notices.values.first { $0.provider == provider && $0.account == account }
    }

    private static func activeNoticeMessage(_ notice: MagpieLimitNotice?, now: Date) -> String? {
        guard let notice else { return nil }
        guard notice.until == nil || notice.until! > now else { return nil }
        if let error = notice.error, !error.isEmpty { return error }
        return notice.why
    }

    private static func historyValues(_ points: [MagpieQuotaPoint]?) -> [Double] {
        Array((points ?? []).compactMap(\.left).suffix(20))
    }

    // MARK: - 签到与网关

    private static func checkinSummary(
        checkins: [MagpieCheckinFileEntry],
        groups: [MagpieProviderGroup],
        now: Date,
        calendar: Calendar
    ) -> MagpieCheckinSummary {
        let day = MagpiePaths.dayString(for: now, calendar: calendar)
        let claimed = checkins.filter {
            $0.day == day && ($0.outcome == "claimed" || $0.outcome == "done")
        }
        let providers = Set(claimed.map(\.provider))
        return MagpieCheckinSummary(
            claimedProviders: providers.count,
            totalCredit: claimed.reduce(0) { $0 + ($1.credit ?? 0) },
            pendingProviders: groups.filter(\.pendingCheckin).count,
            details: providers.sorted()
        )
    }

    private static func gatewayState(
        _ gateway: MagpieGatewayFile?,
        pidAlive: (Int32) -> Bool
    ) -> MagpieGatewayState {
        guard let gateway, let pid = gateway.pid, pidAlive(pid) else { return .offline }
        return .online(version: gateway.version)
    }

    // MARK: - Helpers

    private static func preferredLabel(user: String?, account: String) -> String {
        if let user, !user.isEmpty { return user }
        return account
    }

    private static func firstNonEmpty(_ values: String?...) -> String? {
        values.compactMap { $0 }.first { !$0.isEmpty }
    }
}
