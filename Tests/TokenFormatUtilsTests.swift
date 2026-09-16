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
}
