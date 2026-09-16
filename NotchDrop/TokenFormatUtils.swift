//
//  TokenFormatUtils.swift
//  NotchEvery
//
//  Token 与请求量格式化工具（纯函数）
//

import Foundation

public enum TokenFormatUtils {
    /// 格式化 Token 数量（紧凑人类可读单位）：>= 1B、>= 1M、>= 1k 或原始数值
    public static func formatTokens(_ count: Int) -> String {
        let v = Double(count)
        if count >= 1_000_000_000 {
            return String(format: "%.1fB Tokens", v / 1_000_000_000.0)
        }
        if count >= 1_000_000 {
            return String(format: "%.1fM Tokens", v / 1_000_000.0)
        }
        if count >= 1_000 {
            return String(format: "%.1fk Tokens", v / 1_000.0)
        }
        return "\(count) Tokens"
    }

    /// 格式化请求数/调用数：>= 1M、>= 1k 或原始数值
    public static func formatCount(_ count: Int) -> String {
        let v = Double(count)
        if count >= 1_000_000 {
            return String(format: "%.1fM", v / 1_000_000.0)
        }
        if count >= 1_000 {
            return String(format: "%.1fk", v / 1_000.0)
        }
        return "\(count)"
    }
}
