# Contributing to KnowYou

Thanks for helping improve KnowYou. This project handles private local context, external model credentials, and optional public Networking data, so correctness and data-boundary changes deserve extra care.

## Before you start

1. Read [README.md](README.md), [docs/architecture.md](docs/architecture.md), and [docs/requirements-spec.md](docs/requirements-spec.md).
2. For agent-assisted work, also read [AGENTS.md](AGENTS.md) and [docs/agent-guide.md](docs/agent-guide.md).
3. Open an issue or discussion before a large architectural change.
4. Work on a branch; do not commit directly to the default branch.

## Development principles

- Keep changes small and tied to a user-visible or operational outcome.
- Add or update focused tests before changing behavior.
- Preserve existing user onboarding, login, engine, Keychain, and local data state during verification.
- Keep My Wiki semantics LLM-first. Deterministic rules are appropriate for safety, validation, formatting, provenance, and conservative degraded behavior.
- Never silently represent fallback extraction as completed semantic understanding.
- Do not mix unrelated refactors into a fix.

## Security and privacy rules

Never commit:

- API keys, OAuth credentials, cookies, service-role keys, device tokens, agent tokens, signing private keys, or notarization passwords
- `.env.local`, private xcconfig files, Keychain exports, provisioning profiles, or production database URLs with credentials
- real clipboard, notification, diary, My Wiki, or user-profile data
- generated `.knowyou/` activation state, test result artifacts, DerivedData, or release output

Use clearly fake values in tests. Public keys, publishable Supabase keys, and Apple team identifiers are not secrets, but contributor-facing configuration should still avoid maintainer-specific defaults.

If a change touches capture, persistence, credentials, authentication, authorization, MCP output, or public profile publishing, include the security boundary in the pull request description.

## Verification

Run the smallest relevant test while iterating, then the complete applicable checks before requesting review.

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS'
xcodebuild build -scheme KnowYou -destination 'platform=macOS'
```

```bash
cd NetworkingWeb
npm ci
npm audit --audit-level=high
npm run typecheck
npm run lint
npm test -- --run
```

```bash
cd ThirdParty/llm_wiki
npm ci
npm audit --audit-level=high
npm run typecheck
npm run test:mocks
```

```bash
cd ThirdParty/llm_wiki/src-tauri
cargo check --locked
cargo test --locked
```

```bash
cd Tools/MyWikiMCP
npm ci
npm audit --audit-level=high
npm test
```

Document checks that could not run and why. Do not label a change as passing when a required command was skipped or failed.

## Pull requests

Include:

- the user problem and intended outcome
- the files or subsystem changed
- privacy/security impact
- exact verification commands and results
- screenshots for meaningful UI changes
- known limitations or follow-up work

Maintainers may ask for architecture and requirements updates when behavior or system boundaries change.

Public pull requests are imported into the private canonical repository before the next public snapshot. Maintainers should follow [docs/public-repository-sync.md](docs/public-repository-sync.md); contributors do not need access to the private repository.

## Contribution license

KnowYou is licensed under [GPL-3.0](LICENSE). By submitting a contribution, you confirm that you have the right to provide it and agree that it may be distributed under the same license.
