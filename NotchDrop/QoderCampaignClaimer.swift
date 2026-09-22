//
//  QoderCampaignClaimer.swift
//  NotchEvery
//
//  任务 4：Qoder「每天登录领 100 Credits」活动自动领取。扫描本地账号池凭证文件，
//  逐个走 GET /sash/api/v1/me/campaigns + POST .../claim 两步协议（协议细节已在真实环境验证）。
//  网络经 QoderCampaignTransport 注入（单测用假实现，绝不真联网）；单账号失败只记日志跳过，不影响其它账号。
//  任务 3 增补：每轮结果按天留存（UserDefaults，Key 含日期 → 隔天自然重置），对外只读暴露当日状态，
//  供第三页「今日签到 x/y + 一键签到」与各 Orb tooltip 展示。
//

import Foundation
import os.log

private let claimLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "NotchEvery", category: "QoderCampaign")

// MARK: - Transport

/// 通用 HTTP 传输抽象：支持自定义多 Header + POST body，返回状态码与响应体。
/// 与 QoderHTTPTransport（仅 GET + Bearer）分开定义，避免动到 QoderStore 内部大量调用点。
protocol QoderCampaignTransport {
    func request(url: URL, method: String, headers: [String: String], body: Data?) async throws -> (status: Int, data: Data)
}

/// 默认实现：URLSession，15s 超时（与 URLSessionQoderTransport 对齐，避免单条卡住的请求拖长整轮巡检）。
struct URLSessionQoderCampaignTransport: QoderCampaignTransport {
    func request(url: URL, method: String, headers: [String: String], body: Data?) async throws -> (status: Int, data: Data) {
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = method
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        req.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        return (status, data)
    }
}

// MARK: - 活动 / 结果模型

/// GET /me/campaigns 响应里我们关心的部分（camelCase，权威抓包格式）。
struct QoderCampaignList: Decodable {
    struct Campaign: Decodable {
        let campaignId: String?
        let actionType: String?
        let claimStatus: String?
    }
    let campaigns: [Campaign]?

    /// 过滤出需要领取的条目：actionType == CLAIM_BENEFIT && claimStatus == CLAIMABLE。
    var claimableIds: [String] {
        (campaigns ?? []).compactMap { c in
            guard c.actionType == "CLAIM_BENEFIT", c.claimStatus == "CLAIMABLE", let id = c.campaignId else { return nil }
            return id
        }
    }
}

/// POST .../claim 响应里我们关心的字段。
struct QoderClaimResponse: Decodable {
    let status: String?
    let replayed: Bool?
}

enum QoderClaimOutcome: Equatable, Codable {
    case claimed                      // 本次新领到
    case alreadyClaimed               // replayed==true，今天之前已领过，幂等，不算错误
    case nothingToClaim               // 列表里没有可领项
    case failure(String)              // 带原因的失败（token 失效 / 网络异常 / 解码失败等）
}

/// 一轮 `claimAllWithSummary()` 的整体结果分类，供「一键签到」按钮展示即时反馈用。
/// `claimAll()` 只回传 outcomes 字典、不区分「本轮什么都没做」的两种原因（撞守卫跳过 / 池为空），
/// 也不区分「做了但没新东西可领」——对按钮来说这三种情况视觉上都是「点了没反应」。故单独分类。
enum QoderClaimSweepSummary: Equatable {
    case skippedInFlight              // 撞上后台静默巡检的 in-flight 守卫，本轮直接跳过
    case emptyPool                    // 账号池目录扫不到任何凭证文件
    case completed(newlyClaimed: Int, alreadyClaimed: Int, nothingToClaim: Int, failed: Int)
}

/// `claimAllWithSummary()` 的返回值：结果字典 + 本轮分类摘要。
struct QoderClaimSweep: Equatable {
    let outcomes: [String: QoderClaimOutcome]
    let summary: QoderClaimSweepSummary
}

// MARK: - 并发守卫

/// in-flight 守卫的纯状态转移：`begin` 只有在当前空闲时才占用成功并返回 true（表示"可以开始跑"），
/// 已被占用则返回 false（本次触发应直接跳过）；`end` 无条件释放。
///
/// 抽成无副作用的静态函数，是为了让守卫本身可脱离异步时序单独断言
/// （Swift XCTest 对真实并发交错的测试容易 flaky，这里用等价的状态机验证代替）。
enum QoderCampaignGuard {
    /// 尝试占用守卫。返回 shouldRun=false 表示已有一轮在跑，调用方应直接跳过本次触发。
    static func begin(isRunning: Bool) -> (shouldRun: Bool, isRunning: Bool) {
        if isRunning { return (false, true) }
        return (true, true)
    }
    /// 一轮结束后释放守卫（无条件置回空闲）。
    static func end() -> Bool { false }
}

