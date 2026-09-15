# 灵动岛 UI 深度打磨与 Antigravity 3D 众星捧月舞台设计规格

- **日期**：2026-09-15
- **分类**：架构级（Architectural）UI/UX 重塑
- **范围**：
  1. `AntigravityAccountsCardView.swift`：3D 环形立体聚焦舞台（众星捧月）+ 倒计时紧凑格式化
  2. `AntigravityStore.swift`：切换活跃账号持久化与倒计时格式化函数升级
  3. `TokenZoneView.swift`：顶部 KPI 摘要栏两行排版修复（消除文字横向坍塌）
  4. `GuardCardView.swift` & `GuardControlZoneView.swift`：双开关文案分立解耦 + 顶栏防挤压

---

## 1. 背景与核心诉求

通过真机运行验收，发现当前界面存在以下 4 处亟待解决的视觉与交互缺陷：
1. **账号卡片平铺呆板**：5 张账号卡平铺无主次，用户期望实现「正在使用的账号居中突出、两侧向内环抱」的「众星捧月」3D 空间立体感。
2. **账号倒计时溢出截断**：长周期倒计时（如 `149h...`）在卡片底部徽章中被省略截断。
3. **双开关无独立文案标签**：首页与第三页右上角并排出现 `真执行 [开关1] [开关2]`，用户无法理解第二个开关的含义（实为守护主开关 `store.enabled`）。
4. **Token 摘要栏文字严重挤压**：`summaryBar` 内部嵌套错误，导致原本的双行内容被硬塞进单行，Tokens、命中率、进度条、更新时间全挤在一起溢出。
5. **第三页顶栏空间狭窄截断**：设备名称 `Apple Watc...` 挤在状态与双开关中间，频繁触发省略号。

---

## 2. 模块 1：Antigravity 账号池 3D 众星捧月环形舞台

### 2.1 数据重排算法（Symmetric Re-indexing）
无论当前活跃账号（`isCurrent == true`）位于原始数组的哪个位置，UI 层将其重排为以当前账号为正中心的 5 元素对称序列：

- **排序逻辑**：
  1. 找出当前活跃账号 `currentAccount`。
  2. 将其余账号按照 `percentage`（剩余配额）降序排序。
  3. 按照 `[次高, 最高, 当前活跃(中心), 第三高, 最低/禁用]` 的顺序重排，得到展示数组。
  4. 计算每张卡片相对中心焦点的逻辑距离 `d = index - centerIndex`（`d ∈ {-2, -1, 0, 1, 2}`）。

### 2.2 3D 空间变换与光影阶梯

每个卡片依据逻辑距离 `d` 赋予原生 Metal/CoreAnimation 硬件加速变换：

| 维度 | 两侧外翼 (`|d| = 2`) | 次翼 (`|d| = 1`) | 中央焦点 (`d = 0`, 正在使用) |
| :--- | :--- | :--- | :--- |
| **3D Y轴偏转角** | `±22°`（向中心内收） | `±12°`（微偏向内） | **`0°`（正对屏幕，无扭曲）** |
| **透视比率 (perspective)** | `0.45` | `0.45` | `0.45` |
| **缩放比例 (scaleEffect)** | `0.88` | `0.95` | **`1.08`（显著凸显）** |
| **Y 轴浮空位移** | `offset(y: 0)` | `offset(y: -1)` | **`offset(y: -3)`（上浮突破基线）** |
| **层级 (zIndex)** | `0` | `1` | **`3`（完全浮于两侧上方）** |
| **空间阴影 (shadow)** | 极弱 (`radius: 3, opacity: 0.15`) | 柔和 (`radius: 5, opacity: 0.25`) | **深景深浮空 (`radius: 12, y: 6, opacity: 0.55`)** |
| **光影衰减 (brightness)** | 压暗 20% (`-0.20`) | 压暗 10% (`-0.10`) | **100% 原始高亮 + 底部翡翠绿微光晕** |
| **外框描边** | 普通卡片描边 | 普通卡片描边 | **微光边框 (`StudioColor.emerald.opacity(0.4)`)** |

### 2.3 交互点击与丝滑切换
- 点击任意非中心卡片：
  - 调用 `AntigravityStore.shared.selectAccount(id:)` 切换活跃账号（写入 `~/.antigravity_tools/accounts.json` 的 `current_account_id`）。
  - 配合 SwiftUI `.animation(.spring(response: 0.38, dampingFraction: 0.8), value: store.currentAccountId)`，被点击的卡片平滑滑入中央并放大变正，原中心卡片转体缩小退居侧翼。

