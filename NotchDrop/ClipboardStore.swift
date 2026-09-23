import Foundation
import SwiftUI

public enum ClipboardItemType: String, Codable, Hashable {
    case text
    case image
}

public struct ClipboardItem: Identifiable, Codable, Equatable {
    public let id: UUID
    public let type: ClipboardItemType
    public let textContent: String?
    public let imageFileName: String?
    public let charCount: Int
    public let imageWidth: CGFloat?
    public let imageHeight: CGFloat?
    public let copiedAt: Date

    public init(
        id: UUID = UUID(),
        type: ClipboardItemType,
        textContent: String? = nil,
        imageFileName: String? = nil,
        charCount: Int = 0,
        imageWidth: CGFloat? = nil,
        imageHeight: CGFloat? = nil,
        copiedAt: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.textContent = textContent
        self.imageFileName = imageFileName
        self.charCount = charCount
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.copiedAt = copiedAt
    }
}

public final class ClipboardStore: ObservableObject {
    public static let shared = ClipboardStore()

    public static let maxItemCount = 50
    private let storageDirectory: URL
    private let metadataURL: URL
    private let imagesDirectory: URL
    /// 串行写盘队列：保证多次保存按调用顺序落盘，且不在调用线程做 I/O
    private let saveQueue = DispatchQueue(label: "com.hahappyfu.NotchEvery.clipboard-store-writer", qos: .utility)

    @Published public private(set) var items: [ClipboardItem] = []

    public init(storageDirectory: URL? = nil) {
        let baseDir: URL
        if let custom = storageDirectory {
            baseDir = custom
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            baseDir = appSupport.appendingPathComponent("NotchEvery/Clipboard", isDirectory: true)
        }
        self.storageDirectory = baseDir
        self.metadataURL = baseDir.appendingPathComponent("clipboard_history.json")
        self.imagesDirectory = baseDir.appendingPathComponent("Images", isDirectory: true)

        try? FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        loadFromDisk()
    }

    public func addText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // 去重：与顶部条目完全一致则忽略
        if let first = items.first, first.type == .text, first.textContent == text {
            return
        }

        let item = ClipboardItem(
            type: .text,
            textContent: text,
            charCount: text.count,
            copiedAt: Date()
        )
        insertItem(item)
    }

    public func addImage(data: Data, size: CGSize) {
        // 去重：与顶部图片条目内容完全一致（文件字节相同）则忽略
        if let first = items.first, first.type == .image,
           let existingName = first.imageFileName,
           let existingData = try? Data(contentsOf: imagesDirectory.appendingPathComponent(existingName)),
           existingData == data {
            return
        }

        let id = UUID()
        let fileName = "\(id.uuidString).png"
        let fileURL = imagesDirectory.appendingPathComponent(fileName)

        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            return
        }

        let item = ClipboardItem(
            id: id,
            type: .image,
            imageFileName: fileName,
            imageWidth: size.width,
            imageHeight: size.height,
            copiedAt: Date()
        )
        insertItem(item)
    }

    public func imageURL(for item: ClipboardItem) -> URL? {
        guard let fileName = item.imageFileName else { return nil }
        return imagesDirectory.appendingPathComponent(fileName)
    }

    public func clearAll() {
        items.removeAll()
        try? FileManager.default.removeItem(at: metadataURL)
        if let files = try? FileManager.default.contentsOfDirectory(at: imagesDirectory, includingPropertiesForKeys: nil) {
            for file in files {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    private func insertItem(_ item: ClipboardItem) {
        items.insert(item, at: 0)

        // 淘汰超过 50 条的最老项
        while items.count > Self.maxItemCount {
            if let evicted = items.popLast(), let imgName = evicted.imageFileName {
                let imgURL = imagesDirectory.appendingPathComponent(imgName)
                try? FileManager.default.removeItem(at: imgURL)
            }
        }
        saveToDisk()
    }

    private func saveToDisk() {
        // 先在调用线程（主线程）取 items 快照，后台串行队列只写这份不可变副本，消除并发数据竞争
        let snapshot = items
        let url = metadataURL
        saveQueue.async {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(snapshot) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: metadataURL.path),
              let data = try? Data(contentsOf: metadataURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([ClipboardItem].self, from: data) {
            // 磁盘数据若超过上限（历史版本或手工修改），截断保留最新的 maxItemCount 条
            self.items = Array(decoded.prefix(Self.maxItemCount))
        }
    }
}
