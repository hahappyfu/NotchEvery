//
//  MagpieIconResolver.swift
//  NotchEvery
//
//  Magpie 动态图标：位图同步加载、SVG 走 QuickLook 异步缩略图，兜底由 UI 层绘制。
//

import AppKit
import Foundation
import QuickLookThumbnailing

final class MagpieIconResolver {
    static let shared = MagpieIconResolver()

    private let paths: MagpiePaths
    private let cacheDirectory: URL
    private var icons: [String: String]
    private var loadedIconSignature: IconSignature?
    private let tracksFileChanges: Bool
    private let cache = NSCache<NSString, NSImage>()

    init(
        paths: MagpiePaths = .init(),
        cacheDirectory: URL? = nil,
        icons: [String: String]? = nil,
        tracksFileChanges: Bool = true
    ) {
        self.paths = paths
        self.tracksFileChanges = tracksFileChanges
        self.cacheDirectory = cacheDirectory ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/magpie/icons-small")
        if let icons {
            self.icons = icons
            self.loadedIconSignature = iconFileSignature()
        } else {
            self.icons = [:]
            reloadIconsIfNeeded()
        }
    }

    /// plugin-icons.json 的 mtime + size 变化时才重读，避免每次刷新都解析。
    func reloadIconsIfNeeded() {
        guard tracksFileChanges else { return }
        let signature = iconFileSignature()
        guard signature != loadedIconSignature, let signature else { return }
        guard let data = try? Data(contentsOf: paths.pluginIconsFile),
              let parsed = MagpieFiles.parsePluginIcons(data) else { return }
        loadedIconSignature = signature
        icons = parsed
    }

    private struct IconSignature: Equatable {
        let mtime: Date
        let size: Int
    }

    private func iconFileSignature() -> IconSignature? {
        var info = stat()
        guard stat(paths.pluginIconsFile.path, &info) == 0 else { return nil }
        let size = Int(info.st_size)
        let mtime = Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec)
                         + TimeInterval(info.st_mtimespec.tv_nsec) / 1_000_000_000)
        return IconSignature(mtime: mtime, size: size)
    }

    /// cache 优先、config icons 后备；非 file: 标识先经 plugin-icons 映射。
    func candidateURLs(for icon: String?) -> [URL] {
        guard let raw = icon, !raw.isEmpty else { return [] }
        let fileName: String
        if raw.hasPrefix("file:") {
            fileName = String(raw.dropFirst("file:".count))
        } else if let mapped = icons[raw], mapped.hasPrefix("file:") {
            fileName = String(mapped.dropFirst("file:".count))
        } else {
            return []
        }
        guard !fileName.isEmpty else { return [] }
        return [
            cacheDirectory.appendingPathComponent(fileName + ".png"),
            paths.root.appendingPathComponent("icons").appendingPathComponent(fileName)
        ]
    }

    /// 同步取图：位图（PNG/WebP/JPG）与已缓存的 SVG。
    func image(for icon: String?) -> NSImage? {
        guard let url = existingURL(for: icon) else { return nil }
        let key = url.path as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard url.pathExtension.lowercased() != "svg", let image = NSImage(contentsOf: url) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    /// 异步取图：SVG 生成 32×32 缩略图并缓存；回调在主线程。
    func loadImage(for icon: String?, completion: @escaping (NSImage?) -> Void) {
        guard let url = existingURL(for: icon) else { return completion(nil) }
        let key = url.path as NSString
        if let cached = cache.object(forKey: key) { return completion(cached) }
        guard url.pathExtension.lowercased() == "svg" else { return completion(nil) }

        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: 32, height: 32),
            scale: 2,
            representationTypes: .thumbnail
        )
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, _ in
            let image = representation?.nsImage
            if let image {
                self?.cache.setObject(image, forKey: key)
            }
            DispatchQueue.main.async { completion(image) }
        }
    }

    /// 稳定哈希色相（0..<1），供兜底渐变使用。
    func fallbackHue(for providerID: String) -> Double {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in providerID.utf8 {
            hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }
        return Double(hash % 360) / 360
    }

    func initial(for providerID: String) -> String {
        guard let first = providerID.first else { return "?" }
        return String(first).uppercased()
    }

    private func existingURL(for icon: String?) -> URL? {
        candidateURLs(for: icon).first { FileManager.default.fileExists(atPath: $0.path) }
    }
}
