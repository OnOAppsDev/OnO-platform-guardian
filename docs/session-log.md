# Session Log — Platform Guardian

---

## Session 19c — 2026-11-24 — Inspector 0.12.0 on Node.js: Guardian follows (0.7.3, released)

- Yagil shipped Inspector 0.12.0 (Bun removed, Node.js only, `scripts/node-preflight.mjs`) and gave five rules. Verified against its source, then 0.7.3: no Bun lines for 0.12.0+; an older inspector without Bun gets "update the inspector" (never "install Bun"); the inspector's preflight decides Node; one shared Node line for the inspector and the dev plugin; nothing when the inspector isn't installed here.
- New `scripts/ono-plugin.sh` (shared plugin lookup; `inspector-runtime` skips turned-off and other-project installs) and `scripts/node-check.sh` (one node process under a watchdog). The gate banner and the opener's TOOLS wording were updated; `routes.json` was re-verified against 0.12.0.
- Review: 0 must-fix, 6 should-fix + 8 nits fixed (opener trigger collision, refresh offer hidden by a dev-only Node line, turned-off / other-project installs). 870 checks green, 6 mutations caught; macOS startup 0.97 → 1.00 s.
- PR #45 merged. First official GitHub release + tag: `v0.7.3`. Message sent to Ekaterina: update the marketplace, restart, retry Refresh Project Knowledge.
- Open: Ekaterina's confirmation (then tell Yagil); 0.7.3 not yet run on Windows.
- **Process improvement:** when a hook gets a new context line, grep the opener skill's triggers for it, so no two triggers match one line. The reviewer caught "Node.js" matching both the update line and the Node trigger.
- **Next session:** Ekaterina's result on 0.12.0 + 0.7.3 → report to Yagil; any feedback on 0.7.2 / 0.7.3.

---

## Session 19b — 2026-11-24 — Central branch asked every session (0.7.2) + two reports triaged

- Guy, `yes_plus_mobile_android`: "develop or master?" every session, even before a read-only PR review (origin/HEAD = master, develop 41 ahead). Guardian's bug. 0.7.2: master with no commits of its own except merges → `develop` (`gitflow`, high); otherwise still asks. The answer is remembered per repo on the employee's computer (`protected-branch.sh answer`, protects at once). A read-only first task gets no git questions; the router settles them before a write intent.
- Side effect, on purpose: in these repos `develop` is now protected (it was a plain work branch under the `master` guess). Called out in the CHANGELOG.
- Guy's second report (`/analyze-bug` asks the platform on every bug, yestv_aos) is the dev plugin's design (`commands/analyze-bug.md` step 5, test 17). Message for Yagil given; only that one is his.
- Review: 2 must-fix (a release merge flipped the verdict to master-high; `origin/develop` overwrote a good answer and was then ignored) + 6 should-fix, all fixed. 822 checks green, 4 mutations caught.
- Open: Yagil on Bun (0.7.1 ticket) and on analyze-bug routing; 0.7.1 / 0.7.2 live on team machines.
- **Process improvement:** a history-based guess needs the release step in its test set. The first rule worked until the team's first release; the reviewer found it, my tests didn't.
- **Next session:** Yagil's answers; feedback from Guy / Ekaterina on 0.7.2.

---

## Session 19 — 2026-11-24 — Windows: Bun warning lost with the whole opener (0.7.1)

