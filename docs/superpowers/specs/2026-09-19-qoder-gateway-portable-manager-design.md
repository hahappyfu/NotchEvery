# Qoder 反代移植（管理器模式）设计规格

日期：2026-09-19 · 状态：已获用户批准方向，待规格审查
决策记录：移植深度 = 管理器模式；二进制来源 = 源码入仓 + 构建时编译；UI = 独立 Qoder 卡片；进程接管 = 完全由 App 管；测试端口 = 8096（可配置）；凭证 = 自动读本地 QoderCN CLI 缓存。

## 1. 目标与非目标

**目标**：把 `ali-tools/qodercn-gateway`（Go，~8300 行，QoderCN → OpenAI/Anthropic 兼容反代）以"管理器模式"移植进 NotchEvery——参照 Antigravity-Manager 的思路：NotchEvery 内置网关二进制、负责其完整生命周期（启停/保活/状态监控），并在刘海第 1/2 页以独立卡片展示额度与今日流量。

**非目标**：
- 不用 Swift 重写 Go 网关（两步走路线的后续阶段，本期不做）
- 不抽象统一 ProxyProvider 插件架构（等第三个反代出现再重构，YAGNI）
- 不做远程下载二进制兜底、不做 CI 集成
- 不动现有 Antigravity 卡片/Store 的代码路径

## 2. 仓库结构

```
NotchEvery/
├── Vendor/qodercn-gateway/       # Go 源码 vendor 入仓（上游 git subtree pull 同步）
├── scripts/build-qoder-gateway.sh # 只编二进制，不签名不拷贝
└── NotchDrop/
    ├── QoderGatewayManager.swift  # 进程生命周期 + 健康监控
    ├── QoderStore.swift           # /quota 轮询 + 增量日志聚合
    └── QoderProxyCardView.swift   # 第 1/2 页卡片
```

### 2.1 上游同步（隐患 5）

- 首次用 `git subtree add --prefix=Vendor/qodercn-gateway <ali-tools 仓库 URL> main --squash` 引入（若 ali-tools 整体仓库不便共享，退化为一次性 copy + 记录基线 commit）。
- 此后上游修 bug/改协议：`git subtree pull --prefix=Vendor/qodercn-gateway`，一次命令完成对照合并，无 submodule 的心智负担。
- **选 subtree 而非 submodule 的理由**：submodule 会依赖 ali-tools 本地仓库的 push 状态、checkout 需 `--recursive`，拖累构建与协作者；subtree 对 Xcode 构建完全透明。
- Go 侧源码原则上零修改；确需补丁（如默认值）单独 commit 并加注释标记，subtree pull 时可追溯。

### 2.2 构建集成（隐患 2：签名交给 Xcode）

- `scripts/build-qoder-gateway.sh`：仅执行 `go build -o "$DERIVED_BUILD_DIR/qodercn-gateway" ./cmd/qodercn-gateway`（工作目录 `Vendor/qodercn-gateway`）。找不到 `go` 时报错退出并提示 `brew install go`。**脚本内不出现任何证书名、codesign、cp 到 bundle 的操作。**
- Xcode 工程改动：
  1. Pre-build shell script phase「Build Qoder Gateway」调用上述脚本，产物落 `BUILT_PRODUCTS_DIR/qodercn-gateway`。
  2. 「Copy Files」phase（dstSubspecSpec = `MACOSX_CODE_DIRECTORY`，即 Contents/MacOS/）把二进制拷入 bundle。
  3. Xcode 打包尾部会对整个 .app 重签（含 Contents/MacOS 下 helper），hardened runtime entitlements 随主 target `CODE_SIGN_ENTITLEMENTS` 自动应用——换机器/换证书零改动。
- 验收时必须实测：构建产物里 `codesign --verify --deep .app` 通过，且 spawn 出的子进程能正常起服务（若 Xcode 版本行为导致 helper 未被重签，回退方案：在 Copy Files 后追加一个 `codesign --force --sign - --options runtime`（ad-hoc）phase——ad-hoc 不含机器身份，不算硬编码证书。此回退仅在实测需要时启用）。

## 3. QoderGatewayManager（P2 中枢）

### 3.1 配置归 App 所有

目录：`~/Library/Application Support/NotchEvery/qoder-gateway/`
- `gateway.json`：`{ "host": "127.0.0.1", "port": 8096, "auth_keys_file": ".../authkeys", ... }` —— **端口是配置项不是常量**（隐患 4）。首启写默认 8096；设置页暴露该字段编辑；将来扶正为 8095 改配置重启即可无缝接管。
- `authkeys`：首启自动生成随机入站 key（64 字符内、符合网关字符集约束）。
- `gateway.log` / `gateway.out.log`：spawn 进程的 stdout/stderr 重定向目标，滚动截断（超 10 MB 保留后半）。
- 上游凭证：不写 `remote_auth_file`，由二进制自读 `~/.qoder-cli` 登录缓存（已确认决策）。

