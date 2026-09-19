# Qoder 反代移植（管理器模式）实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 subagent-driven-development（推荐）或 executing-plans 逐任务实现此计划。步骤使用复选框（`[ ]`）语法来跟踪进度。

**目标：** 把 qodercn-gateway（Go 反代）以"源码入仓 + App 全托管生命周期 + 独立卡片展示"的方式移植进 NotchEvery。

**架构：** Go 源码 vendor 进 `Vendor/qodercn-gateway/`，Xcode pre-build 脚本编译、Copy Files 拷入 bundle；Swift 侧新增 `QoderGatewayManager`（启停/防孤儿/状态机）、`QoderStore`（/quota 轮询 + 增量日志聚合）、`QoderProxyCardView`（第 1/2 页）。与 Antigravity 链路零耦合。

**技术栈：** Swift/SwiftUI/XCTest、Go 1.22+、git subtree、Xcode pbxproj 手工编辑。

**规格：** `docs/superpowers/specs/2026-09-19-qoder-gateway-portable-manager-design.md`

## 全局约束

- 测试期端口默认 **8096**，且必须是配置项（`gateway.json` 的 `port`），逻辑代码禁止硬编码端口常量。
- 构建脚本内**不出现**证书名 / codesign / cp 进 bundle；签名交给 Xcode 打包流水线（回退方案见规格 §2.2，仅实测需要时启用）。
- Go 源码零修改为默认；唯一允许补丁 = stdin-EOF 自尽监听（约 15 行，`// notchevery-patch:` 标记，单独 commit）。
- 进程清扫只杀「可执行路径 == bundle 内网关路径」的占用进程，绝不误伤外部实例。
- 数据目录：`~/Library/Application Support/NotchEvery/qoder-gateway/`。
- 日志契约行格式：`remote usage model=<m> in=<i> out=<o> cached=<c> reasoning=<r> total=<t> credits=<x>`，行首时间戳 `YYYY-MM-DD HH:MM:SS`。
- UI 改动完成后构建重启、请用户真机过目再提交（项目记忆规则）。
- commit message 结尾附 `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>`。

---

## 文件结构

| 文件 | 职责 |
|---|---|
| `Vendor/qodercn-gateway/**` | Go 源码（subtree） |
| `scripts/build-qoder-gateway.sh` | 只编二进制到 `$BUILT_PRODUCTS_DIR` |
| `NotchDrop.xcodeproj/project.pbxproj` | 新增 2 个 build phase |
| `NotchDrop/QoderGatewayConfig.swift` | 目录布局 / gateway.json / authkeys 生成（纯函数） |
| `NotchDrop/QoderLogParser.swift` | 增量读取 + 行解析 + 日界聚合（纯函数，无 IO 依赖注入 FileHandle） |
| `NotchDrop/QoderGatewayManager.swift` | 状态机 + spawn/kill + 清扫 + 健康探测 |
| `NotchDrop/QoderStore.swift` | /quota 轮询 + 组合 parser 发布今日统计 |
| `NotchDrop/QoderProxyCardView.swift` | 360pt 三宫格卡片 |
| `NotchDrop/OverviewPageView.swift`（及第二页装配处） | 挂卡 |
| `Tests/QoderGatewayConfigTests.swift` 等 | 各模块单测 |

---

### 任务 1（P1）：源码入仓 + 构建集成

**文件：**
- 创建：`Vendor/qodercn-gateway/`（subtree）、`scripts/build-qoder-gateway.sh`
- 修改：`NotchDrop.xcodeproj/project.pbxproj`

- [ ] **1.1 引入 subtree。** ali-tools 若无远端 URL，先在该目录建裸仓或直接降级 1.2。有 URL 时：

```bash
git subtree add --prefix=Vendor/qodercn-gateway <ali-tools仓库URL> main --squash
```

无远端可用时的等价操作（记录基线，后续同步靠 rsync 脚本对照 diff）：

```bash
mkdir -p Vendor && cp -R /Users/fupingguo/fuhaha_workspace/ali-tools/qodercn-gateway Vendor/qodercn-gateway
rm -rf Vendor/qodercn-gateway/.git Vendor/qodercn-gateway/build Vendor/qodercn-gateway/logs \
       Vendor/qodercn-gateway/local.json Vendor/qodercn-gateway/local.authkeys
echo "qodercn-gateway" > Vendor/qodercn-gateway/.upstream-baseline  # 追加基线 commit hash
```

