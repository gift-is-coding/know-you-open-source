# Sync Memory V1 设计

## 概述

这个功能会在主窗口左下角的 settings / `...` 入口下新增一个二级菜单项 `Sync Memory`，让 Know You 把每天生成的 Markdown 日记复制到两个外部记忆渠道：

- Obsidian
- OpenClaw

V1 刻意收窄范围。它不是一个通用的 “AI 工具 rules 同步系统”，也不包含 Claude Code、Codex、Cursor、Windsurf 等偏 coding-rule 的集成。这个功能的目标是“每日记忆分发”，不是“项目指令管理”。

第一版的体验应该足够简单，普通用户也能理解：

1. 打开 `Sync Memory`
2. 让应用自动探测可能的目标路径
3. 首次确认或修改一次路径
4. 点击 `Sync Now`，或者开启 `Auto Sync Daily`

初始化完成后，Know You 应该能在用户登录后自动生效，并按每天固定时间处理后续复制。

## 问题

Know You 已经能在本地生成每日 Markdown 日记，但依赖外部知识工具的用户，仍然需要手动把这些内容搬过去。这会打断“本地优先，但也能接入外部记忆系统”的产品叙事，让每日记忆采集显得不完整。

当前产品缺的不是日记生成，而是缺少一个从 Know You 每日日记输出，平滑接到外部记忆系统的桥梁。

## 目标

1. 在主窗口左下角 settings / `...` 入口下增加一个清晰、可理解的 `Sync Memory` 二级菜单项。
2. 在 V1 支持两个每日记忆目标：
   - Obsidian
   - OpenClaw
3. 通过路径探测和合理默认值，让首次配置尽量自动化。
4. 允许用户一键触发手动同步。
5. 支持用户登录后、每天固定一次的自动同步。
6. 清楚展示每个渠道的就绪状态和最近一次同步结果。

## 非目标

V1 不包含以下内容：

- Claude Code 集成
- Codex / Gemini / Cursor / Windsurf / Copilot / Continue / Cline 支持
- 双向同步
- 每次日记刷新成功后立刻增量同步
- 直接编辑外部文件
- 替换或覆盖 OpenClaw 原生 daily memory 文件
- 让用户手工输入任意路径字符串

## 为什么只做这两个渠道

### Obsidian

Obsidian 天然适合作为目标，因为它本身就是用户选择的本地 Markdown vault。Know You 可以把日记复制进 vault 里的一个固定子目录，不需要依赖专有 API。

### OpenClaw

OpenClaw 相关，是因为它本身有记忆机制。但 Know You 不应该接管或覆盖 OpenClaw 自己的 daily memory 文件。更合理的方式是：把 Know You 的日记复制到 OpenClaw workspace 里一个独立的 Know You 子目录，让 OpenClaw 把它当作额外 memory 读取和搜索。

### 为什么不做 Claude Code

Claude Code 官方的 memory 更接近 instruction / context 文件系统，例如 `CLAUDE.md`、imports、local overrides，而不是第一类“按天组织的个人工作记忆渠道”。因此它不适合作为这个功能的第一版目标，后续如果需要，可以单独定义成“agent context bridge”功能。

## 考虑过的方案

### 方案 A：一开始就做通用多工具同步面板

直接做一个灵活的 channel 系统，从第一版就支持很多工具。

优点：

- 初始覆盖面更广
- 后续抽象上更通用

缺点：

- 在每日记忆流程还没验证前就先把范围做大
- 会把 UI 推向更复杂的配置面
- 会把真正的 daily memory 渠道和 coding-rule 渠道混在一起

### 方案 B：只做两个 daily memory 渠道，用应用管理的同步流完成

V1 只围绕 Obsidian 和 OpenClaw 做。由应用负责路径探测、文件复制和每日调度；自动同步优先通过用户级 LaunchAgent 实现，在用户登录后按固定时间执行。

优点：

