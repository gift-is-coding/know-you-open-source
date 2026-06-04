# 双击安装包设计

## 背景

当前 DMG 安装页依赖 Finder 在挂载卷中读取 `.DS_Store` 并保持 icon view 的自定义坐标。实际测试中 Finder 会偶发按自己的排序或网格重排图标，导致背景箭头、标题和两个图标错位。这个问题不是图片清晰度问题，而是 Finder 展示层不稳定。

## 目标

- 为 KnowYou 产出一个双击即可进入 macOS Installer 的 `.pkg` 安装包。
- `.pkg` 默认把 app 安装到 `/Applications`，避免用户拖拽，也避免 Finder DMG 图标布局。
- 支持 New User QA app：保留 `KnowYou New User.app`、`dev.knowyou.newuser` 和现有 New User 数据隔离语义。
- 保留现有 DMG 脚本，避免一次性破坏 Sparkle 和发布链路。

## 非目标

- 本次不把线上下载页、Sparkle appcast、GitHub release asset 从 `.dmg` 全量迁移到 `.pkg`。
- 本次不引入新 UI installer app。
- 本次不处理 notarization 凭据或正式 Developer ID Installer 签名发布。

## 方案

新增 `scripts/build-pkg.sh`：

- 读取 `KNOWYOU_APP_PATH` 指向的 `.app`。
- 从 app 的 `Info.plist` 读取 `CFBundleIdentifier`、`CFBundleShortVersionString` 和 `CFBundleVersion`。
- 先把 app 复制到临时 payload root，再使用 `pkgbuild --root <payload> --component-plist <plist> --install-location /Applications` 生成 `KnowYou-<version>-<build>.pkg`。
- 默认 package identifier 为 `<CFBundleIdentifier>.installer`，可用 `KNOWYOU_PKG_IDENTIFIER` 覆盖。
- 默认不签 installer package；如果设置 `KNOWYOU_PKG_SIGN_IDENTITY`，则传给 `pkgbuild --sign`。
- 用 component property list 禁用 relocatable，确保安装目标固定为 `/Applications`。

## 测试

- `scripts/test-release-common.sh` 覆盖 `release_pkg_path`。
- 新增 `scripts/test-build-pkg.sh`，用临时 fake app 真实调用 `pkgbuild`，再展开 package 检查 identifier、version、install location、relocatable 和 payload。
- 对真实 New User app 生成桌面 `.pkg` 后，用 `pkgutil --expand` 和 `pkgutil --payload-files` 验证包内容。
