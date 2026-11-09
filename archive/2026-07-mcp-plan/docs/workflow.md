# Workflow Phase Specification

## Overview

Platform Guardian enforces 7 sequential phases for every project. A project cannot enter Phase N
without completing Phase N-1. Gate conditions are checked programmatically by the plugin.

The only exception is a logged emergency bypass (Phase 5 only, production incidents only),
which notifies the Tech Lead immediately and creates an audit record.

---

## Phase 0 — Environment Setup

**Purpose**: Verify the developer's environment before any project work begins.

**Gate Conditions (must all be true):**
- Claude Code version meets minimum requirement
- Platform Guardian MCP server is running and responding
- Network access to Org Knowledge Repository is verified
- Developer has read access to Repo B

**Actions:**
1. Check Claude Code version against minimum requirement
2. Ping MCP server health endpoint
3. Attempt read access to Org Knowledge Repo (git ls-remote or API)
4. Clone/pull latest org knowledge to local cache
5. Validate local cache integrity

**Outputs:**
- `environment-validation.json` — results of all checks
- Local cache of Org Knowledge (read-only copy)

**Blocking conditions:**
- MCP server unreachable: cannot proceed, fix plugin installation
- Org Knowledge Repo unreachable: cannot proceed, check network/credentials
- Claude Code version too old: update required

---

## Phase 1 — Project Registration

**Purpose**: Register the project with its platform type and link it to the org knowledge system.

**Gate Conditions:**
- Phase 0 complete
- Platform type exists in `org-knowledge/platforms/`
- Project repository is accessible

**Actions:**
1. Prompt developer to confirm project name and platform type
2. Validate platform type against `org-knowledge/platforms/` directory
3. Load platform-specific constraints and capability matrix
4. Create `.platform-guardian/project-config.yaml`
5. Create `.platform-guardian/` directory (gitignored by default — team decision needed)

**Outputs:**
- `.platform-guardian/project-config.yaml` with phase tracking
- Platform constraints loaded into session

**Blocking conditions:**
- Platform type not in Repo B: block and direct to PM to register platform
- Project config already exists with different platform: warn and confirm before overwriting

---

## Phase 2 — Initial Audit

**Purpose**: Systematically compare the existing codebase against all org specs. Surfaces every
deviation and creates the baseline for the project. This must be thorough — not a sampling.

**Gate Conditions:**
- Phase 1 complete
- Codebase is not empty (has actual source files)
- Org specs for this platform are present in Repo B

**Audit Scope:**

| Domain | What to Check | Source in Repo B |
|--------|--------------|-----------------|
| Design System | Component usage, token values, theme implementation | design-system/ |
| Architecture | State management, routing, network layer patterns | architecture/ |
| Dev Guidelines | File naming, folder structure, code style | dev-guidelines/ |
| AI Rules | Evidence of previous Claude usage patterns | ai-rules/ |
| QA | Test file presence, coverage tooling setup | qa-process/ |
| Security | Auth token storage, API key handling | security/ |
| Performance | Bundle configuration, lazy loading setup | performance/ |
| Monitoring | Analytics initialization, logging setup | monitoring/ |

**Outputs:**
- `.platform-guardian/audit-report.md` with three sections:
  - `## Critical` — must acknowledge before Phase 3
  - `## Warnings` — should fix, tracked
  - `## Informational` — FYI only

**Blocking conditions:**
- Critical audit items must be explicitly acknowledged (not fixed, just acknowledged)
- Acknowledgement requires developer + PM sign-off stored in `phase-state.json`
- Without acknowledgement, Phase 3 cannot begin

---

## Phase 3 — Architecture Analysis

**Purpose**: Create a complete map of the current technology stack and explicitly document any
deviations from org architecture decisions. Undocumented deviations are not allowed.

**Gate Conditions:**
- Phase 2 complete
- Audit critical items acknowledged by developer + PM

**Analysis Scope:**
- All package.json / Podfile / build.gradle dependencies
- State management approach (Redux, MobX, Context, etc.)
- Navigation solution
- Network/HTTP layer
- Data persistence (local storage, cache, DB)
- Build tooling and CI configuration
- Testing framework and setup

