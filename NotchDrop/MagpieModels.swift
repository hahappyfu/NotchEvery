//
//  MagpieModels.swift
//  NotchEvery
//
//  Magpie 文件解码与聚合的模型类型。
//

import Foundation

/// usage.jsonl 单行解码后的用量记录（已过滤内部探活行）。
public struct MagpieUsageRecord: Equatable {
    public let id: String            // rid ?? "<route_id>-<byteOffset>"
    public let routeID: Int64?
    public let time: Date
    public let agent: String
    public let provider: String
    public let providerAccount: String
    public let model: String
    public let served: String?
    public let req: String
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheRead: Int
    public let cacheWrite: Int
    public let reasoning: Int
    public let durationMs: Int?
    public let ttftMs: Int?
    public let flowMs: Int?
    public let maskingMs: Int?
    public let tries: Int
    public let status: Int?
    public let handedOn: Bool

    public init(
        id: String,
        routeID: Int64?,
        time: Date,
        agent: String,
        provider: String,
        providerAccount: String,
        model: String,
        served: String?,
        req: String,
        inputTokens: Int,
        outputTokens: Int,
        cacheRead: Int,
        cacheWrite: Int,
        reasoning: Int,
        durationMs: Int?,
        ttftMs: Int?,
        maskingMs: Int?,
        status: Int?,
        handedOn: Bool,
        flowMs: Int? = nil,
        tries: Int = 1
    ) {
        self.id = id
        self.routeID = routeID
        self.time = time
        self.agent = agent
        self.provider = provider
        self.providerAccount = providerAccount
        self.model = model
        self.served = served
        self.req = req
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheRead = cacheRead
        self.cacheWrite = cacheWrite
        self.reasoning = reasoning
        self.durationMs = durationMs
        self.ttftMs = ttftMs
        self.flowMs = flowMs
        self.maskingMs = maskingMs
        self.tries = tries
        self.status = status
        self.handedOn = handedOn
    }
}

// MARK: - 小 JSON 文件原始条目

struct MagpieQuotaWindow: Equatable {
    let name: String
    let usedPercent: Double?
    let amount: Double?
    let limit: Double?
    let unit: String?
    let display: String?
    let resetsAt: Date?
    let runsOutAt: Date?
    let isAside: Bool

    init(
        name: String,
        usedPercent: Double? = nil,
        amount: Double? = nil,
        limit: Double? = nil,
        unit: String? = nil,
        display: String? = nil,
        resetsAt: Date? = nil,
        runsOutAt: Date? = nil,
        isAside: Bool = false
    ) {
        self.name = name
        self.usedPercent = usedPercent
        self.amount = amount
        self.limit = limit
        self.unit = unit
        self.display = display
        self.resetsAt = resetsAt
        self.runsOutAt = runsOutAt
        self.isAside = isAside
    }
}

struct MagpieQuotaFileEntry: Equatable {
    let accountKey: String   // "<provider>/<account>"
    let provider: String
    let account: String
    let name: String?
    let icon: String?
    let plan: String?
    let user: String?
    let at: Date?
    let windows: [MagpieQuotaWindow]

    init(
        accountKey: String,
        provider: String,
        account: String,
        name: String? = nil,
        icon: String? = nil,
        plan: String? = nil,
        user: String? = nil,
        at: Date? = nil,
        windows: [MagpieQuotaWindow] = []
    ) {
        self.accountKey = accountKey
        self.provider = provider
        self.account = account
        self.name = name
        self.icon = icon
        self.plan = plan
        self.user = user
        self.at = at
        self.windows = windows
    }
}

struct MagpieLimitNotice: Equatable {
    let key: String?
    let provider: String
    let account: String
    let why: String?
    let status: Int?
    let error: String?
    let at: Date?
    let until: Date?

    init(
        key: String? = nil,
        provider: String,
        account: String,
        why: String? = nil,
        status: Int? = nil,
        error: String? = nil,
        at: Date? = nil,
        until: Date? = nil
    ) {
        self.key = key
        self.provider = provider
        self.account = account
        self.why = why
        self.status = status
        self.error = error
        self.at = at
        self.until = until
    }
}

struct MagpieCheckinFileEntry: Equatable {
    let provider: String
    let slot: String
    let day: String?
    let at: Date?
    let outcome: String?
    let credit: Double?
    let msg: String?

    init(
        provider: String,
        slot: String,
        day: String? = nil,
        at: Date? = nil,
        outcome: String? = nil,
        credit: Double? = nil,
        msg: String? = nil
    ) {
        self.provider = provider
        self.slot = slot
        self.day = day
        self.at = at
        self.outcome = outcome
        self.credit = credit
        self.msg = msg
    }
}

struct MagpieQuotaPoint: Equatable {
    let at: Date?
    let left: Double?

    init(at: Date? = nil, left: Double? = nil) {
        self.at = at
        self.left = left
    }
}