并在 `Vendor/qodercn-gateway/sync-from-upstream.sh` 落一个 rsync 对照脚本（排除上面删掉的项），二选一路线在 commit message 里写明。
验证：`ls Vendor/qodercn-gateway/cmd internal go.mod` 齐全；`cd Vendor/qodercn-gateway && go build ./...` 通过。

- [ ] **1.2 写 `scripts/build-qoder-gateway.sh`：**

```bash
#!/bin/bash
set -euo pipefail
GO_BIN="$(command -v go || true)"
if [ -z "$GO_BIN" ]; then
  echo "error: go not found. Install with: brew install go" >&2
  exit 1
fi
SRC="${SRCROOT}/Vendor/qodercn-gateway"
OUT="${BUILT_PRODUCTS_DIR}/qodercn-gateway"
cd "$SRC"
"$GO_BIN" build -trimpath -o "$OUT" ./cmd/qodercn-gateway
echo "built $OUT"
```

`chmod +x` 之。本地冒烟：`SRCROOT=$PWD BUILT_PRODUCTS_DIR=/tmp/gwtest ./scripts/build-qoder-gateway.sh` 产出可执行文件。

- [ ] **1.3 工程文件加 phase。** 用文本编辑 pbxproj（uuid 取 24 位 hex 随机、全文件唯一）：
  1. 新 `PBXShellScriptBuildPhase`（name = "Build Qoder Gateway"，`shellPath = /bin/sh`，`shellScript` = `"${SRCROOT}/scripts/build-qoder-gateway.sh"`，inputPaths/outputPaths 留空即每次跑——go 自带构建缓存，代价可接受），插入 target NotchDrop 的 `buildPhases` 数组**首位**。
  2. 新 `PBXCopyFilesBuildPhase`（dstSubspecSpec 用 `MACOSX_CODE_DIRECTORY` 即 `Contents/MacOS`，`name = "Embed Qoder Gateway"`，files 引用新建 `PBXFileReference`（path = `qodercn-gateway`, sourceTree = `BUILT_PRODUCTS_DIR`… 实际采用 `PBXFileSystemSynchronizedRootGroup` 不适用本工程，直接 fileRef + explicitFileType = "compiled.mach-o.executable"），phase 排在 Resources 之后、Sources 之前无所谓，位置在 Copy Files 类阶段即可。
- [ ] **1.4 全量构建验证：**

```bash
xcodebuild -project NotchDrop.xcodeproj -target NotchDrop -configuration Debug build
codesign --verify --deep --strict build/Debug/NotchDrop.app && echo SIGN-OK
ls -la build/Debug/NotchDrop.app/Contents/MacOS/   # 应含 qodercn-gateway
```

若 `codesign -dvvv` 显示 helper 未被重签（仍是 linker-signed），按规格 §2.2 回退：Copy Files 后追加 ad-hoc 签名 phase（`codesign --force --sign - --options runtime "$BUILT_PRODUCTS_DIR/$CONTENTS_FOLDER_PATH/MacOS/qodercn-gateway"`）。把实测结论写进 commit message。
- [ ] **1.5 Commit：** `feat(gateway): vendor qodercn-gateway source and embed binary into app bundle`

---

### 任务 2（P1→P2 交界）：Go 侧 stdin-EOF 自尽补丁 + 共享契约 fixture

**文件：**
- 修改：`Vendor/qodercn-gateway/cmd/qodercn-gateway/main.go`
- 创建：`Tests/Fixtures/qoder-gateway.log`

- [ ] **2.1 打补丁。** main.go 中定位（已核实存在）：

```go
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
```

在其后插入：

```go
	// notchevery-patch: parent-death watchdog. When embedded as a helper inside
	// NotchEvery.app, the manager keeps a pipe write-end open on our stdin; when the
	// parent dies (fd closed), ReadStdin returns EOF and we shut down like SIGTERM.
	go func() {
		buf := make([]byte, 1)
		for {
			n, err := os.Stdin.Read(buf)
			if (err != nil || n == 0) && !errors.Is(err, syscall.EINTR) {
				sigCh <- syscall.SIGTERM
				return
			}
		}
	}()
```

import 补 `"errors"`。验证：`cd Vendor/qodercn-gateway && go vet ./... && go build ./...`。
- [ ] **2.2 行为验证（一次性，不留进程）：**

