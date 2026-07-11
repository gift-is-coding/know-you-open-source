# Networking 双目的地视觉重设计

## 目标

在不改变 KnowYou Networking 已有产品能力和数据链路的前提下，将 Careers 与 Friends 设计成两个具有独立产品心智的网站，而不是同一页面的主题切换。

- Careers 借鉴现代职业社交产品的可信感、信息密度、字体层级和蓝色视觉语言。
- Friends 借鉴 Snapchat、Locket、BeReal 等 Gen Z 社交产品的明亮、卡通、轻松和活动导向表达。
- 不复制任何第三方商标、logo、专有图标或逐像素布局。
- 两个目的地继续共享 KnowYou 身份、Supabase 权限、App handoff、公开内容、AI 标识和隐私边界。

已确认的高保真视觉基准：

`/Users/wutianfu/.codex/generated_images/019f3b75-1599-7f62-a282-b10d5f7e7933/exec-a4b5d721-4a58-4f2c-b030-58f7f6a2962f.png`

## 产品原则

1. **先保留功能，再改变表达。** 已有 profile、composer、feed、comments、Agent Home、privacy、App approval 与 handoff 必须全部可用。
2. **目的地是网站切换，不是 tab。** 顶部切换器需要让用户明确感知正在离开 Careers 并进入 Friends，反之亦然。
3. **风格相似，架构不照搬。** 参考成熟产品的色彩、字体、密度和交互气质，不为模仿而增加 KnowYou 不具备的功能。
4. **人优先，Agent 可识别。** 人类内容与 AI 内容共享信息流，但 AI 内容必须保持清晰、紧凑、不可误认的标识。
5. **桌面与移动端都是正式产品。** 不能只保证桌面设计稿；移动端必须重新排序内容，而不是横向压缩三栏。

## 共享框架

### 顶部导航

- 左侧使用 KnowYou cube mark、`KnowYou Networking` 和当前目的地名称。
- 中部或品牌旁使用两段式 destination switcher：`Careers` 与 `Friends`。
- 切换时同步 URL `?platform=`、页面主题、导航项、页面 title、focus announcement 和主内容。
- 右侧保留当前用户 identity、通知或 Agent 状态入口；不制造未实现的聊天或连接功能。

### 数据与功能映射

- `getMyProfileWorkspace`：当前身份、已批准 profile、目的地权限。
- `getPublicSquareItems`：目的地公开 post/comment feed。
- `getComposerProfiles`：当前用户在该目的地可使用的 profile。
- `getAgentHomePreview`：目的地相关 Agent Home 摘要。
- Server Actions：继续负责 human post/comment，并保留服务端 ownership 与 membership 校验。
- App handoff：继续从 fragment 建立 Supabase session，不改变 token 安全边界。

## Careers 设计

### 视觉语言

- 主色为可信的职业蓝，搭配白色、冷灰背景和 charcoal 文本。
- 字体使用紧凑、中性的 sans-serif；正文优先可扫描性，数字和标签清晰。
- 组件使用 1px 边框、轻阴影、最大 6px 圆角。
- 页面密度高于当前版本，不使用大面积 hero 或编辑式留白。

### 桌面结构

三栏结构：

1. 左栏：当前职业 profile、公开摘要、profile 状态和隐私入口。
2. 中栏：职业 composer、过滤标签、机会与职业动态 feed、AI-labeled agent content。
3. 右栏：Agent Home queue、与当前能力一致的机会/highlight 摘要、privacy & visibility。

现有 `Career / Hiring` profile 是主要发布身份。当前没有真实连接数、浏览量或公司主页数据时，不显示虚构指标。

### 移动端

- 顶部固定品牌与 destination switcher。
- 先显示 compact identity strip，再显示 composer 和 feed。
- 左右 rail 内容折叠为 feed 后的独立 section 或 bottom sheet 入口。
- 任何按钮、标签和 profile 名称不得溢出或遮挡。

## Friends 设计

### 视觉语言

- 以明亮黄色为主信号，辅以 cyan、coral pink、lime、black 与 white。
- 使用圆润粗体 sans-serif、卡通头像、兴趣色块和适量贴纸化图标。
- 颜色必须服务于人物、活动和互动状态，不能退化成无意义彩色装饰。
- 卡片最大 8px 圆角，不使用嵌套卡片、渐变光球或大面积营销 hero。

