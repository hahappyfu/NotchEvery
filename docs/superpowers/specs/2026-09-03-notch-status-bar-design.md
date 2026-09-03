# NotchEvery 状态栏化（额度卡）设计规格

> 批准状态：用户已批准（2026-09-03，头脑风暴四节全过）
> 后续：实现阶段调用前端设计 skill 细化额度环视觉 → writing-plans 出实现计划

**目标：** NotchEvery 从单一文件暂存/隔空投送进化为刘海状态栏，首个状态小组件为 OpenCode Go 额度卡（5h/weekly/monthly 三窗口），鼠标悬停刘海即展开查看。

**架构：** 移植 EveryPlus 已验证的 `QuotaSnapshot.normalize` 纯函数 + 30s 轮询链路，新增 `QuotaStore` 单例；`NotchContentView.normal` 改为 `[QuotaCardView, TrayView]`；hover 触发从 `notchPop` 改为 `notchOpen(.hover)`；沙盒加 `temporary-exception` 放行 bridge 缓存只读。

**技术栈：** Swift 5 / SwiftUI + AppKit / Combine / App Sandbox / Liquid Glass（`glassCard` 封装）

---

## 1. 布局

### 1.1 面板结构（normal 态）

```
HStack(spacing: vm.spacing) {
    QuotaCardView(vm: vm)   // 新增，固定宽 ~180
    TrayView(vm: vm)        // 现有，占剩余宽度
}
```

- `ShareView`（AirDrop）从主行移出，收进 `NotchMenuView` 作为第四个 `GlassButton`（图标 `airplayaudio`，tint 系统蓝），复用现有菜单按钮样式与点击逻辑（`NSOpenPanel` 选择文件 → `Share.begin()`）。
- `notchOpenedSize` 保持 600×160 不变，额度卡固定宽，TrayView 自适应剩余。
- 额度卡只活在 `normal` 态；`menu`/`settings` 内容态照常全覆盖。

### 1.2 额度卡内部（结构定，视觉待细化）

```
VStack(alignment: .leading, spacing: 8) {
    HStack { "🛰 OpenCode Go" + Spacer + 状态圆点 }  // 绿=新鲜，琥珀=过期
    HStack { 5h% | 周% | 月% }                        // 三窗口横排
    底部小字：更新时间 / "已过期"                       // 次要色
}
```

- 纯展示：点击穿透，无 onTapGesture（已确认）。
- 表现形式（已确认）：**C · 主次分明**——5h 大圆环（数字居中）+ 右侧周/月小字两行 + 状态圆点。A（三圆环）/B（三横条）已否决。具体像素（环粗细、阈值配色、字体、间距、过期态样式）实现阶段调用前端设计 skill 细化后锁定。

## 2. 数据流

### 2.1 链路

```
~/.clawd/opencode-go-bridge-cache.json
  → QuotaStore.shared（新文件 NotchDrop/QuotaStore.swift，ObservableObject）
  → start()：启动即刷 + 30s Timer（RunLoop.common，后台 utility 队列读，主线程发布）
  → @Published snapshot: QuotaSnapshot
  → QuotaCardView 订阅渲染
```

### 2.2 移植清单（从 EveryPlus `Plugins/OpenCodeGo` 原样搬）

- `QuotaWindow` / `QuotaSnapshot` 模型 + `QuotaSnapshot.normalize(_:now:)`（含：`percent` 自算忽略缓存 bug 值、毫秒时间戳换算、非法值剔除、固定 `["5h","weekly","monthly"]` 顺序）。
- `publish(_:)` 决策语义：`data == nil` 返回 nil（保留旧快照不发布）。
- **不移植**：`QuotaDetailSnapshot`（modelRows/dailyCosts 明细，卡片用不上，YAGNI）。

### 2.3 无数据态（已确认：旧数据+过期标）

| 场景 | 显示 |
|------|------|
| 读到缓存 | 三窗口百分比 + 绿色圆点 + 更新时间 |
| 缓存过期（>10min）或后续读取失败 | 旧数字 + 琥珀色圆点 + "已过期"小字 |
| 首次启动即无数据 | `--%` 占位（抄 `QuotaNotchCardView`） |

### 2.4 沙盒

- entitlements 新增 `com.apple.security.temporary-exception.files.home-relative-path.read-only: [".clawd/"]`（只读，最小范围）。
- 若例外缺失导致拦读：行为等同"无数据"，卡片显示 `--%`，不弹窗（额度是辅助信息，不打断用户）。

## 3. Hover 状态机

### 3.1 触发变更（唯一改动点）

`NotchViewModel+Events.swift` 的 mouseLocation sink：

```swift
// 改前
if status == .closed, aboutToOpen { notchPop() }
// 改后
if status == .closed, aboutToOpen { notchOpen(.hover) }
```

- `OpenReason` 新增 `.hover`（与 click/drag/boot 并列，便于区分来源与后续埋点）。
- `popping` 状态保留，专供拖文件悬停预备态；拖拽链路（`dragDetector`/`dropTargeting`）不动。

### 3.2 防抖收起

- 收起条件不变（鼠标离开 `notchOpenedRect` → `notchClose()`），但加 0.15s 延迟 + 移回取消（`DispatchWorkItem` 模式），防止刘海→面板路径上的单帧误判导致闪烁。
- 加在现有 `$status/debounce` 管道旁，不动原有管道。

## 4. 错误处理与测试

1. 缓存解析失败 → 静默保留旧快照 + `os_log`，不弹窗。
2. 沙盒拦读 → 等同无数据（`--%`），不弹窗。
3. 文件中途删除/bridge 重启 → 下轮 30s 轮询自然恢复，无特殊处理。
4. 单测：`normalize` 四组（空输入/非法值/毫秒换算/percent 自算），抄 EveryPlus `QuotaColdTests` 用例，放入 `Tests/`（Task 8 已建占位）。
5. UI 无自动化测试，真机截图冒烟：hover 展开/三窗口数字/过期标/明暗外观。

## 5. 范围外（明确不做）

- 额度环最终视觉（实现阶段前端 skill 定）。
- 第二个状态小组件（网速/电池等）——C 方向的状态条架构本次不搭，QuotaCardView 写成独立视图，后续小组件行可复用其数据层。
- 跨进程向 EveryPlus 取数（方案 C，已否决）。
- Xcode target/源码目录重命名（私有化时已决：保持 `NotchDrop`）。
