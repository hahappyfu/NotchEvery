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

    /// 智能精简模型名称为友好的徽标文本：
    /// Claude 系列压缩为「型号-代际」短名；其余模型（gemini/qwen/deepseek/glm…）原名已具
    /// 辨识度，保留原样仅剔除冗余尾部段，防止被折叠为单一名词。
    public static func friendlyModelName(_ full: String) -> String {
        guard !full.isEmpty else { return "" }
        let lower = full.lowercased()

        // Claude 系列：提取型号（sonnet/opus/haiku/fable）与代际
        let kinds = ["sonnet", "opus", "haiku", "fable"]
        if let kind = kinds.first(where: { lower.contains($0) }) {
            let parts = lower.components(separatedBy: "-")
            if let idx = parts.firstIndex(of: kind) {
                // 代际段：1~2 位纯数字，多段以 "." 连接（haiku-4-5 → 4.5）
                var digits = parts[(idx + 1)...].filter(isVersionPart)
                if digits.isEmpty {
                    // 旧式命名：代际在型号前（claude-3-5-sonnet-20241022）
                    digits = parts[..<idx].filter(isVersionPart)
                }
                return digits.isEmpty ? kind : "\(kind)-\(digits.joined(separator: "."))"
            }
            return full
        }

        // 3. OpenAI 与其他开源模型
        if lower.contains("gpt-4o") { return "GPT-4o" }
        if lower.contains("o1") { return "o1" }
        if lower.contains("o3") { return "o3" }
        if lower.contains("120b") { return "OSS 120B" }

        // 4. 其余模型：保留原名，仅剔除冗余尾部段
        return full.components(separatedBy: "-")
            .filter { $0.lowercased() != "tiered" }
            .joined(separator: "-")
    }

    /// 版本代际段：1~2 位纯数字或点分版本号（如 5、4-5、3.5），排除 20241022 这类日期段
    private static func isVersionPart(_ part: String) -> Bool {
        guard !part.isEmpty else { return false }
        let subparts = part.split(separator: ".")
        return !subparts.isEmpty && subparts.allSatisfy { sub in
            !sub.isEmpty && sub.count <= 2 && sub.allSatisfy(\.isNumber)
        }
    }

    /// 计算缓存命中比例（0.0 ~ 1.0）
    /// 口径说明：在 cc-switch 与现代 LLM API 中，input 为未命中缓存的增量输入 Tokens，cached 为读取缓存的 Tokens。
    /// 总 Prompt Tokens = input + cached。
    /// 缓存命中率 = cached / (input + cached)。
    public static func cacheRateFraction(cached: Int, input: Int) -> Double {
        guard cached > 0 else { return 0 }
        let totalInput = input + cached
        guard totalInput > 0 else { return 0 }
        return min(1.0, max(0.0, Double(cached) / Double(totalInput)))
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
