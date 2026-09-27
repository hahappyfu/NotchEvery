# 审计发现存档：数据/存储层（reviewer-data）

> 中间存档；最终汇总见总报告。17 文件全审 + 调用方交叉验证。

## Critical
- **C1** PublishedPersist.swift:76-105 + :54-64 — Persist 解码失败 → CurrentValueSubject 立即回放 defaultValue → sink 写盘**原地覆盖**坏文件，无备份无迁移。触发：任何对 TrayDropItem/ClaimFeedback 的非加性 Codable 改动，老用户升级首启即暂存列表静默清零且无法找回。对照 ConfigStore.swift:115-120 同场景会移 .corrupt.<ts> 备份——同项目两种口径。修复：解码失败移出备份再回落默认，或 payload 加版本号。

## Important
- **I1** AntigravityStore.swift:324-364 vs :203-238 — selectAccount 点选会被 3s 轮询的「最近活跃动态检测」冲掉（用户选 B → 3 秒后高亮弹回 A）；且 :227-237 对 ~/.antigravity_tools/accounts.json 无锁读改写（与工具自身写入交错后写者胜），try? 吞写失败。
- **I2** ClipboardStore.swift:180-189 vs :223-234 — clearAll 直接删盘 vs saveToDisk 经 saveQueue.async；清空后被挂起写盘「复活」指向已删图片的幽灵条目，重启后图片项永久失败。修复：clearAll 也走 saveQueue 或先 sync 排空。
- **I3** QoderLogParser.swift:70-74 + QoderStore.swift:239-240,475-482 — 轮转/瞬时读错误触发全文件重扫，today 桶重复累计（今日请求/credits 虚高翻倍）；copytruncate 轮转即触发。修复：重扫时以「清桶重灌」语义工作。
- **I4** QoderGatewayManager.swift:218,251 vs :116,:285,:241 — process/stdinWriteEnd 跨线程读写无同步（数据竞争）；requestStop 仅允许 .running（:41-44），.starting 20s 健康轮询窗口内 stop 是死按钮；applicationWillTerminate 在 .starting 只关 stdinWriteEnd（若 spawn 未执行到赋值行读 nil 什么都不做）。修法：收敛主线程或加锁。
- **I5** UsageStore.swift:73 — activeSource 全项目无写入方，cc-switch 数据源（ADR-0005）与 CCSwitchUsageStore（:345-579 约 240 行 SQL）永远不可达=死代码；dbPath 参数随之失效。判定：迁移残留而非半成品。建议删双源路由或真正接线到设置。

## Minor
- M1 UsageStore.swift:434,466,502,516 providerId 字符串拼接 SQL（含单引号即 prepare 失败静默变空）；当前在不可达路径，复活前改参数绑定。
- M2 QoderStore.swift:460-461 URL(string:)! 强解包（测试注入负端口可崩）。改 guard let。
- M3 QoderLogParser.swift:126-130 多个非今日日期混进同个 yesterday 桶（注释自认），跨周末「昨日」多日混合。
- M4 UserDefaults 按天 key 永不清理（QoderStore.swift:217-219、QoderCampaignClaimer.swift:274,374-376），长年累积无清扫点。
- M5 QoderGatewayManager.swift:356-361 gateway.log 只追加永不轮转无上限；:370-397 drain 对永久性读错误 10Hz 无限重试。
- M6 ClipboardStore.swift:117-127 addImage 去重主线程同步读盘全量字节比对（截图数 MB）；:132-136 写图失败静默。
- M7 ConfigStore.swift:117-118 corrupt 备份无限累积；:122-134 持锁同步整文件落盘（影响轻）。
- M8 PublishedPersist.swift:29-43 dirEnsured 未同步 Bool，良性但正式的竞争。
- M9 RingBuffer.swift 全项目零引用，纯死代码，建议删。
- M10 存储层全线 ObservableObject+@Published 与 AGENTS.md「@Observable 优先」不一致（历史包袱）。
- M11 QoderCampaignClaimer.swift:203,208 打印完整 credential.userId（其余位置 prefix(8)）。
- M12 家目录口径分裂：AppPaths.swift:12 / QoderPoolCredentials.swift:43 用 NSHomeDirectory，UsageStore.swift:170-174 用 getpwuid 绕沙盒重定向；沙盒化时埋雷。
- M13 QoderStore.swift:462-463 HTTP 成功但 decode 失败时 consecutiveFailures 已清零、quota 发布 nil——格式漂移时用户见空数据无 stale 标记。
- M14 SecurityService.swift:62,73,85-90 安全层直接弹 NSAlert 模态（UI 侵入）；handlePasswordChanged :116-117 连续两次完整查询 Keychain。

## 优点（供汇总）
- SQLite 只读打开策略扎实（普通只读优先读 WAL 未 checkpoint 数据、失败降级 immutable=1、query_only+busy_timeout+FULLMUTEX、defer close）——dcc2018 修复的正确延续
- 值级去重发布贯穿全层（QoderStore.swift:499-503 等）
- QoderCampaignGuard/QoderPoolQuotaGuard 纯函数状态机；nil（守卫挡掉）vs []（真探完为空）语义区分
- QoderPoolIdMatcher 口径纪律：歧义一律 --，双向剔除
- 进程管理过硬：drain() EAGAIN/EINTR 修复管道满卡死、watchExitThenEscalate 防 pid 复用、O_APPEND 原子追加
- ConfigStore 损坏备份/NSLock 串行/双写兼容
- 日界处理：campaignDayString 对齐 UTC+8 10:00 服务端刷新点避免空轮询踩风控
- 无凭据泄漏：token 在第三方工具自身文件、网关入站 key 0600 回环专用、日志脱敏 id
