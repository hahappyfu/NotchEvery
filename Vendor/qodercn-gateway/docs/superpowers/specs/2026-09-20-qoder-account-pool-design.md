# QoderCN 网关 · 内嵌式多凭据账号池 设计规格

- 日期：2026-09-20
- 状态：已通过 brainstorming 分节评审，待用户终审
- 路径分类：架构级（新子系统 + 改动上游源码）
- 目标版本基线：`VERSION` = 0.2.1

## 1. 目标与非目标

### 目标

QoderCN 的日限按**账号**计（已实测确认：`/quota` 全程返回 200、`used=0`，看不出日限；真撞限时是 Chat 调用返回 403）。当前网关只支持单一凭据文件，换号需要人工 `cp`，且切换的那一发请求必然失败。

本设计要求网关内置一个凭据池：**当 Chat() 拿到额度类失败时，当场换号重试，客户端那一发请求最终成功、对失败无感知。**

### 运行环境与会话安全硬约束（用户显式要求，必须执行）

当前与用户的 Claude 会话正通过本机 `8095` 端口的既有网关进程路由（链路：Claude → cc-switch → 8095 → Qoder）。**8095 的存活是本次对话的生命线**。任何导致 8095 停止、重启、崩溃、端口占用的操作都会**立刻掐断当前会话**。

因此：
1. **完全隔离的开发目录**：在 `/Users/fupingguo/fuhaha_workspace/ali-tools/` 下新建独立目录（建议 `qodercn-gateway-pool/`），与原 `qodercn-gateway/` 物理隔离。
2. **独立 git 版本控制**：新目录就地 `git init`，以当前 0.2.1 基线作为 initial commit，所有开发在独立 git 库中进行。原目录一行不碰。
3. **独立调试端口**：新网关在开发调试期间**绑定 8096 端口**（已核实空闲），绝不碰 8095。调试、测试、启动均针对 8096。
4. **验证成功后的切换**：全部功能验证通过后，由用户自行在本地配置中改端口号切流（或切换进程），AI 绝不主动杀 8095。

### 非目标（明确排除）

- **不做**跨机器/多实例的池状态共享。池是本进程内存状态 + 磁盘上的号文件。
- **不改** `FetchQuota` / `ListModels` / `WebSearch` / `ImageSearch` / `GenerateImage` / `PolishText` / `Warmup` 的凭据获取方式。理由见 §3。
- **不做**额度预测或提前轮换。只在真实撞到失败后才换。
- **不支持**加密形态的池成员（`.auth/user` + machine_id 解密配对）。池成员一律明文 JSON。
- **不承诺**SSE 已经开始吐字之后的失败可以挽救。

### 已知风险（一次性声明，不再重复劝退）

多个账号在同一台机器 / 同一出口 IP 上高频轮换，可能加速触发服务端 IP 维度的风控。本设计不试图规避它；`X-QoderCN-Pool` 与 `/v1/pool/status` 的可观测性是为了一旦发生时能快速定位。附带事实：本机 Clash TUN 已开（`utun1024`, `auto-route: true`），qoder 域名走 DIRECT，因此切代理组可改变出口 IP——这是运维手段，不属于本设计范围。

## 2. 方案选择

采用**方案 1：独立文件承载池逻辑，Chat() 只接一条窄缝**。

| 方案 | 说明 | 结论 |
|---|---|---|
| 1 | 新增 `internal/remote/credential_pool.go`，仅 Chat() 接入 | **采用**：上游 diff 最小且集中，冲突面只有 Chat 函数体一处；池逻辑可单测 |
| 2 | 池状态内嵌 Client struct，7 个调用点各自接池 | 否：diff 散布、跟上游冲突多，而那些端点不消耗额度、无需轮换 |
| 3 | 池做成独立进程，网关失败时通知外部 | 否：等价于外挂式，不符合"内嵌零失败"目标 |

## 3. 边界与改动面

### 新增文件

`internal/remote/credential_pool.go` —— 池的全部职责：目录扫描、成员加载、冷却状态机、轮转挑选、探针调度、状态摘要。对外只暴露给 Chat 使用的一小套 API（§6）。

### 改动的现有文件

| 文件 | 改动 | 规模 |
|---|---|---|
| `internal/remote/credentials.go` | 新增读明文 JSON 成员的 helper，复用现成 `storedCredentialFile` 结构与 `validateCredential` | ~15 行 |
| `internal/remote/client.go` | `Config` 加字段；`Chat()` 包一层有界重试环 | ~40 行 |
| `cmd/qodercn-gateway/main.go` | 配置项接线 | ~10 行 |
| `config.example.json` | 示例字段 | ~5 行 |

