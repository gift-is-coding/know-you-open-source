# My Wiki Source Library UX Refinement Plan

## 目标

把 Source Library 从隐藏在进度卡片里的窄弹窗，改成明确的 source 管理工作台：用户通过 `Manage Sources` 进入，在宽面板里选择 source，选择自动保存，只有点击 `Update My Wiki` 才会处理。

## 实施步骤

1. 更新测试：
   - `MyWikiSourceLibraryPresentationTests` 覆盖 `Manual Uploads` 展示名、action copy、布局策略和 visible-only 行为。
   - `MyWikiSourceLibraryTests` 覆盖导入文件仍进入 `raw/sources/Manual Imports`，reload 后为 included + pending，并在 presentation 中显示 `Manual Uploads`。
   - `KnowledgeOntologyPanelTests` 覆盖 Source Library 入口策略：显示 `Manage Sources`，进度卡不打开管理面板。

2. 更新展示模型：
   - 新增 `MyWikiSourceLibraryDisplayPolicy`，只在 UI/presentation 层把 manual source 的 `Manual Imports/...` 显示为 `Manual Uploads/...`。
   - 让搜索同时匹配 raw path 和 display path。
   - 让 source tree builder 支持 display path，但保持 catalog record 的 raw `relativePath` 不变。

3. 更新 My Wiki 入口：
   - `MyWikiPanel` 的 progress 区域改成非点击状态卡。
   - 在状态卡旁增加 `Manage Sources` 按钮。
   - Source Library sheet 接收 `isUpdatingSources` 和 `onUpdateSources`，用于面板内触发 `Update My Wiki`。
   - `MyWikiDetailView` 菜单统一改为 `Update My Wiki` 和 `Manage Sources`。

4. 更新 Source Library UI：
   - 面板调整为约 1080x680 的左右布局。
   - 左侧专注 source tree；右侧放状态统计、筛选、批量操作、`Manual Uploads` 导入区、`Update My Wiki`、`Close`。
   - `Drop`/`Import` 只复制文件并 reload catalog，不触发 ingest。
   - `Close` 只关闭窗口；保存由选择变更即时完成。

5. 文档和验证：
   - 新增本 spec/plan 文档，并同步 `docs/architecture.md`、`docs/requirements-spec.md` 中的入口和语义。
   - 运行目标测试、`git diff --check` 和 macOS build。
