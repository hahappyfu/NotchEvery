import XCTest
import AppKit
@testable import NotchEvery

/// NSHapticFeedbackPerformer 测试替身：统计触觉反馈调用
private final class HapticSpy: NSObject, NSHapticFeedbackPerformer {
    private(set) var performCount = 0

    func perform(
        _ pattern: NSHapticFeedbackManager.FeedbackPattern,
        performanceTime: NSHapticFeedbackManager.PerformanceTime
    ) {
        performCount += 1
    }
}

final class ClipboardPasterTests: XCTestCase {
    private var tempDir: URL!
    private var store: ClipboardStore!
    private var pasteboard: NSPasteboard!
    private var monitor: ClipboardMonitor!
    private var hapticSpy: HapticSpy!
    private var paster: ClipboardPaster!
    private var activatedApps: [NSRunningApplication] = []
    private var keystrokeCount = 0

    /// 本测试进程自身：默认过滤配置下应被排除；自定义 selfBundleIdentifier 时可充当“外部应用”替身
    private let currentApp = NSRunningApplication.current

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardPasterTests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = ClipboardStore(storageDirectory: tempDir)

        // 命名剪贴板隔离测试与系统剪贴板，避免污染用户真实剪贴板
        pasteboard = NSPasteboard(name: NSPasteboard.Name("ClipboardPasterTests-\(UUID().uuidString)"))
        pasteboard.clearContents()
        monitor = ClipboardMonitor(store: store, pasteboard: pasteboard)

