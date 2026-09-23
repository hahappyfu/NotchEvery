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
    /// 最小 160×60 防塌，最大 640 宽 × 屏高 40%，超限由内容区内部吸收，外层不动。
    static let minPanelSize = CGSize(width: IslandMetrics.minExternalPanelWidth, height: IslandMetrics.minPanelHeight)
    static let maxPanelWidth: CGFloat = 640
    /// headerSlotHeight 常量保留，不作语义用途（头部行已删；测试锁定值 29）。
    static let headerSlotHeight: CGFloat = 29

    /// 钳制纯函数：自然尺寸 → 面板尺寸。maxHeight 由调用方按当前屏幕给（屏高 40%）。
    /// 宽度 = 钳制(内容自然宽/刘海宽, 长宽比保底宽)，上限 maxPanelWidth——
    /// 若有物理刘海（deviceNotchWidth > 0），宽度保底为 deviceNotchWidth + 16；
    /// 若无物理刘海，宽度保底为 minExternalPanelWidth (160)；
    /// 长宽比保底 = 岛体宽高比 ≥ panelAspectFloor，防「窄高条」。
    static func clampPanelSize(_ natural: CGSize, maxHeight: CGFloat, deviceNotchWidth: CGFloat = 0) -> CGSize {
        let height = min(max(natural.height, IslandMetrics.minPanelHeight), maxHeight)
        let minWidth: CGFloat
        if deviceNotchWidth > 0 {
            minWidth = max(deviceNotchWidth + 16, natural.width)
        } else {
            minWidth = max(natural.width, IslandMetrics.minExternalPanelWidth)
        }
        let flankBleed = IslandMetrics.openCornerRadius * 2
        let aspectFloorWidth = height * IslandMetrics.panelAspectFloor - flankBleed
        return CGSize(
            width: min(max(minWidth, aspectFloorWidth), maxPanelWidth),
            height: height
        )
    }

    /// 面板高上限 = 屏高 40%；屏幕未知时回落 360（≈900×0.4）。
    var maxPanelHeight: CGFloat {
        screenRect.height > 0 ? screenRect.height * 0.4 : 360
    }

    /// 当前分区上报的自然尺寸（内容驱动，见 ZoneNaturalSizeKey）
    @Published var measuredNaturalSize: CGSize = .zero {
        didSet {
            // 只记有效测量：切换时的归零是占位，不是内容真实尺寸
            if measuredNaturalSize.width > 0 {
                lastZoneSize[contentType] = measuredNaturalSize
            }
        }
    }

    /// 各区上次真实尺寸：重开/切回直接从它起跳，首帧即接近终值，测量到达只剩微调
    private var lastZoneSize: [ContentType: CGSize] = [:]

    /// 当前区已打开尺寸：整体测量值（含安全区+内容+dots）经钳制；未量到取最小保底
    var zoneOpenedSize: CGSize {
        Self.clampPanelSize(measuredNaturalSize, maxHeight: maxPanelHeight, deviceNotchWidth: deviceNotchRect.width)
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
        case clipboard
        case token
        case gateway
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
            // 重开从本区上次宽度起跳（无记忆时回落归零，即旧行为）
            if status == .opened, oldValue != .opened {
                let seed = lastZoneSize[contentType]?.width ?? 0
                measuredNaturalSize = CGSize(width: seed, height: measuredNaturalSize.height)
            }
            // 过渡期标志：开/关弹簧期间岛体响应 is 变化，稳态后锁定
            if status != oldValue {
                transitionActive = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                    self?.transitionActive = false
                }
            }
        }
    }
    @Published var openReason: OpenReason = .unknown
    @Published var contentType: ContentType = .normal {
        didSet {
            // 切页恢复目标区自己的宽度：各区独立记忆，窄区回来不会被宽区卡住
            let seed = lastZoneSize[contentType]?.width ?? 0
            measuredNaturalSize = CGSize(width: seed, height: measuredNaturalSize.height)
            if contentType != oldValue {
                transitionActive = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                    self?.transitionActive = false
                }
            }
        }
    }

    /// 过渡期标志：开/关/切页弹簧期间为 true，稳态后为 false。
    /// NotchView 遮罩弹簧仅在 transitionActive 期间响应 islandSize 变化，
    /// 稳态时数据轮询引起的微小尺寸波动不再驱动岛体动画。
    @Published var transitionActive: Bool = false

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

    /// 展开弹簧：对齐 Apple 灵动岛原生感（360ms 快速舒展，0.82 阻尼保留微弹水滴感）
    let openAnimation: Animation = .spring(response: 0.36, dampingFraction: 0.82, blendDuration: 0.08)
    /// 收起弹簧：对齐 Apple 原生吸附（260ms 快收，1.0 临界阻尼绝对零反弹）
    let closeAnimation: Animation = .spring(response: 0.26, dampingFraction: 1.0, blendDuration: 0.05)
    /// 切页专用：利落机械感弹簧（280ms，0.82 微超调高品质推进）
    let pageAnimation: Animation = .spring(response: 0.28, dampingFraction: 0.82)

    @PublishedPersist(key: "selectedLanguage", defaultValue: .system)
    var selectedLanguage: Language

    @PublishedPersist(key: "hapticFeedback", defaultValue: true)
    var hapticFeedback: Bool

    /// 网关分区开关（设置页持久化；关闭时从分页剔除）
    @PublishedPersist(key: "showGatewayZone", defaultValue: true)
    var showGatewayZone: Bool

    /// 参与分页的区序：剪贴板作为第 4 页工具箱（概览 ｜ Token ｜ 网关 ｜ 剪贴板）。网关页关时剔除网关。
    static let baseZoneOrder: [ContentType] = [.normal, .token, .gateway, .clipboard]
    static func zoneOrder(gatewayEnabled: Bool) -> [ContentType] {
        gatewayEnabled ? baseZoneOrder : [.normal, .token, .clipboard]
    }

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
        // 跟手感优化：由 300ms 缩紧至 120ms，移开后迅速平滑收拢
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    func cancelHoverClose() {
        hoverCloseWorkItem?.cancel()
        hoverCloseWorkItem = nil
    }

    /// 虚影态→展开态（点击/拖拽调用）
    func openFromGhost() {
        notchTimingMark("openFromGhost")
        cancelHoverClose()
        ghostGeneration += 1
        transitionActive = true
        withAnimation(openAnimation) {
            hoverGhosting = false
            ghostFading = false
            status = .opened
        }
        notchTimingMark("preActivate")
        NSApp.activate(ignoringOtherApps: true)
        notchTimingMark("postActivate")
    }

    /// 两段收起：先缩回虚影尺寸，再连贯平滑清态回刘海（消灭 200ms 半空生硬掐断）
    func closeToGhost() {
        openReason = .unknown
        transitionActive = true
        // stage 1: 走 closeAnimation 平滑吸缩回虚影尺寸
        withAnimation(closeAnimation) {
            status = .closed
            ghostFading = true
        }
        ghostGeneration += 1
        let generation = ghostGeneration
        // 等待 280ms 充分收缩到位，再平滑收纳回刘海屏顶
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { [weak self] in
            guard let self, generation == self.ghostGeneration else { return }
            withAnimation(self.closeAnimation) {
                self.ghostFading = false
                self.hoverGhosting = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) { [weak self] in
                self?.transitionActive = false
            }
        }
    }

    func notchOpen(_ reason: OpenReason) {
        openReason = reason
        if reason == .hover {
            // 虚影态：只置标记，不展开（点击/拖拽时才调 openFromGhost()）
            ghostGeneration += 1
            transitionActive = true
            withAnimation(openAnimation) {
                hoverGhosting = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) { [weak self] in
                if self?.status != .opened { self?.transitionActive = false }
            }
        } else {
            cancelHoverClose()
            ghostGeneration += 1
            transitionActive = true
            withAnimation(openAnimation) {
                hoverGhosting = false
                status = .opened
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func notchClose() {
        cancelHoverClose()
        ghostGeneration += 1
        transitionActive = true
        withAnimation(closeAnimation) {
            hoverGhosting = false
            ghostFading = false
            openReason = .unknown
            status = .closed
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { [weak self] in
            self?.transitionActive = false
        }
    }

    /// 设置 Popover 弹出状态：根齿轮与右键菜单共用（设置走 Popover 定案，不占分页）
    @Published var showSettings = false

    /// 功能区固定顺序：左右滑按此循环（概览｜Token｜网关）。网关页由 showGatewayZone 控制剔除。
    /// 单一事实来源 = ConfigStore 键 showGatewayZone（与 @PublishedPersist 同一持久层），默认开。
    static var zoneOrder: [ContentType] {
        zoneOrder(gatewayEnabled: ConfigStore.shared.get("showGatewayZone", fallback: true))
    }

    /// 页—区分区双向映射（TabView 分页地基，越界回概览）
    static func pageIndex(for zone: ContentType) -> Int {
        Self.zoneOrder.firstIndex(of: zone) ?? 0
    }

    static func zone(for page: Int) -> ContentType {
        let order = Self.zoneOrder
        guard order.indices.contains(page) else { return .normal }
        return order[page]
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
        withAnimation(pageAnimation) {
            contentType = zone
        }
    }

    func nextZone() {
        lastSwipeDirection = .next
        let order = Self.zoneOrder
        let idx = order.firstIndex(of: contentType) ?? 0
        withAnimation(pageAnimation) {
            contentType = order[(idx + 1) % order.count]
        }
    }

    func previousZone() {
        lastSwipeDirection = .previous
        let order = Self.zoneOrder
        let idx = order.firstIndex(of: contentType) ?? 0
        withAnimation(pageAnimation) {
            contentType = order[(idx + order.count - 1) % order.count]
        }
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
