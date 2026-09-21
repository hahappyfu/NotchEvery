//
//  QoderGatewayConfigTests.swift
//  NotchEveryTests
//
//  任务 3：网关配置目录布局 / gateway.json / authkeys 生成 的纯函数层测试。
//

import XCTest
@testable import NotchEvery

final class QoderGatewayConfigTests: XCTestCase {

    // MARK: - default(port:) 生成的 JSON 对齐 Go fileConfig 契约

    func testDefaultJSONUsesGivenPortAndHostLoopback() throws {
        let cfg = QoderGatewayConfig.default(port: 8096, authKeysFile: "/tmp/k")
        let data = try JSONEncoder().encode(cfg)
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(obj["port"] as? Int, 8096)
        XCTAssertEqual(obj["host"] as? String, "127.0.0.1")
        XCTAssertNotNil(obj["auth_keys_file"], "必须钉死入站 key 白名单路径")
    }

    func testDefaultDoesNotPinRemoteAuthFile() throws {
        // 上游凭证走本地 CLI 缓存 => 配置里不写 remote_auth_file
        let cfg = QoderGatewayConfig.default(port: 8096, authKeysFile: "/tmp/k")
        let data = try JSONEncoder().encode(cfg)
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertNil(obj["remote_auth_file"])
    }

    func testDefaultPinsCorrectRemoteBaseURL() throws {
        // README 硬约束：默认自动探测会命中 lingma 旧域名，必须钉死 gateway.qoder.com.cn
        let cfg = QoderGatewayConfig.default(port: 8096, authKeysFile: "/tmp/k")
        let data = try JSONEncoder().encode(cfg)
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(obj["remote_base_url"] as? String, "https://gateway.qoder.com.cn")
    }

    func testDefaultConfiguresPoolDirWhenProvided() throws {
        let cfg = QoderGatewayConfig.default(port: 8096, authKeysFile: "/tmp/k", poolDir: "/custom/pool")
        let data = try JSONEncoder().encode(cfg)
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(obj["remote_auth_pool_dir"] as? String, "/custom/pool")
        XCTAssertEqual(obj["model"] as? String, "Qwen3.8-Flash")
        XCTAssertEqual(obj["session_mode"] as? String, "auto")
    }

    // MARK: - authkey 字符集规则（README：≤64 且仅 A-Za-z0-9-_*=+）

    func testGeneratedAuthKeySatisfiesGatewayCharsetRule() {
        let key = QoderGatewayConfig.makeAuthKey()
        XCTAssertFalse(key.isEmpty)
        XCTAssertLessThanOrEqual(key.count, 64)
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_*=+")
        XCTAssertTrue(key.unicodeScalars.allSatisfy { allowed.contains($0) },
                      "authkey 含非法字符会被网关启动时拒绝: \(key)")
    }

    func testGeneratedAuthKeysAreDistinct() {
        let a = QoderGatewayConfig.makeAuthKey()
        let b = QoderGatewayConfig.makeAuthKey()
        XCTAssertNotEqual(a, b, "两次生成不应相同（随机源）")
    }

    // MARK: - ensureLayout 幂等创建三件套

    func testEnsureLayoutCreatesMissingFilesOnly() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("qgw-cfg-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }

        // 首次：应创建 gateway.json / authkeys / gateway.log
        try QoderGatewayConfig.ensureLayout(at: dir, port: 8096)
        let fm = FileManager.default
        XCTAssertTrue(fm.fileExists(atPath: dir.appendingPathComponent("gateway.json").path))
        XCTAssertTrue(fm.fileExists(atPath: dir.appendingPathComponent("authkeys").path))
        XCTAssertTrue(fm.fileExists(atPath: dir.appendingPathComponent("gateway.log").path))

        // authkeys 权限 0600
        let attrs = try fm.attributesOfItem(atPath: dir.appendingPathComponent("authkeys").path)
        let perm = (attrs[.posixPermissions] as? NSNumber)?.int16Value ?? -1
        XCTAssertEqual(perm & 0o777, 0o600, "authkeys 含明文 key，权限必须 0600")

        // 幂等：再次调用不得覆盖已有 authkeys（读回内容应一致）
        let before = try String(contentsOf: dir.appendingPathComponent("authkeys"), encoding: .utf8)
        try QoderGatewayConfig.ensureLayout(at: dir, port: 8096)
        let after = try String(contentsOf: dir.appendingPathComponent("authkeys"), encoding: .utf8)
        XCTAssertEqual(before, after, "ensureLayout 对已存在文件必须幂等、不重生成 key")
    }
}
