# 持久化全局搜索索引

## 背景

全局搜索 V1 已经支持显式 Search 按钮和 Enter 触发，但每次搜索仍会重新读取日记、Source、Todo 与 My Wiki 文件，用户输入一个真实查询时会感到明显等待。当前阶段继续保持本地关键词搜索，不引入 embedding、BM25 或模型下载。

## 范围

- 增加本地 `GlobalSearchIndex`，包含 manifest 与预计算后的 document 列表。
- 索引落盘到当前 profile 的 Application Support `SearchIndex/global-search-index-v1.json`。
- 使用 source signature 判断缓存是否可复用；schema 不匹配、JSON 损坏、signature 不匹配时后台重建。
- UI 打开 Search 时后台预热索引；用户点击 Search 或按 Enter 后，如果索引可用则直接后台查询，否则显示 `Indexing locally...` 并在完成后继续执行当前 query。
- 搜索阶段只查询内存中的持久化索引，不再每次读取日记、Source 或 My Wiki 文件正文。

## 失效输入

- 日记文件：path、size、mtime。
- Source：document id、connector、remote id、contentHash、local path、deletedAt。
- Todo：id、title、normalizedTitle、status、source day、completedAt、completion kind。
- My Wiki：native markdown path、size、mtime。

## 验收

- 能命中 Diary、Sources、Todo、My Wiki entity/concept。
- 相同 signature 可直接加载磁盘索引。
- 文件或 source hash 变化会触发重建。
- schemaVersion 不匹配或 JSON 损坏时不会卡死，会重建。
- Search 按钮和 Enter 复用同一条 submit/search 路径。

## 非目标

- 不引入 embedding、BM25、SQLite FTS 或服务端索引。
- 不改变结果点击后的导航/高亮行为。
- 不上传或同步任何索引内容。
