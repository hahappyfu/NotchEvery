//
//  TrayDrop+DropItem.swift
//  TrayDrop
//
//  Created by 秋星桥 on 2024/7/8.
//

import Cocoa
import CoreTransferable
import Foundation
import QuickLook
import UniformTypeIdentifiers

extension TrayDrop {
    struct DropItem: Identifiable, Codable, Equatable, Hashable {
        let id: UUID
        let fileName: String
        let size: Int
        let copiedDate: Date
        /// 预览独立文件路径（外置，Config/Previews）。
        var previewFileName: String? = nil
        /// 旧版内联预览 Data（多 MB，卡顿主因）。仅旧数据解码兜底用；
        /// 自编 Codable 不再写出，load 时一次性迁移到外置文件后置空。
        var workspacePreviewImageData: Data? = nil

        private enum CodingKeys: String, CodingKey {
            case id, fileName, size, copiedDate, previewFileName, workspacePreviewImageData
        }

        init(url: URL) throws {
            assert(!Thread.isMainThread)

            id = UUID()
            fileName = url.lastPathComponent
            size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            copiedDate = Date()
            // 预览外置文件（#18），不再内联进持久化
            let pngData = url.snapshotPreview().pngRepresentation
            let previewDir = documentsDirectory.appendingPathComponent("Config/Previews")
            try? FileManager.default.createDirectory(at: previewDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let pfn = "\(id.uuidString).png"
            let previewURL = previewDir.appendingPathComponent(pfn)
            try? pngData.write(to: previewURL, options: .atomic)
            previewFileName = pfn

            try FileManager.default.createDirectory(
                at: storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.copyItem(at: url, to: storageURL)
        }

        // 自编 Codable：只编轻量字段，省略多 MB 图片 Data（旧版存过，不再回写）
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(UUID.self, forKey: .id)
            fileName = try c.decode(String.self, forKey: .fileName)
            size = try c.decode(Int.self, forKey: .size)
            copiedDate = try c.decode(Date.self, forKey: .copiedDate)
            previewFileName = try c.decodeIfPresent(String.self, forKey: .previewFileName)
            workspacePreviewImageData = try c.decodeIfPresent(Data.self, forKey: .workspacePreviewImageData)
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encode(fileName, forKey: .fileName)
            try c.encode(size, forKey: .size)
            try c.encode(copiedDate, forKey: .copiedDate)
            try c.encodeIfPresent(previewFileName, forKey: .previewFileName)
            // 有意省略 workspacePreviewImageData：外置预览已接管，避免多 MB 持久化风暴
        }
    }
}

extension TrayDrop.DropItem: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        let exportingBehavior: @Sendable (TrayDrop.DropItem) async throws -> SentTransferredFile = { input in
            let tempDir = temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let newPath = tempDir.appendingPathComponent(input.fileName.sanitizedFileName)
            try FileManager.default.copyItem(
                at: input.storageURL,
                to: newPath
            )
            return .init(newPath, allowAccessingOriginalFile: true)
        }
        let importingBehavior: @Sendable (ReceivedTransferredFile) async throws -> TrayDrop.DropItem = { _ in
            fatalError()
        }
        return FileRepresentation(
            contentType: .data,
            shouldAttemptToOpenInPlace: true,
            exporting: exportingBehavior,
            importing: importingBehavior
        )
    }
}

extension TrayDrop.DropItem {
    static let mainDir = "CopiedItems"
    static let previewDir = "Config/Previews"

    var storageURL: URL {
        documentsDirectory
            .appendingPathComponent(Self.mainDir)
            .appendingPathComponent(id.uuidString)
            // fileName 来自持久化配置回读，二次消毒防篡改后的路径穿越
            .appendingPathComponent(fileName.sanitizedFileName)
    }

    /// 一次性迁移：旧数据内联 Preview Data → 外置文件（无 previewFileName 时）。
    /// 迁移完清空 Data，随下次持久化自然丢弃多 MB 载荷。返回是否可重用（迁移成功才置回 items）。
    mutating func migratePreviewIfNeeded() -> Bool {
        guard previewFileName == nil, let data = workspacePreviewImageData else { return true }
        let previewDir = documentsDirectory.appendingPathComponent(Self.previewDir)
        try? FileManager.default.createDirectory(at: previewDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let pfn = "\(id.uuidString).png"
        let previewURL = previewDir.appendingPathComponent(pfn)
        guard (try? data.write(to: previewURL, options: .atomic)) != nil else { return false }
        previewFileName = pfn
        workspacePreviewImageData = nil
        return true
    }

    private static let previewCache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 200
        return c
    }()

    var workspacePreviewImage: NSImage {
        let key = id.uuidString as NSString
        if let cached = Self.previewCache.object(forKey: key) { return cached }
        // 优先从独立文件读取
        if let pfn = previewFileName {
            let previewURL = documentsDirectory.appendingPathComponent(Self.previewDir).appendingPathComponent(pfn)
            if let data = try? Data(contentsOf: previewURL), let img = NSImage(data: data) {
                Self.previewCache.setObject(img, forKey: key)
                return img
            }
        }
        let img = NSImage(data: workspacePreviewImageData ?? Data()) ?? NSImage()
        Self.previewCache.setObject(img, forKey: key)
        return img
    }

    var shouldClean: Bool {
        if !FileManager.default.fileExists(atPath: storageURL.path) { return true }
        // 钳制下界（1 分钟）：自定义天数输入 0/负数或历史坏值会把 keepInterval 变 ≤0，
        // 走到这会让所有暂存启动即被判删（原 guard 注释意图与行为相反）
        let keepInterval = max(TrayDrop.shared.keepInterval, 60)
        if Date().timeIntervalSince(copiedDate) > keepInterval { return true }
        return false
    }
}