        hapticSpy = HapticSpy()
        activatedApps = []
        keystrokeCount = 0
        paster = makePaster()
    }

    override func tearDown() {
        pasteboard?.releaseGlobally()
        if let tempDir = tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        super.tearDown()
    }

    // MARK: - Helpers

    /// 构造 paster：关闭工作区监听避免抓取测试机前台应用，
    /// 应用激活与按键注入均以 Spy 记录，绝不真的操作其它应用或注入系统按键
    private func makePaster(selfBundleIdentifier: String? = Bundle.main.bundleIdentifier) -> ClipboardPaster {
        ClipboardPaster(
            pasteboard: pasteboard,
            store: store,
            monitor: monitor,
            hapticPerformer: hapticSpy,
            selfBundleIdentifier: selfBundleIdentifier,
            trackWorkspace: false,
            activateApp: { [weak self] app in
                self?.activatedApps.append(app)
            },
            postPasteKeystroke: { [weak self] in
                self?.keystrokeCount += 1
            }
        )
    }

    /// 生成指定像素尺寸的 PNG 数据（与 store.addImage 入参一致的图片内容）
    private func makePNGData(width: Int, height: Int, color: NSColor = .systemRed) -> Data {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        color.setFill()
        NSRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)).fill()
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])!
    }

    /// 自旋主 RunLoop 直到条件满足或超时（等待 asyncAfter 延迟块执行）
    @discardableResult
    private func spinMainLoop(until condition: () -> Bool, timeout: TimeInterval = 2.0) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        return condition()
    }

    /// 排空主队列：自旋主 RunLoop 直到哨兵块执行，确保此前入队的 store 派发都已运行
    private func drainMainQueue(timeout: TimeInterval = 2.0) {
        var drained = false
        DispatchQueue.main.async { drained = true }
        let deadline = Date().addingTimeInterval(timeout)
        while !drained, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertTrue(drained, "主队列排空超时")
    }

    // MARK: - 前台应用追踪与过滤

    func testSelfAppActivationIsIgnored() {
        // 默认过滤基准即宿主进程自身（测试进程与主 bundle 同体）
        XCTAssertEqual(
            currentApp.bundleIdentifier,
            Bundle.main.bundleIdentifier,
            "前置条件：测试进程与主 bundle 标识应一致"
        )

        paster.trackActivatedApp(currentApp)

        XCTAssertNil(paster.lastActiveApp, "自身激活不应被记录为粘贴目标")
    }

    func testExternalAppActivationIsTracked() {
        // 换掉过滤基准，使本进程充当“外部应用”替身
        paster = makePaster(selfBundleIdentifier: "com.example.notch-every-other")

        paster.trackActivatedApp(currentApp)

        XCTAssertEqual(
            paster.lastActiveApp?.bundleIdentifier,
            currentApp.bundleIdentifier,
            "外部应用激活应被记录为粘贴目标"
        )
    }

    // MARK: - 文本写回与内部复制标记

    func testPasteTextWritesBackToPasteboardAndMarksInternalCopy() {
        paster = makePaster(selfBundleIdentifier: "com.example.notch-every-other")
        paster.trackActivatedApp(currentApp)

        paster.paste(item: ClipboardItem(type: .text, textContent: "Paste me", charCount: 8))

        XCTAssertEqual(pasteboard.string(forType: .string), "Paste me", "点击应把文本写回系统剪贴板")
        XCTAssertTrue(monitor.isInternalCopy, "写回剪贴板前应标记内部复制，防止监听器重复录入")
        XCTAssertEqual(hapticSpy.performCount, 1, "每次点击应触发恰好一次触觉反馈")
    }

    // MARK: - 图片写回

    func testPasteImageWritesStoredImageToPasteboard() {
        store.addImage(data: makePNGData(width: 60, height: 40), size: CGSize(width: 60, height: 40))
        guard let item = store.items.first, item.type == .image else {
            return XCTFail("store 应记录图片条目")
        }

        paster.paste(item: item)

        XCTAssertNotNil(NSImage(pasteboard: pasteboard), "点击应把落盘缩略图写回系统剪贴板")
        XCTAssertTrue(monitor.isInternalCopy, "图片写回同样应标记内部复制")
        XCTAssertEqual(hapticSpy.performCount, 1, "每次点击应触发恰好一次触觉反馈")
    }

    // MARK: - 目标应用激活与 Cmd+V 注入

    func testPasteActivatesTargetAppAndInjectsCommandVOnce() {
        paster = makePaster(selfBundleIdentifier: "com.example.notch-every-other")
        paster.trackActivatedApp(currentApp)

        paster.paste(item: ClipboardItem(type: .text, textContent: "inject me", charCount: 9))

        XCTAssertEqual(activatedApps.count, 1, "粘贴时应激活记录的目标应用")
        XCTAssertTrue(activatedApps.first === currentApp, "激活的应是最后记录的前台外部应用")
        XCTAssertEqual(keystrokeCount, 0, "按键注入应延迟到目标应用接管键盘事件之后")

        let injected = spinMainLoop(until: { self.keystrokeCount > 0 })
        XCTAssertTrue(injected, "延迟后应注入 Cmd+V 按键事件")
        XCTAssertEqual(keystrokeCount, 1, "一次粘贴只应注入一次按键")
    }

    func testPasteWithoutTargetOnlyCopiesToClipboard() {
        // trackWorkspace 关闭且未记录任何目标应用
        paster.paste(item: ClipboardItem(type: .text, textContent: "no target", charCount: 9))

        XCTAssertEqual(pasteboard.string(forType: .string), "no target", "无目标应用时仍应写回剪贴板")
        XCTAssertTrue(monitor.isInternalCopy, "无目标应用时同样应标记内部复制")
        XCTAssertEqual(hapticSpy.performCount, 1, "无目标应用时触觉反馈仍应触发")
        XCTAssertTrue(activatedApps.isEmpty, "无目标应用时不应尝试激活任何应用")

        // 等待超过注入延迟，确认没有按键注入
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(keystrokeCount, 0, "无目标应用时不应注入按键")
    }

    // MARK: - 防回环集成

    func testPastedContentIsNotReRecordedByMonitor() {
        paster = makePaster(selfBundleIdentifier: "com.example.notch-every-other")
        paster.trackActivatedApp(currentApp)
        paster.paste(item: ClipboardItem(type: .text, textContent: "no loop", charCount: 7))

        // 监听器下一次轮询应消费内部标记并跳过录入
        monitor.checkPasteboard()
        drainMainQueue()
        XCTAssertFalse(monitor.isInternalCopy, "内部标记应被消费复位")
        XCTAssertTrue(store.items.isEmpty, "自身写回的粘贴内容不应被重新录入历史")

        // 之后的外部复制仍应正常捕获
        pasteboard.clearContents()
        pasteboard.setString("external copy", forType: .string)
        monitor.checkPasteboard()
        drainMainQueue()
        XCTAssertEqual(store.items.first?.textContent, "external copy", "外部复制不应受内部标记影响")
    }
}
