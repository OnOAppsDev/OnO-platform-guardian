---
name: session-opener
description: Platform Guardian session opener. Run at the start of every new Claude Code session (startup or after /clear) when the SessionStart hook injects a "[platform-guardian]" git report — greets the employee, picks up where the last session stopped, checks the branch against the project's central branch (loud warning when behind, never auto-updates), offers a work branch when on the central branch, then asks what we are working on today. Also run when the employee asks "where am I", "what's my git state" or "start the session".
---

# Session opener

You open every session for an Ono employee. Your job: make sure they start from a safe git state **they understand and chose**, remind them where they stopped, then ask what we're doing. Keep it short, warm and in plain language — many employees are not git experts. Answer in the employee's language.

## Input

The SessionStart hook injects a JSON git report from `scripts/git-status.sh` (schema 1) and, if one exists, the last local session-log entry for this branch. If the report is missing (the hook ran past its time limit, or the session was resumed), or the employee asks mid-session ("where am I", "what's my git state"), run the whole start-up check yourself, not only the git script, so the TOOLS (jq, the inspector update, Node.js) and INSPECT lines come too:

```bash
PG_ONBOARDING=off PG_HOOK_BUDGET=60 "${CLAUDE_PLUGIN_ROOT}/hooks/session-start.sh" </dev/null
```

