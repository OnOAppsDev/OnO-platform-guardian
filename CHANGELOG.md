# Changelog

## [0.4.0] — 2026-11-16

Protected branches, the inspect gate and plugin independence (Dev Plugin 0.7.5 integration review; design and reasoning in `docs/branch-policy.md`).

- **Work branch before the inspection** (deadlock: the gate blocked the employee's answer to "create a work branch?", and the inspector on `main` had its writes half-blocked by the dev plugin). On a protected branch the gate blocks the inspector's commands, for a first inspection and a refresh alike (read-only `inspect-status` excepted), and the banner starts with ① `! git switch -c chore/project-inspection` ② `/ono-project-inspector:inspect`. The only thing the gate lets through before the inspection is that exact branch command (`git switch -c` / `git checkout -b`, one command, nothing chained, not to a protected name). Plain-language requests stay blocked, so this opens no way around the inspection.
- **Guardian's own write guard** (`hooks/write-guard.sh`, `Write | Edit | NotebookEdit`): no file changes on a protected branch, meaning `main`, `master`, and the project's central branch when it's certain (`.platform-guardian.json` `centralBranch`, or detection confidence `high`, cached at session start). About 80 ms per write on a work branch. Guardian no longer relies on the dev plugin's `main`/`master` hook; both stay, on purpose.
- **Commit guard: commit or push on a protected branch → deny** (was: a permission prompt). This includes a push whose target is protected (`HEAD:develop`, `+x:refs/heads/main`, `:develop`). `git switch -c x && git commit` is judged on `x`.
- **Claude can't start the Inspector on a protected branch either** (`Skill` / `Agent` / `SlashCommand` → deny, except `inspect-status`). The gate only sees what the employee types.
- **QA plugins keep their own git flow**: the ono-plugin-qa QA repo and matrix-qa's `qa/` folder aren't blocked (the employee reviews and commits there by design). Never blocked either: `~/.claude`, git-ignored files, a brand-new project with no commits yet.
- Hardened after three independent review agents: push through `heads/main`, `--all`, `--mirror`, subshells, `if`/`env`, line breaks and `checkout -` are all caught; branch names compare case-insensitively (`Main` is `main` on macOS); a commit or push the guard can't read gets the permission prompt. Details: `docs/branch-policy.md` → Review.
- **Inspector missing or turned off** → the banner gives the install / enable line, and a command that doesn't exist no longer opens the gate.
- Routes re-verified against `ono-mobile-dev-plugin` 0.7.5 (nested-project knowledge only; no command, hook or document-format change).
- One definition of "protected branch" for every hook: `scripts/protected-branch.sh`. Router: a work branch for every intent that writes files, not only dev. Opener: `.platform-guardian.json` is written after the work branch exists.

## [0.3.7] — 2026-11-16

- Routes re-verified against `ono-project-inspector` 0.11.2 — the fixes for the tester report (agent can run its own flow, Bun preflight, project root below the git root, same layout Guardian 0.3.6 already supports). No route changes; inspector registry artifacts unchanged.

## [0.3.6] — 2026-11-15

- **Projects in a subfolder of the git root** (tester bug, `yestvos/YesTVOS/`): Guardian looked for the inspector's outputs only at the git root, so a complete inspection was reported `missing` and its new `docs/project/capabilities.md` was refused as a stray document. The inspect gate, resume and the commit guard now find the project folder — the nearest folder from the session folder up to the git root holding the inspector's `AUDIT.md`, or the single subfolder (≤ 4 levels) holding `.ono/state.json` (`inspect-status.sh root`) — and allow inspector outputs under it. Two inspected subfolders with the session at the root aren't guessed. The empty "missing ()" detail is gone.
- **Opener: one question per message** (tester report: work-branch name + inspection refresh offer + "what are we working on" arrived together). Git decisions first, one at a time; then the refresh offer (never while still on the central branch — the refresh writes files); then "what are we working on".

## [0.3.5] — 2026-11-15

- **The inspect gate can't drift from the inspector again.** `check-routes.sh` (every PR + the daily drift job, which opens an issue) now compares Guardian's "inspection complete" files and "older knowledge model" files with the inspector's own `skills/registry.json` (`produces` of artifact-completed inspection stages, minus `knowledgeModel` artifacts). A new required or knowledge-model artifact in a future inspector release is reported as `INSPECT DRIFT` before it can wrongly block employees. The lists live in one place (`inspect-status.sh` `STAGE_ARTIFACTS` / `MODEL_ARTIFACTS`); `resume-state.sh` reads the same list.
- Routes re-verified against `ono-project-inspector` 0.11.1 (docs: `/inspect` refresh triggers aligned with 0.11.0) — no route changes; registry artifacts unchanged.

## [0.3.4] — 2026-11-15

Guardian now handles two situations itself that used to need the maintainer (both from the YesPlusSmartTV report):

- **Suspect main-branch detection → asks once, saves for the team.** `git-status.sh` no longer trusts the remote's default blindly: an unusual default (a feature / staging branch such as `Back-key-on-Webos-stg`) while `develop` / `dev` / `main` / `master` exists, or a branch more than 1000 commits ahead of the detected central (`PG_SUSPECT_AHEAD`), is reported low-confidence + `central-ambiguous`. The opener says why, asks once which branch is the main one, and offers (recommended) to write `.platform-guardian.json` so nobody on the team is asked again. `dev` is now a recognized main-branch name. An override is never second-guessed.
- **Older-model inspection → Guardian offers the refresh itself.** When the inspection is complete but predates the current knowledge model, the opener offers to run `/ono-project-inspector:inspect` → Refresh Project Knowledge right away (yes / later); the outputs go into the employee's next PR so the whole team gets the current model. `inspect-status.sh elsewhere` finds a complete current-model inspection sitting on another remote branch and mentions it as FYI (merging another branch stays a human decision) — also in the gate's context when a project is blocked.

## [0.3.3] — 2026-11-15

- **Every commit and push needs the employee's OK** (tester bug: after the employee picked an inspector option, Claude committed on its own — the guard denied the non-code files, then Claude re-ran with `PG_INCLUDE_FILES=1` by itself). The commit guard now returns a permission prompt (`ask`) for every `git commit` and `git push` ("approve only if you asked for it"), and for every `PG_INCLUDE_FILES=1` add of non-code files — the flag alone no longer lets files in; the employee confirms them. Denials (secrets, non-code files without the flag) still win. None of the Ono plugins commit on their own (dev plugin: "never creates a git commit"), so the only prompts are Guardian's close-out and Claude-initiated commits.
- **Inspect gate: an inspection made with an older inspector knowledge model is complete, not "partial"** (tester bug: `YesPlusSmartTV` blocked for a missing `docs/project/capabilities.md`). Per the inspector's registry, a `knowledgeModel` artifact's absence "never reopens an otherwise complete stage" (`inspection-state.ts` skips it). `inspect-status.sh` now requires only the stage artifacts and returns `done` + `refresh-recommended`; the opener shows a one-line, non-blocking 💡 "Refresh Project Knowledge" hint. Same split in `resume-state.sh`.

## [0.3.2] — 2026-11-15

- **Resume knows the dev plugin 0.7.4 half-started bug plan.** 0.7.4 writes the Bug Work Plan right after the platform / device-type confirmation, so an interrupted `/analyze-bug` keeps its routing (the fix for the tester's "platform detected again after /clear" bug). Guardian's resume no longer shows that draft as "waiting for approval — your step": it says *analysis in progress, platform ‹p› / ‹d› already confirmed* → `/analyze-bug ‹key›` continues with no new detection.
- Routes re-verified against `ono-mobile-dev-plugin` 0.7.3 (better tvOS / React Native detection) and 0.7.4 — no route changes.
- Routes re-verified against `spec-team-toolkit` 0.6.1 (`lld-web-backend-spec`: capabilities, readiness table, source-reading rules) — same skills, no route changes. Close-out timing wording follows 0.7.4 (the analysis resumes; routing is no longer lost).

## [0.3.1] — 2026-11-15

- **No close-out in the middle of a plugin step** (tester bug: closing mid-analysis made the next session re-detect the platform and re-run the analysis). The 💡 session-length suggestion now waits until the running Ono plugin step has saved its result. If the employee closes mid-step anyway, the closer first says plainly what would be redone and recommends finishing; on "close anyway" the log records what was already confirmed (e.g. platform / device type) so the next session can tell them. The plugin-side fix (persisting a confirmed routing before the plan exists) is with the dev-plugin owner.

## [0.3.0] — 2026-11-15

- **⛔ Inspect gate (Ono rule: every project is inspected first).** New `hooks/inspect-gate.sh` on `UserPromptSubmit` and `UserPromptExpansion` + `scripts/inspect-status.sh`. If the project hasn't been through the Ono Project Inspector (stages 1–2: `AUDIT.md`, `CLAUDE.md`, `docs/project/*`), every message and Ono plugin command is **blocked** with a red ⛔🚨 banner: run `/ono-project-inspector:inspect`, or — only with a manager's approval — type the exact sentence `I have manager approval to work without inspect` (Hebrew: `יש לי אישור מנהל לעבוד בלי inspect`), which opens the repo for that day (recorded locally, never in git). Started-but-unfinished inspections and branches older than an inspected central branch get their own instruction. The inspector's own commands, Guardian's and built-ins stay open. `.platform-guardian.json` `"inspectRequired": false` exempts a repo (committed → reviewed).
- The inspector's outputs (`AUDIT.md`, `CLAUDE.md`, `docs/project/**`, `audits/**`, `.ono/state.json`, `.ono/repo-knowledge.json`) are now **committed** by default (exception to "only code") — the gate reads them, so the team must share one inspection.
- Routes re-verified against `ono-mobile-dev-plugin` 0.7.2 (fix for the deferred-reproduction QA-handoff block found in Guardian testing) — no route changes.

## [0.2.9] — 2026-11-12

- Routes re-verified against `ono-mobile-dev-plugin` 0.7.1 (its fix for `REPOSITORY_UNAVAILABLE` in large repos, found in Guardian testing) — no route changes.

## [0.2.8] — 2026-11-11

- **Bug reports:** new `platform-guardian:report-bug` skill. When something breaks in Guardian, an Ono plugin or Claude Code ("report a bug", or Claude offers it after spotting a tool bug), it writes one organized report — summary, exact error, expected, steps, findings with `file:line`, workaround, suspected component — plus an Environment section from `scripts/bug-report.sh` (Claude Code, Guardian and every Ono plugin's version, macOS, repo, branch, git state). Saved under `~/.claude/platform-guardian/bug-reports/`, never in the repo; Finder opens with it selected so the employee can send it to the maintainer. The closer offers it once if a tool bug happened and no report was written.

## [0.2.7] — 2026-11-10

- **Commands the employee types are given with their full name** — `/ono-mobile-dev-plugin:verify-fix-cycle bug:KEY`, not `/verify-fix-cycle` (tester bug: the short form didn't run, so the employee hit an unknown command on a human-only approval step).

## [0.2.6] — 2026-11-10

- **Only code goes into a commit, in every flow** (tester bug: two bug fixes pushed MD + JSON files that didn't belong in the PR). The commit guard now leaves new documents, data and plugin working files out — `.json` / `.yaml` included, and the Ono plugins' own documents (bug work plans, task state, planning docs, reviews, spec drafts, inspector reports) too. They stay on disk, never deleted or `.gitignore`d. A file goes in only when the employee asks for it (`PG_INCLUDE_FILES=1 git add <path>`) or the project lists it in `.platform-guardian.json` `"commitPaths"`. The session closer shows ✅ will commit / ⏸️ stays out.
- **Pre-PR check before every PR:** new `platform-guardian:pre-pr` skill (one-page PDF of what the change could break, outside the repo, never committed). The closer runs it automatically before push + PR; **skip** skips it; not run in QA repos or for docs-only changes. Also on request: "ready for PR", "what could I have broken".

## [0.2.5] — 2026-11-10

- **First-time welcome no longer buries the tour offer** (first tester bug): the first reply is only the welcome + the tour offer, as its last line, and waits. Git questions, the branch choice and "what are we working on" come after the employee answers yes/later — before, they followed the offer in the same message and the tester almost missed the tour.
- Docs: one-page employee guide, `docs/employee-guide.md`.

## [0.2.4] — 2026-11-09

- Routing: spec-team-toolkit 0.5.0 renamed `lld-web-figma-spec` → `lld-web-backend-spec` (one integrated web LLD for frontend, backend and QA) — the `spec` route follows it. Caught by the routes check.

## [0.2.3] — 2026-11-09

- Repo renamed `yes-platform-guardian` → `ono-platform-guardian`: manifest `repository`, clone commands and the drift-issue script point to the new name (GitHub redirects the old one).

## [0.2.2] — 2026-11-09

- Branding: **OnO Platform Guardian** — the first-time welcome uses the name; yes+ logo and footer removed from the README (manager's request).

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
