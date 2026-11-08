# Platform Guardian — Vision

Decided 2026-11-08. Supersedes the July 2026 MCP-server plan (`archive/2026-07-mcp-plan/`). Ecosystem facts behind this decision: `docs/ecosystem-status-2026-11.md`.

---

## North star

**Platform Guardian is the only plugin an Ono employee installs, and the single path through the org's processes.**

It opens every session with a clean, current git state, asks what the employee came to do, routes them into the process the org plugins already define, and manages the session's lifetime — tidying git and telling the employee clearly when to `/clear`. The employee never has to guess which plugin or command to run.

Guardian is a **coordinator, not a re-implementation.** The org plugins own their processes and gates; Guardian owns the path between them.

| Owned by the org plugins (Guardian reads / invokes) | Owned by Guardian |
|---|---|
| Dev pipeline + approval gates — `ono-mobile-dev-plugin` | Session opener: git hygiene, central-branch sync warning |
| QA ledger, readiness, sign-off — `ono-plugin-qa`, `matrix-qa-plugin` | Intent intake + routing to the right plugin command |
| Specs (HLD / LLD / SPAC) — `spec-team-toolkit` | Resume: "you're at stage X of feature Y" across plugins |
| Repo knowledge, per-repo `CLAUDE.md` — `ono-project-inspector` | Session closer: commit / PR / `/clear` with handoff note |
| Platform standards — `ono-mobile-dev-plugin/standards/` | Install surface: one plugin that brings the rest |

---

## The session, end to end

1. **Open** — first message of a session (SessionStart hook, `source: startup | clear`).
   - Greet. Run the git check (deterministic script, injected as context).
   - Report: repo, current branch, central branch, behind / ahead, uncommitted changes.
   - **Behind the central branch → ⚠️🚨 warning.** Make sure the employee sees and understands it, explain the options (update via merge / rebase, or continue knowingly), and **wait for their decision**. Never auto-update.
   - **On the central branch → offer to create a work branch.** When unsure which branch is central, **ask** which branch to branch from.
   - Then: "All set. Are we working on a bug, a feature, tests, a spec? Tell me what we're doing."
2. **Route** — classify the intent, confirm it, start the matching org-plugin command. If work is already in progress, resume it from the plugin's own state. Human-only steps (commands with `disable-model-invocation`, e.g. `/qa-approve`) are never run by the model — Guardian tells the employee exactly what to type.
3. **Work** — the org plugin's process runs as its owners designed it.
4. **Close** — when the task / stage is done or the context is getting long:
   - Commit what belongs. **Never push to the central branch without a PR.** Ask where to open the PR and who reviews.
   - Save a handoff note (resumable by step 2).
   - Tell the employee very clearly: everything is saved, run `/clear`, and start a new session with Guardian.

---

## Git policy

- **Central branch is per project** (usually `develop`). Detection order: project override (`.platform-guardian.json`) → `origin/HEAD` → `develop` → `main` → `master`. Low confidence → ask.
- **No direct push to the central branch.** All changes return through a PR; the employee chooses target branch and reviewers.
- **No silent updates.** Being behind is surfaced loudly and decided by the employee.
- **No force operations**, ever, from Guardian.

---

## How it is built (verified 2026-11-08)

| Need | Mechanism | Source |
|---|---|---|
| Install one plugin, get all | `dependencies` array in `.claude-plugin/plugin.json` ("bundle" pattern) — installing Guardian installs the org plugins | [Plugin dependencies](https://code.claude.com/docs/en/plugins/dependencies.md) |
| Nobody installs anything | Managed settings: `extraKnownMarketplaces` (`ono-plugin-marketplace`) + `enabledPlugins` (`platform-guardian@ono-plugin-marketplace: true`). Users can't disable. Needs an org **Owner** in the claude.ai admin console | [Org plugin management](https://code.claude.com/docs/en/plugins/org.md) |
| Session opener | SessionStart command hook → script via `${CLAUDE_PLUGIN_ROOT}` → `hookSpecificOutput.additionalContext` (≤ 10k chars) | [Hooks](https://code.claude.com/docs/en/hooks.md) |
| Route to org plugins | Model invokes `/<plugin>:<command>` as instructed by Guardian's skill | Skills docs |
| Context length | Preferred: a **mod** — `$.session.usage().context.percent`, `session.measure` after each turn. Requires Claude Code ≥ ~2.1.290 (local is 2.1.280). Fallback: UserPromptSubmit hook estimating from transcript size | [Mods reference](https://code.claude.com/docs/en/plugins/mods/reference.md) |
| `/clear` | **User-only.** Guardian instructs; it cannot trigger it | — |

**Dependency names** are marketplace names, not repo names: `ono-project-inspector`, `ono-mobile-dev-plugin`, `ono-plugin-qa`, `spec-team-toolkit`, `matrix-qa-plugin`, `matrix-studio`. Version constraints require release tags `<plugin>--v<version>` in each plugin repo — none exist today (MGA-16), so G0–G3 use unversioned dependencies.

---

## Non-goals

- Re-implementing any plugin's gates, standards, audits, or `CLAUDE.md` generation.
- Auto-updating branches, force-pushing, or pushing to the central branch.
- Owning org standards content (Repo B is dropped; standards live with the dev plugin).

---

## Open questions

1. **Matrix plugins** — `matrix-qa-plugin` and `matrix-studio` are client-specific (Matrix IT). Should Guardian depend on them for everyone, or only route to them when the project is a Matrix project?
2. **Who is the claude.ai org Owner** who will set managed settings (G4)?
3. **Minimum Claude Code version** for employees (mods need ≥ ~2.1.290) — enforce via managed auto-update?
