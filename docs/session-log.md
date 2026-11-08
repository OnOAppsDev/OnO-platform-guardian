# Session Log — Platform Guardian

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
