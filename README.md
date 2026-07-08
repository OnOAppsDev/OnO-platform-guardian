<div align="center">
  <img src="assets/yes-logo.png" alt="yes+" width="170">
  <h1>Platform Guardian</h1>
  <p><strong>AI-enforced development governance for the yes+ multi-platform product</strong></p>

  ![Status](https://img.shields.io/badge/status-in%20development-yellow?style=flat-square)
  ![Platforms](https://img.shields.io/badge/platforms-7-blue?style=flat-square)
  ![Claude Code](https://img.shields.io/badge/Claude%20Code-MCP%20Plugin-orange?style=flat-square)
  ![Workflow Phases](https://img.shields.io/badge/workflow%20phases-7-purple?style=flat-square)
  ![Repos](https://img.shields.io/badge/org%20repos-5-green?style=flat-square)
</div>

---

> **Platform Guardian** is a Claude Code MCP plugin that enforces consistent, gated development workflows across all yes+ platform teams — connecting every developer to the company's shared plugin ecosystem and knowledge base before any code is written.

---

## 🤔 The Problem

yes+ ships on **7 platforms**, developed by separate teams, all using Claude Code. Without governance:

| Issue | What actually happens |
|---|---|
| 🔀 No single source of truth | Each developer defines "correct" differently per session |
| 🏗️ Undocumented architecture decisions | Patterns diverge silently across iOS, Android, and TV |
| 🤖 Claude works from session context only | Inconsistent code generation every time a new chat opens |
| 🎨 Design and spec drift go undetected | Features ship misaligned with Figma without anyone noticing |
| 🧩 New developers have no baseline | No structured onboarding — months to reach production quality |
| 📺 TV platforms have zero tooling coverage | No standards, no agents, no skills for 5 of 7 platforms |

---

## ✅ The Solution — One Enforced Workflow Across Seven Repos

Platform Guardian doesn't read from a single source. It connects to the **entire yes+ org plugin ecosystem** — reading from all relevant repos based on the context of each task.

### The yes+ Plugin Ecosystem

| Repo | What it does | Used when |
|---|---|---|
| 🏪 [ono-plugin-marketplace](https://github.com/appsadmin-design/ono-plugin-marketplace) | Registry of all approved org plugins | Always — Platform Guardian validates plugin versions and registry state |
| 📱 [ono-mobile-dev-plugin](https://github.com/appsadmin-design/ono-mobile-dev-plugin) | Dev workflow for Mobile: standards, agents, skills, pipeline for iOS / Android / RN / React | Feature development on any mobile platform |
| 🔍 [ono-plugin-project-inspector](https://github.com/appsadmin-design/ono-plugin-project-inspector) | Project audit engine and state machine | Phase 2 (Initial Audit) and Phase 3 (Architecture Analysis) |
| 🧪 [ono-plugin-qa](https://github.com/appsadmin-design/ono-plugin-qa) | QA coverage analysis, Figma validation, test plan tooling | Phase 6 (Release Preparation) and ongoing QA gates |
| 📐 [spec-team-toolkit](https://github.com/appsadmin-design/spec-team-toolkit) | HLD/LLD spec building, Figma-to-spec tooling | Phase 1 (Project Registration) — verifying specs exist before development |
| 📚 **Org Knowledge Repo** _(to be created)_ | Universal org standards: design tokens, approved libraries, security rules, forbidden patterns | All phases — read-only enforcement source. Not a plugin. A prerequisite. |
| 🛡️ **This repo** — Platform Guardian | Enforcement layer: phase gates, cross-repo validation, enforcement hook | Always installed — orchestrates all of the above |

```
Developer + Claude
        │
        ▼
┌───────────────────────────┐
│    Platform Guardian      │  ← you are here
│  Checks: phase gates,     │
│  spec exists, Figma       │
│  current, dep approved    │
└───────────┬───────────────┘
            │ reads from, based on context
    ┌───────┼───────┐
    ▼       ▼       ▼
 Mobile   QA    Spec Team   ...and more
 Plugin  Plugin  Toolkit
    \       |       /
     \      |      /
      ▼     ▼     ▼
   ono-plugin-marketplace (registry)
              +
   Org Knowledge Repo (standards)
```

---

## 📱 Supported Platforms

| Platform | Type | Tooling today | Target status |
|---|---|---|---|
| 📱 **iOS Mobile** | Native Swift / SwiftUI | Standards: empty — Owner: Boris | 🔴 Not ready |
| 🤖 **Android Mobile** | Native Kotlin | Standards: empty — Owner: Guy | 🔴 Not ready |
| ⚛️ **React Native** | Cross-platform | ✅ Fully authored | ✅ Ready |
| 🌐 **React (web)** | React / TypeScript | Standards: empty — Owner: Magen | 🔴 Not ready |
| 🍎 **Apple TV** | tvOS | No coverage at all | 🔴 No coverage |
| 📺 **Android TV** | Android / Compose TV | No coverage at all | 🔴 No coverage |
| 🖥️ **Tizen** | Samsung Smart TV | No coverage at all | 🔴 No coverage |
| 🖥️ **WebOS** | LG Smart TV | No coverage at all | 🔴 No coverage |
| 🖥️ **Vidaa** | Hisense Smart TV | No coverage at all | 🔴 No coverage |

---

## 🔄 Workflow Phases — Sequential, Enforced, Cannot Be Skipped

<div align="center">
  <img src="assets/workflow-phases.gif" alt="Platform Guardian — 7 Workflow Phases" width="900">
</div>

| Phase | Name | What happens | Gate to advance |
|---|---|---|---|
| **0** | 🔌 Environment Setup | Plugin connects, Org Knowledge Repo is verified reachable | Plugin online + Repo B accessible |
| **1** | 📋 Project Registration | Platform type registered. Spec and Figma data checked — must exist and be current | Spec + Figma present and not stale |
| **2** | 🔍 Initial Audit | Codebase compared against org standards. Deviations, missing docs, and forbidden patterns surfaced | Audit acknowledged by developer + PM |
| **3** | 🏗️ Architecture Analysis | `package.json` / Podfile / `build.gradle` scanned. State management, navigation, network patterns mapped. Deviation log produced | Architecture documented |
| **4** | 📐 Rules Definition | CLAUDE.md generated from org template — platform constraints, forbidden patterns, approved deps, QA rules | **⭐ Human gate: PM + Tech Lead approval required** |
| **5** | 💻 Development Mode | Active development. Every Claude action validated against org standards in real time | Feature QA complete, no open blockers |
| **6** | 🚀 Release Preparation | Cross-platform consistency check, CI/CD gate validation, final sign-off | All checks green |

> **Phase 4 is the only phase that requires a human.** PM and Tech Lead must explicitly approve the generated CLAUDE.md before any code is written. This gate cannot be automated and cannot be skipped.

---

## 🛡️ How Enforcement Works

Three layers — each with a different cost and trigger:

---

**Layer 1 — The instant blocker** _(always on, zero tokens, zero cost)_

Before any file write, git command, or terminal action, a lightweight hook checks:
- Is there a Platform Guardian project here? (`.platform-guardian/` folder)
- Is the current workflow phase gate satisfied for this action?

If the answer to either is no → the action is **blocked immediately** with a clear reason. No LLM involved, no cost, no delay. This is the floor — it enforces the rules even when a developer doesn't explicitly invoke anything.

---

**Layer 2 — The quality gate** _(triggers only at phase transitions)_

When a developer advances from one phase to the next, Platform Guardian invokes the right tool for that transition:

- Moving to Phase 2 → runs `/plan` before any implementation
- Moving to Phase 3 → runs `/review` or `/workflow` for the audit
- Moving to Phase 4 → runs `/code-review` before the human gate
- Moving to Phase 6 → runs `/workflow` for CI/CD validation
- Architectural decisions at any phase → runs `/peak-quality`

These run **once per transition**, not on every action. Expensive but infrequent.

---

**Layer 3 — The human gate** _(Phase 4 only, non-negotiable)_

PM and Tech Lead must read and sign off on the generated CLAUDE.md. No automation. No bypass. If they're unavailable, the project waits.

---

## 📚 Org Knowledge Status — What Exists vs. What's Missing

This table reflects the **June 2026 marketplace audit** (47 gaps identified). It shows the honest state of what Platform Guardian can enforce today vs. what needs to be authored first.

### Plugin content — per platform

| Platform | Standards | Agents | Skills | Notes |
|---|---|---|---|---|
| ✅ React Native | 6 complete | 5 complete | 3 complete | Fully ready |
| ❌ iOS | 5 empty placeholders | 4 empty | 3 empty | Owner: Boris. Blocks all iOS gate enforcement |
| ❌ Android | 5 empty placeholders | 4 empty | 3 empty | Owner: Guy. Blocks all Android gate enforcement |
| ❌ React (web) | 6 empty placeholders | 4 empty | 3 empty | Owner: Magen. Also missing XSS/CSRF security coverage |
| ❌ Apple TV | None | None | None | No coverage in any repo. Needs new plugin or major extension |
| ❌ Android TV | None | None | None | No coverage in any repo |
| ❌ Tizen | None | None | None | No coverage in any repo — Samsung-specific APIs required |
| ❌ WebOS | None | None | None | No coverage in any repo — LG-specific APIs required |
| ❌ Vidaa | None | None | None | No coverage in any repo — Hisense-specific APIs required |

### Org Knowledge Repo (Repo B) — doesn't exist yet

The Org Knowledge Repo is **not** a plugin — it's a standalone git repository that Platform Guardian reads to enforce org-wide standards (design tokens, approved library list, security rules, forbidden patterns). It is the single most critical prerequisite before Platform Guardian can enforce anything beyond phase gates.

The structure template is in [`org-knowledge-template/`](./org-knowledge-template/) in this repo.

| Domain | Status | Where it should live |
|---|---|---|
| 🎨 Design System tokens, components, themes | ❌ Not started | Org Knowledge Repo |
| 📄 Product Specifications per platform | ❌ Not started | `.platform-guardian/` project config |
| 🏛️ Architecture decisions, approved libraries, forbidden patterns | ❌ Not started | Org Knowledge Repo |
| 📝 Coding standards (iOS, Android, RN, React, TV) | ❌ Partially in plugins — see above | `ono-mobile-dev-plugin` (after authoring) |
| 🔐 Security & privacy rules | ❌ Not started | Org Knowledge Repo |
| ⚡ Performance budgets per platform | ❌ Not started — critical for TV | Org Knowledge Repo |
| 🌍 Localization, RTL, market rules | ❌ Partial in plugins | `ono-mobile-dev-plugin` |
| 🧪 QA standards, test coverage requirements | ❌ Partial in `ono-plugin-qa` | `ono-plugin-qa` (after authoring) |

---

## 🗂️ Repository Structure

```
yes-platform-guardian/
├── 📦 plugin/                    MCP server (TypeScript — in development)
│   └── src/
│       ├── workflow/             Phase enforcement + gate conditions
│       ├── knowledge/            Org Knowledge Repo connector + cache
│       ├── analysis/             Audit engine + gap analysis
│       └── tools/                MCP tool definitions
│
├── 📋 workflows/
│   └── phases.yaml               Phase and gate definitions
│
├── 📐 templates/
│   ├── CLAUDE.md.template        Per-platform CLAUDE.md starter
│   └── project-config.yaml.template
│
├── 🏛️ org-knowledge-template/    Starter structure for the Org Knowledge Repo
│
└── 📚 docs/
    ├── process-overview.html     Interactive system overview (open in browser)
    ├── plugin-spec.md            Plugin technical specification
    ├── workflow.md               Workflow phase specification
    ├── domains.md                Knowledge domain definitions
    ├── governance.md             Approval and review governance
    ├── backlog.md                Full implementation backlog (~35 sessions)
    └── marketplace-gap-audit.md  Audit of all 5 org plugin repos (47 gaps)
```

---

## 🚀 Getting Started

> **Platform Guardian is in development.** The flow below reflects the intended installation experience once v1.0 ships.

**Step 1 — Add the yes+ marketplace to your Claude Code settings** _(org-wide, one-time setup)_

```json
{
  "extraKnownMarketplaces": {
    "yes-plugins": {
      "source": {
        "source": "github",
        "repo": "appsadmin-design/ono-plugin-marketplace"
      }
    }
  }
}
```

**Step 2 — Install the platform plugins for your team** _(via Claude Code)_

```bash
# For mobile developers (iOS / Android / React Native / React)
/install-plugin ono-mobile-dev-plugin@yes-plugins

# For project inspection and audit
/install-plugin ono-plugin-project-inspector@yes-plugins

# For QA engineers
/install-plugin ono-plugin-qa@yes-plugins

# For spec / design team
/install-plugin spec-team-toolkit@yes-plugins
```

**Step 3 — Install Platform Guardian**

```bash
/install-plugin yes-platform-guardian@yes-plugins
```

**Step 4 — Initialize a new project**

```bash
guardian init
# → Prompts for platform type, Figma file IDs, and org knowledge repo location
# → Creates .platform-guardian/project-config.yaml and phase-state.json
# → Runs Phase 0 checks automatically
```

---

## 📊 Implementation Status

| Milestone | Item | Why it's needed | Status |
|---|---|---|---|
| **Design** | System architecture | The blueprint — without this, nothing else is buildable | ✅ Done |
| **Design** | 7 workflow phases | Defines the enforced sequence every developer must follow | ✅ Done |
| **Design** | 12 knowledge domains | Maps what must exist in Repo B for gates to fire correctly | ✅ Done |
| **Design** | Marketplace gap audit | Identifies exactly what's missing before enforcement can work | ✅ Done |
| **Design** | Enforcement architecture | Defines the 3-layer mechanism (hook, skills, human gate) | ✅ Done |
| **Foundation** | Git repo initialized | Tracks all changes — required before any collaborative work | ✅ Done |
| **Foundation** | PreToolCall enforcement hook | Layer 1 — installed globally, fires before every write/git action | ✅ Done |
| **M0.2** | TypeScript project scaffold | Build system, linter, test runner — the foundation for all plugin code | 🔜 Next |
| **M1** | MCP server + phase engine | The actual plugin — connects to Claude Code and enforces phases | ⏳ |
| **M2** | Audit engine + architecture analyzer | Powers Phase 2 and Phase 3 — the baseline scan for every new project | ⏳ |
| **M3** | CLI + developer experience | `guardian init`, emergency bypass, onboarding docs | ⏳ |
| **M4** | iOS standards, agents, skills | Unlocks all iOS gate enforcement — currently all empty | ⏳ Owner: Boris |
| **M4** | Android standards, agents, skills | Unlocks all Android gate enforcement — currently all empty | ⏳ Owner: Guy |
| **M4** | React web standards, agents, skills | Unlocks React web gate enforcement | ⏳ Owner: Magen |
| **M4** | TV platform coverage (5 platforms) | Tizen, WebOS, Vidaa, Apple TV, Android TV — zero coverage today | ⏳ To scope |
| **M4** | Org Knowledge Repo (Repo B) | The org-wide standard that all enforcement reads from — doesn't exist yet | ⏳ Owner: Tom + PM + Design Lead |

Full backlog with ~35 sessions scoped: [`docs/backlog.md`](./docs/backlog.md)

---

## 👥 Team

| Person | Role | Responsibility |
|---|---|---|
| **Tom Zion** | Dev Lead | Platform Guardian plugin (this repo) — owner + 1 reviewer per PR |
| **Magen Yadid** | CTA | Plugin marketplace + mobile dev standards — domain owner |
| **Yagil Cohen** | AI Champion | Project inspector plugin — domain owner |
| **Arditi** | QA Lead | QA plugin (`ono-plugin-qa`) — domain owner |

**Human approval gate (Phase 4):** PM + Tech Lead must sign off before any feature code is written. Non-negotiable.

Marketplace versioning follows semver: **Major** blocks execution, **Minor** warns + re-checks, **Patch** notifies only.

---

## 🔗 Resources

| Resource | Link |
|---|---|
| 📊 Project Gantt | [`docs/gantt.html`](./docs/gantt.html) — open locally in browser |
| 🗂️ Full Backlog | [`docs/backlog.md`](./docs/backlog.md) |
| 🔍 Marketplace Gap Audit | [`docs/marketplace-gap-audit.md`](./docs/marketplace-gap-audit.md) |
| 🌐 Interactive System Overview | [`docs/process-overview.html`](./docs/process-overview.html) |
| 📋 Trello Board | _Link to be added_ |

---

<div align="center">
  <sub>Built for yes+ · Enforced by Claude Code · Powered by Anthropic</sub>
</div>
