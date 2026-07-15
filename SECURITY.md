# Security Policy

## Reporting a vulnerability

Please do not open a public issue for a vulnerability that could expose user content, credentials, local files, Supabase data, or release infrastructure.

Email `cestlouiswu@gmail.com` with:

- a concise description and affected component
- reproduction steps or a minimal proof of concept
- the expected impact
- any suggested mitigation

Remove real secrets and personal diary content from reports. Use synthetic test data whenever possible.

## Security-sensitive areas

The highest-risk boundaries in this repository are:

- clipboard and Notification Center capture before local persistence
- LLM provider and Codex OAuth credentials
- Keychain-to-disk migration paths
- local-file scanning and path traversal prevention
- built-in MCP/CLI output and source citation access
- Networking device/session authorization, RLS, Edge Functions, and one-time web handoff
- Developer ID signing, Sparkle update signing, and notarization tooling

## Supported versions

Security fixes are applied to the current development branch and the latest published release when practical. Older builds may not receive backports.

## Public disclosure

Please allow time to validate and ship a fix before public disclosure. The maintainer will coordinate scope and timing with the reporter when the report is confirmed.
