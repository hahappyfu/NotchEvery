# 领域文档

工程技能在探索代码库时，应如何消费此仓库的领域文档。

## 探索前阅读这些

- **`CONTEXT.md`**，位于仓库根目录，或
- **`CONTEXT-MAP.md`**，如果存在于仓库根目录：它指向每个上下文的 `CONTEXT.md`。读取与主题相关的每一个。
- **`docs/adr/`**：读取涉及你即将处理区域的 ADR。在多上下文仓库中，还需检查 `src/<context>/docs/adr/` 中特定于上下文的决策。

如果这些文件中任何一个不存在，**静默继续**。不要标记它们的缺失；不要建议提前创建它们。`/domain-modeling` 技能（通过 `/grill-with-docs` 和 `/improve-codebase-architecture` 访问）会在术语或决策实际解决时懒创建它们。

## 文件结构

单上下文仓库（大多数仓库）：

```
/
├── CONTEXT.md
├── docs/adr/
│   ├── 0001-event-sourced-orders.md
│   └── 0002-postgres-for-write-model.md
└── src/
```

多上下文仓库（根目录存在 `CONTEXT-MAP.md`）：

```
/
├── CONTEXT-MAP.md
├── docs/adr/                          ← system-wide decisions
└── src/
    ├── ordering/
    │   ├── CONTEXT.md
    │   └── docs/adr/                  ← context-specific decisions
    └── billing/
        ├── CONTEXT.md
        └── docs/adr/                  ← context-specific decisions
```

## 使用词汇表的词汇

当你的输出命名一个领域概念（在 issue 标题、重构提案、假设、测试名称中），使用 `CONTEXT.md` 中定义的术语。不要漂移到词汇表明确避免的同义词。

如果你需要的概念还不在词汇表中，这是一个信号：要么你在发明项目未使用的语言（重新考虑），要么存在真正的空白（记录给 `/domain-modeling`）。

## 标记 ADR 冲突

如果你的输出与现有 ADR 矛盾，明确指出而不是静默覆盖：

> _与 ADR-0007（event-sourced orders）矛盾，但值得重新审视，因为……_
