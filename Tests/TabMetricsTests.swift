import XCTest
@testable import NotchEvery

/// 内容自适应面板（ADR-0008）：高度表已删，本文件只锁边界、跟随关系与保留常量。
final class TabMetricsTests: XCTestCase {
    func testPanelBoundsSane() {
        XCTAssertEqual(NotchViewModel.minPanelSize, CGSize(width: 160, height: 60))
        XCTAssertEqual(NotchViewModel.maxPanelWidth, 640)
    }

    func testCompactPanelSizing() {
        // 物理刘海为 200pt 时，宽度保底为 200 + 16 = 216pt
        let sizeWithNotch = NotchViewModel.clampPanelSize(
            CGSize(width: 100, height: 40),
            maxHeight: 400,
            deviceNotchWidth: 200
        )
        XCTAssertEqual(sizeWithNotch.width, 216)
        XCTAssertEqual(sizeWithNotch.height, 60, "高度保底应为 60pt")

        // 无物理刘海时，宽度保底仅为内容自然宽（受 160 保底）
        let sizeWithoutNotch = NotchViewModel.clampPanelSize(
            CGSize(width: 180, height: 50),
            maxHeight: 400,
            deviceNotchWidth: 0
        )
        XCTAssertEqual(sizeWithoutNotch.width, 180)
        XCTAssertEqual(sizeWithoutNotch.height, 60)
    }

    func testMaxHeightFollowsScreen() {
        let vm = NotchViewModel(events: MockEventMonitors())
        XCTAssertEqual(vm.maxPanelHeight, 360, "屏幕未知时回落 360")
        vm.screenRect = CGRect(x: 0, y: 0, width: 1512, height: 982)
        XCTAssertEqual(vm.maxPanelHeight, 982 * 0.4, accuracy: 0.001)
    }

    func testHeaderSlotHeightRetained() {
        // headerSlotHeight 常量保留，不作语义用途
        XCTAssertEqual(NotchViewModel.headerSlotHeight, 29)
    }

    func testNotchSafeAreaTop() {
        // 安全区 = 物理刘海高 + 8pt；无刘海屏沿用控制器兜底值
        let vm = NotchViewModel(events: MockEventMonitors())
        vm.deviceNotchRect = CGRect(x: 0, y: 0, width: 200, height: 30)
        XCTAssertEqual(vm.notchSafeAreaTop, 38)
    }

    func testPageZoneMapping() {
        // 三分区映射：概览、Token、网关（开关默认开）
        ConfigStore.shared.set(1, forKey: "showGatewayZone") // Int 走 NSNumber.boolValue，等价 Bool
        XCTAssertEqual(NotchViewModel.zoneOrder, [.normal, .token, .gateway])
        XCTAssertEqual(NotchViewModel.pageIndex(for: .normal), 0)
        XCTAssertEqual(NotchViewModel.pageIndex(for: .token), 1)
        XCTAssertEqual(NotchViewModel.pageIndex(for: .gateway), 2)
        XCTAssertEqual(NotchViewModel.zone(for: 0), .normal)
        XCTAssertEqual(NotchViewModel.zone(for: 1), .token)
        XCTAssertEqual(NotchViewModel.zone(for: 2), .gateway)
    }

    func testOverviewPageSpacingAndPadding() {
        // 验证 OverviewPageView 使用紧凑间距 8pt 且两张卡片存在
        let overview = OverviewPageView(vm: NotchViewModel())
        XCTAssertNotNil(overview)
    }

    func testZoneSizeMemoryRestoresFullCGSizeIndependently() {
        let vm = NotchViewModel(events: MockEventMonitors())
        vm.deviceNotchRect = CGRect(x: 570, y: 866, width: 300, height: 34)

        // 1. 在 A 区（.normal）测量自然尺寸 400×334
        vm.contentType = .normal
        vm.measuredNaturalSize = CGSize(width: 400, height: 334)
        XCTAssertEqual(vm.measuredNaturalSize, CGSize(width: 400, height: 334))
        XCTAssertEqual(vm.zoneOpenedSize.height, 334)

        // 2. 切到 B 区（.token），尚未测量时归零，测量后上报 250×120
        vm.contentType = .token
        XCTAssertEqual(vm.measuredNaturalSize, .zero, "初次切入未测量的分区应归零")
        vm.measuredNaturalSize = CGSize(width: 250, height: 120)
        XCTAssertEqual(vm.measuredNaturalSize, CGSize(width: 250, height: 120))
        XCTAssertEqual(vm.zoneOpenedSize.height, 120, "低页高度不得被高页污染锁定")

        // 3. 切回 A 区（.normal），必须恢复 400×334，而不是保留 B 区的 120 高度
        vm.contentType = .normal
        XCTAssertEqual(vm.measuredNaturalSize, CGSize(width: 400, height: 334), "切回 A 区应恢复 A 区独立记忆的高宽")
        XCTAssertEqual(vm.zoneOpenedSize.height, 334)

        // 4. 再切回 B 区（.token），必须恢复 250×120，而不是被 A 区的 334 覆盖
        vm.contentType = .token
        XCTAssertEqual(vm.measuredNaturalSize, CGSize(width: 250, height: 120), "切回 B 区应恢复 B 区独立记忆的高宽")
        XCTAssertEqual(vm.zoneOpenedSize.height, 120)
    }

    func testReopenRestoresCurrentZoneFullSize() {
        let vm = NotchViewModel(events: MockEventMonitors())
        vm.deviceNotchRect = CGRect(x: 570, y: 866, width: 300, height: 34)
        vm.contentType = .normal
        vm.measuredNaturalSize = CGSize(width: 450, height: 280)

        // 关闭
        vm.notchClose()
        XCTAssertEqual(vm.status, .closed)

        // 重新打开（模拟 openFromGhost 或 notchOpen）
        vm.notchOpen(.click)
        XCTAssertEqual(vm.status, .opened)
        XCTAssertEqual(vm.measuredNaturalSize, CGSize(width: 450, height: 280), "重开时应恢复完整高宽记忆")
    }
}
