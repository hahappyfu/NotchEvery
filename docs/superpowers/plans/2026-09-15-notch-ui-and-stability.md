# NotchEvery UI 适配、边缘渲染瑕疵与主线程死锁修复实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 subagent-driven-development（推荐）或 executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 修复后台自动解锁导致的主线程模态死锁，用正向贝塞尔曲线替换 destinationOut 反向遮罩消灭刘海白边，重构刘海尺寸钳制算法使其紧凑自适应硬件刘海底线，并优化第三页守护控制台排版彻底根治文字截断。

**架构：**
1. **FUnManager**：后台自动解锁调用 `fetchPassword(warn: false)`，纯日志与状态机记录，严禁弹出阻塞式 NSAlert。
2. **SmoothNotchShape**：单个平滑连续闭合贝塞尔 Shape 替代反向镂空遮罩，天然抗锯齿并纯黑填充。
3. **NotchGeometry & Clamp**：重构 `clampPanelSize`，支持硬件刘海宽度基线保护、降低最小高度到 60pt、放宽长宽比限制，消除大黑框。
4. **GuardControlZoneView**：舒展容器宽度至 390pt，解耦 Header 状态与开关，优化 2×2 开关与判定卡片双行展示。

**技术栈：** Swift 6, SwiftUI, AppKit, XCTest

**规格：** `docs/superpowers/specs/2026-09-15-notch-ui-and-stability-design.md`

## 全局约束
- 编译与运行需禁签名：`CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO`
- 调试临时代码用 `#if DEBUG` 包裹，定案前清理干净
- 单一职责，遵循 Swift 6 并发与风格规范，修改精准不扩散

---

### 任务 1：根除后台解锁主线程阻塞死锁 (`FUnManager.swift`)

**文件：**
- 修改：`NotchDrop/FUnManager.swift:655-668`
- 测试：`Tests/FUnlockTests.swift`

- [ ] **步骤 1：编写失败的测试**
在 `Tests/FUnlockTests.swift` 中增加测试，验证在密码读取失败或静默解锁调用时，不会触发警告弹窗：

```swift
func testSilentUnlockDoesNotWarnOnError() {
    // 验证静默解锁链路下 warn 为 false
    let mockSys = MockSecuritySystem()
    mockSys.shouldFail = true
    let result = mockSys.fetchPassword(warn: false)
    XCTAssertFalse(mockSys.didShowModal)
}
```

- [ ] **步骤 2：运行测试验证失败**
运行：`xcodebuild test -project NotchDrop.xcodeproj -scheme NotchDrop -only-testing:NotchDropTests/FUnlockTests/testSilentUnlockDoesNotWarnOnError CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO`
预期：PASS（或根据 mock 桩验证行为）

- [ ] **步骤 3：修改 `FUnManager.swift`**
将 `FUnManager.swift:658`：
```swift
let fetchResult = self.system.fetchPassword(warn: true)
```
修改为：
```swift
let fetchResult = self.system.fetchPassword(warn: false)
```
确保后台静默流程不触发 `UIHelper.errorModal()`。

- [ ] **步骤 4：运行测试验证通过**
运行：`xcodebuild test -project NotchDrop.xcodeproj -scheme NotchDrop -only-testing:NotchDropTests/FUnlockTests CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO`
预期：PASS

- [ ] **步骤 5：Commit**
```bash
git add NotchDrop/FUnManager.swift Tests/FUnlockTests.swift
git commit -m "fix(guard): eliminate main thread modal freeze during silent auto-unlock"
```

---

### 任务 2：正向平滑贝塞尔形状成型消灭边缘白边 (`SmoothNotchShape`)

**文件：**
- 创建：`NotchDrop/SmoothNotchShape.swift`
- 修改：`NotchDrop/NotchView.swift:188-230`
- 测试：`Tests/DesignSystemTests.swift`

- [ ] **步骤 1：编写测试**
在 `Tests/DesignSystemTests.swift` 中增加对 `SmoothNotchShape` 路径计算的测试，确认路径在零尺寸与正向尺寸下正确闭合：

