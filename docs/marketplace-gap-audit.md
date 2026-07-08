# Marketplace Gap Audit — 2026-07-08 (Revised — Agent Workflow)

Conducted via a two-pass agent workflow: (1) deep per-repo readers covering all five marketplace repos, followed by (2) an adversarial verification agent that re-read raw files and git history to challenge the initial findings. Corrections from the adversarial pass are marked **(missed by initial audit)**.

---

## Executive Summary

**Total gaps found: 47** across 5 plugin repos, 11 cross-repo integration gaps, and 10 Platform Guardian–specific integration requirements.

| Severity | Count |
|----------|-------|
| Critical | 15 |
| High | 19 |
| Medium | 9 |
| Low | 4 |

**Key risks for Platform Guardian:**

1. **Org Knowledge Repository (Repo B) does not exist.** Not a plugin — a prerequisite. All Phase 5 enforcement gates, the audit engine, CLAUDE.md generation, and spec checking return empty or error responses until Repo B is created and populated. This is the single most fundamental blocker for Platform Guardian going live on any platform and was not surfaced by any repo-scoped audit.

2. **iOS, Android, and React standards are all empty placeholders — including on the unmerged feature branch.** The previous version of this document incorrectly stated that iOS, Android, and React standards were "Authored on branch." This is false. Every one of the 14 platform-specific standard files remains "Not yet authored" on both main and the feature branch. Merging the branch delivers 2 new pipeline stages; it does not deliver any platform standards. Boris and Guy have the full authoring scope remaining.

3. **Five TV platforms (Apple TV, Android TV, Tizen, WebOS, Vidaa) have zero plugin coverage.** Platform Guardian governs 7 platforms. The plugin ecosystem covers 4 (React Native, iOS, Android, React web). No standards, agents, skills, commands, or Repo B content exist for any TV platform.

4. **The feature branch removes `/create-dev-plan` on merge.** If Platform Guardian hardcodes the current 7-stage pipeline by command name, it will break when the branch merges. The pipeline stage map must be sourced from plugin.json version at runtime.

5. **Three critical tool-execution gaps in ono-plugin-project-inspector** mean the TypeScript scripts that Platform Guardian would rely on for machine-readable inspection state may silently not execute, because the agent has no Bash tool and no TypeScript runtime is documented or installed.

---

## Repo-by-Repo Findings

---

### ono-plugin-marketplace

**Complete:** marketplace.json declares 4 plugins with HTTPS source URLs, semantic versions, descriptions, and author emails. README, CHANGELOG, and .gitignore are all substantive and current. Schema is valid.

**Gaps:**

| ID | Description | Severity | Owner | Est. Sessions | Blocked By |
|----|-------------|----------|-------|---------------|------------|
| MGA-11 | Platform Guardian not listed in marketplace.json. Developers cannot install it via the marketplace until it is added. | Critical | Tom | 1 | M1.1 (plugin repo must exist at a real GitHub URL before the entry can be added) |
| MGA-12 | No version pinning — all 4 plugins use `ref: main`. A breaking change pushed to any plugin repo takes effect immediately for every developer on next update, with no rollback path and no minimum-version field. | High | magen | 1 | — |
| MGA-13 | No CI or validation pipeline. No workflow verifies that plugin source URLs are reachable, that referenced refs exist, or that marketplace.json is schema-valid. A typo in a URL silently fails only at developer install time. | High | magen | 2 | — |
| MGA-14 | spec-team-toolkit listed as v0.1.0 in marketplace.json but plugin.json declares v0.2.0 (released 2026-07-08). The version bump was applied to the plugin repo but not propagated to the registry. **(missed by initial audit)** | Medium | magen | 0.1 | — |
| MGA-15 | Three of four plugins have no `keywords` field. Only ono-project-inspector has keywords. Limits discoverability in any future marketplace UI. | Low | magen | 1 | — |
| MGA-16 | No git release tags. CHANGELOG documents 17 versions but `git show-ref` shows zero tags — only the main branch head. Versions exist only as metadata in marketplace.json and CHANGELOG prose. | Low | Tom | 1 | — |

---

### ono-mobile-dev-plugin

**Complete:** All 8 commands are fully authored with real procedural content. All 6 shared skills and 3 React Native skills are complete. All 5 shared standards and 6 React Native standards are fully authored with stable IDs. All 5 RN agents and 2 shared agents are fully authored. All 3 safety hooks (protect-secrets, require-approval-before-code, block-main-branch-changes) are implemented with real bash scripts. All 7 pipeline templates are complete.

**Gaps:**

