---
name: session-closer
description: Platform Guardian session closer. Run when the employee wants to stop or wrap up ("I'm done", "that's it for today", "close the session", "bye", "thanks, that's all" — in any language), when they accept a close-out suggestion from the "[platform-guardian]" session-length signal, or after a plugin stage completes and they agree to stop. Saves the work safely without forcing git steps — a commit only when code changed (optional while the work is in progress), and the PR-readiness check (the dev plugin's review + pre-PR), push and PR only when the bug or feature is finished (never a direct push to the central branch) — writes the local session-log entry, gives a plain-language summary and tells them to /clear.
---

# Session closer

You close the session so nothing is lost and the next session can pick up exactly here. Plain language, short steps, answer in the employee's language. Every git action that changes anything happens **only after the employee confirms it**.

**Closing a session is not finishing the work.** Most closes happen in the middle of a bug or feature: uncommitted code is safe on the employee's computer, and the next session picks it up. So the closer never pushes the employee through commit → PR:
- **No code changed** (only notes, logs, plugin working files) → no commit, no question.
- **Code changed, work still in progress** → one optional question: a checkpoint commit. No push, no readiness check, no PR.
- **The bug or feature is finished** → the full path: commit, PR-readiness check, push, PR.

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

- **Finished** when the employee said so ("the bug is fixed", "done with the feature", "open a PR", "ready for review"), or the Ono flow for this branch reached its end this session — the internal review (`/review-code --bug` / `--feature`) and the pre-PR (`/ono-mobile-dev-plugin:pre-pr`) were done, or the QA notes were created (`/create-dev-qa-notes`), or a project inspection was completed **on a branch that holds nothing else** (e.g. `chore/project-inspection`, `chore/refresh-project-docs` — its outputs go in a PR of their own). An inspection finished on a feature branch doesn't make the feature finished: ask about the feature, not the inspection. When the flow's end was reached but the employee didn't say it's finished, ask once, naming exactly what finished: "Looks like ‹bug YEA-12 / feature login› is finished — open the PR now? (yes / not yet)". **not yet** → in progress.
- **In progress** in every other case — including a close because the session got long.

### 2. Commit hygiene — code, plus the documents the PR needs

**Ono rule, every flow (bugs, features, reviews, QA, inspections):** a commit holds the code change. Documents, data and working files stay **out** — not deleted, not `.gitignore`d, just not committed — unless the employee explicitly asks for a file or the project lists it in `.platform-guardian.json` `"commitPaths"`. Two kinds of documents go **in** with the code: the inspector's outputs, and (dev plugin 0.8.0+) the planning and review documents its PR-readiness check requires.

Go through `changes.files` (and `git status --porcelain` if the list is truncated) and sort every path:

- **✅ Will commit**
  - modified tracked files — mention anything that looks accidental (debug code, local config);
  - new **source code** and the config files that come with it (`package.json`, `Contents.json`, CI workflows …);
  - new files on the project's `"commitPaths"` list;
  - the dev plugin's **planning and review documents** for this work — the PR must carry them (its readiness check blocks without them): Feature Analysis, Detailed Design, Task Breakdown, Dev Plan (any `.md` with `doc_schema_version` + `feature:` at the top, `*-DD.md`) and `docs/reviews/‹feature›/review.md`; for a bug `docs/bugs/‹key›/bug-report.json`, `bug-work-plan.md`, `review-c‹n›.md`; the QA handoff (`docs/qa/*-qa-handoff.md`) when there is one (`requiredInPr` in `routing/committed-artifacts.json`).
- **⏸️ Stays out** (default for everything else that's new): `.md`, `.json`, `.yaml`, `.txt`, `.log`, `.html` … — notes, drafts, tool output, and the plugins' working files (task state `docs/tasks/**`, other files under `docs/bugs/`, atomic-write `*.tmp` — `routing/committed-artifacts.json` lists where they land). They stay on disk for the next session.
- **⛔ Never**: anything on a `neverCommit` list (`.env`, keys, `*.bak` …) — point it out.

**Nothing under ✅** (only notes, logs, plugin working files, tool output changed — or a clean tree) → there is nothing new to commit. Say it in one line — "Nothing to commit: only ‹notes / logs› changed, and they stay on your computer." — and don't ask about a commit. Then:
- **in progress** → no PR, no push question; go to step 5b;
- **finished** and the branch has commits ahead of the central branch (e.g. yesterday's checkpoint commits) with no PR yet → step 4b (readiness check), then step 5;
- **finished** and a PR already exists → give its link; go to step 5b.

**Code under ✅, work in progress** → ask one optional question, with the reassurance first: "Your code changes stay on your computer either way. Save them as a checkpoint commit on `‹branch›`? (yes / no)". **no** → nothing is committed; go to step 5b. **yes** → show the list below, then steps 3–4 (branch, commit). Then go to step 5b — no readiness check, no push, no PR while the work is in progress. One FYI line is enough: "The PR comes when the bug/feature is finished — just say **open PR** then."

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

### 4b. PR-readiness check (before the push — finished work only)

The dev plugin owns the internal review and the pre-PR check (`/ono-mobile-dev-plugin:review-code`, `/ono-mobile-dev-plugin:pre-pr`, 0.8.0+). Guardian runs neither itself — it asks the plugin whether the branch is ready, and acts on the answer. Skip this step when the work is in progress, the branch has no commits ahead of the central branch, or it's a QA repo (`guards.matrixQa` / `guards.onoQaCommitBlocked`).

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/dev-plugin.sh" readiness --base "‹central branch›"
```

Read-only; one JSON object (the plugin's `ono-pr-readiness` contract v1, or Guardian's own `{"guardian": …}`). Act on it:

| Result | Do |
|---|---|
| `"guardian":"dev-plugin-not-installed"` | Not an Ono-managed repo: no pre-PR is required and none is run. Step 5. |
| `"guardian":"dev-plugin-too-old"` | "Your dev plugin is older than 0.8.0 — update it: `/plugin` → **Installed** → `ono-mobile-dev-plugin` → update, then `/reload-plugins`, and close again." |
| `"guardian":"node-unsupported"` | Show `preflight.message` **verbatim** (which Node.js Claude Code uses and what to install), then "close again after the update". |
| `"guardian":"node-missing"` / `"error"`, `status: error`, or `compatible: false` | Say plainly what's wrong: Node.js missing (the TOOLS line has the install command), `blockers[0].message`, or which plugin is out of date (`supported_versions`). |
| `"guardian":"not-a-repo"` | Shouldn't happen after step 1 — skip the check, step 5b. |

**When the check can't answer** (too old, Node.js, error or incompatible — the rows above): never call the branch ready and never run a pre-PR of Guardian's own. The default is to stop before the push: "The PR waits until the check can run — your commit is saved." Only if the employee explicitly says to go ahead without it: push, open the PR with `--fill` (no Ono description), and write `readiness: not checked (‹reason›)` in the session log.

| Result | Do |
|---|---|
| `AMBIGUOUS_WORK` in `blockers` | Ask which work this PR is for (from the message / `candidates`), then run again with `--work ‹bug:KEY / feature:name›`. |
| `managed: false` (`NO_ONO_WORK`) | Not blocked. One line: "This branch has no Ono bug or feature behind it — next time, start new work through the Ono flow." Step 5. |
| `managed: true`, `ready_for_pr: false` | **No push, no PR yet.** Show each `blockers[].message` in plain words. `REQUIRED_DOCS_NOT_COMMITTED` → stage exactly the listed paths (`documents.not_committed`, `blockers[].paths`) and commit them (step 4; if the guard holds one back, `PG_INCLUDE_FILES=1 git add ‹path›` — tell the employee the PR check requires it), then run the check again. `REQUIRED_DOCS_MISSING`: a document whose `documents.required[].status` is `ignored` is in `.gitignore` — never `git add -f` it; tell the employee which file and that the PR can't carry it until the ignore rule changes (their decision, in its own PR); a truly missing one → the blocker's `next_command` recreates it. Other blockers → offer `next_command.display` ("Next: `/ono-mobile-dev-plugin:pre-pr bug:YEA-12` — run it? (yes / not now)"); on **yes** start it through the Skill tool (never a human-only step — then give the command to type), and run the check again when it finishes. **not now** → in progress; step 5b. |
| `managed: true`, `ready_for_pr: true` | Step 5, with `pr_metadata`. Show the `warnings` in one or two lines (Major findings, UI not verified, reviewed code left uncommitted). |

**Explaining the pre-PR.** Many employees meet it for the first time when it blocks here. Before you offer `/pre-pr`, say in their language: "🔍 **Before the PR — a quick safety check.** The dev plugin looks at the code you changed and what uses it, and opens a one-page PDF of what to test in the app: 🔴 must test · 🟠 should test · ⚠️ watch out. The PDF is only for you — not in the project or the PR." When it's done, or the check reports `pre_pr.status: fresh`: "✅ Checklist: ‹must› 🔴 · ‹should› 🟠 (`pre_pr.pdf_path`). Test the 🔴 items, then type **push** — or **push now** if you already did." Their answer is the go-ahead for step 5's question.

Record it for the session log: `pre-PR: ‹must› 🔴 / ‹should› 🟠` from `pre_pr.counts`, or `not run` / `not required (no dev plugin)`.

### 5. Push + PR (finished work only)

Work in progress → skip this step entirely. Their commits stay on this computer until the work is finished; if they ask to push as a backup, push the work branch only (no PR).

- **Ask first, in one question** — the OK in step 2 covered the commit, not sharing it: "Push `‹branch›` and open a PR to `‹central›`? Reviewers? (or stop here — it's committed locally)". Wait for the answer.
- Push the work branch: `git push -u origin ‹branch›`. Rejected because the remote moved → explain, offer `git pull --no-rebase` (merge) and retry; never force.
- PR: check for an existing one first (`gh pr view --json url,state 2>/dev/null`). If none, use the target branch and reviewers from that answer (target default: the central branch from the report).
  - **Ready Ono work** (step 4b said `managed: true`, `ready_for_pr: true`): let the helper write the title and description exactly — never copy them out of the JSON by hand:
    ```bash
    d="$(mktemp -d)"; "${CLAUDE_PLUGIN_ROOT}/scripts/dev-plugin.sh" pr-body "$d" --base "‹target›"
    ```
    It prints `{"guardian":"pr-body",…}` → `gh pr create --base ‹target› --title "$(cat "$d/title.txt")" --body-file "$d/body.md"` (add `--reviewer` if given). Anything else (the code changed since step 4b) → back to step 4b with that answer. Don't edit the description — its `### Ono references (v1)` section is read back by `/review-pr`.
  - Otherwise: `gh pr create --base ‹target› --fill` (add `--reviewer` if given).
  - Bitbucket, or `gh` not installed / not logged in: give the compare link from the push output; for ready Ono work, run the same `pr-body` and show `body.md`'s content in a fenced block for them to paste.
- The employee may choose to stop before pushing (e.g. work not ready to share) — fine; record it in the log.

### 5b. Tool bug during the session?

If something in Guardian, an Ono plugin or Claude Code misbehaved this session and no bug report was written yet, offer it once before the log: "🐞 Earlier ‹what broke›. Want a bug report for Tom first? (type **report**)" — yes → `platform-guardian:report-bug`, then continue here.

### 6. Write the session-log entry (local, never in git)

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/session-log.sh" append <<'EOF'
- **What we did:** ‹1–2 short sentences›
- **Where we stopped:** ‹the exact point, e.g. "validation done, API call not started"›
- **Next step:** ‹the first thing to do next session›
- **Git:** ‹branch› · ‹in progress: "not committed" / "checkpoint commit" — or finished: pushed + PR link› · pre-PR: ‹N 🔴 / M 🟠 (from the readiness check), "not required", or "not yet — work in progress"›
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
