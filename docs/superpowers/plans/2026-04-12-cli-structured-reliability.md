# CLI Structured Reliability Plan

## Scope

Improve foreground CLI story generation reliability by hardening transport, parsing, and retry behavior without changing the user-facing flow.

## Steps

1. Add tests that lock in the new CLI contract.
   - Structured `ProcessRunning` result
   - Codex output-schema file capture
   - stderr isolation
   - one-pass repair flow
   - runtime failure-kind classification

2. Refactor CLI execution.
   - Return `stdout`, `stderr`, exit status, and duration
   - Raise timeout budget to 300 seconds
   - Stop treating free-form stdout as the Codex primary contract

3. Introduce engine-specific structured handling.
   - Claude schema envelope handling
   - Codex `exec` plus output file
   - Gemini envelope extraction
   - Openclaw payload extraction

4. Add one constrained repair pass for invalid non-empty story output.

5. Propagate normalized runtime failures into `AppState`.

6. Run targeted tests first, then full repository verification.

## Verification

- `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/CLISummarizerTests -only-testing:KnowYouTests/EngineProbeTests`
- `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MainWindowViewModelTests/testSummarizerStatusInfersFailureKindFromActiveEngineDetail`
- `xcodebuild test -scheme KnowYou -destination 'platform=macOS'`
- `xcodebuild build -scheme KnowYou -destination 'platform=macOS'`
