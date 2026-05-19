# KnowYou 当前需求规格

本文档描述当前项目已经实现并正在维护的产品规格，重点是统一“这个产品现在是什么、提供什么、不提供什么”。

## 1. 产品目标

KnowYou 的目标是把用户每天电脑上的零散上下文转成一份可阅读、可追溯、按天组织的日记材料。

当前版本强调三件事：

- 自动采集，而不是让用户手写记录
- 本地优先，而不是依赖云端才能工作
- 先看故事，再追溯来源，而不是直接阅读原始事件流

## 2. 当前产品定义

KnowYou 是一个原生 macOS 桌面应用，不是浏览器扩展，不是 Obsidian 插件，也不是多端同步产品。

当前项目包含三类用户可见产物：

- 应用内三栏阅读器
- 每日 Markdown 文件
- 每日结构化 `.story.json` 文件
- 外部 memory 渠道同步（Obsidian / OpenClaw）

其中：

- `.story.json` 用于驱动应用内阅读体验
- `.md` 用于导出、归档和在外部工具中阅读

## 3. 目标用户

当前版本面向的用户是：

- 长时间在电脑上工作，希望回忆“今天都做了什么”的个人用户
- 希望保留工作线索，但不想手动记流水账的知识工作者
- 接受本地工具、对隐私边界敏感、愿意授权 macOS 本机能力的用户

## 4. 核心使用场景

### 4.1 自动记录当天上下文

应用启动后应自动开始工作，持续采集剪贴板，并在条件允许时导入通知历史。
用户首次正常打开应用后，系统应默认把 KnowYou 注册为 macOS 登录项，使后续登录 Mac 时自动启动应用。

### 4.2 生成某一天的日记

系统应能把某一天的事件材料转成日记式 story，并同时生成 Markdown 文件。
当用户手动刷新某一天时，这个动作必须只作用于该选中日期。
如果该天已有成功的模型 story，后续刷新应优先采用增量更新，而不是整天重写。

### 4.3 以故事方式阅读当天内容

用户应先看到压缩后的日记段落，再决定是否查看段落背后的原始来源。

### 4.4 对历史日期刷新

历史日期必须支持按需手动刷新，但不得被后台自动流程隐式改写。
“刷新选中日期”动作只能作用于当前选中日期，不能顺带补跑其他天。

### 4.5 在失败时理解发生了什么

用户应能看到通知导入是否可用、日记引擎是否可用、最近一次刷新是否成功，而不是只看到“没有内容”。

### 4.6 感知应用有新版本可用

当应用存在新版本时，用户应能在主窗口左上标题栏看到一个明确但不打扰正文阅读的更新提醒，并在点击后理解当前版本、可用版本以及更新动作。

## 5. 功能范围

### 5.1 In Scope

- macOS 桌面应用
- 剪贴板监听
- Notification Center 本地数据库导入
- 持久化前隐私过滤
- SQLite 事件存储
- run 记录与刷新日志
- 每日 story 生成
- 每日 Markdown 导出
- story-first 三栏阅读器
- 段落级 source link
- 真实阅读器上的 onboarding coachmarks 与 settings 配置
- 左下角 `...` 二级菜单中的 `Sync Memory`
- 顶部 diary engine selector
- 左上标题栏更新提醒胶囊与更新 sheet
- 晚间回顾本地通知提醒
- 可选 diary engine：
  - OpenAI API
  - Codex Auth
  - Claude Code CLI
  - Codex CLI
  - Gemini CLI
  - Openclaw CLI

### 5.2 Out of Scope

- iOS / Web / Windows 版本
- 多设备同步
- 云端账户系统
- 团队协作与共享
- 全文检索、标签系统、知识图谱界面
- 浏览器历史、邮件、日历等更多信号源
- 主界面中的原始 Markdown 编辑模式
- App Store 分发约束下的沙盒化方案
- 双向外部知识库同步

当前版本的对外分发方式是 Developer ID + notarization，不是 Mac App Store。

## 6. 功能需求

## 6.1 采集需求

### 剪贴板

