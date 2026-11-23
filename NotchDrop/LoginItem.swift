//
//  LoginItem.swift
//  NotchEvery
//
//  开机自启（SMAppService 原生实现，替代 LaunchAtLogin-Modern）。
//

import AppKit
import ServiceManagement
import os.log

enum LoginItem {
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "NotchEvery", category: "LoginItem")

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status == .enabled {
                    try? SMAppService.mainApp.unregister()
                }
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            log.error("设置开机自启失败: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// 是否由登录项启动（镜像 LaunchAtLogin-Modern 的 AppleEvent 判定；
    /// 只应在 applicationDidFinishLaunching 期间读取）。
    static var wasLaunchedAtLogin: Bool {
        let event = NSAppleEventManager.shared().currentAppleEvent
        return event?.eventID == kAEOpenApplication
            && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }
}
