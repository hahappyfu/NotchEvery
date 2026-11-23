import XCTest
@testable import NotchEvery

final class MagpieFilesTests: XCTestCase {
    private func data(_ json: String) -> Data { Data(json.utf8) }

    // 1. quotas：spans[i].aside 平行数组、used 为百分数、windows 缺失容错
    func testParseQuotasSpansAsideAndPercentValues() throws {
        let json = """
        {
          "codearts/151****4090": {
            "at": "2026-11-23T16:08:31.500874+08:00",
            "quota": {
              "provider": "codearts",
              "name": "CodeArts",
              "icon": "file:33fdbde9f5f8ea57.svg",
              "plan": "体验版",
              "user": "151****4090",
              "windows": [
                {"name": "总积分", "used": 1.88, "amount": 86.76, "limit": 4600, "unit": "credits", "display": "87 / 4600"},
                {"name": "基础包", "used": 1.0, "amount": 10, "limit": 100, "unit": "credits"}
              ]
            },
            "spans": [{}, {"aside": true}]
          }
        }
        """
        let entries = try XCTUnwrap(MagpieFiles.parseQuotas(data(json)))
        XCTAssertEqual(entries.count, 1)
        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entry.accountKey, "codearts/151****4090")
        XCTAssertEqual(entry.provider, "codearts")
        XCTAssertEqual(entry.account, "151****4090")
        XCTAssertEqual(entry.name, "CodeArts")
        XCTAssertEqual(entry.icon, "file:33fdbde9f5f8ea57.svg")
        XCTAssertEqual(entry.plan, "体验版")
        XCTAssertEqual(entry.user, "151****4090")
        XCTAssertEqual(entry.windows.count, 2)
        XCTAssertFalse(entry.windows[0].isAside)
        XCTAssertTrue(entry.windows[1].isAside)
        XCTAssertEqual(entry.windows[0].usedPercent ?? -1, 1.88, accuracy: 0.0001)
        XCTAssertEqual(entry.windows[0].amount ?? -1, 86.76, accuracy: 0.0001)
        XCTAssertEqual(entry.windows[0].limit ?? -1, 4600, accuracy: 0.0001)
        XCTAssertEqual(entry.windows[0].unit, "credits")
        XCTAssertNotNil(entry.at)