- 系统必须能够自动监听 macOS 原生剪贴板
- 启动后必须尽快把当前剪贴板纳入当天上下文
- 每条剪贴板事件都必须记录来源应用、采集时间与日期键

### 通知

- 系统必须尝试从本机 Notification Center 数据库读取通知历史
- 当数据库不存在、不可读或 schema 不支持时，系统必须明确暴露状态
- 通知导入失败不能阻塞整个应用启动与日记生成
- 手动刷新某一天时，系统必须只为该同一天执行通知同步
- 今天的手动刷新必须使用 `dayStart ... now` 时间窗；历史日期必须使用 `dayStart ... nextDayStart` 时间窗

## 6.2 隐私需求

- 所有可持久化内容都必须先经过隐私过滤
- 明显敏感文本不得以原文形式写入 SQLite
- 被丢弃或脱敏的内容应保留最小审计信息，帮助用户理解为何某条内容未被完整保留

## 6.3 存储需求

- 系统必须使用本地 SQLite 存储原始事件
- 系统必须为每天输出独立文件，而不是把所有内容混在一个大文件里
- 系统必须支持按 `dayKey` 读取与重生成
- 系统必须通过内容哈希避免重复事件无限累积
- 系统必须在 onboarding 的首屏明确说明日记会以本地 Markdown 文件形式保存在当前 Mac 上
- 系统必须把每次刷新写成独立日志文件，存放在应用支持目录下

## 6.4 生成需求

- 每天都必须能生成 `DailyStory`
- 即使没有可用 summarizer，系统也必须通过 fallback 逻辑生成可阅读故事
- 如果某天已经存在 `generationMode == model` 的成功 `DailyStory`，后续刷新若只得到 fallback 结果，则不得用 fallback 覆写现有 `.story.json` 或 `.md`
- story 中每个段落都必须保留来源事件 ID 列表
- 系统必须为同一天生成 Markdown 文件
- Markdown 必须包含 story 内容和 source notes
- summarizer 是首次完成 onboarding 与首次生成真实故事的前置依赖；用户必须先完成引擎配置
- 当 summarizer 成功时，story 段落内容允许携带 Markdown 结构，而不是被限制为纯文本
- 当前 diary prompt 必须把模型输出组织为以下一级标题：
  - `# 你今天做得很棒`
  - `# 今日总结`
  - `# 详情`
  - `# 待办事项`