// MARK: - Claimer

final class QoderCampaignClaimer {
    static let shared = QoderCampaignClaimer()

    private let transport: QoderCampaignTransport
    private let poolDirectory: URL
    /// 当天去重存储（UserDefaults 持久化，App 重启不重复刷；测试可注入独立 suite 隔离）
    private let defaults: UserDefaults
    private let now: () -> Date
    /// 本类不是 actor 隔离的，且 claimAll() 由 Task.detached 在后台线程发起（QoderStore.runCampaignClaim /
    /// AppDelegate 冷启动巡检），
    /// 多个 detached Task 可能真正并行进入这里，故标志位必须加锁访问，不能用裸 Bool（数据竞争）。
    /// 复用仓库既有的 UnfairLock（SignalPipeline.swift）。
    private let stateLock = UnfairLock()
    private var isRunning = false

    // MARK: 每日签到状态（供 UI 展示）
    //
    // 这里刻意不用 `@MainActor @Published`：本类不是 actor 隔离的（见上面 stateLock 的注释），
    // 写入点全在 detached 后台任务的巡检循环里，从非隔离上下文同步写 @MainActor 存储属性是编译错误；
    // 而把整类改成 @MainActor 会连带动到 8 个已有单测和 3 个 detached 调用点的隔离模型。
    // 故用独立锁保护的只读快照对外暴露（与 stateLock 分开，两者互不嵌套，无死锁风险）。
    // UI 侧由「一键签到」按钮自身的进行中状态 + QoderStore 的额度刷新驱动重算，最长滞后一个刷新周期。

    private let outcomesLock = UnfairLock()
    /// 当天签到结果的内存缓存，`dailyOutcomesCacheDay` 记录它属于哪一天，日期滚动即失效。
    private var dailyOutcomesCache: [String: QoderClaimOutcome] = [:]
    private var dailyOutcomesCacheDay: String?

    init(transport: QoderCampaignTransport = URLSessionQoderCampaignTransport(),
         poolDirectory: URL? = nil,
         defaults: UserDefaults? = nil,
         now: @escaping () -> Date = Date.init) {
        self.transport = transport
        if let d = poolDirectory {
            self.poolDirectory = d
        } else {
            self.poolDirectory = QoderPoolCredentials.defaultDirectory
        }
        self.defaults = defaults ?? .standard
        self.now = now
    }

    // MARK: 扫描

    /// 读取 poolDirectory 下所有 account_*.json，解析出凭证列表（解析失败的静默跳过）。共享实现见 QoderPoolCredentials。
    func scanAccounts(fileManager fm: FileManager = .default) -> [QoderPoolAccountCredential] {
        QoderPoolCredentials.scanAccounts(in: poolDirectory, fileManager: fm)
    }

    // MARK: 单账号领取

    static let baseURL = "https://openapi.qoder.com.cn"

    private func headers(for credential: QoderPoolAccountCredential, contentType: Bool) -> [String: String] {
        var h: [String: String] = [
            "Authorization": "Bearer \(credential.accessToken)",
            "Cosy-ClientType": "10",
            "Cosy-Version": "0.1.18",
            "Cosy-MachineOS": "darwin",
            "Cosy-MachineId": credential.machineId,
            "User-Agent": "Qoder",
            "Accept": "application/json",
        ]
        if contentType { h["Content-Type"] = "application/json" }
        return h
    }

