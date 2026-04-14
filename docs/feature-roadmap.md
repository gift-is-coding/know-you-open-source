# Know You Feature Roadmap

这个文件用来维护产品功能清单，尽量保持简单，只记录粗颗粒度状态，方便持续增补和修改。

更新时间：2026-04-14

## 未完成

- [ ] 品牌命名探索：评估是否需要改名，找到更直观、更容易传播的产品名字
- [ ] 搜索功能：搜索历史上的相应事件，做语义 + 文本的混合式搜索
- [ ] 记忆导出功能：把 General 记忆导出到 Openclaw / Claude Code
- [ ] Obsidian 同步：把日记与相关产物同步到用户现有的 Obsidian vault
- [ ] 更多输入来源：不只采集剪贴板与通知，还要扩展浏览器、文件、邮件、日历、会议等上下文来源
- [ ] 登录保存内容 / 远端同步：支持不同终端之间同步
- [ ] 手机端能力：不只是移动端查看，还要探索手机侧输入、补充记录与上下文采集
- [ ] 付费功能：具体付费方式暂未确定
- [ ] 结构化 diary 生成控制：不要再暴露 raw prompt 编辑；改为探索受限的风格/语气、Summary 密度、Details 分组强度等可控配置

## 已完成

- [x] macOS 本地优先桌面应用基础形态
- [x] 自动采集电脑上下文：剪贴板监听 + Notification Center 通知导入
- [x] 持久化前隐私过滤与本地 SQLite 存储
- [x] 按天生成日记内容，并输出 `.story.json` 与 Markdown 文件
- [x] Story-first 三栏阅读器：日期列表、日记正文、来源追溯
- [x] 段落级 source link 与原始事件查看
- [x] 启动补跑、定时刷新、今日通知增量同步等自动化能力
- [x] Onboarding、Settings 与 Vault 路径配置
- [x] 多种 diary engine 接入与切换：OpenAI、Claude Code、Codex、Gemini、Openclaw
- [x] 联系方式、社区入口、隐私/条款/上线清单等产品外围页面入口
