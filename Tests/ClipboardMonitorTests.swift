import XCTest
import AppKit
@testable import NotchEvery

final class ClipboardMonitorTests: XCTestCase {
    private var tempDir: URL!
    private var store: ClipboardStore!
    private var pasteboard: NSPasteboard!
    private var monitor: ClipboardMonitor!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("ClipboardMonitorTests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = ClipboardStore(storageDirectory: tempDir)

        // 命名剪贴板隔离测试与系统剪贴板，避免互相污染
        pasteboard = NSPasteboard(name: NSPasteboard.Name("ClipboardMonitorTests-\(UUID().uuidString)"))
        pasteboard.clearContents()
        monitor = ClipboardMonitor(store: store, pasteboard: pasteboard)
    }

    override func tearDown() {
        monitor?.stop()
        pasteboard?.releaseGlobally()
        if let tempDir = tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        super.tearDown()
    }

    // MARK: - Helpers

    /// 写入文本并触发一次剪贴板检查
    private func writeTextAndCheck(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        monitor.checkPasteboard()
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

    /// 自旋主 RunLoop 直到条件满足或超时（用于等待定时器触发）
    @discardableResult
    private func spinMainLoop(until condition: () -> Bool, timeout: TimeInterval = 2.0) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        return condition()
    }

    private func makeImage(width: Int, height: Int, color: NSColor = .systemRed) -> NSImage {
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

        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(bitmap)
        return image
    }

    /// 读取 PNG 文件的像素尺寸
    private func pngPixelSize(at url: URL) -> (width: Int, height: Int)? {
        guard let data = try? Data(contentsOf: url),
              let rep = NSBitmapImageRep(data: data) else { return nil }
        return (rep.pixelsWide, rep.pixelsHigh)
    }

    // MARK: - 文本捕获

    func testCapturesExternalTextChange() {
        writeTextAndCheck("Hello Clipboard")
        drainMainQueue()

        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items.first?.type, .text)
        XCTAssertEqual(store.items.first?.textContent, "Hello Clipboard")
        XCTAssertEqual(store.items.first?.charCount, 15)
    }

    func testWhitespaceOnlyTextIsIgnored() {
        writeTextAndCheck("  \n\t ")
        drainMainQueue()

        XCTAssertTrue(store.items.isEmpty, "纯空白文本不应被记录")
    }

    func testUnchangedPasteboardIsNotReprocessed() {
        writeTextAndCheck("Only Once")
        drainMainQueue()
        XCTAssertEqual(store.items.count, 1)

        store.clearAll()
        monitor.checkPasteboard() // changeCount 未变化，应直接短路
        drainMainQueue()

        XCTAssertTrue(store.items.isEmpty, "changeCount 未变化时不应重新读取并记录内容")
    }

    // MARK: - 内部写防回环

    func testInternalCopyFlagPreventsRecordingAndResets() {
        monitor.isInternalCopy = true
        writeTextAndCheck("Internal Write")
        drainMainQueue()

        XCTAssertTrue(store.items.isEmpty, "内部写入不应被重新记录")
        XCTAssertFalse(monitor.isInternalCopy, "消费内部变更后标志应复位")

        // 复位后，外部变更应正常捕获
        writeTextAndCheck("External After Internal")
        drainMainQueue()
        XCTAssertEqual(store.items.first?.textContent, "External After Internal")
    }

    // MARK: - 图片捕获与缩略图

    func testCapturesLargeImageAsMax400pxPNGThumbnail() {
        let image = makeImage(width: 800, height: 600)
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([image]), "图片写入剪贴板失败")
        monitor.checkPasteboard()
        drainMainQueue()

        XCTAssertEqual(store.items.count, 1)
        guard let item = store.items.first, item.type == .image else {
            return XCTFail("应记录图片条目")
        }
        // 条目记录的是原图尺寸
        XCTAssertEqual(item.imageWidth ?? 0, 800, accuracy: 2)
        XCTAssertEqual(item.imageHeight ?? 0, 600, accuracy: 2)

        // 落盘的是最长边 400px 的 PNG 缩略图（800x600 -> 400x300）
        guard let url = store.imageURL(for: item), let size = pngPixelSize(at: url) else {
            return XCTFail("缩略图文件缺失或不可解码")
        }
        XCTAssertEqual(size.width, 400)
        XCTAssertEqual(size.height, 300)
    }

    func testSmallImageIsNotUpscaled() {
        let image = makeImage(width: 100, height: 80)
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([image]), "图片写入剪贴板失败")
        monitor.checkPasteboard()
        drainMainQueue()

        guard let item = store.items.first, item.type == .image,
              let url = store.imageURL(for: item), let size = pngPixelSize(at: url) else {
            return XCTFail("应记录图片条目并可读取缩略图")
        }
        XCTAssertEqual(size.width, 100)
        XCTAssertEqual(size.height, 80)
    }

    // MARK: - 主线程派发

    func testStoreDeliveryHappensOnMainQueue() {
        pasteboard.clearContents()
        pasteboard.setString("Delivered On Main", forType: .string)

        // 主线程被信号量阻塞期间主队列无法排空：若实现直接在后台线程写 store，此处就会看到条目
        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            self.monitor.checkPasteboard()
            finished.signal()
        }
        finished.wait()

        XCTAssertTrue(store.items.isEmpty, "后台线程触发时应异步派发到主队列，而不是立即写入 store")

        drainMainQueue()
        XCTAssertEqual(store.items.first?.textContent, "Delivered On Main")
    }

    // MARK: - 定时轮询启停

    func testStartPollsAndCapturesChange() {
        monitor.start()
        pasteboard.clearContents()
        pasteboard.setString("Timer Capture", forType: .string)

        let captured = spinMainLoop(until: { !self.store.items.isEmpty })
        XCTAssertTrue(captured, "0.6s 轮询应捕获外部变更")
        XCTAssertEqual(store.items.first?.textContent, "Timer Capture")
    }

    func testStopHaltsPolling() {
        monitor.start()
        monitor.stop()
        pasteboard.clearContents()
        pasteboard.setString("After Stop", forType: .string)

        RunLoop.main.run(until: Date().addingTimeInterval(1.2))
        XCTAssertTrue(store.items.isEmpty, "stop 后不应再捕获变更")
    }
}