```bash
cd Vendor/qodercn-gateway && go build -o /tmp/qgw ./cmd/qodercn-gateway
( exec 3< <(:); sleep 0.1 ) # noop guard
python3 - <<'EOF'
import subprocess, time, socket
p = subprocess.Popen(["/tmp/qgw","--host","127.0.0.1","--port","8099"],
                     stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
time.sleep(1.5)
assert p.poll() is None, "should be running"
p.stdin.close()          # simulate parent death -> EOF
p.wait(timeout=5)
print("self-exit OK, rc=", p.returncode)
EOF
```

预期打印 `self-exit OK`。若父进程被 kill -9，Python 退出时 OS 关闭管道读端同样触发——用 `kill -9` 变体再验一次（起进程后 kill -9 python，5 s 后 `lsof -iTCP:8099` 应为空）。
- [ ] **2.3 共享 fixture。** 从真实日志摘 6~8 行（含跨两天、非 usage 噪声行、缓存命中行各至少 1 条）存 `Tests/Fixtures/qoder-gateway.log`，作为任务 3/4 双方测试锚点。敏感 key/token 不得入 fixture。
- [ ] **2.4 Commit：** `feat(gateway): add parent-death stdin-EOF watchdog patch to vendored gateway`

---

### 任务 3（P2 前半）：QoderGatewayConfig（配置/authkeys 纯函数层）

**文件：**
- 创建：`NotchDrop/QoderGatewayConfig.swift`、`Tests/QoderGatewayConfigTests.swift`
- 修改：pbxproj Sources（两个新文件加入对应 target；若工程为 FileSystemSynchronized group 则自动收）

- [ ] **3.1 写失败测试**（fixture 断言 + 行为断言）：

```swift
final class QoderGatewayConfigTests: XCTestCase {
    func testDefaultJSONUsesPort8096AndIsDecodableByGoContract() throws {
        let cfg = QoderGatewayConfig.default(port: 8096, authKeysFile: "/tmp/k")
        let data = try JSONEncoder().encode(cfg)
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(obj["port"] as? Int, 8096)
        XCTAssertEqual(obj["host"] as? String, "127.0.0.1")
        XCTAssertNotNil(obj["auth_keys_file"])
        // 上游凭证走 CLI 缓存 => 不写 remote_auth_file
        XCTAssertNil(obj["remote_auth_file"])
    }
    func testGeneratedAuthKeySatisfiesGatewayCharsetRule() {
        let key = QoderGatewayConfig.makeAuthKey()
        XCTAssertEqual(key.count, 40)
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_*=+")
        XCTAssertTrue(key.unicodeScalars.allSatisfy { allowed.contains($0) })
    }
    func testEnsureLayoutCreatesMissingFilesOnly(dir: URL) // 临时目录三件套：gateway.json / authkeys / gateway.log；已存在不覆盖
}
```

- [ ] **3.2 跑测试确认编译失败**（类型不存在）。运行：`xcodebuild -project NotchDrop.xcodeproj -scheme NotchEvery -only-testing:NotchEveryTests/QoderGatewayConfigTests test`（scheme 名以工程实际为准）。
- [ ] **3.3 实现** `QoderGatewayConfig.swift`：`struct QoderGatewayConfig: Codable`（CodingKeys 对齐 Go fileConfig：host/port/auth_keys_file/model/session_mode，可选字段 encodeIfPresent）、静态 `default(port:authKeysFile:)`、`makeAuthKey()`（SecRandomCopyBytes → 字符表取值）、`enum QoderGatewayPaths { static var baseDir/appSupport 下 qoder-gateway、gatewayJSON、authKeys、gatewayLog }`、`ensureLayout(at:fileManager:)` 返回写入结果元组，authkeys 权限 0600。
- [ ] **3.4 跑测试确认通过**（同上命令），预期 3 tests passed。
- [ ] **3.5 Commit：** `feat(qoder): add gateway config layout and auth-key generation`

---

### 任务 4（P2 后半）：QoderGatewayManager（状态机 + 生命周期）

**文件：**
- 创建：`NotchDrop/QoderGatewayManager.swift`、`Tests/QoderGatewayManagerTests.swift`

- [ ] **4.1 写失败测试**（可测面 = 纯函数 + 假注入）：

```swift
func testStateMachineTransitions() {           // stopped→starting→running→stopping→stopped；running→crashed；非法转换拒绝
func testFindStaleGatewayPIDMatchesOnlyOwnBinaryPath() // 注入 fake lsof 输出解析器："123\n456" + ps 路径表 → 只返回路径==bundlePath 的 pid
func testHealthProbeFailsClosedOnClosedPort()  // 随机高端口 TCP 探测立即 false
```

