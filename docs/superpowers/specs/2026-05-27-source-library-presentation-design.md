# Source Library Presentation Design

## 背景

Task 5 要把 My Wiki 的 Source Library 从平铺 raw files 改成可选择的 source catalog 树。现有 catalog builder 已能发现 Diary、外部导入文档和 Manual Imports，并保留 include 状态、索引状态和层级路径；本任务只补齐展示、筛选、批量操作和 UI 持久化。

## 设计

新增 `MyWikiSourceLibraryPresentation` 作为 UI 和测试共用的只读展示模型。它从 `MyWikiSourceCatalogSnapshot`、搜索 query 和 status filter 计算可见 records、状态计数、可见树，以及总数/包含数/待处理数/变更数/失败数。搜索匹配 `displayTitle` 和 `relativePath`；status filter 只过滤可见层，不改变底层 snapshot。

新增 `MyWikiSourceCatalogBulkAction` 和 `MyWikiSourceCatalogSnapshot.apply(action:visibleSourceIDs:)`。批量操作只作用于当前可见 source IDs：include visible、exclude visible、invert visible。目录选择也通过 descendant source IDs 修改 snapshot，随后保存到 `MyWikiSourceCatalogStore`。

`MyWikiSourceLibraryView` 改为持有 catalog snapshot，并通过 `MyWikiSourceCatalogBuilder().refreshCatalog(projectRoot:sourceVault:importedDocuments:)` reload。视图显示层级目录和 source row，目录/文件都显示 included、excluded、mixed 状态；文件行显示 title、path 和 processing status。保留 choose folder、import files、drag drop，导入完成后 reload catalog。

Manual import 的目标目录改成 `raw/sources/Manual Imports`，旧 summary 查找仍保持 `wiki/sources`，不删除已处理输出。

## 验证

新增 `MyWikiSourceLibraryPresentationTests` 覆盖状态计数、title/path 搜索、visible-only invert、statusFilter、tree hierarchy 和 mixed state。更新 `MyWikiSourceLibraryTests` 的导入路径断言。执行目标测试、presentation 测试、`git diff --check`，时间允许再执行 macOS build。
