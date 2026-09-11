import Cocoa
import Combine
import Foundation
import LaunchAtLogin
import SwiftUI

// MARK: - 首展耗时埋点（systematic-debugging 诊断用，NOTCH_TIMING=1 开启；关闭零开销）
private let notchTimingEnabled = ProcessInfo.processInfo.environment["NOTCH_TIMING"] == "1"
private var notchTimingT0: CFTimeInterval = 0
func notchTimingMark(_ label: String) {
    guard notchTimingEnabled else { return }
    let now = CFAbsoluteTimeGetCurrent()
    if label == "clickDown" || notchTimingT0 == 0 { notchTimingT0 = now }
    let path = "/tmp/notch-timing.log"
    if !FileManager.default.fileExists(atPath: path) {
        FileManager.default.createFile(atPath: path, contents: nil)
    }
    let msg = String(format: "[TIMING] %6.0fms %@\n", (now - notchTimingT0) * 1000, label)
    if let data = msg.data(using: .utf8) {
        FileHandle.standardError.write(data)
        if let fh = try? FileHandle(forWritingTo: URL(fileURLWithPath: path)) {
            try? fh.seekToEnd()
            try? fh.write(contentsOf: data)
            try? fh.close()
        }
    }
}

// MARK: - NotchGeometry（#24 拆分：纯几何计算）

struct NotchGeometry {
    var deviceNotchRect: CGRect
    var screenRect: CGRect
    var zoneOpenedSize: CGSize
    let inset: CGFloat

    var notchOpenedRect: CGRect {
        .init(
            x: screenRect.origin.x + (screenRect.width - zoneOpenedSize.width) / 2,
            y: screenRect.origin.y + screenRect.height - zoneOpenedSize.height,
            width: zoneOpenedSize.width,
            height: zoneOpenedSize.height
        )
    }

    func insetDeviceRect() -> CGRect {
        deviceNotchRect.insetBy(dx: inset, dy: inset)
    }
}

enum SwipeDirection {
    case next
    case previous
}

// MARK: - ViewModel 门面（保持外部 vm.* 调用零改）

class NotchViewModel: NSObject, ObservableObject {
    var cancellables: Set<AnyCancellable> = []
    let inset: CGFloat

    private var eventsBox: (any EventMonitorsProtocol)!
    var events: any EventMonitorsProtocol { eventsBox ?? EventMonitors.shared }

    init(inset: CGFloat = -4, events: (any EventMonitorsProtocol)? = nil) {
        self.inset = inset
        super.init()
        self.eventsBox = events ?? EventMonitors.shared
        setupCancellables(events: events ?? EventMonitors.shared)
    }

    deinit {
        destroy()
    }

    /// 通用弹簧：对齐原版 NotchDrop 的 animation 参数（回弹手感一致）
    let animation: Animation = .interactiveSpring(
        duration: 0.5,
        extraBounce: 0.25,
        blendDuration: 0.125
    )
    /// 内容自适应面板（ADR-0008）：面板尺寸跟随当前分区内容自然大小，钳制有界。
    /// 最小 320×120 防塌，最大 640 宽 × 屏高 40%，超限由内容区内部吸收，外层不动。
    static let minPanelSize = CGSize(width: 320, height: 120)
    static let maxPanelWidth: CGFloat = 640
    /// headerSlotHeight 常量保留，不作语义用途（头部行已删；测试锁定值 29）。
    static let headerSlotHeight: CGFloat = 29

    /// 钳制纯函数：自然尺寸 → 面板尺寸。maxHeight 由调用方按当前屏幕给（屏高 40%）。
    /// 宽度 = 钳制(内容自然宽, 最小宽, 长宽比保底宽)，上限 maxPanelWidth——
    /// natural 取自**含外壳留白**的盒子测量：内容最小宽 + 2×panelContentInset 是硬下限，
    /// 否则内容吃穿留白、贴岛体边缘甚至被裁（2026-09-11 探针定位）。
    /// 长宽比保底 = 岛体宽高比 ≥ panelAspectFloor，防「窄高条」；切页时测量被重置以允许缩回。
    static func clampPanelSize(_ natural: CGSize, maxHeight: CGFloat) -> CGSize {
        let height = min(max(natural.height, minPanelSize.height), maxHeight)
        let flankBleed = IslandMetrics.openCornerRadius * 2
        let aspectFloorWidth = height * IslandMetrics.panelAspectFloor - flankBleed
        return CGSize(
            width: min(max(max(natural.width, minPanelSize.width), aspectFloorWidth), maxPanelWidth),
            height: height
        )
    }

