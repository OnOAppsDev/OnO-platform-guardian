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
- [x] **G0.4: Plugin skeleton** — `claude plugin validate .` passes; deps on the 4 core Ono plugins (Matrix plugins pending decision). repo root becomes the plugin: `.claude-plugin/plugin.json`, `hooks/`, `skills/`, `scripts/`, `tests/`. Matches org conventions (`ono-mobile-dev-plugin` layout, author "Ono Apps").
- [x] **G0.5: Feasibility — org-wide install** — Confirm Claude for Organizations managed settings can force-add the marketplace and enable all plugins. Record result in `docs/vision.md`. **Result: feasible** — plugin `dependencies` (bundle) + managed `enabledPlugins`; mods for context %. See vision "How it is built".

## G1 — Session opener (1–2 sessions)

- [ ] **G1.1: `scripts/git-status.sh`** — Deterministic JSON: repo?, current branch, central branch (detected: origin HEAD → `develop` → `main` → `master`; project override), ahead/behind vs. central after `git fetch`, dirty files, on-central-branch flag, detection confidence. Fails open outside git.
- [ ] **G1.2: SessionStart hook** — Runs on `startup` (and `clear`); injects the git report + opener instructions as context.
- [ ] **G1.3: `session-opener` skill** — Greets, presents git state. Behind central → ⚠️🚨 warning, make sure the employee understands, explain options (merge / rebase / continue as-is), and **wait for their decision** — never auto-update. Unsure of central branch → ask which branch to branch from. On the central branch → offer to create a work branch.
- [ ] **G1.4: Project config** — Optional `.platform-guardian.json` in the work repo (central branch override, team/role). Absent = auto-detect.
- [ ] **G1.5: Tests** — Script tests against throwaway git repos: clean, dirty, behind, ahead, diverged, detached HEAD, no remote, `develop` vs `main`.

## G2 — Router (2–3 sessions)

- [ ] **G2.1: Routing map** — From the fresh org repos (latest branch): intent (bug / feature / QA mobile / QA web / spec / repo onboarding / release) → plugin → entry command → human-only commands (`disable-model-invocation`). Stored as data (`routing/routes.json`), versioned with the plugins.
- [ ] **G2.2: Intent intake** — "Bug, feature, testing, spec? Tell me what we're doing" → classify → confirm → start the right command.
- [ ] **G2.3: Resume in-progress work** — Read each plugin's state (dev task state / `next-command.ts`, QA ledger, Matrix `mqa.mjs plan state`, spec status, `.ono/repo-knowledge.json`) → "you're at stage X of feature Y".
- [ ] **G2.4: Missing-plugin detection** — Required plugin not enabled → show the exact install command.
- [ ] **G2.5: Drift guard** — Detect when a plugin's commands no longer match `routes.json` (plugin version bump).

## G3 — Session closer / context manager (1–2 sessions)

- [ ] **G3.1: Session-length signal** — UserPromptSubmit hook measuring transcript size; threshold → close-out suggestion. Also trigger on task/stage completion.
- [ ] **G3.2: Git close-out** — Commit what belongs; **never push to the central branch without a PR**; ask target branch + reviewers; open PR.
- [ ] **G3.3: Handoff note + `/clear` instruction** — Save where we are (resumable by G2.3), then tell the employee very clearly: everything is saved, run `/clear`, start a new session.

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
