//
//  MagpiePaths.swift
//  NotchEvery
//
//  Magpie 配置目录白名单路径入口（只读，永不触碰密钥文件）。
//

import Foundation

struct MagpiePaths: Equatable {
    let root: URL

    static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/magpie")
    }

    init(root: URL = MagpiePaths.defaultRoot) {
        self.root = root
    }

    var usageFile: URL { root.appendingPathComponent("usage.jsonl") }
    func routingFile(day: String) -> URL { root.appendingPathComponent("routing").appendingPathComponent("\(day).jsonl") }
    func maskingFile(day: String) -> URL { root.appendingPathComponent("masking").appendingPathComponent("\(day).jsonl") }
    var quotasFile: URL { root.appendingPathComponent("quotas.json") }
    var limitNoticesFile: URL { root.appendingPathComponent("limit-notices.json") }
    var pluginCheckinFile: URL { root.appendingPathComponent("plugin-checkin.json") }
    var providersFile: URL { root.appendingPathComponent("providers.json") }
    var pluginProvidersFile: URL { root.appendingPathComponent("plugin-providers.json") }
    var pluginIconsFile: URL { root.appendingPathComponent("plugin-icons.json") }
    var gatewayFile: URL { root.appendingPathComponent("gateway.json") }
    var quotaHistoryFile: URL { root.appendingPathComponent("quota-history.json") }

    /// 本地日期字符串（routing/masking 的按天文件名）。
    static func dayString(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
