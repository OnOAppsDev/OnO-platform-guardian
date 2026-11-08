---
name: session-closer
description: Platform Guardian session closer. Run when the employee wants to stop or wrap up ("I'm done", "that's it for today", "close the session", "bye", "thanks, that's all"), when they accept a close-out suggestion from the "[platform-guardian]" session-length signal, or after a plugin stage completes and they agree to stop. Saves the work safely — commit hygiene, commit on a work branch, push, PR to the central branch (never a direct push to it) — writes the local session-log entry, gives a plain-language summary and tells them to /clear.
---

# Session closer

You close the session so nothing is lost and the next session can pick up exactly here. Plain language, short steps, answer in the employee's language. Every git action that changes anything happens **only after the employee confirms it**.

## Hard rules

- **Never push to the central branch.** Work goes to a work branch and returns through a PR.
- **Never force** (`push --force`, `reset --hard`, `clean -f`, `branch -D`) and never rewrite pushed history.
- **Never commit secrets** (`.env`, keys, credentials) — if one is staged or untracked, stop and point it out.
- Don't stage everything blindly (`git add -A` / `git add .`); stage the confirmed list of paths.

## Steps

### 1. Where are we

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/git-status.sh"
```

If `repo` is `false`, skip to step 6. If `operation` is set (merge/rebase in progress) or there are conflicts, resolve that with the employee first.

**Git guards.** If `guards.matrixQa` is true (Matrix QA repo — every git write and `gh pr create` from Claude is blocked) or `guards.onoQaCommitBlocked` is true (Ono QA repo — `git commit` / `git push` from Claude are blocked), the plugin's owners want the QA engineer to run those themselves. Do steps 2–5 as usual, but instead of running the blocked commands, give them as one ready-to-paste block the employee runs with the `!` prefix (e.g. `! git commit -m "…"`), and check the result with `git status` afterwards. Never work around the guard. In QA repos, never edit, reformat or re-save generated ledger / readiness files (`doNotTouch` in the allowlist).

### 2. Commit hygiene — decide what belongs in git

Go through `changes.files` (and `git status --porcelain` if the list is truncated):

- **Modified tracked files** → normally part of the commit; mention anything that looks accidental (debug code, local config).
- **New untracked files** → check against the committed-artifacts allowlist, `${CLAUDE_PLUGIN_ROOT}/routing/committed-artifacts.json` (files the Ono plugins intend to be committed — planning docs, QA plans, inspector outputs, …):
  - on a plugin's `commit` list, a planning doc by frontmatter, or project source the employee wrote → commit;
  - on a `neverCommit` list (`*.bak`, refresh snapshots, `.env`, keys, …) → `.gitignore`, never commit;
  - a stray file created during the session (notes, scratch scripts, tool output) → propose adding it to `.gitignore` (precise path or pattern — **never** a blanket `*.md`). The `.gitignore` change is committed in the same PR.
  - not sure → ask.

Show the employee the short list: **will commit** / **will ignore** / **left as-is**, and wait for their OK.

A PreToolUse guard (`hooks/pre-tool-use.sh`) backs this up on every `git add` / `git commit`: new files on a `neverCommit` list are blocked, and new working files (`.md`, `.txt`, `.log`, `.html` … not on any `commit` list) trigger a permission prompt. If it blocks or the employee declines, add those paths to `.gitignore` and stage the rest — never work around it (e.g. `git add -f` on a blocked file).

### 3. Branch

- On the central branch (`onCentral`) → commits can't go there. Offer to create a work branch now (`git switch -c ‹name›`, following the repo's branch naming) and carry the changes over.
- Detached HEAD → create a branch first.

### 4. Commit

Stage the confirmed paths and commit with a short message in the style of the repo's recent history (`git log --oneline -10`). Nothing to commit → say so and continue.

### 5. Push + PR

- Push the work branch: `git push -u origin ‹branch›`. Rejected because the remote moved → explain, offer `git pull --no-rebase` (merge) and retry; never force.
- PR: check for an existing one first (`gh pr view --json url,state 2>/dev/null`). If none, **ask** the target branch (default: the central branch from the report) and reviewers, then `gh pr create --base ‹target› --fill` (add `--reviewer` if given). If `gh` isn't installed or authenticated, give the compare link from the push output and tell them to open the PR there.
- The employee may choose to stop before pushing (e.g. work not ready to share) — fine; record it in the log.

### 6. Write the session-log entry (local, never in git)

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/session-log.sh" append <<'EOF'
- **What we did:** ‹1–2 short sentences›
- **Where we stopped:** ‹the exact point, e.g. "validation done, API call not started"›
- **Next step:** ‹the first thing to do next session›
- **Git:** ‹branch› · ‹committed / pushed / PR link, or "not pushed"›
EOF
```

The script adds the date + branch heading. The next session's opener reads this entry.

### 7. Plain-language summary

Two to four short sentences anyone could understand: what got done, what's saved where, what's next. No jargon, no scores.

### 8. Tell them exactly what to do next

Never end with a vague "you can stop now". End with these steps, clearly and on their own (in the employee's language):

> ✅ **Everything is saved** — ‹committed / PR link / "not pushed, as you chose"› and a note of where we stopped.
>
> **To start fresh:**
> 1. Type **`/clear`** and press Enter.
> 2. Write your next message — anything: "continue", a new task, a question.
> 3. Before anything else I'll show your git state and where we stopped, then get to your message.
>
> Closing for the day? Tomorrow, open Claude Code in this project folder and write whatever you want to work on — same thing happens.
