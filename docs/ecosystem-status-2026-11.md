# Ecosystem Status — 2026-11-08

Status diff of the OnOAppsDev plugin ecosystem against the 2026-07-08 baseline (`docs/marketplace-gap-audit.md`).
Method: fresh clones of all 6 active repos → 6 parallel read-only agents (diff vs. baseline MGA items) → critical claims re-verified by hand.

---

## TL;DR

The ecosystem moved fast in four months and **absorbed much of what Platform Guardian was meant to build**:

1. **Platform standards are now real.** iOS (5 files), Android (10), React (7 incl. Smart TV), React Native (6), shared (7 incl. TV baseline, web security). Stable citable rule IDs (`IOS-*`, `AND-*`, `REACT-*`, `REACT-TV-*`, `SEC-*`, `A11Y-*`). Baseline Critical gaps MGA-17/18/19/23/24/25/27/29/30 are closed.
2. **Phase gating already exists inside the plugins.** `ono-mobile-dev-plugin` runs an 8-stage pipeline where each stage refuses to start until the previous artifact is approved, plus hooks blocking code-before-approval and main-branch edits. `ono-plugin-qa` has a deterministic QA ledger with a JSON readiness verdict and fingerprint-pinned sign-off. `Matrix-qa-plugin` binds approvals to content fingerprints. The dev plugin's release gate already consumes signed QA readiness.
3. **Repo knowledge + CLAUDE.md generation belong to project-inspector.** It now emits `.ono/repo-knowledge.json` (v1 contract, consumed by dev + QA plugins), detects staleness, discovers all 7 platform surfaces including TV, and owns per-repo `CLAUDE.md` generation via protected blocks.
4. **What nobody covers:** org-wide enforcement that does not depend on each developer installing each plugin; a cross-plugin view (one feature's state across spec → dev → QA → release); spec/Figma currency; ecosystem health (CI, pinning, contract drift, manifests); Vidaa; and Repo B (still does not exist — but its purpose has changed, see below).

**Implication:** Guardian's original scope (MCP server that gates 7 phases, audits against Repo B, generates CLAUDE.md) is now largely **redundant or conflicting**. Its goal must be redefined.

---

## Per-repo summary

| Repo | Version (Jul → Nov) | Activity since Jul | Headline |
|---|---|---|---|
| ono-mobile-dev-plugin | 0.3 → **0.7.0** | 206 commits, PRs #2–#54 | Standards authored for all 4 platforms + TV (tvOS, Android TV, Tizen/webOS). 8-stage pipeline, Bug Flow, QA release gate, ~55 TS scripts + tests. Platform agents replaced by 7 shared role agents + lane skills. |
| ono-plugin-qa | 0.3 → **0.11.0** | 14 commits, PRs #1–#8 | QA ledger (builds, smoke, execution, bugs, regression, readiness, sign-off) — 13 new commands. Appium automation + live locator verification. 5 contract docs. |
| ono-plugin-project-inspector | 0.7 → **0.11.0** | PRs #1–#5 | `repo-knowledge` manifest + contract, staleness detection, Targets/Surfaces model (all 7 platforms), evidence gate, 6 test suites. |
| spec-team-toolkit | 0.2 → **0.4.2** | 5 commits, direct to main, no PRs | `lld-mobile-spec` (SPAC), `lld-backend-spec`; DRAFT→READY lifecycle; READY blocked without real API contracts. |
| ono-plugin-marketplace | → **1.5.0** | 7 commits, PRs #1–#3 | Per-plugin versions removed (plugin.json is source of truth). 2 new plugins registered: matrix-studio, matrix-qa-plugin (now 6 entries). ~5.6k lines of ecosystem architecture docs. |
| **Matrix-qa-plugin** (NEW) | **0.1.0** (2026-10-21) | 3 commits, Magen | Web QA for client Matrix IT: LLD → test plan → review → approve → Playwright. Strongest approval mechanism in the ecosystem (script-only status writes, fingerprint-bound approval, `disable-model-invocation` on approve). |
| matrix-studio (NEW, registered) | — | not audited | Figma design-system plugin. Lives in a **different GitHub org** (`OnOApps-Admin/MatrixStudioPlugin`). |

---

## Baseline gap verdicts

### Closed / obsolete (22)

| ID | Gap | Verdict | Evidence |
|---|---|---|---|
| MGA-4, MGA-26 | Feature branch merge owner / merge | CLOSED | `feat/design-and-feature-start-stages` = PR #1, merged 2026-07-09 (verified) |
| MGA-14 | spec-team-toolkit version drift in marketplace | OBSOLETE | marketplace PR #3 removed all per-plugin versions |
| MGA-17/23/20 | iOS standards / skills / agent | CLOSED / OBSOLETE | dev PR #17, #19, #21, #22; platform agents removed in PR #40 by design |
| MGA-18/24/21 | Android standards / skills / agent | CLOSED / OBSOLETE | dev PR #4, #12, #13 (10 standards files, verified) |
| MGA-19/25/22 | React standards / skills / agent | CLOSED / OBSOLETE | dev PR #32, #33, #34 |
| MGA-27 | No web security (XSS/CSRF/CSP) | CLOSED | dev PR #14 — `SEC-WEB-*`, `SEC-COOKIE-*` |
| MGA-28 | Audit misstatement | OBSOLETE | standards are now actually authored |
| MGA-29 | a11y RN-only | CLOSED | dev PR #6, #38 |
| MGA-30 | i18n RN-only | CLOSED | `shared/i18n-rtl.md` covers all 4 |
| MGA-31 | RTK-only state mgmt | CLOSED | RTK rules conditional on detection |
| MGA-32 | dev plugin no docs/ | CLOSED | 7 contracts + `docs/planning/` |
| MGA-38 | inspector stale marketplace.json | CLOSED | inspector PR #3 |
| MGA-44 | QA handoff build/install section | CLOSED | `ono-plugin-qa/docs/dev-handoff-contract.md` |
| MGA-46 | QA no docs/ | CLOSED | 5 contract docs |
| MGA-48 | QA hook misses `git add` | OBSOLETE | deliberate, documented in QA PR #2 |

### Partial (11)

MGA-34 (CLAUDE_PLUGIN_ROOT — 1 of 3 hooks has fallback) · MGA-37 (inspector: bun unified, still no package.json) · MGA-42 (QA: no `/qa-status`, but ledger emits JSON readiness) · MGA-43 (QA rules live in contracts, no `standards/`) · MGA-47 (QA fixtures, no onboarding examples) · MGA-53 (marketplace email fixed, plugin.json not) · MGA-54 (toolkit side fixed via `lld-mobile-spec`; QA README caveat open) · MGA-56 (templates under `references/`, no top-level) · **MGA-59 TV** (tvOS, Android TV, Tizen/webOS covered; **Vidaa zero hits**, verified) · MGA-60 (QA pins producer commit `9472f43`, no template version) · MGA-61 (merge happened; Guardian docs still assume 7 stages).

### Still open — notable

- **MGA-35/36 (High, worse):** inspector agent is `tools: Read, Skill` (verified), yet 6 hooks + 2 skills require `bun scripts/…`. The knowledge-freshness certification chain depends on this path.
- **MGA-12 / MGA-13:** all 6 marketplace entries use `ref: main`; no CI in the marketplace — and no CI in any plugin repo except via local scripts.
- **MGA-58 Repo B:** still does not exist — but standards now live in `ono-mobile-dev-plugin/standards/`, so Repo B's original purpose is largely served elsewhere.
- **MGA-62/63:** no `dependsOn`, no capability arrays (inspector excepted). Marketplace README states Claude Code has no cross-plugin dependency mechanism; contracts are vendored byte-identical instead.
- **MGA-64:** duplicate `figma` MCP now declared by 3 plugins.
- MGA-15, 16, 39, 40, 45, 49, 50, 51, 52, 55, 57, 65 — unchanged.

---

## New gaps (since July)

| ID | Repo | Gap | Sev |
|---|---|---|---|
| MGA-66 | marketplace | matrix-studio sourced from a different GitHub org (`OnOApps-Admin`) — split governance | High |
| MGA-67 | spec-team-toolkit | Bitbucket MCP + draw.io used but not declared (extends MGA-50) | High |
| MGA-68 | spec-team-toolkit | Specs written to `/mnt/user-data/outputs/` (claude.ai path) — no stable in-repo location; headers are bold-Markdown, not YAML frontmatter | Medium |
| MGA-69 | spec-team-toolkit | `lld-mobile-spec` near-duplicates `anthropic-skills:create-frontend-spec` — trigger collision / drift | Medium |
| MGA-70 | spec-team-toolkit / Matrix-qa | Direct-to-main, no PRs, single maintainer | Medium |
| MGA-71 | ono-plugin-qa | Git-write hook matches any folder name containing "qa" — likely blocks commits in `Matrix-qa-plugin` (inferred, not run) | Medium |
| MGA-72 | ono-plugin-qa | `appium-mcp@latest` unpinned | Medium |
| MGA-73 | QA (both) | Two QA plugins, two state schemas (YAML frontmatter + ledger vs. key:value + fingerprints), no shared QA-status contract; React web boundary unclear | Medium |
| MGA-74 | Matrix-qa | No CI; tests + validator never run automatically (tests not executed in this audit) | High |
| MGA-75 | Matrix-qa | ~~Client-specific ("Matrix IT") plugin in the internal registry~~ — confirmed in use by the QA team (web) 2026-11-08; `UNLICENSED` on a public repo; author mismatch vs marketplace | Low–Med |
| MGA-76 | inspector ↔ dev | Vendored repo-knowledge contract intentionally behind ("Stage B"); no version check between copies | Medium |
| MGA-77 | dev plugin | iOS lane has 5 standards vs Android 10 — no testing / networking / persistence docs | Medium |
| MGA-78 | all except Matrix | No approval command sets `disable-model-invocation` (`/approve-qa-test-plan`, `/qa-signoff`, `/inspect-approve` — "running it IS the approval"); the model can self-approve. Guardian enforces a human-only list (`routing/routes.json`) | High |
| MGA-79 | dev plugin | Feature Analysis, Dev Plan and Task Breakdown have no defined filename/path; feature `/review-code`, `/review-security`, release checklist write no file. Feature flow has no machine-readable next step (only Bug Flow `next_command`) | Medium |
| MGA-80 | ono-plugin-qa | Commit/push hook falls back to "folder name contains `qa`" (matches e.g. `aqua`); README internals table lists 6 of 17 commands; plan status lives in a fenced yaml block, not frontmatter | Low–Med |
| MGA-81 | spec toolkit | `lld-mobile-spec` calls "Phase 16 — DD Starter" which doesn't exist; outputs hardcoded to `/mnt/user-data/outputs/` (claude.ai sandbox) — no repo location in Claude Code (extends MGA-68) | Medium |
| MGA-83 | dev, qa, Matrix-qa, matrix-studio | Four plugins each bundle their own `figma` MCP server — with all bundled under Guardian, employees may see several Figma auth prompts / duplicate tools. **Likely a non-issue (checked 2026-11-08):** all four are the identical endpoint (`http`, `https://mcp.figma.com/mcp`), and Claude Code matches plugin servers by endpoint and connects once ([MCP docs → Scope hierarchy and precedence](https://code.claude.com/docs/en/mcp.md)). Confirm in the live test §6.3 | Low |
| MGA-82 | Matrix-qa | Guard denies every git write and `gh pr create` session-wide once the session starts inside a Matrix repo — also for other repos in that session | Low (by design) |

---

## Corrections to our own records

- **Session 4 is missing from `docs/session-log.md`.** The backlog records SC-2 as "Resolved in Session 4" (three-layer enforcement: PreToolCall hook / skill invocations / human gate), but no Session 4 entry exists. Not reconstructed here.
- **`~/Projects/OnO Marketplace/` clones were gone**; re-cloned 2026-11-08.
- An agent claimed PR #1 merged 07-07 (before the July audit). **Wrong** — verified 2026-07-09. The July "unmerged" finding was correct at the time.
- project-inspector was already in the July audit; only Matrix-qa-plugin and matrix-studio are new.

---

## What Guardian can reuse instead of building

| Guardian need | Already exists | Where |
|---|---|---|
| Dev phase gates | 8-stage approval chain + hooks | ono-mobile-dev-plugin |
| QA gate | Readiness verdict (JSON, R1–R9, fingerprinted sign-off) | ono-plugin-qa `qa-ledger.mjs` |
| QA gate (web) | `mqa.mjs plan state` JSON | Matrix-qa-plugin |
| Release gate | `qa-release-gate.ts` consuming signed QA readiness | ono-mobile-dev-plugin |
| Org standards | Citable rule IDs per platform | ono-mobile-dev-plugin `standards/` |
| Repo knowledge / surfaces / CLAUDE.md | `.ono/repo-knowledge.json`, managed CLAUDE.md blocks | project-inspector |
| Spec lifecycle | DRAFT → READY, API-contract gate | spec-team-toolkit |
| Approval-integrity pattern | Fingerprint-bound approvals, human-only commands | Matrix-qa-plugin, ono-plugin-qa |
| Stage map source | `scripts/next-command.ts` | ono-mobile-dev-plugin |

---

## Decision — Guardian's redefined goal (2026-11-08)

**North star:** Platform Guardian is the *only* plugin employees install and the single entry point into the org's processes. It opens every session with a clean, current git state, asks what the employee came to do (bug / feature / QA / spec), routes them into the process the org plugins already define, and manages the session's lifetime — tidying git (commit / PR) and telling the employee clearly to `/clear` when the task or the context is done. The employee never has to guess which plugin command to run.

**Git policy (user decisions):**
- Central branch is per-project (usually `develop`); Guardian detects it, and when unsure **asks** at start which branch to branch from.
- Never push to the central branch without a PR; at the end, ask where to open the PR and who reviews.
- Behind the central branch → **no auto-update**: surface it with ⚠️🚨 warnings, confirm the employee understands, and ask what to do with the options explained.

**Milestones:** G0 reset (vision doc, archive old MCP/7-phase plan, plugin skeleton, marketplace registration) → G1 session opener (git hygiene) → G2 router (intent → org plugin command, resume in-progress work) → G3 closer / context manager → G4 org rollout via managed settings + pilot. Later: cross-plugin feature view, ecosystem health.

**Open feasibility check (G0):** Claude Code has no cross-plugin dependency mechanism; verify that Claude for Organizations managed settings can enable the marketplace and all its plugins org-wide. Fallback: Guardian detects missing plugins and shows the install command. Commands with `disable-model-invocation` (e.g. `/qa-approve`) stay human-typed — Guardian tells the employee what to type.
