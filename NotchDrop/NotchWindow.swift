//
//  NotchWindow.swift
//  NotchDrop
//
//  Created by 秋星桥 on 2024/7/7.
//

import Cocoa

class NotchWindow: NSWindow {
    /// 钉死的窗口内容尺寸：hosting 控制器会随 SwiftUI 理想尺寸隐式 resize（实测 200→280 且不回落），
    /// 窗口本体是贴顶 200pt 条，尺寸只允许控制器设置一次，其余调用一律改写
    var pinnedContentSize: NSSize?

    override func setContentSize(_ newSize: NSSize) {
        super.setContentSize(pinnedContentSize ?? newSize)
    }

    override init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask,
        backing: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: styleMask,
            backing: backing,
            defer: flag
        )

        isOpaque = false
        alphaValue = 1
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = NSColor.clear
        isMovable = false
        collectionBehavior = [
            .fullScreenAuxiliary,
            .stationary,
            .canJoinAllSpaces,
            .ignoresCycle,
        ]
        level = .statusBar + 8 // kills ibar lol
        hasShadow = false
    }

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }
}