- [ ] **4.2 跑测试确认失败。**
- [ ] **4.3 实现** `QoderGatewayManager.swift`：
  - `enum GatewayState { case stopped, starting, running, stopping, crashed(reason: String) }`，`@Published private(set) var state`。
  - `start()`：`ensureLayout` → 端口占用检测（NWListener 或 ::connect 探 127.0.0.1:port）→ 占用则 `stalePIDs()`（`lsof -nP -iTCP:\(port) -sTCP:LISTEN -t` 输出经纯函数 `filterPids(_:pathsOf:)` 过滤，路径比对 `Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/qodercn-gateway")`）→ SIGTERM、2 s 后仍活 SIGKILL → 仍占 → `.crashed("端口被占用")`。
  - spawn：`Process` 指向上述路径，`arguments = ["--config", gatewayJSON.path]`，stdin/stdout/stderr 各接 `Pipe`（stdin 持写端不关 = 看门狗通道；stdout/stderr 异步排干并追写 `gateway.log`，超 10 MB 截半）。`terminationHandler` → 非主动 stop 而退出 ⇒ `.crashed`。
  - 健康：spawn 后 250 ms 轮询 TCP 可达，10 s 超时 ⇒ crashed("启动超时")。
  - `stop()`：`.stopping` → SIGTERM → 3 s 未退 SIGKILL → `.stopped`。
  - `applicationWillTerminate` 钩子（main.swift/AppDelegate 现有出口处调 `stop()`）。
  - 全部对外 API 主线程；IO 在 utility queue，状态发布回主线程。参考同工程 `AntigravityStore` 的 Timer/去重风格。
- [ ] **4.4 跑测试确认通过。**
- [ ] **4.5 真机冒烟（手动，验收项）：** 临时 debug 入口或 `swift` REPL 驱动 start/stop 各一次；`kill -9` 主 App 后 5 s 内 `lsof -iTCP:8096` 为空；重启 App 触发清扫路径日志。把结果记进 commit message。
- [ ] **4.6 Commit：** `feat(qoder): add gateway process manager with orphan prevention`

---

### 任务 5（P3 前半）：QoderLogParser（增量 + 日界聚合）

**文件：**
- 创建：`NotchDrop/QoderLogParser.swift`、`Tests/QoderLogParserTests.swift`
- 复用：`Tests/Fixtures/qoder-gateway.log`

- [ ] **5.1 写失败测试：**

```swift
func testParseUsageLineExtractsAllFields()      // golden 行 → in/out/cached/total/credits/date
func testNonMatchingLinesIgnored()              // warmup/listening 行 → nil
func testIncrementalReadOnlyConsumesNewBytes()  // 对同一 FileHandle 两次 readIncremental，第二次仅当追加后产生新事件
func testDayRollResetsAggregatesAndKeepsYesterday()
func testRotationDetectedViaInodeOrShortSizeResetsOffset()
func testCacheRateDenominatorFollowsFixedFormula() // 与 TokenFormatUtils 现口径一致（b956c9d）
```

- [ ] **5.2 跑测试确认失败。**
- [ ] **5.3 实现** `QoderLogParser.swift`：`struct QoderUsageEvent`（date/in/out/cached/total/credits/model，Codable）；`final class QoderLogTailer { struct Cursor {offset: UInt64, inode: UInt64}; func readIncremental(from handle:, now:) -> [QoderUsageEvent] }` —— seek(cursor.offset)，size < offset 或 inode 变 ⇒ 归零重扫；只消费完整行（尾部残行回退 offset）。`struct QoderDailyAgg { calls, tokensIn/Out/Cached, credits, cacheRate }` + `QoderAggregator.apply(events, today:)` 处理跨日清零、旧值移 `yesterday`。正则一条：`^(\d{4}-\d{2}-\d{2}) (\d{2}:\d{2}:\d{2}).*remote usage model=(\S+) in=(\d+) out=(\d+) cached=(\d+) reasoning=(\d+) total=(\d+) credits=([\d.]+)`。
- [ ] **5.4 跑测试确认通过。**
- [ ] **5.5 Commit：** `feat(qoder): add incremental gateway log tailer with day-roll aggregation`

---

### 任务 6（P3 后半）：QoderStore（/quota + 发布层）

**文件：**
- 创建：`NotchDrop/QoderStore.swift`、`Tests/QoderStoreTests.swift`

