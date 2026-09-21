# 会话总结 — 2026-09-19 深夜（CC Switch 核查 + 免费机制取证 + NotchEvery 集成立项）

> 本文档是 `HANDOFF-2026-09-19.md` 的增量取证与修正。**冲突处以本文为准**；HANDOFF 中已标注【回填】的条目同步更新过。

## 一、本次做了三件事

1. **待办 1 完成**：CC Switch provider 查重 → 无重复，但发现 Desktop 槽配置不完整（未处理，见遗留）。
2. **限免机制彻底查清**：模型元数据 + 上游 usage 字段 + 日志三方交叉验证，"免费"的确切含义有了定论（修正了此前多处不准确的说法，见第三节）。
3. **NotchEvery 集成立项**：进入 superpowers-flow 头脑风暴（架构级路径），源码内嵌方向已确认，卡在升级策略选型（见第四节）。

## 二、CC Switch 查证结果（sqlite 只读查询）

| id | app_type | name | is_current | 状态 |
|---|---|---|---|---|
| `qoder-cn-free` | claude（CLI） | Qoder 限免 (Qwen3.8-Flash) | 0 | ✅ 完整：BASE_URL+key+五个模型 pin 全 |
| `284f8e2c-…` | claude-desktop | Qoder 限免 | 1 | ⚠️ 只有 BASE_URL+key，**没 pin 模型名** |

- **不是重复条目**——是两个 app 通道各一条，HANDOFF 担心的"手动配产生重复"没有发生。
- 两条的入站 token 与 `local.authkeys` 精确匹配 ✓；带 key 请求 `/v1/models` 返回 200 ✓。
- **隐患**：Desktop 那条（当前激活）没设 `ANTHROPIC_MODEL` 等五项。按映射规则未知名原样透传 → Desktop 默认发的 `claude-*` 模型名去向不可控。**建议补齐五个 pin 后再用**（改前先备份 db）。

## 三、限免机制定论（本次最重要的一组事实）

### 3.1 "免费"的准确边界

- **服务端目录元数据（`/v1/models` 直读上游）**：`Qwen3.8-Flash` = `is_free: true, price_factor: 0, original_price_factor: 0.1`。同目录其他模型 price_factor 为 0.5/0.2/0.04（错峰折扣）。**免费是账号级、服务端结算的，与从哪个客户端进来无关**——反代不改变计费属性。
- **但"免费"≠"零痕迹"**：上游 SSE 响应的 usage 对象带 `credits` / `original_credits` / `billable` 字段（client.go:979 解析，service.go:428 转述日志）——**每次调用服务端都记一笔影子账**。今日实测：56 次调用合计 34.66 credits（缓存命中 ~0.21–0.29/次，冷启动 cached=0 时 ~2.4–2.6/次），而 `/quota` 的 300 池 used 仍 = 0。
- **解读（推断，可证伪）**：price_factor=0 只免 300 池落账，pre-discount 记账全程在服务端可见。预测：限免结束（price_factor 恢复 0.1）当天，`/quota` used 开始以同量级跳动。
- **时效性**：`is_new: true` + 原价被降为 0 → 属限时运营策略，随时可能恢复收费（目录里大量"错峰折扣"promotion 即先例）。

### 3.2 思考等级链路（顺带查清的机制）

- Flash 目录声明三道：`thinking_config.enabled.efforts = low / medium(默认) / xhigh`。
- 网关翻译（client.go:1056 `buildGenerationParameters`）：OpenAI `reasoning_effort` 原样小写透传（支持 none/low/medium/high/xhigh/max，超出 OpenAI 枚举）；Anthropic 侧 `resolveAnthropicEffort`（server.go:1668）优先级 = thinking block 显式 effort > 顶层/output_config.effort > budget_tokens 折算。最终落成上游参数 `{enable_thinking, reasoning_effort}`。
- 双通道生效：参数之外还按档位注入 system hint（service.go:704，low→"Think briefly"，high→"Take extra time"）。
- 多轮续思：上一轮思考以 `reasoning_content` 回填（service.go:52）。
- **当前实际状态**：LaunchAgent 的 `QODERCN_DISABLE_THINKING=1` 一刀切 → 所有经 8095 的请求被强制 `reasoning_effort=none`（日志恒 `reasoning=0`），**三道一档都没用上**。解除需重启 LaunchAgent（换凭据式的不停机方式不适用，env 变更必须重启进程）。

### 3.3 流量归属澄清（防误解）

