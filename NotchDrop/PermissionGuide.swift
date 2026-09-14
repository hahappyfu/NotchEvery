// PermissionGuide.swift
// NotchEvery
//
// 权限引导判定（工单 07）：纯逻辑，视图与单测共用。
// 守护依赖三项授权，缺任何一项都会静默失效——启动时检查，缺失即给出来源。
// 检查器可注入：单测用 stub，线上 AX/FDA 走系统 API，蓝牙走管理器现存状态。

import ApplicationServices
import Foundation

/// 三项授权（顺序即展示顺序）
enum PermissionKind: String, CaseIterable {
    case ax
    case bluetooth
    case fullDisk
}

/// 一项缺失：缺什么、为什么要、去哪儿开
struct PermissionIssue: Equatable {
    let kind: PermissionKind
    let title: String
    let reason: String
    let settingsURL: URL?
}

struct PermissionGuide {
    var isAXTrusted: () -> Bool = { AXIsProcessTrusted() }
    /// 无默认值是故意的：蓝牙状态只能来自 CBCentralManager 回调后的管理器状态，
    /// 默认值无论取哪边都会静默撒谎，编译器逼调用方显式接线。
    var isBluetoothAuthorized: () -> Bool
    var hasFullDiskAccess: () -> Bool = {
        FileManager.default.isReadableFile(atPath: "/Library/Application Support/com.apple.TCC/TCC.db")
    }

    /// 缺失项（按展示顺序）
    func missing() -> [PermissionKind] {
        var out: [PermissionKind] = []
        if !isAXTrusted() { out.append(.ax) }
        if !isBluetoothAuthorized() { out.append(.bluetooth) }
        if !hasFullDiskAccess() { out.append(.fullDisk) }
        return out
    }

    /// 缺失项 → 文案与跳转（经宿主 t() 走 NSLocalizedString 机制；无表项时回退原文，
    /// 与守护卡既有硬编码中文观感一致，后续补表即本地化）
    static func issue(for kind: PermissionKind) -> PermissionIssue {
        switch kind {
        case .ax:
            return PermissionIssue(
                kind: .ax,
                title: t("需要辅助功能权限"),
                reason: t("没有它，密码输不进登录框，靠近不会解锁"),
                settingsURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"))
        case .bluetooth:
            return PermissionIssue(
                kind: .bluetooth,
                title: t("需要蓝牙权限"),
                reason: t("没有它，搜不到你的设备"),
                settingsURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth"))
        case .fullDisk:
            return PermissionIssue(
                kind: .fullDisk,
                title: t("需要完全磁盘访问"),
                reason: t("没有它读不到蓝牙信息（系统返回 EPERM），会误以为设备不在身边"),
                settingsURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"))
        }
    }
}
