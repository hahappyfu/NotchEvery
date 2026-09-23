import AppKit
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
    /// 是否置顶：置顶项始终排在列表最前，且绝对豁免 50 条上限淘汰
    public var isPinned: Bool = false

    public init(
        id: UUID = UUID(),
        type: ClipboardItemType,
        textContent: String? = nil,
        imageFileName: String? = nil,
        charCount: Int = 0,
        imageWidth: CGFloat? = nil,
        imageHeight: CGFloat? = nil,
        copiedAt: Date = Date(),
        isPinned: Bool = false
    ) {
        self.id = id
        self.type = type
        self.textContent = textContent
        self.imageFileName = imageFileName
        self.charCount = charCount
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.copiedAt = copiedAt
        self.isPinned = isPinned
    }

    /// 兼容旧版本元数据：磁盘上缺失 isPinned 字段时默认非置顶，避免整体解码失败
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        type = try container.decode(ClipboardItemType.self, forKey: .type)
        textContent = try container.decodeIfPresent(String.self, forKey: .textContent)
        imageFileName = try container.decodeIfPresent(String.self, forKey: .imageFileName)
        charCount = try container.decodeIfPresent(Int.self, forKey: .charCount) ?? 0
        imageWidth = try container.decodeIfPresent(CGFloat.self, forKey: .imageWidth)
        imageHeight = try container.decodeIfPresent(CGFloat.self, forKey: .imageHeight)
        copiedAt = try container.decode(Date.self, forKey: .copiedAt)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
    }
}

public final class ClipboardStore: ObservableObject {
    public static let shared = ClipboardStore()

    public static let maxItemCount = 50
    private let storageDirectory: URL
    private let metadataURL: URL
    private let imagesDirectory: URL
    /// 缩略图内存缓存：消除快速滚动时的磁盘读取，保证满帧顺滑
    private let imageCache = NSCache<NSString, NSImage>()
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

        // 多端同步智能去重：比对全部置顶项 + 顶部前 3 条非置顶项（首尾空白规范化后）相同即视为云同步重复，丢弃不新增；
        // 置顶项再多也不挤占普通新内容的去重窗口
        let candidates = items.filter(\.isPinned) + items.filter { !$0.isPinned }.prefix(3)
        let isDuplicate = candidates.contains { item in
            item.type == .text
                && (item.textContent ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == trimmed
        }
        if isDuplicate { return }

        let item = ClipboardItem(
            type: .text,
            textContent: text,
            charCount: text.count,
            copiedAt: Date()
        )
        insertItem(item)
    }

    public func addImage(data: Data, size: CGSize) {
        // 多端同步智能去重：全部置顶项 + 顶部前 3 条非置顶项中已存在字节相同的图片则忽略
        let candidates = items.filter(\.isPinned) + items.filter { !$0.isPinned }.prefix(3)
        for existing in candidates where existing.type == .image {
            if let existingName = existing.imageFileName,
               let existingData = try? Data(contentsOf: imagesDirectory.appendingPathComponent(existingName)),
               existingData == data {
                return
            }
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

    /// 切换指定条目的置顶状态；置顶项始终前置且豁免 50 条上限淘汰。
    /// 取消置顶后该条目按 copiedAt 自然归位（非置顶区严格按复制时间倒序）。
    /// 触发 @Published 状态发布，并在串行队列异步落盘。
    public func togglePin(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        var updated = items
        updated[index].isPinned.toggle()
        let pinned = updated.filter(\.isPinned)
        let unpinned = updated.filter { !$0.isPinned }.sorted { $0.copiedAt > $1.copiedAt }
        items = pinned + unpinned
        saveToDisk()
    }

    public func imageURL(for item: ClipboardItem) -> URL? {
        guard let fileName = item.imageFileName else { return nil }
        return imagesDirectory.appendingPathComponent(fileName)
    }

    /// 高速获取缩略图：优先命中内存缓存
    public func image(for item: ClipboardItem) -> NSImage? {
        guard let fileName = item.imageFileName else { return nil }
        let key = fileName as NSString
        if let cached = imageCache.object(forKey: key) {
            return cached
        }
        guard let url = imageURL(for: item), let image = NSImage(contentsOf: url) else { return nil }
        imageCache.setObject(image, forKey: key)
        return image
    }

    public func clearAll() {
        items.removeAll()
        imageCache.removeAllObjects()
        try? FileManager.default.removeItem(at: metadataURL)
        if let files = try? FileManager.default.contentsOfDirectory(at: imagesDirectory, includingPropertiesForKeys: nil) {
            for file in files {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    private func insertItem(_ item: ClipboardItem) {
        // 置顶项恒在最前：新条目插入到全部置顶项之后（普通区头部）
        let insertIndex = items.firstIndex(where: { !$0.isPinned }) ?? items.count
        items.insert(item, at: insertIndex)

        // 淘汰超过 50 条的最老条目：置顶项绝对豁免，仅淘汰最老的非置顶项；全为置顶时兜底淘汰最老一项
        while items.count > Self.maxItemCount, let evicted = removeOldestEvictable(from: &items) {
            removeImageFile(of: evicted)
        }
        saveToDisk()
    }

    /// 从列表尾部移除最老的可淘汰条目（优先非置顶项；全部置顶时兜底移除最老一项）
    private func removeOldestEvictable(from list: inout [ClipboardItem]) -> ClipboardItem? {
        guard !list.isEmpty else { return nil }
        let index = list.lastIndex(where: { !$0.isPinned }) ?? list.index(before: list.endIndex)
        return list.remove(at: index)
    }

    /// 同步清理图片条目被淘汰后的内存缓存与磁盘文件
    private func removeImageFile(of item: ClipboardItem) {
        guard let imgName = item.imageFileName else { return }
        imageCache.removeObject(forKey: imgName as NSString)
        let imgURL = imagesDirectory.appendingPathComponent(imgName)
        try? FileManager.default.removeItem(at: imgURL)
    }

    /// 稳定分区：置顶项保持原有相对顺序整体前置，非置顶项紧随其后
    private static func pinnedFirst(_ list: [ClipboardItem]) -> [ClipboardItem] {
        list.filter(\.isPinned) + list.filter { !$0.isPinned }
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
            // 恢复时与运行时同规则：置顶项前置且豁免淘汰；
            // 磁盘数据若超过上限（历史版本或手工修改），仅按序淘汰最老的非置顶条目并清理其图片文件
            var restored = Self.pinnedFirst(decoded)
            while restored.count > Self.maxItemCount, let evicted = removeOldestEvictable(from: &restored) {
                removeImageFile(of: evicted)
            }
            self.items = restored
        }
    }
}