        let missingWindows = try XCTUnwrap(MagpieFiles.parseQuotas(data(#"{"p/a":{"quota":{"provider":"p","name":"P"}}}"#)))
        XCTAssertEqual(missingWindows.first?.windows.count, 0)
        XCTAssertEqual(missingWindows.first?.account, "a")
        XCTAssertEqual(missingWindows.first?.provider, "p")
    }

    // 2. limit-notices：provider@account 拆分、until 可缺省
    func testParseLimitNoticesSplitsProviderAndAccount() throws {
        let json = #"""
        {
          "alpha@acct-1": {"key": "k1", "why": "rate", "status": 429, "at": "2026-11-23T16:00:00+08:00", "until": "2026-11-23T18:00:00+08:00"},
          "sensenova@x": {"why": "risk", "status": 405, "at": "2026-11-23T16:00:00+08:00"}
        }
        """#
        let notices = try XCTUnwrap(MagpieFiles.parseLimitNotices(data(json)))
        XCTAssertEqual(notices.count, 2)
        let first = try XCTUnwrap(notices["alpha@acct-1"])
        XCTAssertEqual(first.provider, "alpha")
        XCTAssertEqual(first.account, "acct-1")
        XCTAssertEqual(first.status, 429)
        XCTAssertEqual(first.why, "rate")
        XCTAssertNotNil(first.at)
        XCTAssertNotNil(first.until)
        let second = try XCTUnwrap(notices["sensenova@x"])
        XCTAssertEqual(second.provider, "sensenova")
        XCTAssertEqual(second.account, "x")
        XCTAssertNil(second.until)
        XCTAssertEqual(second.status, 405)
    }

    // 3. plugin-checkin：provider|slot 拆分、outcome 原样
    func testParseCheckinsSplitsProviderAndSlotKeepingOutcome() throws {
        let json = #"""
        {
          "codearts|default": {"day": "2026-11-23", "at": "2026-11-23T09:00:00+08:00", "outcome": "claimed", "credit": 100},
          "workbuddy|main": {"day": "2026-11-23", "at": "2026-11-23T09:05:00+08:00", "outcome": "done", "credit": 300, "msg": "ok"},
          "other|slot": {"day": "2026-11-23", "outcome": "ineligible"}
        }
        """#
        let checkins = try XCTUnwrap(MagpieFiles.parseCheckins(data(json)))
        XCTAssertEqual(checkins.count, 3)
        let claimed = try XCTUnwrap(checkins.first(where: { $0.provider == "codearts" }))
        XCTAssertEqual(claimed.slot, "default")
        XCTAssertEqual(claimed.outcome, "claimed")
        XCTAssertEqual(claimed.credit ?? -1, 100, accuracy: 0.0001)
        XCTAssertEqual(claimed.day, "2026-11-23")
        XCTAssertEqual(checkins.first(where: { $0.provider == "workbuddy" })?.outcome, "done")
        XCTAssertEqual(checkins.first(where: { $0.provider == "other" })?.outcome, "ineligible")
    }

    // 4. providers + pluginProviders 名称非空优先合并
    func testProviderAndPluginMergeNamePriority() throws {
        let providersJSON = #"""
        {
          "providers": [
            {"id": "p1", "name": "Provider One", "icon": "file:one.svg"},
            {"id": "p2", "name": "", "hidden": true}
          ],
          "groups": [
            {"id": "g1", "name": "Group One"},
            {"id": "g2", "name": "Hidden Group", "hidden": true}
          ]
        }
        """#
        let part = try XCTUnwrap(MagpieFiles.parseProviders(data(providersJSON)))
        XCTAssertEqual(part.entries["p1"]?.name, "Provider One")
        XCTAssertEqual(part.entries["p1"]?.signedIn, true)
        XCTAssertEqual(part.entries["p1"]?.icon, "file:one.svg")
        XCTAssertEqual(part.entries["p2"]?.hidden, true)
        XCTAssertEqual(part.groupNameByProviderRef["group/g1"], "Group One")
        XCTAssertEqual(part.groupNameByProviderRef["g1"], "Group One")
        XCTAssertNil(part.groupNameByProviderRef["g2"])

        let pluginsJSON = #"[{"id":"x","name":"Plugin X","signedIn":true},{"id":"y","name":"Plugin Y","signedIn":false}]"#
        let plugins = try XCTUnwrap(MagpieFiles.parsePluginProviders(data(pluginsJSON)))
        XCTAssertEqual(plugins.count, 2)

        let catalog = MagpieProviderCatalog.merged(
            providers: MagpieProviderCatalog.ProviderPart(
                entries: [
                    "p1": .init(id: "p1", name: "Provider One", icon: nil, hidden: false, disabled: false, signedIn: true),
                    "p2": .init(id: "p2", name: "", icon: nil, hidden: true, disabled: false, signedIn: true)
                ],
                groupNameByProviderRef: ["group/g1": "Group One", "g1": "Group One"]
            ),
            plugins: [
                .init(id: "p2", name: "Plugin Two", icon: "file:p2.svg", signedIn: true),
                .init(id: "p4", name: "Plugin Four", icon: nil, signedIn: true),
                .init(id: "p5", name: "Plugin Five", icon: nil, signedIn: false)
            ]
        )
        XCTAssertEqual(catalog.entries["p1"]?.name, "Provider One")
        XCTAssertEqual(catalog.entries["p2"]?.name, "Plugin Two")
        XCTAssertEqual(catalog.entries["p2"]?.hidden, true)
        XCTAssertEqual(catalog.entries["p2"]?.icon, "file:p2.svg")
        XCTAssertEqual(catalog.entries["p4"]?.signedIn, true)
        XCTAssertEqual(catalog.entries["p5"]?.signedIn, false)
        XCTAssertEqual(catalog.groupNameByProviderRef["group/g1"], "Group One")
    }

    // 5. routeIndex：group.name、同 routeID 覆盖、order 快照按 provider 取最新
    func testRouteIndexLatestWinsPerRouteAndAccount() {
        let lines = [
            #"{"id":1,"group":{"id":"g1","ref":"ref1","name":"First"},"order":[{"id":"o1","provider":"p1","name":"P One","used":10,"amount":10,"limit":100,"unit":"credits"}]}"#,
            #"{"id":1,"group":{"id":"g1","ref":"ref1","name":"Second"}}"#,
            #"{"id":2,"group":{"id":"g2","ref":"ref2","name":"Other"},"order":[{"id":"o1","provider":"p1","used":20}]}"#
        ].map { Data($0.utf8) }
        let index = MagpieFiles.parseRouteIndex(lines: lines)
        XCTAssertEqual(index.groupNameByRouteID[1], "Second")
        XCTAssertEqual(index.groupNameByRouteID[2], "Other")
        XCTAssertEqual(index.groupNameByRef["ref2"], "Other")
        XCTAssertEqual(index.groupNameByRef["group/ref2"], "Other")
        XCTAssertEqual(index.orderSnapshotsByAccount["o1"]?.used ?? -1, 20, accuracy: 0.0001)
        XCTAssertEqual(index.orderSnapshotsByAccount["o1"]?.provider, "p1")
    }

    // 6. routeIndex >200 条裁剪保最近
    func testRouteIndexTrimsToMostRecent200() {
        let lines = (1...205).map { i in
            Data("{\"id\":\(i),\"group\":{\"id\":\"g\(i)\",\"name\":\"G\(i)\"}}".utf8)
        }
        let index = MagpieFiles.parseRouteIndex(lines: lines)
        XCTAssertEqual(index.groupNameByRouteID.count, 200)
        XCTAssertNil(index.groupNameByRouteID[1])
        XCTAssertNil(index.groupNameByRouteID[5])
        XCTAssertEqual(index.groupNameByRouteID[6], "G6")
        XCTAssertEqual(index.groupNameByRouteID[205], "G205")
    }

    // 7. gateway、quota-history、masking 行解码
    func testParseGatewayQuotaHistoryAndMasking() throws {
        let gateway = try XCTUnwrap(MagpieFiles.parseGateway(data(#"{"addr":"127.0.0.1:3425","pid":123,"version":"0.1.4692","started":"2026-11-23T08:00:00+08:00"}"#)))
        XCTAssertEqual(gateway.addr, "127.0.0.1:3425")
        XCTAssertEqual(gateway.pid, 123)
        XCTAssertEqual(gateway.version, "0.1.4692")
        XCTAssertNotNil(gateway.started)

        let history = try XCTUnwrap(MagpieFiles.parseQuotaHistory(data(#"{"codearts|151":{"总积分":[{"at":"2026-11-23T10:00:00+08:00","left":80.5},{"at":"2026-11-23T11:00:00+08:00","left":70}]}}"#)))
        XCTAssertEqual(history["codearts|151"]?["总积分"]?.count, 2)
        XCTAssertEqual(history["codearts|151"]?["总积分"]?.last?.left ?? -1, 70, accuracy: 0.0001)

        let masking = try XCTUnwrap(MagpieFiles.decodeMaskingLine(data(#"{"route":1795,"n":3,"t":"2026-11-23T10:00:00+08:00"}"#)))
        XCTAssertEqual(masking.route, 1795)
        XCTAssertEqual(masking.n, 3)
        XCTAssertNotNil(masking.time)
        XCTAssertNil(MagpieFiles.decodeMaskingLine(data(#"{"n":3}"#)))
    }

    // 8. 损坏 JSON → nil；空对象/空数组 → 空值
    func testCorruptJSONReturnsNilAndEmptyJSONReturnsEmpty() {
        XCTAssertNil(MagpieFiles.parseGateway(Data()))
        XCTAssertNil(MagpieFiles.parseQuotas(data("not json")))
        XCTAssertNil(MagpieFiles.parseLimitNotices(data("{")))
        XCTAssertNil(MagpieFiles.parseCheckins(data("[]")))
        XCTAssertNil(MagpieFiles.parseProviders(data("[]")))
        XCTAssertNil(MagpieFiles.parsePluginProviders(data("{}")))
        XCTAssertNil(MagpieFiles.parseQuotaHistory(data("null")))

        XCTAssertEqual(MagpieFiles.parseQuotas(data("{}")), [])
        XCTAssertEqual(MagpieFiles.parseLimitNotices(data("{}"))?.isEmpty, true)
        XCTAssertEqual(MagpieFiles.parseCheckins(data("{}")), [])
        XCTAssertEqual(MagpieFiles.parsePluginProviders(data("[]")), [])
        XCTAssertEqual(MagpieFiles.parseProviders(data("{}"))?.entries.isEmpty, true)
        XCTAssertEqual(MagpieFiles.parseQuotaHistory(data("{}"))?.isEmpty, true)
        XCTAssertEqual(MagpieFiles.parseQuotaHistory(data("[]")), nil)

        // 空文件是合法的空集合，不是解码失败。
        XCTAssertEqual(MagpieFiles.parseQuotas(Data()), [])
        XCTAssertTrue(MagpieFiles.parseLimitNotices(Data())?.isEmpty == true)
        XCTAssertTrue(MagpieFiles.parseCheckins(Data())?.isEmpty == true)
        XCTAssertTrue(MagpieFiles.parseProviders(Data())?.entries.isEmpty == true)
        XCTAssertTrue(MagpieFiles.parsePluginProviders(Data())?.isEmpty == true)
        XCTAssertTrue(MagpieFiles.parsePluginIcons(Data())?.isEmpty == true)
        XCTAssertTrue(MagpieFiles.parseQuotaHistory(Data())?.isEmpty == true)
    }

    // A2: providers.json 的 accountNames 解码并保留在目录中。
    func testParseProvidersAccountNames() throws {
        let providersData = data(#"{"providers":[{"id":"p","name":"P","accountNames":{"a1":"手机主号"}}]}"#)
        let parsed = try XCTUnwrap(MagpieFiles.parseProviders(providersData))
        XCTAssertEqual(parsed.entries["p"]?.accountNames["a1"], "手机主号")

        let catalog = MagpieProviderCatalog.merged(providers: parsed, plugins: [
            .init(id: "p", name: "Plugin P", icon: nil, signedIn: true),
            .init(id: "plugin", name: "Plugin", icon: nil, signedIn: true)
        ])
        XCTAssertEqual(catalog.entries["p"]?.accountNames["a1"], "手机主号")
        XCTAssertEqual(catalog.entries["plugin"]?.accountNames, [:])
    }

    // A5: order 快照按账号 id 存储，同 id 后写覆盖先写。
    func testRouteIndexKeepsEveryOrderAccountAndLatestWins() {
        let lines = [
            #"{"id":1,"order":[{"id":"a1","provider":"p","who":"old","used":10}]}"#,
            #"{"id":2,"order":[{"id":"a2","provider":"p","who":"second","used":20}]}"#,
            #"{"id":3,"order":[{"id":"a1","provider":"p","who":"new","used":30}]}"#
        ].map { Data($0.utf8) }
        let index = MagpieFiles.parseRouteIndex(lines: lines)
        XCTAssertEqual(Set(index.orderSnapshotsByAccount.keys), ["a1", "a2"])
        XCTAssertEqual(index.orderSnapshotsByAccount["a1"]?.who, "new")
        XCTAssertEqual(index.orderSnapshotsByAccount["a2"]?.who, "second")
    }
}
