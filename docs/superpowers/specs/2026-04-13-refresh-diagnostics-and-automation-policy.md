# 刷新诊断与自动化策略设计

## 背景

当前刷新链路已经从“整天重写”收敛到“成功 story 后只做增量”，但还有三个产品层问题必须一起解决：

- 用户看不到每次刷新到底慢在哪一段
- 手动和自动虽然名义上超时不同，实际底层没有按调用场景真正生效
- 历史日期仍可能被自动流程改写，和“历史只手动刷新”的产品预期冲突

## 目标

- 为每次手动/自动刷新生成可落盘、可追溯的日志
- 把 manual / automation / repair 的超时策略真正传到底层 runner
- 自动刷新收缩为 today-only
- 保持现有保守增量策略，不再扩展新的刷新模式

## 设计决策

### 1. 刷新日志

- 刷新日志持久化到 `~/Library/Application Support/KnowYou/RefreshLogs`
- 一次刷新对应一个 JSON 文件
- 日志必须覆盖：
  - `dayKey`
  - `trigger`：manual / automation
  - `mode`：fullRecovery / incrementalUpdate
  - 总耗时
  - 通知导入结果
  - 事件数量与增量事件数量
  - 每次引擎 attempt 的引擎名、超时、时长、成功/失败
  - 最终是否写入 `.md` / `.story.json`
  - 输出文件路径

### 2. 超时策略

- 手动主生成：`600s`
- 自动主生成：`300s`
- 手动 repair：`120s`
- 自动 repair：`60s`
- timeout 值必须按调用场景从 `AppState` 传到 `CLISummarizer`，再传到 `SystemProcessRunner`

### 3. 自动化策略

- `runAutomation()` 只允许处理今天
- 历史日期不再由自动流程创建或改写
- 自动路径仅在“今天已有 `.model` 成功 story”时执行 today incremental
- 如果今天没有成功 story，自动路径只做通知导入和状态更新，不做 full recovery

### 4. 收敛原则

- 手动刷新和自动刷新都复用同一条日志与 attempt 记录结构
- 写盘逻辑只通过统一 helper 执行
- 失败不允许覆盖已有工件

## 验收标准

- 手动刷新与自动刷新都能生成可落盘日志
- timeout 参数真实影响 runner，而不是停留在上层配置
- 历史日期不会再被自动刷新
- 自动 today incremental 和手动 full/incremental 的行为与状态文案一致
