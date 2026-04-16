# CLI Structured Reliability Design

## Problem

Foreground story generation through local CLIs had a noticeably lower success rate than background generation. The failure mode was usually not process execution itself, but post-processing:

- free-form CLI stdout had to be heuristically parsed back into story JSON
- stderr noise could pollute the response contract
- Codex runs did not use native structured output capture
- invalid-but-nonempty model output fell directly to fallback instead of getting one constrained repair pass
- runtime status only preserved a human-readable error string, which made failure classes hard to reason about

## Goals

- Raise successful foreground generation rate without changing reader UX
- Make CLI contracts deterministic where the tool supports it
- Distinguish timeout, non-zero exit, empty output, invalid structured output, and repair failure
- Preserve compatibility across Claude, Codex, Gemini, and Openclaw adapters

## Non-Goals

- No redesign of story prompt semantics
- No async/background UX redesign in this pass
- No model-routing or prompt-compaction project in this pass

## Design

### Structured process results

`ProcessRunning` now returns a structured execution result with:

- `stdout`
- `stderr`
- `terminationStatus`
- `duration`

This separates transport failures from parsing failures and avoids interpreting stderr as story content.

### Engine-specific invocation contracts

- `Claude CLI` keeps schema-based JSON output flags and validates either `structured_output` or raw schema-valid JSON.
- `Codex CLI` now uses `codex exec --output-schema <schema-file> -o <output-file>`, reading the final payload from the output file instead of bannered terminal output.
- `Gemini CLI` keeps JSON output mode and extracts the `response` envelope deterministically.
- `Openclaw CLI` keeps `--json` and extracts payload text deterministically.

### Repair pass

If the primary summarize response is non-empty but still fails story-schema validation, the app performs one repair pass with a narrower prompt that only asks for schema repair. The local fallback only happens after both the primary pass and repair pass fail.

### Failure normalization

The CLI layer now emits normalized error classes:

- `timedOut`
- `nonZeroExit`
- `emptyOutput`
- `invalidStructuredOutput`
- `repairFailed`

`AppState` preserves a derived `failureKind` alongside the human-readable error text so UI and diagnostics can reason about the failure without string matching everywhere else.

## Expected Outcome

- Higher success rate for foreground Codex runs
- Less corruption from stderr noise and banner text
- Better observability for reliability tuning
- Safer fallback behavior because structurally salvageable responses get one repair attempt first
