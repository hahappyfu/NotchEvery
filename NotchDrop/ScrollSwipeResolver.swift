import Foundation

/// 滚轮手势解析器：纯值类型，无 AppKit 依赖，可单测。
/// 方向约定：手指左滑（增量为负）= 下一区，和浏览器前进手势一致；
/// 导航手势不跟随自然滚动方向取反，原样用增量符号。
struct ScrollSwipeResolver {
    /// 触发一次切换需要的累积位移
    var threshold: CGFloat = 12
    /// 两次切换的最短间隔，抬手一次只切一区
    var cooldown: TimeInterval = 0.35

    private var accumulated: CGFloat = 0
    private var lastAccepted: TimeInterval = -.infinity

    mutating func feed(deltaX: CGFloat, hasMomentum: Bool, now: TimeInterval) -> SwipeDirection? {
        // 惯性动量是手指已离开后的余波，不计入
        guard !hasMomentum else { return nil }
        accumulated += deltaX
        guard abs(accumulated) >= threshold else { return nil }
        // 冷却期内不接受第二次切换，累积量清零避免污染下次手势
        guard now - lastAccepted >= cooldown else {
            accumulated = 0
            return nil
        }
        lastAccepted = now
        let direction: SwipeDirection = accumulated < 0 ? .next : .previous
        accumulated = 0
        return direction
    }

    mutating func reset() {
        accumulated = 0
    }
}
