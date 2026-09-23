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

## 4. 验证与测试用例

1. **单元测试**：
   - 5h 额度正常时：断言 `currentTier == .fiveHour`，取值来自 Claude 模型；
   - 5h 额度为 0 时：断言 `currentTier == .weekly`，取值自动切换为 Gemini 周模型；
   - 仅有周额度（无 5h 模型）时：平滑回退 `weekly`，不崩不空；
   - 倒计时格式化函数：验证 `4d12h`、`3h45m` 等格式正确。
2. **真机视觉走查**：
   - 检查 3D 账号环上 `5h` 与 `周额度` 胶囊徽章的对齐与色彩搭配。
