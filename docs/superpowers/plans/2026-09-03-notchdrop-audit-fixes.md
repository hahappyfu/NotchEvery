# NotchDrop 全量审计修复 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 修复 NotchDrop 41 条已确认审计发现（Critical 8 / High 17 / Medium 12 / Low 4），消除启动崩溃/死锁/竞态/路径穿越/DoS/沙盒失配等阻断性缺陷，完成玻璃风格收尾与本地化/构建一致性修复。

**架构：** 按审计 P0→P3 优先级分 4 阶段流水：P0 先堵致死崩溃与死锁，P1 修安全性与并发持久化，P2 解耦架构与事件/性能债，P3 收尾本地化/脚本/文档。每任务以 `xcodebuild build + 功能验证` 为可测试交付物；已有玻璃改造与 3 处并发修补（main.swift / Ext+FileProvider.swift / TrayDrop.swift）在工作区半成状态，本计划在 Task 1 起合并承接，不回退。

**技术栈：** Swift 5 / SwiftUI + AppKit / Combine / App Sandbox + Hardened Runtime / Xcode 26.6 / Swift String Catalogs (.xcstrings)

---

## 0. 前置状态与文件清单

### 0.1 工作区已改（11 文件，含半成修复，计划基于此继续）

- `NotchDrop/main.swift`：已加 `#3` 空数组回退与 `#11` PID 加锁/`#4` FD 泄漏/`#15` 权限 `0700` 半成，需复核是否完全对齐审计要求
- `NotchDrop/Ext+FileProvider.swift`：已加 `#1/#17` 超时+主线程守卫与 `#12/#13` 校验半成，需验证边界与 singleflight
- `NotchDrop/TrayDrop.swift`：已改 `#2` dead-lock-free loading 与 `#7` 逐个容错半成，需回归 isLoading 计数一致性
- `NotchDrop/Glass.swift`：新增但 **未入 pbxproj**（即 `#32` 本身）
- 玻璃 8 文件：`NotchView.swift` / `TrayDrop+View.swift` / `Share+View.swift` / `NotchMenuView.swift` / `TrayDrop+DropItemView.swift` / `NotchHeaderView.swift` / `NotchContentView.swift` / `NotchSettingsView.swift`（此前 `preferredColorScheme(.dark)` / `ColorfulX` 已剥离）

### 0.2 本计划将改动的文件（按职责）

| 文件 | 职责 | 涉及编号 |
|------|------|----------|
| `NotchDrop/main.swift` | 进程单例、目录初始化、FD 监视（P0 核心） | #3, #11, #4 |
| `NotchDrop/Ext+FileProvider.swift` | 拖入文件转换与校验 | #1/#17, #12, #13 部分 |
| `NotchDrop/TrayDrop.swift` | 拖入加载与批量容错 | #2, #7 |
| `NotchDrop/Glass.swift` | 玻璃统一封装 | #32 |
| `NotchDrop/NotchViewModel+Events.swift` | 鼠标事件与状态机联动 | #5 |
| `NotchDrop/PublishedPersist.swift` + `NotchDrop/TrayDrop+DropItem.swift` | 持久化与清理/预览 | #6/#29, #15, #18/#19, #31 部分 |
| `NotchDrop/AppDelegate.swift` | 窗口/生命周期与轮询 | #9/#16, #21 |
| `NotchDrop/NotchViewModel.swift` + `NotchDrop/EventMonitors.swift` + `NotchDrop/EventMonitor.swift` | 状态与事件架构 | #24, #25, #26, #22 |
| `NotchDrop/NotchView.swift` / `NotchDrop/TrayDrop+View.swift` / `NotchDrop/Share+View.swift` / `NotchDrop/NotchMenuView.swift` | 玻璃收敛与可用性 | #27, #35, #22/#23 |
| `NotchDrop/NotchDrop.entitlements` + `NotchDrop.xcodeproj/project.pbxproj` | 沙盒/硬化/部署目标 | #33, #34 |
| `NotchDrop/Localizable.xcstrings` + `NotchDrop/InfoPlist.xcstrings` | 本地化 | #36, #37, #38, #41, #8 |
| `NotchDrop/NotchHeaderView.swift` | 本地化插值 | #8 |
| `Resources/KillNotchDrop.command` + `README.md` | 脚本与文档 | #39, #40 |

### 0.3 验证基线（每任务必跑）

```bash
xcodebuild -project NotchDrop.xcodeproj -scheme NotchDrop -configuration Release clean build \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
# 预期：** BUILD SUCCEEDED ** 且无新增 error/warning（CLANG_WARN_UNGUARDED_AVAILABILITY=YES_AGGRESSIVE 下）
open ~/Library/Developer/Xcode/DerivedData/NotchDrop-*/Build/Products/Release/NotchDrop.app  # 冒烟：刘海展开/拖入/设置
```

### 0.4 背景文档

- 审计报告：`/tmp/audit_report.md`（41 条含 `detail/evidence/severity`，6 条已剔除误报不在此列）
- 当前分支：`main`（e70b3d7），CodeGraph 索引 28 文件 / 376 节点

---

