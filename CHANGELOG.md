# Changelog

## [0.1.0] — unreleased

- Plugin skeleton: manifest with dependencies on all six org plugins (incl. matrix-qa-plugin and matrix-studio) (bundle pattern — installing Guardian installs them).
- Goal redefined as the single entry-point router: `docs/vision.md`.
- July MCP / 7-phase plan archived under `archive/2026-07-mcp-plan/`.
- Session opener (G1): `scripts/git-status.sh` (JSON git report vs. the central branch, bounded non-interactive fetch, fails open, bash 3.2, no jq), `scripts/session-log.sh` (local per-branch session log), SessionStart hook on `startup|clear`, `session-opener` skill, optional `.platform-guardian.json` (`docs/project-config.md`). Tests: `tests/run-all.sh`.
- Router (G2): `routing/routes.json` (intents → Ono plugin commands, human-only list, resume probes, git guards), `skills/work-router`, `scripts/check-routes.sh` drift guard.
- Closer (G3): `hooks/prompt-submit.sh` session-length signal (real context tokens), `skills/session-closer` (hygiene → commit → push → PR, local session log, `/clear`), `routing/committed-artifacts.json`. Git report gains `guards.matrixQa` / `guards.onoQaCommitBlocked`.
- Decisions: specs saved to `docs/specs/<feature-slug>/`; `design-system` intent (matrix-studio); QA routing picks mobile/TV vs web from the task.
