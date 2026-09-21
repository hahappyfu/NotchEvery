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

    /// 测试可见：objectWillChange 发射计数，验证发布去重。
    private(set) var objectWillChangeCountForTest = 0

    /// 网关端口（默认读全局配置；Manager 启动时会同步为当前配置端口）
    var port: Int
    private let transport: QoderHTTPTransport
    private let authKeysFile: URL
    private var consecutiveFailures = 0
    private var timer: Timer?
    private var logTailerCursor = QoderLogTailer.Cursor()
    private var aggregator = QoderAggregator()

    init(port: Int? = nil,
         transport: QoderHTTPTransport = URLSessionQoderTransport(),
         authKeysFile: URL? = nil) {
        self.port = port ?? QoderGatewayManager.configuredPort
        self.transport = transport
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
    }

    func stop() { timer?.invalidate(); timer = nil }

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
            // 独立 Task + try? 兜底：领取逻辑任何异常都不能影响上面的 quota/pool 刷新主流程。
            Task.detached(priority: .background) {
                await QoderCampaignClaimer.shared.claimAllOncePerDay()
            }
        }
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
