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
        let workspacePreviewImageData: Data
        /// 预览独立文件路径（新增，旧数据为空则回落到 Data）
        var previewFileName: String? = nil

        enum CodingKeys: String, CodingKey {
            case id, fileName, size, copiedDate, workspacePreviewImageData, previewFileName
        }

        init(url: URL) throws {
            assert(!Thread.isMainThread)

            id = UUID()
            fileName = url.lastPathComponent
            size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            copiedDate = Date()
            let pngData = url.snapshotPreview().pngRepresentation
            workspacePreviewImageData = pngData
            // 同步落盘预览文件，供后续读取（#18 外置，旧 Data 字段保留作迁移兼容）
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
    }
}

extension TrayDrop.DropItem: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        let exportingBehavior: @Sendable (TrayDrop.DropItem) async throws -> SentTransferredFile = { input in
            let tempDir = temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let newPath = tempDir.appendingPathComponent(input.fileName)
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
            .appendingPathComponent(fileName)
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
        let img = NSImage(data: workspacePreviewImageData) ?? NSImage()
        Self.previewCache.setObject(img, forKey: key)
        return img
    }

    var shouldClean: Bool {
        if !FileManager.default.fileExists(atPath: storageURL.path) { return true }
        let keepInterval = TrayDrop.shared.keepInterval
        guard keepInterval > 0 else { return true } // avoid non-reasonable value deleting user's files
        if Date().timeIntervalSince(copiedDate) > TrayDrop.shared.keepInterval { return true }
        return false
    }
}
