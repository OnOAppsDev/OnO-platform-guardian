# Platform Guardian — Backlog

Last updated: 2026-07-08

Each item is scoped to one session (~1–3 hours). Dependencies are noted inline.

---

## Standing Checks (resolve before implementation begins)

These are open decisions from Session 1 that block or shape downstream work.

- [x] **SC-1: Org-level vs. project-level Claude settings** — Design the boundary: what is org-absolute (cannot be overridden by any CLAUDE.md or developer instruction) vs. what is project-configurable. Output: a written policy document in `docs/`. Blocks: M1 items that touch CLAUDE.md generation (M1.2, M1.4).
  > **Resolved in Session 3:** The three-layer model is the answer.
  > - **Org level** = Repo B / marketplace: universal standards — coding conventions, approved libraries, design system tokens, security rules, forbidden patterns. Applies to ALL projects. Immutable from any project's perspective.
  > - **Project level** = Platform Guardian config (`.platform-guardian/`): Figma file IDs per platform group, cross-platform feature specs, product-level decisions. Spans multiple platforms. Lives in the project repo.
  > - **Platform level** = individual code repos: actual implementation per platform. Read-write per project.
  > - Feature specs for iOS Mobile, Android TV, etc. do NOT go into Repo B — they are project-level Platform Guardian config. Figma lives at project level (file IDs in `project-config.yaml`).
- [x] **SC-2: Auto-review agent** — Decide approach: (a) UserPromptSubmit hook injecting a self-review instruction, (b) explicit invocation of peak-quality/adversarial Agent for significant decisions only, or (c) skip. If (a): implement the hook in `~/.claude/settings.json`. Blocks: nothing, but should resolve early so it's in place during implementation sessions.
  > **Resolved in Session 4:** Three-layer enforcement architecture.
  > - **Layer 1 — PreToolCall hook** (always-on, zero tokens): fires before Edit/Write/Bash tool calls, reads `.platform-guardian/phase-state.json`, blocks actions not permitted at the current phase. Project-scoped via `.platform-guardian/` presence check — silent no-op on non-PG projects. Hook stub installed at `~/.claude/scripts/guardian-phase-check.sh`; registered in `~/.claude/settings.json`. Wired to real logic in M1.2.
  > - **Layer 2 — Skill invocations at phase transitions** (expensive, infrequent): `/plan` before implementation, `/review` or `/workflow` for audit, `/code-review` before Phase 4, `/peak-quality` for architectural decisions. Called by `guardian_complete_phase` MCP tool (M1.3).
  > - **Layer 3 — Human approval at Phase 4** (non-automatable): PM + Tech Lead sign-off. Already specced.
  > - **Rejected:** global UserPromptSubmit hook — fires on every response, 2× token cost, reviews prose not actions. Wrong enforcement surface.

---

## Milestone 0 — Foundation

Infrastructure before any code is written.

- [ ] **M0.1: Initialize git repository** — `git init`, `.gitignore` (node_modules, dist, .env, `.platform-guardian/cache`), first commit with existing docs. No dependencies.
- [ ] **M0.2: Scaffold TypeScript project** — `plugin/package.json`, `tsconfig.json`, `eslint.config.js`, npm scripts (`build`, `dev`, `test`). Choose test runner (recommend Vitest). Output: `npm run build` succeeds on an empty project. No dependencies.

---

## Milestone 1 — MCP Server MVP

Minimum viable enforcement: phase gates + spec checks. Everything a team needs to block undocumented work.

- [ ] **M1.1: MCP server entry point** — `plugin/src/server.ts`: MCP server setup, health endpoint, tool registration skeleton (stubs that return `{ allowed: false, message: "not implemented" }`). Output: server starts, Claude Code can connect. Depends on: M0.2.
- [ ] **M1.2: Phase state engine** — `workflow/engine.ts` + `workflow/gates.ts`: load/write `phase-state.json`, evaluate gate conditions per phase, return allowed/blocked with reason. Output: unit tests cover all 7 phases. Depends on: M0.2. SC-1 now resolved — three-layer model defines what constitutes an org-level gate vs. a project-level gate.
- [ ] **M1.3: `guardian_check_phase` + `guardian_complete_phase`** — Wire phase engine into MCP tools. Test end-to-end with a dummy project state file. Depends on: M1.1, M1.2.
- [ ] **M1.4: Knowledge connector** — `knowledge/connector.ts` + `knowledge/cache.ts`: clone/pull Repo B to local cache path, TTL-based invalidation, read files by path. Output: can fetch a file from a real git repo URL. Depends on: M0.2. Note: needs a Repo B URL to test against — mock or real org-knowledge-template.
- [ ] **M1.5: Knowledge parser** — `knowledge/parser.ts`: parse the standard domain file formats (markdown tables, YAML frontmatter) into structured objects (e.g. approved-libraries table → `{ library, version, platform, approvedBy }`). Output: unit tests for each domain format. Depends on: M1.4.
- [ ] **M1.6: `guardian_check_spec`** — Check `product-spec/{{platform}}/{{feature}}.md` exists in Repo B. Depends on: M1.4.
- [ ] **M1.7: `guardian_check_dependency`** — Check `architecture/approved-libraries.md` for library + version. Depends on: M1.5.
- [ ] **M1.8: `guardian_check_platform_capability`** — Check `platforms/{{platform}}/capability-matrix.md`. Depends on: M1.5.
- [ ] **M1.9: `guardian_check_design_currency`** — Pre-development design currency gate (Phase 1 gate addition). Before any feature development starts, checks: does spec + Figma data exist and is it current for this feature in the project-level config (`.platform-guardian/`)? If missing or stale → HARD BLOCK. Developer cannot proceed. Spec team notified. Reads Figma file IDs from `project-config.yaml` (platform group → file_id). Owner: Tom. Effort: 2 sessions. Depends on: M1.4. **Planning required before execution.**