    func claim(for credential: QoderPoolAccountCredential) async -> QoderClaimOutcome {
        // 步骤 1：查当前可领活动
        guard let listURL = URL(string: "\(Self.baseURL)/sash/api/v1/me/campaigns") else {
            return .failure("invalid campaigns URL")
        }
        let listResp: (status: Int, data: Data)
        do {
            listResp = try await transport.request(url: listURL, method: "GET", headers: headers(for: credential, contentType: false), body: nil)
        } catch {
            return .failure("campaigns fetch threw: \(error.localizedDescription)")
        }
        guard (200..<300).contains(listResp.status) else {
            return .failure("campaigns fetch status \(listResp.status)")
        }
        guard let list = try? JSONDecoder().decode(QoderCampaignList.self, from: listResp.data) else {
            return .failure("campaigns decode failed")
        }
        let ids = list.claimableIds
        guard !ids.isEmpty else { return .nothingToClaim }

        // 步骤 2：逐条领取（一个账号可能有多条可领）；分别统计新领取数、幂等命中数与失败数，
        // 避免"全部 POST 都失败了却仍被当成已领取成功"的误判（见任务4审查问题1b）。
        var newClaimCount = 0      // status==CLAIMED && replayed!=true
        var replayedCount = 0      // status==CLAIMED && replayed==true，幂等命中，不需要重试
        var failureCount = 0
        for id in ids {
            guard let claimURL = URL(string: "\(Self.baseURL)/sash/api/v1/me/campaigns/\(id)/claim") else { continue }
            let claimResp: (status: Int, data: Data)
            do {
                claimResp = try await transport.request(url: claimURL, method: "POST", headers: headers(for: credential, contentType: true), body: Data("{}".utf8))
            } catch {
                claimLog.warning("claim \(id) threw for user \(credential.userId): \(error.localizedDescription)")
                failureCount += 1
                continue   // 单条失败不影响该账号其它条目
            }
            guard (200..<300).contains(claimResp.status) else {
                claimLog.warning("claim \(id) status \(claimResp.status) for user \(credential.userId)")
                failureCount += 1
                continue
            }
            let parsed = try? JSONDecoder().decode(QoderClaimResponse.self, from: claimResp.data)
            if parsed?.status == "CLAIMED" {
                if parsed?.replayed == true {
                    replayedCount += 1
                } else {
                    newClaimCount += 1
                }
            } else {
                // 2xx 但 status 字段不是 CLAIMED（或缺失/解码失败），视为异常响应，不计成功也不重试
                claimLog.warning("claim \(id) unexpected body for user \(credential.userId): \(String(data: claimResp.data.prefix(200), encoding: .utf8) ?? "?")")
                failureCount += 1
            }
        }
        if newClaimCount == 0 && replayedCount == 0 && failureCount > 0 {
            return .failure("all \(failureCount) claim(s) failed")
        }
        return newClaimCount > 0 ? .claimed : .alreadyClaimed
    }

    // MARK: 每日签到主入口

    /// 遍历账号池跑一轮签到，返回**当天累计**的各账号签到结果快照（Key = userId）。
    ///
    /// 先按账号当天去重（跳过「今天已成功处理过」的号），顺序领取（简单优先，避免给服务端并发压力）；
    /// 只有真正领到（新领取或幂等命中）才算「今天处理过了」。`.nothingToClaim`（当前无可领项，
    /// 可能只是还没到活动刷新窗口）和 `.failure` 都不写去重标记，留待下次触发重新查一遍。
    ///
    /// 第三页「一键签到」按钮与 QoderStore/AppDelegate 的静默巡检共用这一条路径：正因为内部有
    /// 当天去重 + in-flight 守卫，用户连点、或手点与后台巡检撞车都不会对同一批号重复发请求。
    @discardableResult
    func claimAll() async -> [String: QoderClaimOutcome] {
        await claimAllWithSummary().outcomes
    }

