//
//  TokenFormatUtilsTests.swift
//  NotchEvery
//

import XCTest
@testable import NotchEvery

final class TokenFormatUtilsTests: XCTestCase {
    func testFormatCompactTokens() {
        XCTAssertEqual(TokenFormatUtils.formatCompactTokens(0), "0")
        XCTAssertEqual(TokenFormatUtils.formatCompactTokens(999), "999")
        XCTAssertEqual(TokenFormatUtils.formatCompactTokens(1_200), "1.2k")
        XCTAssertEqual(TokenFormatUtils.formatCompactTokens(70_494_437), "70.5M")
        XCTAssertEqual(TokenFormatUtils.formatCompactTokens(125_200_000), "125.2M")
        XCTAssertEqual(TokenFormatUtils.formatCompactTokens(1_000_000_000), "1.0B")
    }

    func testFormatTokensWithSuffix() {
        XCTAssertEqual(TokenFormatUtils.formatTokens(70_494_437), "70.5M Tokens")
    }

    func testFormatCompactCount() {
        XCTAssertEqual(TokenFormatUtils.formatCount(0), "0")
        XCTAssertEqual(TokenFormatUtils.formatCount(89), "89")
        XCTAssertEqual(TokenFormatUtils.formatCount(2_412), "2.4k")
        XCTAssertEqual(TokenFormatUtils.formatCount(1_500_000), "1.5M")
    }

    func testFriendlyModelName() {
        XCTAssertEqual(TokenFormatUtils.friendlyModelName(""), "")
        XCTAssertEqual(TokenFormatUtils.friendlyModelName("gemini-3.8-flash"), "gemini-3.8-flash")
        XCTAssertEqual(TokenFormatUtils.friendlyModelName("gemini-3.8-flash-high"), "gemini-3.8-flash-high")
        XCTAssertEqual(TokenFormatUtils.friendlyModelName("gemini-2.5-pro"), "gemini-2.5-pro")
        XCTAssertEqual(TokenFormatUtils.friendlyModelName("claude-3-5-sonnet-20241022"), "sonnet-3.5")
        XCTAssertEqual(TokenFormatUtils.friendlyModelName("claude-3.5-sonnet"), "sonnet-3.5")
        XCTAssertEqual(TokenFormatUtils.friendlyModelName("claude-sonnet-5"), "sonnet-5")
        XCTAssertEqual(TokenFormatUtils.friendlyModelName("gpt-4o-2024-08-06"), "GPT-4o")
        XCTAssertEqual(TokenFormatUtils.friendlyModelName("custom-model"), "custom-model")
    }

    /// 多供应商模型名：保留辨识度，防止被折叠为单一名词
    func testFriendlyModelNameMultiVendors() {
        XCTAssertEqual(TokenFormatUtils.friendlyModelName("gemini-3.7-flash-tiered"), "gemini-3.7-flash")
        XCTAssertEqual(TokenFormatUtils.friendlyModelName("Qwen3.8-Flash"), "Qwen3.8-Flash")
        XCTAssertEqual(TokenFormatUtils.friendlyModelName("DeepSeek-V4-Pro"), "DeepSeek-V4-Pro")
        XCTAssertEqual(TokenFormatUtils.friendlyModelName("deepseek-v3"), "deepseek-v3")
        XCTAssertEqual(TokenFormatUtils.friendlyModelName("glm-5.3-flash"), "glm-5.3-flash")
        XCTAssertEqual(TokenFormatUtils.friendlyModelName("claude-opus-5"), "opus-5")
        XCTAssertEqual(TokenFormatUtils.friendlyModelName("claude-fable-5"), "fable-5")
        XCTAssertEqual(TokenFormatUtils.friendlyModelName("claude-haiku-4-5"), "haiku-4.5")
    }

    func testCacheRateFractionAndTier() {
        // cc-switch 口径：input 为增量未缓存输入，cached 为缓存读取输入，总输入 = input + cached
        // 典型命中场景：cached (3000) > input (1000)，总输入 4000，命中率 75%（旧实现会直接截断为 100%）
        let fractionHigh = TokenFormatUtils.cacheRateFraction(cached: 3000, input: 1000)
        XCTAssertEqual(String(format: "%.2f", fractionHigh), "0.75")

        // 真实日志样例：cached (93108) 与 input (6065)，命中率 93.9%
        let fractionReal = TokenFormatUtils.cacheRateFraction(cached: 93108, input: 6065)
        XCTAssertEqual(String(format: "%.3f", fractionReal), "0.939")

        // 低命中率场景：cached (192) 与 input (1532)，总输入 1724，命中率 11.1%
        let fractionLow = TokenFormatUtils.cacheRateFraction(cached: 192, input: 1532)
        XCTAssertEqual(String(format: "%.3f", fractionLow), "0.111")

        // 无缓存场景
        XCTAssertEqual(TokenFormatUtils.cacheRateFraction(cached: 0, input: 1000), 0.0)
        // 边界保护
        XCTAssertEqual(TokenFormatUtils.cacheRateFraction(cached: 0, input: 0), 0.0)
        XCTAssertEqual(TokenFormatUtils.cacheRateFraction(cached: -1, input: 1000), 0.0)

        // 缓存等级判断
        XCTAssertEqual(TokenFormatUtils.cacheRateTier(fraction: 0.78), .high)
        XCTAssertEqual(TokenFormatUtils.cacheRateTier(fraction: 0.48), .medium)
        XCTAssertEqual(TokenFormatUtils.cacheRateTier(fraction: 0.20), .low)
        XCTAssertEqual(TokenFormatUtils.cacheRateTier(fraction: 0.0), .none)
    }
}
