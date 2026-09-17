//
//  TokenFormatUtils.swift
//  NotchEvery
//
//  Token 与请求量格式化工具（纯函数）
//

import Foundation

public enum TokenFormatUtils {
    /// 格式化 Token 数量（超紧凑人类可读单位）：>= 1B、>= 1M、>= 1k 或原始数值（不带冗余单词，节省刘海宝贵宽度）
    public static func formatCompactTokens(_ count: Int) -> String {
        let v = Double(count)
        if count >= 1_000_000_000 {
            return String(format: "%.1fB", v / 1_000_000_000.0)
        }
        if count >= 1_000_000 {
            return String(format: "%.1fM", v / 1_000_000.0)
        }
        if count >= 1_000 {
            return String(format: "%.1fk", v / 1_000.0)
        }
        return "\(count)"
    }

    /// 兼容老接口（带 Tokens）
    public static func formatTokens(_ count: Int) -> String {
        return "\(formatCompactTokens(count)) Tokens"
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

    /// 智能精简模型名称为友好的短名徽标文本
    public static func friendlyModelName(_ full: String) -> String {
        let lower = full.lowercased()
        if lower.contains("flash-high") { return "Flash High" }
        if lower.contains("flash") { return "Flash" }
        if lower.contains("gemini") && lower.contains("pro") { return "Gemini Pro" }
        if lower.contains("sonnet") { return "Sonnet 3.5" }
        if lower.contains("opus") { return "Opus" }
        if lower.contains("haiku") { return "Haiku" }
        if lower.contains("gpt-4o") { return "GPT-4o" }
        if lower.contains("o1") { return "o1" }
        if lower.contains("o3") { return "o3" }
        return full
    }

    /// 计算缓存命中比例（0.0 ~ 1.0）
    public static func cacheRateFraction(cached: Int, input: Int) -> Double {
        guard input > 0, cached > 0 else { return 0 }
        return min(1.0, max(0.0, Double(cached) / Double(input)))
    }

    /// 缓存命中等级（用于驱动语义色彩）
    public enum CacheRateTier: Equatable {
        case high    // >= 60% 翠绿
        case medium  // 30% ~ 60% 青蓝
        case low     // > 0% 暖琥珀
        case none    // 0% 灰
    }

    /// 根据缓存命中比例返回对应等级
    public static func cacheRateTier(fraction: Double) -> CacheRateTier {
        if fraction >= 0.60 { return .high }
        if fraction >= 0.30 { return .medium }
        if fraction > 0 { return .low }
        return .none
    }
}