| ID | Description | Severity | Owner | Est. Sessions | Blocked By |
|----|-------------|----------|-------|---------------|------------|
| MGA-17 | **All 5 iOS standards files are empty placeholders** — `swift-standards.md`, `swiftui-uikit-standards.md`, `ios-architecture.md`, `xcode-build-signing.md`, `ios-performance.md` all say "Not yet authored." No stable IDs (SWIFT-*, SWIFTUI-*, IOS-ARCH-*) exist. This is true on both main and the feature branch. **(initial audit correctly identified; branch claim was wrong — see MGA-28)** | Critical | Boris | 3–4 | — |
| MGA-18 | **All 5 Android standards files are empty placeholders** — `kotlin-standards.md`, `compose-xml-standards.md`, `android-architecture.md`, `gradle-build-signing.md`, `android-performance.md` all say "Not yet authored." Same caveat as MGA-17. | Critical | Guy | 3–4 | — |
| MGA-19 | **All 6 React (web) standards files are empty placeholders** — `react-coding-standards.md`, `react-routing.md`, `react-state-management.md`, `react-api-service-layer.md`, `react-architecture.md`, `react-performance.md` all say "Not yet authored." Additionally, `mobile-security.md` explicitly documents that XSS/CSRF/CSP are not covered for React. | Critical | magen | 4–5 | — |
| MGA-20 | **All 4 iOS agents are empty placeholders** — `ios-architect.md`, `ios-feature-developer.md`, `ios-code-reviewer.md`, `ios-performance-reviewer.md` all say "Not yet authored." Any pipeline command run on an iOS repo routes to these stubs and produces ungrounded output with no standard-ID citations. | Critical | Boris | 2–3 | MGA-17 (standards needed first) |
| MGA-21 | **All 4 Android agents are empty placeholders** — `android-architect.md`, `android-feature-developer.md`, `android-code-reviewer.md`, `android-performance-reviewer.md` all say "Not yet authored." | Critical | Guy | 2–3 | MGA-18 |
| MGA-22 | **All 4 React (web) agents are empty placeholders** — `react-architect.md`, `react-feature-developer.md`, `react-code-reviewer.md`, `react-performance-reviewer.md` all say "Not yet authored." | Critical | magen | 2–3 | MGA-19 |
| MGA-23 | **All 3 iOS skills are empty placeholders** — `ios-dev-planning/SKILL.md`, `ios-feature-implementation/SKILL.md`, `ios-code-review/SKILL.md` all say "Status: Not yet authored." | Critical | Boris | 1–2 | MGA-17 |
| MGA-24 | **All 3 Android skills are empty placeholders** — `android-dev-planning/SKILL.md`, `android-feature-implementation/SKILL.md`, `android-code-review/SKILL.md` all say "Status: Not yet authored." | Critical | Guy | 1–2 | MGA-18 |
| MGA-25 | **All 3 React (web) skills are empty placeholders** — `react-dev-planning/SKILL.md`, `react-feature-implementation/SKILL.md`, `react-code-review/SKILL.md` all say "Status: Not yet authored." | Critical | magen | 1–2 | MGA-19 |
| MGA-26 | Feature branch `feat/design-and-feature-start-stages` (v0.3.0) is unmerged. It adds `/dev-design-start` and `/dev-feature-start` as a 2-stage replacement for `/create-dev-plan`, plus `dd-template.md` and updated rn-architect. Merging removes `/create-dev-plan` with no backward-compat alias. No merge date or merge decision owner is assigned. | High | magen | 1 | Merge decision owner must be assigned |
| MGA-27 | `mobile-security.md` explicitly does not cover XSS/CSRF/CSP for the React platform. The gap is documented in the file and in the mobile-security-reviewer agent but has no resolution path or owner. Any `/review-security` on a React repo is incomplete by design. | High | magen | 1–2 | MGA-19 |
| MGA-28 | **The previous version of this document incorrectly stated that iOS, Android, and React standards were "Authored on branch."** `git show` of the feature branch confirms every one of the 14 standard files is still "Not yet authored." The branch only changed one line per file (replaced `/create-dev-plan` with `/dev-design-start` in the placeholder body text). MGA-4 in the prior audit must not be interpreted as delivering any standards authoring work. **(missed by initial audit — adversarial pass correction)** | High | Tom | 0 (documentation fix, no code work) | — |
| MGA-29 | `standards/shared/accessibility.md` uses React Native prop names throughout (accessibilityRole, accessibilityLabel, etc.) and explicitly states that iOS UIKit, Android Compose, and React web ARIA equivalents are not yet authored. Any `/review-code` on native iOS, Android, or React web applies RN-flavored accessibility rules. | High | magen | 1 | — |
| MGA-30 | `standards/shared/i18n-rtl.md` react-i18next conventions section is React Native–specific. iOS/Android/React platform equivalents are not yet authored. | Medium | magen | 1 | — |
| MGA-31 | `rn-state-management.md` assumes Redux Toolkit throughout. `rn-api-service-layer.md` assumes RTK Query. No fallback path exists for projects using Zustand, Jotai, React Query, or TanStack Query. The repo-analyst detects the actual library but the standards apply RTK-specific rules regardless. | Medium | magen | 1 | — |
| MGA-32 | No `docs/` directory. Multiple skills reference `docs/` for architecture and ADR notes (particularly `dev-design-start`). No architecture decision records, integration diagrams, or workflow docs exist in the plugin repo itself. | Low | magen | 1 | — |
| MGA-33 | `qa-handoff-template.md` has a "Build / Install / Testing Instructions" section that is absent from `qa-coverage-reviewer.md`'s hardcoded section list and from `qa-coverage-analysis/SKILL.md`'s fixed contract. When a developer fills out this section, the QA coverage checker silently ignores it. This is also the root cause of MGA-41 (cross-repo drift). **(missed by initial audit)** | High | magen + Arditi | 0.5 | — |
| MGA-34 | `CLAUDE_PLUGIN_ROOT` is used in all hook JSON files to reference hook shell scripts. If Claude Code does not set this environment variable at hook execution time, all three hooks silently fail — the secrets scan, main-branch protection, and approval gate do not run, with no error visible to the developer. **(missed by initial audit)** | High | magen + Tom | 0.5 | Requires live Claude Code install to verify |

---

### ono-plugin-project-inspector

**Complete:** All 5 commands, 6 skills, 1 agent, 6 hooks, 3 TypeScript scripts, and 4 documentation files are fully implemented with substantive content. The registry.json is fully registry-driven. The agent workflow, state machine, approval flow, and Stage 3 breakdown-approve loop are all well-specified.

**Gaps:**

| ID | Description | Severity | Owner | Est. Sessions | Blocked By |
|----|-------------|----------|-------|---------------|------------|
| MGA-35 | **The agent has no Bash tool, so it cannot execute TypeScript scripts.** `agents/project-inspector.md` declares `tools: Read, Skill` only. Both `after-audit-breakdown.md` and `after-audit-approve.md` instruct the agent to "Run scripts/update-audit-index.ts" with no mechanism for how an agent with only Read and Skill tools executes a shell command. The hook verification is structurally unreachable. | Critical | magen (yagil) | 2 | — |
| MGA-36 | **Same tool gap for `inspection-state.ts`.** `inspection-state/SKILL.md` describes running `bun scripts/inspection-state.ts <command>` but this shell execution is impossible with only Read and Skill tools. There is no wiring between the SKILL.md and the TypeScript script. `.ono/state.json` may never be written deterministically, making resume behavior unreliable. | Critical | magen (yagil) | 2 | — |
| MGA-37 | No TypeScript runtime configuration exists. No `package.json`, `tsconfig.json`, `bun.lockb`, or lock file. The scripts reference `ts-node` in one place and `bun` in another — they are not equivalent. No runtime version is pinned. Any developer cloning the repo and running the scripts will fail with no clear guidance. | High | magen (yagil) | 1 | — |
| MGA-38 | The stale `.claude-plugin/marketplace.json` in this repo (name: `ono-ai-marketplace`, source: `./`) is the original bootstrap file from before the central ono-plugin-marketplace existed. It uses a local relative source path that only works when installed from the same machine. A developer following this file gets a broken local-path install. **(missed by initial audit)** | Medium | yagil | 0.1 | — |
| MGA-39 | `scripts/inspection-state.ts` reads `registry.json` relative to `__dirname`. No documentation clarifies where scripts should be run from or how `__dirname` resolves when the plugin is installed via the Claude Code plugin cache. Could break when called from a non-standard directory. | Medium | magen (yagil) | 1 | — |
| MGA-40 | The `migrateState()` function in `inspection-state.ts` is a no-op stub. The while loop only bumps `stateSchemaVersion` by 1 with no data transformation. If the schema changes and a developer runs migrate, the function silently produces a malformed state object that looks migrated but is not. | Medium | magen (yagil) | 1 | — |