- 当前 diary prompt 不得生成 `# 今日节奏`
- `今日总结` 必须使用 bullet list，`详情` 必须按事务线程使用 `##` 子标题，`待办事项` 必须使用 Markdown task list
- `详情` 中的每个事务线程都应成为独立的 story paragraph，并各自保留自己的 `sourceEventIDs`
- 当前产品不对 `详情` 段落数量设置硬性上限，分段质量主要由 prompt 约束“合理分段、避免碎片化”
- 当前产品不向用户暴露 raw diary prompt 编辑能力；prompt 变更只通过内置 canonical prompt、代码和测试管理
- 所有 full-story 与 incremental summarizer prompt 都必须在 prompt 组装阶段对单条事件文本做统一裁剪；当前上限为 100 个 Swift 字符，且不改变事件顺序、不改变原始存储内容
- 历史 `.story.json` 如果仍把多个 `详情` 子线程合并在同一个 paragraph 中，加载时必须拆分并回写为新的 paragraph 结构
- 当某天已有 `provenance.generationMode == .model` 的成功 story 时，增量更新只能消费尚未写入该 story 的新事件
- 增量更新给模型的输入必须包含 `existingStory + 新事件`，不得把当天 `allEvents` 全量重新回传给模型
- 增量 structured payload 必须完整返回 `你今天做得很棒`、`今日总结`、`详情`、`待办事项` 四个 section 的更新意图
- 增量成功时，`你今天做得很棒`、`今日总结`、`待办事项` 必须整段替换，`详情` 只允许追加新的事务段落
- 增量 payload 的 `sourceEventIDs` 至少必须属于当天已知事件集合；replacement section 出现非法引用时整次增量 attempt 必须失败，`详情` 追加块出现非法引用时仅丢弃对应 block
- 增量失败时，不得覆盖已有 `.story.json` 或 `.md`
- 系统必须支持把全部每日日记复制到 Obsidian 和 OpenClaw
- Obsidian 目标目录固定为 `<vault>/KnowYou/Daily Memories/`
- OpenClaw 目标目录固定为 `<workspace>/know-you-memory/`
- 系统不得覆盖 OpenClaw 原生 daily memory 文件
- 同步时必须覆盖 KnowYou 在目标目录中已有的同名日记文件，但不得删除目标目录中的其他历史文件
- 用户必须能手动触发 `Sync Memory`
- 用户必须能开启 `Auto Sync Daily`
- 当启用 `Auto Sync Daily` 时，系统必须安装用户级 `LaunchAgent`，在用户登录后按固定时间执行同步
- 系统必须支持一个可开启/关闭的 `Evening review reminder`
- 当 `Evening review reminder` 开启且系统通知权限允许时，产品必须安装一个用户级后台提醒任务，而不是依赖当天前台 app 是否开过
- 晚间提醒必须使用用户本地时区，在每天固定 `20:30` 运行后台判断
- 如果当天 diary 已存在，系统必须发送英文通知 `Come review today's diary.`
- 如果当天 diary 尚不存在，系统必须发送英文通知 `Come generate today's diary.`
- 后台提醒任务不得在后台静默生成 diary；无 diary 的情况下只能发送 `generate` 类型通知
- 同一天最多只允许成功发出一次晚间提醒
- 点击 `review` 通知时，系统必须唤起 KnowYou 并路由到今天的 diary 内容
- 点击 `generate` 通知时，系统必须唤起 KnowYou、定位到今天，并立即开始生成今天的 diary
- 通知点击路由必须优先复用现有主窗口；仅在没有主窗口时才允许新开窗口
- 设置页必须显示晚间提醒开关、通知权限状态、测试入口和简短规则说明
- onboarding 的 `permissions` 步骤必须同时解释 Full Disk Access 与 Notifications，其中通知说明必须明确它用于 `8:30 PM` 晚间回顾提醒
- 通知权限不得阻塞 onboarding 完成；Full Disk Access 仍是该步骤唯一硬阻塞条件
- onboarding 中的通知授权入口在 `notDetermined` 时必须触发系统通知权限请求，在 `denied` 时必须引导打开 Notification Settings
- onboarding 之后不再要求主窗口额外显示 reminder 权限 CTA；后续补授权路径以 Settings 为主

## 6.5 阅读器需求

主阅读器必须保持三栏结构：

- 左侧日期列表
- 中间 story 阅读区
- 右侧 source detail 区

阅读器当前必须支持：

- 选择日期后加载该日 story
- 点击段落后查看其来源事件
- 当 `详情` 被拆成多个事务段时，点击不同 `详情` 子段必须切换到各自对应的 source detail
- 查看该日全部来源事件
- 按当前选中日期重生成内容
- 在刷新按钮旁以内联方式显示当前选中日期的刷新阶段、完成结果或错误信息
- 在中间 story 阅读区按 Markdown 富文本显示段落内容，而不是仅以 plain text 呈现
- 在中间阅读区显示明确的 story 层级标题，如 `今日小记` / `Story`
- 在键盘上下切换 story 段落时，当前选中段落必须保持在可视区域内
- 右侧 source detail card 应在 `sourceApp` 文本前显示渠道 logo；已识别渠道显示本地品牌 asset，未识别渠道回退为通用 icon
- 产品当前应优先内置覆盖常见 global desktop apps 的品牌 logo 集合，目标覆盖 100+ 高频来源应用，而不是只覆盖少量演示品牌
- 已识别渠道的 logo 解析不能只依赖精确 app 名，需要同时兼容中文名、英文名和常见 bundle-id 风格名称
- `Source Notes` 不在中间阅读区重复显示，来源追溯继续通过右侧 source detail 区完成
- 不同日期允许并发刷新，但同一天已有刷新任务进行中时，该天刷新按钮必须禁用
- 主窗口右下角必须持续显示一个只读的 build badge，格式为 `v<marketing-version> · <MM-dd HH:mm> (<build-number>) · <git-short-sha>`；当没有 build time 或 SHA 时必须安全退回，只省略缺失片段
- 当检测到真实新版本时，主窗口左上标题栏必须显示一个更新胶囊，位置应紧邻 traffic lights 但不得遮挡系统关闭、最小化、缩放按钮的命中区域
- 更新胶囊默认隐藏，只有存在 `UpdateOffer` 时才允许显示
- 更新胶囊文案固定为 `new updates`
- 用户点击更新胶囊后，系统必须打开更新 sheet，而不是直接开始更新
- 用户关闭更新 sheet 而不更新时，更新胶囊必须继续保留
- 更新 sheet 必须显示当前版本、可用版本和简短更新说明
- direct build 的更新 sheet 主按钮必须表示下载或打开官网更新入口；App Store build 的主按钮必须表示前往 App Store
- App Store build 不得伪装成可在应用内自行安装更新