- Ticket (Ekaterina, `YesPlusSmartTV`, Windows 11): the inspector stopped with `BUN NOT FOUND`, and Guardian had shown no warning, with no SessionStart report at all. Split: Bun-only is the inspector's design (Yagil, A2); the missing warning is Guardian's.
- Likely cause (not proven on her machine): the start-up hook passed its 20 s timeout, so Claude Code dropped all output. `inspect-status.sh elsewhere` ran up to 3 `git` per remote branch (≤ 200), which is slow in Git Bash. Now one `cat-file --batch-check`: 4.4 s → 0.4 s; hook 7.1 s → 2.2 s on macOS. Alternative cause to ask about: a resumed session (the hook matches only startup|clear).
- 0.7.1: time budget in the hook (`PG_HOOK_BUDGET` 12 s, optional checks skipped and named in `SKIPPED`); opener fallback runs the full hook; the inspector's own Windows Bun command (verified per-user, no admin); no-permission line; no "run it now" refresh offer without Bun. Declined: an extra Bun banner in the gate for `refresh-recommended`.
- 805 checks green, mutation-checked (branch search, budget). Independent review: no must-fix; 5 should-fix/nits fixed (the core before the budget runs git-status once, not twice; one SKIPPED rule; a test that passed without the feature; inherited `SECONDS`; backlog wording). Not fixed (older): once-a-day markers are written even when a timed-out hook loses its output.
- Open: Yagil's side (Bun → Node, or one agreed install command; A2 / A4); confirm on a Windows machine that the opener now arrives.
- **Process improvement:** every script the SessionStart hook calls is now judged by process count, not macOS seconds. Windows Git Bash multiplies each process start, and a timed-out hook loses everything silently.
- **Next session:** Yagil's answer on Bun → adjust the TOOLS line; live check of 0.7.1 on Ekaterina's machine.

---

## Session 18 — 2026-11-22 → 11-23 — Guy's 3 reports (0.6.1), dev plugin 0.8.0 integration (0.7.0)

