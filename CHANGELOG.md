# Changelog

## [0.1.0] — unreleased

- Plugin skeleton: manifest with dependencies on the core Ono plugins (bundle pattern — installing Guardian installs them).
- Goal redefined as the single entry-point router: `docs/vision.md`.
- July MCP / 7-phase plan archived under `archive/2026-07-mcp-plan/`.
- Session opener (G1): `scripts/git-status.sh` (JSON git report vs. the central branch, bounded non-interactive fetch, fails open, bash 3.2, no jq), `scripts/session-log.sh` (local per-branch session log), SessionStart hook on `startup|clear`, `session-opener` skill, optional `.platform-guardian.json` (`docs/project-config.md`). Tests: `tests/run-all.sh`.
