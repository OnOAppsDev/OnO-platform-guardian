# Project config — `.platform-guardian.json`

Optional file at the root of a work repository. **Absent = auto-detect everything.** It is committed with the project, so changes go through a PR like any other change.

```json
{
  "centralBranch": "develop",
  "team": "ios",
  "role": "developer"
}
```

| Key | Used by | Meaning |
|---|---|---|
| `centralBranch` | `scripts/git-status.sh` (G1) | The branch all work branches from and merges back into. Overrides detection (`origin/HEAD` → `develop` → `main` → `master`). Must exist on the remote (or locally when there is no remote); otherwise the report adds the `override-not-found` warning and falls back to detection. |
| `team` | reserved — router (G2) | Narrows intent routing to the team's plugins (e.g. `ios`, `android`, `web`, `qa`, `spec`). |
| `role` | reserved — router (G2) | e.g. `developer`, `qa`, `pm`. |

Unknown keys are ignored. The file is read without `jq`, so keep `"centralBranch": "<name>"` on one line.

The session opener offers to create this file when the central branch can't be detected with confidence.

## Local session log (not in this file, not in git)

`~/.claude/platform-guardian/<repo>/<branch>.md` — one file per repo + branch, entries appended by the session closer and read by the opener (`scripts/session-log.sh`). `<repo>` is the remote's repository name (folder name when there is no remote); `/` in branch names becomes `_`. Override the base folder with `PG_LOG_DIR`.

## Git report

`scripts/git-status.sh [dir]` prints one JSON object (schema 1) and always exits 0. Warnings: `dir-not-found`, `git-not-installed`, `detached-head`, `unborn-head`, `no-remote`, `fetch-failed`, `fetch-timeout`, `override-not-found`, `central-ambiguous`, `central-unknown`, `on-central`, `behind-central`, `operation-in-progress`, `matrix-qa-git-blocked`, `ono-qa-commit-blocked` (the last two mirror org-plugin hooks that block Claude's git writes; also in `guards`). Env: `PG_NO_FETCH=1`, `PG_FETCH_TIMEOUT=<seconds>` (default 5).

## Session-length signal

`hooks/prompt-submit.sh` reads the real context size from the transcript and, past the threshold, asks Claude to suggest the close-out once per band. Env: `PG_CLOSEOUT_TOKENS` (default 120000), `PG_CLOSEOUT_STEP` (default 40000).

## Commit guard

`hooks/pre-tool-use.sh` runs before every Bash command. Only `git add` / `git stage` / `git commit` (also after `cd`, `&&`, `;`, `|`, and with `git -C`) are inspected: it runs `git add --dry-run` with the same arguments and reads new files already staged, then checks the **new** (untracked) files against `routing/committed-artifacts.json` — `neverCommit` → denied; not on any `commit` list and a working-file type (`.md`, `.txt`, `.log`, `.html`, `.csv`, `.patch` …, except README / CHANGELOG / LICENSE and frontmatter planning docs) → permission prompt; anything else → no output. Commands with `$(…)` or backticks, and interactive adds, are skipped. Env: `PG_COMMIT_GUARD=off`.
