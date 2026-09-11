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

    // 02 工单 + 2026-09-11 设计修订：宽 = 钳制(内容自然宽, 最小 320, 长宽比保底宽)，上限 640；
    // 高 = min(max(自然高, 120), maxHeight)。natural 为含外壳留白的盒子（内容最小宽 + 2×32）。
    func testClampKeepsContentWidth() {
        XCTAssertEqual(
            NotchViewModel.clampPanelSize(CGSize(width: 400, height: 200), maxHeight: 360),
            CGSize(width: 400, height: 200) // 保底宽 286 < 内容 400，内容顶住
        )
    }

    func testClampAppliesAspectFloorWhenContentNarrow() {
        XCTAssertEqual(
            NotchViewModel.clampPanelSize(CGSize(width: 400, height: 320), maxHeight: 400),
            CGSize(width: 496, height: 320) // 320×1.75−64 = 496 > 内容 400
        )
    }

    func testClampFloorsToMinimum() {
        XCTAssertEqual(
            NotchViewModel.clampPanelSize(.zero, maxHeight: 360),
            CGSize(width: 320, height: 120)
        )
    }

    func testClampCapsWidthAndHeight() {
        XCTAssertEqual(
            NotchViewModel.clampPanelSize(CGSize(width: 900, height: 800), maxHeight: 360),
            CGSize(width: 640, height: 360) // 宽封顶 640、高封顶 360
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

    // H1（2026-09-11 时序实锤）：点击打开首帧宽度曾被清零，测量晚 ~10ms 才到，
    // 岛体跳两跳而内容走自己的曲线 = 撕裂。重开应从本区上次宽度起跳。
    func testReopenSeedsLastZoneWidthInsteadOfZero() {
        let vm = NotchViewModel(events: MockEventMonitors())
        vm.notchOpen(.click)
        vm.measuredNaturalSize = CGSize(width: 500, height: 200)
        vm.notchClose()
        vm.notchOpen(.click)
        XCTAssertEqual(vm.measuredNaturalSize.width, 500)
    }

    // 切页同理：回旧区应恢复该区自己的宽度（各区独立记忆），而不是归零重涨。
    func testSwitchZoneRestoresThatZonesWidth() {
        let vm = NotchViewModel(events: MockEventMonitors())
        vm.notchOpen(.click)
        vm.measuredNaturalSize = CGSize(width: 500, height: 200)
        vm.jumpToZone(.token)
        vm.measuredNaturalSize = CGSize(width: 420, height: 200)
        vm.jumpToZone(.normal)
        XCTAssertEqual(vm.measuredNaturalSize.width, 500)
    }
}