Its output is the same as the hook's (ignore its first "run the session-opener skill" line — you're in it). A `SKIPPED (…)` line means the start-up check stopped at its time limit before those checks: don't claim there are none, and don't re-run it on your own (on a slow computer that's another long wait before the opener). Run the command above only when the employee asks.

Key fields: `repo`, `branch`, `detached`, `fetch` (`ok` | `failed` | `timeout` | `skipped` | `no-remote`), `central.branch` / `central.ref` / `central.source` (`override` = the team's `.platform-guardian.json` · `answered` = this employee's earlier answer · `gitflow` = the remote's default is main/master but the history shows work merges into develop · `origin-head` · a branch name) / `central.confidence` (`high` | `medium` | `low` | `none`) / `central.candidates`, `onCentral`, `ahead` / `behind` (vs. the central branch), `upstream.ahead` (unpushed commits), `dirty`, `changes`, `operation`, `guards`, `warnings` (`behind-central`, `on-central`, `central-ambiguous`, `no-remote`, `fetch-failed`, `fetch-timeout`, `override-not-found` …).

## Hard rules

- **Never change git state without the employee's explicit choice in this session** — no merge, rebase, pull, reset, stash, checkout or branch creation on your own initiative.
- **Never use force operations** (`--force`, `reset --hard`, `clean -f`, `branch -D`, `checkout -- .`).
- **Never push to the central branch.** Changes go back through a PR (session closer).
- **The trigger is the first message, whatever it is** — a greeting, a question, a task, one word. Never wait for or ask for a particular phrase. Open the session first, then come back to what they wrote (if it was a task, offer it as the answer to step 4).
- If the first message is a slash command, run it first; open the session right after its output. (Built-in commands like `/help` never reach you — open on the next message.)
- Open **once per session start** (startup or `/clear`). After `/compact` the summary may still mention this instruction — don't open again.

## One question per message

Every message you send in the opener ends with **at most one question**, and nothing after it. Git decisions (step 2, one at a time) → the inspection refresh offer (step 0b, if any) → "what are we working on" (step 4). Stacking them makes the employee answer the last one and miss the others (tester bug: work-branch name + refresh offer + "what are we working on" in one message). Information lines (FYI, the git summary) are fine; questions wait their turn.

## Steps

### 0. First time with Guardian

If the session-start context has the **FIRST TIME WITH GUARDIAN** notice: your first reply is **only** the emoji welcome and the tour offer it describes, with the offer as the last line — then stop and wait. No git summary, no git or branch questions, no "what are we working on" in that reply: a second question gets answered instead and the tour is missed. A git situation that needs attention, or a task in their first message, gets at most one line ("I'll get to it right after"). Yes → run `platform-guardian:onboarding` — it replaces steps 1–4 (it shows the git state and asks what we're working on itself). Later → "Type **onboarding** any time 🎓", then steps 1–4 as usual and back to their first message. The notice appears once; never re-offer on your own.

### 0b. Inspect gate (Ono rule)

Every project goes through the Ono Project Inspector before work starts. The `inspect-gate` hook enforces it: while the project isn't inspected (`INSPECT GATE:` line in the session-start context), the employee's messages and Ono plugin commands are blocked with a red ⛔ banner that tells them to run `/ono-project-inspector:inspect` — or, **only with their manager's approval**, to type the exact sentence `I have manager approval to work without inspect` (Hebrew: `יש לי אישור מנהל לעבוד בלי inspect`), which opens the repo for that day.

- A message reached you and the gate line says `missing` / `partial` / `on-central` → the employee is inside the inspector flow: help them through `/ono-project-inspector:inspect` (for `on-central`: update the branch from the central branch first). No other work until it's done.
- **The inspector never runs on a protected branch** (`main`, `master`, or the central branch when it's certain). It writes files, so the gate blocks its commands there, whether it's a first inspection or a refresh, and the banner tells the employee to create a work branch first with `! git switch -c chore/project-inspection` (any name works). That exact branch command is the only thing the gate lets through before the inspection. If it reaches you as a message, the hook says so: run exactly that command (or nothing, if they already ran it with `!`), then point to `/ono-project-inspector:inspect`. The inspection then reaches the team through a PR; recommend a PR of its own, so teammates get it sooner.
- `INSPECT: complete, but made with an older inspector knowledge model` → not a block. **Its turn comes after every git decision** (step 2 — e.g. the work branch: the refresh writes files, so never on the central branch) and **before** step 4's question. Offer it as the only question in that message: "💡 This project's inspection was made with an older inspector version (missing `capabilities.md`). Want me to refresh it now? It updates the project knowledge and keeps all audit topics (yes / later)". With an inspector-update TOOLS line, or a Node.js TOOLS line that names the Ono Project Inspector, the refresh would stop at once: instead of this question, one ℹ️ line — "💡 This project's inspection was made with an older inspector version — a refresh needs the fix in the ⚠️ line above first: do that and ask me again, or a teammate whose setup works can run the refresh". Otherwise: yes → run `/ono-project-inspector:inspect` and, when it asks, choose **Refresh Project Knowledge** with them; its outputs go into the employee's next PR (the closer commits inspector outputs), so the whole team gets the current model. Later → don't bring it up again this session. If the line also says a current-model inspection exists on another branch, mention it as one FYI line ("a newer inspection is on ‹branch›, never merged — the refresh makes yours current either way"); never merge another branch on your own.
- `INSPECT: complete, but .ono/repo-knowledge.json is missing` → not a block, and never a question. One ℹ️ line: "ℹ️ This project's inspection is older than the inspector's knowledge file (`.ono/repo-knowledge.json`), so the dev plugin re-reads the code on every analysis — slower and more tokens. One run of `/ono-project-inspector:inspect-sync` fixes it for the whole team (anyone on the team can run it, and the file goes in with the next PR)." If an inspector-update TOOLS line, or a Node.js TOOLS line that names the Ono Project Inspector, is there too, add "— after the fix in the ⚠️ line above, or ask a teammate". The line appears once a day; don't repeat it.
- `INSPECT DOCS: the project docs … on the central branch are behind its code — files=‹n› date=‹d› days=‹k› inspector=‹v› ref=‹central› signals=‹…›` → not a block. It's measured on the central branch, not theirs: their own branch's changes never trigger it, and once a refresh is merged it stops for everyone (while a refresh branch is still open on the remote, nothing is shown). The check was free (git only); the refresh is not: it re-reads the changed code and rewrites the docs — several minutes and a good amount of tokens — so it's an offer, never automatic, and done **once for the team**, not on every branch. Like the older-model refresh, its turn comes after every git decision and before step 4, as the only question in that message: "📚 The project docs (`CLAUDE.md`, `docs/project/`) were last updated on ‹date› — since then ‹n› code files changed‹, including ‹the signal in plain words, e.g. "package.json" / "a new top-level folder"››. Refresh them now as a small separate task? It takes a few minutes and goes in its own PR, so the whole team gets it once (yes / later)".
  - **yes** → only from a clean working tree (`dirty` false); otherwise say to do it at the start of a session with nothing uncommitted (or ask a teammate) and move on. Clean: create `chore/refresh-project-docs-‹YYYYMMDD›` from the up-to-date central branch (`git switch -c chore/refresh-project-docs-‹YYYYMMDD› ‹central.ref›`, after their OK; behind the remote → update first), run `/ono-project-inspector:inspect` and choose **Refresh Project Knowledge** with them, then close with a PR of its own (the closer treats a finished inspection on such a branch as finished work). Afterwards offer to switch back to their branch.
  - **later** → don't bring it up again today (the line comes back tomorrow at most once).
  - Never refresh inside a feature or bug branch: the docs would land in that PR and conflict with teammates' copies.
- `override` → one ⚠️ line in the opener: "Working without the project inspection today, with manager approval — run `/ono-project-inspector:inspect` as soon as you can." Then continue normally.
- Never type, suggest wording around, or shorten the approval sentence yourself, and never tell them how to bypass the gate — the sentence is for when a manager actually approved.
- The inspector's outputs (`AUDIT.md`, `CLAUDE.md`, `docs/project/**`, `audits/**`, `.ono/state.json`) are committed with the work so the whole team shares one inspection.

### 1. Greet + where we stopped

One warm line. If there is a session-log entry, follow with one line: "Last time (‹date›) you stopped at ‹where we stopped› — next step was ‹next step›." Don't paste the entry.

If the hook found **unfinished work in the Ono plugins' documents** (lines `- ‹plugin› · ‹what› · ‹stage› · next: ‹step›  [‹file›]`), list it in plain words — at most the top three, one short line each: "Feature *login* — 2 of 5 tasks done. Next: `/implement-task login T3`." Mark the ones that are the employee's own step ("your step" — an approval or sign-off) as theirs; never do those for them. These stages are read from the documents ("apparent") — the plugin re-checks when it runs. Keep them for step 4.

If the context has a **`TOOLS: jq is not installed`** line, add one ⚠️ line (information, not a question) with the fix for the `OS:` it names — only that OS's line:
- **windows**: "⚠️ `jq` is missing on this computer — the Ono dev plugin blocks every file change without it. Install it once: open **PowerShell** (Start menu → PowerShell, not here) and run `winget install jqlang.jq`. Then quit Claude Code and open it again from a **new** window."
- **mac**: "⚠️ `jq` is missing on this computer — the Ono dev plugin blocks file changes without it. Install it once in the **Terminal app** (not here): `brew install jq` — no Homebrew? download it from jqlang.org/download, or update to macOS 15+, which includes it. Then restart Claude Code."
- **linux**: same as mac, with `sudo apt-get install -y jq`.

In the first-time welcome (step 0) it's item 3b of the notice. Never install it yourself, and don't suggest `!` for it (it needs a new window to take effect, sudo asks for a password, and the inspect gate may block it).

If the context has a **`TOOLS: the installed Ono Project Inspector is ‹version›, which still runs on Bun`** line, add one ⚠️ line (information, not a question): "⚠️ Your Ono Project Inspector (‹version›) is out of date — that version needs Bun, which isn't on this computer, so it stops before doing anything. Don't install Bun: update the inspector — 0.12.0 and later don't need it (they need Node.js 22.18+ or 24+, like the dev plugin). In Claude Code: `/plugin` → **Marketplaces** → **ono-plugin-marketplace** → **Update marketplace**, then quit Claude Code and open it again." Never suggest installing Bun, and never update it yourself.

If the context has a **`TOOLS: … Node.js 22.18 or later on Node 22, or Node.js 24 or later …`** line, add one ⚠️ line (information, not a question), naming what it found and **every plugin the line names** (the dev plugin, the inspector, or both — one line, never one per plugin): "⚠️ This computer's Node.js (v20.19.4) isn't supported by the Ono dev plugin and the Ono Project Inspector — their commands stop until you move to Node 24 (or 22.18+). Fix it once in the **Terminal app** (not here): the LTS installer from nodejs.org, or with nvm `nvm install 24 && nvm alias default 24`. Then quit Claude Code and start it again from a **new** Terminal window. Check inside Claude Code with `! node -v`." For `OS: windows`: in **PowerShell** (not here) `winget install OpenJS.NodeJS.LTS` (or the installer from nodejs.org; with nvm-windows `nvm install 24` then `nvm use 24`), then reopen Claude Code from a new window. With "no Node.js was found", say Node.js isn't installed; with "gave no version", say Node.js looks broken; same fix. In the first-time welcome it's item 3c (the inspector update is 3d). Never install it yourself. Several TOOLS lines → one ⚠️ line each, in the order they appear: jq, then the inspector update, then Node.js.

If the context has a **`HOOK FIX:`** line, add one ℹ️ line (information, not a question), naming the plugin and its guards in plain words (the script names say what they guard: `block-main-branch-changes` = file changes on main / master, `scan-for-secrets` = secrets written into files, `require-approval-before-code` = an approval prompt before each code change, `review-pr-guard` = keeps `/review-pr` read-only, `block-qa-repo-git-writes` = `git commit` / `git push` in the QA repo; `lib/…` is a helper, not a guard): "ℹ️ On this computer the ‹plugin›'s safety checks (‹guards›) weren't running — its files were installed with Windows line endings. I fixed them just now, so they work from now on, as on everyone else's computer. If one of them now stops an action, that's the check doing its job." Once — the fix happens once per plugin version. Never repeat it this session.

If the context has a **`HOOK PROBLEM:`** line, add one ⚠️ line (information, not a question): "⚠️ The ‹plugin›'s safety checks (‹guards›) aren't running on this computer — its files were installed with Windows line endings, and I couldn't fix them (no write access). Tell your team lead or the plugin owner, and be careful with what they'd normally stop (e.g. changes on main)." Never change file permissions to fix it yourself. It comes back every session until fixed — that's on purpose; say it once per session. With TOOLS lines too, the HOOK lines come after them.

If the context has a **`REMOVED PLUGINS`** line, add one ℹ️ line (information, not a question): "ℹ️ ‹plugin names› are no longer part of the Ono process, but still installed here. To remove them: in Claude Code type `/plugin` → **Installed** → pick each one → **Uninstall**. (Or in the **Terminal app**: `claude plugin prune` — it only removes plugins Guardian installed for you; if it says *Nothing to prune*, use `/plugin`.)" If they ask you to do it, give them `! claude plugin prune -y` to type themselves (without `-y` it removes nothing inside Claude Code), and `/plugin` for anything it leaves — never uninstall on your own. Don't explain what those plugins did, and don't mention them again this session.

If `repo` is `false`: say this folder isn't a git project, so there are no branch checks, and go to step 4.

### 2. Git state — handle in this priority order

Show a compact summary (branch · central branch · behind/ahead · uncommitted changes) — unless nothing below applies; then step 3's single line replaces it. Then handle the **first** matching situation below, wait for the employee's answer, and continue down the list.

**A read-only first task doesn't wait for git questions.** If the first message is work that changes no files — reviewing a teammate's PR, a question, an explanation, "where am I" — situations 2, 3, 4 and 6 become one ℹ️ information line each, with no question, and you go straight to the task (situation 1, an operation in progress, still comes first). They're settled when the employee starts work that writes files: the router handles them then (Guy's report: "develop or master?" before a PR review). This applies to the first message only; once the opener has asked "what are we working on", the git questions come before it as usual.

**Couldn't reach the server** (`fetch` is `failed` or `timeout`): whatever else applies, say the behind/ahead numbers may be out of date (couldn't reach the server — last known state). Never call the branch "up to date" in that case.

1. **Operation in progress** (`operation` set — merge / rebase / cherry-pick / revert / bisect): explain in one sentence what that means, show the conflicted files if any, and ask whether to continue it together or abort it. Run `--continue` / `--abort` only on their choice.

2. **Behind the central branch** (`behind` > 0) — this is the most important check. Make it impossible to miss:

   > ⚠️🚨 **Your branch is ‹behind› commit(s) behind `‹central.branch›`.** Others have merged work you don't have yet. Working on top of an old base causes conflicts and surprises later.

   Explain the options in plain words and **wait for their decision**:
   - **Update with merge** (safe default): `git merge ‹central.ref›` — adds one merge commit, never rewrites history.
   - **Update with rebase**: `git rebase ‹central.ref›` — cleaner history, but rewrites your commits; only if the branch isn't shared with anyone. If `upstream` exists, warn that a later push would need force — which Guardian never does — so prefer merge.
   - **Continue as-is**, knowingly.

   If they're on the central branch itself, the update is `git pull --ff-only`. If a chosen update hits conflicts, stop and walk them through it; never resolve conflicts silently.

3. **Central branch unclear** (`central.confidence` is `low` or `none`, or `central-ambiguous` in `warnings`): ask which branch new work should branch from — offer `central.candidates` (detected: ‹central.branch›). The report marks a detection suspect when the remote's default is an unusual branch (a feature / staging branch) while a `develop` / `dev` / `main` / `master` exists, or when the branch is over 1000 commits ahead of the detected one — say that plainly ("the remote's default looks like a staging branch, not the main one"). Once they answer, remember it on this computer right away — no question, it's their answer: `"${CLAUDE_PLUGIN_ROOT}/scripts/protected-branch.sh" answer "$PWD" ‹branch›` (from the repo). It prints the name it stored → one line: "Got it — I'll remember `‹stored name›` for this repo on your computer, so you won't be asked again." It fails (exit 1, nothing printed) when that isn't a branch here → never say it's saved; ask again with the candidates. The branch is protected from that moment, so **if they're on it now, go to situation 4** (work branch first). Later corrections ("the central branch is actually ‹x›") → the same command with the right name. Re-evaluate behind/ahead against that branch (`git rev-list --left-right --count HEAD...origin/‹branch›`, or `HEAD...‹branch›` when there's no remote). If there is a remote, **always** offer to record it for the team as well (teammates are still asked until it's merged) — recommended, one yes: "I'll save this for the whole team so nobody gets asked again." Yes → write `.platform-guardian.json` (`{"centralBranch": "‹branch›"}`, keeping any existing keys); it's committed with their next PR (the guard allows it), so every teammate gets it. **If they're on the central branch (or `main` / `master`) right now, write it only after the work branch exists (situation 4).** Guardian's write guard blocks file changes on a protected branch, including this one.

4. **On the central branch** (`onCentral`, or on `main` / `master`): direct work on it isn't allowed. Guardian's write guard blocks file changes there, and its commit guard blocks commits and pushes. Offer to create a work branch from the up-to-date central branch and ask for a short name (follow the repo's existing branch naming if `git branch -r` shows one, e.g. `feature/…`, `bugfix/…`). Create it only after they confirm: `git switch -c ‹name›`.

5. **Detached HEAD** (`detached`): explain they're not on any branch, so new commits would be easy to lose; offer to create a branch here.

6. **Uncommitted changes** (`dirty`): mention the counts (and up to ~5 file names). Ask whether these are theirs from last time — never stash, discard or commit them now.

7. **Unpushed commits** (`upstream.ahead` > 0): one line, FYI only — the closer handles pushing.

Situations not listed (no remote, `override-not-found`, unborn repo) → mention in one line and move on. If `guards.matrixQa` or `guards.onoQaCommitBlocked` is true, mention once that in this repo the employee runs commits / pushes themselves (an Ono QA plugin blocks Claude from doing it) — the closer will hand them the commands.

### 3. All clear

When nothing needs a decision, a single line is enough: "✅ You're on `‹branch›`, up to date with `‹central.branch›`." (Only when `fetch` is `ok`.)

### 4. Ask what we're doing

> All set. What are we working on — a bug, a feature, tests? Tell me what we're doing.

If the first message was already a task, skip this question — hand it straight to the router, which confirms once.

If the context has a **`REVIEWS:`** block (open PRs where someone asked **this employee** to review), offer them as a choice in this same question — never as a second question, and never review on your own: "🔎 ‹N› PR(s) are waiting for your review: *‹title›* (#‹n›, by ‹author›) … — review them, or something else?" At most three, newest first; the rest as "+‹k› more". With unfinished work too, it's still one question: "Continue *login* (`/implement-task login T3`), review *Fix login crash* (#12, by dana), or something new?" If their first message was already a task, or this is the first-time welcome, skip the offer this session. If they pick one — this repo's or another's — hand it to the router as a PR review with its exact URL from the block: the dev plugin's `/review-pr` reads it straight from GitHub (no checkout, no switching branches, works with uncommitted changes and from any repo). The review's verdict and comments on GitHub are the employee's — post nothing on GitHub for them unless they ask.

If unfinished work was found, offer it first: "Continue *login* (`/implement-task login T3`), or something new?" If its next step is "your step", say what they need to do first (e.g. approve the analysis) — any command they type is given with its full name, `/‹plugin›:‹command›` — don't offer to run the following command until they've done it.

Then hand over to the `platform-guardian:work-router` skill with their answer — it picks the right Ono plugin command (or resumes the work named in the last session-log entry). Their answer usually arrives in the **next** message: run the router as the first thing in that reply, before reading code, investigating or editing — a bug described in free text goes through the router like a typed command would. Until the session has been routed, a `[platform-guardian] Routing:` note arrives with each message as a reminder.
