<div align="center">
  <img src="assets/yes-logo.png" alt="yes+" width="170">
  <h1>Platform Guardian</h1>
  <p><strong>One plugin to install. One place to start. The right Ono process every time.</strong></p>

  ![Status](https://img.shields.io/badge/status-pilot%20prep-yellow?style=flat-square)
  ![Version](https://img.shields.io/badge/version-0.2.1-blue?style=flat-square)
  ![Org plugins](https://img.shields.io/badge/org%20plugins%20bundled-6-green?style=flat-square)
  ![Claude Code](https://img.shields.io/badge/Claude%20Code-plugin-orange?style=flat-square)
</div>

---

> **Platform Guardian** is the single Claude Code plugin Ono employees install. It opens every session with a safe git state, asks what you're working on, routes you into the right Ono plugin process, and closes the session cleanly — commit, PR, session note, `/clear`. It doesn't replace the org plugins; it connects you to them.

---

## 🤔 Why

The org has six Claude Code plugins — dev pipeline, two QA plugins, specs, repo inspection, Figma design systems — each with its own commands, prerequisites and approval steps. Employees had to know which plugin to install, which command starts what, and what state their branch was in. Guardian removes that guesswork.

## 🔄 A session with Guardian

```
claude ──► 1. OPEN       on your first message (any message): git report vs. the central branch · "last time you stopped at …"
             │           unfinished work in the plugins' documents → "login: 2/5 tasks, next T3"
             │           ⚠️🚨 behind central? → you choose: merge / rebase / continue
             │           on the central branch? → create a work branch
             ▼
           2. ROUTE      "Bug, feature, tests, spec? Tell me what we're doing."
             │           → the right Ono plugin command (or resume where you stopped)
             ▼
           3. WORK       the org plugin's own process, as its owners designed it
             │           approvals stay yours — Guardian never self-approves
             ▼
           4. CLOSE      commit hygiene → commit → push → PR (never straight to central)
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
| QA — web | `matrix-qa-plugin` | `/qa-plan` (`/qa-init` first in a new repo) |
| write a spec (HLD / LLD / SPAC) | `spec-team-toolkit` | the matching spec skill → saved to `docs/specs/<feature>/` |
| sync the app theme from Figma | `ono-mobile-dev-plugin` | `/rn-sync-figma-theme <figma-url>` |
| Figma design system | `matrix-studio` | the matching skill — full system, colors, spacing or typography |
| onboard me to this repo | `ono-project-inspector` | `/inspect` |

The full map — pipelines, prerequisites, resume probes — is data: [`routing/routes.json`](routing/routes.json).

**Human-only steps** (`/approve-qa-test-plan`, `/qa-approve`, `/qa-signoff`, `/inspect-approve`, `/verify-fix-cycle`, approval status edits, …): Guardian stops and tells you exactly what to type. It never runs them for you.

## 🔐 Git rules Guardian follows

- **Central branch per project** (usually `develop`): `.platform-guardian.json` override → `origin/HEAD` → `develop` → `main` → `master`. Unsure → it asks.
- **Never pushes to the central branch.** Everything goes back through a PR; it asks before every push or PR, and you pick the target and reviewers.
- **Never updates your branch silently** and never uses force operations.
- **Offline?** The server check gives up after 5 seconds, and Guardian tells you the numbers may be out of date instead of calling you "up to date".
- **Commit hygiene:** files the org plugins mean to be committed ([`routing/committed-artifacts.json`](routing/committed-artifacts.json)) are committed; stray session files go to `.gitignore`; secrets never.
- **QA repos:** both QA plugins block Claude's own commits there by design — Guardian hands you the commands to run instead.

## 🚀 Install

```
/plugin marketplace add OnOAppsDev/ono-plugin-marketplace
/plugin install platform-guardian@ono-plugin-marketplace
```

Then, once: `/plugin` → **Marketplaces** → **ono-plugin-marketplace** → **Enable auto-update** — so Guardian and the six plugins update by themselves (auto-update is off by default for org marketplaces). Org-wide, the managed settings below turn it on for everyone.

Installing Guardian installs the six org plugins it depends on. Needs Claude Code **2.1.140 or newer** (`claude --version`; `claude update`). For org-wide rollout, admins enable it through Claude for Organizations managed settings — exact JSON and steps in [`docs/rollout.md`](docs/rollout.md).

Testing it for the team? Follow [`docs/tester-guide.md`](docs/tester-guide.md) — it uses this same install.

Optional per-project config: [`docs/project-config.md`](docs/project-config.md).

## 🗂️ Repository

```
.claude-plugin/plugin.json      manifest + dependencies on the six org plugins
hooks/                          SessionStart (open) · UserPromptSubmit (session length) · PreToolUse (commit guard)
skills/                         session-opener · work-router · session-closer · onboarding
scripts/git-status.sh           JSON git report (bash 3.2, no jq, fails open)
scripts/session-log.sh          local session notes — ~/.claude/platform-guardian/, never in git
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
docs/tester-guide.md            one-page guide for whoever runs the live test → fills docs/live-test.md
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
| G2 Router | ✅ built · scripted resume across all six plugins (G2.3) |
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
  <sub>Built for yes+ · Runs in Claude Code</sub>
</div>
