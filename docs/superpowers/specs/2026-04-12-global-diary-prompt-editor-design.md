# 规格说明：全局 Diary Prompt 编辑器

**日期：** 2026-04-12  
**分支：** feature/global-diary-prompt-editor  
**状态：** Draft

---

## 一、问题

当前应用已经在主窗口右上角提供了 diary engine 的运行时入口，但 diary prompt 本身仍然被固定在生成层内部。

这带来三个明显产品缺口：

- 用户无法直接查看系统当前正在使用的默认 diary prompt
- 用户无法为自己的日记生成风格设置一个持久化的全局 prompt 版本
- 用户无法在主界面一级入口中控制“后续日记生成到底用系统默认 prompt，还是用自己的全局版本”

这个需求不是一次性的调试面板，而是一个明确影响后续日记生成结果的产品级全局配置能力。

同时，产品必须避免制造错误预期。修改 prompt 不应让用户误以为旧的 `.md` 或 `.story.json` 会被自动重写。

---

## 二、目标

1. 在主窗口右上角新增一个始终可见的 prompt 编辑入口。
2. 让用户可以直接查看系统默认 diary prompt。
3. 让用户可以编辑并持久化一个全局自定义 prompt。
4. 让用户点击 `Apply` 后，新 prompt 立即对后续日记生成生效。
5. 让用户点击 `Restore Default` 后，一键恢复系统默认 prompt。
6. 在界面上明确说明：prompt 改动只影响后续生成，不会自动改写旧内容。

## 三、非目标

- 不支持按单天定制 prompt
- 不因为 prompt 变更而回写旧的 `.md` 或 `.story.json`
- 不引入 prompt 历史版本、diff 或版本管理
- 不顺带重做整个 Settings 结构
- 不改变现有 diary engine selector 的交互职责

---

## 四、方案比较

### 方案 A：只在 Settings 中增加 prompt 编辑

复用现有设置入口，改动最小。

取舍：

- UI 改动最少
- 但入口太深，不符合“整个 APP 右上角可见入口”的需求
- 对一个会直接影响生成质量的能力来说，可发现性不足

### 方案 B：在右上角 diary engine selector 旁新增独立的 prompt 按钮

把 engine 选择和 prompt 定制作为并列的运行时控制项。

取舍：

- 最符合需求描述
- 信息架构最清晰：engine 控制“用谁生成”，prompt 控制“怎么生成”
- 需要新增一个 toolbar 控件和一个独立编辑面板

### 方案 C：把 prompt 编辑塞进现有 diary engine panel

继续复用已有右上角入口，不新增 toolbar 按钮。

取舍：

- 表面上按钮更少
- 但职责会混在一起，engine 可用性和 prompt 内容不是同一类配置
- 会让现有 engine panel 变成一个过载面板

### 推荐方案

选择 **方案 B**。

当前应用已经把右上角区域定义为“日记生成相关的运行时控制区”。在这个区域里增加一个独立 `Edit Prompt` 按钮，既延续现设计，也不会污染 engine selector 的职责边界。

---

## 五、设计

### 1. 右上角入口

主窗口 toolbar 应在现有 `DiaryEngineSelectorButton` 旁边新增一个 prompt 编辑按钮。

这个按钮应该：

- 位于同一组右上角 toolbar 控件中
- 延续当前按钮的视觉语言，不引入新的设计体系
- 文案明确表达用途，例如 `Edit Prompt`
- 点击后打开独立 prompt 编辑面板

这样用户会把它理解为与 engine selector 并列的“生成控制项”，而不是隐藏在设置里的二级项。

### 2. Prompt 编辑面板

点击按钮后，打开一个独立编辑面板。为了延续当前 API 配置的交互模式，优先采用 `sheet`。

面板必须包含四个部分：

1. 一段简短说明文字
2. 一个只读区域，用来展示系统默认 diary prompt
3. 一个可编辑文本区，用来输入用户自己的全局 prompt
4. 底部操作区，包含 `Apply`、`Restore Default`、关闭/取消

说明文字必须明确表达三件事：

- 这会影响后续 diary 生成结果
- 不会自动修改已经生成过的内容
- 只有在未来再次生成或刷新某一天时，新 prompt 才会体现在输出里

### 3. 默认 Prompt 可见性

用户必须能够在 UI 中直接查看系统默认 prompt，而不需要读源码。

默认 prompt 展示区域应满足：

- 只读
- 可滚动
- 文案来源于实际生产使用的 prompt 构造逻辑
- 清楚标记为“系统默认”，不能和用户自定义内容混淆

