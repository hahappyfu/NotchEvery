//
//  QoderPoolCredentials.swift
//  NotchEvery
//
//  账号池凭证的共享定义：从 QoderCampaignClaimer 提取，供 claimer 与 QoderPoolQuotaProber 复用，
//  避免两处各自维护一份解析逻辑导致口径漂移。
//

import Foundation

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

// MARK: - 共享扫描

enum QoderPoolCredentials {
    /// 默认 pool 目录：~/.qoder-cn/pool
    static var defaultDirectory: URL {
        URL(fileURLWithPath: (NSHomeDirectory() as NSString).appendingPathComponent(".qoder-cn/pool"))
    }

    /// 读取 directory 下所有 account_*.json，解析出凭证列表（文件名排序保证顺序稳定，解析失败的静默跳过）。
    static func scanAccounts(in directory: URL, fileManager fm: FileManager = .default) -> [QoderPoolAccountCredential] {
        guard let names = try? fm.contentsOfDirectory(atPath: directory.path) else { return [] }
        return names.filter { $0.hasPrefix("account_") && $0.hasSuffix(".json") }.sorted().compactMap { name in
            let url = directory.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url) else { return nil }
            return QoderPoolAccountCredential.decode(data)
        }
    }
}
