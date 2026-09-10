//
//  EventMonitors.swift
//  NotchDrop
//
//  Created by 秋星桥 on 2024/7/7.
//

import Cocoa
import Combine

struct ScrollDelta {
    let deltaX: CGFloat
    let hasMomentum: Bool
    let timestamp: TimeInterval
}

enum ArrowDirection {
    case leftBackward
    case rightForward
}

// ——— 修复 #25: 协议化以便注入与测试 ———
protocol EventMonitorsProtocol: AnyObject {
    var mouseLocation: CurrentValueSubject<NSPoint, Never> { get }
    var mouseDown: PassthroughSubject<Void, Never> { get }
    var optionKeyPress: CurrentValueSubject<Bool, Never> { get }
    /// 原始滚轮增量：正=右滑，负=左滑；调用方用 ScrollSwipeResolver 解析
    var scrollDelta: PassthroughSubject<ScrollDelta, Never> { get }
    /// 左右键：.leftBackward = 左键上一区，.rightForward = 右键下一区
    var arrowKey: PassthroughSubject<ArrowDirection, Never> { get }
}

class EventMonitors: EventMonitorsProtocol {
    static let shared = EventMonitors()

    private var mouseMoveEvent: EventMonitor!
    private var mouseDownEvent: EventMonitor!
    private var optionKeyPressEvent: EventMonitor!

    let mouseLocation: CurrentValueSubject<NSPoint, Never> = .init(.zero)
    let mouseDown: PassthroughSubject<Void, Never> = .init()
    let optionKeyPress: CurrentValueSubject<Bool, Never> = .init(false)
    let scrollDelta: PassthroughSubject<ScrollDelta, Never> = .init()
    let arrowKey: PassthroughSubject<ArrowDirection, Never> = .init()
    private var scrollEvent: EventMonitor!
    private var keyDownEvent: EventMonitor!

    private init() {
        mouseMoveEvent = EventMonitor(mask: .mouseMoved) { [weak self] _ in
            guard let self else { return }
            let mouseLocation = NSEvent.mouseLocation
            self.mouseLocation.send(mouseLocation)
        }
        mouseMoveEvent.start()

        mouseDownEvent = EventMonitor(mask: .leftMouseDown) { [weak self] _ in
            guard let self else { return }
            mouseDown.send()
        }
        mouseDownEvent.start()

        optionKeyPressEvent = EventMonitor(mask: .flagsChanged) { [weak self] event in
            guard let self else { return }
            if event?.modifierFlags.contains(.option) == true {
                optionKeyPress.send(true)
            } else {
                optionKeyPress.send(false)
            }
        }
        optionKeyPressEvent.start()

        scrollEvent = EventMonitor(mask: .scrollWheel) { [weak self] event in
            guard let self, let event else { return }
            // 只收精确滚轮（触控板与横滚轮）；传统滚轮一格步进也带精确增量，直接收
            self.scrollDelta.send(ScrollDelta(
                deltaX: event.scrollingDeltaX,
                hasMomentum: !event.momentumPhase.isEmpty,
                timestamp: event.timestamp
            ))
        }
        scrollEvent.start()

        keyDownEvent = EventMonitor(mask: .keyDown) { [weak self] event in
            guard let self, let event else { return }
            // 123=左，124=右；不吞事件，只转发
            if event.keyCode == 123 {
                self.arrowKey.send(.leftBackward)
            } else if event.keyCode == 124 {
                self.arrowKey.send(.rightForward)
            }
        }
        keyDownEvent.start()
    }
}

// ——— Preview/测试用 Mock ———
final class MockEventMonitors: EventMonitorsProtocol {
    let mouseLocation: CurrentValueSubject<NSPoint, Never> = .init(.zero)
    let mouseDown: PassthroughSubject<Void, Never> = .init()
    let optionKeyPress: CurrentValueSubject<Bool, Never> = .init(false)
    let scrollDelta: PassthroughSubject<ScrollDelta, Never> = .init()
    let arrowKey: PassthroughSubject<ArrowDirection, Never> = .init()
}
