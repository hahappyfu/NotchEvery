//
//  Ext+FileProvider.swift
//  NotchDrop
//
//  Created by 秋星桥 on 2024/7/8.
//

import Cocoa
import Foundation
import UniformTypeIdentifiers

extension NSItemProvider {
    // ——— 修复 #12: 校验符号链接与路径穿越 ———
    private func sanitizedFileName(_ name: String) -> String {
        // 拒绝路径分隔符与空名，截断过长
        var s = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { s = UUID().uuidString }
        s = s.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        if s.count > 200 { s = String(s.prefix(200)) }
        return s
    }

    private func duplicateToOurStorage(_ url: URL?) throws -> URL {
        guard let url else { throw NSError(domain: "NotchDrop", code: 1, userInfo: [NSLocalizedDescriptionKey: "empty url"]) }

        // 拒绝非文件 URL 与符号链接
        guard url.isFileURL else { throw NSError(domain: "NotchDrop", code: 2, userInfo: [NSLocalizedDescriptionKey: "not a file URL"]) }
        var st = stat()
        if lstat(url.path, &st) == 0, (st.st_mode & S_IFMT) == S_IFLNK {
            throw NSError(domain: "NotchDrop", code: 3, userInfo: [NSLocalizedDescriptionKey: "symbolic link not allowed"])
        }
        // 大小上限 2GB
        if let sz = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, sz > 2 * 1024 * 1024 * 1024 {
            throw NSError(domain: "NotchDrop", code: 4, userInfo: [NSLocalizedDescriptionKey: "file too large (>2GB)"])
        }

        let temp = temporaryDirectory
            .appendingPathComponent("TemporaryDrop")
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(sanitizedFileName(url.lastPathComponent))
        try? FileManager.default.createDirectory(
            at: temp.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // 若源仍为链接则拒绝拷贝（double check）
        var st2 = stat()
        if lstat(url.path, &st2) == 0, (st2.st_mode & S_IFMT) == S_IFLNK {
            throw NSError(domain: "NotchDrop", code: 3, userInfo: nil)
        }
        try FileManager.default.copyItem(at: url, to: temp)
        return temp
    }

    // ——— 修复 #1/#17: 信号量无超时+主线程死锁 → 改为带超时与主线程保护 ———
    func convertToFilePathThatIsWhatWeThinkItWillWorkWithNotchDrop() -> URL? {
        // 主线程直接拒绝，避免死锁
        if Thread.isMainThread {
            assertionFailure("convertToFilePath must not be called on main thread")
            return nil
        }
        var url: URL?
        let sem = DispatchSemaphore(value: 0)
        let timeout: DispatchTime = .now() + 8 // 8 秒超时
        var signaled = false

        _ = loadObject(ofClass: URL.self) { item, _ in
            if !signaled {
                url = try? self.duplicateToOurStorage(item)
                signaled = true
            }
            sem.signal()
        }
        if sem.wait(timeout: timeout) == .timedOut {
            return nil
        }
        if url == nil {
            signaled = false
            let sem2 = DispatchSemaphore(value: 0)
            loadInPlaceFileRepresentation(
                forTypeIdentifier: UTType.data.identifier
            ) { input, _, _ in
                defer { sem2.signal() }
                if !signaled {
                    url = try? self.duplicateToOurStorage(input)
                    signaled = true
                }
            }
            if sem2.wait(timeout: timeout) == .timedOut {
                return nil
            }
        }
        return url
    }
}

extension [NSItemProvider] {
    func interfaceConvert() -> [URL]? {
        // 数量上限防 DoS
        guard count <= 100 else {
            DispatchQueue.main.async {
                NSAlert.popError(NSError(domain: "NotchDrop", code: 5, userInfo: [NSLocalizedDescriptionKey: String(format: NSLocalizedString("Too many files (max %d)", comment: ""), 100)]))
            }
            return nil
        }
        let urls = compactMap { provider -> URL? in
            provider.convertToFilePathThatIsWhatWeThinkItWillWorkWithNotchDrop()
        }
        guard urls.count == count else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSAlert.popError(NSLocalizedString("One or more files failed to load", comment: ""))
            }
            return nil
        }
        return urls
    }
}
