# Sparkle 自更新与更新内容体验设计

## Goal

把 direct macOS release 从“提示用户下载 DMG”升级为 Sparkle 自更新体验：显示更新内容，点击后由 Sparkle 下载、验证、安装、退出并重启；重启后 KnowYou 自动弹出一次 `What's New`。

## Design

Release app 接入 Sparkle 2.9.x，Info.plist 配置 `SUFeedURL`、`SUPublicEDKey` 和 installer launcher service。现有 `latest.json` 保留给旧版本的更新胶囊，新的 `appcast.xml` 作为 Sparkle 的正式更新源。发布脚本在生成、notarize、打包 DMG 后，用 Sparkle `sign_update` 生成 appcast enclosure 的签名属性。

产品层继续使用 KnowYou 自己的更新胶囊和更新 sheet 来保持一致外观。胶囊必须更明显并带可用版本；更新 sheet 必须默认展示更新内容；direct 主按钮不再打开 DMG URL，而是调用 `SparkleDirectAppUpdater`。App Store 渠道仍只打开 App Store。

安装完成后的更新内容弹窗不依赖 Sparkle 回调。KnowYou 启动时比较 `lastSeenAppVersion` 与当前 `AppBuildMetadata.current.marketingVersion`；如果版本变新且当前版本没有被关闭过，则展示 `What's New in vX.Y.Z`。关闭后写入 `lastDismissedWhatsNewVersion`，同一版本不重复弹。

## Migration

第一版 Sparkle-enabled release 对现有用户仍需要手动下载 DMG 并拖到 `/Applications`。从这个版本之后，后续 direct release 才能通过 Sparkle 自动更新。

## Acceptance Criteria

- direct 更新主按钮调用 Sparkle updater，不再打开 DMG 下载链接。
- 更新胶囊显示可用版本，样式比旧橙点明显。
- 更新 sheet 默认显示完整更新内容和强主按钮。
- 版本升级重启后自动显示一次 `What's New`，同版本关闭后不重复。
- `publish-release.sh` 同时发布 `latest.json` 和 Sparkle `appcast.xml`，并让二者共享同一份 release notes；真实发版可通过 `KNOWYOU_RELEASE_NOTES_FILE` 或 `KNOWYOU_RELEASE_NOTES` 注入本次更新内容。
- Release 构建必须带有 Sparkle public EdDSA key；当前默认公钥为 `DPaKuqvU48UAoI0rOvKtWaStpzMsX9fwypStdx4md/M=`，可用 `KNOWYOU_SPARKLE_PUBLIC_ED_KEY` 覆盖。私钥只保存在发版用户的 macOS Keychain 中。
