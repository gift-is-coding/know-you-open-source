# Build Version Badge And Source App Alias Design

## Goal

解决两个直接影响日常验证的问题：

- 在主窗口右下角持续显示一个很小的构建标识，让每次打开 `dev` build 时都能立刻知道当前二进制对应哪个版本与提交
- 让来源应用图标解析不再只依赖精确 app 名称，能够兼容中文名、英文名和 bundle-id 风格名称

## Decision

采用只读 badge，格式为：

`v<MARKETING_VERSION> (<CURRENT_PROJECT_VERSION>) · <git-short-sha>`

示例：

`v1.0 (1) · 379aff5`

如果当前构建拿不到 git 短 SHA，则回退为：

`v1.0 (1)`

## Source Of Truth

- `MARKETING_VERSION` 继续手动维护
- `CURRENT_PROJECT_VERSION` 改为在 Xcode build phase 中按当前 git commit count 自动写入 bundle
- git 短 SHA 由同一个 build phase 写入 app bundle resource：`BuildMetadata.json`
- 运行时只读取 bundle 中的静态信息，不执行 `git` 命令，不依赖当前工作目录

## UI Placement

- 仅在 `MainWindowView` 显示
- 位置固定在右下角
- 使用小号、monospaced、secondary 样式
- 不参与交互，`allowsHitTesting(false)`

## Source App Alias Resolution

- 继续使用表驱动 alias catalog，不改成分散的 `switch`
- 解析流程改为：
  - 先做标准化后的 exact match
  - exact match 失败后，再做保守 fuzzy match
- 标准化规则需要把 `.`、`-`、`_` 等分隔符统一折叠为空格，并保留中英文字符与数字
- fuzzy match 主要解决 bundle-id 风格来源名，例如：
  - `com.tencent.xinWeChat` -> `WeChat`
  - `com.apple.MobileSMS` -> `Messages`
  - `com.apple.Notes` -> `Notes`
- 目标不是“猜任意未知应用”，而是让已知 alias catalog 能同时覆盖：
  - 中文 app 名
  - 英文 app 名
  - 常见 bundle-id 风格名称

## Non-Goals

- 不在阅读区正文中显示
- 不做可点击 release notes 或 commit 跳转
- 不为菜单栏、设置页、onboarding 同步增加第二份版本展示
- 不引入远程服务、在线图标拉取或运行时 bundle 查询来补图标