不动的部分（刻意约束）：

- `client.go` 中除 `Chat()` 外的 6 处 `LoadCredential(c.cfg.AuthFile)` 全部保持原样。这些端点（quota / model list / web search / image / polish / warmup）不消耗对话额度，无需轮换。
- `internal/deploy/server_bundle.go:64,118` 两处 `LoadCredentialByPolicy` 保持原样。部署快照仍用单号，不影响现有部署流程。
- `LoadCredentialByPolicy` 的 `newest`/`longest` 策略不参与池逻辑（它在 `authFile` 非空时短路返回，本就覆盖不到这个场景）。

### 回退开关

`remote_auth_pool_dir` 留空 → 整套池逻辑（含后台调度器）不启动，代码路径与今天逐字节一致。出问题清空该配置项并重启即可，零残留。

## 4. 配置

```json
{
  "remote_auth_file":      "",
  "remote_auth_pool_dir":  "~/fuhaha_workspace/ali-tools/qodercn-gateway/pool",
  "remote_auth_pool": {
    "max_switches":        3,
    "probe_enabled":       true,
    "probe_quiet_min":     30,
    "probe_interval_min":  30
  }
}
```

| 字段 | 默认 | 语义 |
|---|---|---|
| `remote_auth_pool_dir` | 空 | 池目录。空 = 关闭池，走 `remote_auth_file` 老逻辑 |
| `max_switches` | 3 | 单个请求最多换几个号。0 = 等价于关闭轮换（退回今天行为）。实际生效值 = min(该值, 池大小) |
| `probe_enabled` | true | 探针总开关。false = 只靠零点兜底恢复，其余功能不受影响 |
| `probe_quiet_min` | 30 | 号进入冷却后的静默期，期内不探 |
| `probe_interval_min` | 30 | 静默期后每隔多久一轮探测 |

配置解析沿用现有 config.json + flag + env 三层机制，优先级与现有一致。所有池字段可选，缺失取默认。

## 5. 池成员格式与挑选顺序

### 成员文件

`<pool_dir>/*.json`，每号一份，即 `SaveCredentialFile` 的产物格式：

```json
{
  "source": "...",
  "token_expire_time": "1789...",
  "auth": {
    "cosy_key": "...",
    "encrypt_user_info": "...",
    "user_id": "...",
    "machine_id": "...",
    "access_token": "..."
  }
}
```

权限：目录 `0700`，文件 `0600`（与 `SaveCredentialFile` 现有实现一致）。注意这是明文落盘的 cosy_key / access_token，属已接受的安全权衡。

加载规则：`validateCredential` 不通过的成员**跳过并记一条 warn**，绝不让一个坏文件拖垮整池。

### 身份键

冷却状态以 **`user_id`** 为 key，不以文件名为 key。这样重命名文件或同一号存在多份副本时，不会出现"同一个号复活两次"、把额度算在两个身份上。

同 `user_id` 出现多份时，取 `token_expire_time` 最大的那份（与现有 `CredentialPickLongest` 语义一致）。

### 挑选顺序

每次需要一个可用号时：

1. 过滤掉「已冷却」和「token 已过期」的成员。过期判定复用现成 `IsExpired(cred, 5*time.Minute)`。
2. **sticky 优先**：当前活跃号若仍可用，继续用它。这是刻意的核心决策——日限按号计，无脑轮询会把 N 个号的额度同时磨薄；粘住直到撞墙，每个号才吃得干净。
3. sticky 失效需换号时，按 `token_expire_time` **降序**取下一个未试过的号（先烧快过期的）。

### 热加载

不引入 fsnotify。每次进入 `Chat()` 时按目录 mtime 判断是否变过，变了才重扫。因此往池里丢一个新号文件立即生效，不需要重启 8095 进程（本项目硬约束：网关进程不停机）。

## 6. 对外 API

```go
// Current 返回本轮应使用的凭据。attempt=0 允许返回 sticky 号；
// attempt>0 强制返回一个未在本轮试过的号。全不可用时返回 ErrPoolEmpty。
func (p *CredentialPool) Current(attempt int) (Credential, error)

// Inspect 依据 HTTP 状态码与响应体更新该号状态，返回裁决。
func (p *CredentialPool) Inspect(userID string, status int, body []byte) PoolVerdict

// Summary 渲染一行池状态摘要，用于日志与 X-QoderCN-Pool 头。
func (p *CredentialPool) Summary() string
```

`PoolVerdict` 三值：`VerdictOK` / `VerdictSwitch`（换号）/ `VerdictPropagate`（不换号，原样报错）。

## 7. 失败判据与状态机

