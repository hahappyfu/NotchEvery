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
    var customStorageTimeUnit: CustomstorageTimeUnit

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
            succeeded.forEach { self.items.updateOrInsert($0, at: 0) }
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

    private func delete(item: DropItem) {
        var inEdit = items

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

        inEdit.remove(item)
        items = inEdit
    }

    func removeAll() {
        items.forEach { delete(item: $0) }
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

    enum CustomstorageTimeUnit: String, CaseIterable, Identifiable, Codable {
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