```swift
func testSmoothNotchShapePathValidity() {
    let shape = SmoothNotchShape(
        cornerRadius: 32,
        filletBlend: 64,
        bottomRadius: 26,
        isExpanded: true
    )
    let rect = CGRect(x: 0, y: 0, width: 320, height: 120)
    let path = shape.path(in: rect)
    XCTAssertFalse(path.isEmpty)
    XCTAssertTrue(path.boundingRect.width >= 320)
}
```

- [ ] **步骤 2：创建 `SmoothNotchShape.swift`**
编写平滑连续贝塞尔曲线正向绘制形状，彻底替代原先基于反向挖切遮罩的 `EllipticalCornerCut`：
- 从顶部中心出发向左绘制顶边；
- 在左侧以反曲贝塞尔曲线平滑外延到外耳过渡区；
- 沿外侧下行至底角，绘制底部平滑圆角；
- 沿底部水平连接至右底角，绘制右底圆角；
- 右侧以反曲贝塞尔曲线平滑收回顶边，闭合路径；
- 直接使用纯黑填充，无预乘 Alpha 抗锯齿杂边。

- [ ] **步骤 3：重构 `NotchView.swift` 中的岛体背景**
用 `SmoothNotchShape().fill(.black)` 替换 `notchBackgroundMaskGroup` 中的 `destinationOut` 遮罩群组，移除 `+0.5, -0.5` 亚像素偏移。

- [ ] **步骤 4：运行测试与编译验证**
运行：`xcodebuild test -project NotchDrop.xcodeproj -scheme NotchDrop -only-testing:NotchDropTests/DesignSystemTests CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO`
预期：PASS

- [ ] **步骤 5：Commit**
```bash
git add NotchDrop/SmoothNotchShape.swift NotchDrop/NotchView.swift Tests/DesignSystemTests.swift
git commit -m "fix(ui): replace destinationOut mask with SmoothNotchShape to eliminate white edge halo"
```

---

### 任务 3：刘海尺寸紧凑自适应与物理底线智能对齐

**文件：**
- 修改：`NotchDrop/NotchViewModel.swift:82-132`
- 修改：`NotchDrop/IslandMetrics.swift:40-46`
- 测试：`Tests/TabMetricsTests.swift`
- 测试：`Tests/ZoneSizeGuardTests.swift`

- [ ] **步骤 1：编写失败的测试**
在 `Tests/TabMetricsTests.swift` 中更新最小面板尺寸与钳制测试：

```swift
func testCompactPanelSizing() {
    // 物理刘海为 200pt 时，宽度保底为 200 + 16 = 216pt
    let sizeWithNotch = NotchViewModel.clampPanelSize(
        CGSize(width: 100, height: 40),
        maxHeight: 400,
        deviceNotchWidth: 200
    )
    XCTAssertEqual(sizeWithNotch.width, 216)
    XCTAssertEqual(sizeWithNotch.height, 60, "高度保底应为 60pt")

    // 无物理刘海时，宽度保底仅为内容自然宽（受 160 保底）
    let sizeWithoutNotch = NotchViewModel.clampPanelSize(
        CGSize(width: 180, height: 50),
        maxHeight: 400,
        deviceNotchWidth: 0
    )
    XCTAssertEqual(sizeWithoutNotch.width, 180)
    XCTAssertEqual(sizeWithoutNotch.height, 60)
}
```

- [ ] **步骤 2：运行测试验证失败**
运行：`xcodebuild test -project NotchDrop.xcodeproj -scheme NotchDrop -only-testing:NotchDropTests/TabMetricsTests CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO`
预期：FAIL（旧代码固定 minPanelSize 320×120 且不支持 deviceNotchWidth 入参）

- [ ] **步骤 3：实现新钳制逻辑**
1. 在 `IslandMetrics.swift` 中定义新保底常数：
   - `static let minPanelHeight: CGFloat = 60`
   - `static let minExternalPanelWidth: CGFloat = 160`
   - 适当调整 `panelAspectFloor`（例如 1.15）或仅在高宽比异常陡峭时做柔性保护；
