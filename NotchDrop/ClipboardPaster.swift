import Cocoa
import CoreGraphics

/// 前台应用追踪与一键粘贴注入。
///
/// - 监听 `NSWorkspace.didActivateApplicationNotification` 持续记录用户最近使用的外部应用（自动排除自身）。
/// - `paste(item:)` 触发触觉反馈、把条目写回系统剪贴板（标记内部写入防重录）、激活目标应用并注入 `Cmd+V`。
/// - 交互约束：不做任何关闭刘海面板的动作，保持展开供用户连续点击粘贴。
public final class ClipboardPaster {
    public static let shared = ClipboardPaster()

    /// V 键虚拟键码（ANSI 布局）
    static let vKeyCode: CGKeyCode = 0x09

    /// 用户最近使用的外部应用，即 `paste` 激活与注入按键的目标
    public private(set) var lastActiveApp: NSRunningApplication?

    private let pasteboard: NSPasteboard
    private let store: ClipboardStore
    private let monitor: ClipboardMonitor
    private let hapticPerformer: NSHapticFeedbackPerformer
    private let selfBundleIdentifier: String?
    private let activationDelay: TimeInterval
    private let activateApp: (NSRunningApplication) -> Void
    private let postPasteKeystroke: () -> Void

    /// - Parameters:
    ///   - hapticPerformer: 默认触控板 Force Touch 反馈执行器（测试可注入 Spy）
    ///   - selfBundleIdentifier: 自身应用的 bundle id，用于在追踪中排除本应用
    ///   - trackWorkspace: 是否监听工作区激活通知并抓取初始前台应用（测试传 false 保持隔离）
    ///   - activationDelay: 激活目标应用后注入按键的等待延迟（秒），默认 0.12s——给被唤醒到前台的目标应用
    ///     留足键盘焦点接管窗口，避免首次注入过早被系统丢弃、第二次才贴上的问题（测试可注入缩短）
    ///   - activateApp: 激活目标应用的执行器，默认真实调用 `activate(options:)`
    ///   - postPasteKeystroke: 注入 Cmd+V 的执行器，默认发送真实 CGEvent（测试可注入 Spy）
    public init(
        pasteboard: NSPasteboard = .general,
        store: ClipboardStore = .shared,
        monitor: ClipboardMonitor = .shared,
        hapticPerformer: NSHapticFeedbackPerformer = NSHapticFeedbackManager.defaultPerformer,
        selfBundleIdentifier: String? = Bundle.main.bundleIdentifier,
        trackWorkspace: Bool = true,
        activationDelay: TimeInterval = 0.12,
        activateApp: ((NSRunningApplication) -> Void)? = nil,
        postPasteKeystroke: (() -> Void)? = nil
    ) {
        self.pasteboard = pasteboard
        self.store = store
        self.monitor = monitor
        self.hapticPerformer = hapticPerformer
        self.selfBundleIdentifier = selfBundleIdentifier
        self.activationDelay = activationDelay
        self.activateApp = activateApp ?? Self.activateToFront
        self.postPasteKeystroke = postPasteKeystroke ?? Self.postCommandVPaste

        if trackWorkspace {
            setupWorkspaceTracking()
        }
    }

    // MARK: - 前台应用追踪

    /// 监听应用激活通知并抓取初始前台应用
    private func setupWorkspaceTracking() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.trackActivatedApp(app)
        }

        // 初始抓取：应用启动时已有前台应用
        if let frontmost = NSWorkspace.shared.frontmostApplication {
            trackActivatedApp(frontmost)
        }
    }

    /// 记录最新激活的外部应用；与自身 bundle id 相同的应用（本应用）被忽略
    func trackActivatedApp(_ app: NSRunningApplication) {
        guard app.bundleIdentifier != selfBundleIdentifier else { return }
        lastActiveApp = app
    }

    // MARK: - 粘贴注入

    /// 点击卡片触发：触觉反馈 + 写回剪贴板 + 激活目标应用 + 注入 Cmd+V。
    ///
    /// 不会关闭刘海面板（不调用任何收起逻辑），保持展开便于连续点击粘贴。
    public func paste(item: ClipboardItem) {
        // 1. 触控板 Force Touch 物理震动反馈
        hapticPerformer.perform(.levelChange, performanceTime: .now)

        // 2. 内容写回系统剪贴板，并标记内部写入防止监听器重复录入
        monitor.isInternalCopy = true
        pasteboard.clearContents()
        switch item.type {
        case .text:
            if let text = item.textContent {
                pasteboard.setString(text, forType: .string)
            }
        case .image:
            if let url = store.imageURL(for: item),
               let pngData = try? Data(contentsOf: url),
               let image = NSImage(data: pngData) {
                // 双格式写回：原始 PNG 字节流兼容严格要求原生文件流的富文本应用（微信、飞书、Pages），
                // NSImage 图形对象兼容仅接收图形对象的应用，确保 100% 格式双重兼容。
                pasteboard.setData(pngData, forType: .png)
                pasteboard.writeObjects([image])
            }
        }

        // 3. 目标应用缺失（从未记录）或已退出时降级为仅写回剪贴板
        guard let target = lastActiveApp, !target.isTerminated else { return }

        // 4. 激活原前台应用，待其重新接管键盘事件后注入 Cmd+V
        activateApp(target)
        let postKeystroke = postPasteKeystroke
        DispatchQueue.main.asyncAfter(deadline: .now() + activationDelay) {
            postKeystroke()
        }
    }

    // MARK: - 生产默认执行器

    /// 默认激活执行器：把目标应用拉到前台。
    /// `ignoringOtherApps` 虽在 macOS 14 起标记弃用，但部署目标含 macOS 13，且新系统下调用无副作用。
    private static func activateToFront(_ app: NSRunningApplication) {
        app.activate(options: .activateIgnoringOtherApps)
    }

    /// 默认按键注入执行器：向系统发送真实的 Cmd+V（keyDown/keyUp 各一次，按键 V 即 0x09）
    private static func postCommandVPaste() {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else { return }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
