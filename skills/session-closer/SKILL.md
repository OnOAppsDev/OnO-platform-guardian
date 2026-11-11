---
name: session-closer
description: Platform Guardian session closer. Run when the employee wants to stop or wrap up ("I'm done", "that's it for today", "close the session", "bye", "thanks, that's all" — in any language), when they accept a close-out suggestion from the "[platform-guardian]" session-length signal, or after a plugin stage completes and they agree to stop. Saves the work safely — commit hygiene (only code unless the employee asks), commit on a work branch, automatic pre-PR regression check, push, PR to the central branch (never a direct push to it) — writes the local session-log entry, gives a plain-language summary and tells them to /clear.
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

### 2. Commit hygiene — only code goes in, unless the employee asks

**Ono rule, every flow (bugs, features, reviews, specs, QA, inspections):** a commit holds the code change. Documents, data and working files stay **out** — not deleted, not `.gitignore`d, just not committed — unless the employee explicitly asks for a file or the project lists it in `.platform-guardian.json` `"commitPaths"`.

Go through `changes.files` (and `git status --porcelain` if the list is truncated) and sort every path:

- **✅ Will commit**
  - modified tracked files — mention anything that looks accidental (debug code, local config);
  - new **source code** and the config files that come with it (`package.json`, `Contents.json`, CI workflows …);
  - new files on the project's `"commitPaths"` list.
- **⏸️ Stays out** (default for everything else that's new): `.md`, `.json`, `.yaml`, `.txt`, `.log`, `.html` … — notes, drafts, tool output, and the documents the Ono plugins write while they work (bug work plans, task state, planning docs, reviews, spec drafts, inspector reports — `routing/committed-artifacts.json` lists where they land). They stay on disk for the next session.
- **⛔ Never**: anything on a `neverCommit` list (`.env`, keys, `*.bak` …) — point it out.

Show the short list — **✅ will commit** / **⏸️ stays out** — and wait for their OK. One line under it: "Want any ⏸️ file in the PR? Name it." Only when the employee names a file: stage that exact path with `PG_INCLUDE_FILES=1 git add ‹path›`. Exception — when the file **is** the deliverable of the flow (the spec of a spec session, the inspector's `CLAUDE.md` / `AUDIT.md`), say so and ask about it by name; still only on their yes.

Never `git add -A` / `git add .`; stage the ✅ paths explicitly. Add a `.gitignore` line only if the employee asks (e.g. a file that keeps coming back) — exact path, never a blanket `*.md` / `*.json`.

A PreToolUse guard (`hooks/pre-tool-use.sh`) enforces this on every `git add` / `git commit`, in any flow — also when an Ono plugin's own process commits: new non-code files are denied unless the command carries `PG_INCLUDE_FILES=1` or the project lists them; `neverCommit` files are denied always. If it denies, stage the rest and tell the employee in one line which files stayed out — never work around it (no `git add -f`, no `PG_INCLUDE_FILES=1` the employee didn't ask for).

### 3. Branch

- On the central branch (`onCentral`) → commits can't go there. Offer to create a work branch now (`git switch -c ‹name›`, following the repo's branch naming) and carry the changes over.
- Detached HEAD → create a branch first.

### 4. Commit

Stage the confirmed paths and commit with a short message in the style of the repo's recent history (`git log --oneline -10`). Nothing to commit → say so and continue.

### 4b. Pre-PR check (automatic, before every push + PR)

Before asking to push, run the **`platform-guardian:pre-pr`** skill on the employee's changes. Many employees see it for the first time here — explain it so they know what it is, why, and what to do. In their language, roughly:

**Before** (then run it):

> 🔍 **Before the PR — a quick safety check.** I'm looking at the code you changed and everything that uses it, to find what it might have broken somewhere else. In a moment a one-page PDF opens with a short list of what to test in the app:
> - 🔴 **Must test** — check these before you send the PR.
> - 🟠 **Should test** — worth a quick look.
> - ⚠️ **Watch out** — spots in the code that look risky.
>
> The PDF is just for you — not saved in the project, not part of the PR. (Type **skip** to skip it.)

**After** the PDF opened — one short message, then wait:

> ✅ **Your checklist is open:** ‹N› 🔴 must test · ‹M› 🟠 should test. Most important: ‹the single biggest risk, plain words›.
> 👉 Test the 🔴 items in the app, then type **push** — or **push now** if you've already tested them.

- No PDF (no Chrome on the machine): show the same list right in the chat instead, and say so.
- Skip the check when: nothing was committed in this session, only docs / non-code files changed, it's a QA repo (`guards.matrixQa` / `guards.onoQaCommitBlocked`), or the employee types **skip**.
- Something on the list turns out broken → that's the point: fix it first (back to the plugin's flow), then close again.
- Their answer (**push** / **push now**) is the go-ahead for step 5's push question — still name the target branch and ask for reviewers there.
- Mention it in the session-log entry (`pre-PR: N 🔴 / M 🟠` or `skipped`).

### 5. Push + PR

- **Ask first, in one question** — the OK in step 2 covered the commit, not sharing it: "Push `‹branch›` and open a PR to `‹central›`? Reviewers? (or stop here — it's committed locally)". Wait for the answer.
- Push the work branch: `git push -u origin ‹branch›`. Rejected because the remote moved → explain, offer `git pull --no-rebase` (merge) and retry; never force.
- PR: check for an existing one first (`gh pr view --json url,state 2>/dev/null`). If none, use the target branch and reviewers from that answer (target default: the central branch from the report), then `gh pr create --base ‹target› --fill` (add `--reviewer` if given). If `gh` isn't installed or authenticated, give the compare link from the push output and tell them to open the PR there.
- The employee may choose to stop before pushing (e.g. work not ready to share) — fine; record it in the log.

### 5b. Tool bug during the session?

If something in Guardian, an Ono plugin or Claude Code misbehaved this session and no bug report was written yet, offer it once before the log: "🐞 Earlier ‹what broke›. Want a bug report for Tom first? (type **report**)" — yes → `platform-guardian:report-bug`, then continue here.

### 6. Write the session-log entry (local, never in git)

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/session-log.sh" append <<'EOF'
- **What we did:** ‹1–2 short sentences›
- **Where we stopped:** ‹the exact point, e.g. "validation done, API call not started"›
- **Next step:** ‹the first thing to do next session›
- **Git:** ‹branch› · ‹committed / pushed / PR link, or "not pushed"› · pre-PR: ‹N 🔴 / M 🟠, or skipped›
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