### 3.2 生命周期与防孤儿（隐患 1）

三层防线：

1. **同生共死通道**：manager 以 pipe 作为子进程 stdin，spawn 前设 `SIGPIPE = SIG_IGN`（Go 侧默认亦忽略）。主 App 终止（含崩溃、kill -9）→ 管道写端关闭 → 网关读 stdin 得到 EOF → **自行退出**。为此给 Vendor 的 `cmd/qodercn-gateway/main.go` 加约 15 行 stdin-EOF 监听 goroutine（唯一的 Go 侧补丁，带 `// notchevery-patch:` 注释标记）。
2. **启动前清扫**：App 每次启动，manager 初始化时探测配置端口：若被占用，用 `lsof -nP -iTCP:<port> -sTCP:LISTEN -t` 找 PID，校验可执行文件路径 == bundle 内网关路径才 kill（先 SIGTERM 后 SIGKILL），绝不杀不相干进程（不会误伤你手跑的 8095 实例：端口不同 + 路径不符双重排除）。扫不掉则报"端口被占用"状态。
3. **正常退出**：App terminate → manager 主动 SIGTERM。

### 3.3 状态机

`stopped → starting → running → stopping → stopped`；`running → crashed`（进程意外退出）。
- 健康判定 = Process 存活 && TCP 127.0.0.1:port 可达（启动后 10 s 内轮询确认）。
- crashed 提供手动"重新启动"；不自动拉起（避免上游凭证失效导致的无限重启循环），连续失败 3 次后按钮旁提示检查登录态。
- 错误文案单行化：Go 二进制缺失 / 端口占用 / spawn 失败 / 健康超时 / 进程崩溃。

## 4. QoderStore（P3 数据）

### 4.1 额度

`GET http://127.0.0.1:<port>/quota`，Header `Authorization: Bearer <authkeys 首个 key>`（实测返回：`user_type/unit/total/used/remaining/percentage/is_exceeded/reset_at_ms`）。15 s 定时器 + 随 App 激活刷新；解码失败静默保留上次值并标 stale。

### 4.2 今日流量：增量日志解析（隐患 3）

- 维护 `(offset, inode)`；每 tick `seek(offset)` 只读新增字节，按行匹配契约：
  `remote usage model=<m> in=<i> out=<o> cached=<c> reasoning=<r> total=<t> credits=<x>`
- 内存聚合器累计：今日请求数、in/out/cached tokens、credits 消耗、缓存命中率（分母口径沿用 `b956c9d` 修正后的 cache-rate 算法）。
- **日界处理**：每条命中行用日志时间戳（行首 `YYYY-MM-DD HH:MM:SS`）归属自然日；检测到新的一天 → 清零重计（旧值归档为"昨日"供 footer 对比）。跨午夜不重扫全文件。
- 文件被轮转（inode 变化或长度 < offset）→ 重置 offset=0 全量重读当日部分。
- 解析器纯函数化（`[String] -> UsageDelta`），golden 样例单测。

## 5. UI（P4 界面）

- `QoderProxyCardView`：360 pt 三宫格，严格复用 `AntigravityProxyCardView` 的 `studioCard` 范式——指标位：今日请求(次) / 今日消耗(credits) / 剩余额度(credits)；footer：左"额度重置 <日期>"、右运行状态点 + 最近调用时间。header 状态点兼启停菜单（启动/停止/重新加载配置）。
- 挂载：第 1/2 页与 Antigravity 卡同区并列（OverviewPageView 装配处按现有条件渲染模式接入）；设置页新增开关"显示 Qoder 反代卡片" + 端口/authkeys 只读展示 + 打开日志目录按钮。
- 视觉验收流程不变：构建重启后用户真机过目再提交。

## 6. 测试

| 层 | 内容 |
|---|---|
| 单测（进 CI 即 XCTest） | 日志行解析 golden、日界清零、inode 轮转重置、gateway.json 生成与端口覆盖、quota JSON 解码、状态机转换（注入假时钟/假探针） |
| 集成冒烟（手动，写进计划验收项） | 构建产物 codesign verify → App 起 8096 → curl /health /quota → kill -9 主 App → 确认网关自尽、端口释放 → 重启 App → 清扫+重拉成功 |
| 回归 | 8095 手跑实例全程不受影响（不同端口 + 清扫路径校验） |

## 7. 交付节奏

P1 源码就位+构建打包 → P2 生命周期中枢 → P3 数据链路 → P4 卡片上线 → P5 文档与端口切换演练。每步独立可用、独立提交，节奏已获用户确认。

## 8. 已知风险

- Xcode 对 Contents/MacOS helper 的重签行为需 P1 实测（回退方案见 §2.2）。
- stdin-EOF 补丁依赖 Go 侧不改 main.go 结构；subtree pull 冲突时该补丁需人工重放（文件小，风险可控）。
- `/quota` 上游偶发慢（15 s 超时），UI 需容忍额度区 stale 标记。
