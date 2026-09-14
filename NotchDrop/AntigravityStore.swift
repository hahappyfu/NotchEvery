//
//  AntigravityStore.swift
//  NotchEvery
//
//  Antigravity 账号与配额数据轮询：读取 ~/.antigravity_tools 本地文件 → 归一化 → 主线程发布。
//  纯本地文件操作，不发网络请求。
//

import Combine
import Foundation
import os.log

private let antigravityLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "NotchEvery", category: "AntigravityStore")

// MARK: - Models

public struct AntigravityAccount: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let email: String
    public let isCurrent: Bool
    public let isDisabled: Bool
    public let percentage: Int
    public let resetTime: Date?

    public init(
        id: String,
        name: String,
        email: String,
        isCurrent: Bool,
        isDisabled: Bool,
        percentage: Int,
        resetTime: Date?
    ) {
        self.id = id
        self.name = name
        self.email = email
        self.isCurrent = isCurrent
        self.isDisabled = isDisabled
        self.percentage = percentage
        self.resetTime = resetTime
    }
}

public struct AntigravityIndex: Equatable {
    public let currentAccountId: String?
    public let accountIds: [String]

    public init(currentAccountId: String?, accountIds: [String]) {
        self.currentAccountId = currentAccountId
        self.accountIds = accountIds
    }
}

// MARK: - Store

public final class AntigravityStore: ObservableObject {
    public static let shared = AntigravityStore()

    @Published public private(set) var accounts: [AntigravityAccount] = []
    @Published public private(set) var currentAccountId: String?

    public static let baseDirectory: URL = {
        let base: URL
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            base = URL(fileURLWithPath: String(cString: dir))
        } else {
            base = FileManager.default.homeDirectoryForCurrentUser
        }
        return base.appendingPathComponent(".antigravity_tools")
    }()

    private let baseDir: URL
    private let interval: TimeInterval
    private var timer: Timer?
    private var isRefreshing = false

    public init(baseDir: URL = AntigravityStore.baseDirectory, interval: TimeInterval = 10) {
        self.baseDir = baseDir
        self.interval = interval
    }

    public func start() {
        guard timer == nil else { return }
        refresh()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        antigravityLog.info("AntigravityStore started, interval \(self.interval)s")
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    public func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        let dir = baseDir

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let (newAccounts, currentId) = Self.loadAccounts(from: dir)

            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isRefreshing = false
                if self.accounts != newAccounts {
                    self.accounts = newAccounts
                }
                if self.currentAccountId != currentId {
                    self.currentAccountId = currentId
                }
            }
        }
    }

    // MARK: - Static Parsers & Helpers

    public static func loadAccounts(from directory: URL) -> ([AntigravityAccount], String?) {
        let indexFile = directory.appendingPathComponent("accounts.json")
        guard let indexData = try? Data(contentsOf: indexFile),
              let index = parseIndex(data: indexData) else {
            return ([], nil)
        }

        let accountsDir = directory.appendingPathComponent("accounts")
        var result: [AntigravityAccount] = []

        for accId in index.accountIds {
            let fileURL = accountsDir.appendingPathComponent("\(accId).json")
            guard let data = try? Data(contentsOf: fileURL),
                  let account = parseAccountFile(data: data, currentAccountId: index.currentAccountId) else {
                continue
            }
            result.append(account)
        }

        return (result, index.currentAccountId)
    }

    public static func parseIndex(data: Data) -> AntigravityIndex? {
        struct RawIndex: Decodable {
            let current_account_id: String?
            let accounts: [RawAccountItem]?

            struct RawAccountItem: Decodable {
                let id: String
            }
        }

        guard let raw = try? JSONDecoder().decode(RawIndex.self, from: data) else {
            return nil
        }

        let ids = raw.accounts?.compactMap { $0.id } ?? []
        return AntigravityIndex(currentAccountId: raw.current_account_id, accountIds: ids)
    }

    public static func parseAccountFile(data: Data, currentAccountId: String?) -> AntigravityAccount? {
        struct RawAccount: Decodable {
            let id: String
            let name: String?
            let email: String?
            let disabled: Bool?
            let proxy_disabled: Bool?
            let quota: RawQuota?

            struct RawQuota: Decodable {
                let models: [RawModel]?
            }

            struct RawModel: Decodable {
                let name: String?
                let percentage: Int?
                let reset_time: String?
            }
        }

        guard let raw = try? JSONDecoder().decode(RawAccount.self, from: data) else {
            return nil
        }

        let id = raw.id
        let email = raw.email ?? ""
        let name = (raw.name?.isEmpty == false) ? raw.name! : (!email.isEmpty ? email : id)
        let isCurrent = (id == currentAccountId)
        let isDisabled = (raw.disabled == true) || (raw.proxy_disabled == true)

        // 提取配额模型（优先选择包含 gemini 的共享模型，否则取第一个模型）
        var selectedModel: RawAccount.RawModel?
        if let models = raw.quota?.models, !models.isEmpty {
            selectedModel = models.first { ($0.name ?? "").lowercased().contains("gemini") } ?? models.first
        }

        let rawPercentage = selectedModel?.percentage ?? 0
        let percentage = min(100, max(0, rawPercentage))

        var resetDate: Date?
        if let resetStr = selectedModel?.reset_time {
            resetDate = parseISO8601(resetStr)
        }

        return AntigravityAccount(
            id: id,
            name: name,
            email: email,
            isCurrent: isCurrent,
            isDisabled: isDisabled,
            percentage: percentage,
            resetTime: resetDate
        )
    }

    public static func formatCountdown(from resetTime: Date?, now: Date = Date()) -> String {
        guard let resetTime = resetTime else { return "已就绪" }
        let diff = resetTime.timeIntervalSince(now)
        guard diff > 0 else { return "已就绪" }

        let seconds = Int(diff)
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60

        if hours > 0 {
            return "\(hours)h\(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "已就绪"
        }
    }

    private static func parseISO8601(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: string) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string)
    }
}
