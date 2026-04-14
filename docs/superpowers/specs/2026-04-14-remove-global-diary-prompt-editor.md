# 规格说明：下线全局 Diary Prompt 编辑入口

日期：2026-04-14

## Summary

当前产品的阅读器分段、`Details` workstream 拆分和 `sourceEventIDs` 绑定都依赖 canonical diary prompt 的结构约束。继续暴露 raw prompt 编辑会让用户直接改写内部输出协议，带来分段、索引和读取路径的不稳定性。

本次改动将 raw prompt 编辑从产品能力中下线。产品统一回到代码内的 canonical prompt，并把未来可控生成方向记录到 feature roadmap，而不是继续允许用户直接覆写 prompt 字符串。

## Product Decisions

- 主窗口右上角不再显示 `Edit Prompt` 入口。
- 产品不再支持用户保存、恢复或应用全局 diary prompt override。
- 运行时生成路径统一使用 `DailyMarkdownComposer` 的 canonical prompt。
- 历史 `.story.json` 与 `.md` 不做迁移或回写。
- 如果本地仍残留 legacy `summarizerGlobalDiaryPromptOverride` 配置键，应用必须忽略并清理该键，避免隐藏状态继续影响未来生成。

## Docs And Roadmap

- `docs/requirements-spec.md` 与 `docs/architecture.md` 删除 prompt editor 相关现行能力描述。
- `docs/feature-roadmap.md` 新增后续方向：以结构化生成控制替代 raw prompt 编辑，候选范围包括语气风格、Summary 密度和 Details 分组强度。

## Acceptance Criteria

- UI 中不再存在 `Edit Prompt` 入口。
- 生成与 full recovery 都不再读取或传递全局 prompt override。
- legacy override key 即使存在，也不会影响生成结果，并会在加载/保存配置时被清理。
- 相关测试通过，且全量 `xcodebuild test` 与 `xcodebuild build` 通过。
