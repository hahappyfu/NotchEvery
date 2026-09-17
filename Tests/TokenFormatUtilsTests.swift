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
        XCTAssertEqual(TokenFormatUtils.friendlyModelName("gemini-3.8-flash-high"), "Flash High")
        XCTAssertEqual(TokenFormatUtils.friendlyModelName("gemini-2.5-pro"), "Gemini Pro")
        XCTAssertEqual(TokenFormatUtils.friendlyModelName("claude-3-5-sonnet-20241022"), "Sonnet 3.5")
        XCTAssertEqual(TokenFormatUtils.friendlyModelName("gpt-4o-2024-08-06"), "GPT-4o")
        XCTAssertEqual(TokenFormatUtils.friendlyModelName("custom-model"), "custom-model")
    }

    func testCacheRateFractionAndTier() {
        let fraction = TokenFormatUtils.cacheRateFraction(cached: 81698, input: 170075)
        XCTAssertEqual(String(format: "%.2f", fraction), "0.48")
        XCTAssertEqual(TokenFormatUtils.cacheRateTier(fraction: 0.78), .high)
        XCTAssertEqual(TokenFormatUtils.cacheRateTier(fraction: 0.48), .medium)
        XCTAssertEqual(TokenFormatUtils.cacheRateTier(fraction: 0.20), .low)
        XCTAssertEqual(TokenFormatUtils.cacheRateTier(fraction: 0.0), .none)
    }
}