---

### ono-plugin-qa

**Complete:** All 4 commands, 3 skills, 3 agents, 2 templates, and 1 hook are fully authored with substantive, non-placeholder content. Figma MCP integration is correctly specified. Workspace resolution algorithm is implemented consistently across commands and README. CHANGELOG and README are accurate and up to date.

**Gaps:**

| ID | Description | Severity | Owner | Est. Sessions | Blocked By |
|----|-------------|----------|-------|---------------|------------|
| MGA-41 | **No Opium automation integration.** Described as "Opium automation in progress with Arditi" in org context, but there is zero mention of Opium in any file in the repo — no command, no skill, no agent, no template, no hook, no README section. No data contract has been defined. | Critical | Arditi | 3–5 | Requires defining the Opium data contract before any export command or template can be authored |
| MGA-42 | No Platform Guardian integration point. No `/report-qa-status` command, no structured JSON output, no MCP endpoint. Platform Guardian must scan QA repo Markdown files directly but requires a specific workspace layout to do so. | High | Tom | 2–3 | — |
| MGA-43 | No `standards/` directory. No QA-side document covering pass/fail criteria definitions, severity ratings for coverage gaps, test-case ID naming conventions, or QA-repo folder structure conventions. | High | Arditi | 1–2 | — |
| MGA-44 | `qa-coverage-reviewer.md` and `qa-coverage-analysis/SKILL.md` both omit "Build / Install / Testing Instructions" from their hardcoded section contract, but this section exists in `qa-handoff-template.md` in ono-mobile-dev-plugin. This is a live cross-repo schema drift. Any future change to the handoff template will silently break QA coverage analysis because there is no version pin, schema file, or change notification mechanism. **(missed by initial audit)** | High | magen + Arditi | 0.5 | MGA-33 (fix handoff template first) |
| MGA-45 | `plugin.json` declares no `commands`, `skills`, or `agents` arrays — only `hooks` and `mcpServers`. Platform Guardian and marketplace tooling cannot enumerate declared capabilities from the manifest alone and must scan the filesystem. | Medium | magen | 0.5 | — |
| MGA-46 | No `docs/` directory and no architecture doc. The cross-plugin artifact schema (what exact YAML frontmatter the handoff template must have for the coverage reviewer to validate it) is documented only in README prose and inline agent comments. | Medium | magen | 1 | — |
| MGA-47 | No example output artifacts (no sample `test-plan.md` or `coverage-report.md` in a `fixtures/` or `examples/` subfolder). Onboarding a new QA engineer requires a live run with no reference to calibrate against. | Medium | Arditi | 1 | — |
| MGA-48 | `block-qa-repo-git-writes.sh` regex matches only `git commit` and `git push`. Commands say "Never run git add/commit/push" but the hook only enforces the last two. An accidental `git add` by the agent succeeds. | Low | magen | 0.5 | — |
| MGA-49 | `qa-workspace.json` cache format is documented only in README prose. No JSON schema, no validation step, no example file. A malformed cache file causes silent workspace resolution failure. | Low | magen | 0.5 | — |

---

### spec-team-toolkit

**Complete:** `hld-builder` and `lld-figma-spec` skills are fully authored with real, detailed methodologies. The reference files (`discovery_questions.md`, `draft_conventions.md`, `hld_template_structure.md`, `hld_qa_review.md`, `lld_instructions.md`) all contain substantive, team-derived content. README and CHANGELOG are accurate.

**Gaps:**

| ID | Description | Severity | Owner | Est. Sessions | Blocked By |
|----|-------------|----------|-------|---------------|------------|
| MGA-50 | **`plugin.json` declares no `mcpServers` block**, yet `lld-figma-spec` requires the Figma MCP server. Without the declaration, Figma MCP is not automatically provisioned when the plugin is installed. The skill silently degrades to the "ask for exported images" fallback with no clear error. `ono-mobile-dev-plugin` and `ono-plugin-qa` both correctly declare this. **(missed by initial audit)** | High | magen | 0.1 | — |
| MGA-51 | No formal test evaluations have been run on either skill. README explicitly flags this: "Neither skill has been run through formal test evaluations yet — try each on a real project before rolling out broadly." | High | magen + spec team | 2–3 | — |
| MGA-52 | `hld-builder` SKILL.md Phase 3 and `draft_conventions.md` both reference "the docx skill" for Word document generation, but no docx skill exists in this plugin, no `plugin.json` dependency is declared, and no documentation identifies which plugin or tool provides it. | High | magen | 1 | — |
| MGA-53 | `plugin.json` has no `author.email` — only `author.name: "Spec Team"`. All other plugins have an author email. Platform Guardian cannot associate this plugin with a responsible person for gap routing. marketplace.json entry also has no author email. **(missed by initial audit)** | Low | magen | 0.1 | — |
| MGA-54 | `lld-figma-spec` skill is explicitly Umbraco-CMS oriented (Part 1 produces Umbraco 13 content-entry field tables). `ono-plugin-qa` accepts `--spec=` for any LLD doc, but a QA engineer using a spec-team-toolkit LLD as input for a mobile feature will receive Umbraco-specific field types irrelevant to mobile test planning. No documentation clarifies that `lld-figma-spec` is web/CMS-only. **(missed by initial audit)** | Medium | magen + spec team | 1 | — |
| MGA-55 | No `commands/` directory. No slash commands exist — only skills. No quick one-off actions available without triggering the full skill flow. | Medium | magen | 1–2 | — |
| MGA-56 | No `templates/` directory. No starter templates for `scope-list.md` or `hld-draft.md`. A new analyst must produce these from scratch or let the skill generate them in-session with no offline reference. | Medium | magen | 1 | — |
| MGA-57 | No `docs/` directory. No architecture or workflow documentation beyond README. Integration patterns, prerequisites, and known limitations are undocumented in a way Platform Guardian or other plugins can read. | Low | Tom | 0.5 | — |

