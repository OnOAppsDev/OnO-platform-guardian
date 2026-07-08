# Session Log — Platform Guardian

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
