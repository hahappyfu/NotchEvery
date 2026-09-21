//
//  AppDelegate.swift
//  NotchDrop
//
//  Created by 秋星桥 on 2024/7/7.
//

import AppKit
import Cocoa
import LaunchAtLogin

class AppDelegate: NSObject, NSApplicationDelegate {
    var isFirstOpen = true
    var isLaunchedAtLogin = false
    var mainWindowController: NotchWindowController?

    func applicationDidFinishLaunching(_: Notification) {
        if NSClassFromString("XCTestCase") != nil || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(rebuildApplicationWindows),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        // PID 单例改为一次性校验 + didBecomeActive 校验（#9/#16 干掉 1s 轮询）
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(checkSingletonOnActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        NSApp.setActivationPolicy(.accessory)

        isLaunchedAtLogin = LaunchAtLogin.wasLaunchedAtLogin

        _ = EventMonitors.shared
        determineIfProcessIdentifierMatches()

        // 设计规范要求的「App 启动即异步巡检一次」：不能依赖用户是否打开过网关分区页面
        // （QoderStore.start() 只在 GatewayZoneView.onAppear 时才被调用）。claimAllOncePerDay()
        // 内部按账号当天去重 + in-flight 守卫，重复触发无副作用。
        Task.detached(priority: .background) {
            await QoderCampaignClaimer.shared.claimAllOncePerDay()
        }

        // 同上先例：全池额度也「App 启动即探测一次」，不依赖用户是否打开过网关分区（QoderStore.start()
        // 只在 GatewayZoneView.onAppear 才调用），否则冷启动首张卡一直显示 --。refreshPoolQuotas()
        // 是 nonisolated async、prober 自带 in-flight 守卫，与后续面板打开的轮询不会冲突。
        Task.detached(priority: .background) {
            await QoderStore.shared.refreshPoolQuotas()
        }

        rebuildApplicationWindows()
    }

    @objc func checkSingletonOnActive() {
        determineIfProcessIdentifierMatches()
        makeKeyAndVisibleIfNeeded()
    }

    func applicationWillTerminate(_: Notification) {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        try? FileManager.default.removeItem(at: pidFile)
    }

    func findScreenFitsOurNeeds() -> NSScreen? {
        if let screen = NSScreen.buildin, screen.notchSize != .zero { return screen }
        return .main
    }

    @objc func rebuildApplicationWindows() {
        defer { isFirstOpen = false }
        if let mainWindowController {
            mainWindowController.destroy()
        }
        mainWindowController = nil
        guard let mainScreen = findScreenFitsOurNeeds() else { return }
        mainWindowController = .init(screen: mainScreen)
        if isFirstOpen, !isLaunchedAtLogin {
            mainWindowController?.openAfterCreate = true
        }
    }

    func determineIfProcessIdentifierMatches() {
        if NSClassFromString("XCTestCase") != nil || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return
        }
        let pid = String(NSRunningApplication.current.processIdentifier)
        let content = (try? String(contentsOf: pidFile)) ?? ""
        guard pid.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            == content.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        else {
            NSApp.terminate(nil)
            return
        }
    }

    func makeKeyAndVisibleIfNeeded() {
        guard let controller = mainWindowController,
              let window = controller.window,
              let vm = controller.vm,
              vm.status == .opened
        else { return }
        window.makeKeyAndOrderFront(nil)
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        guard let controller = mainWindowController,
              let vm = controller.vm
        else { return true }
        vm.notchOpen(.click)
        return true
    }
}
