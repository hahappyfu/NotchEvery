# 规格设计：NotchEvery 全量配置外置与统一 JSON 持久化

- **日期**：2026-09-16
- **状态**：Draft -> Pending Review
- **目标**：将应用的所有核心配置、偏好设置和托盘数据从原先分散的 `UserDefaults` 及本地 Documents 目录，外置迁移至用户主目录下的 `~/.notchevery/` 目录中统一以 `config.json` 维护，实现打包重装或多版本迭代后配置永不丢失、免重复配置。

---

## 1. 背景与现状分析

### 1.1 现状问题
1. **近场守护（FUnlock / Guard）配置分散**：
   - 目前近场守护配置保存在 `UserDefaults(suiteName: "com.hahappyfu.NotchEvery.guard")` 中（实际对应 `~/Library/Preferences/com.hahappyfu.NotchEvery.guard.plist`）。
   - 在应用卸载、使用 AppCleaner 或换环境时，plist 极易被清理；且 plist 依赖 macOS 缓存服务 `cfprefsd`，用户无法直接便捷地检视、编辑和备份配置。
2. **UI 偏好与托盘设置分散**：
   - 触觉反馈（`hapticFeedback`）、语言设置（`selectedLanguage`）及托盘保存周期由 `FileStorage` 散落存放在 `~/Documents/NotchEvery/Config/` 下的多个小文件中。
   - 文件碎片化严重，不直观且容易被文稿清理工具误删。
3. **用户痛点**：
   - 应用每次重新打包（Release 构建）或覆盖重装时，容易导致设备重新绑定（Apple Watch 识别丢弃）、距离阈值重置，需要重新扫码配置，严重影响用户体验。

### 1.2 预期成果
- 所有核心配置集中在 `~/.notchevery/config.json`，纯文本 JSON，结构分明，方便人类阅读、版本管理与机器读写。
- 应用启动时自动从历史 `UserDefaults` 和旧 `Documents` 中读取现有有效配置并平滑导入 `config.json`，不丢失当前 Watch 绑定和所有 RSSI 阈值。
- 业务代码（守护状态机 `FUn.swift`、设置页 `PreferencesWindow.swift`、托盘 `TrayDrop.swift` 等）API 保持高度兼容，不引入侵入式大重构。

---

## 2. 目录与存储结构设计

### 2.1 外部根目录
所有应用外置资产统一托管在：
```text
~/.notchevery/
├── config.json           # 核心统一配置文件（权限 0600）
├── TrayDrop/             # 托盘暂存文件与缩略图存储（权限 0700）
└── ProcessIdentifier     # 单例运行检测锁文件（原 ~/Documents/NotchEvery/ProcessIdentifier 迁出）
```

### 2.2 `config.json` 架构规范
文件采用分命名空间层级结构，但保持简单的扁平字典映射，方便扩展：
```json
{
  "guard": {
    "enabled": true,
    "device": "9110EB8B-C17C-44A5-9B18-D092B0CD9E00",
    "deviceName": "Apple Watch Series 7",
    "lockRSSI": -70,
    "unlockRSSI": -60,
    "wakeAdvance": 20,
    "wakeOnProximity": true,
    "preUnlockTrigger": false,
    "lockOnIdle": true,
    "sleepDisplay": false,
    "screensaver": true,
    "iMessageNotify": true,
    "iMessageNotifyRecipient": "+8615167104090",
    "manualLockNoAutoUnlock": false,
    "unlockMargin": 3,
    "realExecution": true,
    "permAck_ax": true,
    "permAck_fullDisk": true
  },
  "preferences": {
    "hapticFeedback": true,
    "selectedLanguage": "zh-Hans",
    "hasSeenSwipeHint": true,
    "launchAtLogin": true
  },
  "tray": {
    "keepInterval": 86400,
    "selectedFileStorageTime": "1 Day",
    "customStorageTime": 1,
    "customStorageTimeUnit": "Days"
  }
}
```

---

## 3. 架构调整与组件设计

### 3.1 路径基础设施 `AppPaths.swift`
- `documentsDirectory` 统一定向为 `~/.notchevery`。
- 如果目标目录不存在，由应用在启动时同步创建（权限 `0700`）。
- `configDir` 指向 `~/.notchevery/`，配置文件固定为 `~/.notchevery/config.json`。
- 托盘文件与预览图存储统一迁移至 `~/.notchevery/TrayDrop/`。

