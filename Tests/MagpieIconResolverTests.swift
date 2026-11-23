import XCTest
@testable import NotchEvery

final class MagpieIconResolverTests: XCTestCase {
    private var root: URL!
    private var cacheDirectory: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("MagpieIconTests-\(UUID().uuidString)")
        cacheDirectory = root.appendingPathComponent("cache")
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        root = nil
        cacheDirectory = nil
    }

    private func resolver(icons: [String: String] = [:]) -> MagpieIconResolver {
        MagpieIconResolver(
            paths: MagpiePaths(root: root),
            cacheDirectory: cacheDirectory,
            icons: icons
        )
    }

    // 1. 候选 URL 顺序：cache 先、config icons 后；非 file: 先查 iconsMap
    func testCandidateURLsOrder() {
        let resolver = resolver(icons: ["alias": "file:abc.svg", "remote": "https://example.com/x.png"])
        let expected = [
            cacheDirectory.appendingPathComponent("abc.svg.png"),
            root.appendingPathComponent("icons").appendingPathComponent("abc.svg")
        ]
        XCTAssertEqual(resolver.candidateURLs(for: "file:abc.svg"), expected)
        XCTAssertEqual(resolver.candidateURLs(for: "alias"), expected)
        XCTAssertTrue(resolver.candidateURLs(for: "remote").isEmpty)
        XCTAssertTrue(resolver.candidateURLs(for: "missing").isEmpty)
        XCTAssertTrue(resolver.candidateURLs(for: "file:").isEmpty)
        XCTAssertTrue(resolver.candidateURLs(for: nil).isEmpty)
        XCTAssertTrue(resolver.candidateURLs(for: "").isEmpty)
    }

    // 2. 兜底色相确定、首字母大写
    func testFallbackInitialAndDeterministicColor() {
        let resolver = resolver()
        let hue = resolver.fallbackHue(for: "codearts")
        XCTAssertEqual(hue, resolver.fallbackHue(for: "codearts"))
        XCTAssertTrue((0..<1).contains(hue))
        XCTAssertNotEqual(hue, resolver.fallbackHue(for: "sensenova"))
        XCTAssertEqual(resolver.initial(for: "codearts"), "C")
        XCTAssertEqual(resolver.initial(for: "Zeta"), "Z")
        XCTAssertEqual(resolver.initial(for: ""), "?")
    }
}