### 2.4 倒计时紧凑格式化
- 升级 `AntigravityStore.formatCountdown(from:resetTime:)`：
  - `hours >= 48`：格式化为天数 `\(hours / 24)d\(hours % 24)h`（如 `6d5h`，仅 4 字符）。
  - `24 <= hours < 48`：格式化为 `\(hours)h`（如 `36h`）。
  - `hours < 24`：保持 `\(hours)h\(minutes)m`。
- 卡片徽章字号设为 9.5pt，并添加 `.minimumScaleFactor(0.75)`，彻底根除 `149h...` 截断。

---

## 3. 模块 2：双开关文案分立解耦与顶栏防挤压

### 3.1 明确双开关独立标签
在 `GuardCardView.swift` 和 `GuardControlZoneView.swift` 中，将并排两个开关彻底解耦为两个独立的带标签组：

```swift
HStack(spacing: 10) {
    // 开关 1：守护功能总开关
    HStack(spacing: 4) {
        Text("守护")
            .font(.system(size: 11))
            .foregroundStyle(Color.white.opacity(0.52))
        Toggle("", isOn: $store.enabled)
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
    }

    // 开关 2：真实锁屏/解锁执行开关
    HStack(spacing: 4) {
        Text("真执行")
            .font(.system(size: 11))
            .foregroundStyle(Color.white.opacity(0.52))
        Toggle("", isOn: $store.realExecution)
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
    }
}
```

### 3.2 第三页顶栏布局防截断
- 第三页（`GuardControlZoneView.swift`）的设备信息与 RSSI 在刘海右耳（`rightEarPill`）中已有完整常驻展示。
- 顶栏精简为两端对齐：
  - 左侧：`● 守护控制 · 生效中`（呼吸动画）
  - 中间：`Spacer()`
  - 右侧：`守护 [开关]  真执行 [开关]`
- 彻底消除中间设备名被左右两侧夹击截断为 `Apple Watc...` 的丑态。

---

## 4. 模块 3：TokenZoneView 顶部 KPI 摘要栏布局修复

### 4.1 根本原因修复
在 `TokenZoneView.swift` 中，`summaryBar` 内部嵌套层级错乱，第二行的两端内容被错误放进了第一行的 `HStack` 中。

### 4.2 正确的两行结构
```swift
VStack(spacing: 8) {
    // 第 1 行：Tokens 总量 (左) <---> 缓存命中率及进度条 (右)
    HStack(alignment: .firstTextBaseline) {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Tokens")
                .font(.system(size: 10, weight: .medium))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            RollupText(text: store.summary.totalTokens, font: .system(size: 19, weight: .bold, design: .rounded))
        }
        Spacer()
        HStack(spacing: 8) {
            Text("缓存命中率")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            RollupText(text: store.summary.cacheRate, font: .system(size: 14, weight: .bold, design: .rounded), color: StudioColor.emerald)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(StudioColor.emerald.opacity(0.2))
                    .frame(width: 64, height: 4)
                Capsule()
                    .fill(StudioColor.emerald.opacity(0.9))
                    .frame(width: 64 * min(1, max(0, store.cacheRateFraction)), height: 4)
            }
            .offset(y: -1)
        }
    }

    // 第 2 行：详细命中 token 数 (左) <---> 更新时间 (右)
    HStack {
        Text("缓存命中 \(UsageStore.formatTokens(store.footer.cacheReadTotal))")
        Spacer()
        Text("更新于 \(footerTimeText)")
    }
    .font(.system(size: 10))
    .foregroundStyle(.tertiary)
}
```
恢复舒展大气的 Apple Native Studio 工业级质感，彻底消除挤压变形。

---

## 5. 验证与验收标准

1. **首页 3D 众星捧月**：
   - 正在使用的账号永远居中，放大 1.08x，带有高光与浮空投影。
   - 两侧卡片向内微倾斜角度（±12°、±22°），呈现舞台环抱感。
   - 点击任意侧翼卡片，卡片旋转滑入中心，完成活跃账号切换。
   - 「傅曜曜」等超长倒计时显示为 `6d5h` 等紧凑格式，无 `...` 截断。
2. **双开关文案清晰**：
   - 首页卡片与第三页控制台均显示 `守护 [开关]  真执行 [开关]`，每个开关含义一目了然。
3. **Token 摘要栏排版工整**：
   - 第一行左侧 Tokens、右侧命中率百分比与进度条；
   - 第二行左侧具体命中量、右侧更新时间，左右呼应，无截断无挤压。
4. **全量测试通过**：
   - 所有已有单元测试（417+）保持 100% PASS。
