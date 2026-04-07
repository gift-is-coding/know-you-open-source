# Know You

Know You is a native macOS app that captures daily computer context and turns it into one Markdown note per day.

The current MVP branch already includes:

- clipboard capture with privacy filtering
- notification ingestion with the same privacy boundary
- SQLite persistence via GRDB
- daily Markdown composition and missing-day planning
- vault writing under the user's Application Support directory
- optional cloud summarization through OpenAI's Responses API
- a minimal two-pane reader with dates on the left and raw Markdown on the right

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
