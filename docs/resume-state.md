# Resume state — what `scripts/resume-state.sh` reads

G2.3. At session start (and when the router needs "where was I"), Guardian lists **unfinished work** from the documents the Ono plugins write — no node, no jq, under a second on a real repo. Finished work is not listed. Every stage is *apparent*: approvals with fingerprints and freshness are re-checked by the plugin's own command when it runs.

Traced to plugin source on 2026-11-08 (latest `main`): ono-mobile-dev-plugin 0.7.0, ono-plugin-qa 0.11.0, matrix-qa-plugin 0.1.0, spec-team-toolkit 0.4.2, ono-project-inspector 0.11.0. When a plugin's version moves (CI `check-routes.sh --strict` flags it), re-check this page.

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
| all tasks complete | `/review-code` (if not done — no file records it), then `/create-dev-qa-notes <f>` |
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
| otherwise | `/create-dev-qa-notes bug:<key>` |

## ono-project-inspector

Only when `AUDIT.md` starts `# AUDIT.md` or `.ono/state.json` exists. `AUDIT.md` is the truth; `state.json` is not read (often stale). The topic table header is `| # | Status | Topic | Priority | File | Notes |`; statuses `Pending Breakdown | Draft | Approved`. Audit files say `Status: Draft` forever — never read them.

| State | Next |
|---|---|
| `CLAUDE.md` or any `docs/project/{overview,components,patterns,integrations,capabilities}.md` missing | your step — `/inspect-approve` (or `/inspect` → Continue) |
| no readable topics | `/inspect-status` |
| a `Draft` topic | your step — review its file, then `/inspect-approve` |
| `Pending Breakdown` topics | `/inspect-topic` |
| all `Approved` | — done |

## spec-team-toolkit

The toolkit writes outside the repo (MGA-68), so only specs saved into `docs/specs/<feature-slug>/` (Guardian convention) are seen.

| Doc | Unfinished when | Next |
|---|---|---|
| `spac_<f>.md` | `**Status:** 🟡 DRAFT`, or `✅ READY` without `dd_<f>.md` | `spec-team-toolkit:lld-mobile-spec` |
| `hld-draft.md` | a section tag `[סטטוס: …]` other than `הושלם` / `לא רלוונטי…` | `spec-team-toolkit:hld-builder` |
| backend LLD (`# LLD:` H1) | `**Status:** DRAFT` | `spec-team-toolkit:lld-backend-spec` |

Web LLDs have no header or status — not detectable.

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

## matrix-qa-plugin (web)

`matrix-qa.config.json` from the session folder up to the repo's parent; `paths.lldDir` / `testCasesDir` / `testDir` (defaults `qa/lld`, `qa/test-cases`, `tests/e2e`). Fingerprints are an exact port of `mqa.mjs` (`fingerprint` / `contentFingerprint`: BOM, CRLF, trailing whitespace, trim; `change-log` and `approval` sections excluded) — verified against `mqa.mjs plan state / validate` on the plugin's `examples/login` through every status; `tests/resume-state.test.sh` re-checks it when `PG_MQA=<path to mqa.mjs>` is set.

| State | Next |
|---|---|
| LLD without a plan | `/qa-plan <lldDir>/<f>.md` |
| LLD fingerprint ≠ `lld_fingerprint` | `/qa-sync <f>` |
| `DRAFT` / `CHANGES_REQUIRED` | `/qa-review <f>` |
| `REVIEWED`, content changed since review | `/qa-review <f>` |
| `REVIEWED` | your step — `/qa-approve <f>` |
| `APPROVED`, content changed since approval | `/qa-review`, then your `/qa-approve` |
| approved, no `test('<FEATURE_ID>-TC-nnn'` in `testDir` | `/qa-automate <f>` |
| approved and automated | — done (runs are local and git-ignored, so not tracked) |
