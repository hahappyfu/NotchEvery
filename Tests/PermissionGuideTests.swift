// PermissionGuideTests.swift（工单 07 新建）
// 引导判定纯逻辑测试：缺失组合、文案跳转映射；不碰系统 API（检查器全 stub）。

import XCTest
@testable import NotchEvery

final class PermissionGuideTests: XCTestCase {
    private func guide(ax: Bool = true, bluetooth: Bool = true, fullDisk: Bool = true) -> PermissionGuide {
        PermissionGuide(
            isAXTrusted: { ax },
            isBluetoothAuthorized: { bluetooth },
            hasFullDiskAccess: { fullDisk })
    }

    func testAllGrantedGivesNoMissing() {
        XCTAssertTrue(guide().missing().isEmpty)
    }

    /// 缺失按展示顺序返回（AX → 蓝牙 → 完全磁盘），与卡片渲染顺序一致
    func testMissingInDisplayOrder() {
        XCTAssertEqual(guide(ax: false, bluetooth: false, fullDisk: false).missing(),
                       [.ax, .bluetooth, .fullDisk])
        XCTAssertEqual(guide(fullDisk: false).missing(), [.fullDisk])
    }

    /// 每项都有标题、用途说明与跳转，且 FDA 解释点名真实症状
    func testEveryKindHasTitleReasonAndURL() {
        for kind in PermissionKind.allCases {
            let issue = PermissionGuide.issue(for: kind)
            XCTAssertFalse(issue.title.isEmpty, "\(kind) 缺标题")
            XCTAssertFalse(issue.reason.isEmpty, "\(kind) 缺用途说明")
            XCTAssertNotNil(issue.settingsURL, "\(kind) 缺跳转")
        }
        XCTAssertTrue(PermissionGuide.issue(for: .fullDisk).reason.contains("EPERM"),
                      "FDA 解释必须点名读不到蓝牙信息这一真实症状")
    }
}
