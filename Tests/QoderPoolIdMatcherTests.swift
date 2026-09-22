//
//  QoderPoolIdMatcherTests.swift
//  NotchEveryTests
//
//  真机 bug 回归锁：第三页 Qoder 账号池每个 Orb 环下方余额恒 `--`。
//  根因是两侧 userId 格式不同 —— UI 侧（网关 /v1/pool/status）是脱敏串
//  `01a******************************057`，余额侧（prober 直连 /api/v2/quota/usage）是完整 UUID
//  `01a0be10-1243-7afc-be98-96fdf904b057`，旧的 `$0.userId == 脱敏串` 相等匹配永远失败。
//  这里锁住新的关联纯函数：正常一对一对应、歧义保守拒配、查不到降级、以及真实样例端到端。
//

import XCTest
@testable import NotchEvery

final class QoderPoolIdMatcherTests: XCTestCase {

    // MARK: - 真实抓包样例（本机实测数据，勿改）

    private let masked = [
        "01a******************************057",
        "01a******************************201",
        "01a******************************3e7",
        "01a******************************4a9",
    ]
    private let full = [
        "01a0b87c-59e6-7f1d-b2e3-a055eb2f6201",
        "01a0bc59-9878-7388-b17c-211c6c7104a9",
        "01a0be10-1243-7afc-be98-96fdf904b057",
        "01a0be11-e75a-7177-b471-7dd3118ed3e7",
    ]

    // MARK: - 旧实现的缺陷 → 新实现的修复

    /// 这是恒 `--` 的核心回归断言：脱敏串与完整 UUID **不是**同一个字符串（旧的相等匹配必然落空），
    /// 但新 matcher 必须把它们认成同一个号 —— 二者都要成立，才说明修的是关联而不是把 id 改了。
    func testMaskedIdResolvesAcrossFormatGap() {
        let quotas = [QoderAccountQuota(userId: full[2], planRemaining: 100, addOnRemaining: 0)]
        XCTAssertNotEqual(masked[0], full[2], "两种格式本身不相等（旧相等匹配因此永远失败）")
        XCTAssertEqual(QoderPoolIdMatcher.quota(for: masked[0], in: quotas)?.userId, full[2],
                       "新 matcher 必须跨过格式差异把它们关联起来")
    }

    // MARK: - normalizeKey

    func testNormalizeKeyStripsSeparators() {
        XCTAssertEqual(QoderPoolIdMatcher.normalizeKey("01a0be10-1243-7afc-be98-96fdf904b057"),
                       "01a0be1012437afcbe9896fdf904b057")
        XCTAssertEqual(QoderPoolIdMatcher.normalizeKey("01a*-*057"), "01a057")
        XCTAssertEqual(QoderPoolIdMatcher.normalizeKey(""), "")
    }

    // MARK: - 一对一对应

    func testSinglePairMatches() {
        let q = QoderAccountQuota(userId: full[2], planRemaining: 250, addOnRemaining: 50)
        let got = try? XCTUnwrap(QoderPoolIdMatcher.quota(for: masked[0], in: [q]))
        XCTAssertEqual(got?.userId, full[2], "唯一候选必须命中")
        XCTAssertEqual(got?.totalRemaining, 300)
    }

    func testRealFourAccountsAllResolveUniquely() {
        // 期望配对：尾号 → 完整 UUID（本机实测数据）
        let expectedByTail: [(String, String)] = [
            (masked[0], "01a0be10-1243-7afc-be98-96fdf904b057"),   // …057
            (masked[1], "01a0b87c-59e6-7f1d-b2e3-a055eb2f6201"),   // …201
            (masked[2], "01a0be11-e75a-7177-b471-7dd3118ed3e7"),   // …3e7
            (masked[3], "01a0bc59-9878-7388-b17c-211c6c7104a9"),   // …4a9
        ]
        let quotas = full.map { QoderAccountQuota(userId: $0, planRemaining: 10, addOnRemaining: 0) }
        for (m, id) in expectedByTail {
            let hits = QoderPoolIdMatcher.candidates(for: m, in: quotas)
            XCTAssertEqual(hits.count, 1, "\(m) 必须唯一命中")
            XCTAssertEqual(hits.first?.userId, id, "\(m) 应解析到 \(id)")
        }
    }

    /// 双方都是完整 id 时（网关哪天不脱敏了），仍要能正确匹配，不能因为走前后缀逻辑而失配。
    func testFullIdAgainstFullIdsStillMatches() {
        let quotas = full.map { QoderAccountQuota(userId: $0, planRemaining: 10, addOnRemaining: 0) }
        XCTAssertEqual(QoderPoolIdMatcher.quota(for: full[2], in: quotas)?.userId, full[2])
    }

    // MARK: - 歧义保护（张冠李戴比显示 -- 严重得多）

    /// 两个候选都能满足「同前缀 + 同后缀」→ 无法确定归属，必须返回 nil 让 UI 显示 --。
    func testAmbiguousSuffixRefusesToGuess() {
        let a = QoderAccountQuota(userId: "01a0be10-1243-7afc-be98-96fdf904b057", planRemaining: 900, addOnRemaining: 0)
        let b = QoderAccountQuota(userId: "01a0ffff-1243-7afc-be98-96fdf999b057", planRemaining: 1, addOnRemaining: 0)
        XCTAssertNil(QoderPoolIdMatcher.quota(for: masked[0], in: [a, b]),
                     "后缀撞车时必须拒配，绝不能把 900 或 1 随便安到某个 Orb 上")
    }