**Deviation Documentation:**
Each deviation from org architecture must have:
```yaml
deviation:
  pattern: "Using MobX instead of org-standard Redux"
  location: "src/store/"
  reason: "Pre-existed org standard — migration planned for Q3"
  owner: "Tech Lead Name"
  migration_plan: "Gradual migration to Redux Toolkit, ticket #1234"
```

**Outputs:**
- `.platform-guardian/architecture-map.md`
- Deviation log (embedded in architecture-map.md)
- Forbidden patterns list (fed directly into Phase 4 / CLAUDE.md generation)

**Blocking conditions:**
- Any deviation without a documented reason blocks Phase 4
- Developer must explicitly document WHY, not just what

---

## Phase 4 — Rules Definition

**Purpose**: Generate the CLAUDE.md for this project. This is a human-collaborative phase —
the plugin generates a draft, but humans review and approve before anything is finalized.

**Gate Conditions:**
- Phase 3 complete
- All deviations documented with reasons
- PM and Tech Lead are available for review (synchronous human gate)

**Generation Process:**
1. Load CLAUDE.md template from Repo A
2. Fill with platform constraints from `org-knowledge/platforms/{{platform}}/`
3. Add forbidden patterns from Phase 3 deviation log
4. Add approved dependency list from `org-knowledge/architecture/approved-libraries.md`
5. Add required testing patterns from `org-knowledge/qa-process/`
6. Add security requirements from `org-knowledge/security/`
7. Present draft to developer for review
8. Schedule and conduct review with PM + Tech Lead
9. Store approval with approver identity and timestamp

**This phase cannot be automated.** The plugin can generate the draft, but approval requires
a human reading and signing off. There is no bypass.

**Outputs:**
- `CLAUDE.md` (project root)
- `.platform-guardian/phase-state.json` updated with approval record

---

## Phase 5 — Development Mode

**Purpose**: Active feature development with all guardrails enforced. This is the ongoing,
recurring phase that runs for every feature built on the project.

**Gate Conditions (project-level, checked once):**
- Phase 4 complete and CLAUDE.md approved

**Per-Feature Gate Conditions (checked before each feature):**
- Feature spec exists in `org-knowledge/product-spec/{{platform}}/`
- UI design assets exist in `org-knowledge/design-system/` (if UI work)
- All required libraries are in approved list
- Target platform supports the feature (check capability matrix)

**Ongoing Enforcement:**
- Every Claude action is validated against CLAUDE.md before execution
- Library imports checked against approved list
- Commit hooks verify test coverage threshold
- Analytics events validated against `org-knowledge/monitoring/event-taxonomy.md`

**Per-Feature Process:**
```
1. Developer: "I want to build [feature X]"
2. Plugin: Check feature in product-spec/
   → Not found: BLOCK — direct to PM
   → Found: continue
3. Plugin: Check design in design-system/ (if UI)
   → Not found: BLOCK — direct to Design Lead
   → Found: continue
4. Plugin: Check platform capability matrix
   → Not supported: BLOCK — explain constraint
   → Supported: continue
5. Claude: Implement following CLAUDE.md rules
6. Plugin: Monitor all actions against CLAUDE.md
7. Plugin: Enforce test coverage on commit
```

---

## Phase 6 — Release Preparation

**Purpose**: Cross-platform coordination and release compliance verification.

**Gate Conditions:**
- Phase 5 complete for all features in release scope
- QA sign-off obtained for this platform
- No open critical blockers

**Cross-Platform Checklist (checked for each platform in release):**
- All features in release scope work as expected
- Feature parity verified against platform capability matrix
- Performance budgets met (especially critical for TV platforms)
- Analytics events firing correctly
- Error tracking verified

**Outputs:**
- Release compliance report
- Cross-platform consistency notes
- Release notes draft (generated from product-spec entries)

---

## Emergency Bypass Protocol

For production incidents ONLY. Does not skip Phase 4 approval.

```bash
guardian emergency-bypass \
  --reason "Production crash: video player crash on Tizen, ticket #999" \
  --ticket "PROD-999" \
  --approver "tech-lead-email@company.com"
```

This:
1. Logs the bypass with reason, ticket, and requester identity
2. Immediately notifies Tech Lead via configured channel
3. Creates a follow-up task to remediate within 48 hours
4. Does NOT allow skipping Phase 4 or CLAUDE.md approval
