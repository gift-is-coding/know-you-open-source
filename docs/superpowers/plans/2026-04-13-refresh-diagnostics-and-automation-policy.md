# 刷新诊断与自动化策略实现计划

1. 为 `SummaryGenerating` 和 CLI runner 打通 invocation context 与 per-call timeout。
2. 在 `AppState` 中统一手动/自动刷新入口，记录阶段耗时、attempt 与最终写盘结果。
3. 把自动刷新改成 today-only，移除历史 backfill 语义。
4. 为新增行为补测试：
   - automation 不再补历史
   - manual/automation timeout 路由正确
   - refresh log 文件会写出
5. 更新 `architecture.md` 与 `requirements-spec.md`，确保文档和实现一致。