## 6.6 更新检查与分发需求

- 系统必须在应用启动时检查更新
- 当应用持续运行时，系统必须至少每天再次检查一次更新
- 更新检查失败不得打断主阅读器，也不得弹出侵入式错误
- 系统必须支持通过构建元数据解析当前分发渠道，至少区分 `direct`、`appStore`、`unknown`
- 如果当前构建未配置 update feed，系统必须安全退回为“无可用更新提醒”，而不是报错或显示伪状态
- 更新提醒的可见行为必须在 direct build 和 App Store build 之间保持一致；两者差异只允许体现在主动作上
- 更新胶囊必须在成功安装到该版本或更高版本后才消失；不得因为用户关闭 sheet 就消失

## 6.7 键盘与焦点需求

阅读器必须维护显式焦点模型，而不是完全依赖系统默认焦点。

当前焦点区只有两类：

- `dateList`
- `storyParagraphs`

行为要求：

- 在 `dateList` 中，`Up/Down` 切换日期
- 在 `dateList` 中，`Right` 进入 story
- 在 `storyParagraphs` 中，`Up/Down` 切换段落
- 在 `storyParagraphs` 中，`Left` 或退出命令回到日期列表
- 每个日期需要记住最近一次选中的段落

## 6.8 配置需求

用户必须能够配置：

- vault 目录
- diary engine 默认项
- 对应的 API token、CLI 路径，或 Codex Auth 本地登录状态

配置入口包括：

- 首次 onboarding 中的 Demo Day + coachmark 流程
- 主窗口左下角 `...` 菜单中的 `Sync Memory`
- 主窗口右上角 diary engine selector
- Settings 页面中的次级状态入口
- Settings 页面中的作者联系、社区与法律文档入口

onboarding 的配置约束为：

- 首次 onboarding 必须叠加在真实主阅读器之上，而不是跳到独立欢迎页
- 首次 onboarding 的固定顺序必须为：`demoRead`、`demoClick`、`demoReference`、`privacy`、`permissions`、`enginePrompt`、`engineSetup`、`generating`
- `demoRead` 必须先让用户阅读中栏里的 `Demo Day`
- `demoClick` 必须要求用户点击正文段落，右侧 source detail 才进入下一步解释
- `demoReference` 必须说明右侧 reference 会跟随阅读位置变化，而不是重复展示另一份正文
- `privacy` 必须直接说明“内容以本地 `.md` 文件保存在当前 Mac 上、没有服务端”
- `permissions` 只允许把 `Full Disk Access` 作为唯一硬 gate，并且必须解释通知与剪贴板上下文如何帮助 story 生成
- `enginePrompt` 必须高亮真实产品里的引擎按钮，`engineSetup` 必须复用现有引擎配置模块，而不是造一套 onboarding 专用配置页
- 引擎配置必须阻塞 onboarding 完成；未配置成功前不得进入真实生成流程
- onboarding 完成后必须自动启动一次性今天+昨天 bootstrap，而不是要求用户手动刷新
- onboarding 完成后必须给出一个非阻塞提醒，告知用户今天和昨天正在生成，并建议约 2 分钟后回来查看
- `Demo Day` 在 onboarding 完成后不得消失，必须继续保留在左侧列表底部
- 如果当前默认引擎为 `None` 且用户没有显式保持 `None`，主应用后续可以自动选择一个已验证绿色引擎；如果用户已明确选择某个非 `None` 引擎，或已明确保持 `None`，则不得被被动覆盖

