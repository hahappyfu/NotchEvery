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

    /// 智能精简模型名称为友好的短名徽标文本（保留版本号与关键档位）
    public static func friendlyModelName(_ full: String) -> String {
        let lower = full.lowercased()

        // 1. Gemini 系列：精确识别版本（3.8 / 3.7 / 2.5 / 3 等）+ 变体
        if lower.contains("gemini") {
            var version = ""
            let parts = lower.components(separatedBy: "-")
            for part in parts {
                if Double(part) != nil || (part.allSatisfy { $0.isNumber || $0 == "." } && !part.isEmpty && part.contains { $0.isNumber }) {
                    version = part
                    break
                }
            }

            var kind = ""
            if lower.contains("flash") {
                if lower.contains("high") { kind = "Flash High" }
                else if lower.contains("low") { kind = "Flash Low" }
                else if lower.contains("lite") { kind = "Flash Lite" }
                else if lower.contains("medium") { kind = "Flash Med" }
                else if lower.contains("tiered") { kind = "Flash Tier" }
                else { kind = "Flash" }
            } else if lower.contains("pro") {
                if lower.contains("high") { kind = "Pro High" }
                else if lower.contains("low") { kind = "Pro Low" }
                else { kind = "Pro" }
            }

            if !version.isEmpty && !kind.isEmpty {
                return "\(version) \(kind)"
            } else if !kind.isEmpty {
                return kind
            } else if !version.isEmpty {
                return "Gemini \(version)"
            }
            return "Gemini"
        }

        // 2. Claude 系列：提取代际与型号
        if lower.contains("sonnet") {
            if lower.contains("3-5") || lower.contains("3.5") { return "Sonnet 3.5" }
            if lower.contains("3-7") || lower.contains("3.7") { return "Sonnet 3.7" }
            if lower.contains("4-6") || lower.contains("4.6") { return "Sonnet 4.6" }
            if lower.contains("5") { return "Sonnet 5" }
            return "Sonnet"
        }
        if lower.contains("opus") {
            if lower.contains("4-6") || lower.contains("4.6") { return "Opus 4.6" }
            if lower.contains("5") { return "Opus 5" }
            return "Opus"
        }
        if lower.contains("haiku") {
            if lower.contains("4-5") || lower.contains("4.5") { return "Haiku 4.5" }
            if lower.contains("4") { return "Haiku 4" }
            if lower.contains("3-5") || lower.contains("3.5") { return "Haiku 3.5" }
            return "Haiku"
        }

        // 3. OpenAI 与其他开源模型
        if lower.contains("gpt-4o") { return "GPT-4o" }
        if lower.contains("o1") { return "o1" }
        if lower.contains("o3") { return "o3" }
        if lower.contains("120b") { return "OSS 120B" }
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
