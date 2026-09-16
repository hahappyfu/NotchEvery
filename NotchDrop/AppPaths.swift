//
//  AppPaths.swift
//  NotchDrop
//
//  全局路径统一入口（#26 拆分顶层副作用）。
//

import Foundation

enum AppPaths {
    static var documentsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".notchevery")
    }

    static var temporaryDirectory: URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "NotchEvery")
    }

    static var pidFile: URL {
        documentsDirectory.appendingPathComponent("ProcessIdentifier")
    }

    static var configDir: URL {
        documentsDirectory.appendingPathComponent("Config")
    }

    static var configFile: URL {
        documentsDirectory.appendingPathComponent("config.json")
    }
}

// ——— 兼容层：main.swift 顶层 let 保留为 AppPaths 的别名，供未迁移引用 ———
let documentsDirectory: URL = AppPaths.documentsDirectory
let temporaryDirectory: URL = AppPaths.temporaryDirectory
let pidFile: URL = AppPaths.pidFile

