import XCTest
@testable import NotchEvery

/// 测量接缝（to-spec 已确认）：内容自然尺寸上报的合并语义。
/// 只测公开行为——多分支取最大、静默分支不污染，不碰 SwiftUI 布局内部。
final class ZoneSizeGuardTests: XCTestCase {
    func testDefaultIsZeroSize() {
        XCTAssertEqual(ZoneNaturalSizeKey.defaultValue, .zero)
    }

    func testReduceMergesMaxPerDimension() {
        var value = CGSize(width: 100, height: 50)
        ZoneNaturalSizeKey.reduce(value: &value) { CGSize(width: 80, height: 70) }
        XCTAssertEqual(value, CGSize(width: 100, height: 70))
    }

    func testSilentBranchReportsZero() {
        var value = CGSize(width: 200, height: 150)
        ZoneNaturalSizeKey.reduce(value: &value) { .zero }
        XCTAssertEqual(value, CGSize(width: 200, height: 150))
    }

    // 02 工单：钳制纯函数（屏高 900 → 高上限 360；最小 320×120；最大宽 640）
    func testClampKeepsNormalSize() {
        XCTAssertEqual(
            NotchViewModel.clampPanelSize(CGSize(width: 400, height: 200), maxHeight: 360),
            CGSize(width: 400, height: 200)
        )
    }

    func testClampFloorsToMinimum() {
        XCTAssertEqual(
            NotchViewModel.clampPanelSize(.zero, maxHeight: 360),
            CGSize(width: 320, height: 120)
        )
    }

    func testClampCapsWidth() {
        XCTAssertEqual(
            NotchViewModel.clampPanelSize(CGSize(width: 900, height: 200), maxHeight: 360),
            CGSize(width: 640, height: 200)
        )
    }

    func testClampCapsHeight() {
        XCTAssertEqual(
            NotchViewModel.clampPanelSize(CGSize(width: 400, height: 800), maxHeight: 360),
            CGSize(width: 400, height: 360)
        )
    }

    // 跟随关系：面板尺寸 = 钳制后整体测量值（含安全区+内容+dots）；未量到取最小保底
    func testZoneOpenedSizeFollowsClampedMeasurement() {
        let vm = NotchViewModel(events: MockEventMonitors())
        vm.measuredNaturalSize = CGSize(width: 400, height: 200)
        XCTAssertEqual(vm.zoneOpenedSize, CGSize(width: 400, height: 200))
        vm.measuredNaturalSize = CGSize(width: 900, height: 800)
        XCTAssertEqual(vm.zoneOpenedSize, CGSize(width: 640, height: 360))
    }

    func testZoneOpenedSizeFloorWhenUnmeasured() {
        let vm = NotchViewModel(events: MockEventMonitors())
        XCTAssertEqual(vm.zoneOpenedSize, CGSize(width: 320, height: 120))
    }
}
