//
//  MagpieStore.swift
//  NotchEvery
//
//  Magpie 只读数据门面：串行 ioQueue 读盘 + 聚合，主线程发布，值级去重。
//

import Combine
import CoreServices
import Foundation

final class MagpieStore: ObservableObject {
    static let shared = MagpieStore()

    @Published private(set) var snapshot: MagpieSnapshot = .empty
    @Published var distributionDimension: DistributionDimension = .combo
    private(set) var isRunning = false

    private let paths: MagpiePaths
    private let iconResolver: MagpieIconResolver
    private let calendar: Calendar
    private let now: () -> Date
    private let ioQueue = DispatchQueue(label: "MagpieStore.io")

    private var timer: Timer?
    private var watcher: MagpieDirectoryWatcher?

    // 以下状态只在 ioQueue 上读写
    private var usageRecords: [MagpieUsageRecord] = []
    private var usageTail = MagpieUsageReader.TailState.empty
    private var routingTail = MagpieUsageReader.TailState.empty
    private var maskingTail = MagpieUsageReader.TailState.empty
    private var currentDay = ""
    private var routeIndex = MagpieRouteIndex()
    private var routeOrder: [Int64] = []
    private var maskingTotals: [Int64: Int] = [:]
    private var quotas: [MagpieQuotaFileEntry] = []
    private var notices: [String: MagpieLimitNotice] = [:]
    private var checkins: [MagpieCheckinFileEntry] = []
    private var providersPart: MagpieProviderCatalog.ProviderPart?
    private var pluginParts: [MagpieProviderCatalog.PluginPart] = []
    private var gateway: MagpieGatewayFile?
    private var quotaHistory: [String: [String: [MagpieQuotaPoint]]] = [:]

    init(
        paths: MagpiePaths = .init(),
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init,
        iconResolver: MagpieIconResolver? = nil
    ) {
        self.paths = paths
        self.iconResolver = iconResolver ?? MagpieIconResolver(paths: paths)
        self.calendar = calendar
        self.now = now
    }

    deinit {
        timer?.invalidate()
        watcher?.stop()
    }

    /// 幂等：立即刷新一次，再启 1.5s 定时器与 FSEvents 监听（0.4s 去抖）。
    func start() {
        guard !isRunning else { return }
        isRunning = true
        catchUp()

        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.catchUp()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        let watcher = MagpieDirectoryWatcher(path: paths.root) { [weak self] in
            self?.catchUp()
        }
        watcher.start()
        self.watcher = watcher
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        watcher?.stop()
        watcher = nil
        isRunning = false
    }

    /// 立即追平一次（悬停虚影等场景）。
    func catchUp() {
        ioQueue.async { [weak self] in
            self?.refresh()
        }
    }

    /// 生命周期裁决：展开态或虚影态（悬停/清态窗口）运行，否则停止。
    /// 常驻视图 NotchView 据此在 status/hoverGhosting/ghostFading 变化时启停。
    static func shouldRun(status: NotchViewModel.Status, hoverGhosting: Bool, ghostFading: Bool) -> Bool {
        status == .opened || hoverGhosting || ghostFading
    }

    // MARK: - 读盘 + 聚合（ioQueue）

