//
//  QoderPoolIdMatcher.swift
//  NotchEvery
//
//  把「Orb 侧脱敏 user_id」与「余额侧完整 user_id」关联起来的纯函数。
//
//  背景（真机 bug：第三页账号池每个 Orb 环下方余额恒 `--`）：同一批账号的 id 有两个来源、两种格式 ——
//  - UI 侧 `QoderStore.poolMembers[i].userId`：本地网关 `/v1/pool/status` 返回的**脱敏串**，
//    形如 `01a******************************057`（前缀 + 一串星号 + 尾部若干位）；
//  - 余额侧 `QoderStore.poolQuotas[i].userId`：prober 直连上游 `api/v2/quota/usage` 响应体里的
//    **完整 id**（UUID），形如 `01a0be10-1243-7afc-be98-96fdf904b057`。
//  旧的 `$0.userId == 脱敏串` 相等匹配因此永远失败 → 永远查不到 → 永远显示 `--`。
//
//  为什么没走更干净的路子（已实测探查，结论留此免得后人重走）：
//  - 拿不到未脱敏 id：网关二进制里只有 /v1/pool/status、/v1/quota、/v1/chat/completions 等路由，
//    没有 /v1/pool/accounts|list 之类；`?full=true` 参数照样脱敏（真机 curl 验证）。
//  - 让 prober 改用脱敏串做 key 也不可行：掩码在服务端生成，App 侧只能猜星号个数，比现在更脆。
//  - 故只能在展示层用两侧**共同可见的信息**做关联：前缀 + 尾部片段，中间被掩码吃掉的部分无从校验。
//
//  设计约束：**宁可显示 `--`，也绝不张冠李戴**。任何歧义（一个 Orb 命中多个不同账号的余额，
//  或一份余额被多个 Orb 争抢）一律判为无法确定 → nil。
//

import Foundation

enum QoderPoolIdMatcher {

    /// 参与匹配的公共片段最短长度：头部取 3 位、尾部取 3 位。
    /// 短于 `headLen + tailLen` 的输入信息量不足（例如只剩 `"01a"` 前缀），直接判不可确定，避免乱撞。
    static let segmentLength = 3

    /// 去掉分隔符后的可比键：抹掉掩码用的 `*` 与 UUID 的 `-`。
    /// 只解决「格式差异」，不解决「中段被掩码吃掉」——所以还需要下面的前后缀匹配。
    static func normalizeKey(_ userId: String) -> String {
        var out = ""
        out.reserveCapacity(userId.count)
        for ch in userId where ch != "*" && ch != "-" { out.append(ch) }
        return out
    }

    /// 判断「Orb 侧 id（可能脱敏）」与「余额侧 id（可能完整）」是否同一个账号。
    ///
    /// 规则（两侧都归一化后）：
    /// - 等长 → 必须精确相等（两侧都没被掩码时退化为原来的严格匹配，不会放宽）；
    /// - 不等长 → 短的一方是「前缀 + 掩码 + 后缀」：头 `segmentLength` 位必须是长方的前缀、
    ///   尾 `segmentLength` 位必须是长方的后缀。
    ///
    /// 为什么只比前后缀、不再做逐位对齐：脱敏是**用等长星号替换中段**，替换后字符位置整体后移
    /// （实测 `01a**…**057` 去掉星号是 `01a057`，与完整 id 只在第 0、3、4、5 位偶然对齐），
    /// 拿短方逐位去套长方必错。前后缀是唯一两侧都严格保留的不变量。
    /// 代价：`…904b057` 与 `…904057` 会同时命中 `01a*…*057` —— 这类歧义正是上面 `resolve` 要剔除的，
    /// 剔除后即 `--`，绝不张冠李戴。
    static func matches(orbId: String, quotaId: String) -> Bool {
        let a = normalizeKey(orbId)
        let b = normalizeKey(quotaId)
        if a.isEmpty || b.isEmpty { return false }
        if a.count == b.count { return a == b }

        let (short, long) = a.count < b.count ? (a, b) : (b, a)
        let k = segmentLength
        guard short.count >= k * 2 else { return false }
        return long.hasPrefix(String(short.prefix(k))) && long.hasSuffix(String(short.suffix(k)))
    }

    /// 某个 Orb 在余额快照里的全部候选（单测可直接观察候选数，UI 一般用 `quota(for:amongAllOrbs:in:)`）。
    static func candidates(for orbId: String, in quotas: [QoderAccountQuota]) -> [QoderAccountQuota] {
        quotas.filter { matches(orbId: orbId, quotaId: $0.userId) }
    }

    /// 单 Orb 查询（不做多对一保护）。整屏解析请用 `resolve`；UI 用 `quota(for:amongAllOrbs:in:)`。
    static func quota(for orbId: String, in quotas: [QoderAccountQuota]) -> QoderAccountQuota? {
        candidates(for: orbId, in: quotas).unique()
    }

    /// 整屏一次性解析：`orbId -> 额度`，内部做完「一对多 / 多对一」双向歧义剔除。
    /// 单独看某个 Orb 命中唯一，不代表它不被邻座 Orb 争抢 —— 所以 UI 必须走这条路径。
    static func resolve(orbIds: [String], quotas: [QoderAccountQuota]) -> [String: QoderAccountQuota] {
        var byOrb: [String: [QoderAccountQuota]] = [:]
        for id in orbIds { byOrb[id] = candidates(for: id, in: quotas) }

        // 反向索引：每份余额被几个 Orb 认领
        var ownersOf: [String: Set<String>] = [:]
        for (orb, list) in byOrb { for q in list { ownersOf[q.userId, default: []].insert(orb) } }

        var result: [String: QoderAccountQuota] = [:]
        for orb in orbIds {
            guard let only = byOrb[orb]?.unique() else { continue }    // 一对多歧义 → 丢弃
            guard ownersOf[only.userId]?.count == 1 else { continue }  // 多对一歧义 → 丢弃
            result[orb] = only
        }
        return result
    }

    /// UI 入口：给单个 Orb 查余额，但带上整屏 Orb 以便做多对一保护。查不到返回 nil → UI 显示 `--`。
    static func quota(for orbId: String, amongAllOrbs orbIds: [String], in quotas: [QoderAccountQuota]) -> QoderAccountQuota? {
        resolve(orbIds: orbIds, quotas: quotas)[orbId]
    }
}

private extension Array where Element == QoderAccountQuota {
    /// 空 → nil；userId 全相同 → 第一个；出现多个不同 userId → nil（歧义，不敢猜）。
    func unique() -> QoderAccountQuota? {
        guard let first = self.first else { return nil }
        return allSatisfy { $0.userId == first.userId } ? first : nil
    }
}
