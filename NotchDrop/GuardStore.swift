//
//  GuardStore.swift
//  NotchEvery
//
//  守护门面（工单 03）：视图读取守护状态的唯一入口，与 AntigravityStore / UsageStore 同构
//  （`@StateObject var store = GuardStore.shared`）。它持有 FUnManager，把后者的
//  @Published 状态映射成视图直接可用的只读数据；视图不直接接触管理器的内部实现。
//
//  职责边界：
//  - 启动装配（delegate 接线、输入监听、设备恢复、开始扫描）——复刻 FUnlock 原
//    AppDelegate.setupManager / restoreSavedDevice 的语义（菜单栏 UI 部分除外）；
//  - 状态映射（guardState / 设备名 / 信号 / 双阈值 / 最近一条判定 / 蓝牙问题）；
//  - 总开关（enabled）读写；真执行开关（realExecution）读写与持久化（05）。
//

import AppKit
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
    @Published private(set) var hasPassword: Bool = false
    @Published private(set) var discoveredDevices: [Device] = []

    let manager: FUnManager
    private let config: ConfigStore
    private let logger: DecisionLogger
    private let monitor = InputActivityMonitor()
    private var cancellables = Set<AnyCancellable>()
    private var systemObservers: [NSObjectProtocol] = []

    /// 暴露底层 FUnManager 供校准向导与高级设置使用
    var funManager: FUnManager { manager }

    /// 绑定目标蓝牙设备并持久化
    func bindDevice(uuid: UUID, name: String) {
        manager.bindDevice(uuid: uuid, name: name)
        deviceName = manager.monitoredDeviceName
    }

    /// 解除当前设备绑定
    func unbindDevice() {
        manager.unbindDevice()
        deviceName = nil
    }

    /// 手动控制扫描
    func startScanning() {
        manager.startScanning()
    }

    func stopScanning() {
        manager.stopScanning()
    }

    /// 设置解锁阈值
    func setUnlockRSSI(_ value: Int) {
        manager.setUnlockRSSI(value)
        unlockRSSI = manager.unlockRSSI
        lockRSSI = manager.lockRSSI
    }

    /// 设置锁定阈值
    func setLockRSSI(_ value: Int) {
        manager.setLockRSSI(value)
        lockRSSI = manager.lockRSSI
    }

    /// 检查密码状态（从 Keychain 确认）
    func checkPassword() {
        hasPassword = passwordChecker()
    }

    /// 弹出密码录入框并在成功录入后刷新状态
    func setOrChangePassword() {
        if passwordPrompter() {
            checkPassword()
        }
    }

    private let passwordChecker: () -> Bool
    private let passwordPrompter: () -> Bool

    /// - Parameters:
    ///   - manager: 守护管理器（测试时注入可控实例；默认现建）。
    ///   - config: 配置存储（测试时注入隔离域名）。
    ///   - logger: 决策日志（默认与 manager 共用同一个；测试时注入内存实例）。
    ///   - guide: 权限检查器（默认 live：AX/FDA 走系统 API，蓝牙走管理器状态；测试注入 stub）。
    ///   - passwordChecker: 密码检查闭包（默认走 SecurityService.shared.hasPassword；测试注入 stub）。
    ///   - passwordPrompter: 密码录入弹窗闭包（默认走 SecurityService.shared.askPassword；测试注入 stub）。
    init(manager: FUnManager? = nil, config: ConfigStore = .shared,
         logger: DecisionLogger? = nil, guide: PermissionGuide? = nil,
         passwordChecker: (() -> Bool)? = nil,
         passwordPrompter: (() -> Bool)? = nil) {
        let m = manager ?? FUnManager(fun: FUn())
        self.manager = m
        self.config = config
        self.logger = logger ?? m.decisionLogger
        self.permissionGuide = guide ?? PermissionGuide(isBluetoothAuthorized: { [weak m] in
            m?.bluetoothIssue != .unauthorized
        })
        self.passwordChecker = passwordChecker ?? { SecurityService.shared.hasPassword }
        self.passwordPrompter = passwordPrompter ?? { SecurityService.shared.askPassword() }
        // 真执行默认关闭（空跑观察）；用户在守护卡打开后持久化，下次启动照旧。
        m.isDryRun = !config.bool(forKey: "realExecution")
        subscribe()
        refresh()
        refreshPermissions()
        checkPassword()
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

    // MARK: - 权限引导（工单 07）

    /// 上次未解锁回显（工单 08）：最近一条解锁失败的原因；点进诊断分区
    @Published private(set) var lastUnlockFailure: String?

    /// 缺失的授权（已确认过的不再出现）；卡片据此渲染引导行。
    @Published private(set) var permissionIssues: [PermissionIssue] = []
    private var permissionGuide: PermissionGuide

    /// 重检三项授权：启动、面板展开、用户点"重新检测"时调；免重启就绪。
    func recheckPermissions() {
        refreshPermissions()
    }

    /// 记下"知道了"：迁移后不重复骚扰（key 随配置域名走）。
    /// 修好即自动清除确认：再坏才重现骚扰；一直坏则确认保留。
    func acknowledgePermission(_ kind: PermissionKind) {
        config.set(true, forKey: ackKey(for: kind))
        refreshPermissions()
    }

    private func ackKey(for kind: PermissionKind) -> String { "permAck_\(kind.rawValue)" }

    private func refreshPermissions() {
        let missing = permissionGuide.missing()
        for kind in PermissionKind.allCases where !missing.contains(kind) {
            config.removeObject(forKey: ackKey(for: kind))
        }
        permissionIssues = missing
            .filter { !config.bool(forKey: ackKey(for: $0)) }
            .map(PermissionGuide.issue(for:))
    }

    // MARK: - 生命周期

    /// 启动装配：delegate 接线 + 输入监听 + 设备恢复 + 开始扫描。
    /// 复刻 FUnlock 原 setupManager / restoreSavedDevice（菜单栏部分除外）。
    func start() {
        manager.fun.delegate = manager
        manager.inputMonitor = monitor
        manager.fun.inputMonitor = monitor
        setupSystemNotifications()
        restoreThresholds()
        restoreDevice()
        if enabled {
            manager.startScanning()
        }
        // Sequoia TCC 兼容：输入监听不在调用栈上同步启动，原实现因此崩溃过。
        DispatchQueue.main.async { [weak self] in self?.monitor.start() }
        refresh()
        refreshPermissions()
        checkPassword()
    }

    func stop() {
        manager.stopScanning()
    }

    // MARK: - 系统生命周期通知

    private func setupSystemNotifications() {
        guard systemObservers.isEmpty else { return }

        let dnc = DistributedNotificationCenter.default()
        let wsCenter = NSWorkspace.shared.notificationCenter

        // 1. 屏幕锁定与解锁
        systemObservers.append(dnc.addObserver(forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            self?.funManager.onSystemScreenLocked()
        })
        systemObservers.append(dnc.addObserver(forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            self?.funManager.onUnlock()
        })

        // 2. 屏幕保护程序
        systemObservers.append(dnc.addObserver(forName: NSNotification.Name("com.apple.screensaver.didstart"), object: nil, queue: .main) { [weak self] _ in
            self?.funManager.onScreensaverStart()
        })
        systemObservers.append(dnc.addObserver(forName: NSNotification.Name("com.apple.screensaver.didstop"), object: nil, queue: .main) { [weak self] _ in
            self?.funManager.onScreensaverStop()
        })

        // 3. 显示器休眠与唤醒
        systemObservers.append(wsCenter.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.funManager.onDisplaySleep()
        })
        systemObservers.append(wsCenter.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.funManager.onDisplayWake()
        })

        // 4. 系统睡眠与唤醒
        systemObservers.append(wsCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.funManager.onSystemSleep()
        })
        systemObservers.append(wsCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.funManager.onSystemWake()
        })
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

    /// 恢复已保存的 RSSI 阈值配置
    func restoreThresholds() {
        let savedUnlock = config.get("unlockRSSI", fallback: -60)
        let savedLock = config.get("lockRSSI", fallback: -80)
        funManager.setUnlockRSSI(savedUnlock)
        funManager.setLockRSSI(savedLock)
        self.unlockRSSI = savedUnlock
        self.lockRSSI = savedLock
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
        manager.$discoveredDevices.assign(to: &$discoveredDevices)
        // 蓝牙授权翻转（系统弹窗回调）即重检引导行，免重启。
        // 注：@Published 在 willSet 时机投递，同步重读 manager 拿到的是旧值，
        // 下一跳主队列再读即新值（一跳延迟，UI 无感）。
        manager.$bluetoothIssue.sink { [weak self] _ in
            DispatchQueue.main.async { [weak self] in self?.refreshPermissions() }
        }.store(in: &cancellables)
        manager.$isDryRun.sink { [weak self] dryRun in self?.refreshState(dryRun: dryRun) }.store(in: &cancellables)
        logger.$events.sink { [weak self] events in
            self?.refreshJudgement(events)
            self?.refreshUnlockFailure(events)
        }.store(in: &cancellables)
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
        lastJudgement = text(of: events.last)
    }

    /// 上次未解锁：以最近一条解锁类事件为准——失败则回显，之后成功即清掉，不常驻
    private func refreshUnlockFailure(_ events: [DecisionEvent]) {
        guard let latest = events.last(where: { $0.category == .unlock }),
              latest.outcome == .failed else {
            lastUnlockFailure = nil
            return
        }
        lastUnlockFailure = text(of: latest)
    }

    /// 事件→展示文本（detail 优先，否则 reason 本地化；取空为 nil）
    private func text(of event: DecisionEvent?) -> String? {
        guard let event else { return nil }
        if !event.detail.isEmpty { return event.detail }
        guard let reason = event.reason else { return nil }
        let text = t(reason.titleKey)
        return text.isEmpty ? nil : text
    }

    private func refresh() {
        refreshState()
        deviceName = manager.monitoredDeviceName
        rssi = manager.rssi
        lockRSSI = manager.lockRSSI
        unlockRSSI = manager.unlockRSSI
        bluetoothIssue = manager.bluetoothIssue
        refreshJudgement(logger.events)
        refreshUnlockFailure(logger.events)
        checkPassword()
    }

    deinit {
        let dnc = DistributedNotificationCenter.default()
        let wsCenter = NSWorkspace.shared.notificationCenter
        for observer in systemObservers {
            dnc.removeObserver(observer)
            wsCenter.removeObserver(observer)
        }
    }
}
