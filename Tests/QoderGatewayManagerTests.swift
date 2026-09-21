//
//  QoderGatewayManagerTests.swift
//  NotchEveryTests
//
//  任务 4：网关生命周期管理器的可测面 —— 状态机转换、陈旧 PID 路径过滤、端口健康探测。
//  全部为纯函数 / 假注入，不真起进程。
//

import Network
import XCTest
@testable import NotchEvery

final class QoderGatewayManagerTests: XCTestCase {

    // MARK: - 状态机合法转换

    func testStateMachineAllowsHappyPath() {
        var sm = GatewayStateMachine()
        XCTAssertEqual(sm.state, .stopped)
        XCTAssertTrue(sm.requestStart())      // stopped -> starting
        XCTAssertEqual(sm.state, .starting)
        XCTAssertTrue(sm.markRunning())       // starting -> running
        XCTAssertEqual(sm.state, .running)
        XCTAssertTrue(sm.requestStop())       // running -> stopping
        XCTAssertEqual(sm.state, .stopping)
        XCTAssertTrue(sm.markStopped())       // stopping -> stopped
        XCTAssertEqual(sm.state, .stopped)
    }

    func testCrashFromRunningIsAllowedAndCarriesReason() {
        var sm = GatewayStateMachine()
        _ = sm.requestStart(); _ = sm.markRunning()
        XCTAssertTrue(sm.markCrashed("启动超时"))
        if case .crashed(let reason) = sm.state {
            XCTAssertEqual(reason, "启动超时")
        } else {
            XCTFail("应为 crashed 态，实为 \(sm.state)")
        }
    }

    func testIllegalTransitionsRejected() {
        var sm = GatewayStateMachine()
        // stopped 不能直接 stop / markRunning / markStopped
        XCTAssertFalse(sm.requestStop())
        XCTAssertFalse(sm.markRunning())
        XCTAssertFalse(sm.markStopped())
        // starting 下重复 requestStart 非法
        _ = sm.requestStart()
        XCTAssertFalse(sm.requestStart())
    }

    // MARK: - 陈旧 PID 过滤：只认「可执行路径 == bundle 内网关路径」的 pid

    func testFilterPidsKeepsOnlyMatchingBinaryPath() {
        let gwPath = "/Applications/NotchEvery.app/Contents/MacOS/qodercn-gateway"
        // lsof -t 输出（每行一个 pid）+ pid→可执行路径表
        let lsofOut = "100\n200\n300\n"
        let paths: [Int: String] = [
            100: gwPath,                                  // 命中：本 App 内嵌二进制
            200: "/Users/x/ali-tools/build/qodercn-gateway", // 外部实例，绝不误伤
            300: "/usr/sbin/httpd",                       // 无关服务
        ]
        let stale = QoderGatewayManager.filterPids(lsofOut, pathsOf: paths, matching: gwPath)
        XCTAssertEqual(stale, [100], "只应返回路径完全等于内嵌网关路径的 pid")
    }

    func testFilterPidsEmptyOrGarbageInputYieldsEmpty() {
        let stale = QoderGatewayManager.filterPids("", pathsOf: [:], matching: "/x")
        XCTAssertTrue(stale.isEmpty)
        let stale2 = QoderGatewayManager.filterPids("abc\n999\n", pathsOf: [999: "/other"], matching: "/mine")
        XCTAssertTrue(stale2.isEmpty, "非数字行忽略；路径不符的不留")
    }

    // MARK: - 端口健康探测：关闭端口立即 false，占用端口 true

    func testHealthProbeFailsClosedOnClosedPort() {
        // 随机高端口几乎必然无人监听
        let closed = UInt16.random(in: 40000...49999)
        XCTAssertFalse(QoderGatewayManager.isPortOpen(host: "127.0.0.1", port: closed, timeoutMS: 200))
    }

    func testHealthProbeSucceedsOnListeningPort() throws {
        // 用 NWListener 占一个端口(on: .any 让系统分配)，验证探测返回 true
        let listener = try NWListener(using: .tcp, on: .any)
        let sem = DispatchSemaphore(value: 0)
        var boundPort: UInt16 = 0
        listener.newConnectionHandler = { (_: NWConnection) in }
        listener.stateUpdateHandler = { (state: NWListener.State) in
            if case .ready = state {
                boundPort = listener.port?.rawValue ?? 0
                sem.signal()
            }
        }
        listener.start(queue: .global())
        XCTAssertEqual(sem.wait(timeout: .now() + 2), .success, "listener 未就绪")
        defer { listener.cancel() }
        XCTAssertTrue(boundPort > 0)
        XCTAssertTrue(QoderGatewayManager.isPortOpen(host: "127.0.0.1", port: boundPort, timeoutMS: 500))
    }
}
