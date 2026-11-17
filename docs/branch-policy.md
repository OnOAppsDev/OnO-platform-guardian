# Protected branches, the inspect gate, and plugin independence

Status: **implemented in Guardian 0.4.0** (proposed against 0.3.7) · checked against ono-mobile-dev-plugin 0.7.5 (`ee7e6c8`) and ono-project-inspector 0.11.2 (`e07729f`) on 2026-11-16 · no change to the dev plugin or the Inspector.

## TL;DR

I agree with the four problems (points 1–4; point 5 is the test list, covered below). I disagree with parts of how they are framed, and in three places the fix needs to go further than the email asks:

1. **Branch before Inspector.** Don't open the gate to a conversation about branches. That would be enforcement by text alone, which is exactly what the email rules out. The gate itself should show the one command that creates the work branch and should refuse the Inspector until the work branch exists.
2. **Protected branches.** Guardian gets its own write guard: it blocks `Write` / `Edit` / `NotebookEdit` on `main`, `master` and the project's central branch. `git commit` / `git push` on a protected branch changes from an "ask" prompt to **deny**.
3. **Dependency.** Guardian stops relying on the dev plugin. Both guard `main`/`master` on purpose, as defense in depth. Neither one relies on the other.
4. **Inspector on central.** The Inspector is blocked at the **command** level on a protected branch, for both a first inspection and a refresh, because its file-write guard alone can't stop it (see finding F1).

Plus one caveat for everyone: hooks on the developer's machine are guard rails, not a wall. The real guarantee is server-side branch protection on the central branch (see "What only the server can guarantee").

## What I found in the code

**F1 — The Inspector on `main` with the dev plugin installed leaves a half-written inspection.** The Inspector has no branch check of its own. It writes with the `Write` tool (docs, AUDIT.md, CLAUDE.md) **and** with `bun` scripts through `Bash` (`.ono/state.json` via `inspection-state.ts sync`). The dev plugin's hook only catches the `Write`/`Edit` calls, so the `bun` writes land and the docs don't. Guardian then reports the project as `partial`. A file-write guard can't fix this, whoever owns it. The Inspector must not *start* on a protected branch.

**F2 — The gate blocks every plain message, so the opener never runs.** Today a first message in an un-inspected project is blocked, so Claude never sees it, and the session opener's "create a work branch?" offer can't happen at all. The only way through is an Inspector command, which then runs on `main`. This is the deadlock described in point 1 of the email.

**F3 — The gate lets the Inspector run on any branch.** `inspect-gate.sh` lets `/ono-project-inspector:*` through and then opens the session for follow-up messages, whatever branch the developer is on.

**F4 — Guardian has no write guard of its own.** `skills/work-router/SKILL.md:34` relies on the dev plugin's hook, which covers only `main`/`master`. On a `develop`-central project, nothing stops writes on `develop`. Guardian's commit guard asks for permission on every commit and push, but a click lets them through on the central branch too.

**F5 — Guardian alone with no Inspector is a dead end.** Guardian lists the Inspector in `dependencies`, so it is normally installed. If an employee disables it, though, the gate keeps telling them to run a command that doesn't exist. The only way out is the manager sentence.

**F6 — Performance.** The full central-branch detection (`git-status.sh`, no fetch) takes about 0.9 s. That's fine once per prompt, but far too slow before every file write. The write guard must use a cached value (see change B).

## Challenges to the email (where I'd do it differently)

