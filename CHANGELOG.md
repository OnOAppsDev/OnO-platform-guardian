# Changelog

## [0.2.1] — 2026-11-09

- **Updates reach employees:** first-time welcome and the tour's cheat sheet give the one-time auto-update setup (`/plugin` → Marketplaces → ono-plugin-marketplace → Enable auto-update) — off by default for org marketplaces; managed settings turn it on org-wide (`docs/rollout.md`).
- CI: `scripts/check-version-bump.sh` fails a PR that changes plugin files without raising `plugin.json`'s version — Claude Code updates installed copies only when it goes up.
- Daily drift check (`.github/workflows/drift.yml`, was weekly): the six Ono plugins vs. `routes.json`; drift opens one GitHub issue assigned to the maintainer (`scripts/report-drift.sh`), closed automatically when back in sync.
- Onboarding wording: the git check shows on the first message; no trigger word; every step says exactly what to type.

## [0.2.0] — 2026-11-09

- **Onboarding** 🎉: first session on a computer opens with an emoji welcome and offers an interactive 3-minute tour (`skills/onboarding`, 5 steps) — how a session starts, routing by plain words (demo, starts nothing), what it never does for you (approvals, commit guard), closing, cheat sheet. Offered once: the SessionStart hook writes `~/.claude/platform-guardian/.state/onboarding-offered` when it injects the offer; `onboarding` re-runs it on request; `PG_ONBOARDING=off` disables it.
- Fetch timeout is a watchdog timer (exactly 5 s; the old sleep-count loop drifted to ~7 s on slow machines).
- Opener: "numbers may be out of date" whenever the fetch failed; open once per session (not after `/compact`); your-step items aren't offered as "continue". Router: approval requests answered directly; disabled vs missing plugin; asks for a missing bug key / feature name; a "yes" never runs a human-only step. Closer: asks before push / PR.
- In the org marketplace (`ono-plugin-marketplace` 1.6.0). Live test runs through the real install (`docs/tester-guide.md`).

## [0.1.0] — 2026-11-09

- Plugin skeleton: manifest with dependencies on all six org plugins (incl. matrix-qa-plugin and matrix-studio) (bundle pattern — installing Guardian installs them).
- Goal redefined as the single entry-point router: `docs/vision.md`.
- July MCP / 7-phase plan archived under `archive/2026-07-mcp-plan/`.
- Session opener (G1): `scripts/git-status.sh` (JSON git report vs. the central branch, bounded non-interactive fetch, fails open, bash 3.2, no jq), `scripts/session-log.sh` (local per-branch session log), SessionStart hook on `startup|clear`, `session-opener` skill, optional `.platform-guardian.json` (`docs/project-config.md`). Tests: `tests/run-all.sh`.
- Router (G2): `routing/routes.json` (intents → Ono plugin commands, human-only list, resume probes, git guards), `skills/work-router`, `scripts/check-routes.sh` drift guard.
- Closer (G3): `hooks/prompt-submit.sh` session-length signal (real context tokens), `skills/session-closer` (hygiene → commit → push → PR, local session log, `/clear`), `routing/committed-artifacts.json`. Git report gains `guards.matrixQa` / `guards.onoQaCommitBlocked`.
- Commit guard (G3.5): `hooks/pre-tool-use.sh` — on `git add` / `git commit`, new files on a `neverCommit` list are denied and stray working files (`.md`, `.log`, `.html` … not on any `commit` list) need the employee's OK. `PG_COMMIT_GUARD=off` disables it.
- Live-test kit for G1.7: `docs/live-test.md` + `scripts/live-test-setup.sh` (test repos, `pg/*` branches, versions, installed Ono plugins, hook timing — one command).
- Minimum Claude Code version: 2.1.140 (`docs/rollout.md`).
- Resume (G2.3): `scripts/resume-state.sh` lists unfinished work from the Ono plugins' own documents — dev features + bugs, ono-plugin-qa, matrix-qa-plugin (exact `mqa.mjs` fingerprints), inspector, specs in `docs/specs/` — with the next step; injected by the SessionStart hook. Formats: `docs/resume-state.md`. `PG_RESUME=off` disables it.
- Fix: `git-status.sh` reported a bogus upstream `"@{u}"` on branches without one under git ≥ 2.4x (found by the Linux CI run).
- CI: `.github/workflows/ci.yml` — tests on macOS bash 3.2 and Linux, and a weekly `check-routes.sh --strict` against every plugin the marketplace lists (`scripts/fetch-org-plugins.sh`).
- Decisions: specs saved to `docs/specs/<feature-slug>/`; `design-system` intent (matrix-studio); QA routing picks mobile/TV vs web from the task.