    /// 面板高上限 = 屏高 40%；屏幕未知时回落 360（≈900×0.4）。
    var maxPanelHeight: CGFloat {
        screenRect.height > 0 ? screenRect.height * 0.4 : 360
    }

    /// 当前分区上报的自然尺寸（内容驱动，见 ZoneNaturalSizeKey）
    @Published var measuredNaturalSize: CGSize = .zero

    /// 当前区已打开尺寸：整体测量值（含安全区+内容+dots）经钳制；未量到取最小保底
    var zoneOpenedSize: CGSize {
        Self.clampPanelSize(measuredNaturalSize, maxHeight: maxPanelHeight)
    }

    /// 刘海安全区顶边 = 物理刘海高 + 8pt（03 工单）。面板内容从此之下开始，
    /// 刘海区只画背景。无刘海屏沿用控制器兜底值。
    var notchSafeAreaTop: CGFloat {
        deviceNotchRect.height + 8
    }
    let dropDetectorRange: CGFloat = 32

    enum Status: String, Codable, Hashable, Equatable {
        case closed
        case opened
        case popping
    }

    enum OpenReason: String, Codable, Hashable, Equatable {
        case click
        case drag
        case boot
        case hover
        case unknown
    }

    enum ContentType: Int, Codable, Hashable, Equatable {
        case normal
        case token
    }

    // ——— 几何经由 NotchGeometry 计算，Published 仍在门面以保持绑定 ———
    var geometry: NotchGeometry {
        NotchGeometry(
            deviceNotchRect: deviceNotchRect,
            screenRect: screenRect,
            zoneOpenedSize: zoneOpenedSize,
            inset: inset
        )
    }

    var notchOpenedRect: CGRect { geometry.notchOpenedRect }

    @Published private(set) var status: Status = .closed {
        didSet {
            // 每次展开重置宽度测量：宽度是「涨」信号，不重置会在多个稳态间漂移
            if status == .opened, oldValue != .opened {
                measuredNaturalSize = CGSize(width: 0, height: measuredNaturalSize.height)
            }
        }
    }
    @Published var openReason: OpenReason = .unknown
    @Published var contentType: ContentType = .normal {
        didSet {
            // 切页允许面板缩：宽度测量含「涨」信号，不重置会卡在上一页的宽度
            measuredNaturalSize = CGSize(width: 0, height: measuredNaturalSize.height)
        }
    }

    @Published var spacing: CGFloat = 20
    @Published var cornerRadius: CGFloat = 20
    @Published var deviceNotchRect: CGRect = .zero
    @Published var screenRect: CGRect = .zero
    @Published var optionKeyPressed: Bool = false
    @Published var hoverGhosting: Bool = false
    /// 两段收起中间态：保持虚影视觉 200ms 再清态
    @Published private(set) var ghostFading: Bool = false
    /// 过桥菊花：openFromGhost 后短闪 150ms
    @Published private(set) var bridgeSpinning: Bool = false

    /// 展开/收起弹簧：原版 NotchDrop 的 interactiveSpring(duration 0.5, extraBounce 0.25,
    /// blendDuration 0.125)；展开回弹降到 0.1（2026-09-11 用户反馈「弹出来用力过猛」）
    let openAnimation: Animation = .interactiveSpring(duration: 0.5, extraBounce: 0.1, blendDuration: 0.125)
    /// 收起沿用同一条曲线（原版开合同参）
    let closeAnimation: Animation = .interactiveSpring(duration: 0.5, extraBounce: 0.25, blendDuration: 0.125)
    /// 切页专用：快、无过冲（清单 05 转场收敛；.snappy 需 macOS 14+，部署目标 13 故用高阻尼 spring）
    let pageAnimation: Animation = .spring(response: 0.3, dampingFraction: 0.9)

    @PublishedPersist(key: "selectedLanguage", defaultValue: .system)
    var selectedLanguage: Language

    @PublishedPersist(key: "hapticFeedback", defaultValue: true)
    var hapticFeedback: Bool

    let hapticSender = PassthroughSubject<Void, Never>()

    /// hover 展开后的延迟收起任务（防刘海→面板路径单帧误判闪烁）
    private var hoverCloseWorkItem: DispatchWorkItem?
    /// 虚影清态代际：closeToGhost 的 200ms 延迟清零必须让位给新鲜 hover
    private var ghostGeneration = 0

