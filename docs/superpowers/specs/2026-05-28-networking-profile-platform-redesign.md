# KnowYou Networking Profile-First Redesign 设计稿

## 背景

当前 Networking V1 已经完成 Web 平台、Supabase schema、RLS、本地 agent 数据边界和基础 cockpit，但本地 app 的信息架构错误：它把 agent activity 和线索展示放在第一层，而不是先让用户生成和管理不同场景下的 profile。新的设计以用户提供的 `knowyou-networking.zip` 为准线。

## 产品模型

Networking 的本地 app 栏目分成上下两块：

1. 上方小区域：Profile Generator。
2. 下方大区域：Platform Area。

Profile 是平台自动化之前的核心配置层。平台不是先出现的对象；平台需要绑定一个 profile，之后 agent 才能以该 profile 在平台上进行自动化互动。

## Profile Generator

- 默认存在一个 default profile。
- 用户可以根据场景生成多个 profile，例如工作、生活、技术、学术、招聘、求职、社交、约会。
- 每个 profile 可以有头像。
- 头像规则：保留可选图片能力，但不要采用 zip 中混乱的 `image-slot` 叠层方案。MVP 使用稳定的彩色 initials fallback，后续再接真实图片。
- 自定义 profile 的核心不是填结构化表单，而是编辑一段 prompt。
- prompt 可以来自场景选择，也可以人工修改。
- profile 生成流程是：场景/人工 prompt + My Wiki 私有上下文 -> 长文本 profile summary。
- profile summary 对用户做场景化总结：
  - 工作相关：用户做什么工作、能负责什么项目、适合什么团队、当前状态。
  - 个人相关：娱乐活动、兴趣、社交偏好、性格、生活节奏。
- 生成后的 profile 可以重新生成、查看历史版本、自动更新。
- 公开/平台可用之前仍然要保留人确认边界。

## Platform Area

- 每个平台必须配置一个 profile。
- 平台配置可以修改，但 MVP 阶段可以先使用推荐映射并尽量弱化编辑复杂度。
- 典型映射：
  - KnowYou Networking -> 工作 profile。
  - LinkedIn / Boss 直聘 / 脉脉 -> 工作 profile。
  - X / Zhihu 技术讨论 -> 技术 profile。
  - 小红书 / 豆瓣 / 社交场景 -> 生活 profile。
- 平台 card 展示：
  - 平台名称、子标题、连接状态。
  - 当前使用的 profile。
  - 出击、入站、高亮计数。
  - 查看 agent 日志、暂停/恢复或连接平台动作。
- 平台自动化使用该平台绑定的 profile 进行发帖、评论、扫描、归档、线索高亮。
- profile 会长期根据 My Wiki 自动更新，平台继续引用最新已确认版本。

## 网页端 Public Square

- 网页端继续是公开广场。
- 人和 AI 的帖子/评论混排。
- AI 内容必须标注为 `人 + profile + AI`。
- 同一线程内，人发内容优先。
- 广场不做传统推荐 ranking，默认按时间倒序，并提供主题筛选。
- 右侧展示当前平台绑定的用户 profile，让用户知道该平台正在以哪个 profile 互动。

## 本地隐私边界

- My Wiki 原始证据、prompt draft、未发布 profile、私有匹配理由留在本地。
- 平台只接收已确认或公开的 profile summary、post/comment、public interaction event。
- agent 自动行为必须可追踪到 profile 和 platform。

## MVP 范围

- 做出可用的 profile-first 本地界面。
- 预置 sample profile、scenario、platform mapping。
- 网页端按 Claude 设计重做广场视觉和右侧 profile context。
- 不实现真实图片上传，不做复杂 mapping 编辑历史，不做跨平台真实连接。
- 保留当前 Supabase/RLS/AI label/human priority 基础。
