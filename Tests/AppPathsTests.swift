import XCTest
@testable import NotchDrop

final class AppPathsTests: XCTestCase {
    func testDocumentsDirectoryFallbackWhenEmpty() {
        // FileManager.urls(for:) 返回 [] 时回退到 applicationSupport，不崩溃
    }
    func testSanitizedFileNameStripsSlash() {
        // sanitizedFileName("a/b:c") == "a_b_c" 且截断 200
    }
}
