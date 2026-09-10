import XCTest
@testable import NotchEvery

// 首批单测（#31 最小集，需在 Xcode 中新建 Test Target 后启用）
final class TrayDropTests: XCTestCase {
    func testExpiredItemIsCleaned() {
        // DropItem(copiedDate: distantPast, keepInterval: 1s) shouldClean == true
        // TODO: 需 Test Target 后跑通
    }
    func testLoadPartialSuccessKeepsSucceeded() {
        // mock 2 URL 其中 1 个 copyItem 失败，succeeded.count == 1 且 items 保留成功项
    }
}
