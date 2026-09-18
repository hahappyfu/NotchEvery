# 隐藏禁止反代与不可用账号卡片 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 subagent-driven-development（推荐）或 executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 在第一页 Antigravity 账号池 3D 环形卡片中，自动过滤隐藏标记为禁止反代（`proxy_disabled`）或已禁用的账号，使可用反代账号优先展示且不被无用卡片占用空间。

**架构：**
1. 数据模型层：在 `AntigravityStore.swift` 中解析并暴露 `isProxyDisabled` 属性，保持 `isDisabled = (disabled == true) || (proxy_disabled == true)` 作为综合可用性标记。
2. 视图编排层：在 `AntigravityAccountsCardView.swift` 中，编排前过滤出可用账号（`filter { !$0.isDisabled }`），仅对可用账号执行对称重排算法；若可用列表为空则展示“暂无可用反代账号”提示。
3. 单元测试层：在 `Tests/AntigravityStoreTests.swift` 中覆盖解析逻辑与重排过滤测试，确保老功能不回退。

**技术栈：** Swift 5.9, SwiftUI, XCTest, macOS 14+

---

## 全局约束

- 宽度固定 360pt，不得破坏灵动岛面板定宽。
- 单元测试使用现有的 `swift test --filter AntigravityStoreTests` 验证。
- 严格遵循 TDD 流程：先写失败测试，后写实现，再跑通验证。

---

### 任务 1：扩展数据模型与解析支持 `proxy_disabled`

**文件：**
- 修改：`NotchDrop/AntigravityStore.swift:18-47`
- 修改：`NotchDrop/AntigravityStore.swift:288-341`
- 测试：`Tests/AntigravityStoreTests.swift`

- [ ] **步骤 1：编写失败的单元测试**

在 `Tests/AntigravityStoreTests.swift` 中新增测试用例 `testParseAccountWithProxyDisabled`：

```swift
    func testParseAccountWithProxyDisabled() throws {
        let jsonStr = """
        {
          "id": "test-account-proxy-disabled",
          "name": "禁止反代账号",
          "email": "banned@example.com",
          "disabled": false,
          "proxy_disabled": true,
          "quota": {
            "models": [
              {
                "name": "gemini-3.1-pro-high",
                "percentage": 50,
                "reset_time": "2026-09-18T15:30:00Z"
              }
            ]
          }
        }
        """
        let data = jsonStr.data(using: .utf8)!
        let account = try XCTUnwrap(AntigravityStore.parseAccountFile(data: data, currentAccountId: nil))

        XCTAssertEqual(account.id, "test-account-proxy-disabled")
        XCTAssertTrue(account.isProxyDisabled)
        XCTAssertTrue(account.isDisabled)
    }
```

- [ ] **步骤 2：运行测试验证失败**

运行：`swift test --filter AntigravityStoreTests/testParseAccountWithProxyDisabled`
预期：编译报错或失败（`Value of type 'AntigravityAccount' has no member 'isProxyDisabled'`）

- [ ] **步骤 3：编写实现代码**

在 `NotchDrop/AntigravityStore.swift` 中：
1. 为 `AntigravityAccount` 增加 `public let isProxyDisabled: Bool` 并在 `init` 中赋值。
2. 在 `parseAccountFile` 中提取 `let isProxyDisabled = (raw.proxy_disabled == true)` 并传入构造器。

```swift
public struct AntigravityAccount: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let email: String
    public let isCurrent: Bool
    public let isDisabled: Bool
    public let isProxyDisabled: Bool
    public let percentage: Int
    public let resetTime: Date?
    public let lastActiveTime: Date?

    public init(
        id: String,
        name: String,
        email: String,
        isCurrent: Bool,
        isDisabled: Bool,
        isProxyDisabled: Bool = false,
        percentage: Int,
        resetTime: Date?,
        lastActiveTime: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.email = email
        self.isCurrent = isCurrent
        self.isDisabled = isDisabled
        self.isProxyDisabled = isProxyDisabled
        self.percentage = percentage
        self.resetTime = resetTime
        self.lastActiveTime = lastActiveTime
    }
}
```