---

## Cross-Repo Gaps

| ID | Description | Affected Repos | Severity | Owner | Est. Sessions |
|----|-------------|----------------|----------|-------|---------------|
| MGA-58 | **Org Knowledge Repository (Repo B) does not exist.** Only `org-knowledge-template/` exists as a local directory with all 12 domains at "Not started." No actual git repository exists on disk or is referenced with a real URL. All Platform Guardian Phase 5 enforcement gates, the audit engine, CLAUDE.md generation, and spec checking are blocked until Repo B is created and populated. This was not surfaced by any plugin-repo-scoped audit. **(missed by initial audit)** | org-platform-guardian | Critical | Tom + PM + Design Lead + Architect | 6+ (see M4 milestones) |
| MGA-59 | **Zero TV platform coverage across all plugins.** No standards, agents, skills, commands, or routing logic exists for Apple TV, Android TV, Tizen, WebOS, or Vidaa in any plugin. Platform Guardian governs 7 platforms; the plugin ecosystem covers 4. Tizen/WebOS/Vidaa use web technologies but require TV-specific APIs, D-pad navigation, 10-foot UI rules, and strict memory limits not addressed by any existing standard. Apple TV and Android TV have partial mobile overlap but are never explicitly routed. | ono-mobile-dev-plugin, ono-plugin-qa, ono-plugin-marketplace | Critical | Tom (to scope) + TV platform leads | 4–6 minimum (new plugin or major extension) |
| MGA-60 | **Live cross-repo schema drift: `qa-handoff-template.md` has evolved but `ono-plugin-qa` has not been updated.** The dev plugin's handoff template added a "Build / Install / Testing Instructions" section. The QA plugin treats the dev handoff template as "a stable, unchanging contract" but has no version pin, no schema file, and no change notification mechanism. Any future change to the handoff template will silently break QA coverage analysis. | ono-mobile-dev-plugin, ono-plugin-qa | High | magen + Arditi | 0.5 |
| MGA-61 | **The feature branch merge removes `/create-dev-plan` with no coordinated Platform Guardian update.** The branch CHANGELOG explicitly removes this command. No merge decision owner or date is assigned. If Platform Guardian hardcodes the 7-stage pipeline by command name, it will enforce a pipeline that no longer exists post-merge. The pipeline stage count also changes from 7 to 8. | ono-mobile-dev-plugin, ono-plugin-marketplace | High | Tom + magen | 1 (coordination) |
| MGA-62 | **No inter-plugin dependency declarations in any manifest.** `ono-plugin-qa` depends on `ono-mobile-dev-plugin` being installed (for the handoff template contract) but a developer can install ono-plugin-qa alone. `spec-team-toolkit`'s LLD output is used by ono-plugin-qa as `--spec=` input, but this is undocumented as a dependency. No marketplace schema field expresses "this plugin requires that plugin." | ono-mobile-dev-plugin, ono-plugin-qa, spec-team-toolkit, ono-plugin-marketplace | Medium | magen + Tom | 1 |
| MGA-63 | **Inconsistent plugin.json capability declaration across all plugins.** Only `ono-plugin-project-inspector` declares `commands`, `skills`, and `agents` arrays in plugin.json. The other three plugins rely on directory-convention discovery. Platform Guardian and the marketplace cannot enumerate plugin capabilities from the manifest alone for 3 of 4 plugins. | ono-mobile-dev-plugin, ono-plugin-qa, spec-team-toolkit, ono-plugin-marketplace | Medium | magen | 1 |
| MGA-64 | **Duplicate `mcpServers.figma` declarations in `ono-mobile-dev-plugin` and `ono-plugin-qa`.** Both declare the identical key name and URL. No documentation addresses what happens when both plugins are installed simultaneously. If Claude Code registers both separately, there could be duplicate tool registration, authentication confusion, or unexpected behavior. | ono-mobile-dev-plugin, ono-plugin-qa | Low | magen + Tom | 0.2 |
| MGA-65 | **Missing `.gitignore` in three plugin repos.** `ono-mobile-dev-plugin`, `ono-plugin-qa`, and `spec-team-toolkit` have no `.gitignore`. Node modules, `.DS_Store`, `.env` files, IDE configs, and generated artifacts could be accidentally committed. | ono-mobile-dev-plugin, ono-plugin-qa, spec-team-toolkit | Low | magen | 0.5 |

---

## Platform Guardian Integration Requirements

These are gaps or risks that specifically affect how Platform Guardian will integrate with the marketplace plugin ecosystem.

**1. Repo B must exist before any Phase 5 enforcement runs.**
All `guardian_check_spec`, `guardian_check_design`, `guardian_check_dependency`, and `guardian_check_platform_capability` calls will return empty or error responses until Repo B is created (M4.1). Platform Guardian must implement graceful degradation: when a domain file does not exist in Repo B, return `domain_not_yet_populated` rather than a hard error. The `guardian_check_phase` tool must distinguish between "gate passed" and "gate skipped (Repo B domain missing)."

**2. Pipeline stage map must not be hardcoded.**
When `feat/design-and-feature-start-stages` merges, the 7-stage pipeline becomes an 8-stage pipeline and `/create-dev-plan` disappears. Platform Guardian must source its pipeline stage map from `ono-mobile-dev-plugin`'s `plugin.json` version field at runtime. Build a plugin-version-aware stage registry.

**3. Platform-specific standards authorship must gate enforcement rules.**
Platform Guardian must read each platform's standards directory before applying audit rules. For any platform where standards are still "Not yet authored" placeholders (iOS, Android, React, all TV platforms), Platform Guardian must skip standard-ID-citation enforcement and surface a clear message: "iOS standards not yet authored — rule enforcement deferred." Any audit rule requiring a SWIFT-*, KOTLIN-*, or REACT-* citation will always fail for those platforms today.