- 本 Claude Desktop 会话 env 实测 `ANTHROPIC_BASE_URL=127.0.0.1:15721/claude-desktop`（CC Switch 代理 → Anthropic Claude），**不走 8095**。`CLAUDE_CODE_EFFORT_LEVEL=max` 是发给 Anthropic 通道的。
- 今晚打到 8095 的 qfmodel 流量来自**另一个会话**（用户自己配置的 CC/Codex 等）。两笔账不要混。

### 3.4 与 Antigravity 白嫖的本质区别

Antigravity/Gemini CLI = 官方 OAuth free tier，正门、无风险；Qoder 这套 = 私有协议 + cosy 签名 + 伪装 UA，窗户、违反 ToC、风控升级随时断线。结果相似，机制完全不同。

## 四、NotchEvery 集成（brainstorming 进行中，未实现任何代码）

- **路径分类：架构级**（8300 行 Go 服务并入 SwiftUI App，改变部署形态）。
- **已定**：源码内嵌（用户原话类比"切接插件"——切 provider + 插组件），排除纯进程托管(A)和 Swift 重写(C)。
- **未决**：上游升级策略 —— A 快照拷入（推荐）/ B git submodule / C 完全分叉。定了之后流程 = 方案对比 → 分节设计 → 规格文档 → writing-plans。
- **硬约束不变**：合并期间现有 8095 独立进程不停（正在承载流量）。
- NotchEvery 现状备查：SwiftUI 工程（`NotchDrop/`），已有 `Process()` 外调先例（Language.swift:81 等），无 Go 嵌入机制；其"本地反代看板"只读 cc-switch SQLite 展示，不管理网关进程。

## 五、对 HANDOFF 前文的修正清单

| HANDOFF 原表述 | 修正后（本次证据） |
|---|---|
| "限免模型疑似不计入该池（推断）" | 不计入 300 池已证实，但存在逐请求影子记账（credits/original_credits/billable），并非无账可查 |
| "跑了近十次调用后 used 仍为 0" | 今日本口径已 56 次调用、影子记账 34.66，used 依然 0 |
| "待办 2：可能存在重复 provider" | 已查证：无重复，是 claude / claude-desktop 两个通道各一条；真正的问题是 Desktop 条缺模型 pin |
| "模型名未知名原样透传，去向不可控" | 仍然成立，且正是 Desktop 激活条目的现行风险 |

## 六、遗留待办（下次抓手，按优先级）

1. ~~补 Desktop provider 的五个模型 pin~~ → **【09-20 更正】不需要**。模型映射在 `providers.meta` 的 `claudeDesktopModelRoutes`（claude-haiku-4-5 / sonnet-5 / opus-5 / fable-5 → Qwen3.8-Flash，`apiFormat: anthropic`，`claudeDesktopMode: proxy`），路由本就完整；cc-switch 日志确认改写生效（`model=Qwen3.8-Flash`）。原判断只看 `settings_config` 得出，是错的。
2. **决定思考锁死去留**：去掉 `QODERCN_DISABLE_THINKING=1` 则档位可达 low/medium/xhigh，代价是延迟↑；保留则维持现状。改动需重启 LaunchAgent（有秒级中断窗口）。
3. **回答集成选型 A/B/C**，继续 NotchEvery brainstorming → 规格 → 计划 → 实现。
4. **定期回看 `/quota`**：验证"影子记账何时落成真实扣费"的预测（限免结束信号）。
5. ~~本会话走 Claude 通道非 Flash~~ → **【09-20 更正】本会话走的就是 cc-switch → 8095 → Qoder**（env `ANTHROPIC_BASE_URL=127.0.0.1:15721/claude-desktop`，而该槽当前 provider 就是 Qoder 限免）。所以今天你和我对话本身就在消耗 Qoder 额度——这也是"报错出现在聊天界面"的原因。

---

# 七、09-20 白天续查：限流真相、网络纠正、账号切换

## 7.1 真正的闸门是「账号日限」，不是 credits 池

| 账号 | 触发点 | 结果 |
|---|---|---|
| `nick2700343610`（原号） | 09-19 夜 821 次调用 | 09-20 官方 CLI 明确回：`You've reached your daily usage limit for Chat. Come back tomorrow` |
| `aliyun3868315277` | 09-20 上午 129 次 | 网关 403，官方 CLI 卡死 |

**全程 `/quota` 都是 200、`used=0`**——额度池状态与限流完全无关，看它判断不了能不能用。**唯一可靠的判据是官方 CLI 的原话**（它会给明确文案）。