    func scheduleHoverClose() {
        hoverCloseWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // 两段收起：展开态走 closeToGhost()，虚影态走 notchClose()
            if status == .opened, openReason == .hover {
                closeToGhost()
            } else if hoverGhosting {
                notchClose()
            }
        }
        hoverCloseWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    func cancelHoverClose() {
        hoverCloseWorkItem?.cancel()
        hoverCloseWorkItem = nil
    }

    /// 虚影态→展开态（点击/拖拽调用），触发过桥菊花 150ms
    func openFromGhost() {
        notchTimingMark("openFromGhost")
        cancelHoverClose()
        ghostGeneration += 1
        hoverGhosting = false
        ghostFading = false
        bridgeSpinning = true
        status = .opened
        notchTimingMark("preActivate")
        NSApp.activate(ignoringOtherApps: true)
        notchTimingMark("postActivate")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.bridgeSpinning = false
        }
    }

    /// 两段收起：先缩回虚影尺寸 200ms，再清态回刘海
    func closeToGhost() {
        openReason = .unknown
        // stage 1: status→closed 触发布局动画，ghostFading 保持虚影视觉（走肉曲线）
        withAnimation(openAnimation) {
            status = .closed
            ghostFading = true
        }
        // stage 2: 200ms 后清虚影，代际校验避免吞掉新鲜 hover（走快收）
        ghostGeneration += 1
        let generation = ghostGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, generation == self.ghostGeneration else { return }
            withAnimation(self.closeAnimation) {
                self.ghostFading = false
                self.hoverGhosting = false
            }
        }
    }

    func notchOpen(_ reason: OpenReason) {
        openReason = reason
        if reason == .hover {
            // 虚影态：只置标记，不展开（点击/拖拽时才调 openFromGhost()）
            // 代际 +1 让挂起的 closeToGhost 清零失效，避免吞新鲜 hover（走肉曲线）
            ghostGeneration += 1
            withAnimation(openAnimation) {
                hoverGhosting = true
            }
        } else {
            cancelHoverClose()
            ghostGeneration += 1
            hoverGhosting = false
            status = .opened
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func notchClose() {
        cancelHoverClose()
        ghostGeneration += 1
        // 虚影态 status 不变，外层动画不触发，此处显式给快收（展开态收起时与外层同曲线，无害）
        withAnimation(closeAnimation) {
            hoverGhosting = false
            ghostFading = false
            openReason = .unknown
            status = .closed
        }
    }

    /// 设置 Popover 弹出状态：根齿轮与右键菜单共用（设置走 Popover 定案，不占分页）
    @Published var showSettings = false

    /// 功能区固定顺序：左右滑按此循环（概览｜Token）
    static let zoneOrder: [ContentType] = [.normal, .token]

    /// 页—区分区双向映射（TabView 分页地基，越界回概览）
    static func pageIndex(for zone: ContentType) -> Int {
        zoneOrder.firstIndex(of: zone) ?? 0
    }

    static func zone(for page: Int) -> ContentType {
        guard zoneOrder.indices.contains(page) else { return .normal }
        return zoneOrder[page]
    }

    /// 最近一次切换方向：内容区不对称过渡用
    @Published var lastSwipeDirection: SwipeDirection = .next

    func jumpToZone(_ zone: ContentType) {
        let order = Self.zoneOrder
        if let cur = order.firstIndex(of: contentType),
           let dst = order.firstIndex(of: zone)
        {
            if dst > cur {
                lastSwipeDirection = .next
            } else if dst < cur {
                lastSwipeDirection = .previous
            }
        }
        contentType = zone
    }

    func nextZone() {
        lastSwipeDirection = .next
        let order = Self.zoneOrder
        let idx = order.firstIndex(of: contentType) ?? 0
        contentType = order[(idx + 1) % order.count]
    }

    func previousZone() {
        lastSwipeDirection = .previous
        let order = Self.zoneOrder
        let idx = order.firstIndex(of: contentType) ?? 0
        contentType = order[(idx + order.count - 1) % order.count]
    }

    /// 首次滑动提示是否已展示过：持久化，只打扰一次
    @PublishedPersist(key: "hasSeenSwipeHint", defaultValue: false)
    var hasSeenSwipeHint: Bool

    func markSwipeHintSeen() {
        hasSeenSwipeHint = true
    }

    func notchPop() {
        openReason = .unknown
        status = .popping
    }
}
