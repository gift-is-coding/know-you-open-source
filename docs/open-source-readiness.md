# Open-source readiness review

Last reviewed: 2026-07-15

Audited base: `main` at `6b3b9c0`, plus the fixes on `codex/open-source-readiness-audit`

This document is a release gate for maintainers and agents. It records what was checked, what the checks can establish, and what still must happen before a public mirror is published.

## Current decision

The code and documentation are suitable for a public release candidate. No known major functional, performance, or credential-exposure issue remains from this review. The repository now includes tested history-sanitization, allowlisted snapshot export, secret scanning, and public CI gates. Publication is still gated on running that workflow against the actual public mirror and reviewing the result before its first push.

| Area | Result | Evidence |
| --- | --- | --- |
| macOS app correctness | Pass | 917 XCTest cases: 915 passed, 2 skipped, 0 failed; build and static analysis passed without warnings |
| Web and agent tooling | Pass | Networking Web: 130 tests; My Wiki: 1,074 tests; MyWikiMCP: 7 tests; typecheck, lint, and builds passed |
| Rust backend | Pass with warnings | 54 tests passed and 1 ignored; `cargo check` passed; 8 existing non-blocking compiler warnings remain |
| Secret review | Pass with classified findings | Gitleaks 8.30.1 scanned the tracked snapshot and more than 400 historical commits; findings were public identifiers or synthetic test fixtures |
| Contributor and agent documentation | Pass | README, contribution, security, architecture, requirements, agent guide, release signing, and third-party notices are present |
| Root license | Pass | GPL-3.0, aligned with the modified and integrated GPL-3.0 My Wiki source |

“Pass” means the review found no release-blocking issue; it is not a guarantee that the software has no defects.

## Verification performed

### macOS app

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS'
xcodebuild build -scheme KnowYou -destination 'platform=macOS'
xcodebuild analyze -scheme KnowYou -destination 'platform=macOS'
```

The final test result contained 917 tests with no failures. The final test, build, and analyze logs contained no Xcode warnings.

### Networking Web

```bash
cd NetworkingWeb
npm audit --audit-level=high
npm run typecheck
npm run lint
npm test -- --run
npm run build
```

The build verification used explicit local-only placeholder Supabase configuration. It did not write production data.

### My Wiki and MCP

```bash
cd ThirdParty/llm_wiki
npm audit --audit-level=high
npm run typecheck
npm run build
npm run test:mocks

cd src-tauri
cargo check --locked
cargo test --locked

cd ../../../Tools/MyWikiMCP
npm audit --audit-level=high
npm test
```

The My Wiki build succeeds with existing bundle-size and dynamic-import warnings. The Rust target succeeds with 8 compiler warnings. These are non-blocking maintenance items, not known functional failures.

## Credential review

The review combined targeted patterns with Gitleaks 8.30.1 scans of the tracked snapshot and Git history. The scanner findings were reviewed individually:

- the Supabase `sb_publishable_...` client key, which is intentionally public and must remain protected by RLS and server-side authorization
- the Sparkle EdDSA public verification key used to validate update signatures
- synthetic JWT and API-key-shaped values used by tests

No service-role key, secret Supabase key, private signing key, private-key block, or credible provider credential was found. The repository uses macOS Keychain or local environment/configuration for user and maintainer secrets.

Before publishing the independent mirror, rerun both scans from the mirror root:

```bash
gitleaks dir . --redact
gitleaks git --redact
```

Do not waive a new finding merely because the same rule was classified as safe here; inspect its file, commit, and purpose.

## Documentation map

- [README](../README.md): product overview, privacy model, repository map, setup, and verification
- [Agent guide](agent-guide.md): change boundaries and starting points for coding agents
- [Architecture](architecture.md): implemented runtime architecture
- [Requirements](requirements-spec.md): current product contracts and acceptance criteria
- [Contributing](../CONTRIBUTING.md): contributor workflow and review standard
- [Security policy](../SECURITY.md): private vulnerability reporting
- [Release signing](release-signing.md): maintainer-only signing and notarization inputs
- [Public repository synchronization](public-repository-sync.md): private-to-public history creation, routine sync, and contribution backflow
- [Third-party notices](../THIRD_PARTY_NOTICES.md): bundled source and binary licensing
- [Terms](../TERMS.md) and [privacy policy](../PRIVACY.md): user-facing legal and privacy boundaries

## Public-mirror release gate

The public mirror must be created without rewriting or damaging the existing private repository. Its entire public history must exclude:

- `docs/investor-pitch/` — personal photographs and investor materials
- `docs/fundraising/` — fundraising and application materials

After the history is sanitized:

1. clone the public mirror into a fresh directory and verify that both paths are absent from every reachable commit
2. rerun the current-tree and history secret scans
3. verify the root `LICENSE`, `TERMS.md`, README links, and third-party notices
4. rerun the deterministic test/build commands applicable to the mirror
5. inspect `git diff` and the final tracked-file list before the first push

Use `scripts/create-public-history.sh` for the one-time disposable history rewrite and `scripts/export-public-repo.sh` for later allowlisted snapshot commits. Both scripts verify before mutation, refuse unsafe destinations, record the private source SHA, and intentionally perform no push.

The confirmed public support contacts are `cestlouiswu@gmail.com` and [@TianfuW49629](https://x.com/TianfuW49629).

## Checks intentionally not completed

This review did not exercise real paid LLM calls, production Supabase writes, Apple notarization, or a fresh GUI smoke test. Those checks require credentials, production-impacting access, or interference with an already-running KnowYou process. They remain separate release checks and must not be inferred from deterministic test success.
