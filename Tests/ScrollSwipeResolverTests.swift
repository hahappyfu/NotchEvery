import XCTest
@testable import NotchEvery

final class ScrollSwipeResolverTests: XCTestCase {
    func testLeftSwipeCrossingThresholdGoesNext() {
        var r = ScrollSwipeResolver()
        XCTAssertNil(r.feed(deltaX: -6, hasMomentum: false, now: 0))
        XCTAssertEqual(r.feed(deltaX: -8, hasMomentum: false, now: 0.01), .next)
    }

    func testRightSwipeGoesPrevious() {
        var r = ScrollSwipeResolver()
        XCTAssertEqual(r.feed(deltaX: 14, hasMomentum: false, now: 0), .previous)
    }

    func testMomentumScrollIsIgnored() {
        var r = ScrollSwipeResolver()
        XCTAssertNil(r.feed(deltaX: -50, hasMomentum: true, now: 0))
    }

    func testCooldownAllowsOnlyOneSwitchPerGesture() {
        var r = ScrollSwipeResolver()
        XCTAssertEqual(r.feed(deltaX: -14, hasMomentum: false, now: 0), .next)
        XCTAssertNil(r.feed(deltaX: -14, hasMomentum: false, now: 0.1))
        XCTAssertEqual(r.feed(deltaX: -14, hasMomentum: false, now: 0.5), .next)
    }

    func testBelowThresholdAccumulates() {
        var r = ScrollSwipeResolver()
        XCTAssertNil(r.feed(deltaX: -5, hasMomentum: false, now: 0))
        XCTAssertNil(r.feed(deltaX: -5, hasMomentum: false, now: 0.01))
        XCTAssertEqual(r.feed(deltaX: -5, hasMomentum: false, now: 0.02), .next)
    }

    func testCooldownDiscardsAccumulatedSoNextGestureStartsFresh() {
        var r = ScrollSwipeResolver()
        XCTAssertEqual(r.feed(deltaX: -14, hasMomentum: false, now: 0), .next)
        // 冷却期内反向滑动被拦截，累积量需清零
        XCTAssertNil(r.feed(deltaX: 14, hasMomentum: false, now: 0.1))
        // 冷却过后小幅滑动不应触发（残留累积会被误触发）
        XCTAssertNil(r.feed(deltaX: 5, hasMomentum: false, now: 0.5))
    }

    func testEventMonitorsExposeScrollAndArrowSubjects() {
        let mocks = MockEventMonitors()
        // 编译即通过：原始增量与左右键必须存在
        _ = mocks.scrollDelta
        _ = mocks.arrowKey
    }

    func testVerticalDominantScrollDoesNotTriggerSwipeAndResetsAccumulator() {
        var r = ScrollSwipeResolver()
        // 先产生一点微弱的水平偏移
        _ = r.feed(deltaX: -8, deltaY: 0, hasMomentum: false, now: 0)

        // 用户上下划动（deltaY = 30，伴随微小 deltaX = -5）：判定为纵向滚动，不应切页且必须清零累积量
        XCTAssertNil(r.feed(deltaX: -5, deltaY: 30, hasMomentum: false, now: 0.01))

        // 紧接着来一个较小的水平滑动（-8），因为前一步已被清零，累积仅为 -8（未达阈值 15），不应误触发
        XCTAssertNil(r.feed(deltaX: -8, deltaY: 0, hasMomentum: false, now: 0.02))
    }

    func testHorizontalDominantSwipeTriggersNormally() {
        var r = ScrollSwipeResolver()
        // 水平分量显著大于垂直分量（deltaX = -18, deltaY = 4）：正常触发切页
        XCTAssertEqual(r.feed(deltaX: -18, deltaY: 4, hasMomentum: false, now: 0), .next)
    }
}