## 6.8 自动化需求

- 首次正常交互式打开应用时，系统必须默认尝试启用 `Launch at Login`
- 用户必须能够在 Settings 中关闭或重新打开 `Launch at Login`
- 用户在 KnowYou 中关闭 `Launch at Login` 后，后续启动不得再次自动打开该设置
- 应用启动时必须立即执行一次自动刷新
- 应用启动时还必须立即执行一次今天的通知补同步
- 首次完成 onboarding 时，系统必须额外执行一次且仅一次“今天+昨天 bootstrap”
- onboarding bootstrap 必须只覆盖今天与昨天两个自然日，并跳过已有成功内容的日期
- onboarding bootstrap 应按顺序先生成今天，再生成昨天；若今天失败，仍应继续尝试昨天
- onboarding bootstrap 在单日事件数超过 `50` 条时，必须启用分批生成：首批 `50` 条走 full recovery，剩余事件按最多 `50` 条一批顺序走 incremental append
- onboarding bootstrap 的分批失败不得回滚已成功块落盘的部分内容，但也不得把该日期记为 bootstrap 全部成功
- onboarding bootstrap 不得在后续正常启动时重复执行
- 正式 reader 的刷新按钮旁必须提供一个下拉入口，并且只显示一个小三角菜单指示器
- 该下拉入口必须允许用户对当前选中的真实日期执行全量刷新，不得把历史日期错误禁用；`Demo Day` 仍应保持只读
- 当选中日期是今天时，菜单文案应为 `Full Refresh Today (Overwriting)`；其他真实日期可显示通用全量刷新文案
- 全量刷新必须忽略已有成功模型 story，始终强制走 full recovery 覆盖路径
- 全量刷新在单日事件数超过 `50` 条时，必须沿用与 onboarding bootstrap 相同的分批策略：首批 `50` 条走 full recovery，剩余事件按最多 `50` 条一批顺序走 incremental append
- 普通增量刷新在已有成功模型 story 且新增事件数超过 `50` 条时，必须按时间顺序每批最多 `50` 条串行 incremental append；每个成功块都要立即落盘，后续块失败时不得回滚已成功内容
- refresh log 与 UI 状态文案必须显示分批计划和当前 chunk 进度，例如 `chunk 2/8` 与该批事件数，避免用户误以为刷新无响应
- 系统必须每 3 小时执行一次自动刷新
- 系统必须每 30 秒执行一次今天的通知增量补同步
- 自动刷新应先尝试导入通知，再生成内容
- 30 秒通知补同步必须使用带重叠缓冲的增量时间窗，而不是全量扫描
- 30 秒通知补同步不得直接触发文档生成；它只负责把今天的新通知补入本地事件库
- 自动刷新不得因为“今天存在 note 文件”就无条件重写今天
- 当今天已有成功模型 story 时，自动刷新只允许做今天的增量更新，不允许整天重建
- 自动化增量范围仅限今天；历史日期必须是 manual-only
- 手动刷新必须先尝试当前默认引擎
- 默认引擎失败后，手动刷新应并行尝试其它绿色引擎；任一成功即停止并取消其它仍在运行的引擎
- 手动刷新全部失败时必须保留旧文件
- 手动刷新必须与自动化分离；它不能计算 pending days，也不能顺带生成其他日期
- 手动刷新主生成超时必须为 `600s`，自动刷新主生成超时必须为 `300s`
- repair 超时必须按场景区分：手动 `120s`，自动 `60s`
- 每次手动或自动刷新都必须记录阶段耗时、attempt、超时和最终结果，便于排查性能与失败原因
- 剪贴板采集必须继续作为后台实时能力存在，不能通过手动刷新补回历史缺失内容
- 读取旧 story 或切换日期不得被动改写 `.story.json` 或 `.md`

