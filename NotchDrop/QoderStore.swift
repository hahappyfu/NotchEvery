//
//  QoderStore.swift
//  NotchEvery
//
//  任务 6：qodercn-gateway 观测层 —— /quota + /v1/pool/status 轮询 + 今日统计聚合发布。
//  网络经 QoderHTTPTransport 注入（单测用假实现）；错误内化为 stale/nil/空数组，不弹错。
//  参考 AntigravityStore 的 Timer + 值级去重风格。
//

import Combine
import Foundation
import os.log

private let storeLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "NotchEvery", category: "QoderStore")

// MARK: - Transport

protocol QoderHTTPTransport {
    func get(url: URL, bearer: String) async throws -> Data
}

/// 默认实现：URLSession，Bearer 头，15s 超时。
struct URLSessionQoderTransport: QoderHTTPTransport {
    func get(url: URL, bearer: String) async throws -> Data {
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        return data
    }
}

// MARK: - Models

struct QoderQuota: Equatable {
    let userType: String
    let unit: String
    let total: Int
    let used: Int
    let remaining: Int
    let percentage: Double
    let isExceeded: Bool
    let resetDate: Date?

    private struct Raw: Decodable {
        let user_type: String?
        let unit: String?
        let total: Int?
        let used: Int?
        let remaining: Int?
        let percentage: Double?
        let is_exceeded: Bool?
        let reset_at_ms: Double?
    }

    static func decode(_ data: Data) -> QoderQuota? {
        guard let raw = try? JSONDecoder().decode(Raw.self, from: data) else { return nil }
        // 关键字段缺失视为无效（total/remaining 至少要有其一）
        guard raw.total != nil || raw.remaining != nil else { return nil }
        let reset = raw.reset_at_ms.map { Date(timeIntervalSince1970: $0 / 1000.0) }
        return QoderQuota(
            userType: raw.user_type ?? "",
            unit: raw.unit ?? "credits",
            total: raw.total ?? 0,
            used: raw.used ?? 0,
            remaining: raw.remaining ?? 0,
            percentage: raw.percentage ?? 0,
            isExceeded: raw.is_exceeded ?? false,
            resetDate: reset
        )
    }
}

struct QoderPoolMember: Equatable, Identifiable {
    let userId: String      // 已脱敏
    let source: String
    let cooled: Bool
    let lastUsedAt: Date?
    let lastProbeOK: Bool
    var id: String { userId }

    /// UI 占位（成员查不到时的中性态）。
    static func placeholder(_ userId: String) -> QoderPoolMember {
        QoderPoolMember(userId: userId, source: "", cooled: false, lastUsedAt: nil, lastProbeOK: false)
    }
}

struct QoderPoolStatus: Equatable {
    let totalAccounts: Int
    let activeAccounts: Int
    let cooledAccounts: Int
    let stickyUserId: String?
    let accounts: [QoderPoolMember]

    private struct Raw: Decodable {
        let total_accounts: Int?
        let active_accounts: Int?
        let cooled_accounts: Int?
        let sticky_user_id: String?
        let accounts: [RawAccount]?
        struct RawAccount: Decodable {
            let user_id: String?
            let source: String?
            let cooled: Bool?
            let last_used_at: String?
            let last_probe_ok: Bool?
        }
    }

    private static let iso = ISO8601DateFormatter()

    static func decode(_ data: Data) -> QoderPoolStatus? {
        guard let raw = try? JSONDecoder().decode(Raw.self, from: data) else { return nil }
        let members = (raw.accounts ?? []).map { a in
            QoderPoolMember(
                userId: a.user_id ?? "",
                source: a.source ?? "",
                cooled: a.cooled ?? false,
                lastUsedAt: a.last_used_at.flatMap { iso.date(from: $0) },
                lastProbeOK: a.last_probe_ok ?? false
            )
        }
        return QoderPoolStatus(
            totalAccounts: raw.total_accounts ?? members.count,
            activeAccounts: raw.active_accounts ?? members.filter { !$0.cooled }.count,
            cooledAccounts: raw.cooled_accounts ?? members.filter { $0.cooled }.count,
            stickyUserId: raw.sticky_user_id,
            accounts: members
        )
    }
}

