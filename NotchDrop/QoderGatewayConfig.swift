//
//  QoderGatewayConfig.swift
//  NotchEvery
//
//  任务 3：qodercn-gateway 的配置目录布局 / gateway.json 生成 / authkeys 生成的纯函数层。
//  无副作用（除显式 ensureLayout），不 spawn 进程、不发网络。
//

import Foundation
import Security

/// 对齐 Go fileConfig 的网关配置文件模型。可选字段用 encodeIfPresent，未设即不写入。
struct QoderGatewayConfig: Codable {
    var host: String
    var port: Int
    var auth_keys_file: String?
    var remote_base_url: String?
    var model: String?
    var session_mode: String?
    var remote_auth_pool_dir: String?

    /// 默认账号池目录：~/.qoder-cn/pool
    static var defaultPoolDir: String? {
        let path = (NSHomeDirectory() as NSString).appendingPathComponent(".qoder-cn/pool")
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    /// 生成一份默认配置：钉死回环 host、指定端口、入站 key 白名单路径，
    /// 并按 README 硬约束钉死 remote_base_url = gateway.qoder.com.cn（自动探测会命中 lingma 旧域名），
    /// 如果本地存在 ~/.qoder-cn/pool 则自动配置账号池路径与模型。
    static func `default`(port: Int, authKeysFile: String, poolDir: String? = defaultPoolDir) -> QoderGatewayConfig {
        QoderGatewayConfig(
            host: "127.0.0.1",
            port: port,
            auth_keys_file: authKeysFile,
            remote_base_url: "https://gateway.qoder.com.cn",
            model: "Qwen3.8-Flash",
            session_mode: "auto",
            remote_auth_pool_dir: poolDir
        )
    }

    /// 生成一个符合网关字符集规则的入站 API key：仅 A-Za-z0-9-_*=+ ，长度 ≤64。
    /// 用 SecRandomCopyBytes 取随机字节映射到字符表，避免不同客户端请求头兼容问题。
    static func makeAuthKey(length: Int = 40) -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_*=+")
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            // 极端兜底：系统随机源不可用时用 UUID 派生（仍满足字符集）
            let fallback = UUID().uuidString.replacingOccurrences(of: "-", with: "")
            return String(fallback.prefix(length))
        }
        return String(bytes.map { alphabet[Int($0) % alphabet.count] })
    }

    /// 在 dir 下确保 gateway.json / authkeys / gateway.log 三件套存在；已存在的文件不覆盖（幂等）。
    /// authkeys 权限 0600（含明文 key）。
    static func ensureLayout(at dir: URL, port: Int, fileManager fm: FileManager = .default) throws {
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let jsonURL = dir.appendingPathComponent("gateway.json")
        let keysURL = dir.appendingPathComponent("authkeys")
        let logURL = dir.appendingPathComponent("gateway.log")

        // authkeys 先建（gateway.json 要引用它的路径）；已存在则保留原 key，不重生成
        if !fm.fileExists(atPath: keysURL.path) {
            let key = makeAuthKey() + "\n"
            try key.write(to: keysURL, atomically: true, encoding: .utf8)
        }
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keysURL.path)

        if !fm.fileExists(atPath: jsonURL.path) {
            let cfg = QoderGatewayConfig.default(port: port, authKeysFile: keysURL.path)
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try enc.encode(cfg)
            try data.write(to: jsonURL, options: .atomic)
        } else if let data = try? Data(contentsOf: jsonURL),
                  var cfg = try? JSONDecoder().decode(QoderGatewayConfig.self, from: data),
                  cfg.remote_auth_pool_dir == nil,
                  let pool = defaultPoolDir {
            // 已有配置文件但未开启 pool_dir，自动补上
            cfg.remote_auth_pool_dir = pool
            if cfg.model == nil { cfg.model = "Qwen3.8-Flash" }
            if cfg.session_mode == nil { cfg.session_mode = "auto" }
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let updated = try? enc.encode(cfg) {
                try? updated.write(to: jsonURL, options: .atomic)
            }
        }

        if !fm.fileExists(atPath: logURL.path) {
            fm.createFile(atPath: logURL.path, contents: Data())
        }
    }
}
