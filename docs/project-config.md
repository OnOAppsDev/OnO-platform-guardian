# Project config — `.platform-guardian.json`

Optional file at the root of a work repository. **Absent = auto-detect everything.** It is committed with the project, so changes go through a PR like any other change.

```json
{
  "centralBranch": "develop",
  "commitPaths": ["docs/specs/**", "AUDIT.md"],
  "team": "ios",
  "role": "developer"
}
```

| Key | Used by | Meaning |
|---|---|---|
| `centralBranch` | `scripts/git-status.sh` (G1) | The branch all work branches from and merges back into. Overrides detection (`origin/HEAD` → `develop` → `dev` → `main` → `master`; an unusual `origin/HEAD` while a conventional branch exists, or a branch >1000 commits ahead, counts as unsure — the opener asks once and saves the answer here for the team). Must exist on the remote (or locally when there is no remote); otherwise the report adds the `override-not-found` warning and falls back to detection. |
| `commitPaths` | `hooks/pre-tool-use.sh`, session closer | Git-style globs of non-code files this project **does** commit (e.g. specs). Everything else that isn't code stays out of commits unless the employee asks. Keep the array on one line. |
| `inspectRequired` | `scripts/inspect-status.sh`, inspect gate | `false` exempts this repo from the inspect gate (e.g. a QA-only or docs repo). Committed, so it goes through PR review — manager's call. Default: required. |
| `team` | reserved — router (G2) | Narrows intent routing to the team's plugins (e.g. `ios`, `android`, `web`, `qa`, `spec`). |
| `role` | reserved — router (G2) | e.g. `developer`, `qa`, `pm`. |

Unknown keys are ignored. The file is read without `jq`, so keep `"centralBranch": "<name>"` and the `"commitPaths": [...]` array each on one line.

The session opener offers to create this file when the central branch can't be detected with confidence.

## Local session log (not in this file, not in git)

`~/.claude/platform-guardian/<repo>/<branch>.md` — one file per repo + branch, entries appended by the session closer and read by the opener (`scripts/session-log.sh`). `<repo>` is the remote's repository name (folder name when there is no remote); `/` in branch names becomes `_`. Override the base folder with `PG_LOG_DIR`.

## Git report

`scripts/git-status.sh [dir]` prints one JSON object (schema 1) and always exits 0. Warnings: `dir-not-found`, `git-not-installed`, `detached-head`, `unborn-head`, `no-remote`, `fetch-failed`, `fetch-timeout`, `override-not-found`, `central-ambiguous`, `central-unknown`, `on-central`, `behind-central`, `operation-in-progress`, `matrix-qa-git-blocked`, `ono-qa-commit-blocked` (the last two mirror org-plugin hooks that block Claude's git writes; also in `guards`). Env: `PG_NO_FETCH=1`, `PG_FETCH_TIMEOUT=<seconds>` (default 5).

## Session-length signal

`hooks/prompt-submit.sh` reads the real context size from the transcript and, past the threshold, asks Claude to suggest the close-out once per band. Env: `PG_CLOSEOUT_TOKENS` (default 120000), `PG_CLOSEOUT_STEP` (default 40000).

The same hook adds a **routing reminder** to every typed message inside a git repo (not slash commands; a message starting with a pasted `/path` does get it) until the session has been routed — the `work-router` or `pre-pr` skill ran, or an Ono plugin skill or command ran (full name, or a short form listed in `routes.json`): a task goes through `platform-guardian:work-router` before any investigation or edit. Env: `PG_ROUTE_REMINDER=off`.

## Inspect gate

Ono rule: every project goes through the Ono Project Inspector before work starts. The project folder may be a subfolder of the git root (e.g. `yestvos/YesTVOS/`): the nearest folder from the session folder up to the git root holding the inspector's `AUDIT.md`, or the single subfolder holding `.ono/state.json` (`inspect-status.sh root`). `scripts/inspect-status.sh check` decides: **done** = the inspector's `AUDIT.md` + `CLAUDE.md` + `docs/project/{overview,components,patterns,integrations}.md` (stages 1–2; open audit topics don't block). A missing knowledge-model artifact (`docs/project/capabilities.md`, the inspector registry's `knowledgeModel`) means the inspection predates the current model: still **done**, with a non-blocking "Refresh Project Knowledge" hint — the inspector itself never reopens a completed stage for it · **partial** = started, not finished · **on-central** = the central branch has it, this branch doesn't · **missing** · **override** · **exempt** (`"inspectRequired": false`) · **skip** (not git).

`hooks/inspect-gate.sh` runs on `UserPromptSubmit` and `UserPromptExpansion`. While the status is missing / partial / on-central it **blocks** every message and every Ono plugin command (full `/plugin:cmd` or a short form listed in `routes.json`) with a red ⛔ banner. Not blocked: the inspector's own commands (after one ran, the rest of that session flows — answering its questions), Guardian's commands, built-ins (`/clear`, `/plugin`, …), and the manager-approval sentence — `I have manager approval to work without inspect` or `יש לי אישור מנהל לעבוד בלי inspect` (case, spaces and a final `.` / `!` ignored). The sentence writes `~/.claude/platform-guardian/<repo>/inspect-override` (date · branch · git user) — valid for that local day only. Env: `PG_INSPECT_GATE=off`.

## Commit guard

`hooks/pre-tool-use.sh` runs before every Bash command. Only `git add` / `git stage` / `git commit` (also after `cd`, `&&`, `;`, `|`, with `git -C`, and after `VAR=value` prefixes) are inspected: it runs `git add --dry-run` with the same arguments and reads new files already staged, then checks the **new** (untracked) files. **Only code goes in by default (Ono rule, every flow):**

- `neverCommit` in `routing/committed-artifacts.json` (secrets, plugin scratch) → **denied, always**.
- Documents, data and working files (`.md`, `.json`, `.yaml`, `.txt`, `.log`, `.html`, `.csv`, `.patch` …) and everything the Ono plugins write while they work (their `commit` lists, frontmatter planning docs) → **denied** — they stay out of the commit, on disk, not `.gitignore`d. Allowed when the project lists them in `"commitPaths"`, or when the employee asked for that file in chat (Claude then runs `PG_INCLUDE_FILES=1 git add <path>`).
- The Ono Project Inspector's outputs (`AUDIT.md`, `CLAUDE.md`, `docs/project/**`, `audits/**`, `.ono/state.json`, `.ono/repo-knowledge.json`) → no output: mandatory, shared by the team — at the repo root, or under a subfolder that holds the inspector's `AUDIT.md` / `.ono/state.json`.
- Source code, README / CHANGELOG / LICENSE, `.env.example`, and config files a code change adds (`package.json`, `tsconfig*.json`, `Contents.json`, CI workflows …) → no output.

**The employee confirms, never Claude alone:** every `git commit` and `git push`, and every `PG_INCLUDE_FILES=1` add of non-code files, gets a permission prompt (`ask`) naming the branch / files — "approve only if you asked for it". Denials above still win.

Commands with `$(…)` or backticks, and interactive adds, are skipped. Env: `PG_COMMIT_GUARD=off`.