---

## Milestone 2 — Audit Engine

Phase 2 audit: the tool that creates the project baseline by comparing the codebase against org specs.

- [ ] **M2.1: Audit engine** — `analysis/auditor.ts`: for each audit domain (8 domains per workflow.md), compare codebase against Repo B spec. Output structured findings (`{ domain, severity, finding, file, recommendation }`). Depends on: M1.5. Note: for any platform where standards are still placeholder ("Not yet authored"), the auditor must skip standard-ID-citation enforcement and surface a `domain_not_yet_populated` result rather than a false failure.
- [ ] **M2.2: Audit reporter** — `analysis/reporter.ts`: take structured findings, write `audit-report.md` with Critical / Warnings / Informational sections. Depends on: M2.1.
- [ ] **M2.3: `guardian_run_audit`** — Wire auditor + reporter into MCP tool. Depends on: M2.1, M2.2.
- [ ] **M2.4: Architecture analyzer** — `analysis/architecture.ts`: scan `package.json` / Podfile / build.gradle, identify state management / navigation / network patterns, produce `architecture-map.md` with deviation log. Depends on: M1.5.
- [ ] **M2.5: `guardian_get_rules` + `guardian_check_design`** — `guardian_get_rules`: read and return project's CLAUDE.md with approval metadata. `guardian_check_design`: check `design-system/components/{{component}}.md` exists. Depends on: M1.4.
- [ ] **M2.6: CLAUDE.md generation** — Phase 4 draft generation: load CLAUDE.md template, fill with platform constraints + forbidden patterns + approved deps + QA rules + security requirements. Output: draft CLAUDE.md ready for human review. Depends on: M1.5, M2.4. SC-1 now resolved — org-level content (Repo B) populates the immutable section; project-level content (`.platform-guardian/`) populates the configurable section.
- [ ] **M2.7: `guardian_run_design_audit`** — Living design fidelity report. Run per feature or per sprint (not per-PR). Compares Figma state (via project-level Figma file IDs in `project-config.yaml`) vs. implemented features vs. spec documents. Output: `.platform-guardian/design-audit.md` — a living document updated continuously. Each deviation gets a status: `Fix` or `Intentional` (with justification). New things appearing in implementation with no spec/design entry trigger a flag. Raises a block if no updated design/spec data exists in the project repo for the feature being developed. Owner: Tom. Effort: 3 sessions. Depends on: M1.9, M2.1. **Planning required before execution.**

---

## Milestone 3 — CLI + Developer Experience

The `guardian init` CLI and emergency bypass command.

- [ ] **M3.1: `guardian init` CLI** — Interactive setup: prompt for project name + platform, validate against Repo B platforms list, create `.platform-guardian/project-config.yaml` (including Figma file IDs per platform group: `tv_platforms`, `mobile_platforms`) + initial `phase-state.json`, run Phase 0 checks. Output: a developer can onboard a new project in < 5 minutes. Depends on: M1.3, M1.4.
- [ ] **M3.2: Emergency bypass command** — `guardian emergency-bypass --reason --ticket --approver`: log bypass with full context, notify Tech Lead (via configured webhook or stdout), create follow-up task in `phase-state.json`. Depends on: M1.2.
- [ ] **M3.3: Developer documentation** — Update README with real installation steps. Add a `docs/getting-started.md` walkthrough for a new developer onboarding their first project. Depends on: M1.3, M3.1.

---

## Milestone 3.5 — Marketplace Gap Audit

*Completed in Session 3. Findings in `docs/marketplace-gap-audit.md`.*

- [x] **MGA-1: Access + structure review** — Cloned all 5 repos: ono-plugin-marketplace, ono-mobile-dev-plugin, ono-plugin-project-inspector, ono-plugin-qa, spec-team-toolkit. Mapped structure and content against plugin requirements.
- [x] **MGA-2: Detailed content audit** — Audited all repos. ono-plugin-project-inspector: complete. React Native in ono-mobile-dev-plugin: complete. iOS/Android/React platforms: skills and agents are placeholders. New branch `feat/design-and-feature-start-stages` (2 new pipeline stages) not yet merged. NOTE: the branch does not deliver any platform standards authoring — all 14 iOS/Android/React standard files remain "Not yet authored" on the branch. See MGA-28.
- [x] **MGA-3: Size empty plugins + assign owners** — See full gap summary in `docs/marketplace-gap-audit.md`. 47 gaps identified across 5 repos plus 11 cross-repo integration gaps and 10 Platform Guardian integration requirements. Adversarial verification pass completed.