## 7.2 【重要纠正】不是梯子的问题，qoder 走直连

曾观察到"出口 IP 是德国 185.119.19.105"并推断是 VPN 触发风控，进而提议给 Clash 加 `DOMAIN-SUFFIX,qoder.com.cn,DIRECT` 覆写规则。**这个推断是错的，规则也不需要加。**

用 Clash 控制器（unix socket `--unix-socket /tmp/verge/verge-mihomo.sock`，secret 见 `clash-verge.yaml`）查 `/connections` 实测：

```
gateway.qoder.com.cn  →  47.97.199.105 (阿里云杭州)  chains=['DIRECT']
openapi.qoder.com.cn  →  118.31.4.192                chains=['DIRECT']
api.qoder.com.cn      →  47.104.160.223              chains=['DIRECT']
qoder.cn              →  47.97.199.105               chains=['DIRECT']
qoder.com             →  139.95.4.188                chains=['DIRECT']
```

qoder 全部命中 `GEOIP,CN,DIRECT`，**本就走中国直连**。对比：`api.anthropic.com` → 🇮🇹Milan，`googleapis.com` → 🇩🇪Frankfurt。

**方法论教训**：不要拿 `curl ipinfo.io` 的出口 IP 去推断某个具体域名的路由——ipinfo 被代理而 qoder 没有。要看就走 Clash 的 `/connections` 看 `chains`。

## 7.3 账号类型差异（新号更便宜大碗）

新号 `personal_standard`：`total=0 / remaining=0 / is_exceeded=true / reset_at=253402214400000`（9999 年哨兵值，即不重置），**但 Flash 照样 200 可用**。再次印证 7.1 节机制：`price_factor=0` + 响应 `billable:false`，不吃额度池。注意此号 **credits 为 0**，非 Flash 模型（price_factor≠0）会直接失败。

## 7.4 账号切换流程（已脚本化）

**核心事实：网关 `LoadCredential()` 每请求重读 `~/.qoder-cn/.auth/user`、无缓存 → 换文件即生效，不用重启、不用重新登录。**

```bash
./switch-account.sh          # 菜单选号 → 自动备份当前号 → 切换 → 探针实测
./switch-account.sh --list   # 只列候选，不改动任何文件
```

- 位置：`ali-tools/switch-account.sh`（不放进上游源码副本，保持其一行未改）
- 备份账本：`~/.qoder-cn/.auth/user.bak-*`；切换前的当前号会自动存成 `user.bak-<时间戳>`
- 探针判定：`200 ✅` / `403 ❌`（日限或 token 已过期，两者都表现为 403）/ 其他 `⚠️` 附原始报文
- 限制：备份名只有时间戳（`.auth/user` 是加密容器，读不出账号名），可手动改名便于辨认；**新账号必须 `qoderclicn login`，脚本不代劳**
- 已知坑：macOS 自带 bash 3.2 无 `mapfile`，脚本按 3.2 语法写；`set -e` 下勿用 `[[ cond ]] && cmd` 作为末句（会连带退出，脚本已改 `if`）

## 7.5 降频才是治本（当前配置有隐患）

昨晚峰值 **349 次/小时**（≈每 10 秒一次），这是打爆日限的直接原因。`QODERCN_GATEWAY_MAX_CONCURRENT=2` 只管并发、管不住总频次。建议：
1. 降到 **1**（plist 改环境变量，需重启 LaunchAgent，有秒级中断）
2. 压 agent 上下文——单次 100K+ tokens 是主要压力来源
3. 别把 Qoder 锁死为主通道，保留 cc-switch 多 provider 兜底（09-20 上午正是靠 fallback 到百炼 DeepSeek 才没停工）

## 7.6 09-20 时间线（供次日判断恢复情况）

| 时间 | 事件 |
|---|---|
| 09:06 | 换到 aliyun3868315277，网关恢复 |
| 09:11–09:14 | 高峰 42 次/4 分钟 |
| 09:15–09:19 | 网关开始 403，官方 CLI 仍正常 |
| 09:22–09:39 | 恢复，成功与 403 交错 |
| 09:40–09:57 | 以 403 为主，零星成功 |
| 09:57 后 | 网关持续 403；官方 CLI 10:00 起卡死 |
| 11:20–11:31 | 换回原号 → 403；CLI 明确报日限 |
| 14:11 | 换新号（personal_standard）→ 恢复，探针 200 |
