//
//  QoderAccountNicknamesTests.swift
//  NotchEveryTests
//
//  账号池三国昵称的分配契约：跟着账号走、不重名、跨重启不变、名单用尽回落尾号。
//

import XCTest
@testable import NotchEvery

@MainActor
final class QoderAccountNicknamesTests: XCTestCase {

    private func uniqueDefaults() -> UserDefaults {
        let suite = "QoderAccountNicknamesTests-\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    /// 同一个号反复问，名字必须一致（否则 UI 每次渲染都在改名）。
    func testSameAccountKeepsSameName() {
        let svc = QoderAccountNicknames(defaults: uniqueDefaults())
        let first = svc.name(for: "user-a", fallback: "aaaa")
        XCTAssertEqual(svc.name(for: "user-a", fallback: "aaaa"), first)
        XCTAssertNotEqual(first, "aaaa", "拿到名单里的名字，而不是回落尾号")
    }

    /// 不同号必须拿到不同名字——重名会让「哪个号还剩多少」彻底无法分辨。
    func testDifferentAccountsGetDistinctNames() {
        let svc = QoderAccountNicknames(defaults: uniqueDefaults())
        let ids = (0..<8).map { "user-\($0)" }
        let names = ids.map { svc.name(for: $0, fallback: "f\($0)") }
        XCTAssertEqual(Set(names).count, names.count, "8 个号必须 8 个不同名字，实际 \(names)")
        XCTAssertTrue(names.allSatisfy { QoderNicknameRoster.names.contains($0) })
    }

    /// 名单里全是 2 字名：Orb 只有 48pt，3 字会被挤扁（这条防日后有人往名单里塞长名字）。
    func testRosterNamesAreTwoCharacters() {
        for name in QoderNicknameRoster.names {
            XCTAssertEqual(name.count, 2, "「\(name)」不是 2 字，会撑破 Orb 排版")
        }
    }

    /// 模拟 App 重启：换新实例、同一份 UserDefaults，名字必须还是原来那个。
    func testAssignmentsPersistAcrossInstances() {
        let defaults = uniqueDefaults()
        let first = QoderAccountNicknames(defaults: defaults)
        let assigned = first.name(for: "user-a", fallback: "aaaa")

        let revived = QoderAccountNicknames(defaults: defaults)
        XCTAssertEqual(revived.name(for: "user-a", fallback: "aaaa"), assigned,
                       "重启后昵称不能变，否则用户记的名字就白记了")
    }

    /// 名单用尽（账号数超过名单长度）时回落尾号：不重名、不崩溃。
    func testRosterExhaustionFallsBackToTail() {
        let svc = QoderAccountNicknames(defaults: uniqueDefaults())
        let overflow = QoderNicknameRoster.names.count + 3
        var names: [String] = []
        for i in 0..<overflow {
            names.append(svc.name(for: "user-\(i)", fallback: "tail-\(i)"))
        }

        let rosterCount = QoderNicknameRoster.names.count
        for i in 0..<rosterCount {
            XCTAssertTrue(QoderNicknameRoster.names.contains(names[i]), "前 \(rosterCount) 个应拿到名单里的名字")
        }
        for i in rosterCount..<overflow {
            XCTAssertEqual(names[i], "tail-\(i)", "超出名单的号应回落尾号")
        }
        XCTAssertEqual(Set(names).count, names.count, "回落也不能与已分配名字重复")
    }

    /// 空 userId 直接回落，不占用名单里的名字。
    func testEmptyUserIdFallsBackWithoutConsumingRoster() {
        let svc = QoderAccountNicknames(defaults: uniqueDefaults())
        XCTAssertEqual(svc.name(for: "", fallback: "----"), "----")
        XCTAssertEqual(svc.name(for: "user-a", fallback: "aaaa"), QoderNicknameRoster.names.first,
                       "空 id 不该消耗名单首位")
    }
}
