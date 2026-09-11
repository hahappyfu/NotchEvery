//
//  NotchWindowController.swift
//  NotchDrop
//
//  Created by 秋星桥 on 2024/7/7.
//

import Cocoa
import Combine

private let notchHeight: CGFloat = 200

class NotchWindowController: NSWindowController {
    var vm: NotchViewModel?
    weak var screen: NSScreen?
    private var cancellables = Set<AnyCancellable>()
    /// hosting 高度约束：跟随窗口高度同步更新，保持面板顶对齐
    private var hostingHeightConstraint: NSLayoutConstraint?

    var openAfterCreate: Bool = false

    init(window: NSWindow, screen: NSScreen) {
        self.screen = screen

        super.init(window: window)

        var notchSize = screen.notchSize

        let vm = NotchViewModel(inset: notchSize == .zero ? 0 : -4)
        self.vm = vm
        contentViewController = NotchViewController(vm)

        // 窗口跟随测量尺寸（ADR-0008）：展开按钳制后面板高，收起回 200pt 条带。
        // 顶边贴屏顶，只往下长；hosting 高度约束同步更新，保持顶对齐。
        vm.$measuredNaturalSize
            .combineLatest(vm.$status, vm.$screenRect)
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak window, weak screen] _, status, _ in
                guard let window = window as? NotchWindow, let screen else { return }
                guard let vm = self?.vm else { return }
                let height: CGFloat
                if status == .opened {
                    height = vm.zoneOpenedSize.height
                } else {
                    height = notchHeight
                }
                window.pinnedContentSize = CGSize(width: screen.frame.width, height: height)
                let target = CGRect(
                    x: screen.frame.origin.x,
                    y: screen.frame.origin.y + screen.frame.height - height,
                    width: screen.frame.width,
                    height: height
                )
                if status == .opened {
                    // 内容自适应：窗口直接跟随测量值。切页（尤其收缩方向）测量分步下降，
                    // 若叠 0.3s animator 会被逐次打断、永久停在中间值，形成"卡卡缩回"；内容自身已有 SwiftUI 转场，窗口跟着走即可。
                    self?.hostingHeightConstraint?.constant = height
                    window.setFrame(target, display: true)
                    notchTimingMark("setFrame h=\(Int(height))")
                } else {
                    NSAnimationContext.runAnimationGroup { context in
                        context.duration = 0.3
                        self?.hostingHeightConstraint?.animator().constant = height
                        window.animator().setFrame(target, display: true)
                    }
                }
            }
            .store(in: &cancellables)

        if notchSize == .zero {
            notchSize = .init(width: 150, height: 28)
        }
        vm.deviceNotchRect = CGRect(
            x: screen.frame.origin.x + (screen.frame.width - notchSize.width) / 2,
            y: screen.frame.origin.y + screen.frame.height - notchSize.height,
            width: notchSize.width,
            height: notchSize.height
        )
        window.makeKeyAndOrderFront(nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak vm] in
            vm?.screenRect = screen.frame
            if self.openAfterCreate {
                vm?.notchOpen(.boot)
            }
            // TEMP-DEL: 截图验证耳区用，NOTCH_EARS=1 强制展开 Token 页
            if ProcessInfo.processInfo.environment["NOTCH_EARS"] == "1" {
                vm?.notchOpen(.boot)
                vm?.contentType = .token
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak vm] in
                    guard let vm else { return }
                    let msg = "DEBUG notch=\(vm.deviceNotchRect.size) panel=\(vm.zoneOpenedSize) safeTop=\(vm.notchSafeAreaTop) status=\(vm.status) window=\(String(describing: self.window?.frame))\n"
                    FileHandle.standardError.write(msg.data(using: .utf8)!)
                }
            }
            // TEMP-DEL: 截图验证 peek 用，NOTCH_GHOST=1 强制悬停虚影态（先收 boot 展开，0.2s 重复对抗 300ms 自动清）
            if ProcessInfo.processInfo.environment["NOTCH_GHOST"] == "1" {
                UsageStore.shared.start()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak vm] in
                    vm?.notchClose()
                }
                Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak vm] _ in
                    vm?.hoverGhosting = true
                }
            }
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError() }

    convenience init(screen: NSScreen) {
        let window = NotchWindow(
            contentRect: screen.frame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        self.init(window: window, screen: screen)

        let topRect = CGRect(
            x: screen.frame.origin.x,
            y: screen.frame.origin.y + screen.frame.height - notchHeight,
            width: screen.frame.width,
            height: notchHeight
        )
        window.pinnedContentSize = topRect.size
        window.setFrameOrigin(topRect.origin)
        window.setContentSize(topRect.size)

        // 宿主层保证：NSHostingView 会把高于窗口的内容垂直居中（历史：面板上溢致选项卡跑出屏幕）。
        // 用自管容器接管 contentView，hosting view 钉死 top、高度由约束跟随窗口，面板永远顶对齐。
        if let hostingView = contentViewController?.view {
            let container = NSView(frame: topRect)
            hostingView.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(hostingView)
            let heightConstraint = hostingView.heightAnchor.constraint(equalToConstant: notchHeight)
            hostingHeightConstraint = heightConstraint
            NSLayoutConstraint.activate([
                hostingView.topAnchor.constraint(equalTo: container.topAnchor),
                hostingView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                heightConstraint,
            ])
            window.contentView = container
        }
    }

    deinit {
        destroy()
    }

    func destroy() {
        cancellables.removeAll()
        vm?.destroy()
        vm = nil
        window?.close()
        contentViewController = nil
        window = nil
    }
}