**4. TypeScript runtime must be verified before relying on inspection-state.ts.**
If Platform Guardian uses `.ono/state.json` as a machine-readable inspection progress endpoint (via `bun scripts/inspection-state.ts detect <repo-root>`), it must first verify that bun or ts-node is available. Given MGA-35 and MGA-36 (the agent has no Bash tool), it must also verify that the scripts actually execute as documented. Implement a fallback that reads `AUDIT.md` directly when `inspection-state.ts` is unavailable.

**5. QA plugin state must be read via direct file scan, not plugin invocation.**
There is no `/report-qa-status` command and no structured JSON output from `ono-plugin-qa`. Platform Guardian must implement a QA repo scanner that: (a) finds feature slugs in the QA repo, (b) reads `test-plan.md` YAML frontmatter for `status` and `approved_date`, (c) checks `coverage-report.md` existence. Figma OAuth makes headless invocation of QA plugin commands infeasible.

**6. SC-1 must be resolved before M1.2 and M2.6.**
Standing Check SC-1 (org-level vs. project-level Claude settings policy) is an unowned, undated decision. It blocks the phase state engine (M1.2), the knowledge connector integration (M1.4), and CLAUDE.md generation (M2.6). Assign SC-1 to Tom with a target resolution date before M1.2 begins.

**7. Hook behaviors must be re-implemented at the MCP level.**
The three safety hooks in `ono-mobile-dev-plugin` are installed per-plugin, not org-wide. A developer who bypasses plugin installation gets no protection. Subject to CLAUDE_PLUGIN_ROOT verification (MGA-34), Platform Guardian must independently enforce these behaviors: secrets-pattern checks on any approved code write, branch verification before feature work, and inclusion in the org-level CLAUDE.md template.

**8. TV platform scoping is blocked and unowned.**
No concrete plan exists for how TV platforms enter the plugin ecosystem. Decisions needed: new `ono-tv-dev-plugin` vs. extension of `ono-mobile-dev-plugin`; TV platform lead assignments (analogous to Boris for iOS, Guy for Android); minimum Repo B content before TV Phase 1 can run. The platform with the most existing overlap is Apple TV (react-native-tvos) — start there.

**9. Cross-plugin handoff template drift must be monitored.**
Platform Guardian should track `qa-handoff-template.md` as a versioned artifact. Add a template-version or schema-hash field to its YAML frontmatter. Platform Guardian's knowledge connector should compare the stored version against the live template on each session and alert when drift is detected.

**10. docs/marketplace-gap-audit.md factual correction (this document).**
The previous version of this document stated that iOS, Android, and React standards were "Authored on branch" and that MGA-4 (merge feature branch) would deliver authored standards. Both claims are false. MGA-5, MGA-6, and MGA-8 (platform completion work for Boris, Guy, and the React owner) are entirely separate from MGA-4 and represent the same authoring scope as before the branch was created. This document supersedes and corrects the prior version.

---

## Complete Gap Table

