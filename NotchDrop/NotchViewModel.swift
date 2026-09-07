import Cocoa
import Combine
import Foundation
import LaunchAtLogin
import SwiftUI

// MARK: - NotchGeometry（#24 拆分：纯几何计算）

struct NotchGeometry {
    var deviceNotchRect: CGRect
    var screenRect: CGRect
    var notchOpenedSize: CGSize
    let inset: CGFloat

    var notchOpenedRect: CGRect {
        .init(
            x: screenRect.origin.x + (screenRect.width - notchOpenedSize.width) / 2,
            y: screenRect.origin.y + screenRect.height - notchOpenedSize.height,
            width: notchOpenedSize.width,
            height: notchOpenedSize.height
        )
    }

    var headlineOpenedRect: CGRect {
        .init(
            x: screenRect.origin.x + (screenRect.width - notchOpenedSize.width) / 2,
            y: screenRect.origin.y + screenRect.height - deviceNotchRect.height,
            width: notchOpenedSize.width,
            height: deviceNotchRect.height
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

    let animation: Animation = .interactiveSpring(
        duration: 0.5,
        extraBounce: 0.25,
        blendDuration: 0.125
    )
    let notchOpenedSize: CGSize = .init(width: 600, height: 160)
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
        case menu
        case settings
    }

    // ——— 几何经由 NotchGeometry 计算，Published 仍在门面以保持绑定 ———
    var geometry: NotchGeometry {
        NotchGeometry(
            deviceNotchRect: deviceNotchRect,
            screenRect: screenRect,
            notchOpenedSize: notchOpenedSize,
            inset: inset
        )
    }

    var notchOpenedRect: CGRect { geometry.notchOpenedRect }
    var headlineOpenedRect: CGRect { geometry.headlineOpenedRect }

    @Published private(set) var status: Status = .closed
    @Published var openReason: OpenReason = .unknown
    @Published var contentType: ContentType = .normal

    @Published var spacing: CGFloat = 20
    @Published var cornerRadius: CGFloat = 20
    @Published var deviceNotchRect: CGRect = .zero
    @Published var screenRect: CGRect = .zero
    @Published var optionKeyPressed: Bool = false
    @Published var notchVisible: Bool = true
    @Published var hoverGhosting: Bool = false
    /// 两段收起中间态：保持虚影视觉 200ms 再清态
    @Published private(set) var ghostFading: Bool = false
    /// 过桥菊花：openFromGhost 后短闪 150ms
    @Published private(set) var bridgeSpinning: Bool = false

    /// 展开弹簧（380/30/0.8 换算真值，轻微过冲）
    let openAnimation: Animation = .spring(response: 0.32, dampingFraction: 0.86)
    /// 收起弹簧（无过冲快退）
    let closeAnimation: Animation = .spring(response: 0.24, dampingFraction: 1.0)

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
        cancelHoverClose()
        ghostGeneration += 1
        hoverGhosting = false
        ghostFading = false
        bridgeSpinning = true
        status = .opened
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.bridgeSpinning = false
        }
    }

    /// 两段收起：先缩回虚影尺寸 200ms，再清态回刘海
    func closeToGhost() {
        openReason = .unknown
        contentType = .normal
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
        contentType = .normal
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
            contentType = .normal
        }
    }

    func showSettings() {
        contentType = .settings
    }

    /// 功能区固定顺序：左右滑按此循环
    static let zoneOrder: [ContentType] = [.normal, .menu, .settings]

    /// 最近一次切换方向：内容区不对称过渡用
    @Published var lastSwipeDirection: SwipeDirection = .next

    /// 圆点点击已通过 onTapGesture 直跳，消费掉随后到达的 mouseDown，避免一次点击两次切换
    var suppressHeadlineClickOnce = false

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
        suppressHeadlineClickOnce = true
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
