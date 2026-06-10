# KnowYou Networking Profile-First Redesign 实施计划

## 目标

按用户提供的 Claude 设计重做 Networking V1 的本地 app 和网页端视觉/信息架构。重点从 agent cockpit 改成 profile-first：先生成场景化 profile，再把 profile 配给平台，平台使用该 profile 进行长期 agent 自动化互动。

## 步骤

1. 扩展本地 Networking 模型。
   - 增加 profile scenario、profile prompt、profile summary section、avatar fallback、platform config。
   - 增加测试覆盖：scenario prompt 生成 profile draft；平台必须绑定已生成 profile；头像 fallback 不依赖混乱 image slot。

2. 重做 macOS 本地 Networking view。
   - 仍使用 WebView，方便快速迭代。
   - HTML 结构改成上方 Profile Generator、下方 Platform Area、右侧轻通知 rail。
   - 使用 Claude 设计的 editorial text-forward 视觉，保留干净头像 fallback。

3. 重做 Web Public Square。
   - 改成 Claude 设计里的三栏 public square：左侧 topics/following，中间 feed/composer，右侧当前平台 profile 和 24h activity。
   - 使用当前 Supabase 数据接口和 fixture fallback。
   - 保留人/AI 混排、AI 标注、人优先排序、自由文本。

4. 更新测试。
   - Web tests 覆盖 sample data、profile/platform mapping、AI label。
   - Swift tests 覆盖 profile prompt/platform config 模型。

5. 验证。
   - `npm run lint`
   - `npm run typecheck`
   - `npm test -- --run`
   - `npm run build`
   - targeted XCTest
   - full `xcodebuild test -scheme KnowYou -destination 'platform=macOS'`
   - full `xcodebuild build -scheme KnowYou -destination 'platform=macOS'`

## 非目标

- 不接真实跨平台账号。
- 不做图片上传。
- 不新增 Supabase schema。
- 不改变现有 RLS/agent token 远端逻辑。
