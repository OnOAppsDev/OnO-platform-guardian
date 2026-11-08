# Platform Guardian — Backlog

Last updated: 2026-11-08

Goal and design: `docs/vision.md`. Ecosystem state the router depends on: `docs/ecosystem-status-2026-11.md`.
The July plan (MCP server / 7-phase gate / Repo B) and its backlog are archived in `archive/2026-07-mcp-plan/`.

Each item is scoped to one session (~2–3 hours) unless noted. Estimate for G0–G4: **7–11 sessions** + a 1–2 week pilot. Re-estimate after G1.

---

## G0 — Reset (1 session)

- [x] **G0.1: Ecosystem status refresh** — 6-repo diff vs. July baseline. Output: `docs/ecosystem-status-2026-11.md`.
- [x] **G0.2: Archive the July plan** — `archive/2026-07-mcp-plan/`.
- [x] **G0.3: Vision document** — `docs/vision.md`: north star, session flow, git policy, routing principles, non-goals, feasibility notes.
- [x] **G0.4: Plugin skeleton** — `claude plugin validate .` passes; deps on all six org plugins (Matrix plugins added 2026-11-08 per G3.6). repo root becomes the plugin: `.claude-plugin/plugin.json`, `hooks/`, `skills/`, `scripts/`, `tests/`. Matches org conventions (`ono-mobile-dev-plugin` layout, author "Ono Apps").
- [x] **G0.5: Feasibility — org-wide install** — Confirm Claude for Organizations managed settings can force-add the marketplace and enable all plugins. Record result in `docs/vision.md`. **Result: feasible** — plugin `dependencies` (bundle) + managed `enabledPlugins`; mods for context %. See vision "How it is built".

## G1 — Session opener (1–2 sessions)

- [x] **G1.1: `scripts/git-status.sh`** — Deterministic JSON: repo?, current branch, central branch (detected: origin HEAD → `develop` → `main` → `master`; project override), ahead/behind vs. central after `git fetch`, dirty files, on-central-branch flag, detection confidence. Fails open outside git.
- [x] **G1.2: SessionStart hook** — Runs on `startup` (and `clear`); injects the git report + opener instructions as context.
- [x] **G1.3: `session-opener` skill** — Greets, presents git state. Behind central → ⚠️🚨 warning, make sure the employee understands, explain options (merge / rebase / continue as-is), and **wait for their decision** — never auto-update. Unsure of central branch → ask which branch to branch from. On the central branch → offer to create a work branch.
- [x] **G1.6: Read last session-log entry** — Opener reads `~/.claude/platform-guardian/<repo>/<branch>.md` (local, never in git) and starts with "last time you stopped at …".
- [x] **G1.4: Project config** — Optional `.platform-guardian.json` in the work repo (central branch override, team/role). Absent = auto-detect. Done: `centralBranch` read by the script; `team`/`role` reserved for G2 — `docs/project-config.md`.
- [x] **G1.5: Tests** — Script tests against throwaway git repos: clean, dirty, behind, ahead, diverged, detached HEAD, no remote, `develop` vs `main`. Done: `tests/run-all.sh` — 71 checks, mutation-checked, bash 3.2.
- [ ] **G1.7: Live test on the test machine** — install Guardian there (never here); verify the hook fires on startup and `/clear`, the report reaches the model, and the opener handles behind / on-central / ambiguous / clean. Check hook latency with a real remote.

## G2 — Router (2–3 sessions)

- [x] **G2.1: Routing map** — From the fresh org repos (latest branch): intent (bug / feature / QA mobile / QA web / spec / repo onboarding / release) → plugin → entry command → human-only commands (`disable-model-invocation`). Stored as data (`routing/routes.json`), versioned with the plugins. Done: 11 intents, human-only list, resume probes, git guards — from the 5 plugins at their latest `main`.
- [x] **G2.2: Intent intake** — "Bug, feature, testing, spec? Tell me what we're doing" → classify → confirm → start the right command. Done: `skills/work-router`; the opener hands over to it.
- [ ] **G2.3: Resume in-progress work** — Read each plugin's state (dev task state / `next-command.ts`, QA ledger, Matrix `mqa.mjs plan state`, spec status, `.ono/repo-knowledge.json`) → "you're at stage X of feature Y". **Partly done:** probes per plugin in `routes.json` `resume`, applied by the router skill. Remaining: scripted adapters (feature-doc discovery by frontmatter, two QA schemas — MGA-73/79) if the live test shows the skill-level probe is unreliable.
- [x] **G2.4: Missing-plugin detection** — Required plugin not enabled → show the exact install command. Done (in the router skill).
- [x] **G2.5: Drift guard** — Detect when a plugin's commands no longer match `routes.json` (plugin version bump). Done: `scripts/check-routes.sh <plugins-dir> [--strict]` — 43 refs verified against the org repos; wire into CI later.

