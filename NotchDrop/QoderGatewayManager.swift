//
//  QoderGatewayManager.swift
//  NotchEvery
//
//  任务 4：qodercn-gateway 进程生命周期管理器 —— 状态机 + spawn/kill + 陈旧实例清扫 + 端口健康探测。
//  设计要点：
//   - 只杀「可执行路径 == bundle 内嵌网关路径」的占用进程，绝不误伤外部实例。
//   - spawn 时保持 stdin 管道写端常开；Go 侧 notchevery-patch 在写端关闭(父死)时自尽，防孤儿。
//   - 对外 API 主线程；IO / 探活在 utility queue，状态发布回主线程。参考 AntigravityStore 的 Timer/去重风格。
//

import Combine
import Foundation
import Network
import os.log

private let gwLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "NotchEvery", category: "QoderGateway")

// MARK: - 状态机（纯逻辑，可脱离真进程单测）

enum GatewayState: Equatable {
    case stopped
    case starting
    case running
    case stopping
    case crashed(reason: String)
}

/// 显式转换表：非法转换返回 false 且不改状态。集中管理避免 Manager 里散落 if。
struct GatewayStateMachine {
    private(set) var state: GatewayState = .stopped

    mutating func requestStart() -> Bool {
        guard case .stopped = state else { return false }
        state = .starting; return true
    }
    mutating func markRunning() -> Bool {
        guard case .starting = state else { return false }
        state = .running; return true
    }
    mutating func requestStop() -> Bool {
        guard case .running = state else { return false }
        state = .stopping; return true
    }
    mutating func markStopped() -> Bool {
        guard case .stopping = state else { return false }
        state = .stopped; return true
    }
    /// starting/running/stopping 都可能崩到 crashed；stopped 不再崩。
    mutating func markCrashed(_ reason: String) -> Bool {
        switch state {
        case .stopped: return false
        default: state = .crashed(reason: reason); return true
        }
    }
    /// crashed → stopped（用户点重试前先归位）。
    mutating func resetToStopped() -> Bool {
        guard case .crashed = state else { return false }
        state = .stopped; return true
    }
}

// MARK: - Manager

final class QoderGatewayManager: ObservableObject {
    static let shared = QoderGatewayManager()

    @Published private(set) var state: GatewayState = .stopped

    /// 测试期默认端口；来自 gateway.json，逻辑不硬编码。
    private(set) var port: Int = 8096

    /// App 退出钩子：优雅停掉托管的网关进程（AppDelegate.applicationWillTerminate 调）。
    @MainActor
    func applicationWillTerminate() {
        if case .running = sm.state { stop() }
        else { stdinWriteEnd?.closeFile(); stdinWriteEnd = nil }
    }

    private var sm = GatewayStateMachine()
    private var process: Process?
    /// 看门狗通道：stdin 写端持有不关；主动 stop 前会先关它触发 Go 侧优雅自尽。
    private var stdinWriteEnd: FileHandle?
    private let dataDir: URL
    private let fm: FileManager

    /// bundle 内嵌网关二进制的绝对路径（清扫比对基准）。
    static var embeddedBinaryPath: String {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/qodercn-gateway")
            .path
    }

    /// gateway.log 落盘路径（Store 增量 tailer 消费）。
    var gatewayLogURL: URL { dataDir.appendingPathComponent("gateway.log") }

    /// 本 App 是否真正托管着运行中的网关进程（crashed/stopped 时为 false → Store 显示离线空态）。
    var isHosting: Bool {
        if case .running = state { return process?.isRunning ?? false }
        return false
    }

    init(dataDir: URL? = nil, fm: FileManager = .default) {
        self.fm = fm
        if let d = dataDir {
            self.dataDir = d
        } else {
            let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
            self.dataDir = base.appendingPathComponent("NotchEvery/qoder-gateway")
        }
    }

    // MARK: 纯函数（单测覆盖）

