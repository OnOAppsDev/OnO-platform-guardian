---
name: session-closer
description: Platform Guardian session closer. Run when the employee wants to stop or wrap up ("I'm done", "that's it for today", "close the session", "bye", "thanks, that's all" — in any language), when they accept a close-out suggestion from the "[platform-guardian]" session-length signal, or after a plugin stage completes and they agree to stop. Saves the work safely without forcing git steps — a commit only when code changed (optional while the work is in progress), and the pre-PR check, push and PR only when the bug or feature is finished (never a direct push to the central branch) — writes the local session-log entry, gives a plain-language summary and tells them to /clear.
---

# Session closer

You close the session so nothing is lost and the next session can pick up exactly here. Plain language, short steps, answer in the employee's language. Every git action that changes anything happens **only after the employee confirms it**.

**Closing a session is not finishing the work.** Most closes happen in the middle of a bug or feature: uncommitted code is safe on the employee's computer, and the next session picks it up. So the closer never pushes the employee through commit → PR:
- **No code changed** (only notes, logs, plugin documents) → no commit, no question.
- **Code changed, work still in progress** → one optional question: a checkpoint commit. No push, no pre-PR check, no PR.
- **The bug or feature is finished** → the full path: commit, pre-PR check, push, PR.

## Hard rules

- **Never push to the central branch.** Work goes to a work branch and returns through a PR.
- **Never force** (`push --force`, `reset --hard`, `clean -f`, `branch -D`) and never rewrite pushed history.
- **Never commit secrets** (`.env`, keys, credentials) — if one is staged or untracked, stop and point it out.
- Don't stage everything blindly (`git add -A` / `git add .`); stage the confirmed list of paths.

## Steps

### 0. Mid-step? Say what would be redone

If an Ono plugin step is still running and hasn't saved its result (an analysis before its plan file is written, a task mid-implementation, a verification half done), tell the employee plainly before closing, in their language:

> ⚠️ ‹step› isn't saved yet — if we close now, next session it starts over (‹what repeats, e.g. "the analysis runs again from where it was saved"›). Finish it first? (recommended) — or say **close anyway**.

Wait for the answer. On **close anyway**: in step 6's log entry, write in **Where we stopped** the exact point *and* anything the employee already confirmed that the plugin hasn't saved (e.g. "routing confirmed: ios / tv — not in a plan yet"), so the next session can tell them.