### 3.2 统一配置引擎 `ConfigStore.swift`
重构 `ConfigStore` 内部实现，将其存储后端从 `UserDefaults` 切换为文件驱动的原子 JSON 存储：
1. **线程安全与并发控制**：
   - 内部维护内存数据结构（`[String: Any]` 或层级字典），使用 `NSLock` 保护并发读写。
   - 写操作触发原子化落盘（`atomic write` 临时文件 + rename），写入使用 `JSONSerialization` 并开启 `.prettyPrinted` 与 `.sortedKeys`，格式整齐可读。
2. **API 兼容层**：
   保留原有所有对外方法：
   - `get(_:fallback:) -> Int`
   - `get(_:fallback:) -> Bool`
   - `get(_:fallback:) -> String`
   - `set(_:forKey:)`
   - `removeObject(forKey:)`
   - `object(forKey:) -> Any?`
   - `bool(forKey:) -> Bool`
   - `string(forKey:) -> String?`
   业务层代码如 `FUn.swift`、`FUnManager.swift`、`GuardControlZoneView.swift` 无需修改任何调用方语法。
3. **分段键路径（Keypath Mapping）与扁平回退**：
   - 支持直接传入顶级 key（如 `"device"`）自动映射到对应 section（如 `"guard.device"`）；
   - 或者内部保持以 `"guard"`、`"preferences"`、`"tray"` 分组的层级字典，对外查询时优先在所属分组中查找，未分组则查根级，实现 100% 透明兼容。

### 3.3 平滑导入与迁移策略（首次启动）
首次启动检测机制：
1. 若 `~/.notchevery/config.json` **已经存在**：
   - 直接读取并加载，跳过迁移，严格信任外部 JSON 配置。
2. 若 `~/.notchevery/config.json` **不存在**：
   - **读取旧 Guard 配置**：从 `UserDefaults(suiteName: "com.hahappyfu.NotchEvery.guard")` 读取所有的键值（包括 `device`, `deviceName`, `lockRSSI`, `unlockRSSI`, `iMessageNotifyRecipient` 等）。
   - **读取旧 Preferences 配置**：从 `~/Documents/NotchEvery/Config/` 读取 `hapticFeedback`、`selectedLanguage` 等文件。
   - **聚合生成**初始 `config.json` 并原子写入 `~/.notchevery/config.json`。
   - 历史文件保留不破坏，确保双向安全。

### 3.4 偏好面板交互 `PreferencesWindow.swift` & `PublishedPersist.swift`
- `FileStorage`（或直接使用 `ConfigStore.shared`）底层读写直接对接 `~/.notchevery/config.json` 中的 `"preferences"` / `"tray"` 节点。
- `PreferencesWindow` 中的 `hapticFeedback`、`selectedLanguage`、`launchAtLogin` 等通过 `ConfigStore` 集中持久化，不再生成零碎小文件。

---

## 4. 错误处理与鲁棒性考量

1. **JSON 解析失败容错**：
   - 若用户手工编辑 `config.json` 产生了语法错误，`ConfigStore` 捕获反序列化异常并备份损坏文件为 `config.json.corrupt.<timestamp>`，日志报警并回退至安全默认值，避免 App 启动崩溃。
2. **磁盘写入失败**：
   - 落盘过程发生 I/O 错误时记录 `os_log`，内存缓存仍保持最新状态，并在下次修改时重试落盘。
3. **单例与锁文件**：
   - `ProcessIdentifier` 文件由 `main.swift` 在启动时创建、`applicationWillTerminate` 退出时清理，全部统一收拢在 `~/.notchevery/` 下。

---

## 5. 验证标准（Definition of Done）

1. **单元测试通过**：
   - 编写 `ConfigStoreJSONBackendTests`，验证：
     - 空配置新建与默认值填充；
     - 读写类型安全（Int, Bool, String）；
     - 原子落盘及重新构造从磁盘加载的持久化一致性；
     - 从 `UserDefaults` 旧数据的自动迁移准确性。
   - 全量 438+ 现有单元测试零失败。
2. **实际运行验证**：
   - 启动应用，检查 `~/.notchevery/config.json` 自动生成，且包含当前已配对的 Apple Watch 设备与阈值。
   - 在设置面板中修改振动开关或守护阈值，确认 `~/.notchevery/config.json` 实时生效且排版清晰。
   - 彻底关闭应用，模拟重装（替换应用本体）重新启动，确认近场守护与首选项无需再次配置即刻正常运行。
