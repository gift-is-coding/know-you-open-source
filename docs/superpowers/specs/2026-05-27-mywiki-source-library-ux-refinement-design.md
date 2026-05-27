# My Wiki Source Library UX Refinement Design

## 背景

现有 Source Library 已经可以展示分层 source catalog，但入口和语义不够清晰：用户需要点击 ingest progress 卡片才会发现管理入口，弹窗宽度偏窄，拖拽导入区占据主要空间，`Done` 容易被误解为保存或开始处理。

本轮目标是把 Source Library 明确成 source 管理工作台：进度条只展示状态，用户通过 `Manage Sources` 打开管理面板；面板中选择变更自动保存，真正处理只由 `Update My Wiki` 显式触发。

## 设计

My Wiki 左侧进度区域改为状态卡加独立 `Manage Sources` 按钮。状态卡不再响应点击，避免把“看进度”和“管理 source”混成同一个动作。详情页 `More` 菜单保留管理入口，并统一使用 `Manage Sources` / `Update My Wiki` 文案。

`MyWikiSourceLibraryView` 改成宽工作台，最小宽度约 1280、高度约 760，首选尺寸约 1480x900。左侧约 68% 宽度只负责标题、状态、搜索和 source tree；右侧固定管理栏负责 `Update My Wiki`、状态统计、status filter、visible 批量操作、`Manual Uploads` 导入区和 `Close`。右侧管理栏必须可滚动，避免在较小屏幕或 sheet 约束下裁掉导入区和底部动作。

`Manage Sources` 入口按钮必须是明确的文字按钮，而不是只剩一个小 icon。按钮保持 folder 图标，但需要有足够点击面积和完整 label，避免用户把它误认为一个无说明的小设置按钮。

Source 选择语义保持“自动保存 + 手动更新”。include/exclude、目录选择、include visible、exclude visible、invert visible 仍会立即写入 `.knowyou/source-catalog.json`；`Close` 只关闭面板，不保存也不处理，因为保存已经自动完成；`Update My Wiki` 才调用 My Wiki ingest flow。

手动导入的底层目录继续使用 `raw/sources/Manual Imports`，避免迁移旧文件；UI 层通过 `MyWikiSourceLibraryDisplayPolicy` 把 manual source 展示为 `Manual Uploads/...`。新导入文件默认 included，状态为 `Pending`，不会因为 drop/import 立即进入处理。

## 验证

新增/更新 presentation 和行为测试，覆盖 `Manual Uploads` root、display path 不改变 raw path、导入后 pending/included、action copy、宽面板布局策略、以及 progress card 不再作为 Source Library 入口。完整验证仍以 Source Library 目标测试和 macOS build 为准。