### Gap Backlog (findings from MGA-1/2/3)

Items MGA-4 through MGA-10 have been superseded by the full revised gap audit (Session 3). The corrected and expanded gap list follows. Gaps MGA-4 through MGA-65 reflect the adversarial-verified audit document.

---

#### ono-plugin-marketplace gaps

- [ ] **MGA-4: Assign merge decision owner for feature branch** — Assign a named owner and target date for merging `feat/design-and-feature-start-stages` in ono-mobile-dev-plugin. The branch adds `/dev-design-start` and `/dev-feature-start` as a 2-stage replacement for `/create-dev-plan`, a new `dd-template.md`, and updated `rn-architect`. It does NOT deliver any platform standards authoring (all 14 iOS/Android/React standard files remain "Not yet authored" on the branch — see MGA-28). Coordinate the merge with a simultaneous Platform Guardian pipeline-stage map update so both change atomically. Bump `marketplace.json` `ono-mobile-dev-plugin` entry to v0.3.0. Owner: magen + Tom. Effort: 1 session. Severity: High. **Planning required before execution.**
- [ ] **MGA-11: Register Platform Guardian in marketplace** — Add Platform Guardian plugin entry to `ono-plugin-marketplace/marketplace.json` with HTTPS source URL, version, description, and author email. Bump marketplace version to 1.4.0. Update README.md plugin table and CHANGELOG. Owner: Tom. Effort: 1 session. Severity: Critical. Blocked by: M1.1 (plugin code must exist — repo is live at https://github.com/appsadmin-design/yes-platform-guardian). **Planning required before execution.**
- [ ] **MGA-12: Add version pinning to marketplace plugins** — Replace `ref: main` with specific git tags or commit SHAs on all 4 plugin entries. Add a `sha` or `tag` field to the marketplace schema. Document a rollback procedure in the marketplace README. Owner: magen. Effort: 1 session. Severity: High. **Planning required before execution.**
- [ ] **MGA-13: Add CI validation pipeline to ono-plugin-marketplace** — Create a GitHub Actions workflow that validates marketplace.json against the schema, verifies each plugin URL is reachable, and confirms each referenced ref exists. Fails on any unreachable URL. Owner: magen. Effort: 2 sessions. Severity: High.
- [ ] **MGA-14: Sync spec-team-toolkit version in marketplace** — Update `marketplace.json` `spec-team-toolkit` entry from v0.1.0 to v0.2.0. Bump marketplace `metadata.version`. Update CHANGELOG. Owner: magen. Effort: 0.1 sessions (< 15 minutes). Severity: Medium.
- [ ] **MGA-15: Add keywords to marketplace plugin entries** — Three of four plugins have no `keywords` field. Add relevant keywords to improve discoverability in any future marketplace UI. Owner: magen. Effort: 1 session. Severity: Low.
- [ ] **MGA-16: Add git release tags to ono-plugin-marketplace** — CHANGELOG documents 17 versions but `git show-ref` shows zero tags. Create tags for all documented versions (at minimum the latest). Owner: Tom. Effort: 1 session. Severity: Low.

---

#### ono-mobile-dev-plugin gaps

- [ ] **MGA-17+MGA-23+MGA-20: iOS platform full completion** — Author all 5 iOS standards (`swift-standards.md`, `swiftui-uikit-standards.md`, `ios-architecture.md`, `xcode-build-signing.md`, `ios-performance.md`) with stable SWIFT-*/IOS-ARCH-* IDs; author all 3 iOS skills (`ios-dev-planning`, `ios-feature-implementation`, `ios-code-review`); author all 4 iOS agents (`ios-architect`, `ios-feature-developer`, `ios-code-reviewer`, `ios-performance-reviewer`). This work is entirely independent of MGA-4 (merging the feature branch delivers no standards authoring). Owner: Boris. Effort: 6–9 sessions total. Severity: Critical (MGA-17, MGA-20, MGA-23 individually). **Planning required before execution.**
- [ ] **MGA-18+MGA-24+MGA-21: Android platform full completion** — Author all 5 Android standards (`kotlin-standards.md`, `compose-xml-standards.md`, `android-architecture.md`, `gradle-build-signing.md`, `android-performance.md`) with stable KOTLIN-*/ANDROID-ARCH-* IDs; author all 3 Android skills (`android-dev-planning`, `android-feature-implementation`, `android-code-review`); author all 4 Android agents (`android-architect`, `android-feature-developer`, `android-code-reviewer`, `android-performance-reviewer`). Independent of MGA-4 merge. Owner: Guy. Effort: 6–9 sessions total. Severity: Critical. **Planning required before execution.**
- [ ] **MGA-19+MGA-25+MGA-22: React web platform full completion** — Author all 6 React standards with stable REACT-* IDs (including web security: XSS/CSRF/CSP coverage missing from `mobile-security.md`); author all 3 React skills (`react-dev-planning`, `react-feature-implementation`, `react-code-review`); author all 4 React agents (`react-architect`, `react-feature-developer`, `react-code-reviewer`, `react-performance-reviewer`). Update `mobile-security.md` to cover web security. Author React-specific accessibility and i18n rules. Owner: magen. Effort: 7–10 sessions total. Severity: Critical. **Planning required before execution.**
- [ ] **MGA-26: Merge feature branch (pipeline stages only)** — Once MGA-4 coordination is complete and Platform Guardian pipeline-stage map is updated, execute the merge of `feat/design-and-feature-start-stages` to main. Bump version. Owner: magen + Tom. Effort: 1 session (execution, after MGA-4 coordination). Severity: High.
- [ ] **MGA-27: Add web security coverage to mobile-security.md** — `mobile-security.md` explicitly does not cover XSS/CSRF/CSP for the React platform. Scope and author this section. Any `/review-security` on a React repo is incomplete by design until this is resolved. Owner: magen. Effort: 1–2 sessions. Severity: High. Blocked by: MGA-19.
- [ ] **MGA-28: Correct docs/marketplace-gap-audit.md** — The previous version of `docs/marketplace-gap-audit.md` incorrectly stated that iOS, Android, and React standards were "Authored on branch." This is false — all 14 standard files remain "Not yet authored" on both main and the feature branch. The revised audit document (Session 3) supersedes the prior version. MGA-5, MGA-6, and MGA-8 (the old backlog items) are now replaced by MGA-17/18/19 and their consolidated sub-items. Owner: Tom. Effort: 0 (completed by this backlog update). Severity: High (documentation correction).
- [ ] **MGA-29: Fix accessibility.md to cover all platforms** — `accessibility.md` uses React Native prop names throughout (accessibilityRole, accessibilityLabel, etc.) and explicitly states that iOS UIKit, Android Compose, and React web ARIA equivalents are not yet authored. Owner: magen. Effort: 1 session. Severity: High.
- [ ] **MGA-30: Fix i18n-rtl.md to cover all platforms** — `i18n-rtl.md` react-i18next conventions section is React Native-specific. iOS/Android/React platform equivalents are not yet authored. Owner: magen. Effort: 1 session. Severity: Medium.
- [ ] **MGA-31: Add non-RTK state management fallback path** — `rn-state-management.md` assumes Redux Toolkit throughout. `rn-api-service-layer.md` assumes RTK Query. No fallback path exists for projects using Zustand, Jotai, React Query, or TanStack Query. Owner: magen. Effort: 1 session. Severity: Medium.
- [ ] **MGA-32: Add docs/ directory to ono-mobile-dev-plugin** — Multiple skills reference `docs/` for architecture and ADR notes. No architecture decision records, integration diagrams, or workflow docs exist in the plugin repo itself. Owner: magen. Effort: 1 session. Severity: Low.
- [ ] **MGA-33+MGA-44+MGA-60: Fix cross-repo handoff template schema drift** — `qa-handoff-template.md` has a "Build / Install / Testing Instructions" section missing from `ono-plugin-qa`'s `qa-coverage-reviewer.md` and `qa-coverage-analysis/SKILL.md` fixed contract. Add a `template_version` field to the handoff template YAML frontmatter. Update the QA plugin to include this section in its contract. Create a cross-plugin contract document in `ono-plugin-marketplace` pinning the expected section list and version. Platform Guardian to monitor this contract version and alert on drift. Owner: magen + Arditi. Effort: 0.5 sessions. Severity: High.
- [ ] **MGA-34: Verify CLAUDE_PLUGIN_ROOT in Claude Code hook execution** — `CLAUDE_PLUGIN_ROOT` is used in all three hook JSON files to reference hook shell scripts. If Claude Code does not set this env var at hook execution time, all three hooks (`protect-secrets`, `require-approval-before-code`, `block-main-branch-changes`) silently fail. Test in a real installed-plugin context. If not set, add absolute-path fallback logic to all three hook shell scripts. Document verified behavior. Owner: magen + Tom. Effort: 0.5 sessions. Severity: High.

---

#### ono-plugin-project-inspector gaps

- [ ] **MGA-35+MGA-36: Resolve agent tool-execution gap** — The `project-inspector` agent declares `tools: Read, Skill` only — it has no Bash tool. Both `after-audit-breakdown.md` and `after-audit-approve.md` instruct the agent to run TypeScript scripts (`update-audit-index.ts`, `inspection-state.ts`) with no mechanism for shell execution. `.ono/state.json` may never be written deterministically. Either add `Bash` to the agent's tool list or redesign integration so the LLM reads state from AUDIT.md directly without a TypeScript runner. Document the verified execution path for both scripts. Platform Guardian must implement a fallback that reads `AUDIT.md` directly when `inspection-state.ts` is unavailable. Owner: magen (yagil). Effort: 2 sessions. Severity: Critical. **Planning required before execution.**
- [ ] **MGA-37: Add TypeScript runtime configuration** — No `package.json`, `tsconfig.json`, `bun.lockb`, or lock file exists. Scripts reference `ts-node` in one place and `bun` in another — they are not equivalent. Pin the runtime version. Add a README section on how to run scripts and from which directory. Owner: magen (yagil). Effort: 1 session. Severity: High.
- [ ] **MGA-38: Remove stale local-path marketplace.json** — `.claude-plugin/marketplace.json` in this repo is the original bootstrap file with `source: './'` — a local relative path that only works when installed from the same machine. Either delete it or update it to reference the real HTTPS marketplace URL. Owner: yagil. Effort: 0.1 sessions. Severity: Medium.
- [ ] **MGA-39: Fix __dirname-relative path in inspection-state.ts** — `scripts/inspection-state.ts` reads `registry.json` relative to `__dirname`. No documentation clarifies where scripts should be run from or how `__dirname` resolves when the plugin is installed via the Claude Code plugin cache. Owner: magen (yagil). Effort: 1 session. Severity: Medium.
- [ ] **MGA-40: Fix no-op migrateState() stub** — `migrateState()` in `inspection-state.ts` is a no-op stub — the while loop only bumps `stateSchemaVersion` by 1 with no data transformation. A schema change will silently produce a malformed state object that looks migrated but is not. Owner: magen (yagil). Effort: 1 session. Severity: Medium.

---

#### ono-plugin-qa gaps

- [ ] **MGA-41: Opium automation integration** — Zero references to Opium exist anywhere in `ono-plugin-qa`. Define the Opium data contract (what format Opium expects for test cases), then implement at minimum: an `/export-to-opium` command, an Opium-format template, and a skill for translating QA test-plan sections into Opium test cases. Owner: Arditi. Effort: 3–5 sessions. Severity: Critical. Blocked by: Opium data contract definition. **Planning required before execution.**
- [ ] **MGA-42: Add Platform Guardian integration point to ono-plugin-qa** — Implement a `/qa-status --json` command that outputs structured JSON (feature slug, test-plan status, approved date, coverage-report presence). This is the machine-readable endpoint Platform Guardian will consume. Until this exists, Platform Guardian must scan QA repo Markdown files directly. Owner: Tom (to spec) + magen (to implement). Effort: 2–3 sessions. Severity: High.
- [ ] **MGA-43: Author QA standards** — Create `standards/` directory in `ono-plugin-qa`. Document at minimum: pass/fail criteria definitions, severity ratings for coverage gaps, test-case ID naming conventions, QA repo folder structure conventions. Owner: Arditi. Effort: 1–2 sessions. Severity: High.
- [ ] **MGA-45: Standardize plugin.json capability declaration in ono-plugin-qa** — `plugin.json` declares no `commands`, `skills`, or `agents` arrays — only `hooks` and `mcpServers`. Platform Guardian cannot enumerate declared capabilities from the manifest alone. Owner: magen. Effort: 0.5 sessions. Severity: Medium.
- [ ] **MGA-46: Add docs/ directory and cross-plugin artifact schema to ono-plugin-qa** — The cross-plugin artifact schema (what YAML frontmatter the handoff template must have for the coverage reviewer to validate it) is documented only in README prose. Owner: magen. Effort: 1 session. Severity: Medium.
- [ ] **MGA-47: Add example output artifacts for QA onboarding** — No sample `test-plan.md` or `coverage-report.md` exists in a `fixtures/` or `examples/` subfolder. A new QA engineer has no reference to calibrate against without a live run. Owner: Arditi. Effort: 1 session. Severity: Medium.
- [ ] **MGA-48: Fix git hook to also block git add** — `block-qa-repo-git-writes.sh` regex matches only `git commit` and `git push`. Commands say "Never run git add/commit/push" but the hook only enforces the last two. Owner: magen. Effort: 0.5 sessions. Severity: Low.
- [ ] **MGA-49: Add JSON schema and validation for qa-workspace.json** — `qa-workspace.json` cache format is documented only in README prose. A malformed cache file causes silent workspace resolution failure. Owner: magen. Effort: 0.5 sessions. Severity: Low.

---

#### spec-team-toolkit gaps

- [ ] **MGA-50: Add mcpServers block to spec-team-toolkit plugin.json** — `plugin.json` has no `mcpServers` block despite `lld-figma-spec` requiring the Figma MCP server. Without this declaration, Figma MCP is not automatically provisioned on install. The skill silently degrades to the "ask for exported images" fallback. Both `ono-mobile-dev-plugin` and `ono-plugin-qa` correctly declare this. Owner: magen. Effort: 0.1 sessions. Severity: High.
- [ ] **MGA-51: Run formal test evaluations on spec-team-toolkit skills** — Neither `hld-builder` nor `lld-figma-spec` has been run through formal test evaluations. README explicitly flags this. Run both on real projects, document findings, and produce at least one example output artifact per skill. Owner: magen + spec team. Effort: 2–3 sessions. Severity: High.
- [ ] **MGA-52: Identify and declare docx skill dependency** — `hld-builder` SKILL.md Phase 3 and `draft_conventions.md` reference "the docx skill" for Word document generation, but no such skill is declared, no plugin declares it, and no documentation identifies which plugin or tool provides it. Identify the provider, declare it in `plugin.json`, or replace the step with a documented alternative. Owner: magen. Effort: 1 session. Severity: High.
- [ ] **MGA-53: Add author.email to spec-team-toolkit plugin.json and marketplace.json** — `plugin.json` has `author.name: "Spec Team"` but no `author.email`. `marketplace.json` entry also has no author email. Platform Guardian cannot associate this plugin with a responsible person for gap routing. Owner: magen. Effort: 0.1 sessions. Severity: Low.
- [ ] **MGA-54: Clarify lld-figma-spec scope and add QA plugin format caveat** — `lld-figma-spec` is Umbraco-CMS-oriented (Part 1 produces Umbraco 13 content-entry field tables). `ono-plugin-qa` accepts `--spec=` for any LLD doc. A QA engineer using a spec-team-toolkit LLD as input for a mobile feature receives Umbraco-specific field types irrelevant to mobile test planning. Document this limitation in both repos; scope a platform-agnostic LLD format if mobile LLD generation is needed. Owner: magen + spec team. Effort: 1 session. Severity: Medium.
- [ ] **MGA-55: Add commands/ directory to spec-team-toolkit** — No slash commands exist — only skills. No quick one-off actions are available without triggering the full skill flow. Owner: magen. Effort: 1–2 sessions. Severity: Medium.
- [ ] **MGA-56: Add templates/ directory to spec-team-toolkit** — No starter templates exist for `scope-list.md` or `hld-draft.md`. A new analyst must produce these from scratch. Owner: magen. Effort: 1 session. Severity: Medium.
- [ ] **MGA-57: Add docs/ directory to spec-team-toolkit** — No architecture or workflow documentation beyond README. Integration patterns, prerequisites, and known limitations are undocumented in a way Platform Guardian or other plugins can read. Owner: Tom. Effort: 0.5 sessions. Severity: Low.

---

#### Cross-repo gaps

- [ ] **MGA-58: Create Repo B (Org Knowledge Repository)** — Repo B does not exist. Only `org-knowledge-template/` exists as a local directory with all 12 domains at "Not started." No actual git repository exists on disk or is referenced with a real URL. All Platform Guardian Phase 5 enforcement gates, the audit engine, CLAUDE.md generation, and spec checking are blocked until Repo B is created and populated. This is the single highest-priority blocker for Platform Guardian going live on any platform. Platform Guardian must implement graceful degradation: when a domain file does not exist in Repo B, return `domain_not_yet_populated` rather than a hard error. Owner: Tom + PM + Design Lead + Architect. Effort: 6+ sessions (M4.1 through M4.6 as scoped below). Severity: Critical. Blocked by: OQ-1 (write access and approval process). **This is the single highest-priority blocker.**
- [ ] **MGA-59: Scope TV platform plugin work** — Zero plugin coverage exists for Apple TV, Android TV, Tizen, WebOS, and Vidaa across all repos. Platform Guardian governs 7 platforms; the plugin ecosystem covers 4. Decide: extend `ono-mobile-dev-plugin` with a TV module or create a new `ono-tv-dev-plugin`. Assign TV platform leads (analogous to Boris for iOS, Guy for Android). Add tvOS detection to `repo-analyst` (react-native-tvos package, Info.plist UIDeviceFamily 3). Author Tizen/WebOS/Vidaa standards (D-pad focus management, 10-foot typography, memory budgets). Register any new plugin in marketplace.json. Start with Apple TV (most overlap with existing mobile plugin). Owner: Tom (to scope) + TV platform leads (to author). Effort: 4–6 sessions minimum. Severity: Critical. **Planning required before execution.**
- [ ] **MGA-61: Coordinate feature branch merge with Platform Guardian pipeline update** — When `feat/design-and-feature-start-stages` merges, `/create-dev-plan` disappears and the pipeline becomes 8 stages. Platform Guardian must source its pipeline stage map from `plugin.json` version at runtime rather than hardcoding command names. The pipeline map for v0.3.0 must be ready before the branch merges. Owner: Tom + magen. Effort: 1 session (coordination only). Severity: High.
- [ ] **MGA-62: Add inter-plugin dependency declarations to marketplace schema** — No `peerPlugins` or `dependsOn` field exists in any manifest. `ono-plugin-qa` depends on `ono-mobile-dev-plugin` being installed (for the handoff template contract) but a developer can install ono-plugin-qa alone. `spec-team-toolkit`'s LLD output is used by ono-plugin-qa as `--spec=` input but is undocumented as a dependency. Platform Guardian should check peer plugin installation status before enforcing cross-plugin pipeline gates. Owner: magen + Tom. Effort: 1 session. Severity: Medium.
- [ ] **MGA-63: Standardize plugin.json capability declaration across all plugins** — Only `ono-plugin-project-inspector` declares `commands`, `skills`, and `agents` arrays in plugin.json. The other three plugins rely on directory-convention discovery. Platform Guardian cannot enumerate plugin capabilities from the manifest alone for 3 of 4 plugins. Either require manifest arrays or document directory scanning as the canonical algorithm and provide a standard implementation. Owner: magen. Effort: 1 session. Severity: Medium.
- [ ] **MGA-64: Document co-installation behavior for duplicate mcpServers.figma declarations** — Both `ono-mobile-dev-plugin` and `ono-plugin-qa` declare the identical `mcpServers.figma` key name and URL. No documentation addresses co-installation behavior. Clarify and document the expected behavior (deduplication, authentication sharing, or other). Owner: magen + Tom. Effort: 0.2 sessions. Severity: Low.
- [ ] **MGA-65: Add .gitignore to three plugin repos** — `ono-mobile-dev-plugin`, `ono-plugin-qa`, and `spec-team-toolkit` have no `.gitignore`. Add a standard `.gitignore` covering at minimum: `node_modules/`, `.DS_Store`, `.env`, `*.local`, `dist/`, `.cache/`. Owner: magen. Effort: 0.5 sessions. Severity: Low.

---

## Milestone 3.6 — TV Platform Coverage Gap

*Critical finding from Session 3 gap audit. Five TV platforms (Apple TV, Android TV, Tizen, WebOS, Vidaa) have zero plugin coverage across all marketplace repos. No standards, agents, skills, commands, or Repo B content exist for any TV platform. Platform Guardian governs 7 platforms; the plugin ecosystem covers 4. This milestone must be scoped and owned before any TV platform can enter the development workflow.*

- [ ] **MTV-1: Decide TV plugin strategy** — Determine whether TV platforms get a new `ono-tv-dev-plugin` or a major extension of `ono-mobile-dev-plugin` with a TV module. Produce an Architecture Decision Record (ADR) documenting the decision and rationale. Assign TV platform leads (one per platform or one for all TV). Start scoping with Apple TV (most overlap with existing React Native mobile plugin via react-native-tvos). Output: ADR in `docs/`. Owner: Tom + magen. Effort: 1 session.
- [ ] **MTV-2: TV platform standards (pilot — Apple TV)** — Author standards for Apple TV as the pilot TV platform: tvOS-specific constraints, D-pad navigation, 10-foot UI rules, memory budgets, react-native-tvos patterns. Produce stable TVOS-* standard IDs. Extends to other TV platforms in subsequent sessions (1 session per additional platform). Owner: TBD (TV developer). Effort: 2 sessions for Apple TV pilot. Blocked by: MTV-1.
- [ ] **MTV-3: TV agents + skills (pilot — Apple TV)** — Author agents and skills for Apple TV: `appletv-architect`, `appletv-feature-developer`, `appletv-code-reviewer` agents; `appletv-feature-implementation` and `appletv-code-review` skills. Extend to other TV platforms in subsequent sessions. Owner: TBD. Effort: 2 sessions for Apple TV pilot. Blocked by: MTV-2.

---

## Milestone 4 — Org Knowledge Repository (Repo B)

Create and populate the org knowledge repo. This is a separate deliverable from the plugin — it is the content the plugin enforces. Each item is one session of content work.

*Scope revised after MGA-3 (Session 3). MGA-58 confirms Repo B does not yet exist as a git repository. Three-layer model (SC-1 resolved) clarifies: Repo B contains org-level universal standards only. Feature specs and Figma file IDs are project-level and do not go into Repo B.*

- [ ] **M4.1: Create / formalize Repo B** — Create a real git repository (not just the local template directory). Assign domain owners. Resolve OQ-1 (write access + approval process). Ensure org-knowledge-template structure is in place for all 12 domains. First commit.
- [ ] **M4.2: Domain 6 — Platform Constraints (iOS Mobile)** — Populate `platforms/ios-mobile/`: constraints, capability matrix, navigation patterns, performance limits, testing requirements, known issues. This is the pilot platform — done first.
- [ ] **M4.3: Domain 3 — Architecture Decisions** — Populate `architecture/`: ADR stubs (state management, navigation, network layer), `approved-libraries.md` (initial list), `forbidden-patterns.md` (initial list), `tech-stack.md` for iOS Mobile.
- [ ] **M4.4: Domain 2 — Product Specifications** — Note: per SC-1 resolution, feature specs are project-level (live in `.platform-guardian/`), not in Repo B. This item is now scoped to: populate `product-spec/` with org-level spec templates and structure conventions sufficient to test Phase 5 enforcement. PM must participate in this session.
- [ ] **M4.5: Domains 1, 4, 5 — Design System, Dev Guidelines, AI Rules** — One session to populate stubs sufficient for audit. Full content follows iteratively. Requires Design Lead input for Domain 1.
- [ ] **M4.6: Domains 7–12 — QA, Release, Security, Performance, Localization, Monitoring** — Two sessions (6 domains). Populate to a functional baseline. Stubs are acceptable; the audit engine will flag gaps and drive completion over time.
- [ ] **M4.7+: Fill empty plugins** — Items coordinated with MGA-17/18/19 (iOS, Android, React platform authoring by Boris, Guy, magen). TV platforms: blocked until MTV-1 scoping is complete.

---

## Milestone 5 — Integration & Pilot (iOS Mobile)

End-to-end run of all 7 phases on the first real platform.

- [ ] **M5.1: Phase 0–1 pilot** — Connect plugin to real Repo B. Run `guardian init` on iOS Mobile project. Verify Phase 0 checks pass, project registers correctly. Verify Phase 1 design currency gate (`guardian_check_design_currency`) fires correctly on a feature with missing spec/Figma data.
- [ ] **M5.2: Phase 2 pilot — Full audit** — Run `guardian_run_audit` on iOS Mobile codebase. Review output. Fix any false positives in the audit engine. Verify `domain_not_yet_populated` responses are returned correctly for any platform domains not yet authored in Repo B.
- [ ] **M5.3: Phase 3–4 pilot** — Run architecture analyzer. Human review of deviation log. Generate CLAUDE.md draft (org-level section from Repo B + project-level section from `.platform-guardian/`). PM + Tech Lead review session.
- [ ] **M5.4: Phase 5 pilot** — Enable development mode. Test all enforcement gates against a real feature request. Verify blocks fire correctly. Test design audit (`guardian_run_design_audit`) and confirm `.platform-guardian/design-audit.md` is written correctly.
- [ ] **M5.5: Rollout plan** — Document lessons from iOS Mobile pilot. Produce onboarding sequence for remaining 6 platforms (Android Mobile → Apple TV → Android TV → TV platforms). Assign platform leads.

---

## Open Questions (must resolve before launch)

These are governance questions, not technical ones. They need a stakeholder meeting, not a code session.

- [ ] **OQ-1:** Who has write access to Repo B? What is the review/approval process for changes to org knowledge?
- [ ] **OQ-2:** How do individual projects handle Repo B version upgrades when standards change? (Major versions block — how is migration communicated and tracked?)
- [ ] **OQ-3:** What is the escalation path when a developer is blocked by the plugin and the PM is unavailable? Who can unblock?
- [ ] **OQ-4:** What notification channel does the emergency bypass use? (Slack? Email? PagerDuty?)

---

## Summary

| Milestone | Sessions | Owner | Prerequisite |
|-----------|----------|-------|-------------|
| Standing Checks (SC-2 remaining) | 1 | Tom | — |
| ~~SC-1~~ | ~~Resolved~~ | Tom | Session 3 |
| M0: Foundation | 2 | Tom | — |
| M1: MCP Server MVP (M1.1–M1.8) | 8 | Tom | M0 |
| M1.9: guardian_check_design_currency | 2 | Tom | M1.4 |
| M2: Audit Engine (M2.1–M2.6) | 6 | Tom | M1 |
| M2.7: guardian_run_design_audit | 3 | Tom | M1.9, M2.1 |
| M3: CLI + DX | 3 | Tom | M1 |
| M3.5: MGA (Gap Audit) | Done | Tom | Repo access |
| M3.6: TV Platform Coverage Gap | 5 per platform | Tom + TV leads | MTV-1 |
| MGA-4: Assign feature branch merge decision | 1 | magen + Tom | — |
| MGA-11: Register Platform Guardian in marketplace | 1 | Tom | M1.1 |
| MGA-12: Version pinning | 1 | magen | — |
| MGA-13: CI validation pipeline | 2 | magen | — |
| MGA-14: Sync spec-team-toolkit version | 0.1 | magen | — |
| MGA-17+20+23: iOS full completion | 6–9 | Boris | — |
| MGA-18+21+24: Android full completion | 6–9 | Guy | — |
| MGA-19+22+25: React full completion | 7–10 | magen | — |
| MGA-26: Execute feature branch merge | 1 | magen + Tom | MGA-4 |
| MGA-33+44+60: Fix handoff template schema drift | 0.5 | magen + Arditi | — |
| MGA-34: Verify CLAUDE_PLUGIN_ROOT | 0.5 | magen + Tom | Live install |
| MGA-35+36: Fix agent tool-execution gap | 2 | magen (yagil) | — |
| MGA-37: Add TS runtime config to project-inspector | 1 | magen (yagil) | — |
| MGA-41: Opium automation integration | 3–5 | Arditi | Data contract |
| MGA-42: QA status JSON endpoint | 2–3 | Tom + magen | — |
| MGA-43: Author QA standards | 1–2 | Arditi | — |
| MGA-50: Add Figma MCP to spec-team-toolkit | 0.1 | magen | — |
| MGA-51: spec-team-toolkit test evaluations | 2–3 | magen + spec team | — |
| MGA-52: Identify docx skill dependency | 1 | magen | — |
| MGA-58: Create Repo B | 6+ | Tom + PM + Design Lead + Architect | OQ-1 |
| MGA-59: Scope TV platform plugin work | 4–6 | Tom + TV leads | MTV-1 |
| MGA-61: Coordinate branch merge with pipeline update | 1 | Tom + magen | — |
| MGA-62/63: Standardize plugin manifests | 1 | magen | — |
| MGA-65: Add .gitignore to 3 repos | 0.5 | magen | — |
| M4: Org Knowledge Repo | 6+ | Tom + stakeholders | MGA-58, OQ-1 |
| M5: Integration & Pilot | 5 | Tom | M1–M4 |
| **Total (Platform Guardian track)** | **~45+** | Tom | M4 scope confirmed |
| **Total (Marketplace plugin track)** | **~35–45** | Boris, Guy, Arditi, magen, spec team | Parallel |
| **Total (TV platform track)** | **~10–20** | Tom + TV leads | MTV-1 scoping |

**Recommended next session:** SC-2 (auto-review agent) + M0.1 (git init). SC-1 is resolved. SC-2 and M0.1 are both short and unblock everything else.

**Pilot platform:** iOS Mobile (confirmed from Session 1).

**Architecture model (SC-1 resolved):** Three-layer — Org (Repo B) / Project (`.platform-guardian/`) / Platform (code repos). Figma at project level.

**Critical blocker:** MGA-58 (Repo B does not exist). No Phase 5 enforcement, audit engine, or CLAUDE.md generation works until Repo B is created and minimally populated.

**Gantt:** `docs/gantt.html` — high-level 12-week visual timeline (update required to reflect new items).