- 更贴近真实产品目标
- 用户心智更简单
- 避免不稳定或相关性弱的集成
- 实现风险更低

缺点：

- 需要额外处理 LaunchAgent 安装、更新和修复
- 其他 agent 渠道需要留到后面再做

### 方案 C：从第一版就做系统级后台同步

和方案 B 的渠道范围一致，但进一步扩展到更重的后台系统能力，例如更复杂的系统守护进程方案或额外后台基础设施。

优点：

- 自动化故事更完整

缺点：

- 实现和支持成本更高
- 文件访问与后台任务的边界情况更多
- 对验证这个功能的核心价值不是必须的

### 推荐

选择 **方案 B**。

它可以用相对可控的产品和实现风险，把用户真正想要的价值交付出来。用户会获得可见的同步入口、一次性初始化、手动同步和可预期的每日自动同步，而不需要自己接触 plist、终端命令或后台任务细节。

## 用户体验

## 入口

这个功能不是右上角一级按钮，而是放在主窗口左下角 settings / `...` 入口下的一个二级菜单项：`Sync Memory`。

一级入口仍然保持现有的 settings / `...` 语义，不新增新的高频主按钮。二级菜单项应当用容易理解的同步 / 存储类图标，并配合清晰的 `Sync Memory` 文案。

点击二级菜单项后，再进入同步面板。

## 面板结构

点击 `Sync Memory` 后，弹出一个紧凑面板，包含：

1. 两张渠道卡片：
   - Obsidian
   - OpenClaw
2. 一个全局 `Sync Now` 按钮
3. 一个 `Auto Sync Daily` 开关
4. 最近一次成功同步时间或最新错误摘要

每张渠道卡片应显示：

- 渠道图标或可识别的符号
- 渠道名称
- 状态灯
- 当前路径摘要
- `Change Folder`
- 当路径就绪时显示 `Open Folder`

## 状态模型

每个渠道应当暴露以下产品状态之一：

- `Detecting`
- `Ready`
- `Needs confirmation`
- `Missing`
- `Error`

颜色可以辅助理解，但文字状态必须清楚，不能只靠灯色表达含义。

## 渠道行为

### Obsidian

Know You 应该先自动探测可能的 vault。即使探测到一个或多个候选 vault，V1 也仍然需要用户首次确认一次最终目标。

配置完成后，Know You 会把同步文件写入所选 vault 中的固定子目录：

`Know You/Daily Memories/`

这些同步文件应该保持为普通 Markdown，用户可以在 Finder 或 Obsidian 中直接查看。

### OpenClaw

Know You 应该按照 OpenClaw 当前的默认 workspace 约定和兼容性 fallback 去自动探测 workspace。探测成功后，Know You 应该在其中创建并使用一个独立子目录：

`<openclaw-workspace>/know-you-memory/`

这个目录必须和 OpenClaw 自己的原生 daily memory 文件隔离。Know You 的职责是把额外记忆材料放到 OpenClaw 可读取的 workspace 里，而不是替换或覆盖 OpenClaw 的 daily-memory 机制。

如果探测到的 workspace 不正确或不标准，用户仍然可以手动改选目录。

## 文件模型

Know You 仍然是日记生成的唯一事实来源。

同步功能只是把 Know You 已有的每日 Markdown 输出复制到外部目标，而不是在 V1 里为每个渠道生成一套不同格式的内容。

推荐的目标文件名：

`YYYY-MM-DD.md`

这样可以让两个渠道的文件结构都保持稳定、可读、可排查。

## 同步语义

## 手动同步

`Sync Now` 会把当前符合条件的每日记忆文件复制到所有已启用、已就绪的渠道。

V1 应采取保守策略：

- 只覆盖 Know You 自己写入目标目录的文件
- 不修改用户无关文件
- 一个渠道失败时，不阻塞另一个渠道继续成功

## 自动同步

V1 支持每天固定一个时间点的自动同步，优先通过用户级 LaunchAgent 实现。

行为如下：

