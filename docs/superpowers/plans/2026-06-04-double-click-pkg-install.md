# 双击安装包 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增稳定的双击 `.pkg` 安装包，让用户不再依赖 Finder DMG 拖拽页。

**Architecture:** 保留现有 DMG 发布路径，新增独立的 pkg artifact helper 和 pkgbuild 脚本。New User QA 使用同一个 `build-pkg.sh`，只需传入已经改名/重签的 `KnowYou New User.app`。

**Tech Stack:** bash, pkgbuild, pkgutil, PlistBuddy, macOS Installer packages.

---

### Task 1: 写失败测试

**Files:**
- Modify: `scripts/test-release-common.sh`
- Create: `scripts/test-build-pkg.sh`

- [x] 在 `scripts/test-release-common.sh` 增加 `release_pkg_path` 断言，期望 `build/test-release/KnowYou-1.2.3-145.pkg`。
- [x] 新增 `scripts/test-build-pkg.sh`，先要求 `scripts/build-pkg.sh` 存在并包含 `pkgbuild`、`--install-location`、`/Applications` 和 plist 读取逻辑。
- [x] 在 `scripts/test-build-pkg.sh` 中创建临时 `KnowYou Test.app`，运行 `build-pkg.sh` 后展开 pkg，检查 identifier、version、install-location、payload。
- [x] 运行两个测试，确认它们因缺少实现失败。

### Task 2: 实现 pkg artifact helper

**Files:**
- Modify: `scripts/release-common.sh`

- [x] 增加 `release_pkg_path()`，返回 `$release_dir/$(artifact_basename).pkg`。
- [x] 运行 `scripts/test-release-common.sh`，确认 release helper 通过。

### Task 3: 实现 pkg 构建脚本

**Files:**
- Create: `scripts/build-pkg.sh`

- [x] 用 `PlistBuddy` 读取 app bundle id、marketing version 和 build version。
- [x] 生成 component property list，设置 `BundleIsRelocatable=false`。
- [x] 调用 `pkgbuild --root "$payload_root" --install-location "/Applications"` 产出 `release_pkg_path`。
- [x] 支持可选 `KNOWYOU_PKG_IDENTIFIER`、`KNOWYOU_PKG_VERSION`、`KNOWYOU_PKG_INSTALL_LOCATION`、`KNOWYOU_PKG_SIGN_IDENTITY`。
- [x] 运行 `scripts/test-build-pkg.sh`，确认通过。

### Task 4: 文档和真实 New User 包

**Files:**
- Modify: `docs/architecture.md`
- Modify: `docs/requirements-spec.md`

- [x] 更新文档，说明 `.pkg` 是解决拖拽布局不稳定的双击安装路径，DMG 暂时保留。
- [x] 构建/复用当前 New User app，生成桌面 `KnowYou-NewUser-a4eddb2.pkg`。
- [x] 展开真实 pkg 并检查 payload、PackageInfo 和 app identity。
- [x] 运行 `git diff --check`、相关脚本测试、必要的 Xcode build。
- [x] 尝试标准 full test；标准 bundle id 因当前机器已有另一个 `dev.knowyou.app` 运行而在 test host bootstrap 前被 SIGTERM，隔离 bundle id 版本在 Xcode 控制层无 test host 进程时卡住，已终止本次 `xcodebuild`。
