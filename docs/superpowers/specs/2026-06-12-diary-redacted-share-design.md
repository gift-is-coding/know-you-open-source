# 日记脱敏分享设计

## 背景

KnowYou 的日记已经是可读的 story，而不是原始事件流水账。分享功能要利用这一点，让用户把当天有趣的日记片段变成适合社群传播的图片，同时不破坏产品一直强调的本地优先和隐私边界。

## 目标

- 用户可以从 `My Diary` 的日记顶部分享当天全文。
- 用户可以从日记正文段落的右键菜单分享局部内容。
- 默认分享为脱敏副本，用户可以明确取消脱敏后再分享。
- 分享结果是一张可复制到剪贴板或保存的图片，图片右下角包含 KnowYou 下载地址和二维码。
- 生成图片只使用当前 UI 已加载的 `DailyStory` 内容，不读取 SQLite 原始事件，不把分享内容发送到服务端。

## 非目标

- 不做社交平台 API 发布。
- 不做云端短链、点击统计或用户归因。
- 不修改日记生成、采集入库或 My Wiki ingest 逻辑。
- 不把右侧 source detail 的原始事件纳入分享图片。

## 用户体验

### 顶部全文分享

在日记日期 header 右侧、刷新控件旁增加 `脱敏分享` / `Share Redacted` 按钮。点击后在 header 下方展开一个轻量分享面板：

- `脱敏` checkbox 默认勾选。
- 用户取消勾选后，按钮文案切换为非脱敏分享语义。
- 面板提供 `复制图片` 和 `保存图片` 两个动作。
- 当前日期没有 story 段落或处于 Demo Day 时，分享动作禁用并显示温和提示。

### 划选与段落右键分享

每个 story 段落提供 context menu：

- `脱敏分享`
- `非脱敏分享`

正文允许文本选择。右键分享优先读取当前窗口的 AppKit selection，并校验划选文本属于当前段落；如果没有稳定 selection，则回退分享当前段落的 Markdown 文本。

### 分享图片模板

图片模板为单张竖向卡片，适合微信群、Discord、X 和小红书截图流：

- 顶部显示日期和 `KnowYou Diary`。
- 中部显示日记正文，保留基础 Markdown 语义的纯文本化结果。
- 右下角显示下载地址 `giiift.site/know-you/download` 和二维码。
- 底部显示 `Shared from KnowYou`。
- 脱敏图片显示 `Redacted share` 标记，非脱敏图片显示 `Original share` 标记。

## 脱敏策略

新增分享专用 `DiaryShareRedactor`，不复用入库用 `PrivacyFilter` 的 drop 语义。原因是分享图需要保持可读性，而采集入库的过滤逻辑是持久化安全边界。

V1 脱敏规则：

- email -> `[email]`
- URL query / fragment -> 保留 host/path，移除 `?query` 和 `#fragment`
- 长数字、银行卡、订单号、手机号等 11 位以上连续数字 -> `[number]`
- password / token / secret / api key / bearer 等键值片段 -> `[secret]`
- 明显 private key block -> `[secret block]`

脱敏是保守展示层处理，不承诺覆盖所有个人身份信息。UI 默认勾选脱敏，降低误分享风险。

## 架构

新增三个轻量边界：

- `DiaryShareContentBuilder`：从 `DailyStory` 或 `DailyStoryParagraph` 生成分享文本。
- `DiaryShareRedactor`：对分享文本做展示层脱敏。
- `DiaryShareImageRenderer` / `DiaryShareTemplateView`：把分享 payload 渲染成 `NSImage`。

`DailyMarkdownView` 只负责入口和交互状态；`MainWindowView` 把当前 story、日期和操作闭包接起来；AppState 不持久化分享状态。

## 错误处理

- 没有 story 内容：禁用分享按钮。
- 图片生成失败：分享面板显示 `Could not create share image.`。
- 剪贴板写入失败：显示 `Could not copy image.`。
- 保存失败：显示系统错误摘要，不弹侵入式全局 alert。

## 测试

必须覆盖：

- 分享全文时按 story 段落顺序合并文本。
- 分享划选文本时只包含该选区；没有稳定划选时只包含该段落文本。
- 脱敏规则覆盖 email、长数字、secret、URL query。
- 脱敏默认开启，非脱敏不会修改文本。
- 顶部分享 presentation 在无内容时禁用。
- context menu action 能把划选文本或段落回退分享请求传给上层闭包。
- 图片 payload 包含下载 URL 和二维码文本来源。

## 验收标准

- 日记顶部出现可用的分享入口，默认是脱敏分享。
- 用户能取消脱敏并生成非脱敏分享图片。
- 划选文字后右键菜单提供脱敏与非脱敏分享；没有稳定选区时回退当前段落。
- 生成图片可复制到系统剪贴板，也可保存为 PNG。
- 图片包含 KnowYou 下载地址和二维码。
- 实现不读取原始 SQLite 事件，不上传分享内容。
