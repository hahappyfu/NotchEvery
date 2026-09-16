import XCTest
@testable import NotchEvery

final class TokenFormatUtilsTests: XCTestCase {

    // MARK: - formatTokens Tests

    func testFormatTokensBillions() {
        XCTAssertEqual(TokenFormatUtils.formatTokens(1_000_000_000), "1.0B Tokens")
        XCTAssertEqual(TokenFormatUtils.formatTokens(1_500_000_000), "1.5B Tokens")
        XCTAssertEqual(TokenFormatUtils.formatTokens(2_450_000_000), "2.5B Tokens")
    }

    func testFormatTokensMillions() {
        XCTAssertEqual(TokenFormatUtils.formatTokens(1_000_000), "1.0M Tokens")
        XCTAssertEqual(TokenFormatUtils.formatTokens(70_494_437), "70.5M Tokens")
        XCTAssertEqual(TokenFormatUtils.formatTokens(999_900_000), "999.9M Tokens")
    }

    func testFormatTokensThousands() {
        XCTAssertEqual(TokenFormatUtils.formatTokens(1_000), "1.0k Tokens")
        XCTAssertEqual(TokenFormatUtils.formatTokens(45_200), "45.2k Tokens")
        XCTAssertEqual(TokenFormatUtils.formatTokens(999_999), "1000.0k Tokens")
    }

    func testFormatTokensRawUnder1k() {
        XCTAssertEqual(TokenFormatUtils.formatTokens(999), "999 Tokens")
        XCTAssertEqual(TokenFormatUtils.formatTokens(128), "128 Tokens")
        XCTAssertEqual(TokenFormatUtils.formatTokens(1), "1 Tokens")
        XCTAssertEqual(TokenFormatUtils.formatTokens(0), "0 Tokens")
    }

    // MARK: - formatCount Tests

    func testFormatCountMillions() {
        XCTAssertEqual(TokenFormatUtils.formatCount(1_000_000), "1.0M")
        XCTAssertEqual(TokenFormatUtils.formatCount(2_400_000), "2.4M")
    }

    func testFormatCountThousands() {
        XCTAssertEqual(TokenFormatUtils.formatCount(1_000), "1.0k")
        XCTAssertEqual(TokenFormatUtils.formatCount(2_400), "2.4k")
        XCTAssertEqual(TokenFormatUtils.formatCount(45_200), "45.2k")
    }

    func testFormatCountRawUnder1k() {
        XCTAssertEqual(TokenFormatUtils.formatCount(999), "999")
        XCTAssertEqual(TokenFormatUtils.formatCount(128), "128")
        XCTAssertEqual(TokenFormatUtils.formatCount(1), "1")
        XCTAssertEqual(TokenFormatUtils.formatCount(0), "0")
    }
}