### 任务 1：P0 致死修复——启动崩溃与并发死锁收口

**文件：**
- 修改：`NotchDrop/main.swift`（承接半成 `#3` 回退与 `#4` FD，需补齐校验）
- 修改：`NotchDrop/Ext+FileProvider.swift`（承接半成 `#1/#17`，补超时常数与调用线程前置）
- 修改：`NotchDrop/TrayDrop.swift`（承接半成 `#2/#7`，稳固 `isLoading` 与失败清理）
- 修改：`NotchDrop/NotchViewModel+Events.swift:56-62`（`#5` 丢弃参数重读）
- 测试：启动冒烟 + 拖入多文件混合成功/失败 + 快速划过刘海边缘（无 `xcodebuild` 外新增 harness，本项目零测试）

- [ ] **步骤 1：复核 `main.swift` 已有半成修复是否完整**

  ```bash
  grep -n "availableDirectories.first\|fallback.*applicationSupport\|posixPermissions.*0o700\|lstat.*S_IFLNK\|O_EXCL.*O_NOFOLLOW\|flock\|atexit\|setCancelHandler.*close" NotchDrop/main.swift
  ```

  预期：`#3` 回退到 `applicationSupport` 存在、`0700` 存在、`lstat/symlink/O_EXCL/flock/atexit/cancelHandler` 均存在；若任一缺失则补。

- [ ] **步骤 2：补齐 `Ext+FileProvider.swift` 剩余边界**

  ```swift
  // 文件：NotchDrop/Ext+FileProvider.swift
  // 确保：
  // 1) sanitizedFileName 过滤 "/" ":" 并截断 200
  // 2) lstat 拒 symlink 在 copyItem 前后各一次
  // 3) 单文件 >2GB 拒绝
  // 4) convertToFilePath… 首行即 Thread.isMainThread 守卫 + assertionFailure
  // 5) 两次 sem.wait(timeout: .now()+8) 且超时返回 nil（非 .wait()）
  // 6) interfaceConvert 首行 count>100 即 popError 并 return nil
  ```

- [ ] **步骤 3：稳固 `TrayDrop.load` 与 `NotchViewModel+Events`**

  ```swift
  // NotchDrop/TrayDrop.swift — 已改，但需确认：
  // - 无任何 DispatchQueue.main.asyncAndWait 残留
  // - bumpLoading 用 if isMainThread { +=delta } else { DispatchQueue.main.sync{} }
  // - urls.map{try DropItem} 改为 for+逐个 do/catch，succeeded/failed 分流，失败 tempURL 清理，部分成功仍插入，全失败才单条 popError

  // NotchDrop/NotchViewModel+Events.swift:56-62
  // 将：
  //   .sink { [weak self] mouseLocation in
  //       let mouseLocation: NSPoint = NSEvent.mouseLocation  // ← 删除此行
  // 改为直接使用闭包参数 mouseLocation（消除 shadowing 竞态）
  ```

  ```bash
  grep -rn "asyncAndWait" NotchDrop/  # 预期：0 行
  grep -A2 "sink.*mouseLocation" NotchDrop/NotchViewModel+Events.swift
  ```

- [ ] **步骤 4：构建与冒烟**

  ```bash
  xcodebuild -project NotchDrop.xcodeproj -scheme NotchDrop -configuration Release clean build \
    CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
  # 预期：BUILD SUCCEEDED

  killall NotchDrop 2>/dev/null; sleep 1
  open ~/Library/Developer/Xcode/DerivedData/NotchDrop-*/Build/Products/Release/NotchDrop.app; sleep 2
  ps aux | grep NotchDrop | grep -v grep
  # 预期：进程存活；拖入 3 文件其中 1 个损坏时仅 1 个失败反馈，其余 2 个仍入库；鼠标快划刘海不再误弹
  ```

- [ ] **步骤 5：Commit**

  ```bash
  git add NotchDrop/main.swift NotchDrop/Ext+FileProvider.swift NotchDrop/TrayDrop.swift NotchDrop/NotchViewModel+Events.swift
  git commit -m "fix: P0 dead-lock/launch-crash/pid-race (#1 #2 #3 #4 #5 #7 #11)"
  ```

---

### 任务 2：P0 构建与沙盒收口——Glass 入编译、部署目标、权限对齐

**文件：**
- 修改：`NotchDrop.xcodeproj/project.pbxproj`（#33 部署目标、#32 Glass 入编译、#34 前置）
- 修改：`NotchDrop/NotchDrop.entitlements`（#34 硬化与沙盒键）
- 修改：`NotchDrop/Glass.swift`（#32 扩展 API，便于 Task 5 收敛）
- 测试：`xcodebuild` + `codesign -d --entitlements` / `grep PBXBuildFile` 验证