| ID | Repo | Description | Severity | Owner | Est. Sessions | Blocked By |
|----|------|-------------|----------|-------|---------------|------------|
| MGA-11 | ono-plugin-marketplace | Platform Guardian not in marketplace.json | Critical | Tom | 1 | M1.1 |
| MGA-12 | ono-plugin-marketplace | No version pinning (all plugins ref: main) | High | magen | 1 | — |
| MGA-13 | ono-plugin-marketplace | No CI / validation pipeline | High | magen | 2 | — |
| MGA-14 | ono-plugin-marketplace | spec-team-toolkit listed as v0.1.0, plugin says v0.2.0 **(missed)** | Medium | magen | 0.1 | — |
| MGA-15 | ono-plugin-marketplace | Missing keywords on 3 of 4 plugins | Low | magen | 1 | — |
| MGA-16 | ono-plugin-marketplace | No git release tags despite 17 CHANGELOG versions | Low | Tom | 1 | — |
| MGA-17 | ono-mobile-dev-plugin | All 5 iOS standards are empty placeholders (on main AND branch) | Critical | Boris | 3–4 | — |
| MGA-18 | ono-mobile-dev-plugin | All 5 Android standards are empty placeholders | Critical | Guy | 3–4 | — |
| MGA-19 | ono-mobile-dev-plugin | All 6 React standards are empty placeholders + no web security coverage | Critical | magen | 4–5 | — |
| MGA-20 | ono-mobile-dev-plugin | All 4 iOS agents are empty placeholders | Critical | Boris | 2–3 | MGA-17 |
| MGA-21 | ono-mobile-dev-plugin | All 4 Android agents are empty placeholders | Critical | Guy | 2–3 | MGA-18 |
| MGA-22 | ono-mobile-dev-plugin | All 4 React agents are empty placeholders | Critical | magen | 2–3 | MGA-19 |
| MGA-23 | ono-mobile-dev-plugin | All 3 iOS skills are empty placeholders | Critical | Boris | 1–2 | MGA-17 |
| MGA-24 | ono-mobile-dev-plugin | All 3 Android skills are empty placeholders | Critical | Guy | 1–2 | MGA-18 |
| MGA-25 | ono-mobile-dev-plugin | All 3 React skills are empty placeholders | Critical | magen | 1–2 | MGA-19 |
| MGA-26 | ono-mobile-dev-plugin | feat/design-and-feature-start-stages not merged; no merge date/owner | High | magen | 1 | Merge decision |
| MGA-27 | ono-mobile-dev-plugin | No XSS/CSRF/CSP coverage in mobile-security.md for React platform | High | magen | 1–2 | MGA-19 |
| MGA-28 | ono-mobile-dev-plugin | Prior audit document incorrectly stated branch delivers authored standards **(adversarial correction)** | High | Tom | 0 | — |
| MGA-29 | ono-mobile-dev-plugin | accessibility.md uses RN-only prop names; native iOS/Android/React ARIA rules not authored | High | magen | 1 | — |
| MGA-30 | ono-mobile-dev-plugin | i18n-rtl.md conventions are RN-specific; platform equivalents not authored | Medium | magen | 1 | — |
| MGA-31 | ono-mobile-dev-plugin | State management standards assume RTK/RTK Query only; no non-RTK fallback path | Medium | magen | 1 | — |
| MGA-32 | ono-mobile-dev-plugin | No docs/ directory | Low | magen | 1 | — |
| MGA-33 | ono-mobile-dev-plugin | qa-handoff-template.md "Build / Install / Testing Instructions" section missing from QA plugin's contract **(missed)** | High | magen + Arditi | 0.5 | — |
| MGA-34 | ono-mobile-dev-plugin | CLAUDE_PLUGIN_ROOT env var used in all hooks but not verified to exist in Claude Code hook execution context **(missed)** | High | magen + Tom | 0.5 | Requires live install test |
| MGA-35 | ono-plugin-project-inspector | Agent has no Bash tool — cannot run update-audit-index.ts as hooks require | Critical | magen (yagil) | 2 | — |
| MGA-36 | ono-plugin-project-inspector | Agent has no Bash tool — cannot run inspection-state.ts; .ono/state.json may not be written deterministically | Critical | magen (yagil) | 2 | — |
| MGA-37 | ono-plugin-project-inspector | No TypeScript runtime config (no package.json, tsconfig.json, bun.lockb); scripts fail on clone | High | magen (yagil) | 1 | — |
| MGA-38 | ono-plugin-project-inspector | Stale .claude-plugin/marketplace.json with local relative source path **(missed)** | Medium | yagil | 0.1 | — |
| MGA-39 | ono-plugin-project-inspector | inspection-state.ts uses __dirname-relative path to registry.json; breaks when run from non-standard directory | Medium | magen (yagil) | 1 | — |
| MGA-40 | ono-plugin-project-inspector | migrateState() is a no-op stub; silently produces malformed state on schema change | Medium | magen (yagil) | 1 | — |
| MGA-41 | ono-plugin-qa | No Opium automation integration (zero references in entire repo) | Critical | Arditi | 3–5 | Opium data contract |
| MGA-42 | ono-plugin-qa | No Platform Guardian integration point (no /qa-status command, no structured JSON output) | High | Tom | 2–3 | — |
| MGA-43 | ono-plugin-qa | No standards/ directory (no QA-side naming conventions, severity ratings, pass/fail criteria) | High | Arditi | 1–2 | — |
| MGA-44 | ono-plugin-qa | qa-coverage-reviewer and qa-coverage-analysis/SKILL.md omit "Build / Install / Testing Instructions" from handoff contract **(missed)** | High | magen + Arditi | 0.5 | MGA-33 |
| MGA-45 | ono-plugin-qa | plugin.json declares no commands/skills/agents arrays | Medium | magen | 0.5 | — |
| MGA-46 | ono-plugin-qa | No docs/ directory; cross-plugin artifact schema undocumented formally | Medium | magen | 1 | — |
| MGA-47 | ono-plugin-qa | No example output artifacts for QA engineer onboarding | Medium | Arditi | 1 | — |
| MGA-48 | ono-plugin-qa | Hook does not block git add (only commit and push) | Low | magen | 0.5 | — |
| MGA-49 | ono-plugin-qa | qa-workspace.json has no JSON schema or validation | Low | magen | 0.5 | — |
| MGA-50 | spec-team-toolkit | plugin.json missing mcpServers block despite Figma MCP dependency **(missed)** | High | magen | 0.1 | — |
| MGA-51 | spec-team-toolkit | No formal test evaluations run on either skill | High | magen + spec team | 2–3 | — |
| MGA-52 | spec-team-toolkit | "docx skill" referenced in finalization phase but undeclared and unidentified | High | magen | 1 | — |
| MGA-53 | spec-team-toolkit | plugin.json has no author.email; marketplace.json entry also has no author email **(missed)** | Low | magen | 0.1 | — |
| MGA-54 | spec-team-toolkit | lld-figma-spec is Umbraco-CMS-only but ono-plugin-qa accepts its output as mobile test plan input without any format caveat **(missed)** | Medium | magen + spec team | 1 | — |
| MGA-55 | spec-team-toolkit | No commands/ directory (no slash commands) | Medium | magen | 1–2 | — |
| MGA-56 | spec-team-toolkit | No templates/ directory (no starter files for scope-list.md or hld-draft.md) | Medium | magen | 1 | — |
| MGA-57 | spec-team-toolkit | No docs/ directory | Low | Tom | 0.5 | — |
| MGA-58 | org-platform-guardian | Repo B does not exist **(missed by all plugin-scoped audits)** | Critical | Tom + PM + Design Lead + Architect | 6+ | OQ-1 |
| MGA-59 | ono-mobile-dev-plugin + ono-plugin-qa + ono-plugin-marketplace | Zero TV platform coverage (Apple TV, Android TV, Tizen, WebOS, Vidaa) | Critical | Tom + TV platform leads | 4–6 minimum | TV platform lead assignments |
| MGA-60 | ono-mobile-dev-plugin + ono-plugin-qa | Cross-repo handoff template schema drift; no version pin or notification mechanism **(missed)** | High | magen + Arditi | 0.5 | MGA-33 |
| MGA-61 | ono-mobile-dev-plugin + ono-plugin-marketplace | Feature branch merge removes /create-dev-plan with no coordinated Platform Guardian update | High | Tom + magen | 1 | Merge decision |
| MGA-62 | ono-mobile-dev-plugin + ono-plugin-qa + spec-team-toolkit + ono-plugin-marketplace | No inter-plugin dependency declarations in any manifest | Medium | magen + Tom | 1 | — |
| MGA-63 | ono-mobile-dev-plugin + ono-plugin-qa + spec-team-toolkit + ono-plugin-marketplace | Inconsistent plugin.json capability declaration (3 of 4 plugins use directory discovery only) | Medium | magen | 1 | — |
| MGA-64 | ono-mobile-dev-plugin + ono-plugin-qa | Duplicate mcpServers.figma declaration — co-installation behavior undocumented **(missed)** | Low | magen + Tom | 0.2 | — |
| MGA-65 | ono-mobile-dev-plugin + ono-plugin-qa + spec-team-toolkit | Missing .gitignore in 3 plugin repos | Low | magen | 0.5 | — |

---

## Backlog Items to Add

The following items are new and should be added to `docs/backlog.md` under the Milestone 3.5 Gap Backlog section. Items MGA-4 through MGA-10 already exist; the descriptions of MGA-4, MGA-5, MGA-6, and MGA-8 must be corrected per MGA-28.