| Email | My position |
|---|---|
| "The gate should allow the actions needed to create the work branch" | **Agree on the goal, not on the means.** If the gate lets plain messages through so Claude can create the branch, every message gets through and the only thing stopping other work is an instruction to Claude. Instead the developer runs one exact command themselves (`! git switch -c <name>`), and the gate accepts that exact command shape and nothing else (change A). Claude is not involved, so there is nothing to bypass. |
| Point 3: the work-branch rule as a dev-plugin precondition | **Too narrow.** Every intent that writes files needs a work branch: the Inspector, spec (`docs/specs/`), matrix QA (`qa/lld/`), the dev plugin. The router rule becomes "any writing intent". |
| Point 2: "enforce, not just text" | **Agree, but be honest about the limit.** A client-side hook catches the tools it sees. A write through `Bash` (`sed -i`, `>`, a `bun` script) gets past the dev plugin's hook and would get past Guardian's write guard too. Locally, the real wall is **deny commit/push on a protected branch**, and the real guarantee is server-side protection. |
| Scenario: "Guardian without the other plugins" | **Mostly theoretical.** Installing Guardian installs them all (`dependencies`). The real case is a *disabled* plugin. Handle it (F5), but don't design around running Guardian on its own. |
| (implicit) where the inspection lands | **Recommend a dedicated branch + its own PR** (e.g. `chore/project-inspection`), not inspection inside a feature PR. The inspection reaches the central branch sooner, and every teammate then gets the existing "central already has it → merge" path instead of re-inspecting. The cost is one extra small PR. Open decision: Yagil / Tom. |

## Who protects what (after the change)

| Protection | Owner | Mechanism | Works without the other plugins? |
|---|---|---|---|
| No work before inspection | Guardian | inspect gate (prompt + slash command) | yes |
| Inspector never starts on a protected branch | Guardian | inspect gate (typed commands) + write guard (Claude starting it through `Skill` / `Agent` / `SlashCommand`) | yes |
| *(optional)* Inspector refuses to write on `main`/`master` by itself | Inspector | its own preflight (**needs Yagil, not proposed for now**) | n/a |
| No file writes on `main` / `master` | dev plugin **and** Guardian | each has its own `PreToolUse` hook | yes, both, on purpose |
| No file writes on the project central branch (`develop`, …) | Guardian | `PreToolUse` write guard | yes |
| No commit / push on a protected branch | Guardian | commit guard: **deny** | yes |
| Commit / push needs the employee's OK | Guardian | commit guard: ask (as today) | yes |
| Secrets never committed | dev plugin + Guardian | each its own | yes |
| Bug-flow / approval gates | dev plugin | its own hooks + scripts | yes, Guardian never relies on them |
| Git flow in QA repos (the ono-plugin-qa QA repo, matrix-qa `qa/`) | the QA plugins | their own guards; the employee reviews and commits | Guardian doesn't block these (see B) |
| Nothing reaches the central branch without a PR | **the git server** | branch protection | the only real guarantee |

"Protected branch", defined once in Guardian: `main`, `master`, and the project's central branch when it's known for sure (`.platform-guardian.json` `centralBranch`, or detection confidence `high`). If the central branch is uncertain, Guardian doesn't block it. The opener asks first, so a wrong guess never blocks a legitimate branch.

## Changes (Guardian only)