struct MagpieGatewayFile: Equatable {
    let addr: String?
    let pid: Int32?
    let version: String?
    let started: Date?

    init(addr: String? = nil, pid: Int32? = nil, version: String? = nil, started: Date? = nil) {
        self.addr = addr
        self.pid = pid
        self.version = version
        self.started = started
    }
}

struct MagpieMaskingEntry: Equatable {
    let route: Int64
    let n: Int
    let time: Date?

    init(route: Int64, n: Int, time: Date? = nil) {
        self.route = route
        self.n = n
        self.time = time
    }
}

// MARK: - routing 索引

struct MagpieProviderOrderSnapshot: Equatable {
    let provider: String?
    let name: String?
    let icon: String?
    let who: String?
    let plan: String?
    let unit: String?
    let used: Double?
    let amount: Double?
    let limit: Double?

    init(
        provider: String? = nil,
        name: String? = nil,
        icon: String? = nil,
        who: String? = nil,
        plan: String? = nil,
        unit: String? = nil,
        used: Double? = nil,
        amount: Double? = nil,
        limit: Double? = nil
    ) {
        self.provider = provider
        self.name = name
        self.icon = icon
        self.who = who
        self.plan = plan
        self.unit = unit
        self.used = used
        self.amount = amount
        self.limit = limit
    }
}

struct MagpieRouteIndex: Equatable {
    var groupNameByRouteID: [Int64: String] = [:]
    var groupNameByRef: [String: String] = [:]
    var orderSnapshotsByAccount: [String: MagpieProviderOrderSnapshot] = [:]
}

// MARK: - 供应商目录

struct MagpieProviderCatalog: Equatable {
    struct Entry: Equatable {
        let id: String
        let name: String
        let icon: String?
        let hidden: Bool
        let disabled: Bool
        let signedIn: Bool
        let accountNames: [String: String]

        init(
            id: String,
            name: String,
            icon: String?,
            hidden: Bool,
            disabled: Bool,
            signedIn: Bool,
            accountNames: [String: String] = [:]
        ) {
            self.id = id
            self.name = name
            self.icon = icon
            self.hidden = hidden
            self.disabled = disabled
            self.signedIn = signedIn
            self.accountNames = accountNames
        }
    }

    struct ProviderPart: Equatable {
        let entries: [String: Entry]
        let groupNameByProviderRef: [String: String]
    }

    struct PluginPart: Equatable {
        let id: String
        let name: String
        let icon: String?
        let signedIn: Bool
    }

    var entries: [String: Entry] = [:]
    var groupNameByProviderRef: [String: String] = [:]

    /// providers.json 名称（非空）优先，plugin-providers 名称补空。
    static func merged(providers: ProviderPart?, plugins: [PluginPart]?) -> MagpieProviderCatalog {
        var catalog = MagpieProviderCatalog()
        if let providers {
            catalog.entries = providers.entries
            catalog.groupNameByProviderRef = providers.groupNameByProviderRef
        }
        for plugin in plugins ?? [] where !plugin.id.isEmpty {
            let base = catalog.entries[plugin.id]
            let providerName = base?.name ?? ""
            let providerIcon = base?.icon ?? ""
            catalog.entries[plugin.id] = Entry(
                id: plugin.id,
                name: providerName.isEmpty ? plugin.name : providerName,
                icon: providerIcon.isEmpty ? plugin.icon : base?.icon,
                hidden: base?.hidden ?? false,
                disabled: base?.disabled ?? false,
                signedIn: (base?.signedIn ?? false) || plugin.signedIn,
                accountNames: base?.accountNames ?? [:]
            )
        }
        return catalog
    }
}

// MARK: - 聚合快照

enum DistributionDimension: String, CaseIterable, Identifiable, Hashable {
    case combo
    case provider
    case group

    var id: String { rawValue }

    var title: String {
        switch self {
        case .combo: return "模型·提供商"
        case .provider: return "提供商"
        case .group: return "Group"
        }
    }
}

struct DistributionItem: Equatable, Identifiable {
    let id: String
    let label: String
    let secondaryLabel: String?
    let detail: String?
    let tokenCount: Int
    let cacheRead: Int
    let calls: Int
    let shareFraction: Double
    let copyText: String
    let tokensPerSecond: Double?
    let averageTTFTMs: Double?
}

struct MagpieFlowRow: Equatable, Identifiable {
    let id: String
    let agent: String
    let providerID: String
    let providerName: String
    let account: String
    let model: String
    let requestedModel: String
    let groupName: String?
    let inputTokens: Int
    let outputTokens: Int
    let cacheRead: Int
    let durationMs: Int?
    let ttftMs: Int?
    let maskingMs: Int?
    let tokensPerSecond: Double?
    let status: Int?
    let handedOn: Bool
    let maskedCount: Int
    let time: Date

