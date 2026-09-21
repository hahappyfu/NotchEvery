# Qoder 网关分区 UI 视觉重构实施计划

> **面向执行模型/子代理：**
> 本计划专注于重构第三页（网关分区）的视觉质感，彻底消除刺眼红圈与粗糙感，完全融入第一页的高端 Dark Tech / Apple Native Studio 工业级设计系统。

## ⚠️ 交接须知（接手前必读）

**工作分支**：`worktree-qoder-gateway-manager`（已在 git worktree `.claude/worktrees/qoder-gateway-manager`）。
底层链路已全部跑通并提交（vendor 入仓、进程启停、状态机、账号池/额度轮询、日志聚合、独立分区），
**本次只做纯视觉重构，不要改动 `QoderStore`/`QoderGatewayManager` 的数据逻辑与网络契约**。

**环境与验证姿势（务必遵守，否则构建必挂）：**
- scheme 名是 `NotchDrop`（不是 NotchEvery）；测试 target 是 `NotchEveryTests`。
- 命令行构建/测试必须带签名绕过两参数（本机无 team 964G86XT2P 证书）：
  ```bash
  xcodebuild test -project NotchDrop.xcodeproj -scheme NotchDrop -configuration Debug \
    -derivedDataPath /tmp/nDD-qgw CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO
  ```
- 新增 `.swift` 文件不会自动进工程：本工程用显式文件列表（非 FileSystemSynchronized），
  需手动加进 `project.pbxproj`（PBXFileReference + PBXBuildFile + Sources phase + group children 四处）。
  可复用 `/tmp/register_swift.py <path> --target app|test`（若已失效则手改 pbxproj，改后 `plutil -lint` 校验）。
- 主 target 的 `PRODUCT_MODULE_NAME = NotchEvery`，测试里须 `@testable import NotchEvery`。
- 基线现状：**168 个测试全绿**。改完必须回到全绿。

**端口现状（重要）：** NotchEvery 托管网关默认端口已从 8096 迁到 **8097**（8096 留给用户独立后台服务）。
UI 上任何端口展示走 `manager.port`，不要写死数字。

**验收铁律（项目记忆）：** UI 改动完成后 → 构建 → 装到 `/Applications`（只装系统应用目录，不装 ~/Applications）
→ pkill+open 重启实例 → **请用户真机过目视觉**再提交（visual-verify-by-user）。构建会触发运行实例自退，
固定顺序「先构建 → 再 pkill+open」。commit message 结尾附
`Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>`。

---

## 目标
重构 `QoderPoolRingView.swift` 与 `GatewayZoneView.swift`，达到与第一页 `AntigravityAccountsCardView` 完全同等的高级硬件感与精致度。

---

## 涉及文件
1. `NotchDrop/QoderPoolRingView.swift` —— 重构圆形账号节点（Orb）渲染逻辑、层次与配色
2. `NotchDrop/GatewayZoneView.swift` —— 重构两张卡片的布局、启停控制胶囊与第二张度量看板的视觉细节

---

## 任务清单

### 任务 1：重写色彩与状态映射规则（消灭“全红报警感”）
在 `QoderPoolRingView.swift` 中：
- [ ] 探针未通过/未探测**不要**使用高饱和度 `StudioColor.rose`！
- [ ] 重新定义色彩逻辑：
  - `isCurrent`（主力/粘性）：`StudioColor.emerald`（薄荷绿）+ 柔和绿光晕
  - `cooled`（冷却）：`StudioColor.amber`（暗琥珀金）+ 迷你雪花
  - 备用未冷却账号：`Color.white.opacity(0.38)`（哑光冰白银圈，正常工作态）
  - 仅当明确出现错误/离线时使用低饱和灰/暗红微标，绝对不要整圈刺眼大红。

### 任务 2：重塑圆形账号胶囊（Multi-layered Orb Capsule）
在 `QoderPoolRingView.swift` 的 `circleMember` 中：
- [ ] 直径设定为 48×48pt。
- [ ] **底层槽**：`Circle().fill(Color.white.opacity(0.04))` + 细边框 `Circle().stroke(Color.white.opacity(0.08), lineWidth: 1)`。
- [ ] **状态光环**：覆盖在底层槽上的 2.5pt 环形条，针对主力账号使用 `.shadow(color: StudioColor.emerald.opacity(0.35), radius: 6, y: 0)`。
- [ ] **文字排版**：
  - 尾号：`Text(account.name).font(.system(size: 11, weight: account.isCurrent ? .bold : .medium, design: .monospaced))`。
  - 下方副标：主力账号显示迷你实心绿点；冷却号显示 8pt 琥珀雪花；备用号显示极淡灰白短横或点，保持高度一致与呼吸感。
- [ ] **3D 景深保留**：保留 `rotationAngle` 透视和 `scaleEffect(1.08 / 0.95 / 0.88)`。

### 任务 3：重塑卡片顶栏与控制胶囊（Micro Action Capsule）
在 `QoderPoolRingView.swift` 的 `header` 中：
- [ ] 状态点：running 时薄荷绿呼吸微发光，stopped 时深石墨灰。
- [ ] 启停按钮（`toggleButton`）：
  - 运行态时：深暗底 `Color.white.opacity(0.08)` + 柔和白字 `停止`（带有极小正方形图标 `square.fill` 7pt），不再用刺眼大红底。
  - 停止态时：淡绿底 `StudioColor.emerald.opacity(0.12)` + 翠绿文字 `▶ 启动`。
  - 增加微质感描边：`Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)`。

### 任务 4：精细化第二张度量看板（QoderMetricsCardView）
在 `GatewayZoneView.swift` 的 `qoderMetricsCard` 中：
- [ ] 顶栏右侧文本端口号精修：采用微型深色胶囊包裹（例如 `Text(":8096").font(.system(size: 10, design: .monospaced)).padding(.horizontal, 6).padding(.vertical, 2).background(Color.white.opacity(0.05), in: Capsule())`）。
- [ ] 三个度量单元格（`metricCell`）：
  - 严格采用 `.studioCard(radius: 8)`。
  - 标题采用 `Color.white.opacity(0.45)`，大数字采用 `.system(size: 15, weight: .bold, design: .rounded)`，单位采用 `.system(size: 10)`。
- [ ] 底部状态条：左侧重置时间，右侧如果有缓存率，显示翠绿色的缓存率徽章。

---

## 验证验收标准（Verification）
1. 编译通过：`xcodebuild -project NotchDrop.xcodeproj -scheme NotchDrop -configuration Debug -derivedDataPath /tmp/nDD-qgw CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO build` 无警告无报错。
2. 单元测试全绿：所有 168 个测试全部通过。
3. 截图真机验收：
   - 账号圈不再是全屏刺眼大红，而是主力翠绿 + 备用银白 + 冷却琥珀的雅致配色。
   - 按钮高级精致，整体与第一页（Antigravity）视觉体验浑然一体。
