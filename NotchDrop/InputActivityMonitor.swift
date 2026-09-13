// InputActivityMonitor.swift
// 输入活动监听：全局 HID 输入（键盘按键 / 鼠标按键 / 触控板点击）的时间戳，
// 供「输入活动保护」判断用户是否正在操作，从而暂缓自动锁定。
//
// 来源：由 FUnlock 的 AppDelegate.swift 抽取而来（工单 01，见 .scratch/funlock-merge/）。
// 原实现与 AppDelegate 同文件且被 FUn 以属性类型引用；为让 FUn 不依赖 AppKit 而独立成文件。
// 逻辑逐字未改，仅补 import（原文件靠 Cocoa/IOKit.hid/os.lock 的传递可见性）。

import Foundation
import IOKit.hid
import os.lock

class InputActivityMonitor {
    private var hidManager: IOHIDManager?
    private var _lastInputTime: Date = Date.distantPast
    private var lock = os_unfair_lock()
    var activityWindow: TimeInterval = 15

    var lastInputTime: Date {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return _lastInputTime
    }

    var isActive: Bool {
        Date().timeIntervalSince(lastInputTime) < activityWindow
    }

    func start() {
        hidManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(0))
        guard let hidManager = hidManager else { return }
        let keyboard: [String: Any] = [
            kIOHIDDeviceUsagePageKey: 0x01,
            kIOHIDDeviceUsageKey: 0x06
        ]
        let trackpad: [String: Any] = [
            kIOHIDDeviceUsagePageKey: 0x0D,
            kIOHIDDeviceUsageKey: 0x04
        ]
        IOHIDManagerSetDeviceMatchingMultiple(hidManager, [keyboard, trackpad] as CFArray)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(hidManager, inputCallback, ctx)
        IOHIDManagerScheduleWithRunLoop(hidManager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(hidManager, IOOptionBits(0))
    }

    func stop() {
        if let mgr = hidManager {
            IOHIDManagerClose(mgr, IOOptionBits(0))
            hidManager = nil
        }
    }

    fileprivate func didReceiveInput() {
        os_unfair_lock_lock(&lock)
        _lastInputTime = Date()
        os_unfair_lock_unlock(&lock)
    }
}

private func inputCallback(_ ctx: UnsafeMutableRawPointer?,
                            _ result: IOReturn,
                            _ sender: UnsafeMutableRawPointer?,
                            _ value: IOHIDValue) {
    guard let ctx = ctx else { return }
    let monitor = Unmanaged<InputActivityMonitor>.fromOpaque(ctx).takeUnretainedValue()

    // 通过 element 的 usage page / usage 收紧过滤：
    // 只有按下事件（value 从 0 变为非 0）才计为有效输入，忽略释放、移动、滚动、媒体键等。
    let element = IOHIDValueGetElement(value)
    let page = IOHIDElementGetUsagePage(element)
    let usage = IOHIDElementGetUsage(element)
    let intValue = IOHIDValueGetIntegerValue(value)
    guard intValue != 0 else { return } // 释放等 value==0 的事件忽略

    let isKeyPress = (page == 0x01 && usage == 0x06)   // 键盘按键
    let isMousePress = (page == 0x01 && usage == 0x02) // 鼠标按键
    let isTrackpadClick = (page == 0x0D && usage == 0x09) // 触控板点击按钮

    if isKeyPress || isMousePress || isTrackpadClick {
        monitor.didReceiveInput()
    }
}
