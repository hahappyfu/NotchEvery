//
//  FlowPauseController.swift
//  NotchEvery
//
//  实时流水暂停定格：冻结当前行、累计未读、有界待读队列与缺口计数。
//

import Foundation

struct FlowPauseController: Equatable {
    static let pendingCapacity = 200
    private static let seenCapacity = 500

    private(set) var isPaused = false
    private(set) var frozenRows: [MagpieFlowRow] = []
    private(set) var missedCount = 0
    private(set) var gapCount = 0

    /// 仅供测试观察队列占用；业务侧只关心 missed/gap 计数。
    var pendingRowCount: Int { pendingRows.count }

    private var pendingRows: [MagpieFlowRow] = []
    private var seenIDs: [String] = []

    mutating func pause(liveRows: [MagpieFlowRow]) {
        isPaused = true
        frozenRows = Array(liveRows.prefix(5))
        pendingRows = []
        missedCount = 0
        seenIDs = frozenRows.map(\.id)
    }

    mutating func receive(liveRows: [MagpieFlowRow]) {
        guard isPaused else { return }
        for row in liveRows where !seenIDs.contains(row.id) {
            remember(row.id)
            missedCount += 1
            pendingRows.append(row)
            if pendingRows.count > Self.pendingCapacity {
                let dropped = pendingRows.removeFirst()
                gapCount += 1
                _ = dropped
            }
        }
    }

    mutating func resume(liveRows: [MagpieFlowRow]) -> Int {
        isPaused = false
        frozenRows = []
        pendingRows = []
        missedCount = 0
        // shortcut: resume 不合并待读行，列表由 MagpieStore 下一帧的最新快照接管
        return gapCount
    }

    private mutating func remember(_ id: String) {
        seenIDs.append(id)
        if seenIDs.count > Self.seenCapacity {
            seenIDs.removeFirst(seenIDs.count - Self.seenCapacity)
        }
    }
}