每个号只有两态：`active` / `cooled(until, reason)`。不设"疑似""降级"等中间态——状态机越简单越不容易误伤。

判定表（仅在 Chat() 拿到非 2xx 时执行）：

| 观测 | 动作 |
|---|---|
| 2xx | `active`，清零失败计数 |
| 401/403 + body 命中**额度关键字** | → `cooled(下一个本地零点, "daily_limit")` |
| 401/403 + body 命中**鉴权关键字** | → `cooled(下一个本地零点, "auth_invalid")`，日志额外提示"该号需重新登录" |
| 401/403 + 两类关键字均不命中 | 只换号、**不冷却**；原样记一条 warn 含状态码 + 脱敏 body 摘要 |
| 429 | → `cooled(now+15min, "rate_limited")`（短冷却，不到零点） |
| 其余 4xx（400/404/422…） | **不换号、不冷却**，原样报错——这类失败换号也不会变好 |
| 5xx / 网络错误 / ctx 取消 | **完全不碰池状态**，按原逻辑报错 |

最后一行的原则：上游抖动绝不能被记成某个号的过错。

### 关键字表

这是本设计唯一的经验性成分，按以下方式诚实处理：

- 初版额度类：`exceed` / `quota` / `limit` / `每日` / `额度` / `上限`
- 初版鉴权类：`invalid token` / `unauthorized` / `未登录` / `expire`
- 表可在配置中追加覆盖，不需改代码
- 每次命中冷却都完整落一行日志（状态码 + 脱敏 body），便于首次真撞日限时校准规则
- **默认保守：没命中关键字就绝不冷却**——宁可多撞一次也不误杀好号

### SSE 中途失败

`parseSSEPayload` 报出的 `remote sse status 403` 一类错误发生在流已开始之后。**不换号、不重试**，直接冒给客户端。半截响应无法回退，这是硬边界。

## 8. 恢复探针

### 为什么需要独立调度器

号进入冷却后，若无流量则永远不会被再次触达，也就永远放不出来。所以恢复探测不能惰性挂在 Chat() 上，需要一个 goroutine。这是全设计唯一新增的常驻后台组件，封闭在 `credential_pool.go` 内部，对外零暴露。

### 节奏

- 号进入冷却后前 `probe_quiet_min`(30) 分钟内不探
- 之后每 `probe_interval_min`(30) 分钟一轮；**每轮只探队首一个**待恢复号（最早该放出的那个）
- 探到可用 → 立即置 `active`、打日志、本轮结束（不再探其余）
- 探到仍是额度类失败 → 保持冷却，下一轮再来
- 池中无任何冷却号时调度器完全静默，不发一个包

### 探针形态

极小 Chat 请求（prompt `"hi"`、`max_tokens: 1`），走与 `Chat()` 完全相同的签名 / headers 路径，只是**绕过池、直接指定要测的那个号**。

不能用 `/quota` 或 `ListModels` 做探针：二者只验鉴权、看不出日限（§1 已实测证实），拿它们探测会误判"已恢复"，随后真实流量立刻撞墙。

### 安全阀

- 同一时刻最多一个探针在飞（互斥），不与真实流量并发抢出口
- 探针错误**绝不冒给任何客户端**，只更新池状态
- 探针独立短超时 20s，挂住不影响下一轮
- `probe_enabled: false` 可整体关闭

### 零点兜底

`cooled.until` 存的是下一个本地零点。`Current()` 取号时先看时间戳，过期即自动回到 `active`——**不需要定时器去"解冷却"**。探针只是在零点之前提供一条提前回来的路。

## 9. Chat() 重试环

`Chat()` 内唯一的上游逻辑改动：

```go
for attempt := 0; attempt <= maxSwitches; attempt++ {
    cred, err := pool.Current(attempt)
    if err != nil { break }                    // 池空 → 走耗尽分支
    headers, err := c.headers(cred, chatPath, body)   // 必须整体重算
    req, err := http.NewRequestWithContext(ctx, ...)  // 必须重建 request
    resp, err := c.client.Do(req)
    verdict := pool.Inspect(cred.UserID, resp.StatusCode, body)
    switch verdict {
    case VerdictOK:         /* 走现有 SSE 解析并返回 */
    case VerdictSwitch:     continue
    case VerdictPropagate:  break
    }
}
```

三条硬约束：

1. **每轮重建 request**。body 字符串可复用（requestID 保持不变，服务端可去重），但 `req.Body` 已被消费，必须新建 reader。这是最容易写错的一点，测试专门覆盖。
2. **headers 必须随凭据整体重算**。`c.headers()` 内含 `cosy_key`、`machine_id`，且 `clientIP(machineID)` 由 machine_id 派生——换号只换其中一部分会产生签名与身份不一致的请求。
3. **本轮已失败的号进 in-flight 排除集**，不重复尝试。

