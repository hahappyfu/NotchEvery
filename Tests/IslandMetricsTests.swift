import XCTest
@testable import NotchEvery

/// 模型列宽自适应：纯函数外部行为（钳制边界与单调性），不测具体像素值。
final class IslandMetricsTests: XCTestCase {
    func testEmptyModelsReturnsMin() {
        XCTAssertEqual(IslandMetrics.modelColumnWidth(for: []), IslandMetrics.modelColumnMin)
    }

    func testShortModelsClampToMin() {
        XCTAssertEqual(
            IslandMetrics.modelColumnWidth(for: ["gpt", "kimi", "qwen-plus"]),
            IslandMetrics.modelColumnMin
        )
    }

    func testVeryLongModelClampsToMax() {
        let long = String(repeating: "very-long-model-name-", count: 5)
        XCTAssertEqual(IslandMetrics.modelColumnWidth(for: [long]), IslandMetrics.modelColumnMax)
    }

    func testWidthMonotonicWithLongerNames() {
        let short = IslandMetrics.modelColumnWidth(for: ["gpt-5"])
        let mid = IslandMetrics.modelColumnWidth(for: ["deepseek-v4-flash-0731"])
        let long = IslandMetrics.modelColumnWidth(for: ["deepseek-ai/deepseek-v4-flash-0731"])
        XCTAssertLessThanOrEqual(short, mid)
        XCTAssertLessThanOrEqual(mid, long)
    }

    func testLongestModelDrivesWidth() {
        let mixed = IslandMetrics.modelColumnWidth(for: ["gpt-5", "qwen-plus-2025-07-14"])
        let onlyLong = IslandMetrics.modelColumnWidth(for: ["qwen-plus-2025-07-14"])
        XCTAssertEqual(mixed, onlyLong)
    }

    func testAlwaysWithinBounds() {
        for sample in [["a"], ["deepseek-v4-flash-vision-exp"], [String(repeating: "x", count: 60)]] {
            let w = IslandMetrics.modelColumnWidth(for: sample)
            XCTAssertGreaterThanOrEqual(w, IslandMetrics.modelColumnMin)
            XCTAssertLessThanOrEqual(w, IslandMetrics.modelColumnMax)
        }
    }

    func testShapeMetricsIdentityAtPrototypeScale() {
        let proto = CGSize(width: 285, height: 46)
        XCTAssertEqual(IslandMetrics.filletRadius(for: proto), 15)
        XCTAssertEqual(IslandMetrics.peekSize(for: proto), CGSize(width: 380, height: 82))
        XCTAssertEqual(IslandMetrics.peekBottomRadius(for: proto), 20)
        XCTAssertEqual(IslandMetrics.openBottomRadius, 26)
        XCTAssertEqual(IslandMetrics.openFilletRadius, 14)
    }

    func testShapeMetricsScaleWithRealNotch() {
        let real = CGSize(width: 179, height: 32)
        XCTAssertEqual(IslandMetrics.filletRadius(for: real), 9)
        XCTAssertEqual(IslandMetrics.peekSize(for: real), CGSize(width: 239, height: 57))
        XCTAssertEqual(IslandMetrics.peekBottomRadius(for: real), 13)
    }

    func testHoverActiveRectClosedMatchesDeviceNotchWithInset() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let notch = CGRect(x: (1440 - 285) / 2, y: 900 - 46, width: 285, height: 46)
        let geo = NotchGeometry(deviceNotchRect: notch, screenRect: screen, zoneOpenedSize: CGSize(width: 400, height: 300), inset: -4)

        let rect = geo.hoverActiveRect(status: .closed, hoverGhosting: false)
        XCTAssertEqual(rect, notch.insetBy(dx: -4, dy: -4))

