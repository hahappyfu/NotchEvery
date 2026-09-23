# 第一页配额展示升级：5h 额度优先与耗尽自动切换周额度设计规格

## 1. 需求背景与痛点

当前 NotchEvery 第一页展示的 Antigravity 账号配额默认优先提取了 `gemini` 模型的指标，其重置周期通常为 7 天或多日（周额度），导致用户日常高频使用的 5 小时短周期（Claude / GPT）额度无法直观感知。

用户诉求：
1. 默认优先展示 5 小时短周期额度（5h）；
2. 当 5h 额度耗尽（0% 或触发限流）时，自动无缝切换为周额度显示，并呈现周重置倒计时；
3. UI 界面有明确清晰的视觉标识（显示“周额度”徽标），避免用户混淆当前周期的口径。

---

## 2. 数据层设计（`AntigravityStore.swift`）

### 2.1 配额层级分类
解析账号模型列表（`quota.models`）时，将模型划分为两大层级：

1. **短周期池（5h Quota）**：
   - 模型筛选：优先匹配 `claude-*`（如 `claude-sonnet-4-6`、`claude-opus-*`），或重置时间在 5.5 小时以内的模型。
   - 提取字段：`fiveHourPercentage: Int?`，`fiveHourResetTime: Date?`。
2. **长周期池（Weekly Quota）**：
   - 模型筛选：匹配 `gemini-*` 系列或重置周期在 24 小时以上的多日/周模型。
   - 提取字段：`weeklyPercentage: Int`，`weeklyResetTime: Date?`。

### 2.2 自动切换状态机（`QuotaTier`）
```swift
public enum QuotaDisplayTier: String, Equatable {
    case fiveHour // 正在展示 5h 短期额度
    case weekly   // 5h 耗尽，降级展示周额度
}

extension AntigravityAccount {
    /// 当前生效展示的配额层级
    public var currentTier: QuotaDisplayTier {
        guard let fiveHourPct = fiveHourPercentage else {
            return .weekly
        }
        // 当 5h 额度大于 0 时，优先展示 5h 额度；耗尽 (<= 0) 时自动降级为周额度
        return fiveHourPct > 0 ? .fiveHour : .weekly
    }

    /// 供给圆环显示的当前百分比
    public var displayPercentage: Int {
        currentTier == .fiveHour ? (fiveHourPercentage ?? 0) : weeklyPercentage
    }

    /// 供给底部显示的倒计时重置时间
    public var displayResetTime: Date? {
        currentTier == .fiveHour ? fiveHourResetTime : weeklyResetTime
    }
}
```

---

## 3. UI 视觉表现设计（`AntigravityAccountsCardView.swift`）

1. **5h 正常展示态**：
   - 圆环百分比：显示 5h 额度（如 `95%`）；
   - 底部文字：显示 5h 重置倒计时（如 `4h12m`）；
   - 微标：姓名旁或圆环右上角显示沉稳低调的 `5h` 微标。

2. **自动切换为周额度态**：
   - 明确视觉提示：圆环右上角或卡片顶部亮起精致小巧的琥珀色胶囊微标：`周额度`；
   - 圆环百分比：自动切换显示该账号的周额度剩余（如 `24%`）；
   - 底部倒计时：明确格式化为天级/多日倒计时，带清晰说明（如 `周重置 4d2h` 或 `重置 98h`），让用户对何时迎来大周期刷新一目了然。

---

## 4. 第三页网关缓存命中率计算修正（`QoderLogParser.swift`）

### 4.1 根因与口径偏差
- **现状缺陷**：`QoderDailyAgg.cacheRateFraction` 当前公式写为：
  ```swift
  let denom = tokensIn + cached
  return denom > 0 ? Double(cached) / Double(denom) : 0
  ```
- **真实日志事实**：`gateway.log` 中网关输出格式为：
  `remote usage model=dfmodel in=63126 out=269 cached=62208 total=63395`
  数值关系满足 $63126 + 269 = 63395$（$in + out = total$），证明 `in` 已经是**包含已缓存部分的完整输入 Tokens**。
- **误差量级**：原有公式在分母上把 `cached` 又累加了一次，导致实际命中率 98.5% 被错误稀释为 49.6%，直接腰斩。

### 4.2 修正公式
将 `NotchDrop/QoderLogParser.swift` 中 `cacheRateFraction` 统一修正为业界标准口径（与第二页 Token 专区对齐）：
```swift
var cacheRateFraction: Double {
    tokensIn > 0 ? min(1.0, max(0.0, Double(cached) / Double(tokensIn))) : 0
}
```

---

## 5. 剪贴板专区交互与体验加固（`ClipboardZoneView.swift` & `ClipboardPaster.swift`）

### 5.1 图片一次性粘贴成功保障
- **痛点根因**：
  1. 激活外部目标应用时，复杂应用（如微信、VSCode 等）从后台换到前台完成焦点接管通常需要 80~120ms，原先 60ms 延迟注入 Cmd+V 过早，导致第一次按键被吞，第二次目标应用已在前台才能成功；
  2. 剪贴板写回时仅写入 `NSImage` 对象，缺少某些应用强制检查的 `public.png` 二进制数据层。
- **加固方案**：
  1. `ClipboardPaster` 写回图片时，同时提供 `public.png` 原生数据与 `NSImage`，达到 100% 格式兼容；
  2. 将按键注入延迟平滑放宽至 `0.12s`（120ms），给宿主窗口充分的焦点响应窗口，确保**单次点击必达 100% 成功注入**。

### 5.2 内联清空确认（消灭系统弹窗遮挡）
- **痛点根因**：调用系统 `NSAlert` 模态框位于屏幕中央，而刘海处于 `level = .statusBar + 8` 置顶层，正好把系统弹窗上半部遮挡，既遮挡又打断操作流程。
- **全新方案（原地内联确认）**：
  - 彻底干掉 `NSAlert` 系统弹窗；
  - 点击「清空」时，顶栏右侧原地平滑展开为 `[ 确认清空 ] [ 取消 ]` 的紧凑胶囊按钮组合；
  - 点击「确认清空」即执行清空，点击「取消」或 3 秒无操作自动收缩复位。零遮挡、零打扰、防误触。

### 5.3 多条内容置顶（Pin）功能
- **功能设计**：
  - 数据模型：`ClipboardItem` 新增 `isPinned: Bool`，随本地 JSON 永久持久化；
  - 排序逻辑：置顶条目始终浮在列表最顶端（多条置顶按时间排），非置顶条目在其下方按时间流排列；
  - 免死金牌淘汰保护：当历史条目达到 50 条触发 FIFO 淘汰时，**所有置顶项绝对豁免**，只淘汰最老的未置顶条目；
  - UI 交互：鼠标悬停在卡片上时右侧出现微型图钉（📌），点击切换置顶态，置顶后图钉常驻高亮显示，并伴随一次轻微的齿轮卡嗒触感。

---

## 6. 验证与测试用例

1. **第一页 5h / 周额度切换**：
   - 单元测试覆盖 5h > 0% 展示 5h、5h == 0% 自动降级为 weekly；
   - 倒计时字符串覆盖天级与小时级格式。
2. **第三页缓存命中率修复**：
   - `QoderLogParserTests`：断言 `cacheRateFraction` 恢复为 `cached / tokensIn`。
3. **剪贴板体验加固与置顶**：
   - `ClipboardStoreTests`：测试 `isPinned` 置顶排序置顶优先；
   - `ClipboardStoreTests`：测试 50 条淘汰时置顶项不被淘汰；
   - `ClipboardPasterTests`：测试写入图片时同时包含 png 数据与 NSImage。

