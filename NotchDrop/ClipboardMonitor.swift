import Cocoa
import Foundation

/// 系统剪贴板监听器：低频轮询 `NSPasteboard.changeCount`，捕获用户复制的文本与图片。
///
/// - 仅当 changeCount 变化时才读取剪贴板内容，未变化时不做任何解析（零开销路径）。
/// - 捕获到的内容一律通过主队列派发给 `store`，保证 UI 状态更新在主线程。
/// - 通过 `isInternalCopy` 标志过滤自身写回剪贴板的动作（粘贴注入防回环）。
public final class ClipboardMonitor {
    public static let shared = ClipboardMonitor()

    /// 轮询间隔（秒）：低频轮询以降低空闲能耗
    public static let pollInterval: TimeInterval = 0.6
    /// 缩略图最长边像素上限：图片只落盘压缩后的缩略图，不持有大尺寸原图
    public static let maxThumbnailDimension: CGFloat = 400

    private let store: ClipboardStore
    private let pasteboard: NSPasteboard
    private var timer: Timer?
    private var lastChangeCount: Int

    /// 自身写入剪贴板前应置为 true，下一次检测到的变更将被消费并跳过记录（仅主线程访问）
    public var isInternalCopy: Bool = false

    public init(store: ClipboardStore = .shared, pasteboard: NSPasteboard = .general) {
        self.store = store
        self.pasteboard = pasteboard
        self.lastChangeCount = pasteboard.changeCount
    }

    /// 启动低频轮询（需在主线程调用）
    public func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            self?.checkPasteboard()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// 检查一次剪贴板；changeCount 未变化时立即返回
    public func checkPasteboard() {
        let currentCount = pasteboard.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        // 自身写回的变更：消费标志并跳过本次记录
        if isInternalCopy {
            isInternalCopy = false
            return
        }

        // 1. 文本优先
        if let string = pasteboard.string(forType: .string),
           !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            deliver { store in
                store.addText(string)
            }
            return
        }

        // 2. 图片：只保存最长边 400px 的 PNG 缩略图
        guard let image = NSImage(pasteboard: pasteboard),
              image.size.width > 0, image.size.height > 0 else { return }
        let originalSize = image.size
        guard let pngData = Self.makeThumbnailPNG(from: image, maxDimension: Self.maxThumbnailDimension) else { return }

        deliver { store in
            store.addImage(data: pngData, size: originalSize)
        }
    }

    // MARK: - 内部实现

    /// 统一把 store 更新派发到主队列
    private func deliver(_ action: @escaping (ClipboardStore) -> Void) {
        let store = self.store
        DispatchQueue.main.async {
            action(store)
        }
    }

    /// 生成最长边不超过 `maxDimension` 的 PNG 缩略图数据；小图不放大
    private static func makeThumbnailPNG(from image: NSImage, maxDimension: CGFloat) -> Data? {
        let originalSize = image.size
        guard originalSize.width > 0, originalSize.height > 0 else { return nil }

        let ratio = min(1, min(maxDimension / originalSize.width, maxDimension / originalSize.height))
        let targetSize = CGSize(
            width: max(1, (originalSize.width * ratio).rounded()),
            height: max(1, (originalSize.height * ratio).rounded())
        )

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(targetSize.width),
            pixelsHigh: Int(targetSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: originalSize),
            operation: .copy,
            fraction: 1.0
        )
        NSGraphicsContext.restoreGraphicsState()

        return bitmap.representation(using: .png, properties: [:])
    }
}
