//
//  QoderCampaignClaimer.swift
//  NotchEvery
//
//  任务 4：Qoder「每天登录领 100 Credits」活动自动领取。扫描本地账号池凭证文件，
//  逐个走 GET /sash/api/v1/me/campaigns + POST .../claim 两步协议（协议细节已在真实环境验证）。
//  网络经 QoderCampaignTransport 注入（单测用假实现，绝不真联网）；单账号失败只记日志跳过，不影响其它账号。
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

/// 默认实现：URLSession，30s 超时。
struct URLSessionQoderCampaignTransport: QoderCampaignTransport {
    func request(url: URL, method: String, headers: [String: String], body: Data?) async throws -> (status: Int, data: Data) {
        var req = URLRequest(url: url, timeoutInterval: 30)
        req.httpMethod = method
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        req.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        return (status, data)
    }
}

// MARK: - 账号池凭证

/// ~/.qoder-cn/pool/account_<uuid>.json 里我们关心的三个字段（其余忽略）。
struct QoderPoolAccountCredential: Equatable {
    let accessToken: String
    let machineId: String
    let userId: String

    private struct Raw: Decodable {
        struct Auth: Decodable {
            let access_token: String?
            let machine_id: String?
            let user_id: String?
        }
        let auth: Auth?
    }

    static func decode(_ data: Data) -> QoderPoolAccountCredential? {
        guard let raw = try? JSONDecoder().decode(Raw.self, from: data), let auth = raw.auth,
              let token = auth.access_token, !token.isEmpty,
              let machineId = auth.machine_id, !machineId.isEmpty,
              let userId = auth.user_id, !userId.isEmpty
        else { return nil }
        return QoderPoolAccountCredential(accessToken: token, machineId: machineId, userId: userId)
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

enum QoderClaimOutcome: Equatable {
    case claimed                      // 本次新领到
    case alreadyClaimed               // replayed==true，今天之前已领过，幂等，不算错误
    case nothingToClaim               // 列表里没有可领项
    case failure(String)              // 带原因的失败（token 失效 / 网络异常 / 解码失败等）
}

// MARK: - Claimer

final class QoderCampaignClaimer {
    static let shared = QoderCampaignClaimer()

    private let transport: QoderCampaignTransport
    private let poolDirectory: URL
    /// 当天去重存储（UserDefaults 持久化，App 重启不重复刷；测试可注入独立 suite 隔离）
    private let defaults: UserDefaults
    private let now: () -> Date

    init(transport: QoderCampaignTransport = URLSessionQoderCampaignTransport(),
         poolDirectory: URL? = nil,
         defaults: UserDefaults? = nil,
         now: @escaping () -> Date = Date.init) {
        self.transport = transport
        if let d = poolDirectory {
            self.poolDirectory = d
        } else {
            self.poolDirectory = URL(fileURLWithPath: (NSHomeDirectory() as NSString).appendingPathComponent(".qoder-cn/pool"))
        }
        self.defaults = defaults ?? .standard
        self.now = now
    }

    // MARK: 扫描

    /// 读取 poolDirectory 下所有 account_*.json，解析出凭证列表（解析失败的静默跳过）。
    func scanAccounts(fileManager fm: FileManager = .default) -> [QoderPoolAccountCredential] {
        guard let names = try? fm.contentsOfDirectory(atPath: poolDirectory.path) else { return [] }
        return names.filter { $0.hasPrefix("account_") && $0.hasSuffix(".json") }.sorted().compactMap { name in
            let url = poolDirectory.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url) else { return nil }
            return QoderPoolAccountCredential.decode(data)
        }
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

        // 步骤 2：逐条领取（一个账号可能有多条可领）
        var didClaimNew = false
        for id in ids {
            guard let claimURL = URL(string: "\(Self.baseURL)/sash/api/v1/me/campaigns/\(id)/claim") else { continue }
            let claimResp: (status: Int, data: Data)
            do {
                claimResp = try await transport.request(url: claimURL, method: "POST", headers: headers(for: credential, contentType: true), body: Data("{}".utf8))
            } catch {
                claimLog.warning("claim \(id) threw for user \(credential.userId): \(error.localizedDescription)")
                continue   // 单条失败不影响该账号其它条目
            }
            guard (200..<300).contains(claimResp.status) else {
                claimLog.warning("claim \(id) status \(claimResp.status) for user \(credential.userId)")
                continue
            }
            let parsed = try? JSONDecoder().decode(QoderClaimResponse.self, from: claimResp.data)
            if parsed?.status == "CLAIMED" {
                if parsed?.replayed == true {
                    // 幂等重放：今天之前已领过，静默跳过
                } else {
                    didClaimNew = true
                }
            }
        }
        return didClaimNew ? .claimed : .alreadyClaimed
    }

    // MARK: 每日一次主入口

    /// 遍历账号池，跳过「今天已成功处理过」的账号，顺序领取（简单优先，避免给服务端并发压力）。
    /// 成功/幂等/无可领都算「今天处理过了」；只有真正的网络/权限失败才留待下次触发重试。
    func claimAllOncePerDay() async {
        let accounts = scanAccounts()
        guard !accounts.isEmpty else {
            claimLog.info("no pool accounts found at \(self.poolDirectory.path), skip")
            return
        }
        let today = Self.dayString(now())
        for credential in accounts {
            let key = "qoder.campaign.claimed.\(credential.userId)"
            if defaults.string(forKey: key) == today { continue }   // 今天已处理过
            let outcome = await claim(for: credential)
            switch outcome {
            case .claimed:
                defaults.set(today, forKey: key)
                claimLog.info("user \(credential.userId.prefix(8)):… claimed credits today")
            case .alreadyClaimed, .nothingToClaim:
                defaults.set(today, forKey: key)
                claimLog.info("user \(credential.userId.prefix(8)):… outcome=\(outcome.isNoRetryNeededDescription)")
            case .failure(let reason):
                claimLog.warning("user \(credential.userId.prefix(8)):… failed: \(reason)")
            }
        }
    }

    private static func dayString(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: d)
    }
}

private extension QoderClaimOutcome {
    var isNoRetryNeededDescription: String {
        switch self {
        case .alreadyClaimed: return "already-claimed(replayed)"
        case .nothingToClaim: return "nothing-to-claim"
        default: return "unexpected"
        }
    }
}
