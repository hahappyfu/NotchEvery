//
//  QuotaStore.swift
//  NotchEvery
//
//  额度轮询：读本机 bridge 缓存 → 归一化 → 主线程发布。纯观察者，不碰网络。
//

import Combine
import Foundation
import os.log

private let quotaLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "NotchEvery", category: "QuotaStore")

final class QuotaStore: ObservableObject {
    static let shared = QuotaStore()

    @Published private(set) var snapshot: QuotaSnapshot = .empty

    /// 用 libc 直取真实家目录（不经过沙盒重定向的 Foundation 家目录 API）
    static let cacheURL: URL = {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir))
                .appendingPathComponent(".clawd/opencode-go-bridge-cache.json")
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".clawd/opencode-go-bridge-cache.json")
    }()

    private let interval: TimeInterval
    private var timer: Timer?

    init(interval: TimeInterval = 30) {
        self.interval = interval
    }

    func start() {
        guard timer == nil else { return }
        refresh()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        quotaLog.info("QuotaStore started, interval \(self.interval)s")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

#if DEBUG
    /// 预览/调试用：直接灌快照（绕过文件读取）
    func seedForPreview(_ snapshot: QuotaSnapshot) {
        self.snapshot = snapshot
    }
#endif

    func refresh() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let data = try? Data(contentsOf: Self.cacheURL)
            let next = data.map { QuotaSnapshot.normalize($0, now: Date()) }
            DispatchQueue.main.async { [weak self] in
                guard let self, let next else { return }
                self.snapshot = next
                quotaLog.info("quota refresh: available=\(next.available) expired=\(next.expired) windows=\(next.windows.count)")
            }
        }
    }
}