    /// 从 lsof -t 文本中挑出可执行路径完全等于内嵌网关路径的 pid。非数字行忽略。
    static func filterPids(_ lsofOutput: String, pathsOf: [Int: String], matching gwPath: String) -> [Int] {
        lsofOutput
            .split(whereSeparator: { !$0.isNumber })
            .compactMap { Int($0) }
            .filter { pathsOf[$0] == gwPath }
    }

    /// TCP 连接探测端口是否可达（同步、短超时）。关闭端口立即 false。
    static func isPortOpen(host: String, port: UInt16, timeoutMS: Int) -> Bool {
        let conn = NWConnection(host: NWEndpoint.Host(host),
                                port: NWEndpoint.Port(rawValue: port) ?? 0, using: .tcp)
        defer { conn.cancel() }
        let sem = DispatchSemaphore(value: 0)
        var open = false
        conn.stateUpdateHandler = { s in
            switch s {
            case .ready: open = true; sem.signal()
            case .failed, .cancelled: sem.signal()
            default: break
            }
        }
        conn.start(queue: .global(qos: .utility))
        _ = sem.wait(timeout: .now() + Double(timeoutMS) / 1000.0)
        conn.stateUpdateHandler = nil
        return open
    }

    // MARK: 生命周期（真机冒烟验收，不在单测范围）

    /// crashed → stopped 归位（UI「重试」按钮先调它再 start()，否则 requestStart 被非法态挡掉变死按钮）。
    @MainActor
    func retry() {
        guard sm.resetToStopped() else { return }
        publishState()
        start()
    }

