import XCTest
@testable import NotchEvery

final class LoginItemTests: XCTestCase {
    func testIsEnabledDoesNotCrash() {
        // 只验证可安全读取：测试环境里注册状态不确定，值必须是 Bool 且不触崩
        let enabled: Bool = LoginItem.isEnabled
        XCTAssertTrue(enabled == true || enabled == false)
    }

    func testWasLaunchedAtLoginFalseInXCTest() {
        // XCTest 进程不是登录项启动：镜像 LaunchAtLogin-Modern 的 AppleEvent 判定应返回 false
        XCTAssertFalse(LoginItem.wasLaunchedAtLogin)
    }
}