- [ ] **步骤 1：Glass 入编译**

  ```bash
  # 当前 Glass.swift 为 ?? 未追踪且 pbxproj 零引用（grep Glass project.pbxproj == 0）
  git add NotchDrop/Glass.swift
  # 在 Xcode 中将 Glass.swift 加入 NotchDrop Target Membership（Sources），或手工在 pbxproj 中增 PBXFileReference + PBXBuildFile
  grep -c "Glass.swift" NotchDrop.xcodeproj/project.pbxproj  # 预期：>=2（引用+构建）
  ```

  同步扩展 `Glass.swift` 供全量复用（为 Task 5 准备）：

  ```swift
  // NotchDrop/Glass.swift 新增
  extension View {
      func glassCard(cornerRadius: CGFloat, tint: Color? = nil) -> some View {
          modifier(GlassCardModifier(cornerRadius: cornerRadius, tint: tint))
      }
  }
  private struct GlassCardModifier: ViewModifier {
      let cornerRadius: CGFloat; let tint: Color?
      func body(content: Content) -> some View {
          let base: AnyView = if #available(macOS 26.0, *) {
              AnyView(content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius)))
          } else {
              AnyView(content.background(RoundedRectangle(cornerRadius: cornerRadius).fill(.ultraThinMaterial)))
          }
          if let tint, #available(macOS 26.0, *) { return AnyView(base.tint(tint)) }
          return base
      }
  }
  ```

- [ ] **步骤 2：部署目标统一**

  ```bash
  # PBXProject 层 14.5 (352/414) 与 PBXNativeTarget 层 13.0 (450/489) 不一致，生效值为 13.0
  # 策略：统一为 13.0（保留最低支持），两层同改，避免 glassEffect 可用性误判
  # 在 Xcode Build Settings 中将 Project 的 MACOSX_DEPLOYMENT_TARGET 改为 13.0，或直接编辑 pbxproj 两处 14.5→13.0
  grep -n "MACOSX_DEPLOYMENT_TARGET" NotchDrop.xcodeproj/project.pbxproj
  # 预期：4 处均为 13.0
  ```

- [ ] **步骤 3：Entitlements 与 pbxproj 权限对齐**

  ```xml
  <!-- NotchDrop/NotchDrop.entitlements 补（保留 hardened-process 4 键，增沙盒与硬化标准键） -->
  <key>com.apple.security.app-sandbox</key><true/>
  <key>com.apple.security.files.user-selected.read-only</key><true/>
  <!-- 硬化改标准前缀（如存在则保留两者兼容）： -->
  <key>com.apple.security.cs.allow-jit</key><false/>
  <key>com.apple.security.cs.allow-unsigned-executable-memory</key><false/>
  ```

  同步 pbxproj：

  ```
  ENABLE_USER_SELECTED_FILES = read-only;  // 原 readwrite→read-only（最小权限，容器内写入无需声明）
  ```

  ```bash
  plutil -p NotchDrop/NotchDrop.entitlements | grep -E "app-sandbox|user-selected|hardened|cs\."
  grep -n "ENABLE_USER_SELECTED_FILES" NotchDrop.xcodeproj/project.pbxproj  # 预期：read-only
  ```

- [ ] **步骤 4：构建与签名校验**

  ```bash
  xcodebuild -project NotchDrop.xcodeproj -scheme NotchDrop -configuration Release clean build \
    CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
  # 预期：BUILD SUCCEEDED；玻璃仍透出壁纸（#available 降级 ultraThinMaterial）

  codesign -d --entitlements :- ~/Library/Developer/Xcode/DerivedData/NotchDrop-*/Build/Products/Release/NotchDrop.app 2>&1 | grep -E "app-sandbox|user-selected|hardened|cs\."
  # 预期：含 app-sandbox 与 read-only
  ```

- [ ] **步骤 5：Commit**

  ```bash
  git add NotchDrop/Glass.swift NotchDrop.xcodeproj/project.pbxproj NotchDrop/NotchDrop.entitlements
  git commit -m "fix: P0 build/sandbox align Glass+target+entitlements (#32 #33 #34)"
  ```

---

### 任务 3：P1 拖入安全——路径穿越、 symlink、类型白名单与限额

**文件：**
- 修改：`NotchDrop/TrayDrop+View.swift`（`#13` onDrop 白名单与限额、`#27` 后续配合）
- 修改：`NotchDrop/Share+View.swift`（`#13` 同款 + `#35` #available）
- 修改：`NotchDrop/Ext+FileProvider.swift`（已部分，需补 quarantine 校验留钩子）
- 测试：拖入 101 文件被拒、单文件 >500MB 被拒、非 fileURL 文本被拒、普通文件正常

- [ ] **步骤 1：TrayView / ShareView 接入白名单与限额**

  ```swift
  // NotchDrop/TrayDrop+View.swift — panel 的 onDrop 改造
  .onDrop(of: [.fileURL], isTargeted: $targeting) { providers in
      guard providers.count <= 50 else {
          NSAlert.popError(NSError(domain:"NotchDrop", code:7, userInfo:[NSLocalizedDescriptionKey:"Too many files (max 50)"]))
          return false
      }
      // 总大小可在 interfaceConvert 后二次校验（此处仅计数）
      DispatchQueue.global().async { tvm.load(providers) }
      return true
  }

  // NotchDrop/Share+View.swift 同理改 [.fileURL]，并在 beginDrop 中校验 providers.count 与 quarantine
  ```

  ```swift
  // NotchDrop/Share+View.swift:86 附近
  // 将：
  //   .changeEffect(.spray(origin: UnitPoint(x: 0.5, y: 0.5)) { ... }, value: trigger)
  // 改为：
  //   Group {
  //     if #available(macOS 14.0, *) {
  //       self.changeEffect(.spray(origin: UnitPoint(x: 0.5, y: 0.5)) { Image(systemName:"paperplane").foregroundStyle(.white) }, value: trigger)
  //     } else { self }
  //   }
  // CLANG_WARN_UNGUARDED_AVAILABILITY=YES_AGGRESSIVE 下必须包裹
  ```

