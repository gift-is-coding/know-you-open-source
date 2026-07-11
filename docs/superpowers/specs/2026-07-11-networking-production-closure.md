# Networking 生产闭环设计

## 目标

把 Networking 从本地可演示状态推进到可验证的生产闭环：线上 Web 使用 `networking.giiift.site`，本地 KnowYou Release/Debug 构建都能发现该地址，用户从 App 完成身份交接后可发帖并在网页回读；本地 Claude Terminal 持续 review，直到没有 P0、P1、P2。

## 已验证风险

- Release 构建只读取进程环境中的 Web URL，Finder 启动时无法稳定打开线上 Square。
- 激活状态把机器密码、agent token 和 refresh token 明文写入 `.knowyou/networking/activation.json`。
- 旧状态缺少机器凭据时会创建新身份，可能让已发布资料与本地身份断开。
- Web server action 依赖 RLS 拒绝伪造 `profileID`，缺少应用层所有权校验和对应行为测试。
- pipeline 构建生产包后仍用开发服务器验收，且只启动 Debug App，不能证明生产路径成立。

## 设计

### 生产配置

`NetworkingPlatformConfig` 增加 `webBaseURL`，并由 `.knowyou/networking/platform.json` 持久化。环境变量仍拥有最高优先级；文件配置作为 Finder/Release 的稳定来源；Debug 在两者都缺失时才回退本地 `127.0.0.1:3028`。

### 本地秘密

Networking 复用项目现有 `KeychainStoring`。JSON 只保存非敏感元数据和 Keychain account 标识；机器密码、agent token、refresh token 写入 Keychain。加载旧 JSON 时执行原地迁移：先写 Keychain，再以无明文格式覆盖文件。迁移失败不得删除旧数据，也不得继续创建新机器身份。

### 身份连续性

已有 platform 状态但无法取得机器凭据时，激活流程必须以可操作错误停止，不得自动 signup。只有从未连接过 platform 的状态才允许创建新机器身份。

### Web 写入授权

发帖和评论 server action 在 insert 前查询当前用户拥有、且属于当前平台的 profile。RLS 继续作为最终边界；应用层返回明确错误。测试覆盖伪造另一用户 profile 的请求。

### 生产验证

- Web 以 `npm run build && npm start` 验证 HTML、CSS、认证交接和发帖回读。
- App 同时验证 Debug 与 Release 配置，启动本次 DerivedData 的新构建。
- 线上部署使用现有 `knowyou-networking` Supabase 项目和 Vercel，域名为 `networking.giiift.site`。
- 使用真实本地 App 身份完成 handoff、发帖，并从线上页面和 Supabase 数据双向确认。
- Claude Terminal 以代码功能、App UX、Web UX、安全和生产运维为视角 review；每轮逐项复核并修复，直到无 P0/P1/P2。

## Benchmark 与验收用例

1. Release App 无环境变量时能从平台配置得到 `https://networking.giiift.site`。
2. 新激活及旧状态迁移后，`activation.json` 不包含密码、agent token、refresh token。
3. 已连接但凭据缺失时零 signup、零 person/profile 写入，并显示恢复提示。
4. 用户 A 不能以用户 B 的 profile 发帖或评论；应用层与 RLS 均拒绝。
5. `npm start` 下首页、认证交接、发帖、评论、刷新回读通过；静态资源无 4xx/5xx。
6. App handoff 后浏览器保持正确 platform，上线帖子刷新后仍可见。
7. 完整 Web test/lint/typecheck/build、Swift targeted/full test、Debug/Release build 全部通过。
8. 最后一轮 Claude review 明确没有 P0、P1、P2。

