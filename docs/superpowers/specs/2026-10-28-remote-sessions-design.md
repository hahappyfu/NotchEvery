# 远程会话监督：手机 / 手表看会话并就地批准

日期：2026-10-28
状态：待批准（批准前不写产品代码）

## 1. 目标与非目标

### 1.1 目标

在 NotchEvery 里做出这样一件事：Claude Code 因权限请求停下来时，人不坐在 Mac 前，也能在 iPhone（以及 Apple Watch）上看到「哪个会话、要做什么、原文是什么」，并直接批准或拒绝，Claude Code 随即继续。

四件具体能力：

1. **配对**：手机与 Mac 绑定一次，之后自动连上
2. **实时活动**：手机上看到当前有哪些会话在跑、在等、已停
3. **审批**：在手机上批准 / 拒绝，决定回到正在运行的会话
4. **通知**：会话停下来等人时，Mac 与手机各推一条

### 1.2 非目标

- 不做成本估算、不做模型排行、不做额度预测（A5/A6/B3 已分别裁定不做）
- 不替代 Claude Code 的终端交互：手机上只处理「停下来等人」这一刻，不在手机上发起新任务
- 首版不支持跨网（不同 Wi-Fi / 蜂窝）；跨网是 Phase 4
- 不支持多台 Mac
- 不改 `NotchDrop/UsageStore.swift` 的用量口径

### 1.3 与既有产品约束的关系（重要）

用户 2026-10-28 划的线是「只做两个可见面，新开界面 = 加第三个功能」。**本项目经用户明确同意，解除该约束**——审批需要在面板里呈现，这是第三次、也是唯一一次经用户拍板的界面扩张。

## 2. 关键事实（已核实，非推测）

| 事实 | 证据 |
|---|---|
| Claude Code 的 `PermissionRequest` hook 支持 `type: "http"`，**不需要附带可执行文件** | `https://code.claude.com/docs/en/hooks` 的 hook 配置骨架；这是上游开源版卡死的那个坑的解 |
| hook 输出只有 `allow` / `deny`，无 `ask`；**无输出 = 走正常权限流程** | 同上，「Exit code 2 isn't honored for this event」 |
| `timeout` 默认 600 秒，可配任意大；用户现有 Agent HUD 用 86400 | `~/.claude/settings.json` 的 `PermissionRequest` 条目 |
| 超时后输出被丢弃、正常权限流程接管，不会误放行也不会误拒绝 | 同上 |
| HTTP hook 契约：2xx + JSON object ≡ 按 JSON 输出解析；非 2xx / 连接失败 ≡ 非阻塞错误 | 同上 |
| 用户机器上**已装 Agent HUD 0.5.5 并已占用 `PermissionRequest` hook**，订阅 `app.agenthud.remote.1mac.monthly` **不自动续费，2026-11-03 23:32 到期** | `/Applications/Agent HUD.app`、`~/Library/Application Support/Agent HUD/declarations.json` |
| Agent HUD 已配对 1 台设备，最近同步 2026-10-28 09:34 | `~/Library/Application Support/Agent HUD/local-network/clients.json`、`cursor.json` |
| 会话活动可从 `~/.claude/projects/**/*.jsonl` 读取，末行 `timestamp` 为 ISO8601 UTC 带毫秒 | A5 侦察，见 `.scratch/agent-hud-research/00-absorption-tiers.md` §1.4 |
| NotchEvery 当前**没有任何网络代码** | 全仓 `NWListener` / `URLSession` / `listen(` 零命中 |

## 3. 架构

### 3.1 三条独立的链

```
┌─────────────┐   jsonl 文件(只读)    ┌──────────────┐
│ Claude Code │ ───────────────────▶ │              │
│  会话日志    │                      │  NotchEvery  │
└─────────────┘                      │  (Mac 宿主)   │
                                     │              │
┌─────────────┐  POST /hooks/perm    │  ┌────────┐  │   SSE/轮询
│ Claude Code │ ───────────────────▶ │  │LocalLink│ ─┼──────────▶ iPhone
│ 权限请求     │ ◀─────────────────── │  │ Server │  │
└─────────────┘  decision JSON       │  └────────┘  │
                                     │              │
                                     └──────┬───────┘
                                            │ WatchConnectivity
                                         Apple Watch
```

三条链互不依赖，可分别上线：

- **活动链**：读日志 → 会话四态 → 面板 / 手机列表。不需要任何 hook。
- **审批链**：HTTP hook → 本地服务 → 面板 / 手机 → 回传 decision。这是核心。
- **通知链**：本机 `UNUserNotificationCenter`；手机端本地通知，Phase 4 才上 APNs。

### 3.2 为什么用 `http` hook 而不是 `command` hook

上游开源版用 `command` hook，必须随 app 附带一个路径稳定的已签名可执行文件，其安装器（`src/crates/platform/src/hooks/install.rs:38-65`）连自己都装不上——这是开源版审批功能死掉的直接原因。`http` hook 不执行任何东西，只要求 Claude Code 能连上一个本地端口，把这个问题整个消掉。

副作用：不需要 App Sandbox 例外、不需要公证、不需要为 hook 单独做签名。**NotchEvery 保持现在的 ad-hoc 签名即可。**

### 3.3 审批链的完整时序

