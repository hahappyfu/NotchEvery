import Cocoa
import Combine
import Foundation
import OrderedCollections
import os.log

private let trayLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "NotchDrop", category: "TrayDrop")

class TrayDrop: ObservableObject {
    static let shared = TrayDrop()

    var cancellables = Set<AnyCancellable>()

    @Persist(key: "keepInterval", defaultValue: 3600 * 24)
    var keepInterval: TimeInterval

    private init() {
        Publishers.CombineLatest3(
            $selectedFileStorageTime.removeDuplicates(),
            $customStorageTime.removeDuplicates(),
            $customStorageTimeUnit.removeDuplicates()
        )
        .map { selectedFileStorageTime, customStorageTime, customStorageTimeUnit in
            let customTime = switch customStorageTimeUnit {
            case .hours:
                TimeInterval(customStorageTime) * 60 * 60
            case .days:
                TimeInterval(customStorageTime) * 60 * 60 * 24
            case .weeks:
                TimeInterval(customStorageTime) * 60 * 60 * 24 * 7
            case .months:
                TimeInterval(customStorageTime) * 60 * 60 * 24 * 30
            case .years:
                TimeInterval(customStorageTime) * 60 * 60 * 24 * 365
            }
            let ans = selectedFileStorageTime.toTimeInterval(customTime: customTime)
            trayLog.info("using interval \(ans) to keep files")
            return ans
        }
        .receive(on: DispatchQueue.main)
        .sink { [weak self] output in
            self?.keepInterval = output
        }
        .store(in: &cancellables)
    }

    var isEmpty: Bool { items.isEmpty }

    @PublishedPersist(key: "TrayDropItems", defaultValue: .init())
    var items: OrderedSet<DropItem>

    @PublishedPersist(key: "selectedFileStorageTime", defaultValue: .oneDay)
    var selectedFileStorageTime: FileStorageTime

    @PublishedPersist(key: "customStorageTime", defaultValue: 1)
    var customStorageTime: Int

    @PublishedPersist(key: "customStorageTimeUnit", defaultValue: .days)
    var customStorageTimeUnit: CustomStorageTimeUnit

    @Published var isLoading: Int = 0

    // ——— 修复 #2/#7: 主线程死锁 + 单文件失败丢整批 ———
    func load(_ providers: [NSItemProvider]) {
        // 主线程安全：不再用 asyncAndWait
        func bumpLoading(_ delta: Int) {
            if Thread.isMainThread {
                isLoading += delta
            } else {
                DispatchQueue.main.sync { isLoading += delta }
            }
        }
        bumpLoading(1)

        guard let urls = providers.interfaceConvert() else {
            bumpLoading(-1)
            return
        }
        // 逐个尝试，失败项收集，成功项保留（修复 #7）
        var succeeded: [DropItem] = []
        var failures: [Error] = []
        var tempURLsToClean: [URL] = []
        for url in urls {
            do {
                let item = try DropItem(url: url)
                succeeded.append(item)
            } catch {
                failures.append(error)
                tempURLsToClean.append(url)
            }
        }
        // 清理失败项对应的临时拷贝
        for u in tempURLsToClean { try? FileManager.default.removeItem(at: u) }

        if succeeded.isEmpty, !failures.isEmpty {
            DispatchQueue.main.async {
                bumpLoading(-1)
                if let first = failures.first { NSAlert.popError(first) }
            }
            return
        }
        DispatchQueue.main.async {
            // 一次性迁移旧数据到外置预览文件（迁移失败则该条丢弃，不拖累整批）
            var migrated: [DropItem] = []
            for item in succeeded {
                var copy = item
                if copy.migratePreviewIfNeeded() { migrated.append(copy) }
            }
            // 批量收集后一次赋值：不再逐条 updateOrInsert（每条都触发一次全量持久化 = 卡顿主因）
            var newSet = self.items
            for item in migrated {
                if let idx = newSet.firstIndex(where: { $0.id == item.id }) {
                    newSet.remove(at: idx)
                }
                newSet.insert(item, at: 0)
            }
            // ——— 修复 #18: 限容 100，最老优先淘汰（文件删除集中处理，不再逐条触发持久化）———
            let maxItems = 100
            if newSet.count > maxItems {
                let overflow = newSet.count - maxItems
                let oldest = newSet.sorted(by: { $0.copiedDate < $1.copiedDate }).prefix(overflow)
                for o in oldest {
                    self.removeFiles(of: o)
                }
                let oldestIDs = Set(oldest.map(\.id))
                newSet.removeAll { oldestIDs.contains($0.id) }
                trayLog.info("capacity trimmed \(overflow) items")
            }
            self.items = newSet
            bumpLoading(-1)
            if !failures.isEmpty {
                trayLog.error("load: \(failures.count) of \(urls.count) items failed")
            }
        }
        if !failures.isEmpty, !succeeded.isEmpty {
            // 部分失败也提示
            DispatchQueue.main.async {
                NSAlert.popError(NSError(domain: "NotchDrop", code: 6, userInfo: [NSLocalizedDescriptionKey: String(format: NSLocalizedString("%d of %d files failed to import", comment: ""), failures.count, urls.count)]))
            }
        }
    }