        // 物理挖槽正中心应命中
        XCTAssertTrue(rect.contains(CGPoint(x: notch.midX, y: notch.midY)))
        // 挖槽下方（进入 peekHint 区域，例如 y = 900 - 65）在关闭态未进虚影时不命中
        XCTAssertFalse(rect.contains(CGPoint(x: notch.midX, y: 900 - 65)))
    }

    func testHoverActiveRectGhostExpandsToPeekSize() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let notch = CGRect(x: (1440 - 285) / 2, y: 900 - 46, width: 285, height: 46)
        let geo = NotchGeometry(deviceNotchRect: notch, screenRect: screen, zoneOpenedSize: CGSize(width: 400, height: 300), inset: -4)

        let ghostRect = geo.hoverActiveRect(status: .closed, hoverGhosting: true)
        XCTAssertEqual(ghostRect.width, 380)
        XCTAssertEqual(ghostRect.height, 82)
        XCTAssertEqual(ghostRect.maxY, 900)
        XCTAssertEqual(ghostRect.minY, 900 - 82)

        // 挖槽正中心命中
        XCTAssertTrue(ghostRect.contains(CGPoint(x: notch.midX, y: notch.midY)))
        // 挖槽下方 peekHint 文案区（y = 900 - 65）在虚影态必须命中，防止触发延时收起
        XCTAssertTrue(ghostRect.contains(CGPoint(x: notch.midX, y: 900 - 65)))
        // 左右边缘外扩区（例如距离中线 160pt）必须命中（原 285 挖槽半宽 142.5，peek 380 半宽 190）
        XCTAssertTrue(ghostRect.contains(CGPoint(x: notch.midX + 160, y: 900 - 30)))
        // 虚影岛体完全外部不应命中
        XCTAssertFalse(ghostRect.contains(CGPoint(x: notch.midX, y: 900 - 95)))
    }

    func testHoverActiveRectOpenedMatchesNotchOpenedRect() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let notch = CGRect(x: (1440 - 285) / 2, y: 900 - 46, width: 285, height: 46)
        let openedSize = CGSize(width: 500, height: 350)
        let geo = NotchGeometry(deviceNotchRect: notch, screenRect: screen, zoneOpenedSize: openedSize, inset: -4)

        let openedRect = geo.hoverActiveRect(status: .opened, hoverGhosting: false)
        XCTAssertEqual(openedRect, geo.notchOpenedRect)
        XCTAssertEqual(openedRect.width, 500)
        XCTAssertEqual(openedRect.height, 350)
        XCTAssertTrue(openedRect.contains(CGPoint(x: notch.midX, y: 900 - 200)))
    }

    // MARK: - D3 测试补齐：零宽刘海与 Ghost 收起状态机

    func testZeroWidthNotchGeometryNoNegativeWidthOrOutOfBounds() {
        let screens: [CGRect] = [
            CGRect(x: 0, y: 0, width: 2560, height: 1440),        // 2.5K
            CGRect(x: 0, y: 0, width: 3840, height: 2160),        // 4K
            CGRect(x: 0, y: 0, width: 5120, height: 2880),        // 5K
            CGRect(x: -1920, y: 0, width: 1920, height: 1080),     // 副屏负原点
            CGRect(x: 0, y: -1080, width: 1920, height: 1080),     // 垂直副屏
            CGRect(x: 0, y: 0, width: 800, height: 600),          // 紧凑屏幕
        ]

        let naturalSizes: [CGSize] = [
            .zero,
            CGSize(width: 50, height: 20),
            CGSize(width: 300, height: 200),
            CGSize(width: 1200, height: 900),
        ]

        for screen in screens {
            let zeroNotch = CGRect(x: screen.midX, y: screen.maxY, width: 0, height: 0)

            for natural in naturalSizes {
                let clamped = NotchViewModel.clampPanelSize(
                    natural,
                    maxHeight: screen.height * 0.4,
                    deviceNotchWidth: 0
                )

                // 宽度保底 >= 160，上限 <= 640
                XCTAssertGreaterThanOrEqual(clamped.width, IslandMetrics.minExternalPanelWidth)
                XCTAssertLessThanOrEqual(clamped.width, NotchViewModel.maxPanelWidth)

                // 高度保底 >= 60，上限 <= screenHeight * 0.4
                XCTAssertGreaterThanOrEqual(clamped.height, IslandMetrics.minPanelHeight)

                let geo = NotchGeometry(
                    deviceNotchRect: zeroNotch,
                    screenRect: screen,
                    zoneOpenedSize: clamped,
                    inset: -4
                )

                let openedRect = geo.notchOpenedRect
                // 无负宽、无负高
                XCTAssertGreaterThan(openedRect.width, 0)
                XCTAssertGreaterThan(openedRect.height, 0)

                // 水平居中且严格落在 screenRect 水平跨度内（屏幕宽于面板时）
                if screen.width >= clamped.width {
                    XCTAssertGreaterThanOrEqual(openedRect.minX, screen.minX)
                    XCTAssertLessThanOrEqual(openedRect.maxX, screen.maxX)
                }

                // 顶边紧贴屏幕顶
                XCTAssertEqual(openedRect.maxY, screen.maxY, accuracy: 0.001)
                XCTAssertEqual(openedRect.minY, screen.maxY - clamped.height, accuracy: 0.001)
            }
        }
    }

    func testGhostStateMachineReopenCancelsOldGenerationClose() {
        let mocks = MockEventMonitors()
        let vm = NotchViewModel(events: mocks)
        vm.screenRect = CGRect(x: 0, y: 0, width: 1440, height: 900)
        vm.deviceNotchRect = CGRect(x: (1440 - 285) / 2, y: 900 - 46, width: 285, height: 46)

        // 1. 悬停触发虚影态
        vm.notchOpen(.hover)
        XCTAssertTrue(vm.hoverGhosting)
        XCTAssertEqual(vm.status, .closed)
        XCTAssertEqual(vm.openReason, .hover)

        // 2. 从虚影态点开展开
        vm.openFromGhost()
        XCTAssertFalse(vm.hoverGhosting)
        XCTAssertEqual(vm.status, .opened)

        // 3. 移开触发两段收起：进入 ghostFading
        vm.closeToGhost()
        XCTAssertEqual(vm.status, .closed)
        XCTAssertTrue(vm.ghostFading)

        // 4. 在 280ms 延时收起尚未到达时，用户迅速再次重新点开
        vm.openFromGhost()
        XCTAssertEqual(vm.status, .opened)
        XCTAssertFalse(vm.ghostFading)

        // 5. 等待 350ms（超过旧代际的 280ms 延时清理死线），断言旧代际延迟闭环未把新会话强关
        let exp = expectation(description: "Wait for old generation async cleanup deadline")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)

        // 验证：新打开的展开态依然稳固保持，旧代际没有覆盖清除
        XCTAssertEqual(vm.status, .opened)
        XCTAssertFalse(vm.hoverGhosting)
        XCTAssertFalse(vm.ghostFading)
    }

    func testScheduleHoverCloseCancelsOnReopen() {
        let mocks = MockEventMonitors()
        let vm = NotchViewModel(events: mocks)
        vm.screenRect = CGRect(x: 0, y: 0, width: 1440, height: 900)
        vm.deviceNotchRect = CGRect(x: (1440 - 285) / 2, y: 900 - 46, width: 285, height: 46)

        vm.notchOpen(.hover)
        XCTAssertTrue(vm.hoverGhosting)

        // 调度 120ms 延时收拢
        vm.scheduleHoverClose()

        // 50ms 内用户再次进入并点开
        let exp1 = expectation(description: "Interim wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            vm.openFromGhost()
            exp1.fulfill()
        }
        wait(for: [exp1], timeout: 0.5)

        // 再等待 150ms（总计 200ms > 120ms）
        let exp2 = expectation(description: "Post close deadline wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            exp2.fulfill()
        }
        wait(for: [exp2], timeout: 0.5)

        // 验证：scheduleHoverClose 已被 cancel，面板保持打开
        XCTAssertEqual(vm.status, .opened)
    }
}