    private func refresh() {
        let date = now()
        let day = MagpiePaths.dayString(for: date, calendar: calendar)
        if day != currentDay {
            currentDay = day
            routingTail = .empty
            maskingTail = .empty
            routeIndex = MagpieRouteIndex()
            routeOrder = []
            maskingTotals = [:]
        }

        usageRecords.append(contentsOf: MagpieUsageReader.readNewRecords(file: paths.usageFile, state: &usageTail))
        iconResolver.reloadIconsIfNeeded()
        let startOfDay = calendar.startOfDay(for: date)
        usageRecords.removeAll { $0.time < startOfDay }

        let routingLines = readNewLines(file: paths.routingFile(day: day), state: &routingTail)
        if !routingLines.isEmpty {
            mergeRouteIndex(MagpieFiles.parseRouteIndex(lines: routingLines))
        }
        for line in readNewLines(file: paths.maskingFile(day: day), state: &maskingTail) {
            if let entry = MagpieFiles.decodeMaskingLine(line) {
                maskingTotals[entry.route, default: 0] += entry.n
            }
        }

        load(paths.quotasFile, parse: MagpieFiles.parseQuotas) { quotas = $0 }
        load(paths.limitNoticesFile, parse: MagpieFiles.parseLimitNotices) { notices = $0 }
        load(paths.pluginCheckinFile, parse: MagpieFiles.parseCheckins) { checkins = $0 }
        load(paths.providersFile, parse: MagpieFiles.parseProviders) { providersPart = $0 }
        load(paths.pluginProvidersFile, parse: MagpieFiles.parsePluginProviders) { pluginParts = $0 }
        load(paths.quotaHistoryFile, parse: MagpieFiles.parseQuotaHistory) { quotaHistory = $0 }
        load(paths.gatewayFile, parse: MagpieFiles.parseGateway) { gateway = $0 }

        let newSnapshot = MagpieAggregator.buildSnapshot(
            usage: usageRecords,
            routes: routeIndex,
            masking: maskingTotals.map { MagpieMaskingEntry(route: $0.key, n: $0.value, time: date) },
            quotas: quotas,
            notices: notices,
            checkins: checkins,
            catalog: MagpieProviderCatalog.merged(providers: providersPart, plugins: pluginParts),
            gateway: gateway,
            quotaHistory: quotaHistory,
            hasMagpieDirectory: FileManager.default.fileExists(atPath: paths.root.path),
            now: date,
            calendar: calendar
        )

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            var comparable = newSnapshot
            comparable.refreshedAt = self.snapshot.refreshedAt
            guard comparable != self.snapshot else { return }
            self.snapshot = newSnapshot
        }
    }

    private func load<T>(_ url: URL, parse: (Data) -> T?, assign: (T) -> Void) {
        guard let data = try? Data(contentsOf: url), let value = parse(data) else { return }
        assign(value)
    }

    private func mergeRouteIndex(_ batch: MagpieRouteIndex) {
        for (id, name) in batch.groupNameByRouteID {
            if let position = routeOrder.firstIndex(of: id) {
                routeOrder.remove(at: position)
            }
            routeOrder.append(id)
            routeIndex.groupNameByRouteID[id] = name
            while routeOrder.count > 200 {
                routeIndex.groupNameByRouteID[routeOrder.removeFirst()] = nil
            }
        }
        for (ref, name) in batch.groupNameByRef {
            routeIndex.groupNameByRef[ref] = name
        }
        for (id, snapshot) in batch.orderSnapshotsByAccount {
            routeIndex.orderSnapshotsByAccount[id] = snapshot
        }
    }

    /// 通用 JSONL 增量读取：复用 TailState，只消费到最后一个换行。
    private func readNewLines(file: URL, state: inout MagpieUsageReader.TailState) -> [Data] {
        var info = stat()
        guard lstat(file.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return [] }
        let inode = UInt64(info.st_ino)
        let size = UInt64(max(0, info.st_size))
        if state.inode == 0 {
            state.inode = inode
        } else if state.inode != inode || size < state.offset {
            state = MagpieUsageReader.TailState(offset: 0, inode: inode)
        }
        guard size > state.offset, let handle = try? FileHandle(forReadingFrom: file) else { return [] }
        defer { try? handle.close() }
        do { try handle.seek(toOffset: state.offset) } catch { return [] }
        guard let body = try? handle.readToEnd(),
              !body.isEmpty,
              let newline = body.lastIndex(of: 0x0A)
        else { return [] }
        let consumed = body[...newline]
        state.offset += UInt64(consumed.count)
        return consumed.dropLast()
            .split(separator: 0x0A, omittingEmptySubsequences: false)
            .filter { !$0.isEmpty }
            .map { Data($0) }
    }
}

// MARK: - FSEvents 递归目录监听

final class MagpieDirectoryWatcher {
    private let path: URL
    private let queue: DispatchQueue
    private let onChange: () -> Void
    private let debounce: TimeInterval = 0.4
    private var stream: FSEventStreamRef?
    private var pending: DispatchWorkItem?

    init(path: URL, queue: DispatchQueue = .main, onChange: @escaping () -> Void) {
        self.path = path
        self.queue = queue
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    func start() {
        guard stream == nil, FileManager.default.fileExists(atPath: path.path) else { return }
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<MagpieDirectoryWatcher>.fromOpaque(info).takeUnretainedValue().schedule()
        }
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot
        )
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            [path.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.1,
            flags
        ) else { return }
        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            return
        }
        self.stream = stream
    }

    func stop() {
        pending?.cancel()
        pending = nil
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
        }
        stream = nil
    }

    private func schedule() {
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pending = nil
            self.onChange()
        }
        pending = item
        queue.asyncAfter(deadline: .now() + debounce, execute: item)
    }
}