这样 `Restore Default` 才是可理解、可验证的，而不是一个黑箱按钮。

### 4. 全局自定义 Prompt 模型

应用应支持一个持久化的全局 prompt override。

行为规则：

- 当不存在自定义 prompt 时，生成逻辑使用系统默认 prompt
- 当存在已应用的自定义 prompt 时，后续生成逻辑使用该自定义 prompt
- 这个 prompt 是全局的，不绑定某一天
- 这个 prompt 在应用重启后仍然保留

这一能力应落在一个明确的 prompt 配置模型里，或作为现有配置模型的清晰扩展，而不是让 View 直接零散读写 `UserDefaults`。

### 5. Apply 语义

`Apply` 必须做两件事：

1. 持久化当前编辑中的全局 prompt
2. 立即更新应用内存中的生成配置，使后续生成路径使用新 prompt

`Apply` 明确不能做这些事：

- 不自动刷新当前选中日期
- 不自动回刷历史日期
- 不自动重写任何已存在的生成文件

产品语义应非常明确：

“从现在开始，未来的 diary 生成使用这个 prompt。”

### 6. Restore Default 语义

`Restore Default` 必须移除激活中的自定义 override，让应用回到系统默认 prompt。

行为规则：

- 编辑区应回到默认 prompt 内容，或清楚反映“当前没有 override”，具体以最终 UI 设计为准
- 持久化层不再保留激活中的自定义 override
- 后续 diary 生成再次走系统默认 prompt
- 已存在文件保持不变

该动作在当前编辑会话内应可逆，直到用户关闭面板或再次应用新的内容。

### 7. 生成链路接入

当前生产 prompt 的核心入口在 `DailyMarkdownComposer.storyPrompt(dayKey:events:)`。

这次改动应保持一个唯一、可信的 prompt 构造边界：

- 默认 prompt 构造仍然留在 composer / generation 层
- override 的解析发生在把最终 prompt 字符串交给 summarizer 之前
- 测试必须覆盖默认 prompt 路径和自定义 prompt 路径

UI 不应复制一份“看起来差不多”的 prompt 模板做展示。编辑器看到的默认 prompt 和实际生成时使用的默认 prompt，必须来自同一份 canonical source。

### 8. 旧内容安全性

UI 和运行时行为必须把“不会自动改旧内容”作为硬规则表达清楚。

硬约束：

- 编辑或应用 prompt 时，不得修改磁盘上已存在的 `DailyStory` 工件
- 编辑或应用 prompt 时，不得修改磁盘上已存在的 Markdown 导出
- 新 prompt 只会在未来某一天再次生成时影响该天输出

这能避免用户误以为 prompt 编辑是一种“历史迁移”操作。它本质上只是后续生成输入的变化。

### 9. 测试范围

这个功能至少应覆盖三层测试：

#### Prompt 配置测试

- 没有 override 时，默认状态加载正确
- 保存并重新加载全局自定义 prompt
- `Restore Default` 后 override 被清除

#### Composer / 生成测试

- 没有 override 时，默认 prompt 输出不变
- 有 override 时，后续 summarizer 生成使用自定义 prompt
- `Restore Default` 后，生成路径回到系统默认 prompt

#### 主窗口 / 交互测试

- 主窗口 toolbar 中存在新的 prompt 编辑按钮
- 打开编辑器后能看到“只影响后续生成，不自动改旧内容”的说明
- `Apply` 会更新应用状态，但不会自动触发重新生成
- `Restore Default` 会重置当前激活的 prompt 配置

---

## 六、预计改动文件

- `KnowYou/UI/MainWindowView.swift`
- `KnowYou/Services/Composer/DailyMarkdownComposer.swift`
- `KnowYou/App/AppState.swift`
- `KnowYou/Services/Summary/SummarizerConfig.swift`，或者拆出一个更清晰的 prompt 配置文件
- 新增 prompt 编辑 UI 文件，放在 `KnowYou/UI/Reader/` 或现有配置相关目录下
- `KnowYouTests/` 中对应的聚焦测试文件

---

## 七、验收标准

满足以下条件时，功能可视为完成：

1. 主窗口右上角出现独立的 prompt 编辑按钮。
2. 用户可以打开编辑器并查看当前系统默认 diary prompt。
3. 用户可以编辑并应用一个全局自定义 prompt。
4. 应用会把该自定义 prompt 用于后续 diary 生成。
5. 用户可以一键恢复系统默认 prompt。
6. UI 明确说明：prompt 改动只影响后续生成，不会自动修改旧内容。
7. 仅仅修改 prompt 设置本身，不会导致任何历史 diary 工件被自动重写。