    /// 同 `claimAll()`，但额外回传本轮分类摘要（`QoderClaimSweepSummary`），供「一键签到」按钮
    /// 区分「撞守卫跳过 / 池为空 / 真的跑完了一轮」三种情况给出不同反馈文案。
    @discardableResult
    func claimAllWithSummary() async -> QoderClaimSweep {
        // 并发守卫：refresh() 每 15s 触发一次，而单轮巡检（账号数 × GET/POST 超时）很容易超过 15s，
        // 不加守卫会叠加多个 detached Task 对同一批未标记账号重复发请求 —— 对逆向的活动接口这是
        // 最容易触发服务端风控的行为。命中重入时直接跳过本次触发，不做额外错误处理。
        let shouldRun: Bool = stateLock.withLock {
            let r = QoderCampaignGuard.begin(isRunning: isRunning)
            isRunning = r.isRunning
            return r.shouldRun
        }
        guard shouldRun else {
            claimLog.info("claim sweep already in flight, skipping this trigger")
            return QoderClaimSweep(outcomes: dailyOutcomes, summary: .skippedInFlight)
        }
        defer { stateLock.withLock { isRunning = QoderCampaignGuard.end() } }

        let accounts = scanAccounts()
        guard !accounts.isEmpty else {
            claimLog.info("no pool accounts found at \(self.poolDirectory.path), skip")
            return QoderClaimSweep(outcomes: dailyOutcomes, summary: .emptyPool)
        }
        let today = Self.dayString(now())
        var outcomes = dailyOutcomes
        var outcomesDirty = false
        var newlyClaimed = 0, alreadyClaimed = 0, nothingToClaim = 0, failed = 0
        for credential in accounts {
            let key = "qoder.campaign.claimed.\(credential.userId)"
            if defaults.string(forKey: key) == today {
                // 今天已成功处理过 → 不再发请求。老版本只有去重标记、没有当日状态字典，
                // 这里补齐成「今日已领过」，否则 UI 会在明明已经领到的情况下谎报「待签到」。
                if outcomes[credential.userId]?.countsAsClaimed != true {
                    outcomes[credential.userId] = .alreadyClaimed
                    outcomesDirty = true
                }
                alreadyClaimed += 1
                continue
            }
            let outcome = await claim(for: credential)
            outcomes[credential.userId] = outcome
            outcomesDirty = true
            switch outcome {
            case .claimed:
                newlyClaimed += 1
                defaults.set(today, forKey: key)
                claimLog.info("user \(credential.userId.prefix(8)):… outcome=\(outcome.logDescription)")
            case .alreadyClaimed:
                alreadyClaimed += 1
                defaults.set(today, forKey: key)
                claimLog.info("user \(credential.userId.prefix(8)):… outcome=\(outcome.logDescription)")
            case .nothingToClaim:
                nothingToClaim += 1
                // 不写标记：现在没有可领项不代表今天之后也没有（比如还没到每日刷新点），下次触发再查
                claimLog.info("user \(credential.userId.prefix(8)):… nothing-to-claim now, will retry on next trigger")
            case .failure(let reason):
                failed += 1
                claimLog.warning("user \(credential.userId.prefix(8)):… failed: \(reason)")
            }
        }
        if outcomesDirty { saveDailyOutcomes(outcomes, forDay: today) }
        return QoderClaimSweep(
            outcomes: outcomes,
            summary: .completed(newlyClaimed: newlyClaimed, alreadyClaimed: alreadyClaimed, nothingToClaim: nothingToClaim, failed: failed)
        )
    }

    // MARK: 签到状态查询与持久化

    /// 当天全部账号的签到结果快照（Key = userId）。跨天时自然变为空字典（读的是新一天的 Key）。
    var dailyOutcomes: [String: QoderClaimOutcome] {
        outcomesLock.withLock { syncedDailyOutcomesLocked() }
    }

    /// 单号签到状态文案。当天无记录 = 待签到。
    /// - Parameter userId: **凭证文件里的完整 userId**。UI 侧拿到的多半是网关的脱敏串
    ///   （`01a**…**057`），传那个请用 `statusDescription(forOrbId:amongAllOrbs:)`。
    func statusDescription(for userId: String) -> String {
        Self.statusText(for: dailyOutcomes[userId])
    }

    /// 同上，但入参是 Orb 侧 id（可能是脱敏串），并带整屏 Orb 做歧义保护。QoderPoolRingView tooltip 用这条。
    func statusDescription(forOrbId orbId: String, amongAllOrbs orbIds: [String]) -> String {
        Self.statusText(forOrbId: orbId, amongAllOrbs: orbIds, in: dailyOutcomes)
    }

    /// Orb 侧 id → 当日签到结果。
    ///
    /// 为什么不能直接查字典：签到结果的 Key 是凭证文件里的**完整 UUID**，而 UI 侧 Orb 的 id 是网关
    /// `/v1/pool/status` 返回的**脱敏串**，两者永远不相等 —— 与「Orb 余额恒 `--`」是同一个坑
    /// （详见 `QoderPoolIdMatcher` 头注释），故复用它的 `matches` 做前后缀匹配。
    /// 口径同样严格：**任何歧义一律判不可确定返回 nil**（UI 降级为「待签到」），绝不张冠李戴。
    static func outcome(forOrbId orbId: String,
                        amongAllOrbs orbIds: [String],
                        in outcomes: [String: QoderClaimOutcome]) -> QoderClaimOutcome? {
        let hits = outcomes.keys.filter { QoderPoolIdMatcher.matches(orbId: orbId, quotaId: $0) }
        // 命中 Key 天然互异（字典键），故 0 个 = 无记录、>1 个 = 歧义，都判不可确定。
        guard hits.count == 1, let only = hits.first else { return nil }
        // 反向保护：同一个 Key 被整屏里多个 Orb 认领时，说明这几个 Orb 无法区分，同样不猜。
        let owners = orbIds.filter { QoderPoolIdMatcher.matches(orbId: $0, quotaId: only) }.count
        guard owners <= 1 else { return nil }
        return outcomes[only]
    }

