import XCTest
@testable import NotchEvery

final class AppPathsTests: XCTestCase {
    func testDocumentsDirectoryPointsToUserHomeDotNotchEvery() {
        let expectedHome = FileManager.default.homeDirectoryForCurrentUser
        let expected = expectedHome.appendingPathComponent(".notchevery")
        XCTAssertEqual(AppPaths.documentsDirectory.path, expected.path)
    }

    func testConfigDirPointsToDocumentsDirectory() {
        let expected = AppPaths.documentsDirectory.appendingPathComponent("Config")
        XCTAssertEqual(AppPaths.configDir.path, expected.path)
    }

    func testPidFilePointsToDocumentsDirectory() {
        let expected = AppPaths.documentsDirectory.appendingPathComponent("ProcessIdentifier")
        XCTAssertEqual(AppPaths.pidFile.path, expected.path)
    }
}