- 0.6.1 (PR #40): Ono commands come before generic review skills (only where the dev plugin is installed, honest "what ran"), "review A into B" → `/review-code B`, and report-bug shows a draft before writing. Guy's "first message not routed" doesn't reproduce since 0.5.1, but that isn't fully proven.
- 0.7.0 (PR #41) implements Yagil's `docs/guardian-integration.md` §1–§10 for dev plugin 0.8.0. Guardian's pre-PR is removed; the closer queries `ono-pr-readiness` v1 via the new `scripts/dev-plugin.sh` (`readiness` / `pr-body`); teammate PRs go to `/review-pr ‹URL›`; routes and resume lines are updated.
- Policy (approved with Yagil's PR): the dev plugin's planning and review documents are committed with the code (`requiredInPr`), the second exception after inspector outputs.
- Independent reviews: 0.6.1 had 4 must-fix findings and 0.7.0 had 2 (wrong installed entry with several installs; hand-copied PR body), all fixed. 791 checks are green and routes are verified against 0.8.0.
- Open: inspector still 0.11.3 (A4, A2 `winget`); Yagil's live-unverified gates (`/review-pr` fork + guard, real gh / Bitbucket reads); the `next_command` question. Message: `~/Downloads/2026-11-23-yagil-after-dev-plugin-0.8.0.md`.
- **Process improvement:** a value another plugin hands over to be used verbatim (PR body, title, paths) goes through a Guardian script, never copied by the model (memory `verbatim-handoffs-via-script`).
- **Next session:** first real PR through the 0.7.0 closer on a team machine (live gates), then the inspector release (A4 / A2) when Yagil ships it.

---

## Session 17 — 2026-11-22 — Windows bugs, close without forced PR, PR reviews, docs freshness (0.6.0)

- Two Windows bug reports (ekaterina.s, `YesPlusSmartTV`): the dev plugin blocks every write without `jq` (Yagil); the inspector needs Bun, and the repo has no `.ono/repo-knowledge.json` (one `/inspect-sync` by anyone with Bun fixes it for the team). Guardian: OS-aware jq / Bun / Node lines (`winget`), Bun first in the gate banner, a once-a-day manifest line.
- Team feedback: the closer no longer forces commit + PR — nothing to commit when only notes / logs changed, an optional checkpoint commit mid-work, pre-PR + push + PR only for finished work.
- New: PRs waiting for the employee's review at session start (`scripts/review-requests.sh`, `gh`, org members only, sanitized titles, bounded); docs freshness (`inspect-status.sh drift`, git only, measured on the central branch, refresh offered once as its own chore PR — the refresh costs tokens, the check doesn't).
- Two independent review agents: 7 + 5 must-fix findings, all fixed; 702 checks green. Handoff for Yagil (jq on Windows, Bun `winget` line, pre-PR in the dev flow, doc version / date headers, audit re-check, `/review-code --pr`): `~/Downloads/2026-11-22-yagil-handoff-and-guardian-0.6.0.md`.
- Open: Yagil's side (backlog "Waiting on plugin owners"); the team actions in the handoff Part C.
- **Process improvement:** for any check that leads to a team-wide action (a refresh, a PR), decide first *which branch it's measured on*; the reviewer caught that drift on the employee's own branch would have offered refreshes to everyone.
- **Next session:** Yagil's answers → route Guardian to his `/pre-pr`, trim the TOOLS lines his fixes make unnecessary; live test of 0.6.0 on a Windows machine.

---

## Sessions 14–16 (catch-up, written 2026-11-22) — 2026-11-17 → 11-19 — 0.4.2 → 0.5.2

Not logged at the time; reconstructed from the changelog and git history.
- 0.4.2 / 0.4.3 (11-17): routes re-verified against dev plugin 0.7.7 and inspector 0.11.3; opener warns when Node.js is too old for the dev plugin, and explains Matrix QA's "hook failed" lines on a broken Node.
- 0.5.0 (11-17, PR #36): matrix-qa-plugin, matrix-studio and spec-team-toolkit removed from Guardian (Yagil); a one-time ℹ️ line tells employees how to uninstall them; `node_modules/` stays never-committed everywhere.
- 0.5.1 / 0.5.2 (11-18 / 11-19, PRs #37 / #38): a task described after the opener, and every later new task, goes through `work-router` (bug report from Raz, `yestv_aos`).
- **Process improvement:** write the session-log entry in the same PR as the release; three releases went out without one.

---

## Session 13 — 2026-11-16 — Dev Plugin 0.7.6 review + Guardian 0.4.1

- Yagil asked for a review of Dev Plugin 0.7.6 (dev plugin PR #62). The user approved and merged it before the review started. Post-merge check: 39 suites · 4607 checks · 0 failures on Node 24, and our findings 1–4 are fixed (`docs/branch-policy.md` status). Item 5 is still open.
- Node 20 makes 4 `edit-approval` checks fail (already true in 0.7.5): the approval hook runs `node *.ts`, so on old Node every approved bug edit asks again. That's undocumented, and it's in the message to Yagil along with the missing server-side protection on the plugin repo's `main` (PR #62 merged with no CI or rule).
- Guardian 0.4.1 (PR #32, merged, CI green on macOS + Linux): routes verified against 0.7.6. 0.7.6 blocks every write without `jq`, so session start now adds a `TOOLS:` line and the opener shows one ⚠️ install line, only when the dev plugin is installed (item 3b for first-time users).
- Review agent: 5 findings in my first version, all fixed. The worst was a false claim that the QA plugin needs `jq`: its only hook matches `Bash` and fails open.
- Open: Yagil's reply (minimum Node version, server-side branch protection), live test §5e, deck update.
- **Process improvement:** before writing anything about another plugin's behavior into Guardian text, read that hook's matcher and its no-jq/error path. Grepping for `jq` isn't evidence (same lesson as Session 11: rules come from the owning plugin's code).
- **Next session:** Yagil's answers → if he confirms the minimum Node version, add a Node warning next to the jq one; then the deck update and live test §5e.

---

## Session 12 — 2026-11-16 — Protected branches + inspect-gate deadlock (0.4.0)

- Yagil's email (Dev Plugin 0.7.5 integration): investigated Guardian + dev plugin + inspector code, wrote `docs/branch-policy.md` (findings F1–F6, challenges, who-protects-what table). Key finding: the inspector on `main` gets its `Write` calls blocked but its `bun` writes land, so it leaves a half-written inspection. The block has to be at the command level.
- 0.4.0 (PR #30, merged, CI green macOS + Linux): gate shows ① `! git switch -c …` ② inspect and lets only that exact command through; new `hooks/write-guard.sh` (writes + Claude-started inspector on main/master/certain central); commit/push on a protected branch → deny; one definition `scripts/protected-branch.sh`; dev-plugin routes re-verified 0.7.5.
- User asked for challenge, not agreement, plus review by agents: 3 parallel reviewers (bypass / portability / integration) found 7 bypasses, the QA-plugin conflict and Claude starting the inspector. All fixed + tested (~500 checks); declined a per-project write-guard opt-out.
- Noam's bug (`edit-approval.ts` missing `mkdirSync`) is still in 0.7.5 → it's in the message to Yagil (org admin too), together with server-side branch protection, 3 small hook findings and the QA-exemption sign-off. The user sends it + the MD.
- Open: live test §5e (incl. whether `!` reaches the gate), QA owners' confirmation, deck update.
- **Process improvement:** in an integration change, run the "Claude calls it through a tool" path (Skill/Agent) and every other plugin's own git flow before writing the first version. The reviewers caught both, but they should have been in the design.
- **Next session:** Yagil's answers / live test §5e results → fix any ❌; then deck update (inspect gate, branch step, commit deny).

---

## Session 11 — 2026-11-09 → 11-16 — Live testing with the team: 0.2.4 → 0.3.7

- First tester + team bug reports drove 13 releases (PRs #17–#28, all merged after green CI): first-run tour not buried; only code goes into commits (plugin docs stay out, `commitPaths` per project); bundled `pre-pr` check before every PR; full `/plugin:command` names; `report-bug` skill + `bug-report.sh` (versions of every Ono plugin) — reports now arrive as files and get triaged here.
- ⛔ Inspect gate (0.3.0, user rule): un-inspected projects blocked on every prompt + slash command (`UserPromptSubmit` + `UserPromptExpansion`) unless the exact manager-approval sentence (today only); inspector outputs committed. Follow-ups: older-model inspection = done + refresh offer (inspector registry `knowledgeModel` carve-out), registry drift check in CI, nested project folders (`yestvos/YesTVOS`), Guardian finds an inspection on another branch.
- Guard hardening: every `git commit` / `git push` and every `PG_INCLUDE_FILES=1` needs the employee's permission prompt (Claude had committed on its own and used the flag itself). Suspect main branch (unusual `origin/HEAD`, >1000 ahead, `dev`) → ask once, save `.platform-guardian.json` for the team. Close-out never mid-plugin-step; resume knows dev-plugin 0.7.4 half-started plans.
- Plugin bugs triaged to Yagil, all fixed + version-bumped: maxBuffer `REPOSITORY_UNAVAILABLE` (0.7.1), deferred reproduction QA-handoff block (0.7.2), routing lost on interrupted `/analyze-bug` (0.7.4). Routes verified: dev 0.7.4, spec 0.6.1, inspector 0.11.1. Deck: 17-slide PDF/PPTX on the user's Desktop (pre-PR, report-a-bug, 3 example screens); employee guide `docs/employee-guide.md`.
- Yagil fixed the inspector report overnight (0.11.2: agent tools, Bun preflight, project root below the git root) → routes verified, Guardian 0.3.7. Open: coworker test of dev-plugin 0.7.4; deck not yet updated for the inspect gate + commit approval prompts.
- **Process improvement:** before shipping any new opener/hook behavior, read it as the employee (one question per message — the stacked-question bug came back in step 0b) and derive rules from the owning plugin's contract (registry / code), never from file names.
- **Next session:** user's new items → then deck update (inspect gate, commit approval) → field-check inspector 0.11.2 with the yestvos team (nested project).

---

## Session 10 — 2026-11-09 — Simulated live test, marketplace launch, onboarding, auto-updates, OnO rename

- Simulated the live test here (hooks/scripts on throwaway repos + model replies by agents): fetch cap drifted to ~7 s → watchdog timer; offline opener said "up to date"; ~15 opener/router/closer wording fixes. 0.1 → 0.2.3, PRs #3–#14 merged (user: no reviewer needed), CI green macOS + Linux.
- Repo public; Guardian in `ono-plugin-marketplace` 1.6.0 (#4). User changed the order: the tester installs from the marketplace like every employee (`docs/tester-guide.md`, checklist §0–§0b).
- Onboarding (user idea): first session → one-time emoji welcome + 5-step interactive tour (`skills/onboarding`); hook writes the marker. User-driven fixes: git check shows on the first message, never "hi" (example: "let's start"), every step says exactly what to type.
- Updates (verified in official docs): auto-update is off for org marketplaces and Claude Code updates only on a version bump → one-time setup in welcome/tour/guide, CI version-bump guard, daily drift check → one GitHub issue (`drift.yml`). Org Owners = Magen + Yagil → `docs/org-setup.md`.
- Repo renamed to `OnO-platform-guardian`; yes+ logo removed. Open: marketplace PR #5 (new URL — merge blocked without review; old URL redirects), live test, org setup.
- **Process improvement:** explain to the user in plain, non-technical words first (twice "I didn't understand") and verify any claim about Claude Code behavior in the docs before stating it — saved as memory `plain-language-first`.
- **Next session:** process the tester's filled `docs/live-test.md` → fix every ❌, bump version, merge.

---

## Session 9 — 2026-11-08 — Unblocking rollout: live-test setup, min version, visibility, MGA-83

- Autonomous (user: "close as many tasks as possible"). Org repos unchanged; drift guard clean; 264 checks green on macOS bash 3.2 + Debian; CI green on PR #3.
- G1.7 shortened: `scripts/live-test-setup.sh <app-repo-url>` builds the test repos + `pg/*` branches and fills the §0 table (versions, Ono plugins, hook time); 21 tests, mutation-checked.
- Min Claude Code **2.1.140** (verified in the raw CHANGELOG — the subagent's 2.1.153 was unsupported); in README, rollout, local marketplace branch (new commit `007c178`, not pushed). MGA-83 → Low: the four `figma` servers share one URL and Claude Code connects once (official MCP docs).
- Visibility **decided: public** — history audit clean (no secrets). Flip failed: `tomzion90` has only *write*; needs `OnOApps-Admin` (steps in `docs/rollout.md`).
- Still blocked on the user: admin flips visibility, live test, PR #3 reviewer (`magen`/`yagilcohen` need read access), org Owner.
- **Process improvement:** "since which version" questions → grep the raw CHANGELOG directly (one call), no subagent; check `permissions` via `gh api` before admin-level repo actions — none codified (one-off).
- **Next session:** process the filled `docs/live-test.md` → fix findings; once public + PR #3 merged: tag `platform-guardian--v0.1.0`, push the marketplace PR (G4.1, ask first).

---

## Session 8 — 2026-11-08 — G2.3 resume adapter, CI, Linux bug fix

- Autonomous session (user: "finish as much as possible"). Org repos re-fetched: no change since Session 6; `check-routes --strict` clean.
- G2.3 done: `scripts/resume-state.sh` — unfinished work + next step from all six plugins' own documents (formats traced by 3 parallel agents to plugin source → `docs/resume-state.md`); Matrix fingerprints byte-identical to `mqa.mjs` through every status. Injected at SessionStart; opener/router updated; live-test 5b. 71 tests, 38 mutants (survivors: dead code removed / one equivalent).
- CI: `.github/workflows/ci.yml` (macOS bash 3.2 + Linux, weekly drift check via new `scripts/fetch-org-plugins.sh`). Linux run (Debian container, git 2.47, mawk) caught a real Session-6 bug: bogus `"@{u}"` upstream on newer git — fixed. First real CI run: git ≥ 2.48 re-creates a deleted origin/HEAD on fetch → 3 test setups pinned (`followRemoteHEAD=never`); CI green on all three jobs.
- Caught my own hang: the Matrix config walk looped forever on a relative path (`dirname .` = `.`) — fixed + regression test; also one awk pass instead of ~10 processes per doc (<0.1 s on a real repo). First CI push failed on YAML (`: ` in a plain scalar) — fixed; now parsed locally before push.
- PR #3 updated (243 checks). Still blocked on the user: live test (G1.7), repo visibility, PR #3 reviewer, org Owner.
- **Process improvement:** parse workflow/YAML files locally (`python3 -c 'import yaml…'`) and run the suite on Linux (local `debian:stable-slim`) before pushing CI changes — none codified (one-off).
- **Next session:** process the filled `docs/live-test.md` (incl. 5b resume) → fix findings; or, once decided, G4.1 marketplace PR.

---

## Session 7 — 2026-11-08 — G3.5 commit guard, live-test kit, rollout prep

- Plan to the goal: ~3–5 build sessions left + 1–2 week pilot (≈4–5 weeks at 2–3 sessions/week); the critical path is external — test machine, PR #3 reviewer, org Owner, pilot team.
- G3.5 done: `hooks/pre-tool-use.sh` (PreToolUse on Bash) dry-runs `git add` / reads staged new files → `neverCommit` deny, stray working files ask, source silent. 53 tests, mutation-checked (survivors were dead code, removed); 155 total, plugin validates.
- G1.7 kit: `docs/live-test.md` (~30 checks incl. guard, latency, MGA-83 Figma prompts) for the user to run on the test machine and paste back.
- G4.1 prepared on local branch `add-platform-guardian` in the marketplace clone (1.6.0, README, CHANGELOG; validates; not pushed). G4.2 JSON + Owner steps in `docs/rollout.md`, verified against the official org-plugins doc.
- Open decisions (user): Guardian repo is PRIVATE while marketplace + 6 plugins are public — private breaks credential-less installs; PR #3 reviewer; org Owner; OK to push the marketplace PR after #3 merges.
- **Process improvement:** launch long test loops (mutation runs) with `run_in_background` from the start — none codified (one-off).
- **Next session:** process the filled `docs/live-test.md` → fix findings (+ G2.3 adapters if resume probes proved unreliable).

---

## Session 6 — 2026-11-08 — G1–G3 built, all six org plugins mapped, one consolidated PR

- G1 opener: `scripts/git-status.sh` (JSON vs. central branch, bounded fetch, NUL-safe, bash 3.2, no jq, fails open), `scripts/session-log.sh` (local notes, never in git), SessionStart hook, `session-opener` skill — fires on ANY first message, no trigger word.
- G2 router: 5 parallel agents mapped the org plugins (latest `main`) + matrix-studio → `routing/routes.json` (12 intents, human-only list — only Matrix enforces it itself, MGA-78), `work-router` skill, `scripts/check-routes.sh` drift guard (47 refs OK).
- G3 closer: real-token session-length hook (120k, +40k) with concrete how-to steps; `session-closer` skill (hygiene → commit → push → PR, never to central / never force); `committed-artifacts.json`; QA repos whose plugin hooks block Claude's git writes → commands handed to the employee.
- Decisions: specs → `docs/specs/<feature-slug>/`; all six org plugins bundled (QA team uses both QA plugins; router picks mobile/TV vs web from the task). README rewritten. MGA-78..83 logged.
- Shipped as one PR #3 (`platform-guardian-v0.1` → master); #1/#2 closed as superseded. 102 tests, mutation-checked; `claude plugin validate .` passes. Not yet live-tested.
- **Process improvement:** every user-facing text (hook messages, instructions) gets an exact-content + empty-stderr test — "it fired" isn't enough (the backtick bug slipped through). Memories added: one PR at end, close-out gives steps, Guardian independent of personal rituals.
- **Next session:** G1.7 live test on the test machine (hooks fire on startup + `/clear`, latency with a real remote, MGA-83 Figma prompts) → fix findings → G4.1 marketplace PR (ask first).

---

## Session 5 — 2026-11-08 — Ecosystem refresh, goal redefined, G0 done

- Re-cloned 6 OnOAppsDev repos (main = latest everywhere) and diffed vs July with 6 parallel agents: 22 baseline gaps closed/obsolete, 11 partial, 12 new (MGA-66..77) — `docs/ecosystem-status-2026-11.md`. The plugins now own phase gates, standards, QA readiness and CLAUDE.md, so the July MCP plan was archived to `archive/2026-07-mcp-plan/`.
- New goal (`docs/vision.md`): Guardian = the single plugin employees install and the coordinator into the org plugins — git-hygiene opener → intent routing → close-out with commit/PR and an explicit `/clear`.
- Git policy (user): central branch per project (usually `develop`, ask if unsure); never push to it without a PR; behind → ⚠️🚨 warn, employee decides. Guardian ships its own open/close (not the personal session-rituals): close = local session log (never in git) + plain summary + `/clear`; stray files Claude creates → `.gitignore` unless on the org plugins' committed-artifacts allowlist (G3.4/G3.5).
- Verified in official docs: plugin `dependencies` (bundle) + managed `enabledPlugins` make "install one plugin" native; mods expose context % but need Claude Code ≥ ~2.1.290 (local 2.1.280). Skeleton `.claude-plugin/plugin.json` 0.1.0 depends on the 4 core Ono plugins; validates.
- Open: Matrix plugins for everyone or Matrix projects only? Who is the claude.ai org Owner (G4)? Session 4 entry is missing from this log (backlog cites it for SC-2). Never install Guardian on this machine — local tests only.
- **Process improvement:** never fill identity fields from session context — codified in memory `no-personal-account.md`.
- **Next session:** G1 — `scripts/git-status.sh` + SessionStart hook + session-opener skill, tested against throwaway git repos (G1.1–G1.5 in `docs/backlog.md`).

---

## Session 3 — 2026-07-08 — Marketplace audit, architecture decisions, work plan finalized

- Cloned all 5 marketplace repos into `~/Projects/OnO Marketplace/`. Ran a two-pass agent workflow (5 parallel deep-readers + adversarial verifier) — found 47 gaps, 15 critical. Key finding: all iOS, Android, and React standards are empty placeholders on both main and the unmerged branch; 5 TV platforms have zero plugin coverage.
- Resolved SC-1 (org vs. project-level settings): three-layer model — Org (Repo B, universal standards) / Project (`.platform-guardian/`, Figma file IDs, cross-platform specs) / Platform (individual code repos). Feature specs do not go into Repo B.
- Defined two new Platform Guardian tools: `guardian_check_design_currency` (Phase 1 pre-development hard block if Figma/spec missing or stale) and `guardian_run_design_audit` (living design fidelity report per feature/sprint, living in `.platform-guardian/design-audit.md`).
- Updated `docs/backlog.md` (47 MGA gaps, M1.9, M2.7, Milestone 3.6 TV coverage) and `docs/gantt-gantpro.csv` (two parallel tracks, project end date 2026-10-12). Gap audit written to `docs/marketplace-gap-audit.md`.
- **Process improvement:** Added "scan → workflow" rule to memory: any session involving a multi-repo or multi-file scan must propose a workflow before any solo reads begin. Fire this check at Step 4 of the opening ritual, before focus options are presented.
- **Next session:** SC-2 (auto-review agent decision) + Trello board setup (Make integration or manual) → then M0.1 git init to open the implementation track.

---

## Session 2 — 2026-07-08 — Work plan, backlog, and Gantt

- Created `docs/backlog.md`: ~35+ sessions across 7 milestones — Standing Checks, Foundation, MCP Server MVP (8 items), Audit Engine (6), CLI+DX (3), Marketplace Gap Audit (3, pending access), Org Knowledge (6+), Integration & Pilot (5).
- Added Milestone 3.5 (Marketplace Gap Audit) after user confirmed they will grant marketplace repo access; M4 scope is marked TBD pending audit findings — empty plugins will be sized and assigned after MGA-3.
- Created `docs/gantt.html`: 12-week standalone HTML Gantt with two parallel tracks (Technical + Marketplace/Content), today marker on W1, pending-access stripes for unscoped items.
- Added English-only language rule to `~/.claude/CLAUDE.md` — was empty; rule was missing and caused mid-session correction when I mirrored user's Hebrew.
- **Process improvement:** At session open Step 2–3, if `~/.claude/CLAUDE.md` is empty, prompt user for standing org-level communication rules before proceeding.
- **Next session:** Grant marketplace repo access → run gap audit (MGA-1/2/3) → refine M4 scope and session count → update Gantt with findings.

---

## Session 1 — 2026-07-07

**Focus:** System design and documentation — session 0 (no prior state)

- Defined full system architecture: Platform Guardian plugin (Repo A) + Company Marketplace as org knowledge source. Plugin is MCP server installed per developer; Marketplace is queried automatically at every session start.
- Specified 7 sequential workflow phases with explicit gate conditions, human approval gates (Phase 4 requires PM + Tech Lead), and an emergency bypass protocol for production incidents only.
- Defined 13 knowledge domains required in the Marketplace: Design System, Product Spec, Architecture, Dev Guidelines, AI Rules, Platform Constraints, QA, Release/CI-CD, Security, Performance Budgets, Localization, Monitoring, API Contracts.
- Resolved all governance decisions: Repo A — owner + 1 reviewer per PR; Marketplace — domain owner approves publish + 1 reviewer; Marketplace versioning — semantic with tiered developer response (Major blocks, Minor warns + re-check, Patch notifies).
- Delivered interactive HTML (`docs/process-overview.html`) with 7 tabs: Overview, Workflow Phases, Knowledge Domains, Platforms, Rules Engine, Repo Structure, Governance, How It Works.

**Additional context (end of session):**
- User is on Claude for Organizations. Org-level settings should be defined for the entire org — not just per-project. Critical rules (no bypass of security gates, no direct commit to main, mandatory Platform Guardian onboarding before feature work) belong in the org-level system prompt so no individual developer can override them. These are separate from project-level CLAUDE.md. Define: what is org-absolute (cannot be overridden by any CLAUDE.md or developer instruction) vs. what is project-configurable. This needs a dedicated session.
- User requested a persistent auto-review agent that checks every response before delivery. Honest assessment: Claude Code has no mechanism for a true independent agent to intercept responses in real-time. What IS buildable: (1) a UserPromptSubmit hook that injects a self-review instruction before every prompt, (2) a commitment to invoke peak-quality or spawn an adversarial Agent for all significant architectural decisions, (3) a global CLAUDE.md rule enforcing this. This is the practical maximum. A truly independent reviewer requires a separate Claude invocation per response — expensive but possible via hooks. Decide in next session whether the value justifies the cost.

**Process improvement:** Run opening ritual at session start — confirm language (English) before any work. Don't wait for user to correct mid-session.

**Next session:** Work plan + timeline + backlog. Also: (1) define org-level vs. project-level Claude settings, (2) decide auto-review agent approach and implement it. Pilot platform recommendation: iOS Mobile.

---
