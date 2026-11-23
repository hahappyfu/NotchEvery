//
//  CopyFeedback.swift
//  NotchEvery
//
//  复制反馈：写剪贴板并短暂标记哪一行已复制，延迟后清空。
//

import AppKit
import Combine
import Foundation

@MainActor
final class CopyFeedback: ObservableObject {
    @Published private(set) var copiedID: String?

    private let resetDelay: TimeInterval
    private let pasteboard: NSPasteboard
    private var resetTask: DispatchWorkItem?

    init(resetDelay: TimeInterval = 1.5, pasteboard: NSPasteboard = .general) {
        self.resetDelay = resetDelay
        self.pasteboard = pasteboard
    }

    func copy(_ text: String, id: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        copiedID = id

        resetTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            // 仅当没有更晚的复制接管时才清空，避免新反馈被旧延迟擦掉
            if self?.copiedID == id {
                self?.copiedID = nil
            }
        }
        resetTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + resetDelay, execute: task)
    }
}