**A. Inspect gate (`hooks/inspect-gate.sh`)**
1. **On a protected branch, any inspect status** → `/ono-project-inspector:*` and `/inspect*` are blocked with "create a work branch first", except the read-only `inspect-status`. This covers both a first inspection and a refresh (point 4).
2. **Not inspected + on a protected branch** → the ⛔ banner becomes two numbered steps: ① `! git switch -c chore/project-inspection` (or any name) ② `/ono-project-inspector:inspect`. Once the developer is off the protected branch, the gate behaves as today.
3. **The branch command gets through the gate in either form.** It is not documented whether `!` commands reach `UserPromptSubmit` (the docs only say they run "directly without going through Claude"). So the gate also accepts the exact text `git switch -c <name>` / `git checkout -b <name> [<start>]`: one line, one command, none of `; & | $ \` < > ( ) \`, the name isn't a protected branch, and a start point must be a real commit. On `on-central` the banner's own `git merge <central ref>` is let through the same way. If it arrives as a message, Claude is told to run exactly that command and nothing else. The commit/push guard still covers everything after that. To verify in the live test: which path actually happens.
4. **Inspector disabled or not installed** (read from `installed_plugins.json`, as `bug-report.sh` already does) → the banner gives the install / enable line instead of a command that doesn't exist (F5).

**B. New write guard (`hooks/write-guard.sh`, `PreToolUse` matcher `Write|Edit|MultiEdit|NotebookEdit|Skill|SlashCommand|Agent|Task`; `MultiEdit` is kept only for older Claude Code versions)**
- Deny when the file is **inside the repo** and the current branch is protected. Never blocked: files outside the repo (scratch, `/tmp`), anything under `~/.claude`, git-ignored files, and a brand-new project with no commits yet. The message: create a work branch (`git switch -c <name>`), never "commit here".
- **Claude starting the Inspector** through a tool (`Skill` / `Agent` / `SlashCommand` naming `ono-project-inspector`, except `inspect-status`) is denied on a protected branch too. The gate only sees what the employee types (review finding).
- **QA plugins are not blocked** (review finding): ono-plugin-qa works in its own QA repo and matrix-qa in `qa/`, and the employee commits there by design (matrix-qa even blocks Claude's `git switch -c`). Exempt: the QA repo named in the workspace's `.claude/qa-workspace.json` (or the plugin's own auto-detect: a `*qa*` repo next to another repo), and `qa/` next to `matrix-qa.config.json`. **To confirm with the QA owners.**
- Branch names compare case-insensitively (`Main` is `main` on macOS).
- Fast path: one `git rev-parse`, the branch read from `.git/HEAD`, and the central branch cached per repo by the SessionStart hook (`~/.claude/platform-guardian/.state/central…`). Measured at about 80 ms per write on a work branch (process launches dominate). If there is no cache, it protects `main`/`master` only.
- Fails open on anything unexpected, like every Guardian hook. No `jq`.

**C. Commit guard (`hooks/pre-tool-use.sh`)**
- `git commit` while on a protected branch → **deny** (today: ask).
- `git push` while on a protected branch, or with a refspec whose target is protected (`HEAD:develop`, `origin develop`, `x:heads/main`, `:develop`, `--all`, `--mirror`) → **deny**. Subshells, `if … then`, `env`, and line breaks are read through; a commit or push the guard can't read (`sh -c '…'`) gets the permission prompt.
- Everything else stays as it is (ask for every commit/push, code-only staging).

**D. Skills**
- `work-router` step 3: "work branch required for every intent that writes files; Guardian's write guard enforces it". Remove the reliance on the dev plugin's hook.
- `session-opener`: record `.platform-guardian.json` **after** the work branch exists. Otherwise Guardian's own new guard would block it on the central branch, and the dev plugin's already does on `main`/`master`.

**E. Docs + release**
- `docs/branch-policy.md` (this page), the employee guide, `docs/live-test.md` §5e. The deck is **not** updated yet (open item).
- Version **0.4.0**, not a patch: writes on `develop` are newly blocked, which is a visible behavior change for teams that work on `develop` today (e.g. QA running matrix locally on `develop`).

## Test plan (the 9 scenarios + what the code review added)

Automated (bash, macOS 3.2 + Linux CI) on throwaway repos with `PG_PLUGINS_FILE` simulating installed sets, except rows marked *live*: the tests run Guardian's hooks, not the other plugins.

| # | Scenario | Expected |
|---|---|---|
| 1 | New project, not inspected, on `main` | banner shows ① branch ② inspect; `/ono-project-inspector:inspect` blocked; `inspect-status` allowed |
| 2 | Same, on `develop` (`centralBranch: develop`) | same as 1 |
| 2b | Same, central uncertain (confidence low) | `develop` not treated as protected; `main`/`master` still are |
| 3 | Inspected, refresh recommended, on central → on a work branch | central: Inspector blocked · work branch: allowed, no gate |
| 4 | Guardian + dev plugin, write on `main` (*live* 5e.6) | both deny (Guardian alone is enough) |
| 4b | Guardian + dev plugin, write on `develop` (*live* 5e.7) | Guardian denies (the dev plugin allows) |
| 5 | Guardian + Inspector only | gate + write guard work; Claude starting the Inspector on `main` denied |
| 6 | Guardian alone (Inspector disabled) | banner gives the enable/install line; write guard works |
| 7 | Write on a protected branch: inside the repo / outside it | deny / allow |
| 8 | Branch creation before inspection: `git switch -c x` as a message; `git switch -c develop`; `git switch -c x; rm -rf .` | allowed / blocked / blocked |
| 9 | Commit + push after the work: on a work branch / on central / `push origin HEAD:develop` | ask / deny / deny |
| — | Write guard latency | 10 writes ≤ 3 s in CI (≈ 80 ms each measured locally); a 2 MB write stays fast |
| — | Review findings | every confirmed bypass / false positive from the three review agents has a test |

Live (with a tester, real Claude Code): scenarios 1, 4b, 8 and 9 end to end, plus the `!` question from A3.

## Review (three independent agents) — what changed

- **Bypass review:** 7 confirmed bypasses, all fixed + tested — push through `heads/main`, `--all` / `--mirror`, subshells / `if` / `env` / line breaks, `checkout -`, `Main` vs `main` on macOS, `--repo=`; and in the gate, a branch command with a second line or a free-text start point. 2 false positives fixed: a brand-new project, `~/.claude` inside a home-folder repo. Out of scope (deliberate attacker): a symlink to a tracked file.
- **Correctness / portability review:** all suites green on macOS bash 3.2; mawk-safe by reading. Fixed: `checkout <branch> -- <file>` taken as a branch switch, `--create=X`, settings precedence for a disabled Inspector (user → project → local), reftable repos, a cache-file collision, a slow walk over big Write payloads.
- **Integration review:** fixed: Claude starting the Inspector through a tool, the QA plugins' own repos. Declined, with reason: a `.platform-guardian.json` opt-out for the write guard. The request is to enforce central-branch protection, and a team that truly works on `develop` can say so to Tom / Yagil first. Accepted as known limits: the central-branch cache refreshes on startup / `/clear` (not on resume), and writes through scripts (`Bash`) aren't seen, as stated above.

## What only the server can guarantee

Every client-side hook can be avoided: by a terminal, by `!`, by a `Bash` write, or by disabling a plugin. Guardian and the dev plugin make the right way easy and the wrong way loud. **Branch protection on the git server** (required PR into `develop` / `main`, no direct push) is what actually guarantees it. **Recommendation:** enable it on every Ono app repo's central branch. It's an org-admin action, outside Guardian.

## For Yagil — findings in the other plugins (FYI, no change made)

**Status 2026-11-16 (dev plugin 0.7.6, PR #62):** 1–4 fixed. 5 open (optional).

**Correction 2026-11-17 (dev plugin 0.7.7, PR #63):** the 0.7.6 note "server-side branch protection off" was wrong. We only asked the classic protection API (404); `ono-mobile-dev-plugin` `main` has had a **ruleset** since 2026-07-09 (PR required, 1 approval, no force-push, no deletion). The real gap: 0.7.7's new CI (`Strict suite` on Node 22.18.0 and 24) is **not a required status check**, so a red build can still be merged. Lesson: check `gh api repos/<o>/<r>/rulesets` as well as `…/branches/<b>/protection`.

1. **Bug report 2026-11-15 (Noam): still open in 0.7.5.** `scripts/edit-approval.ts` `writeRecord` writes into `docs/tasks/bugs/` without `mkdirSync(…, { recursive: true })` (the `fs` import at :48 has no `mkdirSync`), so the first bug in a repo fails with `WRITE_FAILED`/`ENOENT`. Secondary: `task-state.ts` ~:1164 refuses `complete` with one shared message. It should name the failing condition (e.g. "accessibility applies but no Tier 1/2 check recorded").
2. **The main-branch hook needs `jq`.** Without it `tool_name` is empty and the hook exits 0, so the protection is silently off. macOS 15+ ships `jq`, so the risk is low, but it fails open without a word.
3. **The main-branch hook blocks by branch, not by path.** On `main` it also blocks writes outside the repo (Claude's memory, scratch files). Low.
4. **Hook matcher:** `MultiEdit` no longer exists in Claude Code (tools reference); `NotebookEdit` isn't covered. Low.
5. **Optional, needs agreement:** an Inspector preflight that refuses to write on `main`/`master` when it runs on its own, matching the dev plugin's standalone stance. Guardian doesn't need it, but it would close F1 for anyone running the Inspector without Guardian.
