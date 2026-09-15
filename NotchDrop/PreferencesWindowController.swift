//
//  PreferencesWindowController.swift
//  NotchEvery
//
//  独立偏好设置窗口单例控制器。
//

import AppKit
import SwiftUI

final class PreferencesWindowController: NSWindowController {
    static let shared = PreferencesWindowController()

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 460),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "NotchEvery 偏好设置"
        window.minSize = NSSize(width: 650, height: 440)
        window.center()
        window.setFrameAutosaveName("NotchEveryPreferencesWindow")
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: PreferencesWindow())
        self.init(window: window)
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        if window?.isMiniaturized == true {
            window?.deminiaturize(nil)
        }
        window?.makeKeyAndOrderFront(nil)
    }
}