## 6.9 发布需求

- 系统必须能产出一个使用 `Developer ID Application` 签名的 macOS release app
- Release 构建必须启用 hardened runtime，满足 notarization 前提
- 项目必须提供可复用脚本来完成 archive、压缩、notarize、staple、verify
- Apple ID app-specific password 不得保存在仓库文件中，必须通过 keychain `notarytool` profile 管理
- 发布验证必须至少包含 `codesign --verify --deep --strict --verbose=2`、`stapler validate`、`spctl --assess --type execute -vv`
- `fullRecovery` 成功写盘前必须执行一次规范化，以保证新生成 `Details` 保持 paragraph-level workstream 结构

## 6.9 状态反馈需求

应用必须向用户暴露至少以下状态：

- 剪贴板服务状态
- 通知导入可用性
- 当前默认 diary engine
- 六个 diary engine 的灰/黄/绿状态
- 最近一次刷新结果
- 当前选中日期的刷新阶段与错误详情
- 自动化运行概览

状态展示位置包括：

- Settings
- 菜单栏入口
- onboarding 权限说明页中的首次解释文案

## 6.10 联系、社区与法律入口需求

- Settings 页面必须提供作者联系入口
- 当前联系入口至少包括 X/Twitter 与邮箱
- Settings 页面必须提供社区入口或明确的社区状态说明
- Discord 是当前主社区形态
- 产品必须展示版权主体信息
- 仓库必须提供隐私政策、使用条款、社区说明与上线检查清单

## 6.11 My Wiki 需求

