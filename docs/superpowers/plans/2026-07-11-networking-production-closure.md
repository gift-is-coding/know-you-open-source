# Networking 生产闭环实施计划

## 成功标准

- `networking.giiift.site` 可公开访问并连接现有 Supabase。
- 本地 KnowYou 能完成线上 handoff、发帖和网页回读。
- 敏感激活凭据只保存在 Keychain，旧状态安全迁移。
- 最终 Claude Terminal review 无 P0、P1、P2。

## 任务

- [ ] 先写配置解析、Keychain 持久化、旧身份保护和 Web profile 所有权失败测试。
- [ ] 实现 `webBaseURL` 配置持久化及线上默认配置生成路径。
- [ ] 实现 Networking Keychain secret store 和旧 JSON 原子迁移。
- [ ] 阻止旧 platform 状态在凭据缺失时静默创建新身份。
- [ ] 增加 Web server action profile 所有权校验和无 profile 交互提示。
- [ ] 升级 production review skill：使用 `npm start`、Release build 和本地已认证 Claude CLI。
- [ ] 跑 Web focused/full、Swift targeted/full、Debug/Release 构建及安全检查。
- [ ] 部署 Vercel，绑定 `networking.giiift.site`，校验环境变量、RLS 与线上健康状态。
- [ ] 启动本次新构建 App，完成真实 handoff、发帖、刷新和线上回读。
- [ ] 循环执行 Claude review，验证并修复所有 P0/P1/P2。
- [ ] 复跑全量验证，更新架构/需求文档并提交本地 commit。