    /// UI 入口：给单个 Orb 出文案（形状对齐 `QoderPoolIdMatcher.quota(for:amongAllOrbs:in:)`）。
    static func statusText(forOrbId orbId: String,
                           amongAllOrbs orbIds: [String],
                           in outcomes: [String: QoderClaimOutcome]) -> String {
        statusText(for: outcome(forOrbId: orbId, amongAllOrbs: orbIds, in: outcomes))
    }

    /// 「今日签到: x/y」的分子口径：claimed 与 alreadyClaimed 都算今天拿到过。
    static func claimedCount(in outcomes: [String: QoderClaimOutcome]) -> Int {
        outcomes.values.filter(\.countsAsClaimed).count
    }

    /// outcome → 展示文案的纯映射。与实例状态解耦，是为了能脱离 UserDefaults 单测每条分支。
    static func statusText(for outcome: QoderClaimOutcome?) -> String {
        switch outcome {
        case .claimed: return "已领取"
        case .alreadyClaimed: return "今日已领过"
        case .nothingToClaim, .none: return "待签到"
        case .failure(let reason): return "签到失败(\(reason))"
        }
    }

    /// 持久化 Key 带当天日期：隔天写新 Key、读不到旧 Key，自然重置，不需要任何清理逻辑。
    private func dailyOutcomesKeyLocked() -> String {
        "QoderCampaignClaimer_outcomes_\(Self.dayString(now()))"
    }

    /// 取内存缓存；日期滚动（或本进程首次访问）时从当天的持久化 Key 重新装载。调用方必须已持有 outcomesLock。
    private func syncedDailyOutcomesLocked() -> [String: QoderClaimOutcome] {
        let key = dailyOutcomesKeyLocked()
        if dailyOutcomesCacheDay != key {
            dailyOutcomesCacheDay = key
            if let data = defaults.data(forKey: key),
               let saved = try? JSONDecoder().decode([String: QoderClaimOutcome].self, from: data) {
                dailyOutcomesCache = saved
            } else {
                dailyOutcomesCache = [:]
            }
        }
        return dailyOutcomesCache
    }

    /// 落盘当日状态。`forDay` 必须与本轮开始时算出的日期一致：跨零点完成的一轮，其基线字典属于昨天，
    /// 整包写进新一天的 Key 会把昨天的结果冒充成今天的进度（缓存的 cacheDay 仍是旧值，
    /// 下次读取自然按新 Key 重载成空，无需在此处补救）。
    private func saveDailyOutcomes(_ outcomes: [String: QoderClaimOutcome], forDay day: String) {
        outcomesLock.withLock {
            guard day == Self.dayString(now()) else { return }
            guard let data = try? JSONEncoder().encode(outcomes) else { return }
            let key = dailyOutcomesKeyLocked()
            defaults.set(data, forKey: key)
            dailyOutcomesCache = outcomes
            dailyOutcomesCacheDay = key
        }
    }

    /// 日期 Key 专用格式器：`yyyy-MM-dd` + en_US_POSIX（不受用户地区/日历设置影响），配置在初始化后
    /// 不再改动，故可静态复用，免去每次访问签到状态都新建一个 DateFormatter。
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static func dayString(_ d: Date) -> String {
        dayFormatter.string(from: d)
    }
}

private extension QoderClaimOutcome {
    /// 「今天这个号已经拿到过 credits」——签到进度分子的统计口径，与 `claimedCount(in:)` 共用。
    var countsAsClaimed: Bool {
        switch self {
        case .claimed, .alreadyClaimed: return true
        case .nothingToClaim, .failure: return false
        }
    }

    var logDescription: String {
        switch self {
        case .claimed: return "claimed"
        case .alreadyClaimed: return "already-claimed(replayed)"
        case .nothingToClaim: return "nothing-to-claim"
        case .failure: return "failed"
        }
    }
}
