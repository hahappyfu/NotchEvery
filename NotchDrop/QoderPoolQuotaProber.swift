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

extension Double {
    /// 展示用安全取整：NaN / ±∞ / 负值 / 超出 Int 范围一律回落 nil。
    /// 上游 JSON 的余额是浮点且不可信（NaN、无界极端值都可能混进来），直接 `Int(value)`
    /// 会触发 Swift runtime trap（整个 App 闪退）。所有余额取整必须先过这道守卫。
    var safeCreditsInt: Int? {
        guard isFinite, self >= 0, self < Double(Int.max) else { return nil }
        return Int(self)
    }

    /// 安全取整后的展示文案：合法则数字，非法回落 `--`（与「未探测到」同一降级口径）。
    var safeCreditsText: String { safeCreditsInt.map { "\($0)" } ?? "--" }
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
/// Sendable：`refreshPoolQuotas()` 是 nonisolated async，会把本对象引用带出 MainActor 隔离域，
/// Swift 6 严格并发下要求跨隔离传递的类型必须 Sendable，否则迁移即编译失败。
///
/// 返回 Optional 是为了区分两种语义完全不同的"空"（真机 bug：第三页 Orb 环下方一直显示 `--`）：
/// - `nil` —— 本轮被 in-flight 守卫挡掉，**什么都没探**，调用方必须保持既有数据不动；
/// - `[]`（非 nil）—— 探测**确实跑完了**但一个号都没查到（如 token 全失效），调用方应以此为准清空。
/// 若两者都返回 `[]`，撞守卫的那次触发会把空数组覆盖到已有好数据上，UI 就永久回到 `--`。
protocol QoderPoolQuotaProbing: AnyObject, Sendable {
    func probeAll() async -> [QoderAccountQuota]?
}

/// 唯一可变状态 `isRunning` 由 UnfairLock 保护（见下），满足 Sendable 语义，故用 @unchecked 显式声明。
final class QoderPoolQuotaProber: QoderPoolQuotaProbing, @unchecked Sendable {
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
    /// 返回值语义见 `QoderPoolQuotaProbing`：nil = 被守卫跳过（别动现有数据）；非 nil（含 []）= 本轮探测完成。
    func probeAll() async -> [QoderAccountQuota]? {
        let shouldRun: Bool = stateLock.withLock {
            let r = QoderPoolQuotaGuard.begin(isRunning: isRunning)
            isRunning = r.isRunning
            return r.shouldRun
        }
        guard shouldRun else {
            probeLog.info("quota probe already in flight, skipping this trigger")
            return nil
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