- 主窗口左侧栏必须提供 `My Wiki` 入口
- 点击 `My Wiki` 后，主内容区必须切换到黑色背景的 My Wiki 首页，而不是打开旧式 toolbar sheet
- My Wiki 首页必须优先展示用户可理解的内容：搜索、来源、实体、概念、近期活动和需要复核的线索
- 面向用户的 My Wiki 控件、按钮和栏目文案必须使用英文，例如 `Organize Journals`、`Sources`、`Entities`、`Concepts`
- 点击 My Wiki 条目后，右侧详情栏必须显示该条目的标题、分类、摘要、近期提及、证据来源和相关项；不得停留在静态 placeholder，也不得默认用完整 Markdown 正文挤占 summary 阅读空间
- My Wiki 主界面不得重复显示分类 tabs 和分组标题；左侧只保留搜索与可展开分组
- My Wiki 分类必须从项目级 `mywiki.schema.json` 读取，不得写死在 Swift UI enum 或固定 tabs 中
- 默认推荐 schema 的用户可见分类必须是 llm_wiki 原生 `Sources`、`Entities`、`Concepts`，但用户项目中的 `mywiki.schema.json` 优先
- 默认首页索引必须优先显示 `Entities`、`Concepts`，并把 `Sources` 放在最后；`Entities` 和 `Concepts` 展开时默认最多显示 10 个条目，`Sources` 保持紧凑预览
- `Recent`、`Needs Review` 等必须作为 view 处理，不得作为 ontology category 生成对应 wiki 目录
- 每个 schema 分类分组必须支持展开/折叠，首页仅显示少量高频条目，并提供 `View all` 进入该分类全量列表
- 全量列表必须支持搜索、排序和点击选择条目；窗口放大时应把更多空间留给右侧详情内容
- 用户可见分类名称必须来自 schema；默认不强行拆分 People/Projects/Topics 等细分类。旧 `wiki/people`、`wiki/organizations`、`wiki/projects`、`wiki/events` 必须读入 `Entities`，旧 `wiki/topics`、`wiki/decisions`、`wiki/preferences`、`wiki/follow-ups`、`wiki/summaries` 必须读入 `Concepts`
- 主界面不得展示 `tag:` 一类内部字段；别名应展示为 `Also known as`，关系应展示为 `Related`
- `Open Project`、journal count、last date 等维护信息必须进入 `More > Wiki Status / Reveal Wiki Folder`，不得占据主阅读界面
- `More` 菜单必须提供轻量 `Source Library` 入口，允许用户选择文件夹、导入文件或拖拽素材，并能区分全局 source 处理进度与单个 entity 的 evidence source 数
- `Edit` 必须统一编辑 display name、aliases 与 summary
- 改名保存前必须检测同分类 title 或 slug 冲突；有冲突时不得直接覆盖，必须引导用户保留当前名称、另选名称或进入合并审核
- 主动发现疑似重复实体必须由用户显式触发或仅在有真实候选时提示；系统不得固定展示假的 duplicate 状态
- 合并重复实体必须由用户确认，合并后必须保留 sources、aliases、related、mentions 和 summary/正文，并刷新 My Wiki snapshot
- 合并前必须写备份；合并后应重写 wiki 内部引用，避免旧实体名继续悬挂
- 没有生成内容时，首页也必须保留这些核心栏目位置，并用空状态说明下一步是整理日记
- 系统必须能创建 My Wiki 项目结构，包括 `purpose.md`、`mywiki.schema.json`、`schema.md`、`raw/sources/` 和 schema 中声明的各个 `wiki/` 目录
- 默认 schema 目录必须使用 `wiki/sources`、`wiki/entities`、`wiki/concepts`；读取层仍需兼容 legacy People/Projects/Topics/Preferences/Follow-ups/Summaries 等旧目录，但不得默认创建这些旧目录
- 系统必须能把已有 `YYYY-MM-DD.md` 日记同步为 `raw/sources/knowyou-diary-YYYY-MM-DD.md`
- 重复同步同一天日记必须覆盖稳定文件名，不得生成重复文件
- My Wiki 必须尽量复用 `ThirdParty/llm_wiki` 的后端 pipeline，包括 LLM ingest、cache、search、page merge、source traceability、dedup/review 和 vector store；普通用户首页不得直接暴露复杂工作台
- 默认 My Wiki pipeline 每次运行最多处理 3 个 source，并且在限定批量时优先选择还没有 `wiki/sources/<source>.md` 的最新 raw source；旧生成内容清理后重跑也必须按小批次逐步推进
- LLM Wiki headless runner 对原生 `Sources / Entities / Concepts` schema 不得生成 KnowYou 自定义 output contract，必须尽量复用 llm_wiki 默认生成路径；只有非原生自定义目录才生成 output contract，并按 contract 中的目录和 frontmatter types 生成页面
- My Wiki 的正式本体抽取、关系发现、去重、总结和 agent context 必须使用 LLM 语义能力，不得用 keyword/regex/starter extractor 伪造可信本体页
- bundled helper、`ThirdParty/llm_wiki` 开发源码或 Codex CLI pipeline 不可用时，系统必须写入失败/降级状态并保留已有页面，不得生成 keyword fallback 正式页面
- 仓库中的旧 starter extractor 不得再作为产品代码或测试入口保留；读取层只允许过滤旧历史页面，不能生成新的 starter ontology 页面
- My Wiki 生成页的 frontmatter type 必须与 schema category 语义一致；默认生成 `source`、`entity`、`concept`。旧 `person`、`organization`、`project`、`event`、`topic`、`decision`、`preference`、`follow-up`、`summary` 页面必须读取兼容到当前 native schema
- KnowYou 必须优先连接 bundled llm_wiki helper；没有 bundled helper 时，允许回退到 `ThirdParty/llm_wiki` 开发源码目录
- 第一版只能导出 KnowYou 已生成的每日 Markdown，不得直接导出未经额外授权的 SQLite 原始事件
- 系统必须提供本地服务层能力，让 Codex、Claude、Cowork 等 agent 能读取 My Wiki 的最小必要背景摘要

## 7. 内容体验要求

当前内容体验不是“事件流水账”，而是“可读的 Markdown 工作日记”。

因此 story 需要满足以下要求：