**Correction to existing item MGA-4:**
> Remove the claim that the branch includes "iOS/Android/React standards content." The branch adds 2 new pipeline stages (dev-design-start, dev-feature-start), a new dd-template, and updated rn-architect. It does not deliver any platform standards — all 14 iOS/Android/React standard files remain "Not yet authored" on the branch. MGA-5, MGA-6, and MGA-8 are fully independent of MGA-4.

---

- [ ] **MGA-11: Register Platform Guardian in marketplace** — Add Platform Guardian plugin entry to `ono-plugin-marketplace/marketplace.json` with HTTPS source URL, version, description, and author email. Bump marketplace version to 1.4.0. Update README.md plugin table and CHANGELOG. Owner: Tom. Effort: 1 session. Blocked by M1.1 (plugin repo must exist at a real GitHub URL). **Planning required before execution.**

- [ ] **MGA-12: Add version pinning to marketplace plugins** — Replace `ref: main` with specific git tags or commit SHAs on all 4 plugin entries. Add a `sha` or `tag` field to the marketplace schema. Document a rollback procedure in the marketplace README. Owner: magen. Effort: 1 session. **Planning required before execution.**

- [ ] **MGA-13: Add CI validation pipeline to ono-plugin-marketplace** — Create a GitHub Actions workflow that validates marketplace.json against the schema, verifies each plugin URL is reachable, and confirms each referenced ref exists. Fails on any unreachable URL. Owner: magen. Effort: 2 sessions.

- [ ] **MGA-14: Sync spec-team-toolkit version in marketplace** — Update `marketplace.json` `spec-team-toolkit` entry from v0.1.0 to v0.2.0. Bump marketplace `metadata.version` from 1.3.3 to 1.3.4. Update CHANGELOG. Owner: magen. Effort: 0.1 sessions (< 15 minutes).

- [ ] **MGA-17+MGA-23+MGA-20: iOS platform full completion** — Author all 5 iOS standards (`swift-standards.md`, `swiftui-uikit-standards.md`, `ios-architecture.md`, `xcode-build-signing.md`, `ios-performance.md`) with stable SWIFT-*/IOS-ARCH-* IDs; author all 3 iOS skills (`ios-dev-planning`, `ios-feature-implementation`, `ios-code-review`); author all 4 iOS agents (`ios-architect`, `ios-feature-developer`, `ios-code-reviewer`, `ios-performance-reviewer`). Note: this work is independent of and not reduced by merging MGA-4/MGA-26. Owner: Boris. Effort: 6–9 sessions total. **Planning required before execution.**

- [ ] **MGA-18+MGA-24+MGA-21: Android platform full completion** — Same scope as iOS but for Android: 5 standards with KOTLIN-*/ANDROID-ARCH-* IDs, 3 skills, 4 agents. Independent of MGA-26 merge. Owner: Guy. Effort: 6–9 sessions total. **Planning required before execution.**

- [ ] **MGA-19+MGA-25+MGA-22: React web platform full completion** — Author all 6 React standards with stable REACT-* IDs (including web security: XSS/CSRF/CSP coverage), all 3 React skills, all 4 React agents. Update `mobile-security.md` to cover web security. Author React-specific accessibility and i18n rules. Owner: magen. Effort: 7–10 sessions total. **Planning required before execution.**

- [ ] **MGA-26: Assign merge decision owner for feature branch** — Assign a named owner and target date for merging `feat/design-and-feature-start-stages`. Coordinate the merge with a simultaneous Platform Guardian pipeline-stage map update so both change atomically. Bump `marketplace.json` `ono-mobile-dev-plugin` entry to v0.3.0. Owner: magen + Tom. Effort: 1 session. **Planning required before execution.**

- [ ] **MGA-28: Correct docs/marketplace-gap-audit.md (this document supersedes)** — Done by writing this revised document. Verify backlog.md MGA-4 description does not claim branch delivers authored standards. Owner: Tom. Effort: 0 (completed).

- [ ] **MGA-33+MGA-44+MGA-60: Fix cross-repo handoff template schema drift** — Add a `template_version` field to `qa-handoff-template.md` YAML frontmatter. Update `qa-coverage-reviewer.md` and `qa-coverage-analysis/SKILL.md` to include "Build / Install / Testing Instructions" in the fixed section contract. Create a cross-plugin contract document in `ono-plugin-marketplace` or a shared location that pins the expected section list and version. Platform Guardian to monitor this contract version and alert on drift. Owner: magen + Arditi. Effort: 0.5 sessions.

- [ ] **MGA-34: Verify CLAUDE_PLUGIN_ROOT in Claude Code hook execution** — Test all three hooks (`protect-secrets`, `require-approval-before-code`, `block-main-branch-changes`) in a real installed-plugin context. Confirm `CLAUDE_PLUGIN_ROOT` is set by Claude Code at hook execution time. If not set, add absolute-path fallback logic to all three hook shell scripts. Document verified behavior. Owner: magen + Tom. Effort: 0.5 sessions.

- [ ] **MGA-35+MGA-36: Resolve agent tool-execution gap in ono-plugin-project-inspector** — Either add `Bash` to the agent's tool list (allowing direct script execution) or redesign the `inspection-state` and `update-audit-index` integration so the LLM does not need to shell out (e.g., parse state from AUDIT.md directly in the skill, without a TypeScript runner). Document the verified execution path for both scripts. Owner: magen (yagil). Effort: 2 sessions. **Planning required before execution.**

- [ ] **MGA-37: Add TypeScript runtime configuration to ono-plugin-project-inspector** — Add `package.json` (with bun or ts-node as runtime), `tsconfig.json`, and a lock file. Resolve the ts-node vs bun inconsistency. Pin the runtime version. Add a `README` section on how to run scripts and from which directory. Owner: magen (yagil). Effort: 1 session.

- [ ] **MGA-38: Remove stale marketplace.json from ono-plugin-project-inspector** — Either delete `.claude-plugin/marketplace.json` (the old bootstrap file with `source: './'`) or update it to reference the real HTTPS marketplace URL. Add a comment in CHANGELOG. Owner: yagil. Effort: 0.1 sessions.