## G3 — Session closer / context manager (1–2 sessions)

- [x] **G3.1: Session-length signal** — UserPromptSubmit hook measuring transcript size; threshold → close-out suggestion. Also trigger on task/stage completion. Done: `hooks/prompt-submit.sh` reads real context tokens from the transcript `usage`; default 120k, then every +40k (`PG_CLOSEOUT_TOKENS` / `PG_CLOSEOUT_STEP`). Stage completion → router skill.
- [x] **G3.2: Git close-out** — Commit what belongs; **never push to the central branch without a PR**; ask target branch + reviewers; open PR. Done: `skills/session-closer`; in QA repos whose plugin hooks block Claude's git writes (`guards.*` in the report) it hands the commands to the employee.
- [x] **G3.3: Close-out = session log + plain-language summary + `/clear`** — Guardian's own close (no personal-ritual scores/retros): write the local session-log entry (date · branch · what we did · where we stopped · next step · open PR), give a short plain-language summary, then tell the employee very clearly: everything is saved, run `/clear`, start a new session.
- [x] **G3.4: Committed-artifacts allowlist** — From the 6 org repos (latest branch): which files each plugin intends to be committed (inspector outputs, dev planning docs, QA plans, …) → `routing/committed-artifacts.json`. Done (commit / neverCommit / doNotTouch per plugin).
- [ ] **G3.5: Commit hygiene** — At close-out and before `git add`/`commit`: new untracked files not on the allowlist → ensure in `.gitignore` (change goes via the employee's PR); PreToolUse guard warns/blocks staging non-allowlisted new files. No blanket `*.md` ignore. **Partly done:** close-out hygiene in the closer skill. Remaining: the PreToolUse guard on `git add`/`commit`.

- [x] **G3.6: Decisions needed (user)** — (a) ~~Where do specs live?~~ **Decided 2026-11-08:** `docs/specs/<feature-slug>/` in the work repo, committed; `.html` previews not (routes.json `spec.saveTo`, allowlist). (b) ~~Matrix plugins?~~ **Decided 2026-11-08 (user):** every org plugin is part of the process — `matrix-qa-plugin` (QA team, web) and `matrix-studio` (designers, Figma design systems) added to `dependencies`; the router picks the QA plugin from the nature of the task and asks only when unclear.

## G4 — Rollout (1 session + pilot)

- [ ] **G4.1: Register in `ono-plugin-marketplace`** (closes MGA-11) — PR to the org repo; ask before opening.
- [ ] **G4.2: Managed settings** — Org-wide marketplace + plugin enablement (per G0.5 result).
- [ ] **G4.3: Pilot** — One team, 1–2 weeks; collect friction; fix.
- [ ] **G4.4: README rewrite** — Reflect the router product (install, session flow, routing table). Current README describes the archived plan.

## Later

- Cross-plugin feature view (one feature across spec → dev → QA → release).
- Ecosystem health checks (CI, pinning, contract drift — MGA-12/13/60/62/63/66..77).
- Spec / Figma currency check.

---

## Ecosystem gaps that affect the router

Owned by the plugin repos, not Guardian — tracked in `docs/ecosystem-status-2026-11.md`. The ones Guardian depends on:

- **MGA-35/36** — inspector's bun scripts may not run from its agent → `.ono/repo-knowledge.json` may be stale/missing; G2.3 needs a fallback.
- **MGA-68** — spec-team-toolkit writes specs outside the repo → G2.3 cannot resume spec work from repo state.
- **MGA-71** — ono-plugin-qa git hook may block commits in any "qa"-named folder → can collide with G3.2 close-out.
- **MGA-73** — two QA plugins, two state schemas → G2.3 needs two adapters.
