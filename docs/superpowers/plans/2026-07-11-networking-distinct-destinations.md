# Networking 双站点体验实施计划

1. 更新 Web 契约测试，先覆盖 destination link、单一平台数据源、inactive `hidden`、双主题 token、结构分叉、移动 composer、avatar 对比度和假按钮移除，并确认测试按预期失败。
2. 重构 `SquareTabs` 为 destination switcher：真实链接 + client-side interception、整页 active theme、inactive panel hidden、reduced-motion 进入动效。
3. 重构 `PublicSquarePage` / `SquarePanel`：由 `networkingPlatforms` 驱动；按 scenario 输出 Careers/Friends 的结构 class、hero、composer 文案、feed metadata 与辅助 rail。
4. 重构 CSS token 和 responsive layout：Careers 冷蓝职业网络、Friends 明亮时间线；360px composer 分行；focus-visible 与 avatar fallback 对比度。
5. 接入 KnowYou 自有 logo 视觉资产，不引入第三方平台商标或抽象装饰图。
6. 运行 unit、lint、typecheck、audit、OpenNext build；Playwright 检查桌面/移动、切换、单一 h1、无水平 overflow 和 production E2E 隔离。
7. 部署 Cloudflare Worker，验证线上 HTML/CSS/截图；调用本地 Claude 复审，验证并修复所有真实 P0/P1/P2，循环到清零后提交。