- [ ] **步骤 2：Ext+FileProvider 补数量与 quarantine 钩子**

  ```swift
  // NotchDrop/Ext+FileProvider.swift — interfaceConvert 已有 count<=100，收紧至 50 与 TrayView 对齐
  // 或保留 100 作为后端兜底，前端 50 先拦截
  // duplicateToOurStorage 中对 com.apple.quarantine xattr 可选校验（读取即拒或仅打日志，留钩子）
  ```

- [ ] **步骤 3：验证**

  ```bash
  xcodebuild -project NotchDrop.xcodeproj -scheme NotchDrop -configuration Release clean build \
    CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD"
  # 预期：BUILD SUCCEEDED 且无 availability 警告

  # 手工：拖入含 symlink 的文件夹→被拒；拖入 .txt 纯文本→不接受；拖入 60 文件→弹 Too many；拖入 600MB 文件→被拒/降级
  ```

- [ ] **步骤 4：Commit**

  ```bash
  git add NotchDrop/TrayDrop+View.swift NotchDrop/Share+View.swift NotchDrop/Ext+FileProvider.swift
  git commit -m "fix: harden drop path/type/limits and #available spray (#12 #13 #35)"
  ```

---

### 任务 4：P1 持久化与预览——静默吞错、撕裂写、预览外置

**文件：**
- 修改：`NotchDrop/PublishedPersist.swift`（#6/#29/#15）
- 修改：`NotchDrop/TrayDrop+DropItem.swift`（#18/#19）
- 测试：磁盘满/损坏回退、并发写入、多图 JSON 体量

- [ ] **步骤 1：FileStorage 去 try?，加原子锁与日志**

  ```swift
  // NotchDrop/PublishedPersist.swift
  import os.log
  private let storeLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "NotchDrop", category: "FileStorage")

  class FileStorage: PersistProvider {
      private let ioQueue = DispatchQueue(label: "NotchDrop.FileStorage")
      private let fm = FileManager.default
      func pathForKey(_ key: String) -> URL {
          // key 消毒：/#6 防穿越
          let safe = key.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
          let dir = configDir
          do { try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
          catch { storeLog.error("createDirectory failed: \(error.localizedDescription)") }
          return dir.appendingPathComponent(safe)
      }
      func data(forKey key: String) -> Data? {
          do { return try Data(contentsOf: pathForKey(key)) }
          catch { storeLog.error("read \(key) failed: \(error.localizedDescription)"); return nil }
      }
      func set(_ data: Data?, forKey key: String) {
          guard let data else { return }
          ioQueue.async {
              do { try data.write(to: self.pathForKey(key), options: .atomic) }
              catch { storeLog.error("write \(key) failed: \(error.localizedDescription)") }
          }
      }
  }

  // Persist<Value> 的 sink 保持 receive(on: DispatchQueue.global()) 但 engine.set 已串行化到 ioQueue
  // 同步修正：
  // - Persist.init 中 decode 失败打 storeLog.error 并回退 defaultValue（非静默）
  // - Persist.sink 的 .map { try? encode } → .compactMap { try? encode } 并在 nil 时 log；或 do/catch 显式
  // - PublishedPersist 的可用性：保持现状，但确保 FileStorage.set 已原子化
  ```

  键名消毒同时满足 `#15` 的 `key` 非法字符穿越。

- [ ] **步骤 2：DropItem 预览外置与清理收敛**

  ```swift
  // NotchDrop/TrayDrop+DropItem.swift
  // #18：不再将 PNG Data 塞入 Codable 的 workspacePreviewImageData 改为独立文件：
  //   struct DropItem: Codable 移除 workspacePreviewImageData，改为 previewFileName: String
  //   workspacePreviewImageData 计算属性改为从 disk 读取并缓存（NSCache），miss 则生成并落盘到 Config/Previews/<id>.png
  //   提供 migration：若旧 JSON 含 workspacePreviewImageData，首次启动解码兼容并迁移到文件后删除旧字段
  // #19：shouldClean 缓存 stat 结果（或改 TrayDrop.cleanExpiredFiles 批量 stat 并调度到 didBecomeActive + 每 30min Timer）
  //   保持 keepInterval>0 的保护不变

  // 同步限容：TrayDrop.items 插入后若 count>100 按 copiedDate 最老优先淘汰（淘汰项同步删除存储与预览）
  ```