// MARK: - Store

/// 「一键签到」点击后短暂展示的一次性反馈。`id` 用于让文案完全相同（如连续两次都「今日已全部签到」）
/// 的两次点击也能被 SwiftUI 认成一次新变化、重新播放淡入动画，不至于看起来「点了没反应」。
struct ClaimFeedback: Equatable {
    let text: String
    let isFailure: Bool
    let id: UUID
}

@MainActor
final class QoderStore: ObservableObject {
    static let shared = QoderStore()

    @Published private(set) var quota: QoderQuota?
    @Published private(set) var poolMembers: [QoderPoolMember] = []
    /// /v1/pool/status 顶层 sticky_user_id（粘性当前号，圆形池主焦点用）
    @Published private(set) var poolStatusStickyId: String?
    @Published private(set) var today = QoderDailyAgg()
    @Published private(set) var yesterday: QoderDailyAgg?
    @Published private(set) var isQuotaStale = false
    /// 全池额度快照：账号池里每个号各自的真实余额（plan+addOn），由 QoderPoolQuotaProber 异步探测回填。
    @Published private(set) var poolQuotas: [QoderAccountQuota] = []
    /// 手动刷新（第三页账号池「刷新」按钮）进行中的标志位，仅用于按钮自身置灰/转圈反馈；
    /// 不互斥定时轮询——底层 prober 自带 in-flight 守卫，两路并发探测本身就不会打架。
    @Published private(set) var isProbingPoolQuotas: Bool = false
    /// 当日各账号的 credits 签到结果（Key = 凭证文件里的完整 userId），由 `runCampaignClaim()` 从
    /// QoderCampaignClaimer 回填。放这儿而不是让 UI 直读 claimer，是因为 claimer 不是 ObservableObject
    /// （网络巡检跑在 detached 后台任务里，见其类内注释），后台静默领取完成后没人发布变化 ——
    /// 走 @Published 才能让「今日签到 x/y」与各 Orb tooltip 不用等下一个额度轮询周期就自动刷新。
    @Published private(set) var claimOutcomes: [String: QoderClaimOutcome] = [:]
    /// 「一键签到」进行中的标志位，仅供按钮置灰/换文案（与 `isProbingPoolQuotas` 同一设计）。
    /// 收在 store 而不是 View 的 @State：View 的计算属性不保证 MainActor 隔离，
    /// 在按钮里 `Task {}` 中写 @State 会落到非主线程执行器上。
    @Published private(set) var isClaimingCampaignCredits: Bool = false
    /// 点完「一键签到」后短暂展示的即时反馈（成功/失败/无新内容等），nil 表示当前无反馈可展示。
    /// 之所以单独有这一个字段：`claimOutcomes` 走 `publishIfChanged` 去重，当天全部命中去重标记时
    /// 本轮结果与上一轮完全相同 → 不触发发布 → 按钮「签到中…」瞬间复原、数字纹丝不动，用户看不出
    /// 到底点没点上。反馈文案独立于 outcomes，只要点了就一定变一次，解决「没任何反馈」的问题。
    @Published private(set) var lastClaimFeedback: ClaimFeedback?
    private var claimFeedbackClearTask: Task<Void, Never>?

    /// 全池剩余额度合计；空数组表示「还没探测到任何数据」而非「真的是 0」，故返回 nil 供 UI 显示 --。
    var poolTotalRemaining: Double? {
        poolQuotas.isEmpty ? nil : poolQuotas.reduce(0) { $0 + $1.totalRemaining }
    }

    /// 测试可见：objectWillChange 发射计数，验证发布去重。
    private(set) var objectWillChangeCountForTest = 0

