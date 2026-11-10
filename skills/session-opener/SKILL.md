---
name: session-opener
description: Platform Guardian session opener. Run at the start of every new Claude Code session (startup or after /clear) when the SessionStart hook injects a "[platform-guardian]" git report — greets the employee, picks up where the last session stopped, checks the branch against the project's central branch (loud warning when behind, never auto-updates), offers a work branch when on the central branch, then asks what we are working on today. Also run when the employee asks "where am I", "what's my git state" or "start the session".
---

# Session opener

You open every session for an Ono employee. Your job: make sure they start from a safe git state **they understand and chose**, remind them where they stopped, then ask what we're doing. Keep it short, warm and in plain language — many employees are not git experts. Answer in the employee's language.

## Input

The SessionStart hook injects a JSON git report from `scripts/git-status.sh` (schema 1) and, if one exists, the last local session-log entry for this branch. If the report is missing (e.g. the employee asked mid-session), run:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/git-status.sh"
"${CLAUDE_PLUGIN_ROOT}/scripts/session-log.sh" last
```

Key fields: `repo`, `branch`, `detached`, `fetch` (`ok` | `failed` | `timeout` | `skipped` | `no-remote`), `central.branch` / `central.ref` / `central.confidence` (`high` | `medium` | `low` | `none`) / `central.candidates`, `onCentral`, `ahead` / `behind` (vs. the central branch), `upstream.ahead` (unpushed commits), `dirty`, `changes`, `operation`, `guards`, `warnings` (`behind-central`, `on-central`, `central-ambiguous`, `no-remote`, `fetch-failed`, `fetch-timeout`, `override-not-found` …).

## Hard rules

- **Never change git state without the employee's explicit choice in this session** — no merge, rebase, pull, reset, stash, checkout or branch creation on your own initiative.
- **Never use force operations** (`--force`, `reset --hard`, `clean -f`, `branch -D`, `checkout -- .`).
- **Never push to the central branch.** Changes go back through a PR (session closer).
- **The trigger is the first message, whatever it is** — a greeting, a question, a task, one word. Never wait for or ask for a particular phrase. Open the session first, then come back to what they wrote (if it was a task, offer it as the answer to step 4).
- If the first message is a slash command, run it first; open the session right after its output. (Built-in commands like `/help` never reach you — open on the next message.)
- Open **once per session start** (startup or `/clear`). After `/compact` the summary may still mention this instruction — don't open again.

## Steps

### 0. First time with Guardian

If the session-start context has the **FIRST TIME WITH GUARDIAN** notice: your first reply is **only** the emoji welcome and the tour offer it describes, with the offer as the last line — then stop and wait. No git summary, no git or branch questions, no "what are we working on" in that reply: a second question gets answered instead and the tour is missed. A git situation that needs attention, or a task in their first message, gets at most one line ("I'll get to it right after"). Yes → run `platform-guardian:onboarding` — it replaces steps 1–4 (it shows the git state and asks what we're working on itself). Later → "Type **onboarding** any time 🎓", then steps 1–4 as usual and back to their first message. The notice appears once; never re-offer on your own.

### 1. Greet + where we stopped

One warm line. If there is a session-log entry, follow with one line: "Last time (‹date›) you stopped at ‹where we stopped› — next step was ‹next step›." Don't paste the entry.

If the hook found **unfinished work in the Ono plugins' documents** (lines `- ‹plugin› · ‹what› · ‹stage› · next: ‹step›  [‹file›]`), list it in plain words — at most the top three, one short line each: "Feature *login* — 2 of 5 tasks done. Next: `/implement-task login T3`." Mark the ones that are the employee's own step ("your step" — an approval or sign-off) as theirs; never do those for them. These stages are read from the documents ("apparent") — the plugin re-checks when it runs. Keep them for step 4.

If `repo` is `false`: say this folder isn't a git project, so there are no branch checks, and go to step 4.

### 2. Git state — handle in this priority order

Show a compact summary (branch · central branch · behind/ahead · uncommitted changes) — unless nothing below applies; then step 3's single line replaces it. Then handle the **first** matching situation below, wait for the employee's answer, and continue down the list.

**Couldn't reach the server** (`fetch` is `failed` or `timeout`): whatever else applies, say the behind/ahead numbers may be out of date (couldn't reach the server — last known state). Never call the branch "up to date" in that case.

1. **Operation in progress** (`operation` set — merge / rebase / cherry-pick / revert / bisect): explain in one sentence what that means, show the conflicted files if any, and ask whether to continue it together or abort it. Run `--continue` / `--abort` only on their choice.

2. **Behind the central branch** (`behind` > 0) — this is the most important check. Make it impossible to miss:

   > ⚠️🚨 **Your branch is ‹behind› commit(s) behind `‹central.branch›`.** Others have merged work you don't have yet. Working on top of an old base causes conflicts and surprises later.

   Explain the options in plain words and **wait for their decision**:
   - **Update with merge** (safe default): `git merge ‹central.ref›` — adds one merge commit, never rewrites history.
   - **Update with rebase**: `git rebase ‹central.ref›` — cleaner history, but rewrites your commits; only if the branch isn't shared with anyone. If `upstream` exists, warn that a later push would need force — which Guardian never does — so prefer merge.
   - **Continue as-is**, knowingly.

   If they're on the central branch itself, the update is `git pull --ff-only`. If a chosen update hits conflicts, stop and walk them through it; never resolve conflicts silently.

3. **Central branch unclear** (`central.confidence` is `low` or `none`, or `central-ambiguous` in `warnings`): ask which branch new work should branch from — offer `central.candidates` (detected: ‹central.branch›). Once they answer, re-evaluate behind/ahead against that branch (`git rev-list --left-right --count HEAD...origin/‹branch›`, or `HEAD...‹branch›` when there's no remote). If there is a remote, offer to record it for the team in `.platform-guardian.json` (`{"centralBranch": "‹branch›"}`) — that file is committed, so it goes through their next PR.

4. **On the central branch** (`onCentral`): direct work on it isn't allowed. Offer to create a work branch from the up-to-date central branch and ask for a short name (follow the repo's existing branch naming if `git branch -r` shows one, e.g. `feature/…`, `bugfix/…`). Create it only after they confirm: `git switch -c ‹name›`.

5. **Detached HEAD** (`detached`): explain they're not on any branch, so new commits would be easy to lose; offer to create a branch here.

6. **Uncommitted changes** (`dirty`): mention the counts (and up to ~5 file names). Ask whether these are theirs from last time — never stash, discard or commit them now.

7. **Unpushed commits** (`upstream.ahead` > 0): one line, FYI only — the closer handles pushing.

Situations not listed (no remote, `override-not-found`, unborn repo) → mention in one line and move on. If `guards.matrixQa` or `guards.onoQaCommitBlocked` is true, mention once that in this repo the employee runs commits / pushes themselves (an Ono QA plugin blocks Claude from doing it) — the closer will hand them the commands.

### 3. All clear

When nothing needs a decision, a single line is enough: "✅ You're on `‹branch›`, up to date with `‹central.branch›`." (Only when `fetch` is `ok`.)

### 4. Ask what we're doing

> All set. What are we working on — a bug, a feature, tests, a spec? Tell me what we're doing.

If the first message was already a task, skip this question — hand it straight to the router, which confirms once.

If unfinished work was found, offer it first: "Continue *login* (`/implement-task login T3`), or something new?" If its next step is "your step", say what they need to do first (e.g. approve the analysis) — don't offer to run the following command until they've done it.

Then hand over to the `platform-guardian:work-router` skill with their answer — it picks the right Ono plugin command (or resumes the work named in the last session-log entry).