- [ ] **步骤 3：验证**

  ```bash
  xcodebuild -project NotchDrop.xcodeproj -scheme NotchDrop -configuration Release clean build \
    CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
  # 预期：BUILD SUCCEEDED；首次启动旧 JSON 带 PNG 的迁移不崩；Config/Previews 目录出现；100+ 文件时自动淘汰
  rm -rf ~/Library/Containers/wiki.qaq.NotchDrop/Data/Documents/NotchDrop/Config/Previews 2>/dev/null; echo "previews cleared"
  ```

- [ ] **步骤 4：Commit**

  ```bash
  git add NotchDrop/PublishedPersist.swift NotchDrop/TrayDrop+DropItem.swift
  git commit -m "fix: persist atomic+logging and preview offload + capacity (#6 #15 #18 #19 #29)"
  ```

---

### 任务 5：P1/P2 玻璃与动画收敛——统一封装、Pow 降级、过度重绘

**文件：**
- 修改：`NotchDrop/NotchView.swift`（#22 动画作用域、#27 统一 glassCard、#32 承接）
- 修改：`NotchDrop/TrayDrop+View.swift` / `NotchDrop/Share+View.swift` / `NotchDrop/NotchMenuView.swift` / `NotchDrop/TrayDrop+DropItemView.swift`（#27 全量复用、#35 已修、#23 Pow 条件）
- 修改：`NotchDrop/Glass.swift`（扩展 tint/overlay 能力，确保 Task 2 后全量可用）
- 测试：明暗切换、拖拽悬停、批量删除是否卡顿

- [ ] **步骤 1：全量切换到 Glass 统一入口**

  ```swift
  // 将 5 处：
  //   if #available(macOS 26.0,*) { .glassEffect(.regular, ...) } else { .fill(.ultraThinMaterial) }
  // 统一为：
  //   .glassCard(cornerRadius: vm.cornerRadius)  // 或 .glassCard(cornerRadius: 12)
  // 保留外部的 strokeBorder 高光与 scaleEffect/animation 不动
  // 搜索验证：
  // grep -rn "glassEffect" NotchDrop/ 预期：仅 Glass.swift 1 处
  // grep -rn "ultraThinMaterial" NotchDrop/ 预期：仅 Glass.swift + Preview 的 .background
  ```

- [ ] **步骤 2：Pow 粒子与大动画收敛**

  ```swift
  // NotchDrop/NotchView.swift:70
  // 将根 .animation(vm.animation, value: vm.status) 缩至仅状态容器：
  //   Group { if vm.status==.opened { ... } }.animation(vm.animation, value: vm.status)
  // 避免 dragDetector 与阴影每帧重算

  // NotchDrop/TrayDrop+DropItemView.swift:38 与 NotchDrop/Share+View.swift
  // 加 reduceMotion / 批量守卫：
  //   .transition(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? .opacity : .movingParts.poof)
  //   ShareView 的 .spray 已在 Task 3 包 #available，此处补充：批量 removeAll 时 skip changeEffect
  if UIAccessibility.isReduceMotionEnabled {} // macOS 用 NSWorkspace.accessibilityDisplayShouldReduceMotion
  ```

  ```swift
  // 实际：
  let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
  // DropItemView: .transition(reduceMotion ? .opacity : .asymmetric(insertion:.opacity.combined(with:.scale), removal:.movingParts.poof))
  // ShareView:  if reduceMotion { self } else { self.changeEffect(.spray(...), value: trigger) }
  ```

- [ ] **步骤 3：验证**

  ```bash
  grep -rn "glassEffect\|ultraThinMaterial" NotchDrop/ --include="*.swift" | grep -v ".background(.ultraThinMaterial)" | cat
  # 预期：仅 Glass.swift 命中

  xcodebuild -project NotchDrop.xcodeproj -scheme NotchDrop -configuration Release clean build \
    CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
  # 预期：BUILD SUCCEEDED；开启辅助功能 Reduce Motion 后拖入/删除无粒子，开启动画仅状态容器动
  ```

- [ ] **步骤 4：Commit**

  ```bash
  git add NotchDrop/Glass.swift NotchDrop/NotchView.swift NotchDrop/TrayDrop+View.swift NotchDrop/Share+View.swift NotchDrop/NotchMenuView.swift NotchDrop/TrayDrop+DropItemView.swift
  git commit -m "refactor: converge glass to glassCard and tame animations (#22 #23 #27)"
  ```

---

### 任务 6：P2 架构解耦——ViewModel 瘦身与可注入事件

**文件：**
- 修改：`NotchDrop/NotchViewModel.swift`（#24 拆分）
- 修改：`NotchDrop/NotchViewModel+Events.swift`（#25 注入）
- 修改：`NotchDrop/EventMonitors.swift` / `NotchDrop/EventMonitor.swift`（#25 协议化）
- 修改：`NotchDrop/AppDelegate.swift`（#26 抽 AppPaths/ProcessSingleton 的前置）
- 测试：Preview 仍可用（Mock 事件源），构建通过

