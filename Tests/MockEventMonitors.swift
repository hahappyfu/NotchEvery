//
//  MockEventMonitors.swift
//  NotchEveryTests
//
//  EventMonitorsProtocol 的测试替身（原住在生产 target，已迁入测试 target）。
//

import Cocoa
import Combine
@testable import NotchEvery

final class MockEventMonitors: EventMonitorsProtocol {
    let mouseLocation: CurrentValueSubject<NSPoint, Never> = .init(.zero)
    let mouseDown: PassthroughSubject<Void, Never> = .init()
    let optionKeyPress: CurrentValueSubject<Bool, Never> = .init(false)
    let scrollDelta: PassthroughSubject<ScrollDelta, Never> = .init()
    let arrowKey: PassthroughSubject<ArrowDirection, Never> = .init()
}