    /// 反向撞车：一份余额同时符合两个 Orb 的脱敏串。单看每个 Orb 都「唯一命中」，
    /// 所以必须由**整屏入口** `resolve` 做多对一剔除 —— 两边都不给（宁缺勿错配）。
    func testOneQuotaMatchingTwoOrbsMarksBothAmbiguous() {
        let shared = QoderAccountQuota(userId: "01a0be10-1243-7afc-be98-96fdf904057", planRemaining: 42, addOnRemaining: 0)
        let orbs = ["01a******************************057", "01a*****************************4057"]
        // 前置条件：单点查询各自确实都能命中同一份余额（证明歧义来自争抢而非查不到）
        XCTAssertEqual(QoderPoolIdMatcher.quota(for: orbs[0], in: [shared])?.userId, shared.userId)
        XCTAssertEqual(QoderPoolIdMatcher.quota(for: orbs[1], in: [shared])?.userId, shared.userId)
        XCTAssertTrue(QoderPoolIdMatcher.resolve(orbIds: orbs, quotas: [shared]).isEmpty,
                      "多对一必须整屏判为不确定")
        for orb in orbs {
            XCTAssertNil(QoderPoolIdMatcher.quota(for: orb, amongAllOrbs: orbs, in: [shared]))
        }
    }

    /// 只有完整 id 集合内部重复（同一 user_id 出现两次）不算歧义：它们指向同一个号，取第一个即可。
    func testDuplicateSameUserIdIsNotAmbiguity() {
        let quotas = [
            QoderAccountQuota(userId: full[2], planRemaining: 100, addOnRemaining: 0),
            QoderAccountQuota(userId: full[2], planRemaining: 100, addOnRemaining: 0),
        ]
        XCTAssertEqual(QoderPoolIdMatcher.quota(for: masked[0], in: quotas)?.userId, full[2])
    }

    // MARK: - 优雅降级

    func testNoCandidatesDegradesToNil() {
        XCTAssertNil(QoderPoolIdMatcher.quota(for: masked[0], in: []))
    }

    func testGarbageInputsDegradeToNilWithoutCrashing() {
        let quotas = full.map { QoderAccountQuota(userId: $0, planRemaining: 1, addOnRemaining: 0) }
        for bad in ["", "***", "-", "x", "01a", "057", "************"] {
            XCTAssertNil(QoderPoolIdMatcher.quota(for: bad, in: quotas), "非法/过短的 id 不能乱匹配：\(bad)")
        }
    }

    /// 前缀不同的同号后缀也不能错配（防跨号张冠李戴）。
    func testDifferentPrefixDoesNotMatch() {
        let quotas = [QoderAccountQuota(userId: "09f0be10-1243-7afc-be98-96fdf904b057", planRemaining: 7, addOnRemaining: 0)]
        XCTAssertNil(QoderPoolIdMatcher.quota(for: masked[0], in: quotas))
    }

    // MARK: - UI 侧真正用的整屏入口 resolve / quota(amongAllOrbs:)

    /// 真实四号整屏：每个 Orb 都要解析出自己的余额（这是恒 `--` bug 的端到端断言）。
    func testResolveRealScreenAllFourOrbs() {
        let quotas = zip(masked, [300.0, 200.0, 100.0, 50.0]).map { m, plan in
            QoderAccountQuota(userId: try! XCTUnwrap(soleFull(for: m)), planRemaining: plan, addOnRemaining: 0)
        }
        let map = QoderPoolIdMatcher.resolve(orbIds: masked, quotas: quotas)
        XCTAssertEqual(map.count, 4, "整屏四个 Orb 都应解析成功")
        for (m, plan) in zip(masked, [300.0, 200.0, 100.0, 50.0]) {
            XCTAssertEqual(map[m]?.totalRemaining, plan, "\(m)")
        }
    }

    /// 脱敏串 → 唯一对应的完整 UUID（真实数据，供上面端到端用例复用）。
    private func soleFull(for mask: String) -> String? {
        full.filter { QoderPoolIdMatcher.matches(orbId: mask, quotaId: $0) }.first
    }

    /// 多对一保护走整屏入口：单看某个 Orb 命中唯一，但邻座 Orb 也抢同一份余额 → 两边都不给。
    func testResolveDropsMutuallyContestedQuota() {
        let shared = QoderAccountQuota(userId: "01a0be10-1243-7afc-be98-96fdf904057", planRemaining: 42, addOnRemaining: 0)
        let orbs = ["01a******************************057", "01a*****************************4057"]
        XCTAssertTrue(QoderPoolIdMatcher.resolve(orbIds: orbs, quotas: [shared]).isEmpty,
                      "一份余额被两个 Orb 争抢时，宁缺勿错配")
        XCTAssertNil(QoderPoolIdMatcher.quota(for: orbs[0], amongAllOrbs: orbs, in: [shared]))
    }

    /// 整屏里只有一号歧义时，其余号不受牵连。
    func testResolveKeepsUnambiguousOrbsWhenOneIsAmbiguous() {
        let quotas = full.map { QoderAccountQuota(userId: $0, planRemaining: 10, addOnRemaining: 0) }
            + [QoderAccountQuota(userId: "01a0ffff-1243-7afc-be98-96fdf999b057", planRemaining: 99, addOnRemaining: 0)]
        let map = QoderPoolIdMatcher.resolve(orbIds: masked, quotas: quotas)
        XCTAssertNil(map[masked[0]], "…057 撞车应被剔除")
        XCTAssertEqual(map.count, 3)
    }
}