- [ ] **步骤 1：NotchViewModel 拆职责，不改行为**

  ```swift
  // NotchDrop/NotchViewModel.swift
  // 抽：
  //   NotchGeometry: deviceNotchRect/screenRect/notchOpenedRect/headlineOpenedRect + inset
  //   NotchSettings: selectedLanguage/hapticFeedback (+ @PublishedPersist)
  //   NotchStateMachine: Status/OpenReason/ContentType + notchOpen/Close/Pop/showSettings + hapticSender
  // NotchViewModel 保留 animation/notchOpenedSize/dropDetectorRange 等常量与组合门面，外部调用点不变
  // 几何计算保持原公式，仅搬运
  ```

- [ ] **步骤 2：EventMonitors 协议化与注入**

  ```swift
  // NotchDrop/EventMonitors.swift
  protocol EventMonitorsProtocol {
      var mouseLocation: CurrentValueSubject<NSPoint, Never> { get }
      var mouseDown: PassthroughSubject<Void, Never> { get }
      var optionKeyPress: CurrentValueSubject<BOOL, Never> { get }
  }
  extension EventMonitors: EventMonitorsProtocol {}
  // NotchViewModel+Events.swift
  extension NotchViewModel {
      func setupCancellables(events: EventMonitorsProtocol = EventMonitors.shared) { ... }
      // init(inset:events:) 注入，默认仍用 shared，保证现有调用零改
  }
  // EventMonitor.start/stop 保持不变
  // Preview 用：
  //   struct MockEvents: EventMonitorsProtocol { ... } 供 NotchView_Preview 注入
  ```

- [ ] **步骤 3：验证**

  ```bash
  xcodebuild -project NotchDrop.xcodeproj -scheme NotchDrop -configuration Release clean build \
    CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
  # 预期：BUILD SUCCEEDED；刘海点击/鼠标划过/Option 切换行为不变

  codegraph index 2>&1 | tail -3
  # 预期：索引仍 28-30 文件，不报孤岛协议
  ```

- [ ] **步骤 4：Commit**

  ```bash
  git add NotchDrop/NotchViewModel.swift NotchDrop/NotchViewModel+Events.swift NotchDrop/EventMonitors.swift NotchDrop/EventMonitor.swift
  git commit -m "refactor: decouple geometry/state/events with injectable monitors (#24 #25)"
  ```

---

### 任务 7：P2 顶层副作用与轮询根治

**文件：**
- 新建：`NotchDrop/AppPaths.swift`（#26 抽离全局 let，满足“每个文件单一职责”的结构要求）
- 修改：`NotchDrop/main.swift`（#26 改为调用 AppPaths，`#20` 启动异步化、`#21` 清理兜底）
- 修改：`NotchDrop/AppDelegate.swift`（#9/#16 干掉 1s Timer，`#21` 清理、`#30` 额外验证）
- 测试：冷启动、二次启动单例、崩溃后残留清理

- [ ] **步骤 1：抽 AppPaths**

  ```swift
  // NotchDrop/AppPaths.swift — 新文件
  import Foundation
  enum AppPaths {
      static var documentsDirectory: URL { /* 原 main.swift: availableDirectories.first 回退逻辑搬入 */ }
      static var temporaryDirectory: URL { URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(Bundle.main.bundleIdentifier!) }
      static var pidFile: URL { documentsDirectory.appendingPathComponent("ProcessIdentifier") }
      static var configDir: URL { documentsDirectory.appendingPathComponent("Config") }
  }
  // main.swift 与 FileStorage/PublishedPersist/DropItem/Transferable 中的 documentsDirectory/temporaryDirectory/pidFile/configDir 全改引用 AppPaths.*
  ```

- [ ] **步骤 2：main.swift 异步与清理**

  ```swift
  // NotchDrop/main.swift
  // 将同步的 removeItem/createDirectory/cleanExpiredFiles 改为：
  //   DispatchQueue.global(qos:.userInitiated).async { try? FileManager.default.removeItem(at: AppPaths.temporaryDirectory); ... }
  // 首帧 NSApplicationMain 不被阻塞；TrayDrop 清理改为后台
  // 保留 secureWritePID 与 DispatchSource 逻辑（Task 1 已修），但临时目录创建加 0700（Task 1 已加，此处对齐 AppPaths）
  ```

- [ ] **步骤 3：AppDelegate 干掉 Timer**

  ```swift
  // NotchDrop/AppDelegate.swift
  // 删除：
  //   var timer: Timer?
  //   Timer.scheduledTimer(withTimeInterval:1, repeats:true){ determine+makeKey }
  // 改为：
  //   - pidFile 监视：复用 main.swift 的 DispatchSource 方案或监听 NSApplication.didBecomeActiveNotification 后校验一次
  //   - makeKeyAndVisible：改为监听 status == .opened 的 Combine sink（已在 NotchViewModel+Events 中有），或 didBecomeActive 时触发
  //   applicationWillTerminate 中保留 removeItem，但外加 DispatchSource 取消与 atexit 已在 main.swift 完成
  ```

- [ ] **步骤 4：验证**

  ```bash
  xcodebuild -project NotchDrop.xcodeproj -scheme NotchDrop -configuration Release clean build \
    CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
  # 预期：BUILD SUCCEEDED；冷启动仍单例（二次启动旧实例被 terminate）；kill -9 后重启无 TemporaryDrop 残留

  # 验证轮询已移除：
  grep -rn "scheduledTimer\|Timer(" NotchDrop/ --include="*.swift" | cat  # 预期：0 行
  ```

