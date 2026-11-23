import XCTest
@testable import NotchEvery

@MainActor
final class CopyFeedbackTests: XCTestCase {
    func testCopyWritesPasteboardAndSetsID() {
        let pasteboard = NSPasteboard.withUniqueName()
        let feedback = CopyFeedback(pasteboard: pasteboard)

        feedback.copy("hello-world", id: "row-1")

        XCTAssertEqual(feedback.copiedID, "row-1")
        XCTAssertEqual(pasteboard.string(forType: .string), "hello-world")
    }

    func testCopiedIDResetsAfterDelay() {
        let pasteboard = NSPasteboard.withUniqueName()
        let feedback = CopyFeedback(resetDelay: 0.02, pasteboard: pasteboard)
        feedback.copy("text", id: "row-2")
        XCTAssertEqual(feedback.copiedID, "row-2")

        let exp = expectation(description: "copiedID resets")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            XCTAssertNil(feedback.copiedID)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2)
    }
}
