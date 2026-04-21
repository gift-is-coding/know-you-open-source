# KnowYou

KnowYou is a native macOS app that captures daily computer context and turns it into a story-first daily journal with source-linked evidence.

The current project includes:

- clipboard capture with privacy filtering
- read-only import from the local macOS Notification Center SQLite store when a supported database path is available
- SQLite persistence via GRDB for events and run history
- launch-time refresh plus a 15-minute automation loop for backfill and regeneration
- fallback local story synthesis when no external summarizer is available
- optional summarizers via OpenAI API, Claude Code CLI, Codex CLI, or Gemini CLI
- daily output written as both `YYYY-MM-DD.story.json` and `YYYY-MM-DD.md`
- a three-pane reader with dates on the left, story paragraphs in the center, and linked raw sources on the right
- onboarding and settings flows for vault path, summarizer config, and service diagnostics

## Local Development

1. Open `KnowYou.xcodeproj` in Xcode, or use `xcodebuild`.
2. Optionally export `OPENAI_API_KEY` before launching if you want cloud summaries.
3. Build the app:

```bash
xcodebuild build -scheme KnowYou -destination 'platform=macOS'
```

By default, the app stores runtime data under:

- database: `~/Library/Application Support/KnowYou/events.sqlite`
- vault: `~/Library/Application Support/KnowYou/Vault`

## Running Tests

Run the full suite:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS'
```

Run a focused test target while iterating:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MainWindowViewModelTests
```

## Real-Machine Verification

For a real clipboard + notification smoke test on this Mac, run:

```bash
./scripts/verify-real-machine.sh
```

The harness prints the exact SQLite and Markdown follow-up commands and documents the notification persistence fallback in [`docs/real-machine-verification.md`](docs/real-machine-verification.md).

For reproducibility, the harness relaunches the app and relies on launch-time clipboard bootstrap plus launch-time refresh to verify the real clipboard -> SQLite -> Markdown path on this Mac.

## Release Signing

KnowYou now ships through a dedicated Developer ID release path rather than the local debug signing flow.

One-time notarization setup on a release machine:

```bash
xcrun notarytool store-credentials "know-you-notary" \
  --apple-id "ouyang_danhua@outlook.com" \
  --team-id "3DY726RPHL" \
  --password "<app-specific-password>"
```

Release commands:

```bash
./scripts/build-release.sh
./scripts/notarize-release.sh
./scripts/verify-release.sh
```

See [`docs/release-signing.md`](docs/release-signing.md) for the full flow and artifact layout.

## Project Docs

- [Architecture](docs/architecture.md)
- [Requirements Spec](docs/requirements-spec.md)

## Contact

- X / Twitter: https://x.com/TianfuW49629
- Email: cestlouiswu@gmail.com

## Community

Discord 是 KnowYou 当前规划的主社区形态，适合讨论产品想法、反馈体验、分享你的日记工作流。

- 社区说明与频道建议见 [COMMUNITY.md](COMMUNITY.md)
- 当前社区链接：https://discord.gg/ZrqF5jwQ

## Privacy

KnowYou 是本地优先的 macOS 应用。隐私边界、数据来源、过滤时机与第三方总结器说明见 [PRIVACY.md](PRIVACY.md)。

## Support

- 隐私问题或不适合公开讨论的内容，请直接发邮件联系
- 产品建议、使用体验和公开反馈，优先进入 Discord 社区
- 正式上线前的剩余准备项见 [LAUNCH-CHECKLIST.md](LAUNCH-CHECKLIST.md)