    @MainActor
    func start() {
        guard sm.requestStart() else { gwLog.info("start ignored, state=\(String(describing: self.sm.state))"); return }
        publishState()

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            do {
                try QoderGatewayConfig.ensureLayout(at: self.dataDir, port: self.port, fileManager: self.fm)
            } catch {
                self.failCrash("配置初始化失败: \(error.localizedDescription)")
                return
            }

            // 端口占用检测 → 若被「本 App 旧实例」占则清扫，被外部占则报错不动手
            if Self.isPortOpen(host: "127.0.0.1", port: UInt16(self.port), timeoutMS: 300) {
                let stale = self.staleOwnPIDs()
                if stale.isEmpty {
                    self.failCrash("端口 \(self.port) 被外部实例占用")
                    return
                }
                for pid in stale { self.terminate(pid: Int32(pid)) }
                if Self.isPortOpen(host: "127.0.0.1", port: UInt16(self.port), timeoutMS: 500) {
                    self.failCrash("端口 \(self.port) 占用未释放")
                    return
                }
            }

            self.spawnAndWatch()
        }
    }

    private func spawnAndWatch() {
        let binPath = Self.embeddedBinaryPath
        guard fm.isExecutableFile(atPath: binPath) else {
            failCrash("内嵌网关二进制缺失: \(binPath)")
            return
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: binPath)
        p.arguments = ["--config", dataDir.appendingPathComponent("gateway.json").path]

        // stdin 管道：写端由本类持有不关，作为父死看门狗通道
        let stdinPipe = Pipe()
        p.standardInput = stdinPipe
        stdinWriteEnd = stdinPipe.fileHandleForWriting

        // stdout/stderr 追写 gateway.log（异步排干防管道满阻塞子进程）
        let logURL = dataDir.appendingPathComponent("gateway.log")
        let outPipe = Pipe(); p.standardOutput = outPipe
        let errPipe = Pipe(); p.standardError = errPipe
        drain(outPipe.fileHandleForReading, to: logURL)
        drain(errPipe.fileHandleForReading, to: logURL)

        p.terminationHandler = { [weak self] proc in
            guard let self else { return }
            DispatchQueue.main.async {
                // 主动 stop 路径下 state 已是 stopping→stopped，不判 crash
                if case .stopping = self.sm.state {
                    _ = self.sm.markStopped(); self.publishState()
                    QoderStore.shared.resetToOffline()
                } else if case .running = self.sm.state {
                    self.sm.resetToStopped(); _ = self.sm.markCrashed("进程意外退出 rc=\(proc.terminationStatus)"); self.publishState()
                    QoderStore.shared.resetToOffline()
                } else if case .starting = self.sm.state {
                    self.sm.resetToStopped(); _ = self.sm.markCrashed("启动即退出 rc=\(proc.terminationStatus)"); self.publishState()
                    QoderStore.shared.resetToOffline()
                }
                self.process = nil
            }
        }

        do {
            try p.run()
        } catch {
            failCrash("spawn 失败: \(error.localizedDescription)")
            return
        }
        process = p

        // 健康轮询：在当前 utility 后台线程中每 250ms 探活，10s 超时（不依赖 RunLoop）
        let deadline = Date().addingTimeInterval(10)
        var started = false
        while Date() < deadline {
            if Self.isPortOpen(host: "127.0.0.1", port: UInt16(self.port), timeoutMS: 200) {
                started = true
                break
            }
            usleep(250_000)
        }

        if started {
            DispatchQueue.main.async {
                _ = self.sm.markRunning()
                self.publishState()
                gwLog.info("gateway running on :\(self.port) pid=\(p.processIdentifier)")
                // 启动成功立即触发一次数据层刷新，避免用户干等 15s 轮询周期
                QoderStore.shared.refresh(logURL: self.gatewayLogURL)
            }
        } else {
            self.terminate(pid: p.processIdentifier)
            self.failCrash("启动超时（10s 未监听 \(self.port)）")
        }
    }

    @MainActor
    func stop() {
        guard sm.requestStop() else { return }
        publishState()
        // 先看门狗通道优雅关（Go 侧读 EOF → SIGTERM 流程），再兜底信号
        stdinWriteEnd?.closeFile()
        stdinWriteEnd = nil
        if let p = process, p.isRunning {
            terminate(pid: p.processIdentifier)
        } else {
            _ = sm.markStopped(); publishState()
            QoderStore.shared.resetToOffline()
        }
    }

    /// SIGTERM，3s 未退 SIGKILL。
    private func terminate(pid: Int32) {
        kill(pid, SIGTERM)
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 3) {
            if kill(pid, 0) == 0 { kill(pid, SIGKILL) }
        }
    }

    /// 列出占用本端口、且可执行路径 == 内嵌网关路径的陈旧 pid。
    private func staleOwnPIDs() -> [Int] {
        let out = shell("/usr/sbin/lsof", ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN", "-t"])
        var paths: [Int: String] = [:]
        for pid in out.split(whereSeparator: { !$0.isNumber }).compactMap({ Int($0) }) {
            paths[pid] = procPath(pid)
        }
        return Self.filterPids(out, pathsOf: paths, matching: Self.embeddedBinaryPath)
    }

    private func procPath(_ pid: Int) -> String? {
        shell("/bin/ps", ["-p", "\(pid)", "-o", "comm="]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func drain(_ handle: FileHandle, to url: URL) {
        DispatchQueue.global(qos: .background).async {
            while true {
                let data = (try? handle.read(upToCount: 4096)) ?? Data()
                if data.isEmpty { break }
                if let fh = try? FileHandle(forWritingTo: url) {
                    fh.seekToEndOfFile(); fh.write(data); try? fh.close()
                }
            }
        }
    }

    private func shell(_ exe: String, _ args: [String]) -> String {
        let p = Process(); p.executableURL = URL(fileURLWithPath: exe); p.arguments = args
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
        do { try p.run() } catch { return "" }
        p.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    private func failCrash(_ reason: String) {
        DispatchQueue.main.async {
            _ = self.sm.markCrashed(reason); self.publishState()
            gwLog.error("gateway crashed: \(reason)")
        }
    }

    @MainActor private func publishState() { state = sm.state }
}
