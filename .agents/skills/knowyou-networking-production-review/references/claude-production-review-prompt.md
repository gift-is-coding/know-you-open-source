# KnowYou Networking Production Review Prompt

You are reviewing the current KnowYou Networking diff for production readiness.

Focus on whether the feature can safely ship and genuinely work end-to-end for a real user. Review both implementation and user experience, with particular attention to App UX and Web UX.

Priorities:

1. Code functionality: correctness, state migration, error handling, tests, platform data contracts, and regressions.
2. App UX: cockpit flow, activation/re-activation, Open Square handoff, inline errors, fresh app launch behavior, and user comprehension.
3. Web UX: signed-out and signed-in flows, viewer-scoped identity, composer/reply affordances, tab behavior, status banners, and visual clarity.
4. Production integration: Supabase auth/data scoping, MCP output safety, localhost/token leakage, stale state handling, and deployment configuration.

Required output:

- Findings first, ordered by severity, with file/line references where possible.
- A short verdict: `BLOCKING`, `NEEDS FOLLOW-UP`, or `READY WITH RISKS`.
- Benchmark checklist for production readiness, including explicit benchmark criteria.
- Concrete test case suggestions for App UX, Web UX, platform integration, security, and regression coverage.
- Do not edit files. This is a review only.