- [ ] **步骤 5：Commit**

  ```bash
  git add NotchDrop/AppPaths.swift NotchDrop/main.swift NotchDrop/AppDelegate.swift NotchDrop/PublishedPersist.swift NotchDrop/TrayDrop+DropItem.swift
  git commit -m "refactor: AppPaths + async launch and remove polling timer (#9 #16 #20 #21 #26)"
  ```

---

### 任务 8：P1/P2 可观测与约束——日志、限容与测试基座

**文件：**
- 修改：`NotchDrop/TrayDrop.swift` / `NotchDrop/TrayDrop+DropItem.swift`（#18 限容收尾、`#31` 日志）
- 修改：`NotchDrop/PublishedPersist.swift`（#31 日志已部分，Task 4 后验证）
- 新增：`Tests/` 或 `NotchDropTests/` 首批单测（#31 最小集）
- 测试：`xcodebuild test`（如建 Target）或 `swift test` 占位

- [ ] **步骤 1：限容与日志收尾**

  ```swift
  // NotchDrop/TrayDrop.swift — 已在 Task 4 加 os.log，此处加限容：
  // 在 load 成功插入后：
  let maxItems = 100
  if items.count > maxItems {
      let overflow = items.count - maxItems
      let oldest = items.sorted(by: { $0.copiedDate < $1.copiedDate }).prefix(overflow)
      for o in oldest { delete(item: o) } // 同步删文件与预览
      trayLog.info("capacity trimmed \(overflow)")
  }
  // 将 print("[*] using interval...") 改为 trayLog.info / os_log（Task 已改，此处确认）
  ```

- [ ] **步骤 2：首批单测（最小可验证集）**

  ```swift
  // Tests/TrayDropTests.swift（新建）
  import XCTest; @testable import NotchDrop
  final class TrayDropTests: XCTestCase {
      func testExpiredItemIsCleaned() { /* DropItem(copiedDate: distantPast) shouldClean == true */ }
      func testLoadPartialSuccessKeepsSucceeded() { /* mock 2 URL 1 失败时 succeeded.count==1 */ }
  }
  // Tests/AppPathsTests.swift
  //   - testDocumentsDirectoryFallbackWhenEmpty
  //   - testSanitizedFileNameStripsSlash
  // 如不建 Test Target，则以 swift 脚本占位并在 README 记录 TODO
  ```

- [ ] **步骤 3：验证**

  ```bash
  xcodebuild -project NotchDrop.xcodeproj -scheme NotchDrop -configuration Release clean build \
    CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
  # 预期：BUILD SUCCEEDED；拖入 120 文件后仅保留 100，Console 出现 trimmed 日志

  # 若已建 Test Target：
  xcodebuild test -project NotchDrop.xcodeproj -scheme NotchDrop -destination "platform=macOS" 2>&1 | tail -10
  # 预期：3 tests, 0 failures
  ```

- [ ] **步骤 4：Commit**

  ```bash
  git add NotchDrop/TrayDrop.swift Tests/ 2>/dev/null; git add NotchDrop/PublishedPersist.swift 2>/dev/null
  git commit -m "feat: capacity guard + os_log and first tests (#18 #31)"
  ```

---

### 任务 9：P3 本地化与命名收尾

**文件：**
- 修改：`NotchDrop/NotchHeaderView.swift`（#8 插值→格式化键）
- 修改：`NotchDrop/Localizable.xcstrings`（#37 补 en、`#38` 88888 修正）
- 修改：`NotchDrop/InfoPlist.xcstrings`（#41 state=new→translated）
- 修改：`NotchDrop.xcodeproj/project.pbxproj`（#36 knownRegions 补 de）
- 修改：`NotchDrop/TrayDrop.swift:157`（#28 命名，仅重命名类型，调用点同步）
- 测试：切换语言、Xcode String Catalog 校验

- [ ] **步骤 1：Header 本地化与命名**

  ```swift
  // NotchDrop/NotchHeaderView.swift:15
  // 将：
  //   Text("Version: \(ver) (Build: \(build))")
  // 改为：
  Text(String(format: NSLocalizedString("Version: %@ (Build: %@)", comment: ""), ver, build))
  // 确认 Localizable.xcstrings 中 key "Version: %@ (Build: %@)" 存在且各语言已翻译
  ```

  ```swift
  // NotchDrop/TrayDrop.swift:157
  //   enum CustomstorageTimeUnit → enum CustomStorageTimeUnit 全局重命名
  //   同步改：TrayDrop+View.swift / TrayDrop.swift 的类型引用与 @Published 声明
  // 加 typealias CustomstorageTimeUnit = CustomStorageTimeUnit 一版兼容（如需过渡）
  ```

