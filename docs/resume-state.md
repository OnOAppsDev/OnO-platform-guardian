# Resume state — what `scripts/resume-state.sh` reads

G2.3. At session start (and when the router needs "where was I"), Guardian lists **unfinished work** from the documents the Ono plugins write — no node, no jq, under a second on a real repo. Finished work is not listed. Every stage is *apparent*: approvals with fingerprints and freshness are re-checked by the plugin's own command when it runs.

Traced to plugin source on 2026-11-08 (latest `main`): ono-mobile-dev-plugin 0.7.0, ono-plugin-qa 0.11.0, ono-project-inspector 0.11.0 (formats re-checked unchanged in 0.12.0, 2026-11-24, 0.13.0 and 0.14.0, 2026-11-25 — its header line sits below the H1). Every document parser drops `\r`, so a Windows CRLF checkout reads the same (tested). (spec-team-toolkit and matrix-qa-plugin were dropped in Guardian 0.5.0.) When a plugin's version moves (CI `check-routes.sh --strict` flags it), re-check this page.

Output: one line per item, at most `PG_RESUME_MAX` (8); `PG_RESUME=off` disables.

```
- <plugin> · <what> · <stage> · next: <command | "your step — …">  [<evidence file>]
```

"your step" = a human-only approval or sign-off (`routes.json` `humanOnly`); Guardian tells the employee what to type and never runs it.

## ono-mobile-dev-plugin — features

Found the way the plugin finds them: `*.md` under `docs/` (depth ≤ 6, not `bugs/`, `tasks/`, `node_modules/`), max 400 files. Frontmatter = `---` block on line 1, else the first ` ```yaml ` fence before the first `## ` heading outside an HTML comment; inline ` #` comments and `null` are dropped. There is no `doc_type` key — the type comes from keys:

| Key present | Doc |
|---|---|
| `work_type` | bug document — lives in `docs/bugs/`, not scanned here |
| `dev_plan_link` | Task Breakdown |
| `detail_level` / `dd_generation` | Design Doc |
| `generated_by: create-dev-qa-notes` | QA handoff |
| `dd_link` + `repo_knowledge_status` / `surface` / `capability` / `design_reference_fingerprint` | Feature Analysis |
| `dd_link` only | Dev Plan if the filename says `dev-plan`, else FA (legacy FAs look like Dev Plans) |

Several files of one kind for a feature (`-v1` copies): the shortest path wins. Stage, most advanced doc first:

| State | Next |
|---|---|
| handoff `ready-for-qa` | — done on the dev side |
| handoff `draft` | your step — set `ready-for-qa` |
| TB or Dev Plan not `approved` | your step — approve both, then `/implement-task <f> T1` |
| TB approved, a task not `complete` in `docs/tasks/<f>-task-state.json` | `/implement-task <f> <first not complete>` |
| all tasks complete, no `docs/reviews/<f>/review.md` | `/review-code --feature <f>` (dev plugin 0.8.0+; older: `/review-code` if not done, then `/create-dev-qa-notes <f>`) |
| review record exists | `/pre-pr feature:<f>` (skips itself if already done), then `/create-dev-qa-notes <f>` |
| DD `draft` / `approved` | your step — approve / `/dev-feature-start <f>` |
| FA `proposed` / `approved` | your step — approve / `/dev-design-start <f>` |

Task ids: first column of TB tables matching `^([A-Za-z]+[0-9]+|C[1-9][0-9]*-T[1-9][0-9]*)$`. Task state: pretty-printed JSON, task ids at 4-space indent inside `"tasks"`, `"state"` at 6 spaces (`in-progress | complete | blocked | failed`). Staleness (`rowFingerprint`) is not checked.

## ono-mobile-dev-plugin — bugs (`docs/bugs/<key>/`)

| State | Next |
|---|---|
| no `bug-work-plan.md` | `/analyze-bug <key>` |
| plan not `approved`, or `approved_cycle ≠ fix_cycle` | `/analyze-bug <key>` (resumes at the approval, which is the employee's) |
| a cycle task not complete (`docs/tasks/bugs/<key>.task-state.json`) | `/implement-task bug:<key> <task>` — cycle 1 = `## Tasks`, cycle n = `### Cycle n` |
| `verification-c<n>.md` missing or not `passed` | your step — `/verify-fix-cycle bug:<key>` |
| no `review-c<n>.md` | `/review-code --bug <key>` |
| `docs/qa/bug-<key>-qa-handoff.md` `ready-for-qa` for cycle n | — waiting for QA |
| otherwise | `/pre-pr bug:<key>` (0.8.0+, skips itself if already done), then `/create-dev-qa-notes bug:<key>` |

## ono-project-inspector

Only when `AUDIT.md` starts `# AUDIT.md` or `.ono/state.json` exists. `AUDIT.md` is the truth; `state.json` is not read (often stale). The topic table header is `| # | Status | Topic | Priority | File | Notes |`; statuses `Pending Breakdown | Draft | Approved`. Audit files say `Status: Draft` forever — never read them.

| State | Next |
|---|---|
| `CLAUDE.md` or any `docs/project/{overview,components,patterns,integrations}.md` missing (`capabilities.md` is a knowledge-model artifact — its absence never reopens stage 2) | your step — `/inspect-approve` (or `/inspect` → Continue) |
| no readable topics | `/inspect-status` |
| a `Draft` topic | your step — review its file, then `/inspect-approve` |
| `Pending Breakdown` topics | `/inspect-topic` |
| all `Approved` | — done |

## ono-plugin-qa (mobile / TV)

QA repo: `.claude/qa-workspace.json` `qaRepoPath` (in the session folder or next to the repo), else this repo when its folder name contains `qa` (not an inspector or Matrix repo). Per feature `<qa>/<slug>/test-plan.md`; status from the first ` ```yaml ` block anywhere.

| State | Next |
|---|---|
| plan not `approved` | your step — `/approve-qa-test-plan <slug>` |
| `readiness/feature/<slug>.md` `signoff_status: valid` | — done |
| readiness `READY` / `READY_WITH_EXCEPTIONS`, not signed off | your step — `/qa-signoff <slug>` |
| no `<slug>/coverage-report.md` | `/check-qa-coverage <slug>` |
| no `qa-ledger/builds/*.json` with `"feature:<slug>"` | `/register-build <slug> <build-id>` |
| no `"field":"surfaces"` in `qa-ledger/scopes/feature/<slug>.jsonl` | your step — `/set-qa-scope <slug>` |
| no closed (`"kind":"run.closed"`) `qa-ledger/runs/functional-*.jsonl` for the scope | `/record-execution <slug>` |
| otherwise | `/qa-readiness <slug>` — it lists the exact blockers |

Smoke, bug, regression and sign-off validity are derived by the plugin's node ledger; past the functional run Guardian hands over to `/qa-readiness` instead of approximating them.
