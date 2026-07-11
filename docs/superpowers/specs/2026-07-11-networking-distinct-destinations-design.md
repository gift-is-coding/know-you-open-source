# Networking 双站点体验设计

## 目标

把 `Know You Careers` 与 `Find Your Friends` 从同一页面中的两个 tab，升级为 KnowYou Networking 入口下的两个明显不同的产品空间。用户在不读取标题时，也应能凭布局、节奏、色彩和内容组织判断当前处于职业网络还是朋友网络。

## 设计原则

- 借鉴职业社交产品的身份与机会层级，以及公共时间线产品的即时对话节奏，但不复制 LinkedIn、X/Twitter 的商标、品牌蓝、导航或像素布局。
- 顶层 KnowYou 品牌、App-first handoff、AI 标签与隐私边界保持一致。
- 切换是进入另一个 destination，不是切换内容 tab：整页主题、hero、信息架构和 feed treatment 同步变化。
- 首屏直接呈现可用社区，不增加营销 landing page。

## Destination Switcher

顶部使用两个并列的 destination link：

- `Careers Network`：briefcase 图标、职业身份摘要、机会与协作描述。
- `Friends Network`：message-circle 图标、轻量对话摘要、活动与兴趣描述。

激活项拥有明确的背景、边框、状态文案与进入感；非激活项仍像可前往的另一个网站。链接必须保留真实 `href`，JavaScript 启用时进行无刷新切换，无 JavaScript 时仍可通过 query string 导航。切换时仅暴露一个 `h1` 和一个可访问 panel；动效遵守 `prefers-reduced-motion`。

## Careers Network

- 视觉：冷蓝、白色和少量金色 opportunity accent，紧凑边界与低圆角。
- 结构：职业身份 banner 与 profile 优先；主列是机会/协作讨论；右侧是 community guide、App agent queue 和隐私说明。
- Feed：帖子更像专业更新或机会卡，突出 profile label、topic、时间和讨论数量。
- Composer：提示聚焦 opportunity、hiring、collaboration、ask。

## Friends Network

- 视觉：明亮青绿、浅天空色与珊瑚互动点色，更开放的留白和圆形头像。
- 结构：composer 与时间线优先；社区状态和个人 profile 压缩为辅助信息；桌面主列更窄，移动端保持单列。
- Feed：帖子采用连续时间线节奏，减少外围卡框，评论与回复更贴近内容。
- Composer：提示聚焦 plan、interest、place、people to meet。

## 共用行为

- 只使用 `networkingPlatforms` 作为平台顺序与渲染来源。
- signed-out、signed-in/no-profile、active-profile 三种权限状态保持原有安全语义。
- inactive panel 使用 `hidden`，不进入辅助技术读取与键盘顺序。
- 删除没有行为的 `Save to App` 按钮；评论数显示为信息而非假按钮。
- avatar fallback 使用有足够对比度的深色背景；所有 destination link 与可交互控件具备 `focus-visible`。
- 360px 宽度下 composer 不横向溢出，输入区和操作区分行。

## 视觉资产

使用 KnowYou 自有 logo 作为产品品牌资产；社区差异通过真实 profile/feed 数据、图标与版式呈现，不使用抽象背景插画或第三方社交平台 logo。

## 验收 Benchmark

1. 1440x900 与 390x844 截图中，遮住文案后仍可凭视觉语言区分 Careers 与 Friends。
2. 两个 panel 至少在 accent、surface、hero、post treatment、layout rhythm 中有三项 computed-style 差异。
3. destination 为真实链接；JS 开启时无刷新切换，JS 关闭时 query URL 可访问对应空间。
4. 任一时刻只有一个可见 `h1` 和一个未隐藏的 community panel。
5. 360px 下无水平 overflow；composer 输入与操作不互相挤压；主要按钮高度至少 40px。
6. 键盘可见焦点、avatar 对比度和 reduced-motion 均通过检查。
7. Web unit、lint、typecheck、OpenNext build、Playwright 桌面/移动截图和生产 smoke 全部通过。

