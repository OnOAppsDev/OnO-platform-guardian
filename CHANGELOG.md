# Changelog

## [0.7.5] — 2026-11-25

**Other Ono plugins installed with Windows line endings: Guardian fixes them at session start, so their guards run** (Ekaterina's count on a real Windows machine, Session 22).

- **What was wrong.** Ekaterina's installed ono-mobile-dev-plugin 0.9.0 and ono-plugin-qa 0.11.0 had CRLF on every line of every hook script. It's the same `bash\r` shebang Guardian had until 0.7.4: Claude Code can't start the hook (`env: bash\r: No such file or directory`, exit 127) and treats that as a non-blocking error. On that computer the dev plugin's main-branch guard, secrets scan, approval-before-code prompt and `/review-pr` read-only guard, and the QA plugin's git-write guard, blocked nothing. A comment in scan-for-secrets.sh (lines 9–11) says it too: any non-zero exit other than 2 is a non-blocking error that lets the write through.
- **New `scripts/hook-eol.sh check|fix`.** For every ono-plugin-marketplace install except Guardian, and only inside Claude Code's plugin cache (`…/plugins/cache/…`; a marketplace added from a local folder is someone's working copy), it looks at `hooks/*.sh`, `hooks/*/*.sh` and `scripts/*.sh` (never `*.test.sh`, never a symlink). It finds the ones with any CR (counted with `tr`, since Git Bash's `grep` can't see CR; a CRLF body behind an LF shebang breaks bash too) and removes the CRs. The fixed file replaces the old one by rename: atomic, so two sessions starting at once, a hook running right now or a kill halfway never leave a half-written script. The executable bit is kept. Partly fixed → one `fixed` and one `failed` line, each naming only its own files. On `autocrlf=true` clones of the real plugins, the fixed files are byte-for-byte the plugins' committed files, and the hook goes from exit 127 to running.
- **The session-start hook runs it before anything else can use the hooks** and says it once: a `HOOK FIX:` line, which the opener turns into one ℹ️ line naming the plugin and its guards in plain words. It's also item 3e of the first-time welcome. No write access → `HOOK PROBLEM:` and one ⚠️ line (tell the team lead / plugin owner). It sits inside the time budget (named in `SKIPPED` on a slow computer). `PG_HOOK_EOL=off` turns it off.
- **Not a replacement for the plugins' own fix.** Each new plugin version is a fresh checkout, so Guardian fixes it again until the plugin ships `.gitattributes` (`eol=lf`), which has been asked of Yagil (backlog A6). The inspector already has it (0.13.0).
- New `tests/hook-eol.test.sh` (44 checks): one-line and pretty-printed lists; Guardian, other marketplaces, `*.test.sh`, non-scripts, symlinks and installs outside the cache never touched; CRLF body behind an LF shebang; executable bit kept; byte-for-byte original; the fixed hook blocks with exit 2; read-only → `failed`, file untouched; part fixed / part failed; six fixes running at once leave every script whole; session-start line, said once, welcome item, off switch, time budget. Seven mutations caught (including the in-place rewrite the review flagged, caught by the concurrency check 3 of 3 runs).
- Independent review: 1 must-fix (in-place rewrite could empty a hook when two sessions start together → rename), 3 should-fix (cache-only + no symlinks, whole-file CR count, separate fixed / failed lines + tests) — all fixed. Adds about 0.16 s to session start on macOS with two Ono plugins installed.

## [0.7.4] — 2026-11-25

