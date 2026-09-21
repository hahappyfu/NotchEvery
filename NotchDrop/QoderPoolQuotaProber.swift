//
//  QoderPoolQuotaProber.swift
//  NotchEvery
//
//  全池额度探针：逐个查询账号池里每个 Qoder 号各自的真实余额（GET /api/v2/quota/usage），
//  供上层汇总成全池总额、并在每个 Orb 上展示。网络经 QoderCampaignTransport 注入
//  （单测用假实现，绝不真联网）；单账号失败只记日志跳过，不影响其它账号。
//

import Foundation
import os.log

private let probeLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "NotchEvery", category: "QoderPoolQuota")

// MARK: - 结果模型

/// 单个账号的额度快照。上游响应是嵌套结构（userQuota / addOnQuota），这里压平成两个分量 + 相加口径。
struct QoderAccountQuota: Equatable {
    let userId: String
    let planRemaining: Double
    let addOnRemaining: Double
    var totalRemaining: Double { planRemaining + addOnRemaining }
}

// MARK: - 上游响应解码

/// GET https://gateway.qoder.com.cn/api/v2/quota/usage 的原始嵌套响应（权威抓包格式）。
/// 注意 remaining 是浮点数；**不能**复用 App 里扁平的 QoderQuota（那是网关 /quota 压平后的结构）。
private struct QoderUsageResponse: Decodable {
    struct QuotaBlock: Decodable {
        let remaining: Double?
    }
    let userId: String?
    let userQuota: QuotaBlock?
    let addOnQuota: QuotaBlock?
}

// MARK: - 并发守卫

/// in-flight 守卫的纯状态转移（与 QoderCampaignGuard 同款）：`begin` 只在空闲时占用成功，
/// 已占用则拒绝；`end` 无条件释放。抽成纯函数以便脱离异步时序稳定断言。
enum QoderPoolQuotaGuard {
    static func begin(isRunning: Bool) -> (shouldRun: Bool, isRunning: Bool) {
        if isRunning { return (false, true) }
        return (true, true)
    }
    static func end() -> Bool { false }
}

// MARK: - Prober

/// 抽象出 `probeAll()` 供 `QoderStore` 注入假实现做单测（与仓库对 transport/claimer 的协议化风格一致，
/// 但因 QoderCampaignClaimer 目前直接以具体类型被引用、无协议先例，这里只为本类新增最小协议）。
protocol QoderPoolQuotaProbing: AnyObject {
    func probeAll() async -> [QoderAccountQuota]
}

final class QoderPoolQuotaProber: QoderPoolQuotaProbing {
    static let shared = QoderPoolQuotaProber()

    static let baseURL = "https://gateway.qoder.com.cn"

    private let transport: QoderCampaignTransport
    private let poolDirectory: URL
    /// 本类不是 actor 隔离的，probeAll() 可能被后台 Task 并发触发，标志位必须加锁访问。
    /// 复用仓库既有的 UnfairLock（SignalPipeline.swift）。
    private let stateLock = UnfairLock()
    private var isRunning = false

    init(transport: QoderCampaignTransport = URLSessionQoderCampaignTransport(),
         poolDirectory: URL? = nil) {
        self.transport = transport
        self.poolDirectory = poolDirectory ?? QoderPoolCredentials.defaultDirectory
    }

    // MARK: 单账号请求头（与 claimer 同一套 Cosy-* 约定）

    private func headers(for credential: QoderPoolAccountCredential) -> [String: String] {
        [
            "Authorization": "Bearer \(credential.accessToken)",
            "Cosy-ClientType": "10",
            "Cosy-Version": "0.1.18",
            "Cosy-MachineOS": "darwin",
            "Cosy-MachineId": credential.machineId,
            "User-Agent": "Qoder",
            "Accept": "application/json",
        ]
    }

    // MARK: 主入口

    /// 遍历账号池凭证，**顺序**逐号 GET 额度接口（简单优先，避免给服务端并发压力）。
    /// 单号 HTTP 非 2xx / 抛错 / 解码失败 → 打 warning 日志后静默跳过，不影响其余账号。
    /// 返回成功查到额度的账号列表（顺序与 scanAccounts 一致）。
    func probeAll() async -> [QoderAccountQuota] {
        let shouldRun: Bool = stateLock.withLock {
            let r = QoderPoolQuotaGuard.begin(isRunning: isRunning)
            isRunning = r.isRunning
            return r.shouldRun
        }
        guard shouldRun else {
            probeLog.info("quota probe already in flight, skipping this trigger")
            return []
        }
        defer { stateLock.withLock { isRunning = QoderPoolQuotaGuard.end() } }

        let accounts = QoderPoolCredentials.scanAccounts(in: poolDirectory)
        guard !accounts.isEmpty else {
            probeLog.info("no pool accounts found at \(self.poolDirectory.path), skip")
            return []
        }
        guard let usageURL = URL(string: "\(Self.baseURL)/api/v2/quota/usage") else { return [] }

        var results: [QoderAccountQuota] = []
        for credential in accounts {
            let resp: (status: Int, data: Data)
            do {
                resp = try await transport.request(url: usageURL, method: "GET", headers: headers(for: credential), body: nil)
            } catch {
                probeLog.warning("quota fetch threw for user \(credential.userId.prefix(8)):… \(error.localizedDescription)")
                continue
            }
            guard (200..<300).contains(resp.status) else {
                probeLog.warning("quota fetch status \(resp.status) for user \(credential.userId.prefix(8)):…")
                continue
            }
            guard let parsed = try? JSONDecoder().decode(QoderUsageResponse.self, from: resp.data),
                  let plan = parsed.userQuota?.remaining else {
                probeLog.warning("quota decode failed for user \(credential.userId.prefix(8)):…")
                continue
            }
            results.append(QoderAccountQuota(
                userId: parsed.userId ?? credential.userId,
                planRemaining: plan,
                addOnRemaining: parsed.addOnQuota?.remaining ?? 0
            ))
        }
        return results
    }
}