    /// 网关端口（默认读全局配置；Manager 启动时会同步为当前配置端口）
    var port: Int
    private let transport: QoderHTTPTransport
    private let authKeysFile: URL
    /// 全池额度探针（协议注入，默认走真网络单例；测试注入假实现，绝不真联网）。
    private let quotaProber: any QoderPoolQuotaProbing
    private var consecutiveFailures = 0
    private var timer: Timer?
    /// 60s 全池额度定时刷新循环句柄（区别于上面 15s 的 quota/pool/status `timer`，那个只打网关 HTTP；
    /// 这个专门驱动 `refreshPoolQuotas()`，覆盖真实探测本身可能耗时较久、不该挤进 15s 节奏的情况）。
    private var quotaTimerTask: Task<Void, Never>?
    private var logTailerCursor = QoderLogTailer.Cursor()
    private var aggregator = QoderAggregator()

    init(port: Int? = nil,
         transport: QoderHTTPTransport = URLSessionQoderTransport(),
         authKeysFile: URL? = nil,
         quotaProber: any QoderPoolQuotaProbing = QoderPoolQuotaProber.shared) {
        self.port = port ?? QoderGatewayManager.configuredPort
        self.transport = transport
        self.quotaProber = quotaProber
        if let k = authKeysFile {
            self.authKeysFile = k
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
            self.authKeysFile = base.appendingPathComponent("NotchEvery/qoder-gateway/authkeys")
        }
        // 追踪自身发布次数用于去重断言
        _ = objectWillChange.sink { [weak self] in self?.objectWillChangeCountForTest += 1 }
    }

