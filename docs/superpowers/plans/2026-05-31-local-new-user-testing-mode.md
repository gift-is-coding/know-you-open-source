# KnowYou 本机新用户测试模式收敛计划

> **For agentic workers:** 使用 Superpowers 执行本计划；所有步骤都必须保护普通 `KnowYou` 数据、Keychain 与 macOS 权限。

## Goal

把 `KnowYou New User` 明确定义为本机新用户 QA 测试模式，而不是日常开发默认路径或正式发布路径。

## Tasks

- [x] 用 focused XCTest 固定 `AppRuntimeProfile` 的普通路径与 New User 隔离路径。
- [x] 补充本机新用户测试模式 spec，说明它只用于首次用户场景验证。
- [x] 更新 requirements / architecture，明确普通 `KnowYou` 与 `KnowYou New User` 的数据、Keychain 与权限边界。
- [x] 运行 focused metadata tests。
- [x] 运行 New User 安装脚本并验证 Info.plist / executable。
- [x] 运行 full macOS test/build verification。

## Acceptance

- 普通 `KnowYou` 仍默认写入 `~/Library/Application Support/KnowYou`，使用现有 `com.knowyou.app` Keychain service。
- `KnowYou New User` 只由安装脚本创建，使用独立 app identity、独立数据目录和独立 Keychain service。
- 任何非 New User bundle id 都不会触发隔离路径。