    func cleanExpiredFiles() {
        var inEdit = items
        let shouldCleanItems = items.filter(\.shouldClean)
        for item in shouldCleanItems {
            inEdit.remove(item)
        }
        items = inEdit
    }

    func delete(_ item: DropItem.ID) {
        guard let item = items.first(where: { $0.id == item }) else { return }
        delete(item: item)
    }

    /// 仅清理文件与空父目录，不触碰 items（供批量删除复用，避免逐条触发持久化）
    private func removeFiles(of item: DropItem) {
        var url = item.storageURL
        try? FileManager.default.removeItem(at: url)

        do {
            // loops up to the main directory
            url = url.deletingLastPathComponent()
            while url.lastPathComponent != DropItem.mainDir, url != documentsDirectory {
                let contents = try FileManager.default.contentsOfDirectory(atPath: url.path)
                guard contents.isEmpty else { break }
                try FileManager.default.removeItem(at: url)
                url = url.deletingLastPathComponent()
            }
        } catch {}
    }

    private func delete(item: DropItem) {
        var inEdit = items
        removeFiles(of: item)
        inEdit.remove(item)
        items = inEdit
    }

    func removeAll() {
        // 先删文件再一次清空：避免逐条删除触发 N 次全量持久化
        items.forEach { removeFiles(of: $0) }
        items = []
    }
}

extension TrayDrop {
    enum FileStorageTime: String, CaseIterable, Identifiable, Codable {
        case oneHour = "1 Hour"
        case oneDay = "1 Day"
        case twoDays = "2 Days"
        case threeDays = "3 Days"
        case oneWeek = "1 Week"
        case never = "Forever"
        case custom = "Custom"

        var id: String { rawValue }

        var localized: String {
            NSLocalizedString(rawValue, comment: "")
        }

        func toTimeInterval(customTime: TimeInterval) -> TimeInterval {
            switch self {
            case .oneHour:
                60 * 60
            case .oneDay:
                60 * 60 * 24
            case .twoDays:
                60 * 60 * 24 * 2
            case .threeDays:
                60 * 60 * 24 * 3
            case .oneWeek:
                60 * 60 * 24 * 7
            case .never:
                TimeInterval.infinity
            case .custom:
                customTime
            }
        }
    }

    enum CustomStorageTimeUnit: String, CaseIterable, Identifiable, Codable {
        case hours = "Hours"
        case days = "Days"
        case weeks = "Weeks"
        case months = "Months"
        case years = "Years"

        var id: String { rawValue }

        var localized: String {
            NSLocalizedString(rawValue, comment: "")
        }
    }
}
