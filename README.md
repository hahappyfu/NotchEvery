# qodercn-gateway

一个轻量、仅远程的网关，把 QoderCN Remote API（`gateway.qoder.com.cn`）通过标准的
**OpenAI** 和 **Anthropic** HTTP 接口暴露出来，让 Claude Code、Cline 等任意
OpenAI/Anthropic 兼容客户端可以直接接入 QoderCN 托管的模型（Qwen、Kimi、MiniMax、
GLM、DeepSeek 等）。

该项目是从[lingma-proxy](https://github.com/Lutiancheng1/lingma-proxy)重构而来，去掉了gui和依赖本地环境的ipc模式，并优化了诸多原生工具、图片输入等内容。

## 接口

| 方法 | 路径 | 用途 |
| --- | --- | --- |
| POST | `/v1/chat/completions`、`/api/v1/chat/completions` | OpenAI Chat Completions |
| POST | `/v1/messages` | Anthropic Messages |
| GET  | `/v1/models` | 模型列表 |
| POST | `/v1/images/search` | 图片搜索（网关 `imageSearch`） |
| POST | `/v1/images/generations` | 图片生成（网关 `generateImage`） |
| GET  | `/quota`、`/v1/quota` | 账户额度/用量快照 |
| GET  | `/version` | 构建版本 |
| GET  | `/`、`/health` | 健康检查 / 状态 |

Chat 与 Messages 通过 SSE 流式返回。网关支持原生 function-calling。

## ⚠️ 必须显式指定 `remote_base_url`

上游自动探测（`ResolveBaseURLWithSource`）会命中缓存文件
`~/.config/qodercn-gateway/remote-base-url.json`，实测被带回 `https://lingma.alibabacloud.com`
—— 那是**阿里通义灵码的旧域名**，不是 Qoder 的模型网关。两者差别极大：

| `remote_base_url` | `/v1/models` | 高级模型 |
| --- | --- | --- |
| `https://lingma.alibabacloud.com`（自动探测结果） | 4 个 | 全部回 `Agent quota exceeded` |
| **`https://gateway.qoder.com.cn`（正确）** | **14 个** | **全部可用** |

注意本仓库的 `DefaultBaseURL`（`internal/remote/client.go`）仍是 `lingma.alibabacloud.com`，
与本文开头写的 `gateway.qoder.com.cn` 自相矛盾——**别依赖默认值，配置里钉死**：

```json
{ "remote_base_url": "https://gateway.qoder.com.cn" }
```

## 账号池（多凭据自动轮换）

Qoder 的日限按**账号**计，且无法从 `/quota` 提前看出，只能在调用失败时从错误体判定。
配置一个目录，每个号一份明文 JSON（即 `--export-remote-auth` 的产物格式），撞限即自动换号：

```json
{
  "remote_auth_pool_dir": "~/.qoder-cn/pool",
  "remote_auth_pool": { "max_switches": 3 }
}
```

- **目录 `0700`、文件 `0600`**；成员含明文 `cosy_key` / `access_token`，注意文件保密。
- **热加载**：往目录里加/删号无需重启，但**重扫只在 `Chat()` 路径（`Current()`）按目录 mtime 触发**——
  只查 `/v1/pool/status` 不会驱动重扫。加号后发一发 chat 请求即生效；别以为 status 数字没变就是坏了。
- **不消耗额度的端点不入池**：quota / 模型列表 / 联网搜索 / 图片仍走 `remote_auth_file`，
  池只在 `Chat()` 生效（`internal/remote/credential_pool.go`）。
- **冷却两态**：`active` / `cooled(到下一个本地零点)`。撞真日限
  （`{"code":"110","message":"Billing daily count exceeded"}`）才冷却；429 冷却 15 分钟。
  错误体不含额度关键字的 401/403 **只换号、不冷却**——宁可多撞一次也不误杀好号。
- **恢复探针**：号冷却后默认静默 30 分钟，之后每 30 分钟拿一个极小 Chat 请求探测队首号，
  探通即提前放出。`probe_enabled: false` 可关闭（那样只能等零点自动解冻）。
- **零额度号自动退役**：后台每小时（首次启动后 5s）对每个活跃号查一次 `/quota`，命中
  `total==0 && isQuotaExceeded==true`（试用过期的免费套餐形态）**且查询无错**的号移入 retired 集、
  不进轮换，日志 `[pool] retiring …`。判据保守：任一信号单独成立、或查询报错/超时，一律乐观放行——
  误杀活号的代价远大于多撞一次请求。retired 是内存态不落盘，重启即重新评估。关掉整个池即停用此机制。
- **池耗尽**：用最初那个号再打一次，把它返回的**真实错误原样**冒给客户端，绝不合成；
  同时在响应头 `X-QoderCN-Pool` 和日志里附一行池状态摘要。

### 免费模型会排队，不是额度问题

`Qwen3.8-Flash`（内部 key `qfmodel`）是唯一 `price_factor: 0` 的真免费模型，代价是排在
**全服共享的 p3 低优先级队列**里：

```json
{"isQueued":true,"queueCount":7633,"queueType":"p3","retryAfterSeconds":30,"waitTime":232}
```

这是"忙，重试"而不是额度墙——实测一次重试 6.5 秒就进。网关会按 `retryAfterSeconds`
等待后**用同一个号重试**（最多 3 次），因为队列全局共享，换号毫无意义。
此时**不会**把账号判成冷却。

### 观测

```bash
curl -H "Authorization: Bearer $(head -n1 local.authkeys)" http://127.0.0.1:8096/v1/pool/status
```

返回每个号的脱敏 `user_id`、是否在冷却、冷却原因、何时放出、最近一次探针结果。

每次计费调用还会在日志行打 `acct=<脱敏 user_id>`（与 `/v1/pool/status` 同一个 `MaskAccount`，
两边 token 可直接 grep 对接），用于回溯哪个号当天烧了多少：

```bash
grep "remote usage" logs/gateway_8096.log \
  | awk '{for(i=1;i<=NF;i++){if($i~/^acct=/)a=$i;if($i~/^credits=/){split($i,c,"=");s[a]+=c[2]}}}END{for(k in s)printf "%s %.4f\n",k,s[k]}'
```

注意**不能用凭据的 `Source` 字段归属**：多个号可能从同一个 `.auth/user` 导出、`Source` 完全相同，
按它聚合会把不同号并成一个。

## 构建与运行

本机常驻端口是 **8096**。原并存的 8095 单号实例（上游原版）已于 2026-09-20 退役删除，
本仓库即唯一版本。后续开发新版本时**递增端口**（8097…），不要复用正在承载流量的端口。

```bash
go build -o qodercn-gateway ./cmd/qodercn-gateway
./qodercn-gateway --host 127.0.0.1 --port 8096
```

凭证会自动从本地 QoderCN CLI 的登录缓存读取，也可用 `--remote-auth-file credentials.json`
显式指定。导出可移植的凭证/部署包（用于服务器部署）：

```bash
./qodercn-gateway --export-server-bundle bundle.zip
```

## 配置

支持命令行参数（见 `--help`）、JSON 配置文件（`--config qodercn-gateway.json`，参见
`config.example.json`）、环境变量三种方式——优先级：命令行 > 环境变量 > 配置文件。
常用项：`--remote-auth-file`、`--remote-base-url`、`--remote-proxy-url`、`--model`、
`--auth-keys-file`（入站 API key 白名单，一行一个、`#` 注释；留空 = 开放访问）。
每个入站 key 最长 64 字符，且只允许 `A-Z a-z 0-9 - _ * + =`（避免不同客户端的请求头兼容问题）；
不合规会在启动时直接报错拒绝运行。

可选特性开关（环境变量）：

- `QODERCN_INJECT_MEDIA_TOOLS=1` —— 在服务端以 agentic 循环方式声明并执行网关的
  `web_search` / `ImageSearch` / `TextPolish` 工具（对客户端隐藏）。
- `QODERCN_IMAGE_DEWATERMARK=1` —— 通过不可逆的几何去同步重编码，破坏生成图片中的
  鲁棒水印载荷（有效性未知）。
- `QODERCN_REPLACE_WEB_SEARCH` —— 是否替换 Claude Code 的 hosted web_search（**默认开**）。
  开启时拦截客户端声明的 hosted `web_search`，在网关侧执行，并以 Anthropic 原生
  `server_tool_use` + `web_search_tool_result` 块返回，让 Claude Code 渲染自带的联网搜索 UI；
  设为 `0`/`false`/`no`/`off` 关闭：不拦截，该 hosted 工具被丢弃、模型不联网搜索。

## Docker

```bash
docker build -t qodercn-gateway .
docker run -p 8096:8096 -v "$PWD/credentials.json:/credentials.json:ro" \
  qodercn-gateway --remote-auth-file /credentials.json --port 8096
```

## 目录结构

- `cmd/qodercn-gateway` —— 入口 / 配置装配
- `internal/httpapi` —— OpenAI + Anthropic HTTP 层（含可选的服务端工具）
- `internal/remote` —— QoderCN Remote API 客户端（cosy 签名、SSE、图片、凭证）
  - `credential_pool.go` —— 账号池：成员加载、两态冷却机、挑选顺序（sticky → 过期时间降序）、
    恢复探针调度、状态摘要
- `internal/service` —— 请求编排
- `internal/tooltypes` —— 工具数据类型 + 请求侧抽取器
- `internal/deploy` —— 凭证 / 部署包导出