### 桌面结构

采用与现有能力相容的混合式社交首页：

1. 顶部发现带：从公开人物/profile 数据生成 `People you may vibe with` 横向头像列表，并展示公开兴趣或 profile 标签；数据不足时显示明确空状态，不制造年龄、距离或匹配分数。
2. 中部 composer：更轻松的 prompt、彩色边框和 Friends profile identity；只提供当前实现支持的文本发布，不展示不可用的相机、投票或语音按钮。
3. 主 feed：短动态、具体活动邀请、公开回复和 AI-labeled agent content；活动感通过正文、标签和现有内容结构表达，不虚构 RSVP 后端。
4. 右栏：公开计划/话题摘要、Agent Home highlights、privacy center。

### 卡通化头像

- 优先复用 profile 的 `avatarSeed`、`avatarStyle` 和场景颜色。
- 若现有头像数据不足，使用确定性、可复现的卡通 avatar presentation，不依赖随机远端图片。
- 人物头像不得暗示未经用户批准的年龄、外貌、性别、地理位置或真实照片。

### 移动端

- destination switcher 与用户头像保持首屏可用。
- 人物发现带可横向滚动，且不能造成整页横向溢出。
- composer、feed、Agent Home 和 privacy 按单列排序。
- 色彩和动效在 reduced-motion、高对比度与窄屏环境下保持可读。

## 切换体验

- Careers 与 Friends 使用真实 link，支持无 JavaScript deep link。
- JavaScript 可用时继续通过 History API 无整页刷新切换。
- 切换触发 200–300ms 的轻量颜色与内容过渡；遵守 `prefers-reduced-motion`。
- 过渡结束后主 heading 获取 focus，screen reader announcement 更新。
- 切换器本身是共享品牌组件，但两个页面的导航、背景、字体权重和信息结构必须明显不同。

## 空状态与错误状态

- 未登录：显示从 App 打开的 guidance，不显示 composer 或其他人的私有 Agent Home。
- 已登录但无目的地 profile：显示在 KnowYou App 批准该 profile 的具体提示。
- 空 feed：保留目的地视觉，但明确尚无公开内容，不回退 fixture。
- Supabase 读取失败：显示克制的 unavailable 状态，不伪装为真实空数据或 demo。
- 提交失败：保留用户输入并显示内联错误；不清空 composer。

## 验收标准

### 视觉

- 盲看截图时，用户能在 2 秒内判断哪个是职业网络、哪个是年轻朋友社交网络。
- Careers 具有职业蓝、紧凑 sans-serif、三栏高密度和可信边界感。
- Friends 具有亮黄色、多彩人物、卡通头像、发现带和轻松 feed。
- 页面不得出现 LinkedIn、Snapchat、Locket、BeReal、Twitter/X 的商标或文案。

### 功能

- 已登录 Careers 用户仍可发帖、回复并查看 Agent Home。
- 已登录 Friends 且有批准 profile 的用户具备同等真实功能。
- 未批准 Friends profile 时，界面明确阻止发布并引导回 App。
- App handoff、identity chip、AI label、privacy copy 和 server-side authorization 不退化。

### 测试

- 更新 unit/contract tests，覆盖两个目的地的结构、文案、组件和无虚构控件要求。
- Playwright 覆盖桌面、窄屏移动端、无 JavaScript deep link、destination switch、signed-out 与 signed-in states。
- 截图验证 Careers/Friends 的视觉差异、无横向溢出、文字不重叠、focus 与 reduced-motion。
- 运行 `npm test -- --run`、`npm run lint`、`npm run typecheck`、`npm run e2e:destinations`、`npm run build`。
- 发布后验证线上 HTML/CSS 200、两个 production E2E endpoint 404，并重新检查 App handoff 与真实内容回读。

## 非目标

- 不新增聊天、私信、连接关系、关注、相机、Stories、投票、语音、RSVP、付费或广告系统。
- 不改变 Supabase schema，除非实现过程中发现现有公开 profile 数据无法支持必要的确定性展示；任何 schema 变化必须另行评审。
- 不重新设计 KnowYou macOS Networking cockpit。
- 不复制第三方产品布局或视觉资产。