- [ ] **MGA-41: Opium automation integration in ono-plugin-qa** — Define the Opium data contract (what format Opium expects for test cases). Then implement: at minimum an `/export-to-opium` command, an Opium-format template, and a skill for translating QA test-plan sections into Opium test cases. Owner: Arditi. Effort: 3–5 sessions. Blocked by: Opium data contract definition. **Planning required before execution.**

- [ ] **MGA-42: Add Platform Guardian integration point to ono-plugin-qa** — Implement a `/qa-status --json` command that outputs structured JSON (feature slug, test-plan status, approved date, coverage-report presence). This is the machine-readable endpoint Platform Guardian will consume. Owner: Tom (to spec) + magen (to implement). Effort: 2–3 sessions.

- [ ] **MGA-43: Author QA standards** — Create `standards/` directory in `ono-plugin-qa`. Document at minimum: pass/fail criteria definitions, severity ratings for coverage gaps (Critical/High/Medium/Low), test-case ID naming conventions, QA repo folder structure conventions. Owner: Arditi. Effort: 1–2 sessions.

- [ ] **MGA-50: Add mcpServers block to spec-team-toolkit plugin.json** — Add the Figma MCP server declaration (matching the pattern in `ono-mobile-dev-plugin` and `ono-plugin-qa`). Owner: magen. Effort: 0.1 sessions.

- [ ] **MGA-51: Run formal test evaluations on spec-team-toolkit skills** — Run `hld-builder` and `lld-figma-spec` on real projects. Document findings, edge cases, and any prompt adjustments needed. Produce at least one example output artifact per skill. Owner: magen + spec team. Effort: 2–3 sessions.

- [ ] **MGA-52: Identify and declare docx skill dependency in spec-team-toolkit** — Identify which plugin or tool provides "the docx skill." Declare it in `plugin.json` (as a peer dependency or MCP server). If it does not exist, scope and build it or replace the Word export step with a documented alternative. Owner: magen. Effort: 1 session.

- [ ] **MGA-53: Add author email to spec-team-toolkit plugin.json and marketplace.json** — Add `author.email` to both files with the correct team contact. Owner: magen. Effort: 0.1 sessions.

- [ ] **MGA-54: Clarify lld-figma-spec scope and add QA plugin format caveat** — Document explicitly in `lld-figma-spec/SKILL.md` and `spec-team-toolkit/README.md` that this skill produces Umbraco-CMS-oriented LLD output, not a general-purpose mobile LLD. Update `ono-plugin-qa/README.md` to note that `--spec=` input must be a platform-appropriate LLD, not an Umbraco CMS spec. Scope a platform-agnostic LLD format if mobile LLD generation is needed. Owner: magen + spec team. Effort: 1 session.

- [ ] **MGA-58: Create Repo B (Org Knowledge Repository)** — Create a real git repository (not just the local template directory). Assign domain owners. Resolve OQ-1 (write access + approval process). Populate at minimum: `platforms/ios-mobile/` (pilot platform), `architecture/approved-libraries.md`, and `product-spec/ios-mobile/` with 3–5 real features. Owner: Tom + PM + Design Lead + Architect. Effort: 6+ sessions (M4.1 through M4.6 as scoped in main backlog). **This is the single highest-priority blocker for Platform Guardian going live.**

- [ ] **MGA-59: Scope TV platform plugin work** — Decide whether TV platforms (Apple TV, Android TV, Tizen, WebOS, Vidaa) get a new `ono-tv-dev-plugin` or a major extension of `ono-mobile-dev-plugin`. Assign TV platform leads. Add tvOS detection to `repo-analyst` (react-native-tvos package, Info.plist UIDeviceFamily 3). Author Tizen/WebOS/Vidaa as new platform standards (D-pad focus management, 10-foot typography, memory budgets). Register any new plugin in marketplace.json. Start with Apple TV (most overlap with existing mobile plugin). Owner: Tom (to scope) + TV platform leads (to author). Effort: 4–6 sessions minimum. **Planning required before execution.**

- [ ] **MGA-61: Coordinate feature branch merge with Platform Guardian pipeline update** — Establish a merge decision and date for `feat/design-and-feature-start-stages`. At the same time, update Platform Guardian's pipeline stage registry to source stage definitions from `plugin.json` version rather than a hardcoded command list. The pipeline map for v0.3.0 must be ready before the branch merges. Owner: Tom + magen. Effort: 1 session (coordination only).

- [ ] **MGA-62: Add inter-plugin dependency declarations to marketplace schema** — Add a `peerPlugins` or `dependsOn` field to the marketplace schema. `ono-plugin-qa` should declare `ono-mobile-dev-plugin` as a peer. Update marketplace README to document which plugins are designed to be co-installed. Platform Guardian should check peer plugin installation status before enforcing cross-plugin pipeline gates. Owner: magen + Tom. Effort: 1 session.

- [ ] **MGA-63: Standardize plugin.json capability declaration** — Either require `commands`, `skills`, and `agents` arrays in all plugin manifests (following `ono-plugin-project-inspector`'s pattern) or document directory scanning as the canonical discovery mechanism and provide a standard scanning algorithm for Platform Guardian to implement. Apply consistently across all plugins. Owner: magen. Effort: 1 session.

- [ ] **MGA-65: Add .gitignore to three plugin repos** — Add a standard `.gitignore` to `ono-mobile-dev-plugin`, `ono-plugin-qa`, and `spec-team-toolkit` covering at minimum: `node_modules/`, `.DS_Store`, `.env`, `*.local`, `dist/`, `.cache/`. Owner: magen. Effort: 0.5 sessions.

---

## Repos Audited

| Repo | Audit Status |
|------|-------------|
| ono-plugin-marketplace | Reviewed — 6 gaps |
| ono-mobile-dev-plugin | Reviewed — 18 gaps (including branch analysis) |
| ono-plugin-project-inspector | Reviewed — 6 gaps |
| ono-plugin-qa | Reviewed — 9 gaps |
| spec-team-toolkit | Reviewed — 8 gaps |
| org-platform-guardian (Repo B) | Not plugin-scoped — 1 critical gap identified by adversarial pass |

**Total plugin completion gap: ~30–40 sessions across Boris, Guy, Arditi, magen, spec team, and Tom.**
**Platform Guardian development: separate track — see main backlog.**
**TV platform work: unscoped, unowned — requires dedicated planning session before any estimate.**