并在 `parseAccountFile` 中：
```swift
        let isProxyDisabled = (raw.proxy_disabled == true)
        let isDisabled = (raw.disabled == true) || isProxyDisabled
```
并将 `isProxyDisabled: isProxyDisabled` 传给 `AntigravityAccount` 初始化。

- [ ] **步骤 4：运行测试验证通过**

运行：`swift test --filter AntigravityStoreTests`
预期：PASS

- [ ] **步骤 5：Commit**

```bash
git add NotchDrop/AntigravityStore.swift Tests/AntigravityStoreTests.swift
git commit -m "feat(antigravity): expose isProxyDisabled flag on AntigravityAccount"
```

---

### 任务 2：在 AntigravityAccountsCardView 中过滤隐藏禁止反代及已禁用账号

**文件：**
- 修改：`NotchDrop/AntigravityAccountsCardView.swift:125-145`
- 测试：`Tests/AntigravityStoreTests.swift`

- [ ] **步骤 1：编写失败的单元测试**

在 `Tests/AntigravityStoreTests.swift` 中新增测试 `testSymmetricRearrangeExcludesDisabledAccounts`：

```swift
    func testSymmetricRearrangeExcludesDisabledAccounts() {
        let acc1 = AntigravityAccount(id: "acc-ok-1", name: "OK1", email: "1@ok.com", isCurrent: false, isDisabled: false, percentage: 80, resetTime: nil)
        let acc2 = AntigravityAccount(id: "acc-disabled", name: "Banned", email: "2@ban.com", isCurrent: false, isDisabled: true, isProxyDisabled: true, percentage: 90, resetTime: nil)
        let acc3 = AntigravityAccount(id: "acc-ok-2", name: "OK2", email: "3@ok.com", isCurrent: true, isDisabled: false, percentage: 60, resetTime: nil)

        let arranged = AntigravityAccountsCardView.arrangedAccounts(from: [acc1, acc2, acc3])
        XCTAssertEqual(arranged.count, 2)
        XCTAssertFalse(arranged.contains(where: { $0.account.id == "acc-disabled" }))
        XCTAssertEqual(arranged.first(where: { $0.logicalDistance == 0 })?.account.id, "acc-ok-2")
    }
```

- [ ] **步骤 2：运行测试验证失败**

运行：`swift test --filter AntigravityStoreTests/testSymmetricRearrangeExcludesDisabledAccounts`
预期：FAIL（方法 `arrangedAccounts(from:)` 未定义或未进行过滤）

- [ ] **步骤 3：编写实现代码**

在 `NotchDrop/AntigravityAccountsCardView.swift` 中：
1. 提取可测试的静态函数：
```swift
    public static func arrangedAccounts(from accounts: [AntigravityAccount]) -> [(account: AntigravityAccount, logicalDistance: Int)] {
        let activeAccounts = accounts.filter { !$0.isDisabled }
        guard !activeAccounts.isEmpty else { return [] }
        return symmetricRearrange(accounts: activeAccounts)
    }
```
2. 更新 `accountsRow` 调用 `Self.arrangedAccounts(from: store.accounts)`：
```swift
    private var accountsRow: some View {
        let arranged = Self.arrangedAccounts(from: store.accounts)
        return HStack(spacing: 6) {
            if arranged.isEmpty {
                Text("暂无可用反代账号")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.white.opacity(0.4))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                ForEach(arranged, id: \.account.id) { item in
                    accountCard(item.account, distance: item.logicalDistance)
                }
            }
        }
        .animation(reduceMotion ? nil : StudioAnimation.interactiveSpring, value: arranged.map(\.account.id))
    }
```

- [ ] **步骤 4：运行测试验证通过**

运行：`swift test --filter AntigravityStoreTests`
预期：所有 AntigravityStoreTests 用例全部 PASS。

- [ ] **步骤 5：Commit**

```bash
git add NotchDrop/AntigravityAccountsCardView.swift Tests/AntigravityStoreTests.swift
git commit -m "feat(ui): automatically hide disabled and proxy-disabled accounts from first page"
```

---

### 任务 3：全量单元测试与回归验收

**文件：**
- 测试：全量测试套件

- [ ] **步骤 1：运行全量单元测试**

运行：`swift test`
预期：所有现有测试用例全部 PASS，无任何回归错误。

- [ ] **步骤 2：记录结果与确认状态**

确认 `git status` 无遗留脏文件。
