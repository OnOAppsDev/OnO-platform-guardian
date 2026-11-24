<div align="center">
  <h1>OnO Platform Guardian</h1>
  <p><strong>One plugin to install. One place to start. The right Ono process every time.</strong></p>

  ![Status](https://img.shields.io/badge/status-pilot%20prep-yellow?style=flat-square)
  ![Version](https://img.shields.io/badge/version-0.5.2-blue?style=flat-square)
  ![Org plugins](https://img.shields.io/badge/org%20plugins%20bundled-3-green?style=flat-square)
  ![Claude Code](https://img.shields.io/badge/Claude%20Code-plugin-orange?style=flat-square)
</div>

---

> **Platform Guardian** is the single Claude Code plugin Ono employees install. It opens every session with a safe git state, asks what you're working on, routes you into the right Ono plugin process, and closes the session cleanly — commit, PR, session note, `/clear`. It doesn't replace the org plugins; it connects you to them.

---

## 🤔 Why

The org's Claude Code plugins — dev pipeline, QA, repo inspection — each have their own commands, prerequisites and approval steps. Employees had to know which plugin to install, which command starts what, and what state their branch was in. Guardian removes that guesswork.

## 🔄 A session with Guardian

```
claude ──► 1. OPEN       on your first message (any message): git report vs. the central branch · "last time you stopped at …"
             │           unfinished work in the plugins' documents → "login: 2/5 tasks, next T3"
             │           ⚠️🚨 behind central? → you choose: merge / rebase / continue
             │           on the central branch? → create a work branch
             ▼
           2. ROUTE      "Bug, feature, tests? Tell me what we're doing."
             │           → the right Ono plugin command (or resume where you stopped)
             ▼
           3. WORK       the org plugin's own process, as its owners designed it
             │           approvals stay yours — Guardian never self-approves
             ▼
           4. CLOSE      in progress: log + optional checkpoint commit · finished: commit → readiness check (dev plugin's review + pre-PR) → push → PR (never straight to central)
                         local session note · plain summary · "type /clear"
```

Long session? Once the context passes ~120k tokens, Guardian suggests closing at the next natural point.

**First time?** 🎉 Your first session after installing opens with a welcome and an interactive 3-minute tour of how to work with Guardian (offered once; type **onboarding** any time to take it again).

## 🧭 What gets routed where

| You say… | Plugin | Starts with |
|---|---|---|
| new feature / screen | `ono-mobile-dev-plugin` | `/analyze-feature` |
| fix a bug | `ono-mobile-dev-plugin` | `/analyze-bug <KEY>` |
| continue a task | `ono-mobile-dev-plugin` | `/implement-task` |
| review my code | `ono-mobile-dev-plugin` | `/review-code`, `/review-security` |
| hand off to QA · release | `ono-mobile-dev-plugin` | `/create-dev-qa-notes` · `/prepare-mobile-release` |
| QA — mobile / TV | `ono-plugin-qa` | `/create-qa-test-plan` |
| sync the app theme from Figma | `ono-mobile-dev-plugin` | `/rn-sync-figma-theme <figma-url>` |
| onboard me to this repo | `ono-project-inspector` | `/inspect` |

The full map — pipelines, prerequisites, resume probes — is data: [`routing/routes.json`](routing/routes.json).

**Human-only steps** (`/approve-qa-test-plan`, `/qa-signoff`, `/inspect-approve`, `/verify-fix-cycle`, approval status edits, …): Guardian stops and tells you exactly what to type. It never runs them for you.

## 🔐 Git rules Guardian follows

- **Central branch per project** (usually `develop`): `.platform-guardian.json` override → the employee's own earlier answer (kept on their computer) → `origin/HEAD` (when that's `main`/`master` beside a `develop` and master has no commits of its own except release merges → `develop`) → `develop` → `main` → `master`. Unsure → it asks once per repo, remembers the answer on the employee's computer, and offers to save it for the team. When the first message is read-only (a PR review, a question), git questions wait until work that writes files starts.
- **Never pushes to the central branch.** Everything goes back through a PR; it asks before every push or PR, and you pick the target and reviewers.
- **Never updates your branch silently** and never uses force operations.
- **Offline?** The server check gives up after 5 seconds, and Guardian tells you the numbers may be out of date instead of calling you "up to date".
- **Code goes into a commit, plus the documents the PR needs** — in every flow. Documents, data and plugin working files (`.md`, `.json`, `.yaml` …, task state, reports) stay out — on disk, not `.gitignore`d — unless the employee asks for a file or the project lists it in `.platform-guardian.json` `"commitPaths"`. Two exceptions go in with the code: the inspector's outputs, and the dev plugin's planning and review documents (Feature Analysis, DD, Task Breakdown, Dev Plan, bug report + plan, review records), which its PR-readiness check requires (dev plugin 0.8.0+). Secrets never. A guard enforces it on every `git add` / `git commit`.
- **⛔ Inspect gate — every project is inspected first.** If the project hasn't been through the Ono Project Inspector (`AUDIT.md` + `CLAUDE.md` + `docs/project/*`), Claude is blocked in it: a red ⛔ banner on every message and Ono plugin command, until the employee runs `/ono-project-inspector:inspect` — or, only with a manager's approval, types the exact sentence `I have manager approval to work without inspect` (opens the repo for that day). The inspector's outputs are committed so the whole team shares one inspection.
- **Bug reports:** something broken in the tools? "report a bug" → one organized file (exact error, steps, versions of Guardian + every Ono plugin) for the maintainer to triage — outside the repo, never committed.
- **No forced commit or PR at close:** mid-work closes save a note (and a checkpoint commit only if the employee wants one, only when code changed); the readiness check, push and PR come when the bug or feature is finished.
- **PRs waiting for your review:** at session start (with `gh` logged in) the opener lists open PRs where the employee was asked personally to review and offers them as a focus — the dev plugin's `/review-pr ‹URL›` reviews any of them straight from GitHub, with no checkout. `PG_REVIEWS=off` turns it off.
- **Project docs freshness:** a free git check at session start (`inspect-status.sh drift`) — when `CLAUDE.md` / `docs/project/` are meaningfully behind the code, one line a day offers the inspector's **Refresh Project Knowledge** as a separate `chore/` branch + PR. Never automatic (it costs tokens).
- **Per-OS tool lines:** an unsupported or missing Node.js (one line for the dev plugin and the inspector together; with Inspector 0.12.0+ its own Node.js preflight decides) or a missing `jq` (only for a dev plugin older than 0.8.0) → one ⚠️ line with this computer's install command (Windows: `winget`). An inspector older than 0.12.0 without Bun → "update the inspector" (0.12.0+ runs on Node.js), never "install Bun". No inspector installed → no inspector line. If the start-up check runs long (a slow Windows computer), it skips the optional checks and says so, so the git report and the warnings aren't lost with them.
- **PR-readiness before every PR:** before pushing finished Ono work, the closer asks the dev plugin (`scripts/dev-plugin.sh readiness` → its `ono-pr-readiness` contract v1) whether the internal review and the pre-PR check (`/ono-mobile-dev-plugin:pre-pr`, a one-page PDF of what to test) are done and the required documents committed. Not ready → it shows why and offers the next command; ready → the PR gets the plugin's generated description. Guardian runs no pre-PR of its own. Repos without the dev plugin aren't blocked.
- **QA repos:** both QA plugins block Claude's own commits there by design — Guardian hands you the commands to run instead.

## 🚀 Install

```
/plugin marketplace add OnOAppsDev/ono-plugin-marketplace
/plugin install platform-guardian@ono-plugin-marketplace
```

Then, once: `/plugin` → **Marketplaces** → **ono-plugin-marketplace** → **Enable auto-update** — so Guardian and the three plugins update by themselves (auto-update is off by default for org marketplaces). Org-wide, the Owners turn it on for everyone: [`docs/org-setup.md`](docs/org-setup.md).

Installing Guardian installs the three org plugins it depends on. Needs Claude Code **2.1.140 or newer** (`claude --version`; `claude update`). For org-wide rollout, admins enable it through Claude for Organizations managed settings — exact JSON and steps in [`docs/rollout.md`](docs/rollout.md).

**New here?** The one-page employee guide — install + everyday use: [`docs/employee-guide.md`](docs/employee-guide.md).

Testing it for the team? Follow [`docs/tester-guide.md`](docs/tester-guide.md) — it uses this same install.

Optional per-project config: [`docs/project-config.md`](docs/project-config.md).

## 🗂️ Repository

```
.claude-plugin/plugin.json      manifest + dependencies on the three org plugins
hooks/                          SessionStart (open) · UserPromptSubmit + UserPromptExpansion (inspect gate, routing reminder, session length) · PreToolUse (commit guard)
skills/                         session-opener · work-router · session-closer · onboarding · report-bug
scripts/git-status.sh           JSON git report (bash 3.2, no jq, fails open)
scripts/session-log.sh          local session notes — ~/.claude/platform-guardian/, never in git
scripts/inspect-status.sh       inspect gate: done / partial / missing / on-central / override (manager-approved, per day)
scripts/bug-report.sh           bug-report helper: versions + git facts, report path outside the repo
scripts/resume-state.sh         unfinished work from the plugins' own documents (docs/resume-state.md)
scripts/check-routes.sh         drift guard: routes.json vs. the org plugins
scripts/fetch-org-plugins.sh    clone every plugin the marketplace lists (for check-routes / CI)
scripts/live-test-setup.sh      test-machine setup for the live test (docs/live-test.md)
scripts/check-version-bump.sh   CI: plugin files changed → version must go up (installs update only then)
scripts/report-drift.sh         CI: daily drift → one GitHub issue, closed when back in sync
routing/                        routes.json · committed-artifacts.json
tests/run-all.sh                tests against throwaway git repos
.github/workflows/ci.yml        tests on macOS bash 3.2 + Linux · version-bump check on PRs
.github/workflows/drift.yml     daily: org plugins vs. routes.json → issue to the maintainer
docs/                           vision · backlog · ecosystem status · project config · rollout · session log
docs/employee-guide.md          one-page guide for employees: install + everyday use
docs/tester-guide.md            one-page guide for whoever runs the live test → fills docs/live-test.md
docs/org-setup.md               one-page guide for the org Owners: turn Guardian + auto-update on for everyone
archive/2026-07-mcp-plan/       the superseded July MCP / 7-phase plan
```

## 🧪 Develop

```bash
tests/run-all.sh                                    # needs git + jq (jq is test-only)
scripts/fetch-org-plugins.sh /tmp/ono && scripts/check-routes.sh /tmp/ono --strict   # CI runs this weekly
claude plugin validate .
```

## 📊 Status

| Milestone | State |
|---|---|
| G0 Reset — vision, skeleton, feasibility | ✅ |
| G1 Session opener | ✅ built · simulated end-to-end · live test on a tester's machine pending (G1.7) |
| G2 Router | ✅ built · scripted resume across the org plugins (G2.3) |
| G3 Session closer | ✅ built · commit guard (G3.5) |
| G4 Rollout — marketplace, managed settings, pilot | ✅ in the org marketplace · ⏳ live test, managed settings, pilot |

Details: [`docs/backlog.md`](docs/backlog.md) · ecosystem gaps: [`docs/ecosystem-status-2026-11.md`](docs/ecosystem-status-2026-11.md).

## 👥 Team

| Person | Role | Responsibility |
|---|---|---|
| **Tom Zion** | Dev Lead | Platform Guardian (this repo) |
| **Magen Yadid** | CTA | Plugin marketplace + mobile dev plugin — domain owner |
| **Yagil Cohen** | AI Champion | Project inspector plugin — domain owner |
| **Arditi** | QA Lead | QA plugin (`ono-plugin-qa`) — domain owner |

---

<div align="center">
  <sub>Built for OnO · Runs in Claude Code</sub>
</div>