### 1. Where are we

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/git-status.sh"
```

If `repo` is `false`, skip to step 6. If `operation` is set (merge/rebase in progress) or there are conflicts, resolve that with the employee first.

**Git guards.** If `guards.matrixQa` is true (Matrix QA repo — every git write and `gh pr create` from Claude is blocked) or `guards.onoQaCommitBlocked` is true (Ono QA repo — `git commit` / `git push` from Claude are blocked), the plugin's owners want the QA engineer to run those themselves. Do steps 2–5 as usual, but instead of running the blocked commands, give them as one ready-to-paste block the employee runs with the `!` prefix (e.g. `! git commit -m "…"`), and check the result with `git status` afterwards. Never work around the guard. In QA repos, never edit, reformat or re-save generated ledger / readiness files (`doNotTouch` in the allowlist).

### 1b. Finished, or in progress?

Decide once, from this session — never from a guess:

- **Finished** when the employee said so ("the bug is fixed", "done with the feature", "open a PR", "ready for review"), or the Ono flow for this branch reached its end this session — the fix was verified and reviewed, or every task is complete and reviewed, or the QA notes were created (`/create-dev-qa-notes`), or the project inspection was completed (its outputs go in a PR of their own). When the flow's end was reached but the employee didn't say it's finished, ask once: "Looks like ‹bug/feature› is finished — open the PR now? (yes / not yet)". **not yet** → in progress.
- **In progress** in every other case — including a close because the session got long.

### 2. Commit hygiene — only code goes in, unless the employee asks

**Ono rule, every flow (bugs, features, reviews, QA, inspections):** a commit holds the code change. Documents, data and working files stay **out** — not deleted, not `.gitignore`d, just not committed — unless the employee explicitly asks for a file or the project lists it in `.platform-guardian.json` `"commitPaths"`.

Go through `changes.files` (and `git status --porcelain` if the list is truncated) and sort every path:

- **✅ Will commit**
  - modified tracked files — mention anything that looks accidental (debug code, local config);
  - new **source code** and the config files that come with it (`package.json`, `Contents.json`, CI workflows …);
  - new files on the project's `"commitPaths"` list.
- **⏸️ Stays out** (default for everything else that's new): `.md`, `.json`, `.yaml`, `.txt`, `.log`, `.html` … — notes, drafts, tool output, and the documents the Ono plugins write while they work (bug work plans, task state, planning docs, reviews, inspector reports — `routing/committed-artifacts.json` lists where they land). They stay on disk for the next session.
- **⛔ Never**: anything on a `neverCommit` list (`.env`, keys, `*.bak` …) — point it out.

**Nothing under ✅** (only notes, logs, plugin documents, tool output changed) → there is nothing to commit. Say it in one line — "Nothing to commit: only ‹notes / logs› changed, and they stay on your computer." — and don't ask about a commit, a PR or a push. Go to step 5b (step 5 only if the work is finished and earlier commits aren't pushed yet).

**Code under ✅, work in progress** → ask one optional question, with the reassurance first: "Your code changes stay on your computer either way. Save them as a checkpoint commit on `‹branch›`? (yes / no)". **no** → nothing is committed; go to step 5b. **yes** → show the list below and commit (step 4). Then go to step 5b — no pre-PR check, no push, no PR while the work is in progress. One FYI line is enough: "The PR comes when the bug/feature is finished — just say **open PR** then."

**Code under ✅, work finished** → the full path below.

Show the short list — **✅ will commit** / **⏸️ stays out** — and wait for their OK. One line under it: "Want any ⏸️ file in the PR? Name it." Only when the employee names a file: stage that exact path with `PG_INCLUDE_FILES=1 git add ‹path›`. Exception — the Ono Project Inspector's outputs (`AUDIT.md`, `CLAUDE.md`, `docs/project/**`, `audits/**`, `.ono/state.json`, `.ono/repo-knowledge.json`) are mandatory project infrastructure: list them under ✅ will commit (the inspect gate reads them, and the whole team needs the same inspection). When another file **is** the deliverable of the flow, say so and ask about it by name; still only on their yes.

Never `git add -A` / `git add .`; stage the ✅ paths explicitly. Add a `.gitignore` line only if the employee asks (e.g. a file that keeps coming back) — exact path, never a blanket `*.md` / `*.json`.

A PreToolUse guard (`hooks/pre-tool-use.sh`) enforces this on every `git add` / `git commit`, in any flow — also when an Ono plugin's own process commits: new non-code files are denied unless the command carries `PG_INCLUDE_FILES=1` or the project lists them; `neverCommit` files are denied always. If it denies, stage the rest and tell the employee in one line which files stayed out — never work around it (no `git add -f`, no `PG_INCLUDE_FILES=1` the employee didn't name a file for). `PG_INCLUDE_FILES=1` also triggers a permission prompt: the employee confirms those files themselves.

### 3. Branch

- On the central branch (`onCentral`) → commits can't go there. Offer to create a work branch now (`git switch -c ‹name›`, following the repo's branch naming) and carry the changes over.
- Detached HEAD → create a branch first.

### 4. Commit

The guard asks the employee to confirm every `git commit` and `git push` in a permission prompt ("approve only if you asked for it"). Say it once before the commit: "Claude Code will ask you to approve the commit — that's Guardian making sure nothing is committed without you." Never commit or push outside this closer unless the employee explicitly asked for it in their own words.


Stage the confirmed paths and commit with a short message in the style of the repo's recent history (`git log --oneline -10`). Nothing to commit → say so and continue.

### 4b. Pre-PR check (automatic, before the PR — finished work only)

Only when the work is **finished** (step 1b). Before asking to push, run the pre-PR check on the employee's changes: if the Ono dev plugin's flow already produced its own pre-PR check for these commits in this session, show that result instead of running it again; otherwise run the **`platform-guardian:pre-pr`** skill. Many employees see it for the first time here — explain it so they know what it is, why, and what to do. In their language, roughly:

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
- Skip the check when: the work is in progress, there are no code commits to send, it's a QA repo (`guards.matrixQa` / `guards.onoQaCommitBlocked`), or the employee types **skip**.
- Something on the list turns out broken → that's the point: fix it first (back to the plugin's flow), then close again.
- Their answer (**push** / **push now**) is the go-ahead for step 5's push question — still name the target branch and ask for reviewers there.
- Mention it in the session-log entry (`pre-PR: N 🔴 / M 🟠` or `skipped`).

### 5. Push + PR (finished work only)

Work in progress → skip this step entirely. Their commits stay on this computer until the work is finished; if they ask to push as a backup, push the work branch only (no PR).

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
- **Git:** ‹branch› · ‹in progress: "not committed" / "checkpoint commit" — or finished: pushed + PR link› · pre-PR: ‹N 🔴 / M 🟠, skipped, or "not yet — work in progress"›
EOF
```

The script adds the date + branch heading. The next session's opener reads this entry.

### 7. Plain-language summary

Two to four short sentences anyone could understand: what got done, what's saved where, what's next. No jargon, no scores.

### 8. Tell them exactly what to do next

Never end with a vague "you can stop now". End with these steps, clearly and on their own (in the employee's language):

> ✅ **Everything is saved** — ‹"your changes are on your computer" / checkpoint commit / PR link› and a note of where we stopped.
>
> **To start fresh:**
> 1. Type **`/clear`** and press Enter.
> 2. Write your next message — anything: "continue", a new task, a question.
> 3. Before anything else I'll show your git state and where we stopped, then get to your message.
>
> Closing for the day? Tomorrow, open Claude Code in this project folder and write whatever you want to work on — same thing happens.
