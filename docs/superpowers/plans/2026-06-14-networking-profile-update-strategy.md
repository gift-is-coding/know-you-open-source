# Networking Profile Update Strategy 实施计划

## 目标

把 Networking profile 从“每次 regenerate 的一次性草稿”改为“生成一次、长期增量更新、人工批准后使用”的本地状态模型。

## 步骤

1. 先写测试覆盖新行为：
   - UI 不再出现 `Regenerate`，改为 `Update profile`。
   - `Approve profile` 出现在长正文前方。
   - custom profile 配置可多实例持久化。
   - draft 记录 `generatedAt/updatedAt`。
   - My Wiki context provider 支持 `changedAfter` 增量读取。
   - daily update policy 24 小时内不重复运行。

2. 扩展本地模型：
   - `NetworkingProfileDraft` 增加时间戳。
   - `NetworkingCustomProfileConfiguration` 保存 custom profile 场景配置。
   - `NetworkingProfileDraftState` 保存 draft、custom profiles、daily update checkpoint。

3. 扩展 profile generation pipeline：
   - context provider 增加 `changedAfter` 参数。
   - update 模式只读取修改时间晚于 `changedAfter` 的 curated wiki markdown。
   - 没有新增材料时返回明确的 `noNewMyWikiMaterial`，UI 展示为非失败状态。

4. 重构 App UI：
   - 删除固定 custom card，新增 `Add custom profile` 加号卡。
   - 生成 custom profile 后把它追加到 profile 列表。
   - 已有 draft 的主操作改成 `Update profile`。
   - 把 approval 操作移动到 preview 顶部。
   - daily update 状态以轻量 status card 展示。

5. 验证：
   - 运行 targeted Networking tests。
   - 运行完整 `xcodebuild test` 与 `xcodebuild build`。
   - 用 dev app 脚本打开当前 worktree app，避免影响其他 worktree。