    init(
        id: String,
        agent: String,
        providerID: String,
        providerName: String,
        account: String,
        model: String,
        requestedModel: String,
        groupName: String?,
        inputTokens: Int,
        outputTokens: Int,
        cacheRead: Int,
        durationMs: Int?,
        ttftMs: Int?,
        maskingMs: Int?,
        tokensPerSecond: Double? = nil,
        status: Int?,
        handedOn: Bool,
        maskedCount: Int,
        time: Date
    ) {
        self.id = id
        self.agent = agent
        self.providerID = providerID
        self.providerName = providerName
        self.account = account
        self.model = model
        self.requestedModel = requestedModel
        self.groupName = groupName
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheRead = cacheRead
        self.durationMs = durationMs
        self.ttftMs = ttftMs
        self.maskingMs = maskingMs
        self.tokensPerSecond = tokensPerSecond
        self.status = status
        self.handedOn = handedOn
        self.maskedCount = maskedCount
        self.time = time
    }
}

enum ProviderLimitState: Equatable {
    case none
    case cooling(until: Date)
    case rateLimited
    case riskBlocked

    var isActive: Bool {
        if case .none = self { return false }
        return true
    }

    /// riskBlocked 3 > cooling 2 > rateLimited 1 > none 0
    var severity: Int {
        switch self {
        case .none: return 0
        case .rateLimited: return 1
        case .cooling: return 2
        case .riskBlocked: return 3
        }
    }

    static func resolve(_ notice: MagpieLimitNotice?, now: Date) -> ProviderLimitState {
        guard let notice else { return .none }
        if let until = notice.until, until > now { return .cooling(until: until) }
        if notice.status == 403 || notice.status == 405 { return .riskBlocked }
        if notice.status == 429 || notice.why == "rate" { return .rateLimited }
        return .none
    }
}

struct MagpieWindow: Equatable, Identifiable {
    let id: String
    let name: String
    let usedPercent: Double?
    let amount: Double?
    let limit: Double?
    let unit: String?
    let display: String?
    let resetsAt: Date?
    let runsOutAt: Date?
    let isAside: Bool
    let history: [Double]
}

struct MagpieQuotaAccount: Equatable, Identifiable {
    let id: String
    let provider: String
    let label: String
    let plan: String?
    let windows: [MagpieWindow]
    let limitState: ProviderLimitState
    let noticeMessage: String?
    let remaining: Double?
    let limit: Double?
    let remainingFraction: Double?
}

struct MagpieProviderGroup: Equatable, Identifiable {
    let id: String
    let name: String
    let icon: String?
    let accounts: [MagpieQuotaAccount]
    let limitState: ProviderLimitState
    let totalRemaining: Double?
    let totalLimit: Double?
    let fraction: Double?
    let availableAccounts: Int
    let exhaustedAccounts: Int
    let pendingCheckin: Bool
}

struct MagpieCheckinSummary: Equatable {
    let claimedProviders: Int
    let totalCredit: Double
    let pendingProviders: Int
    let details: [String]

    static let empty = MagpieCheckinSummary(claimedProviders: 0, totalCredit: 0, pendingProviders: 0, details: [])
}

enum MagpieGatewayState: Equatable {
    case online(version: String?)
    case offline
}

struct MagpieHourBucket: Equatable {
    let hour: Int
    let netTokens: Int
    let topProviderID: String?
    let topProviderName: String?
    let topProviderTokens: Int
}

struct MagpieSnapshot: Equatable {
    var hasMagpieDirectory: Bool
    var todayNetTokens: Int
    var todayCacheRead: Int
    var todayCacheRate: Double?
    var todayRequestCount: Int
    var todayErrorCount: Int
    var todayAverageMs: Double?
    var todayRetriedSuccessCount: Int
    var hourlyBuckets: [MagpieHourBucket]
    var lastRequestAt: Date?
    var recentFlows: [MagpieFlowRow]
    var distributions: [DistributionDimension: [DistributionItem]]
    var activeAlertCount: Int
    var todayMaskedValues: Int
    var todayMaskedRequests: Int
    var providerGroups: [MagpieProviderGroup]
    var checkin: MagpieCheckinSummary
    var gateway: MagpieGatewayState
    var refreshedAt: Date

    static let empty = MagpieSnapshot(
        hasMagpieDirectory: false,
        todayNetTokens: 0,
        todayCacheRead: 0,
        todayCacheRate: nil,
        todayRequestCount: 0,
        todayErrorCount: 0,
        todayAverageMs: nil,
        todayRetriedSuccessCount: 0,
        hourlyBuckets: [],
        lastRequestAt: nil,
        recentFlows: [],
        distributions: [.combo: [], .provider: [], .group: []],
        activeAlertCount: 0,
        todayMaskedValues: 0,
        todayMaskedRequests: 0,
        providerGroups: [],
        checkin: .empty,
        gateway: .offline,
        refreshedAt: .distantPast
    )
}