**Windows line endings: Guardian installs and reads correctly with `core.autocrlf=true`, and routes match Inspector 0.13.0** (Ekaterina's CRLF ticket on the inspector led to two Guardian bugs).

- **The plugin's files are always installed with LF** (new `.gitattributes`, the same rule the inspector has). Claude Code installs plugins with Git, and Git for Windows defaults to `core.autocrlf=true`. Until now an install on such a computer got CRLF hook scripts: the shebang reads `bash\r` (`env: bash\r: No such file or directory`), the hook never starts, and the session-start report never arrived. Reproduced with an `autocrlf=true` clone of 0.7.3; not yet confirmed on a Windows machine. This is a likely cause of the missing opener in Ekaterina's report (0.7.1), next to the hook timeout fixed there.
  - **An already-broken install is fixed only by updating to 0.7.4** (each version is a fresh checkout, so the old CRLF files are not carried over). Its opener can't run, so Guardian can't ask for the update itself: tell Windows users directly (`/plugin` → **Marketplaces** → **ono-plugin-marketplace** → **Update marketplace**, then restart).
  - New `tests/line-endings.test.sh`: every tracked text file resolves to `eol=lf`, and the start hook runs from an `autocrlf=true` clone.
- **"Where you stopped" reads CRLF documents.** In a Windows checkout every dev-plugin planning doc, bug plan, QA test plan and `AUDIT.md` has CRLF endings, and `resume-state.sh` read none of them (42 of 60 checks failed on CRLF copies). Every file parser now drops the `\r` (four of them needed it; the other two are line-start or mid-row matches and got it for consistency). The resume suite runs a second time with CRLF documents.
- **`routes.json` re-verified against Inspector 0.13.0** (closes the drift issue #47). New `/inspect-recheck <topic>` listed as an inspector alternative (re-verifies one approved topic's findings whose files changed; never approves). The new document header line sits below the H1, so Guardian's `AUDIT.md` detection is unchanged. A Hebrew folder name in the drift check is now tested.
- **`routes.json` re-verified against dev plugin 0.9.0** (single-target bug routing, non-ASCII paths). `/analyze-bug`, `pr-readiness.ts` (`ono-pr-readiness` v1) and the bug work plan's frontmatter are unchanged, so Guardian's routing and resume lines stay as they are.
- **Not adopted yet: the inspector's new `freshness` command.** It measures the checked-out branch, so on a feature branch any source change gives `REFRESH_RECOMMENDED`; Guardian measures the central branch on purpose (one refresh PR for the team, Session 17). On a CRLF checkout it also reports fresh knowledge as `REFRESH_RECOMMENDED` (its Markdown heading parser misses `\r` lines — reproduced). Guardian's git-only drift check is unaffected by line endings. Asked the inspector for a `--ref` option and the CRLF fix; Guardian switches once both ship.

## [0.7.3] — 2026-11-24

**Inspector 0.12.0 runs on Node.js, not Bun: Guardian follows** (Yagil's release for Ekaterina's `BUN NOT FOUND` ticket, YSV-404, and his five rules).

- **No more Bun warnings for Inspector 0.12.0+.** Guardian reads the installed inspector from `installed_plugins.json` (new `scripts/ono-plugin.sh inspector-runtime`). Its own `scripts/node-preflight.mjs` is the proof of 0.12.0+.
- **Older inspector without Bun → "update the inspector", never "install Bun".** This applies to the session-start TOOLS line, the first-time welcome (new item 3d) and the inspect gate's banner. All three give `/plugin` → **Marketplaces** → **ono-plugin-marketplace** → **Update marketplace**, then a restart. They also mention that 0.12.0+ needs Node.js 22.18+ / 24+. The Bun install commands are gone. An old inspector with Bun present gets no line.
- **Node.js is checked with the inspector's own preflight** when 0.12.0+ is installed (new `scripts/node-check.sh`):
  - Exit 0 with JSON → supported.
  - Exit 1 with JSON → unsupported, with its version and message.
  - Anything else (crash, no JSON, exit 0 with `"supported":false`, a hang past 3 s) → never treated as supported.
  - Without the inspector it's `node -v` against the same rule, as before (2 s watchdog).
- **One Node.js line, not two.** The dev plugin and the inspector share the version rule, so there is one TOOLS line naming whichever of them is installed ("The Ono dev plugin (0.7.7+) and the Ono Project Inspector (0.12.0+) need …").
- **No inspector runtime line when the inspector is not installed here**, at session start and in the gate. That covers:
  - not installed at all;
  - turned off in user / project / local settings;
  - installed only for another project;
  - version unknown (the inspector's own preflight explains when it runs).
- **Gate banner with 0.12.0+ and a bad Node.js:** "First fix Node.js", with the preflight's own message verbatim, plus this OS's install command for Node.js 24 or later (LTS). No Node.js at all → "First install Node.js 24 or later".
- **The refresh offer is held back only when the inspector itself can't run** (an update line, or a Node line that names the inspector). A Node line about the dev plugin alone no longer hides it.
- `dev-plugin.sh` finds its plugin through the same `ono-plugin.sh`, with no behavior change. Both hooks now honor `CLAUDE_CONFIG_DIR` for the plugins list.
- `routes.json` re-verified against inspector 0.12.0. No command or file format Guardian reads changed.
- **Startup cost:** no extra node process.
  - macOS: about +0.03 s (0.97 → 1.00 s with both plugins).
  - Windows Git Bash: expect a few hundred ms more, from two short helper scripts. The git root is looked up only when the list has project-scoped entries.
- **Independent review:** 0 must-fix, 6 should-fix and 9 nits.
  - Fixed: all should-fix items and 8 of the 9 nits.
  - Not changed: one nit asked whether the "Update marketplace" path really updates installed plugins. The Claude Code docs say it does.
  - Also fixed: a bug found while fixing those, where the combined Node line named the dev plugin twice.
  - Checks: 6 mutations, all caught.

## [0.7.2] — 2026-11-24

**The central branch is no longer asked every session** (Guy, `yes_plus_mobile_android`: "develop or master?" at the start of every session, even before a read-only PR review).

- **`develop` beside `master` decided from history.** When the remote's default is `main`/`master` and a `develop`/`dev` exists, `git-status.sh` checks whether master has any commit of its own **other than merge commits**:
  - **No, and the two differ → `develop`**, confidence high, `source: gitflow`. Release merges (develop or a release branch merged into master) don't count as master's own work, so a release doesn't flip it.
    - Guy's repo: 41 commits ahead, 0 behind.
    - `yestvos`: 3588 ahead; master's last commit is from 2021.
  - **Anything else → still unsure, the opener asks.** That covers master having real commits of its own (a stale develop, or a fresh hotfix, which look the same) and identical branches. The rule never picks master with confidence.
- **Behavior change: in these repos `develop` is now protected.** Guardian used to guess `master`, so `develop` counted as a plain work branch. Now the write guard and commit guard block file changes and commits directly on `develop`, and the opener offers a work branch, as on any central branch.
- **The employee's answer is remembered on their computer:**
  - `protected-branch.sh answer` stores it outside the repo, per repo folder. It accepts `origin/develop` for `develop`, refuses a name that isn't a branch there (so the opener never says "saved" when it wasn't), and protects the branch right away.
  - `git-status.sh` reads it right after the team's `.platform-guardian.json` (`source: answered`, high, never second-guessed as suspect).
  - So it's asked once per employee per repo folder. A separate git worktree is asked once too.
  - The employee can correct it any time ("the central branch is actually …").
  - Offering to save it for the whole team in `.platform-guardian.json` is unchanged.
- **No git questions before a read-only first task.** When the first message changes no files (reviewing a teammate's PR, a question, an explanation):
  - Behind-central, central-unclear, on-central and uncommitted changes become ℹ️ lines, and the task starts right away.
  - Before an intent that writes files, the router settles them in the opener's order.
- Not done: reading the central branch from the project's `CLAUDE.md` (free text, fragile).
- Independent review: 2 must-fix (a release merge flipped the verdict to master; a mistyped answer replaced a good one and was then ignored) + 6 should-fix, all fixed. Startup cost: the answer is read directly (no extra process); the history rule adds at most 2 `git` calls, only in a repo with both `develop` and `master`.
- The same day's report on `/analyze-bug` asking for the platform on every bug is the dev plugin's design (`commands/analyze-bug.md` step 5). It went to its owner.

## [0.7.1] — 2026-11-24

**Windows: the Bun warning was lost along with the whole opener** (ticket from Ekaterina, `YesPlusSmartTV`, Windows 11. The inspector stopped with `BUN NOT FOUND`, and Guardian had said nothing at session start).

- **Most likely cause: the start-up check ran past its 20 s limit**, and Claude Code then drops all of its output (git report, TOOLS lines, INSPECT lines). On a repo with an older-model inspection, Guardian looks for a newer inspection on the other branches, and that took up to 3 `git` calls per remote branch (≤ 200). Process starts are slow in Git Bash, so that alone could take tens of seconds. Now it's **one** `git cat-file --batch-check` call: 4.4 s → 0.4 s on a 132-branch repo (whole hook 7.1 s → 2.2 s on macOS). Same result.
- **Time budget inside the start-up check** (`PG_HOOK_BUDGET`, default 12 s). Past it, the optional checks are skipped: the branch search, project-docs freshness, PRs waiting for review, and unfinished-work list. A `SKIPPED (…)` line names them, so the opener never claims there are none (and doesn't re-run them unless the employee asks). The core is not budgeted (git report, inspect status, TOOLS lines), but it got lighter: `inspect-status.sh check` takes the central ref from the git report instead of running `git-status.sh` a second time.
- **The opener's fallback runs the full start-up check**, not only `git-status.sh`, when the report is missing. The Bun / Node.js / jq and INSPECT lines now come with it.
- **One Windows Bun command, the inspector's own:** `powershell -c "irm bun.sh/install.ps1 | iex"`, which installs in the user's folder with no admin (was `winget install Oven-sh.Bun`). Used in the opener and the inspect-gate banner.
- **No permission to install software:** the Bun line adds "ask IT, or a teammate who has Bun can run the inspector command". With Bun missing, the older-model refresh is no longer offered as "run it now" (it would stop at once). It's one ℹ️ line pointing to Bun or a teammate.
- Not changed (by choice): no extra Bun banner in the inspect gate for `refresh-recommended`. That repo isn't blocked, the start-up line covers it, and the inspector's own check stops cleanly before writing anything. Running the inspector on Node.js instead of Bun is the inspector's decision (backlog A2).

## [0.7.0] — 2026-11-23

**Works with ono-mobile-dev-plugin 0.8.0** (Yagil's answer to the 2026-11-22 handoff, A1 / A3 / A5 and the dev-plugin half of A2), following its `docs/guardian-integration.md`.

- **Pre-PR belongs to the dev plugin now.** Guardian's own `pre-pr` skill is removed, with no fallback. "Ready for PR", "what could I have broken" and similar requests go to `/ono-mobile-dev-plugin:pre-pr bug:‹key› | feature:‹name› --base ‹central›`. It refuses until the internal review is done and says what comes first. In a repo without the dev plugin, no pre-PR is required and none is run.
- **The closer asks the dev plugin whether the PR is ready.** New `scripts/dev-plugin.sh readiness` runs the plugin's read-only `ono-pr-readiness` contract v1 (`pr-readiness.ts check --contract 1 --base ‹central›`). It finds the plugin through `installed_plugins.json`: this project's entry first, then the user-wide one, from any marketplace key, with Windows paths unescaped. The plugin's own Node.js check runs first, and its message is passed on word for word. Before pushing finished work:
  - **Not ready:** no push and no PR. The closer shows each blocker in plain words and offers the plugin's `next_command` (e.g. the pre-PR), then runs the check again.
  - **Ready:** the PR is opened with the plugin's generated title and description. `dev-plugin.sh pr-body ‹dir›` writes them exactly (outside the repo, so nothing is hand-copied out of JSON), then `gh pr create --title "$(cat …)" --body-file …`. On Bitbucket, or without `gh`, the description is shown for pasting.
  - **No Ono work on the branch:** not blocked; one line suggests starting new work through the Ono flow.
  - **Plugin older than 0.8.0, Node.js missing or unsupported, or a contract mismatch:** never reported as "ready", and never replaced by a pre-PR of Guardian's own. The PR waits; only on the employee's explicit go-ahead is it opened with `--fill`, logged as `readiness: not checked`.
  - **A required document that's git-ignored:** never force-added. The employee decides about the ignore rule.

  The session log's pre-PR line comes from the check's counts.
- **The planning and review documents go into the PR** (agreed in the integration: the readiness check blocks a PR without them). New `requiredInPr` in `routing/committed-artifacts.json`:
  - bug: `bug-report.json`, `bug-work-plan.md`, `review-c‹n›.md`
  - feature: `docs/reviews/‹feature›/review.md`
  - `*-DD.md`, and the QA handoff
  - any `.md` with `doc_schema_version` + `feature:` at the top (Feature Analysis, DD, Task Breakdown, Dev Plan)

  The commit guard now lets these in with the code, also in a subfolder project. Task state, other bug files and `*.tmp` files still stay out. Unstamped legacy documents the check lists are staged by name, and the employee confirms them.
- **A teammate's PR → `/ono-mobile-dev-plugin:review-pr ‹exact URL›`.** It's read-only and pinned to one revision. No checkout and no clean tree are needed, it works from any repo, and Guardian never passes credentials. This replaces 0.6.0's `gh pr checkout` → `/review-code` → switch back. The opener's 🔎 PRs (this repo's and other repos') go straight to it. Before offering it, the router checks the plugin has it (`dev-plugin.sh has-review-pr`); if not, it asks the employee to update the plugin. `/review-code` is only for the employee's own changes.
- **Routes re-verified against dev plugin 0.8.0:**
  - the feature pipeline gains `/review-code --feature` and `/pre-pr feature:`
  - the bug pipeline gains `/pre-pr bug:` after the review
  - new `review-pr` and `pre-pr` intents
  - feature commands' Continue offers are followed like the bug flow's
  - "where was I" shows "reviewed → `/pre-pr` then QA notes" and "all tasks done → `/review-code --feature`"; older dev plugins keep the old lines
  - for a feature the employee picks, the router asks the plugin's `feature-flow.ts status`, which also sees a stale review. The fast session-start lines (no Node) stay a hint.
- **No jq warning with dev plugin 0.8.0+.** Its hooks now fall back to Node.js, which has its own TOOLS line. The jq line stays for 0.7.6–0.7.7 (and unknown versions).
- The routing notes' "Ono commands come first" line names `/review-pr` for a teammate's PR and `/ono-mobile-dev-plugin:pre-pr`. Guardian's removed pre-PR skill no longer counts as "routed".
- Still waiting on the inspector (unchanged at 0.11.3): version / date lines on its documents, audit re-check and freshness fields (A4), and the Windows `winget` line for Bun (A2). Guardian's Bun line and once-a-day manifest line stay.

## [0.6.1] — 2026-11-22

Three bug reports from one session (Guy, `yestv_aos`).

- **Ono commands come first** ("Generic review skills offered as equals"). Asked which skill had done a review, Claude listed `android-pr-review`, `/review-code` and the built-in `code-review` as equal choices. Both `[platform-guardian] Routing:` notes now end with one line when the dev plugin is installed (unknown plugins list → assumed installed):
  - Where an Ono command does the job (code review → `/ono-mobile-dev-plugin:review-code`, security review → `review-security`, a bug in the app → `analyze-bug`, pre-PR → `platform-guardian:pre-pr`), it starts through the router or as the running Ono step's next command.
  - Skills from outside the Ono plugins with the same job (`code-review`, `security-review`, `*-pr-review` …) are not offered as equal options. The dev plugin's own review skills aren't affected.
  - Asked which tool to use, Claude names the Ono command. Asked which one ran, it answers honestly: if it wasn't the Ono command, it says so and offers it.
  - A generic skill is fine when the employee asks for it instead of the Ono flow, or when the Ono command doesn't fit the repo.

  The router says the same.
- **"Review A into B" maps to `/review-code B`** while on A ("Code review bypassed Ono process"). If they aren't on A, they switch and back as for a PR review. Claude fetches first and uses `origin/B` when the local B is missing or behind. The other half of that report, no routing note on the first message, doesn't reproduce today. Since 0.5.1 the note comes on every typed message, the first one included (tested with no transcript yet). The report's quotes show Guy's later messages already carried 0.5.1-era notes, though, so a mid-session update or a misreport is possible. If it happens again, send the session transcript.
- **Bug reports: draft first, write after OK** ("report-bug writes without confirmation"). On "report a bug", Claude wrote a one-bug report from its own reading of the session and opened Finder; the employee had three bugs in mind. Now, after collecting the facts and picking the suspected component, Claude shows a short draft:
  - title, suspected component, what happened, expected
  - the one missing-fact question, if any
  - "one bug or several?"

  Nothing is written before the employee's OK. Several bugs → one file each, linked to the others, and Finder opens their folder once. Facts still come from the session (no interview).
- Checked by an independent review agent. Its 4 must-fix findings were all fixed: a "which one did you use" answer that could have been untrue, the line showing where the dev plugin isn't installed, wording that could catch the dev plugin's own review skills, and an over-sure changelog claim. So were the useful notes: running-step next command, "bug in the app", stale base branch, report-bug step order and several files.

## [0.6.0] — 2026-11-22

- **Closing a session no longer pushes the employee into a commit and a PR** (team feedback: every close asked for commit + PR, even with only logs changed). Closing isn't finishing: the closer first decides whether the bug or feature is **finished** (the employee said so, or the Ono flow reached its end this session: fix verified + reviewed, every task done and reviewed, QA notes created, an inspection completed; when the flow ended but the employee didn't say so, it asks once) or **in progress** (everything else, including a close because the session got long).
  - Only notes, logs or plugin documents changed → "nothing to commit", no question.
  - Code changed, work in progress → one optional question: a checkpoint commit (yes / no). No pre-PR check, no push, no PR.
  - Work finished → the full path as before: commit hygiene → commit → pre-PR check → push → PR.
  The long-session 💡 suggestion, the router's stage-end offer, onboarding and the employee guide say the same.
- **PRs waiting for your review at session start.** New `scripts/review-requests.sh`: open PRs where someone asked **this employee** to review (personal requests, not team ones; drafts left out), through the employee's own `gh` login. It starts together with the git fetch and has its own 3-second watchdog; no `gh`, not logged in, offline or slow → nothing shown. The opener offers them in its "what are we working on" question (at most three); a PR of this repo goes to `/ono-mobile-dev-plugin:review-code ‹PR url›`, another repo's gets its link. Guardian never approves, requests changes or comments on GitHub for the employee. Off switch: `PG_REVIEWS=off`.
- **Windows: jq and Bun lines with a Windows fix** (bug reports 2026-11-22, Windows 11 / Git Bash, `YesPlusSmartTV`). The `jq` line from 0.4.1 gave only Mac / Linux install commands. The TOOLS lines now carry the OS, and the opener gives that OS's command: Windows `winget install jqlang.jq` in PowerShell, then reopen Claude Code from a new window.
- **Bun missing → said up front.** The Ono Project Inspector runs on Bun and stops without it. When the inspector is installed and has something to run here (project not inspected, older knowledge model, or the manifest below missing), session start adds a Bun TOOLS line (Windows `winget install Oven-sh.Bun`, Mac `brew install oven-sh/bun/bun`). The inspect gate's red banner starts with "First install Bun" on such a computer, so an employee isn't sent to an `/inspect` that can only stop.
- **Inspection done but `.ono/repo-knowledge.json` missing → one ℹ️ line, once a day per repo.** An inspection made before the inspector wrote its manifest makes the dev plugin re-read the code on every analysis. The manifest is committed by design, so one `/ono-project-inspector:inspect-sync` by anyone with Bun fixes it for the whole team.
- **Project docs behind the code → offered once, as its own task** (Tom + Yagil, 2026-11-22). New `inspect-status.sh drift`: the inspector's own freshness rule (`inspection-state.ts`), in git only — no Bun, no tokens — **measured on the central branch** (its `.ono/state.json` and code), where the refresh is done: source files changed since `knowledgeHead`, inspector-owned files left out, nested projects relative to their folder, names with spaces or non-ASCII handled, only inspections through stage 3, "last updated" = when `state.json` was last committed. An employee's own branch never triggers it, a merged refresh stops it for everyone, and an unmerged `chore/refresh-project-docs*` branch on the remote silences it (no duplicate PRs). When it matters — a build / dependency / CI manifest changed, a top-level folder came or went, 30+ source files changed (`PG_DRIFT_FILES`), or a change on knowledge 30+ days old (`PG_DRIFT_DAYS`) — the opener shows once a day per repo when the docs were last updated and what changed, and offers **Refresh Project Knowledge** as a separate task: from a clean tree, on `chore/refresh-project-docs-‹date›` off the up-to-date central branch, in a PR of its own, so the team pays for it once and feature PRs never carry doc rewrites. Never automatic: the refresh re-reads code and rewrites docs (minutes, many tokens).
- PR review requests: only PRs by people in the org / repo (`authorAssociation` MEMBER / OWNER / COLLABORATOR — CODEOWNERS also requests reviews on outsiders' PRs), titles stripped of control characters and backticks, cut to 80 characters, and marked as data for Claude. The lookup has a hard bound in the hook too (a `gh` that ignores the watchdog can't hold up the opener) and its own temp folder. A picked PR is reviewed on the PR's own code (`gh pr checkout` from a clean tree, then back), not the employee's branch.
- Closer review fixes: finished work that's already committed (checkpoint commits from earlier) still gets the pre-PR check and the PR; a checkpoint commit goes through the branch step; an inspection on a feature branch doesn't make the feature "finished". The Node.js TOOLS line names the OS too (Windows: `winget install OpenJS.NodeJS.LTS`).
- Independent review agents: 7 + 5 must-fix findings, all fixed and tested; notes kept for later (Git Bash has no `pkill` — same as the existing watchdogs).
- The plugin-side parts (the dev plugin's `jq` dependency on Windows, the inspector's Windows install line, the pre-PR check as part of the dev flow, version / date headers on the inspector's documents and a way to bring audits up to date) go to the plugin owner separately.

## [0.5.2] — 2026-11-19

- **Every new task goes through the router, not just the first one** (employees still saw work done outside the Ono plugins). In 0.5.1 the routing note stopped once the session had been routed, so a second bug or task later in the same session was again handled without the plugin flow. Now, after routing, a shorter `[platform-guardian] Routing:` note stays on each typed message: new work — a different bug, feature or task, or any code change after the Ono step has finished — goes through `platform-guardian:work-router` before reading code or editing; a reply to the running step's own question (approve, continue, results, details) continues that step even when it describes a failure or a new symptom; "yes" / "continue" to a Continue? offer follows its `next_command`; questions with no change asked for are just answered; work outside the Ono flow only when the employee said so for that task or the whole session. Reviewed by an independent agent (wording risks around mid-step answers and post-step edits — fixed). Same scope as before: typed messages in a git repo, not slash commands; `PG_ROUTE_REMINDER=off` turns both notes off.
- The router's "Between stages" section says the same.
- The plugin-side part goes to the dev-plugin owner separately: the feature planning stages to offer the next step like the bug flow does (`next_command`, "Continue?"), and the code-edit permission prompt to name the right entry command when no Ono work is in progress.

## [0.5.1] — 2026-11-18

- **A task described after the opener now goes through the router** (bug report 2026-11-18, Raz, `yestv_aos`). The opener asks "what are we working on?" and hands over to `work-router`, but the answer arrives in the next message, and nothing reminded Claude then: a bug described in free text was investigated and edited directly (two wrong fixes, one a black screen), with no bug analysis, approved plan or QA handoff. Now every typed message in a git repo gets a short `[platform-guardian] Routing:` note until the session has been routed — the `work-router` or `pre-pr` skill ran, or an Ono plugin skill or command ran (typed in full or as a short form `routes.json` knows, or started by Claude). Only the transcript's own records count, not text quoted in a tool result. The note: a task goes through `platform-guardian:work-router` before reading code, investigating or editing; greetings, answers to the opener's git question, questions with no change asked for, close-out requests and questions about Guardian are just answered; a general preference for "lean" work doesn't skip it — only the employee saying they don't want the Ono flow does (asked once). Slash commands get no note; a message that starts with a pasted path (`/Users/…`) does. Checked by an independent review agent (7 findings: path messages skipped, text in tool results counted as routing, non-repo folders reminded, unprefixed skill / `SlashCommand` runs missed — all fixed and tested; the rest are notes). It's a reminder, not a block: small work with no Ono route stays possible. Off switch: `PG_ROUTE_REMINDER=off`.
- The opener says the same at its hand-off: run the router first thing in the reply that brings the task.

## [0.5.0] — 2026-11-17

Three plugins are no longer part of the Ono process (Yagil, via Tom): **`matrix-qa-plugin`** (web QA), **`matrix-studio`** (Figma design systems) and **`spec-team-toolkit`** (HLD / LLD / SPAC).

- **Removed from Guardian's `dependencies`** — Guardian now brings three plugins: `ono-project-inspector`, `ono-mobile-dev-plugin`, `ono-plugin-qa`.
- **Removed from routing and resume** — the `qa-web-matrix`, `spec` and `design-system` intents, their human-only steps, resume probes (`docs/specs/`, Matrix QA plans) and committed-artifact lists are gone. Guardian behaves as if they never existed: a request for web QA, a spec or a design system is handled like any other request with no Ono route.
- **Already installed? One notice.** Removing a dependency doesn't uninstall it (Claude Code docs: plugin dependencies). When one of the three is still installed, the session start shows a one-time ℹ️ line (once per computer, never in the same reply as the first-time welcome) with how to remove it: `/plugin` → **Installed** → **Uninstall**, or `claude plugin prune` in the Terminal app (removes only plugins installed as Guardian's dependencies; never one the employee installed themselves). Inside Claude Code it's `! claude plugin prune -y` — without `-y` it removes nothing there (not a terminal). Guardian never uninstalls anything itself.
- The 0.4.3 Matrix-QA broken-Node line is gone with it; the dev-plugin Node check (0.4.2) stays.
- **Kept on purpose (passive, never shown unless the repo has `matrix-qa.config.json`):** Guardian's write guard still leaves a Matrix QA repo's `qa/` folder alone, and the git report still notes that such a repo blocks Claude's git writes — **only while matrix-qa-plugin is installed** (unknown plugin list → assumed installed). So a team that keeps using it outside Guardian isn't broken, and after uninstalling it nobody is told their git writes are blocked.
- Docs: plugin counts (six → three), Figma MCP copies (four → two: dev, QA).
- **`node_modules/` stays blocked from commits in every repo** — it was on the never-commit list only through matrix-qa-plugin's entry; now it's in the list that applies everywhere (found by the commit-guard tests).

## [0.4.3] — 2026-11-17

- **Broken or missing Node.js + Matrix QA plugin → the opener explains the red "hook failed" lines** (bug report 2026-11-17, Android repo). The Matrix QA plugin (0.1.0) starts `node` for its guard before almost every tool call (Bash, Read, Edit, Grep …) in every repo; on a machine whose `node` crashes on start (an Intel Homebrew Node missing its ICU library) or isn't installed, every call printed "PreToolUse:… hook failed" with a raw `dyld` error and nothing said where it came from. Inside Matrix QA repos the guard is then off (a crashing hook doesn't block). Guardian now checks Node when the Matrix QA plugin is installed too, and the opener shows one ⚠️ line: where the errors come from, that work isn't blocked, and the fix (the LTS installer from nodejs.org, restart from a new Terminal window). A working old Node (e.g. 20) is fine for that plugin's guard and gets no line from it. The plugin-side fix (start `node` only in QA repos, a clear message) goes to its maintainers.
- Routes re-verified against `ono-project-inspector` 0.11.3 (its own protected-branch workflow: a working-branch gate before the first write, helpers that refuse to write on `main`/`master`/detached HEAD, and a write guard for the Inspector agent). No route change; registry artifacts unchanged. No conflict with Guardian's gate: on a protected branch Guardian still blocks the Inspector's commands first and offers `! git switch -c chore/project-inspection`; on the work branch the Inspector asks nothing. On a detached HEAD (not protected for Guardian) the Inspector's own gate now offers the branch.

## [0.4.2] — 2026-11-17

- Routes re-verified against `ono-mobile-dev-plugin` 0.7.7 (Node.js preflight in every command, complete JSON output from its scripts). No command, route or resume change (document formats changed only in version strings).
- **Node.js too old → the opener says so.** From 0.7.7 the dev plugin needs Node.js 22.18+ on the 22 line, or 24+. On anything older (or no Node at all) every dev-plugin command stops at its Node check, and an approved Bug Fix Cycle no longer skips the code-edit approval prompt. When the dev plugin is installed, the session-start hook checks the `node` on Claude Code's PATH (with a 2-second watchdog) and adds a `TOOLS:` line; the opener shows one ⚠️ line with the version found, how to upgrade in the Terminal app (nodejs.org LTS installer, or nvm, then restart Claude Code from a new Terminal window) and how to check inside Claude Code (`! node -v`). For first-time users it's part of the welcome (item 3c). Guardian itself still needs no Node.

## [0.4.1] — 2026-11-16

- Routes re-verified against `ono-mobile-dev-plugin` 0.7.6 (Bug Flow first-bug fix, hooks fail closed, `NotebookEdit` covered, main/master hook scoped to the project repo). No command, route or resume change (document formats changed only in version strings). Both hooks now allow files outside the project repo (scratch, `/tmp`); they still differ on a sibling repo and on git-ignored files (Guardian judges the file's own repo and allows ignored files).
- **`jq` missing → the opener says so.** From 0.7.6 the dev plugin's hooks block (secrets, main branch) or ask (approval) on every file change when `jq` isn't installed, on every branch. Guardian itself needs no `jq`; when the dev plugin is installed, the session-start hook adds a `TOOLS:` line and the opener shows one ⚠️ line with how to install it in the Terminal app (Homebrew, jqlang.org, or macOS 15+, which includes it). For first-time users it's part of the welcome (item 3b), not a second opener line.

## [0.4.0] — 2026-11-16

Protected branches, the inspect gate and plugin independence (Dev Plugin 0.7.5 integration review; design and reasoning in `docs/branch-policy.md`).

- **Work branch before the inspection** (deadlock: the gate blocked the employee's answer to "create a work branch?", and the inspector on `main` had its writes half-blocked by the dev plugin). On a protected branch the gate blocks the inspector's commands, for a first inspection and a refresh alike (read-only `inspect-status` excepted), and the banner starts with ① `! git switch -c chore/project-inspection` ② `/ono-project-inspector:inspect`. The only thing the gate lets through before the inspection is that exact branch command (`git switch -c` / `git checkout -b`, one command, nothing chained, not to a protected name). Plain-language requests stay blocked, so this opens no way around the inspection.
- **Guardian's own write guard** (`hooks/write-guard.sh`, `Write | Edit | NotebookEdit`): no file changes on a protected branch, meaning `main`, `master`, and the project's central branch when it's certain (`.platform-guardian.json` `centralBranch`, or detection confidence `high`, cached at session start). About 80 ms per write on a work branch. Guardian no longer relies on the dev plugin's `main`/`master` hook; both stay, on purpose.
- **Commit guard: commit or push on a protected branch → deny** (was: a permission prompt). This includes a push whose target is protected (`HEAD:develop`, `+x:refs/heads/main`, `:develop`). `git switch -c x && git commit` is judged on `x`.
- **Claude can't start the Inspector on a protected branch either** (`Skill` / `Agent` / `SlashCommand` → deny, except `inspect-status`). The gate only sees what the employee types.
- **QA plugins keep their own git flow**: the ono-plugin-qa QA repo and matrix-qa's `qa/` folder aren't blocked (the employee reviews and commits there by design). Never blocked either: `~/.claude`, git-ignored files, a brand-new project with no commits yet.
- Hardened after three independent review agents: push through `heads/main`, `--all`, `--mirror`, subshells, `if`/`env`, line breaks and `checkout -` are all caught; branch names compare case-insensitively (`Main` is `main` on macOS); a commit or push the guard can't read gets the permission prompt. Details: `docs/branch-policy.md` → Review.
- **Inspector missing or turned off** → the banner gives the install / enable line, and a command that doesn't exist no longer opens the gate.
- Routes re-verified against `ono-mobile-dev-plugin` 0.7.5 (nested-project knowledge only; no command, hook or document-format change).
- One definition of "protected branch" for every hook: `scripts/protected-branch.sh`. Router: a work branch for every intent that writes files, not only dev. Opener: `.platform-guardian.json` is written after the work branch exists.

## [0.3.7] — 2026-11-16

- Routes re-verified against `ono-project-inspector` 0.11.2 — the fixes for the tester report (agent can run its own flow, Bun preflight, project root below the git root, same layout Guardian 0.3.6 already supports). No route changes; inspector registry artifacts unchanged.

## [0.3.6] — 2026-11-15

- **Projects in a subfolder of the git root** (tester bug, `yestvos/YesTVOS/`): Guardian looked for the inspector's outputs only at the git root, so a complete inspection was reported `missing` and its new `docs/project/capabilities.md` was refused as a stray document. The inspect gate, resume and the commit guard now find the project folder — the nearest folder from the session folder up to the git root holding the inspector's `AUDIT.md`, or the single subfolder (≤ 4 levels) holding `.ono/state.json` (`inspect-status.sh root`) — and allow inspector outputs under it. Two inspected subfolders with the session at the root aren't guessed. The empty "missing ()" detail is gone.
- **Opener: one question per message** (tester report: work-branch name + inspection refresh offer + "what are we working on" arrived together). Git decisions first, one at a time; then the refresh offer (never while still on the central branch — the refresh writes files); then "what are we working on".

## [0.3.5] — 2026-11-15

- **The inspect gate can't drift from the inspector again.** `check-routes.sh` (every PR + the daily drift job, which opens an issue) now compares Guardian's "inspection complete" files and "older knowledge model" files with the inspector's own `skills/registry.json` (`produces` of artifact-completed inspection stages, minus `knowledgeModel` artifacts). A new required or knowledge-model artifact in a future inspector release is reported as `INSPECT DRIFT` before it can wrongly block employees. The lists live in one place (`inspect-status.sh` `STAGE_ARTIFACTS` / `MODEL_ARTIFACTS`); `resume-state.sh` reads the same list.
- Routes re-verified against `ono-project-inspector` 0.11.1 (docs: `/inspect` refresh triggers aligned with 0.11.0) — no route changes; registry artifacts unchanged.

## [0.3.4] — 2026-11-15

Guardian now handles two situations itself that used to need the maintainer (both from the YesPlusSmartTV report):

- **Suspect main-branch detection → asks once, saves for the team.** `git-status.sh` no longer trusts the remote's default blindly: an unusual default (a feature / staging branch such as `Back-key-on-Webos-stg`) while `develop` / `dev` / `main` / `master` exists, or a branch more than 1000 commits ahead of the detected central (`PG_SUSPECT_AHEAD`), is reported low-confidence + `central-ambiguous`. The opener says why, asks once which branch is the main one, and offers (recommended) to write `.platform-guardian.json` so nobody on the team is asked again. `dev` is now a recognized main-branch name. An override is never second-guessed.
- **Older-model inspection → Guardian offers the refresh itself.** When the inspection is complete but predates the current knowledge model, the opener offers to run `/ono-project-inspector:inspect` → Refresh Project Knowledge right away (yes / later); the outputs go into the employee's next PR so the whole team gets the current model. `inspect-status.sh elsewhere` finds a complete current-model inspection sitting on another remote branch and mentions it as FYI (merging another branch stays a human decision) — also in the gate's context when a project is blocked.

## [0.3.3] — 2026-11-15

- **Every commit and push needs the employee's OK** (tester bug: after the employee picked an inspector option, Claude committed on its own — the guard denied the non-code files, then Claude re-ran with `PG_INCLUDE_FILES=1` by itself). The commit guard now returns a permission prompt (`ask`) for every `git commit` and `git push` ("approve only if you asked for it"), and for every `PG_INCLUDE_FILES=1` add of non-code files — the flag alone no longer lets files in; the employee confirms them. Denials (secrets, non-code files without the flag) still win. None of the Ono plugins commit on their own (dev plugin: "never creates a git commit"), so the only prompts are Guardian's close-out and Claude-initiated commits.
- **Inspect gate: an inspection made with an older inspector knowledge model is complete, not "partial"** (tester bug: `YesPlusSmartTV` blocked for a missing `docs/project/capabilities.md`). Per the inspector's registry, a `knowledgeModel` artifact's absence "never reopens an otherwise complete stage" (`inspection-state.ts` skips it). `inspect-status.sh` now requires only the stage artifacts and returns `done` + `refresh-recommended`; the opener shows a one-line, non-blocking 💡 "Refresh Project Knowledge" hint. Same split in `resume-state.sh`.

## [0.3.2] — 2026-11-15

- **Resume knows the dev plugin 0.7.4 half-started bug plan.** 0.7.4 writes the Bug Work Plan right after the platform / device-type confirmation, so an interrupted `/analyze-bug` keeps its routing (the fix for the tester's "platform detected again after /clear" bug). Guardian's resume no longer shows that draft as "waiting for approval — your step": it says *analysis in progress, platform ‹p› / ‹d› already confirmed* → `/analyze-bug ‹key›` continues with no new detection.
- Routes re-verified against `ono-mobile-dev-plugin` 0.7.3 (better tvOS / React Native detection) and 0.7.4 — no route changes.
- Routes re-verified against `spec-team-toolkit` 0.6.1 (`lld-web-backend-spec`: capabilities, readiness table, source-reading rules) — same skills, no route changes. Close-out timing wording follows 0.7.4 (the analysis resumes; routing is no longer lost).

## [0.3.1] — 2026-11-15

- **No close-out in the middle of a plugin step** (tester bug: closing mid-analysis made the next session re-detect the platform and re-run the analysis). The 💡 session-length suggestion now waits until the running Ono plugin step has saved its result. If the employee closes mid-step anyway, the closer first says plainly what would be redone and recommends finishing; on "close anyway" the log records what was already confirmed (e.g. platform / device type) so the next session can tell them. The plugin-side fix (persisting a confirmed routing before the plan exists) is with the dev-plugin owner.

## [0.3.0] — 2026-11-15

- **⛔ Inspect gate (Ono rule: every project is inspected first).** New `hooks/inspect-gate.sh` on `UserPromptSubmit` and `UserPromptExpansion` + `scripts/inspect-status.sh`. If the project hasn't been through the Ono Project Inspector (stages 1–2: `AUDIT.md`, `CLAUDE.md`, `docs/project/*`), every message and Ono plugin command is **blocked** with a red ⛔🚨 banner: run `/ono-project-inspector:inspect`, or — only with a manager's approval — type the exact sentence `I have manager approval to work without inspect` (Hebrew: `יש לי אישור מנהל לעבוד בלי inspect`), which opens the repo for that day (recorded locally, never in git). Started-but-unfinished inspections and branches older than an inspected central branch get their own instruction. The inspector's own commands, Guardian's and built-ins stay open. `.platform-guardian.json` `"inspectRequired": false` exempts a repo (committed → reviewed).
- The inspector's outputs (`AUDIT.md`, `CLAUDE.md`, `docs/project/**`, `audits/**`, `.ono/state.json`, `.ono/repo-knowledge.json`) are now **committed** by default (exception to "only code") — the gate reads them, so the team must share one inspection.
- Routes re-verified against `ono-mobile-dev-plugin` 0.7.2 (fix for the deferred-reproduction QA-handoff block found in Guardian testing) — no route changes.

## [0.2.9] — 2026-11-12

- Routes re-verified against `ono-mobile-dev-plugin` 0.7.1 (its fix for `REPOSITORY_UNAVAILABLE` in large repos, found in Guardian testing) — no route changes.

## [0.2.8] — 2026-11-11

- **Bug reports:** new `platform-guardian:report-bug` skill. When something breaks in Guardian, an Ono plugin or Claude Code ("report a bug", or Claude offers it after spotting a tool bug), it writes one organized report — summary, exact error, expected, steps, findings with `file:line`, workaround, suspected component — plus an Environment section from `scripts/bug-report.sh` (Claude Code, Guardian and every Ono plugin's version, macOS, repo, branch, git state). Saved under `~/.claude/platform-guardian/bug-reports/`, never in the repo; Finder opens with it selected so the employee can send it to the maintainer. The closer offers it once if a tool bug happened and no report was written.

## [0.2.7] — 2026-11-10

- **Commands the employee types are given with their full name** — `/ono-mobile-dev-plugin:verify-fix-cycle bug:KEY`, not `/verify-fix-cycle` (tester bug: the short form didn't run, so the employee hit an unknown command on a human-only approval step).

## [0.2.6] — 2026-11-10

- **Only code goes into a commit, in every flow** (tester bug: two bug fixes pushed MD + JSON files that didn't belong in the PR). The commit guard now leaves new documents, data and plugin working files out — `.json` / `.yaml` included, and the Ono plugins' own documents (bug work plans, task state, planning docs, reviews, spec drafts, inspector reports) too. They stay on disk, never deleted or `.gitignore`d. A file goes in only when the employee asks for it (`PG_INCLUDE_FILES=1 git add <path>`) or the project lists it in `.platform-guardian.json` `"commitPaths"`. The session closer shows ✅ will commit / ⏸️ stays out.
- **Pre-PR check before every PR:** new `platform-guardian:pre-pr` skill (one-page PDF of what the change could break, outside the repo, never committed). The closer runs it automatically before push + PR; **skip** skips it; not run in QA repos or for docs-only changes. Also on request: "ready for PR", "what could I have broken".

## [0.2.5] — 2026-11-10

- **First-time welcome no longer buries the tour offer** (first tester bug): the first reply is only the welcome + the tour offer, as its last line, and waits. Git questions, the branch choice and "what are we working on" come after the employee answers yes/later — before, they followed the offer in the same message and the tester almost missed the tour.
- Docs: one-page employee guide, `docs/employee-guide.md`.

## [0.2.4] — 2026-11-09

- Routing: spec-team-toolkit 0.5.0 renamed `lld-web-figma-spec` → `lld-web-backend-spec` (one integrated web LLD for frontend, backend and QA) — the `spec` route follows it. Caught by the routes check.

## [0.2.3] — 2026-11-09

- Repo renamed `yes-platform-guardian` → `ono-platform-guardian`: manifest `repository`, clone commands and the drift-issue script point to the new name (GitHub redirects the old one).

## [0.2.2] — 2026-11-09

- Branding: **OnO Platform Guardian** — the first-time welcome uses the name; yes+ logo and footer removed from the README (manager's request).

## [0.2.1] — 2026-11-09

- **Updates reach employees:** first-time welcome and the tour's cheat sheet give the one-time auto-update setup (`/plugin` → Marketplaces → ono-plugin-marketplace → Enable auto-update) — off by default for org marketplaces; managed settings turn it on org-wide (`docs/rollout.md`).
- CI: `scripts/check-version-bump.sh` fails a PR that changes plugin files without raising `plugin.json`'s version — Claude Code updates installed copies only when it goes up.
- Daily drift check (`.github/workflows/drift.yml`, was weekly): the six Ono plugins vs. `routes.json`; drift opens one GitHub issue assigned to the maintainer (`scripts/report-drift.sh`), closed automatically when back in sync.
- Onboarding wording: the git check shows on the first message; no trigger word; every step says exactly what to type.

## [0.2.0] — 2026-11-09

- **Onboarding** 🎉: first session on a computer opens with an emoji welcome and offers an interactive 3-minute tour (`skills/onboarding`, 5 steps) — how a session starts, routing by plain words (demo, starts nothing), what it never does for you (approvals, commit guard), closing, cheat sheet. Offered once: the SessionStart hook writes `~/.claude/platform-guardian/.state/onboarding-offered` when it injects the offer; `onboarding` re-runs it on request; `PG_ONBOARDING=off` disables it.
- Fetch timeout is a watchdog timer (exactly 5 s; the old sleep-count loop drifted to ~7 s on slow machines).
- Opener: "numbers may be out of date" whenever the fetch failed; open once per session (not after `/compact`); your-step items aren't offered as "continue". Router: approval requests answered directly; disabled vs missing plugin; asks for a missing bug key / feature name; a "yes" never runs a human-only step. Closer: asks before push / PR.
- In the org marketplace (`ono-plugin-marketplace` 1.6.0). Live test runs through the real install (`docs/tester-guide.md`).

## [0.1.0] — 2026-11-09

- Plugin skeleton: manifest with dependencies on all six org plugins (incl. matrix-qa-plugin and matrix-studio) (bundle pattern — installing Guardian installs them).
- Goal redefined as the single entry-point router: `docs/vision.md`.
- July MCP / 7-phase plan archived under `archive/2026-07-mcp-plan/`.
- Session opener (G1): `scripts/git-status.sh` (JSON git report vs. the central branch, bounded non-interactive fetch, fails open, bash 3.2, no jq), `scripts/session-log.sh` (local per-branch session log), SessionStart hook on `startup|clear`, `session-opener` skill, optional `.platform-guardian.json` (`docs/project-config.md`). Tests: `tests/run-all.sh`.
- Router (G2): `routing/routes.json` (intents → Ono plugin commands, human-only list, resume probes, git guards), `skills/work-router`, `scripts/check-routes.sh` drift guard.
- Closer (G3): `hooks/prompt-submit.sh` session-length signal (real context tokens), `skills/session-closer` (hygiene → commit → push → PR, local session log, `/clear`), `routing/committed-artifacts.json`. Git report gains `guards.matrixQa` / `guards.onoQaCommitBlocked`.
- Commit guard (G3.5): `hooks/pre-tool-use.sh` — on `git add` / `git commit`, new files on a `neverCommit` list are denied and stray working files (`.md`, `.log`, `.html` … not on any `commit` list) need the employee's OK. `PG_COMMIT_GUARD=off` disables it.
- Live-test kit for G1.7: `docs/live-test.md` + `scripts/live-test-setup.sh` (test repos, `pg/*` branches, versions, installed Ono plugins, hook timing — one command).
- Minimum Claude Code version: 2.1.140 (`docs/rollout.md`).
- Resume (G2.3): `scripts/resume-state.sh` lists unfinished work from the Ono plugins' own documents — dev features + bugs, ono-plugin-qa, matrix-qa-plugin (exact `mqa.mjs` fingerprints), inspector, specs in `docs/specs/` — with the next step; injected by the SessionStart hook. Formats: `docs/resume-state.md`. `PG_RESUME=off` disables it.
- Fix: `git-status.sh` reported a bogus upstream `"@{u}"` on branches without one under git ≥ 2.4x (found by the Linux CI run).
- CI: `.github/workflows/ci.yml` — tests on macOS bash 3.2 and Linux, and a weekly `check-routes.sh --strict` against every plugin the marketplace lists (`scripts/fetch-org-plugins.sh`).
- Decisions: specs saved to `docs/specs/<feature-slug>/`; `design-system` intent (matrix-studio); QA routing picks mobile/TV vs web from the task.