- 用户开启 `Auto Sync Daily`
- 用户选择每天的一个固定时间
- LaunchAgent 在用户登录后自动生效
- Know You 每天到这个时间点执行一次同步

这里的语义应当明确为“用户登录后自动生效”，而不是“机器未登录时也会运行”。

## 复制范围

V1 同步的是 Know You 已生成的每日日记文件，而不是任意历史导出，也不是整个 vault 内容。

第一版的规则调整为：

- 首次同步时，把当前所有符合 `YYYY-MM-DD.md` 命名规则的每日日记复制到每个已启用渠道
- 后续同步时，继续按同名文件覆盖方式补齐和更新这些日记
- 不删除目标目录里已有的其他历史文件

这样用户在 Obsidian 和 OpenClaw 中看到的是完整日记历史，而不是只看到当天最新一篇。

## 路径探测

## Obsidian 探测

Obsidian 路径探测应当：

1. 搜索可能的 vault
2. 识别哪些候选目录看起来像真实 vault 根目录
3. 把探测结果作为预填默认值展示给用户
4. 允许用户通过文件夹选择器替换该路径

应用不能依赖“文件夹名称叫 Obsidian”来判断 vault。有效 vault 应由目录结构判断，而不是名称判断。

## OpenClaw 探测

OpenClaw 路径探测应当：

1. 优先使用当前默认 workspace 约定
2. 检查已知兼容 fallback
3. 在解析出的 workspace 中创建 `know-you-memory/`
4. 如果有必要，允许用户手动改选

## 持久化

应用需要持久化以下信息：

- 每个渠道是否启用
- 已确认的目标目录 bookmark / path
- 最近一次路径探测结果摘要
- 自动同步是否开启
- 每日同步时间
- 最近一次成功同步时间戳
- 最新同步错误摘要

这些配置应属于新的 sync-memory 配置模型，而不是并入 summarizer 配置。

## 失败处理

失败必须是渠道级、可理解的。

例如：

- Obsidian vault 被移动
- OpenClaw workspace 不存在
- 目标目录不可写
- 源日记文件不存在

UI 行为要求：

- 将失败渠道显示为 `Error`
- 保持另一个渠道仍然可用
- 保留最后一次有效路径，便于修复，而不是强制重新配置
- 以内联方式显示简短、可读的人类错误说明

## 测试

V1 需要增加聚焦测试，覆盖：

- 路径探测 helper
- 目标路径解析
- 渠道状态推导
- 同步规划逻辑
- 两个渠道的复制行为
- 单渠道失败时的局部恢复
- 应用运行期间的每日自动同步调度逻辑

UI 测试或 view-model 测试应覆盖：

- 工具栏按钮可见性
- 已探测 / 未配置状态下的面板表现
- 开启自动同步
- 手动同步后的状态更新

## 架构影响

预计新增以下区域：

- sync-memory 配置模型
- 路径探测 helper
- 文件复制服务 / sync coordinator
- LaunchAgent 安装与状态管理
- settings / `...` 二级菜单入口与同步面板 UI

设计上必须让 sync-memory 逻辑和 diary-engine 选择器分离，也必须和日记生成流程解耦。这个功能只是消费现有日记输出，不应改变生成行为。

## 已确认的问题

- V1 渠道：只做 `Obsidian` 和 `OpenClaw`
- Claude Code：不进入 V1
- Obsidian 目标目录：固定为 `Know You/Daily Memories/`
- OpenClaw 目标目录：固定为探测到的 workspace 下的 `know-you-memory/`
- OpenClaw 原生 memory 文件：不替换，不覆盖
- 自动同步时机：每天固定一次
- 入口位置：左下角 settings / `...` 下的二级菜单
- 后台模型：V1 优先采用用户级 LaunchAgent，用户登录后自动生效

## 后续扩展

后续可以考虑：

- Claude Code context bridge
- 更多 agent 渠道
- 可配置的历史同步窗口
- 渠道级模板或汇总格式
