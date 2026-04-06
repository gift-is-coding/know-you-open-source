# Know You

Know You is a native macOS app that captures daily computer context and turns it into one Markdown note per day.

This repository currently contains the initial SwiftUI app shell for the MVP:

- a native macOS `App` entry point
- a split-view reader window
- a menu bar extra and placeholder settings screen
- app state for selecting a day and resolving its Markdown path

## Running Tests

Use the focused app-state test during early bootstrap work:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MainWindowViewModelTests
```

## Configuration

Copy `KnowYou/Config/Secrets.example.xcconfig` to a local, untracked xcconfig file such as `KnowYou/Config/Secrets.local.xcconfig` when later tasks wire secrets into the app target.