    func start(logURL: URL?) {
        stop()
        refresh(logURL: logURL)
        let t = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh(logURL: logURL) }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        storeLog.info("QoderStore started, interval 15s, port \(self.port)")
        // 面板打开先拿 claimer 当天已持久化的结果占位：冷启动时后台巡检还要几秒才回得来，
        // 少了这一步「今日签到 x/y」与 tooltip 会先空一帧显示成全员待签到。
        publishIfChanged(\.claimOutcomes, QoderCampaignClaimer.shared.dailyOutcomes)
        // 只要 start() 被调用（不管是不是因为面板打开才调用的），就无条件异步发起一次每日巡检，
        // 保证 App 生命周期内至少尝试过一次自动领取，不完全依赖 refresh() 的轮询节奏。
        // claimAll() 内部按账号当天去重，重复触发无副作用；detached + 不阻塞主线程。
        Task.detached(priority: .background) { [weak self] in
            guard let store = self else { return }
            await store.runCampaignClaim()
        }
        // 启动即异步探测一次全池额度，不等第一次 refresh 轮询节奏。
        Task.detached(priority: .background) { [weak self] in
            guard let store = self else { return }
            await store.refreshPoolQuotas()
        }
        // 60s 循环：面板可见期间持续刷新全池额度，避免只看冷启动那一次的结果。
        // Task.sleep 挂起不占 MainActor；store 弱引用 + 双重取消检查，stop() 调用后立即退出循环。
        quotaTimerTask?.cancel()
        quotaTimerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard let self, !Task.isCancelled else { break }
                await self.refreshPoolQuotas()
            }
        }
    }

    func stop() {
        timer?.invalidate(); timer = nil
        quotaTimerTask?.cancel(); quotaTimerTask = nil
    }

    /// 第三页「刷新」按钮手动触发一次全池额度探测。
    /// 与 60s 定时循环共用 `refreshPoolQuotas()`；这里额外加 `isProbingPoolQuotas` 标志位，
    /// 仅用于让按钮自身置灰/转圈（避免用户连点重复触发），不追求全局互斥——底层 prober 的
    /// in-flight 守卫才是真正防并发的机制。
    func triggerManualQuotaRefresh() async {
        guard !isProbingPoolQuotas else { return }
        isProbingPoolQuotas = true
        defer { isProbingPoolQuotas = false }
        await refreshPoolQuotas()
    }

    /// 第三页「一键签到」按钮手动触发一轮 credits 签到。与 `triggerManualQuotaRefresh()` 同款设计：
    /// 标志位只为按钮自身的置灰/换文案反馈，真正防并发的是 claimer 内部的 in-flight 守卫 +
    /// 按账号当天去重（连点、或与后台静默巡检撞车都不会重复发请求）。
    /// 收尾再刷一次全池额度：签到本身会改余额，不刷就要等 60s 才能在卡上看出来。
    func triggerManualCampaignClaim() async {
        guard !isClaimingCampaignCredits else { return }
        isClaimingCampaignCredits = true
        let startedAt = Date()
        defer { isClaimingCampaignCredits = false }
        // 走带摘要的变体而不是 `runCampaignClaim()`：后者的结果字典在「当天全部命中去重标记」时
        // 与上一轮逐字节相同，`publishIfChanged` 会吞掉这次发布，UI 完全不动 —— 这正是
        // 「点了没反应」的根因，摘要分类才能区分「真的做了但没新东西」与「压根没做」。
        let sweep = await QoderCampaignClaimer.shared.claimAllWithSummary()
        await Task { @MainActor in
            publishIfChanged(\.claimOutcomes, sweep.outcomes)
            showClaimFeedback(for: sweep.summary)
        }.value
        // 「签到中…」至少可见 600ms：当天全部命中去重标记时整轮可能 <50ms 就跑完（一个网络请求都不发），
        // 不加下限按钮会闪一下立刻复原，跟「点了没反应」几乎没区别。
        let elapsed = Date().timeIntervalSince(startedAt)
        let minVisible: TimeInterval = 0.6
        if elapsed < minVisible {
            try? await Task.sleep(nanoseconds: UInt64((minVisible - elapsed) * 1_000_000_000))
        }
        await refreshPoolQuotas()
    }

    /// 把本轮签到分类摘要翻译成一句反馈文案，展示 4s 后自动消失。`claimFeedbackClearTask` 先取消
    /// 再重挂，保证连点时上一轮的清除定时器不会把新一轮刚设置的文案提前抹掉。
    private func showClaimFeedback(for summary: QoderClaimSweepSummary) {
        let text: String
        let isFailure: Bool
        switch summary {
        case .skippedInFlight:
            text = "正在签到中，请稍候…"
            isFailure = false
        case .emptyPool:
            text = "账号池为空"
            isFailure = true
        case .completed(let newly, let already, let nothing, let failedCount):
            if failedCount > 0 {
                text = "签到完成，\(failedCount) 个号失败"
                isFailure = true
            } else if newly > 0 {
                text = "新领到 \(newly) 个号"
                isFailure = false
            } else if already > 0 {
                text = "今日已全部签到"
                isFailure = false
            } else if nothing > 0 {
                text = "暂无可领奖励"
                isFailure = false
            } else {
                text = "今日已全部签到"
                isFailure = false
            }
        }
        lastClaimFeedback = ClaimFeedback(text: text, isFailure: isFailure, id: UUID())
        claimFeedbackClearTask?.cancel()
        claimFeedbackClearTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard let self, !Task.isCancelled else { return }
            self.lastClaimFeedback = nil
        }
    }

    /// 驱动一轮签到并把结果回填 `claimOutcomes`，返回结果字典（按钮侧不关心，自动巡检侧便于直接取用）。
    /// nonisolated：与 `refreshPoolQuotas()` 同一套路 —— 整轮巡检是「账号数 × GET/POST 超时」的网络活，
    /// 不能压在 MainActor 上；回填切回 MainActor 写 @Published，避免跨隔离数据竞争。
    @discardableResult
    nonisolated func runCampaignClaim() async -> [String: QoderClaimOutcome] {
        let outcomes = await QoderCampaignClaimer.shared.claimAll()
        await Task { @MainActor in
            publishIfChanged(\.claimOutcomes, outcomes)
        }.value
        return outcomes
    }

    /// 供单测直接驱动一次刷新（gatewayUp 注入脱离全局 shared）。
    func refreshNow(gatewayUp: Bool = true) async {
        await fetchQuotaAndPool(gatewayUp: gatewayUp)
    }

    /// 重置为离线未运行态
    func resetToOffline() {
        consecutiveFailures = 0
        publishIfChanged(\.quota, nil)
        publishIfChanged(\.poolMembers, [])
        publishIfChanged(\.poolStatusStickyId, nil)
        withMutation { isQuotaStale = false }
    }

    func refresh(logURL: URL?) {
        Task { @MainActor in
            await fetchQuotaAndPool()
            if let url = logURL { updateUsageFromLog(url: url) }
            // 顺带静默触发一次每日 Credits 自动领取（内部按账号去重，当天重复调用无副作用）。
            // 独立 detached Task：领取逻辑任何异常/耗时都不能影响上面的 quota/pool 刷新主流程。
            Task.detached(priority: .background) { [weak self] in
                guard let store = self else { return }
                await store.runCampaignClaim()
            }
            // 顺带异步探测一次全池额度；prober 自带 in-flight 守卫，15s 轮询节奏下若上一轮还没跑完会自动跳过。
            Task.detached(priority: .background) { [weak self] in
                guard let store = self else { return }
                await store.refreshPoolQuotas()
            }
        }
    }

    /// 驱动一次全池额度探测并回填 `poolQuotas`。
    /// nonisolated：由 detached background Task 调用，不阻塞 MainActor；回填必须切回 MainActor
    /// 赋值 @Published 属性（QoderStore 是 @MainActor 类，跨隔离直接写会有数据竞争）。
    /// probeAll() 签名不 throws，无需包 do/catch（写了反而是永远进不去的死分支 + 编译器 unreachable 警告）。
    ///
    /// **只在拿到非 nil 时回填**：nil 代表本轮撞上了 prober 的 in-flight 守卫、压根没探。触发源有
    /// 三处且几乎同时（AppDelegate 冷启动、GatewayZoneView.onAppear→start()、15s refresh 轮询），
    /// 后到的那次若把"被跳过的空结果"当成探测结论覆盖上去，就会把先完成的那轮真值冲掉，UI 永久显示 `--`。
    nonisolated func refreshPoolQuotas() async {
        guard let quotas = await self.quotaProber.probeAll() else { return }
        await Task { @MainActor in
            publishIfChanged(\.poolQuotas, quotas)
        }.value
    }

    /// gatewayUp=false（未托管/非 running）→ 直接离线空态，不发注定失败的请求。
    private func fetchQuotaAndPool(gatewayUp: Bool = QoderGatewayManager.shared.isHosting) async {
        if !gatewayUp {
            resetToOffline()
            return
        }
        let bearer = firstAuthKey()
        do {
            let qData = try await transport.get(url: URL(string: "http://127.0.0.1:\(port)/quota")!, bearer: bearer)
            let pData = try await transport.get(url: URL(string: "http://127.0.0.1:\(port)/v1/pool/status")!, bearer: bearer)
            consecutiveFailures = 0
            publishIfChanged(\.quota, QoderQuota.decode(qData))
            let pool = QoderPoolStatus.decode(pData)
            publishIfChanged(\.poolMembers, pool?.accounts ?? [])
            publishIfChanged(\.poolStatusStickyId, pool?.stickyUserId)
            if isQuotaStale { withMutation { isQuotaStale = false } }
        } catch {
            consecutiveFailures += 1
            if consecutiveFailures >= 2 && !isQuotaStale { withMutation { isQuotaStale = true } }
            storeLog.debug("fetch failed (\(self.consecutiveFailures)): \(error.localizedDescription)")
        }
    }

    private func updateUsageFromLog(url: URL) {
        guard let events = try? QoderLogTailer.readIncremental(url: url, cursor: &logTailerCursor),
              !events.isEmpty else { return }
        let todayStr = Self.dayString(Date())
        aggregator.apply(events: events, today: todayStr)
        publishIfChanged(\.today, aggregator.today)
        publishIfChanged(\.yesterday, aggregator.yesterday)
    }

    private func firstAuthKey() -> String {
        guard let s = try? String(contentsOf: authKeysFile, encoding: .utf8) else { return "" }
        return s.split(separator: "\n").first.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
    }

    private static func dayString(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: d)
    }

    // MARK: 值级去重发布

    private func withMutation(_ body: () -> Void) { body() }

    private func publishIfChanged<T: Equatable>(_ keyPath: ReferenceWritableKeyPath<QoderStore, T>, _ newValue: T) {
        if self[keyPath: keyPath] != newValue {
            self[keyPath: keyPath] = newValue
        }
    }
}
