# Networking Profile Update Strategy 规格

## 背景

Networking 的 profile 不是一次性 mock 文本，而是用户长期维护的公开身份资产。第一次进入 Networking 时，App 应自动准备本地 agent 权限，并基于默认场景生成 profile draft；用户确认后，profile 才能被社区和 agent 自动化使用。

## 用户体验

- 页面默认展示两个内置 profile：`Career / Hiring` 和 `Friends / Social`。
- 自定义 profile 通过 `Add custom profile` 加号入口创建。用户填写使用场景、形象方向、公开语气和脱敏说明后生成；生成成功后它会成为新的持久 profile 卡片，用户仍可继续点击加号添加更多 profile。
- profile 没有 draft 时按钮显示 `Generate from My Wiki`。
- profile 已有 draft 后按钮显示 `Update profile`，语义是用新增 My Wiki 素材更新现有 profile，而不是把旧资料全部重新扫一遍。
- `Approve profile` 必须靠近 draft 顶部，避免用户读长正文后找不到人工卡点。

## 数据与隐私

- draft 存在当前 My Wiki projectRoot 的 `.knowyou/networking/profile-drafts.json`。
- draft 记录 `generatedAt` 和 `updatedAt`，用于后续增量更新。
- custom profile 配置也存在同一个本地状态文件里，只包含公开场景配置，不上传 My Wiki 原始证据。
- My Wiki context provider 在 update 模式下先按文件修改时间筛选，只读取 `changedAfter` 之后变化的 curated wiki 页面。

## 更新策略

- 初始化：默认 profile 首次没有 draft 时，进入 Networking 后可自动生成；custom profile 不自动生成，必须用户先填写配置。
- 手动更新：已有 draft 时点击 `Update profile`，使用上次 `updatedAt/generatedAt` 作为增量边界。
- 定期更新：进入 Networking 时检查一次 daily checkpoint；超过 24 小时才运行一次后台检查。后台只针对已有 draft 且 `autoUpdate = true` 的 profile，并只读取新增 My Wiki 材料。
- 没有新增素材时，不视为失败；UI 显示“no new material”状态。

## 非目标

- 本轮不改 Web/Supabase schema。
- 本轮不实现后台常驻 daemon；daily update 是 App 页面进入时的轻量检查。
- 本轮不把 private matching reason、raw citations 或 My Wiki 原文上传到平台。