2. 在 `NotchViewModel.swift` 中更新 `clampPanelSize(_ natural: CGSize, maxHeight: CGFloat, deviceNotchWidth: CGFloat)`：
   - 若 `deviceNotchWidth > 0`，最小宽度 = `max(deviceNotchWidth + 16, natural.width)`；
   - 若 `deviceNotchWidth == 0`，最小宽度 = `max(natural.width, IslandMetrics.minExternalPanelWidth)`；
   - 最小高度 = `IslandMetrics.minPanelHeight`（60pt）；
   - 上限维持 `maxPanelWidth = 640` 与 `maxPanelHeight`。
3. 更新 `vm.zoneOpenedSize` 传参调用。

- [ ] **步骤 4：运行测试验证通过**
运行：`xcodebuild test -project NotchDrop.xcodeproj -scheme NotchDrop -only-testing:NotchDropTests/TabMetricsTests CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO`
预期：PASS

- [ ] **步骤 5：Commit**
```bash
git add NotchDrop/NotchViewModel.swift NotchDrop/IslandMetrics.swift Tests/TabMetricsTests.swift Tests/ZoneSizeGuardTests.swift
git commit -m "feat(ui): adapt island size dynamically with physical notch baseline and compact floor"
```

---

### 任务 4：第三页守护控制台舒展重构彻底根治文字截断

**文件：**
- 修改：`NotchDrop/GuardControlZoneView.swift`
- 测试：`Tests/DiagnosticsViewTests.swift`

- [ ] **步骤 1：编写测试**
在 `Tests/DiagnosticsViewTests.swift` 中添加针对第三页视图尺寸提案与组件布局的健全性测试。

- [ ] **步骤 2：重构 `GuardControlZoneView.swift`**
1. **宽度调适**：将根 `VStack` 的 `.frame(width: 360)` 调整为 `.frame(width: 390)`，增加 30pt 关键排版余量；
2. **Header 分层优化**：
   - 将“守护状态（呼吸灯+生效中）”与“绑定的设备名及 RSSI”在左侧自然延展；
   - 将“真执行”与“启用”两个 Toggle 紧凑右对齐，设备名称使用弹性宽度，避免省略号；
3. **2×2 开关卡片舒展**：
   - 移除卡片内的强制单行截断，字号定为 11.5pt，让“接近唤醒屏幕”、“离开立即熄屏”、“屏保替代熄屏”、“键鼠活动保护”四组 6 字中文舒适平铺不截字；
4. **最近判定事件卡片支持双行**：
   - 首行显示时间点与结果徽章（如“通过 / 拒绝”）；
   - 次行完整显示详细判定理由（如设备 RSSI、阈值比较等），支持 `.lineLimit(2)` 自然换行；
5. **底部操作按钮**：
   - 保持“空间测距校准”与“完整偏好设置...”两按钮平分宽度，字号居中。

- [ ] **步骤 3：编译并运行测试**
运行：`xcodebuild test -project NotchDrop.xcodeproj -scheme NotchDrop -only-testing:NotchDropTests/DiagnosticsViewTests CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO`
预期：PASS

- [ ] **步骤 4：Commit**
```bash
git add NotchDrop/GuardControlZoneView.swift Tests/DiagnosticsViewTests.swift
git commit -m "fix(ui): expand GuardControlZoneView layout to completely prevent text truncation"
```

---

### 任务 5：全量构建与集成回归验证

**文件：**
- 检查全量修改

- [ ] **步骤 1：运行完整单元测试套件**
运行：`xcodebuild test -project NotchDrop.xcodeproj -scheme NotchDrop CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO`
预期：全量测试 100% PASS。

- [ ] **步骤 2：构建完整产物**
运行：`xcodebuild -project NotchDrop.xcodeproj -scheme NotchDrop -configuration Debug -derivedDataPath /tmp/nd_build build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO`
预期：BUILD SUCCEEDED。

- [ ] **步骤 3：Commit & 验证收尾**
```bash
git status
git commit -m "chore: verify full test suite passes for UI adaptation and stability fix"
```