## 10. 池耗尽时的行为

采用"保真 + 附带摘要"：

- 用**最初那个活跃号**再打一次，把它的真实状态码与响应体**逐字**冒给客户端。不合成、不改写，Claude Code 侧看到的就是真话。
- 在该 HTTP 响应上追加一行头部：
  `X-QoderCN-Pool: accounts=4 active=0 cooled=4 earliest_reset=2026-09-21T00:00+08:00 probe=on`
- 同步落一行同内容日志，便于事后 grep。
- 诚实标注局限：Anthropic 兼容层若不透传自定义响应头，该摘要可能只对直连 OpenAI 端点的客户端可见。因此**以日志为准，响应头当加分项，不作承诺**。

## 11. 可观测性

新增只读端点 `GET /v1/pool/status`，受现有 `auth_keys_file` 入站白名单保护（注意：`authKeys` 是入站白名单，与本设计的出站凭据池无关，两者不可混淆）。

返回每个号的脱敏 `user_id`（复用现成 `maskIdentifier`）、状态、冷却原因、`until` 时间、最近一次探针结果与结论。日常排查以此端点为主，不翻日志。

## 12. 测试策略

沿用仓库既有做法（`go test -race ./...`），池逻辑不依赖真实网关进程：

| 层级 | 覆盖 |
|---|---|
| 单元 | 成员加载（坏文件跳过、同 user_id 去重取最长过期）、关键字判定表逐条、状态机两态迁移、`until` 零点计算与自动解冻 |
| 单元 | 挑选顺序：sticky 保持、撞墙后按 expire 降序、过期成员被过滤 |
| 集成（`httptest`） | 403→换号→第二次 200→客户端只见成功；验证第二轮 headers 确实变了（签名/machine_id/clientIP 三者一致跟随） |
| 集成 | 重试环不重复试同号；`max_switches=0` 时行为与今天完全一致 |
| 集成 | 池耗尽时透传首个号的真实状态码与原文 |
| 集成 | 429 短冷却 vs 额度类长冷却，二者 `until` 不同 |
| 集成 | 5xx / ctx 取消不改动任何池状态 |
| 单元（假时钟） | 探针静默期、每轮只探队首、命中即停、`probe_enabled=false` 时零发包 |
| 回归 | `pool_dir` 为空时代码路径与今天一致（§3 回退承诺） |

## 13. 实现前置条件

### 13.1 独立开发环境建立（硬约束，先于代码实现）

为避免开发调试打断正在承载本会话的 8095 网关：

1. **新工程目录**：`/Users/fupingguo/fuhaha_workspace/ali-tools/qodercn-gateway-pool/`，从 `qodercn-gateway/` 完整复制基线代码。
2. **初始化独立 git**：新目录下执行 `git init` + 提交 baseline tag `v0.2.1-upstream`，所有池功能开发在这个独立仓库上推进，改动清晰可追溯。
3. **独立端口与配置**：新工程的 `local.json` 显式绑定 **8096** 端口，日志写入新目录下的 `logs/`，与 8095 实例完全解耦。
4. **共享资源写入防护**：原工程的 `remote-base-url.json` 缓存在 `~/.config/qodercn-gateway/`，该文件仅存成功的 base_url 字符串，读写幂等无害；其余资源全部自包含在新目录下。

### 13.2 待实测校准项（不阻塞实现）

额度/鉴权关键字表（§7）是按语义推定的初版，**尚无真实 403 响应体样本**——今天网关日志里只落了成功行，没留下失败原文。实现按以下方式处理即安全：命中才冷却、未命中绝不冷却、每次冷却都落完整脱敏日志。首次真撞日限时据日志校准关键字即可，无需改结构。

## 14. 验收标准（"做完"长什么样）

1. `go build ./... && go vet ./... && go test -race ./...` 全绿。
2. 池中放 ≥2 个号，人为让第一个号返回额度类 403，客户端发起一发请求：**收到完整成功响应，无 403 泄漏**；日志显示发生了换号及换到哪个号。
3. `GET /v1/pool/status` 能看出哪个号在冷却、原因、何时放出。
4. 往池目录新增一个号文件，不重启进程，下一发请求即可用到它。
5. 清空 `remote_auth_pool_dir` 并重启，行为与改动前一致。
6. 所有池改动集中在 `credential_pool.go` + §3 表格所列的四文件；`git diff`（若建库）不含其他上游文件。