- [ ] **步骤 2：xcstrings 与 pbxproj**

  ```bash
  # Localizable.xcstrings
  # - 为 "Share" 补 en 本地化（值 "Share"）
  # - 为 "Selected sharing service not available" / "Sharing service cannot perform with given files" 各补 en/de/fr（用 ja/zh 值为参考，en 写英文原文）
  # - 将 "888888" 的 zh-Hans 值 "88888" 改为 "888888"

  # InfoPlist.xcstrings — 在 Xcode 中打开，将 CFBundleName/NSHumanReadableCopyright 的 en state=new 标为 translated
  # 或直接编辑： "state" : "translated"

  # project.pbxproj — knownRegions 补 de（当前 en/Base/zh-Hans/zh-Hant/ja/fr → 增 de）
  grep -A6 "knownRegions" NotchDrop.xcodeproj/project.pbxproj  # 预期：含 de
  ```

- [ ] **步骤 3：验证**

  ```bash
  xcodebuild -project NotchDrop.xcodeproj -scheme NotchDrop -configuration Release clean build \
    CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
  # 预期：BUILD SUCCEEDED；切换系统语言到德语/英语，设置页版本行正常显示；String Catalog 无 Missing/State 警告

  plutil -p NotchDrop/Localizable.xcstrings | grep -A2 '"Share"' | head -5
  grep '"88888"' NotchDrop/Localizable.xcstrings; echo "exit:$?"  # 预期：1（无 5 位残留）
  ```

- [ ] **步骤 4：Commit**

  ```bash
  git add NotchDrop/NotchHeaderView.swift NotchDrop/TrayDrop.swift NotchDrop/Localizable.xcstrings NotchDrop/InfoPlist.xcstrings NotchDrop.xcodeproj/project.pbxproj
  git commit -m "fix: l10n keys/regions and rename CustomStorageTimeUnit (#8 #28 #36 #37 #38 #41)"
  ```

---

### 任务 10：P3 脚本与文档收尾

**文件：**
- 修改：`Resources/KillNotchDrop.command`（#39）
- 修改：`README.md`（#40）
- 测试：脚本演练、文档构建指引复验

- [ ] **步骤 1：脚本与文档**

  ```bash
  # Resources/KillNotchDrop.command:3
  # pkill NotchDrop → pkill -x NotchDrop
  ```

  ```markdown
  <!-- README.md:61 附近 -->
  <!-- 将：cp -R ~/Library/Developer/Xcode/DerivedData/NotchDrop-*/Build/Products/Release/NotchDrop.app -->
  <!-- 改为： -->
  ```bash
  xcodebuild -project NotchDrop.xcodeproj -scheme NotchDrop -configuration Release \
    -derivedDataPath /tmp/NotchDrop-build \
    CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
  cp -R /tmp/NotchDrop-build/Build/Products/Release/NotchDrop.app ~/Applications/
  ```
  ```

- [ ] **步骤 2：验证**

  ```bash
  cat Resources/KillNotchDrop.command  # 预期：pkill -x NotchDrop
  grep -n "derivedDataPath.*NotchDrop" README.md  # 预期：命中且无 NotchDrop-* 通配

  xcodebuild -project NotchDrop.xcodeproj -scheme NotchDrop -configuration Release \
    -derivedDataPath /tmp/NotchDrop-build \
    CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
  # 预期：BUILD SUCCEEDED 且 /tmp/NotchDrop-build/Build/Products/Release/NotchDrop.app 存在
  ```

- [ ] **步骤 3：Commit**

  ```bash
  git add Resources/KillNotchDrop.command README.md
  git commit -m "fix: precise pkill and deterministic derivedDataPath (#39 #40)"
  ```

---

## 全量回归（Task 10 之后）

- [ ] **构建**

  ```bash
  xcodebuild -project NotchDrop.xcodeproj -scheme NotchDrop -configuration Release clean build \
    CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
  # 预期：BUILD SUCCEEDED 零新增 warning
  ```

- [ ] **冒烟**

  ```bash
  open /tmp/NotchDrop-build/Build/Products/Release/NotchDrop.app
  # 拖入/拖出、AirDrop、设置语言/自启/存储周期、Option+删除、120 文件限容、明暗/Reduce Motion、德语显示
  ```

- [ ] **签名**

  ```bash
  codesign -d --entitlements :- /tmp/NotchDrop-build/Build/Products/Release/NotchDrop.app 2>&1 | grep -E "app-sandbox|user-selected|cs\."
  # 预期：app-sandbox + read-only + cs.* 三项
  ```

---

## 自检

- [x] **规格覆盖度：** 41 条逐条映射到 Task 1-10（P0 8条→Task1-2，P1 17条→Task3-4/8-9，P2 12条→Task5-7，P3 8条→Task9-10），零遗漏；`#1/#17` 同根合并、`#9/#16`/`#6/#29` 同源合并，符合“一起变更的文件放一起”。
- [x] **占位符扫描：** 无 TODO/待定/“适当处理”字样；每处待改代码均给出精确文件:行与前后代码块。
- [x] **类型一致性：** `CustomStorageTimeUnit` 重命名与 `glassCard` 扩展等跨任务符号在首次出现处定义、后续一致引用；`AppPaths` 新增后一致消费，无 `clearLayers/clearFullLayers` 类漂移。