- [ ] **6.1 写失败测试：** quota 解码 golden（实测样例：user_type/unit/total/used/remaining/percentage/is_exceeded/reset_at_ms/source → struct 字段与 resetDate 换算）；`isStale` 语义（连续失败 ≥2 ⇒ stale，成功即清除）；store 组合 tailer+aggregator 的发布去重（同值不 publish）。网络层注入假 transport 协议。
- [ ] **6.2 跑测试确认失败。**
- [ ] **6.3 实现** `QoderStore.swift`：`@MainActor final class QoderStore: ObservableObject`，`@Published private(set) var quota: QoderQuota?`、`today: QoderDailyAgg`、`yesterday: QoderDailyAgg?`、`isQuotaStale: Bool`、`stateText`。15 s Timer + `NSApp` 激活刷新；`GET http://127.0.0.1:<manager.port>/quota`，Bearer = authkeys 首行；URLSession timeout 15 s。日志 tailer 复用 manager 暴露的 log 句柄路径。错误全部内化为 stale/nil，不弹错。
- [ ] **6.4 跑测试确认通过。**
- [ ] **6.5 Commit：** `feat(qoder): add quota polling and daily usage store`

---

### 任务 7（P4）：卡片 UI + 挂载 + 设置开关

**文件：**
- 创建：`NotchDrop/QoderProxyCardView.swift`
- 修改：`NotchDrop/OverviewPageView.swift:9-21`、第二页装配处（执行时定位 `iOSPageIndicator` 关联的 page 2 视图）、`NotchSettingsView.swift`/`ConfigStore`（新增 `showQoderCard` 开关，沿用 PublishedPersist 模式）、`AppDelegate.swift`（store/manager.start()）

- [ ] **7.1 View 实现**：照抄 `AntigravityProxyCardView` 骨架（padding 18/12、`.frame(width: 360)`、`studioCard(radius: 8)`、字号体系），替换数据源为 `QoderStore.shared` + `QoderGatewayManager.shared`：header = 状态点（running emerald / crashed red / stopped gray，点击弹 Menu：启动/停止/重新加载配置）+ 标题「Qoder 反代 :\(port)」；三宫格 = 今日请求(次)/今日消耗(credits)/剩余额度(credits)；footer = 「重置 \(date)」「缓存命中率 x%」+ stale 时额度值后缀「· 离线」。空数据全部渲染 `--` 不隐藏卡片。
- [ ] **7.2 挂载**：两页均包 `if ConfigStore.shared.showQoderCard { QoderProxyCardView(vm: vm).padding(.horizontal, 14).background(...) }`，样式与相邻 Antigravity 卡完全一致。
- [ ] **7.3 设置页**：开关 + 只读信息区（端口、authkeys 路径、「打开日志目录」按钮走 `NSWorkspace.open`）。
- [ ] **7.4 构建 + 真机验收：** `xcodebuild build` 绿 → 装到 /Applications（项目记忆：只装系统应用目录）→ 请用户过目视觉与交互，反馈修完才继续。
- [ ] **7.5 Commit：** `feat(ui): add Qoder proxy dashboard card to overview pages`

---

### 任务 8（P5）：收尾文档 + 端口切换演练

- [ ] **8.1** `docs/qoder-gateway.md`：架构图、故障排查（Go 缺失/端口冲突/登录态失效三类文案）、上游同步 SOP（subtree pull 或 rsync 脚本 + 重放 notchevery-patch）、扶正 8095 步骤（改 gateway.json port → 设置页重载 → 验证接管）。
- [ ] **8.2 端口切换演练（验收）：** 临时停掉手跑 8095 → 配置改 8095 → App 接管成功 → `/quota` 通 → 改回 8096 → 恢复手跑实例。全程记录。
- [ ] **8.3 全量回归：** XCTest 全套绿；Antigravity 两卡不受影响（视觉抽查）。
- [ ] **8.4 Commit：** `docs(qoder): add gateway operations guide and finish port-migration drill`

## 自检记录

- 规格覆盖度：§2.1→T1.1，§2.2→T1.2-1.4，§3.1→T3/T4，§3.2→T2+T4，§3.3→T4，§4.1→T6，§4.2→T5，§5→T7，§6→各任务测试步+T8.3，§7→节奏映射 P1=T1-2/P2=T3-4/P3=T5-6/P4=T7/P5=T8。无遗漏。
- 类型一致性：`QoderDailyAgg`/`QoderQuota`/`GatewayState` 定义于 T5/T6/T4，T7 仅消费；`manager.port` 由 gateway.json 解码而来，单一来源。
