# Conservative Incremental Refresh Plan

## Scope

- Change automation scheduling so today is not always fully regenerated.
- Add incremental prompt/parse/merge support in the composer.
- Route manual refresh between incremental update and full recovery.
- Add bounded manual retry across available green engines.
- Add tests for automation behavior, incremental merge behavior, retry behavior, and failure preservation.

## Implementation Steps

1. Update `DailyAutomationPlanner` so it only returns true backfill gaps and does not append today by default.
2. Extend `DailyMarkdownComposer` with:
   - used source ID extraction
   - incremental prompt generation
   - incremental payload parsing
   - merge logic that preserves encouragement and appends only allowed sections
3. Update `AppState` to:
   - classify refresh mode per day
   - run incremental refresh for existing model stories
   - run full recovery otherwise
   - preserve files on failed attempts
   - retry manual refresh across engines up to 5 attempts
4. Add targeted tests for:
   - planner conservative behavior
   - incremental prompt scope
   - incremental merge behavior
   - automation append behavior for today
   - manual retry behavior
   - failure preserving existing files
5. Sync product docs and architecture docs with the new behavior.
6. Run full `xcodebuild test` and `xcodebuild build`.

## Verification

- Targeted tests for `DailyAutomationPlannerTests`
- Targeted tests for `DailyMarkdownComposerTests`
- Targeted tests for the updated `MainWindowViewModelTests`
- Full `xcodebuild test -scheme KnowYou -destination 'platform=macOS'`
- Full `xcodebuild build -scheme KnowYou -destination 'platform=macOS'`