- 以第一人称日记叙述为主，不得把用户写成第三人称
- 按真实事件组织，不应虚构事实
- 允许在“总结”和“待办”部分使用 Markdown 列表，而不是强制全文纯 prose
- 详情部分应按事务主线或工作线程组织，而不是照搬原始碎片顺序
- 会议、通知、任务提醒等外部推动因素应并入相关事务，而不是被当作噪音抛弃
- 尽量压缩路径、branch、hash、URL、工具指令等技术碎片，避免正文退化成上下文转储
- 对嘈杂日期也要尽量合并相近片段，而不是一事件一段
- 中英文内容应尽量遵循当天源数据的主语言

Markdown 导出也应服务于这个目标：

- 顶部是日期
- 主体是 story
- 后部保留 source notes，提供可追溯性

当前结构化 diary 的推荐阅读顺序为：

- `你今天做得很棒`：正向反馈，必须落在当天真实发生的推进上
- `今日总结`：高层摘要
- `详情`：按事务展开
- `待办事项`：衔接到下一步行动

## 8. 非功能需求

### 8.1 可靠性

- 重复刷新同一天不应生成无限重复事件
- 上一次异常中断的 run 需要被标记为失败
- 通知导入失败时，剪贴板与本地 fallback 仍应继续工作
- 30 秒通知增量扫描与手动刷新共享同一去重收敛目标；重叠时间窗不得制造重复通知事件
- 今天的通知导入水位必须在同一数据库路径上持久化，并在换库或缺失当日通知事件时被安全清空
- 当今天还没有成功 story 时，自动化应在已验证引擎可用时执行一次首篇 full recovery；没有已验证引擎时不得静默失败
- 当现有 `.story.json` 存在但读取失败时，刷新流程不得把它误判成“缺失 story”并自动切到 full recovery

### 8.2 可解释性

- 当通知缺失时，用户应知道是数据库缺失、权限不足还是 macOS 未持久化
- 当 diary engine 缺失或未验证时，用户应明确看到“需要先配置并验证引擎”，而不是把失败误装成成功内容
- onboarding 中的权限说明必须先讲清用户价值，再引导用户进入系统设置
- 主阅读器本身不应为了状态解释重新退化回配置面板或顶部状态 banner
- 刷新日志写失败时，主阅读器刷新按钮附近应以低调文案提示，但不应打断主要阅读流程

### 8.3 隐私优先

- 默认架构应以本地处理为主
- 云端 summarizer 是可选增强，而不是基础依赖
- 敏感文本不应越过过滤边界进入持久化层
- 可选同步或云端增强不得弱化“本地 Markdown 是默认事实”这一承诺

### 8.4 可维护性

- story 与 Markdown 必须分离为两类工件，避免 UI 完全绑定 Markdown 解析
- 采集、存储、生成、展示应保持模块化边界
- onboarding 的叙事内容与步骤顺序应通过独立内容模型维护，而不是散落在单个视图分支里

## 9. 当前已知约束

- 通知导入高度依赖 macOS 本机实现细节
- Full Disk Access 对通知导入是现实前提
- 部分通知即使系统展示过，也不保证数据库中可见
- 当前信号源仍然较少，因此某些日子内容可能偏稀疏
- CLI summarizer 的输出质量和稳定性取决于外部工具可用性

## 10. 当前不变的产品原则

- 先保护隐私，再谈记录完整性
- 先给出可读故事，再展示原始来源
- 先保证本地可用，再接入云端增强
- 每一天是一个独立单元，而不是一个无边界时间流

## 11. 验收口径

从当前产品规格看，一次有效的“日常使用”应满足以下结果：

- 用户启动应用后，系统能自动运行采集与刷新
- 用户启动应用后，系统还能在后台持续补同步今天的新通知，而不要求手动刷新
- 用户能在日期列表里看到已有日期
- 用户选中某天后，能看到可阅读的 story
- 用户手动刷新某天时，只会刷新该天，不会顺带刷新其他日期
- 用户首次进入应用时，先看到真实阅读器里的 `Demo Day` 与 coachmarks，而不是配置项堆叠
- 用户在理解 Demo Day 与右侧 reference 之后，才会被请求理解隐私、权限与引擎配置
- 用户只有完成 `Full Disk Access + 引擎配置` 后，才会自动开始生成过去 7 天的真实日记
