//
//  GuardStore.swift
//  NotchEvery
//
//  守护门面（工单 03）：视图读取守护状态的唯一入口，与 QuotaStore / UsageStore 同构
//  （`@StateObject var store = GuardStore.shared`）。它持有 FUnManager，把后者的
//  @Published 状态映射成视图直接可用的只读数据；视图不直接接触管理器的内部实现。
//
//  职责边界：
//  - 启动装配（delegate 接线、输入监听、设备恢复、开始扫描）——复刻 FUnlock 原
//    AppDelegate.setupManager / restoreSavedDevice 的语义（菜单栏 UI 部分除外）；
//  - 状态映射（guardState / 设备名 / 信号 / 双阈值 / 最近一条判定 / 蓝牙问题）；
//  - 总开关（enabled）读写；真执行开关（realExecution）读写与持久化（05）。
//

import Combine
import Foundation

/// 守护对外呈现的三态（工单 03/06/09 共用）。
enum GuardState {
    /// 总开关关闭：不扫描、不判定。
    case disabled
    /// 空跑观察：扫描与判定正常跑，只记录、不执行（03 的唯一工作态）。
    case observing
    /// 守护中：判定会真的驱动锁屏/解锁（09 接管后可达）。
    case guarding
}

@MainActor
final class GuardStore: ObservableObject {
    static let shared = GuardStore()

    @Published private(set) var guardState: GuardState = .observing
    @Published private(set) var deviceName: String?
    @Published private(set) var rssi: Int?
    @Published private(set) var lockRSSI: Int = -80
    @Published private(set) var unlockRSSI: Int = -60
    @Published private(set) var lastJudgement: String?
    @Published private(set) var bluetoothIssue: BluetoothIssue?

    private let manager: FUnManager
    private let config: ConfigStore
    private let logger: DecisionLogger
    private let monitor = InputActivityMonitor()
    private var cancellables = Set<AnyCancellable>()

    /// - Parameters:
    ///   - manager: 守护管理器（测试时注入可控实例；默认现建）。
    ///   - config: 配置存储（测试时注入隔离域名）。
    ///   - logger: 决策日志（默认与 manager 共用同一个；测试时注入内存实例）。
    init(manager: FUnManager? = nil, config: ConfigStore = .shared, logger: DecisionLogger? = nil) {
        let m = manager ?? FUnManager(fun: FUn())
        self.manager = m
        self.config = config
        self.logger = logger ?? m.decisionLogger
        // 真执行默认关闭（空跑观察）；用户在守护卡打开后持久化，下次启动照旧。
        m.isDryRun = !config.bool(forKey: "realExecution")
        subscribe()
        refresh()
    }

    // MARK: - 总开关

    /// 总开关：缺键时按启用处理（与管理器内部的 enabled 语义一致，避免静默拦截）。
    var enabled: Bool {
        get { config.object(forKey: "enabled") == nil || config.bool(forKey: "enabled") }
        set {
            config.set(newValue, forKey: "enabled")
            if newValue {
                manager.startScanning()
            } else {
                manager.stopScanning()
            }
            refresh()
        }
    }

    /// 空跑模式（只读透出；真执行开关负责翻转，见 realExecution）。
    var isDryRun: Bool { manager.isDryRun }

    /// 真执行开关（工单 05）：默认关闭（空跑观察，只记录不执行）。
    /// 打开后判定真的驱动锁屏/解锁/唤醒；写 manager.isDryRun（@Published）并 refresh，切换立即生效并持久化。
    var realExecution: Bool {
        get { config.bool(forKey: "realExecution") }
        set {
            config.set(newValue, forKey: "realExecution")
            manager.isDryRun = !newValue
            refresh()
        }
    }

    // MARK: - 生命周期

    /// 启动装配：delegate 接线 + 输入监听 + 设备恢复 + 开始扫描。
    /// 复刻 FUnlock 原 setupManager / restoreSavedDevice（菜单栏部分除外）。
    func start() {
        manager.fun.delegate = manager
        manager.inputMonitor = monitor
        manager.fun.inputMonitor = monitor
        restoreDevice()
        if enabled {
            manager.startScanning()
        }
        // Sequoia TCC 兼容：输入监听不在调用栈上同步启动，原实现因此崩溃过。
        DispatchQueue.main.async { [weak self] in self?.monitor.start() }
        refresh()
    }

    func stop() {
        manager.stopScanning()
    }

    // MARK: - 内部

    /// 恢复已绑定的监控设备（读迁移后的配置；设备名一并恢复，FUnlock 原版只恢复了 UUID）。
    private func restoreDevice() {
        guard let str = config.string(forKey: "device"),
              let uuid = UUID(uuidString: str) else { return }
        manager.updateConnected(false)
        manager.monitoredDeviceName = config.string(forKey: "deviceName") ?? t("default_paired_device")
        manager.fun.startMonitor(uuid: uuid)
    }

    private func subscribe() {
        // 注意：$x 递送的元素是新值，但递送时机在存储更新之前——因此 sink 里必须用
        // 递送下来的值，绝不能重读属性（重读拿到的是旧值；已用最小复现验证过）。
        // objectWillChange 更是在变更之前触发，同样不能用于读取。
        manager.$monitoredDeviceName.assign(to: &$deviceName)
        manager.$rssi.assign(to: &$rssi)
        manager.$lockRSSI.assign(to: &$lockRSSI)
        manager.$unlockRSSI.assign(to: &$unlockRSSI)
        manager.$bluetoothIssue.assign(to: &$bluetoothIssue)
        manager.$isDryRun.sink { [weak self] dryRun in self?.refreshState(dryRun: dryRun) }.store(in: &cancellables)
        logger.$events.sink { [weak self] events in self?.refreshJudgement(events) }.store(in: &cancellables)
    }

    /// 派生态（enabled × isDryRun）；在 init / setEnabled / start / isDryRun 翻转时刷新。
    /// dryRun 必须由调用方传入（sink 递送值）；禁止在订阅回调里重读（见上）。
    private func refreshState(dryRun: Bool? = nil) {
        let dry = dryRun ?? manager.isDryRun
        if !enabled {
            guardState = .disabled
        } else if dry {
            guardState = .observing
        } else {
            guardState = .guarding
        }
    }

    private func refreshJudgement(_ events: [DecisionEvent]) {
        lastJudgement = events.last.flatMap { event in
            if !event.detail.isEmpty { return event.detail }
            guard let reason = event.reason else { return nil }
            let text = t(reason.titleKey)
            return text.isEmpty ? nil : text
        }
    }

    private func refresh() {
        refreshState()
        deviceName = manager.monitoredDeviceName
        rssi = manager.rssi
        lockRSSI = manager.lockRSSI
        unlockRSSI = manager.unlockRSSI
        bluetoothIssue = manager.bluetoothIssue
        refreshJudgement(logger.events)
    }
}