1. Claude Code 决定要请求权限 → 向 `http://127.0.0.1:<port>/hooks/permission` 发 POST，body 是事件 JSON（含 `session_id`、`tool_name`、`tool_input`、`tool_use_id`、`cwd`、`permission_mode`、`transcript_path`）
2. 服务**不立即响应**，把请求挂起，登记为一条 pending
3. 面板展开到「待批准」页；同时推送给已配对设备
4. 用户在 Mac 面板或手机上点「允许」/「拒绝」
5. 服务返回 `200` + `{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}`
6. Claude Code 继续执行
7. **超时**（默认 24h）或服务不可达 → 无有效响应 → Claude Code 走正常权限流程，终端照常弹窗。**这是安全降级，不是失败。**

幂等要求：每次 pending 由 `tool_use_id` 唯一标识；重复提交同一 `tool_use_id` 只返回首次结果，不重复执行。

### 3.4 安全模型

首版**只监听 `127.0.0.1`**，不对外暴露。理由：审批链是「本机 Claude Code → 本机 NotchEvery」，不经过网络；只有活动链需要给手机看。

手机访问走第二条独立端口，要求：

- 一次性邀请（QR 内含 `{deviceID, endpoint, token, expiresAt}`），5 分钟有效、用后即删、单槽
- 凭证只存 `SHA256(token)`，比对用常量时间
- 凭证存 iOS Keychain（`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`）
- 首版不启用 TLS，仅限同一局域网；**Phase 4 上 TLS 时改用 SPKI pin**（不要学上游 pin 证书 DER——它 365 天静默重签会让所有配对失效）

`/hooks/permission` 这条路径只绑走 loopback，不暴露给手机端口。

### 3.5 与 Agent HUD 的 hook 冲突

`PermissionRequest` 的 `matcher: ""` 是全局匹配，同一事件可以被多个 hook 条目处理，但**两个 app 各自弹自己的窗会互相打架**，且 `onFailure: "block"` 的语义会被叠加。

结论：**本项目启用时，必须卸掉 Agent HUD 的 `PermissionRequest` 条目。** 实施时提供一个「一键接管 / 一键还原」的开关，把原条目备份到 `~/.notchevery/hook-backup.json`，可完整回滚。

注意 Agent HUD 的订阅 2026-11-03 到期，到期后它的 hook 也失效——接管这件事可以自然发生，不必强拆。

## 4. 分阶段

| 阶段 | 内容 | 估时 | 完成标志 |
|---|---|---|---|
| **P0 可行性验证** | 最小 HTTP 服务 + 临时 settings 配 `http` hook，跑通一次 allow 与一次 deny | **1 天** | 终端里一次真实的权限请求被我们返回的决定放行/拒绝 |
| **P1 Mac 侧完整** | 会话四态 + 待批准面板 + 本机通知 + 设置页开关 + hook 接管/还原 | 4–6 天 | 全程在 Mac 上完成一次审批，不需要手机 |
| **P2 iPhone** | 扫码配对、会话列表、审批、本地通知 | 6–8 天 | 手机在另一个房间批准一次真实请求 |
| **P3 Watch** | WatchConnectivity 转发，列表 + 批准 | 3–5 天 | 手表上批准一次 |
| **P4 远程** | 跨网（Tailscale / 中继）、APNs 真推送、TLS + SPKI pin | 5–10 天 | 不在同一 Wi-Fi 也能批准 |

**P0 不过，后面全部作废。** 所以先花一天验证，再谈其余。

合计 **19–30 人日**（约 4–6 周）。

## 5. 会话四态（P1 的核心算法）

沿用 agent-hud 的判定（`src/crates/agents/src/transcript/live.rs:484-527`）：

- 状态：`running` / `waiting` / `idle` / `unverified`
- `QUIET_MS = 120_000`（2 分钟无输出判静默）
- `ABANDONED_MS = 1_800_000`（30 分钟判放弃）
- 优先级：有 pending 审批 → 强制 `waiting`；否则按日志推导
- `unverified` 独立于 `idle`：读不到就显示读不到，不伪装成在线

输入只有一样：会话 `jsonl` 的末行时间戳 + 是否最后一个事件是提问。已在 A5 侦察中确认可得。

## 6. 验收标准

- P0：一条真实 `Bash` 权限请求，由我们返回 `allow` 后在终端执行；由我们返回 `deny` 后被拒绝；超时后终端正常弹窗
- P1：审批面板在 200ms 内出现；决定回传后终端继续；无残留 pending；`tool_use_id` 重复提交不重复执行
- P2：断网重连后手机自动恢复；未配对设备无法读取任何数据；配对码 5 分钟后失效
- P3：手表与手机同时在线时，任一端批准，另一端同步消失
- 全程：NotchEvery 不启动时 Claude Code 行为与未安装时完全一致

## 7. 风险

1. **hook 抢占导致用户的 Claude Code 行为改变**——最严重的风险。缓解：接管前备份、支持一键还原、P0 阶段用临时配置验证不碰生产 settings
2. **面板新增第三个界面**——已获用户同意，但要控制面积，避免把用量面板挤变形
3. **iOS app 的长期维护成本**——每年 iOS 大版本要重编、签名证书要续。这是自建相对于续费的真实代价，用户已知悉
4. **本地端口的权限边界**——loopback 端口同机任何进程都能访问，等同于「同一用户下的进程互信」。首版接受此假设
5. **上游的坑不要照抄**：证书 pin 改为 SPKI、邀请改多槽、`valid_token` 只认 64 位小写十六进制、body 上限 8 KB 对「长回答」不够——这些在 06-remote-pairing.md §七 有完整清单

## 8. 待用户确认的决策

1. **hook 接管方式**：立即卸掉 Agent HUD 的 `PermissionRequest`，还是等它 11-03 到期自然失效后再接管？
2. **P0 是否用临时配置验证**（不改动现有 `~/.claude/settings.json`）？
