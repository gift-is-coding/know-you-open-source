# Plan: Global LLM Prompt Budget

## Summary

Add a shared prompt event formatter in `DailyMarkdownComposer` so every full-story and incremental LLM prompt truncates each event text to 100 characters before calling a summarizer.

## Implementation

1. Update prompt assembly.
   - Add one internal helper that formats prompt event lines.
   - Apply the helper to both `storyPrompt(...)` and `incrementalPrompt(...)`.
   - Keep event order and field shape unchanged while truncating only the prompt `text` value.

2. Add regression coverage.
   - Assert long event text is truncated in `storyPrompt(...)`.
   - Assert short event text remains unchanged.
   - Assert long new-event text is truncated in `incrementalPrompt(...)`.
   - Assert a real generation call receives the truncated prompt before hitting the summarizer.

3. Sync docs.
   - Update `docs/requirements-spec.md`
   - Update `docs/architecture.md`

## Verification

- Focused tests for `DailyMarkdownComposerTests`
- Focused tests for `MainWindowViewModelTests`
- `xcodebuild build -scheme KnowYou -destination 'platform=macOS'`
