# 账号池优化与 Qoder 每日自动签到功能设计规范

- **日期**：2026-09-21
- **状态**：待评审
- **相关组件**：`AntigravityStore`, `AntigravityAccountsCardView`, `QoderPoolRingView`, `QoderCampaignClaimer`, `QoderStore`

---

## 1. 背景与目标

当前刘海面板在使用过程中存在三个痛点：
1. **第一张卡片（Antigravity 账号卡）空间占用不合理**：
   - `accounts.json` 中被标记为 `proxy_disabled: true` 或已禁用的账号与正常可用账号混在同一排大卡片中，或者未正确过滤，浪费了顶部宝贵的 3D 聚光灯大卡空间。
   - **目标**：主排仅展示可用账号（居中 3D 聚光灯排列）；禁用账号移至主卡片下方的独立单行，以紧凑灰色小胶囊呈现。
2. **第三张卡片（Qoder 账号池）居左不美观**：
   - 当账号数量较少（如 1~4 个）时，由于缺乏全局弹性居中约束，整个 Orb 圆环列表紧贴卡片最左侧，与第一张卡片的居中视觉语言不统一。
   - **目标**：实现像第一张卡片一样的全局水平居中对齐，粘性中心号处于正中，其余两侧对称分布。
3. **Qoder 每日 100 Credits 领取耗时耗力**：
   - 官方自 2026 年 9 月 18 日起开启每日 100 Credits 签到活动，但需客户端手动点击，多账号池用户手动切换登录极为繁琐。
   - **目标**：通过已逆向验证的客户端接口协议，集成 `QoderCampaignClaimer`，在网关运行或 App 启动时自动扫描池内账号，静默巡检并完成签到，Credits 直接到账个人资源包（Add-on Credits）。

---

## 2. 架构设计与模块划分

### 模块 A：Antigravity 账号数据与卡片分层重构
1. **数据层修正 (`AntigravityStore.swift`)**：
   - `parseIndex` 时解析 `accounts.json` 顶层的 `accounts` 列表对象，提取每个账号的 `disabled` 与 `proxy_disabled` 字段字典映射 `[String: (disabled: Bool, proxyDisabled: Bool)]`。
   - 在 `loadAccounts` 解析单文件后，优先以 `accounts.json` 中的 `proxy_disabled` / `disabled` 为权威事实来源，正确赋值 `AntigravityAccount.isDisabled` 和 `isProxyDisabled`。
2. **视图层分层 (`AntigravityAccountsCardView.swift`)**：
   - **主排（活跃账号）**：`activeAccounts = store.accounts.filter { !$0.isDisabled }`，经过 `symmetricRearrange` 渲染 3D 聚光灯大卡。
   - **下排（禁用账号）**：若 `disabledAccounts = store.accounts.filter { $0.isDisabled }` 非空，在下方新起一个紧凑行：
     - 水平排列紧凑小胶囊（灰暗底色、半透明小圆点、8.5pt 名称缩略、弱化边框）。
     - 点击禁用胶囊可直接弹窗提示或切换启用（或仅展示）。

### 模块 B：Qoder 账号池 Orb 居中排布
1. **视图层改造 (`QoderPoolRingView.swift`)**：
   - 修改 `membersRow` 的外层容器，增加 `.frame(maxWidth: .infinity, alignment: .center)`。
   - 保持中心 Orb（distance = 0，粘性账号）位于正中心，左翼与右翼 Orb 对称展开。
   - 保证 1 个、2 个或更多账号时，在 360pt 卡片内绝对水平居中。

### 模块 C：Qoder 每日 Credits 自动签到器 (`QoderCampaignClaimer.swift`)
1. **协议规范**：
   - **请求头**：
     - `Authorization: Bearer <access_token>`
     - `Cosy-ClientType: 10`
     - `Cosy-Version: 0.1.18`
     - `Cosy-MachineOS: darwin`
     - `Cosy-MachineId: <auth.machine_id>`
     - `User-Agent: Qoder`
   - **接口 1（查可领活动）**：
     - `GET https://openapi.qoder.com.cn/sash/api/v1/me/campaigns`
     - 响应体过滤：`campaigns` 数组中 `actionType == "CLAIM_BENEFIT" && claimStatus == "CLAIMABLE"`。
   - **接口 2（执行领取）**：
     - `POST https://openapi.qoder.com.cn/sash/api/v1/me/campaigns/<campaignId>/claim`
     - Body: `{}`
     - 成功响应：`status: "CLAIMED", benefit.amount: 100`。
2. **调度策略**：
   - 触发时机：
     - `QoderStore.start()` / 网关每次启动成功时自动触发一次异步巡检。
     - 每日定时轮询（在面板展开或后台心跳时，若跨越当日 10:00 UTC+8 刷新窗口则自动触发）。
   - 状态追踪与防重：
     - 内存记录每日已成功领取的账号 ID 与时间，当天成功后不再重复请求。

---

## 3. 测试与验证策略

1. **单元测试**：
   - `AntigravityStoreTests`：测试 `accounts.json` 中 `proxy_disabled: true` 正确覆盖单账号 json。
   - `AntigravityAccountsCardViewTests`：测试活跃账号排布与禁用账号列表拆分逻辑。
   - `QoderCampaignClaimerTests`：使用 MockTransport 验证活动过滤与领取请求组装。
2. **真机集成验证**：
   - 检查 NotchEvery 展开面板第一张卡：正常账号 3D 居中，禁用账号作为小胶囊整齐停在下排。
   - 检查第三张卡：账号池 Orb 在卡片中完全水平居中。
   - 检查 Qoder 用量：自动签到触发后，Add-on Credits 成功到账并正常刷新用量。
