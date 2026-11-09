# Rollout (G4) — marketplace + org-wide install

Verified against the official docs on 2026-11-08: [Manage plugins for your organization](https://code.claude.com/docs/en/plugins/org.md), [Plugin dependencies](https://code.claude.com/docs/en/plugins/dependencies.md).

## Order

1. ✅ **PR #3 merged** into `master` (2026-11-09) — the marketplace entry tracks `master`.
2. **G4.1 — marketplace entry.** Ready on a local branch `add-platform-guardian` in the `ono-plugin-marketplace` clone (not pushed): manifest entry (`ref: master`), version 1.5.0 → 1.6.0, README + CHANGELOG in the marketplace's own style; `claude plugin validate .` passes. All six dependencies are already listed in that marketplace, so they resolve.
3. **Pilot install by hand** (one team) — `/plugin install platform-guardian@ono-plugin-marketplace`, confirm the six plugins come with it.
4. **G4.2 — managed settings** (org Owner), below.

## Repo visibility — ✅ public (2026-11-09)

**Done:** flipped by an admin on 2026-11-09; `git ls-remote` with no credentials works. The rest of this section is the background to the decision.

**Decided by the user: make it public.** Blocked on permissions: `tomzion90` has only *write*; changing visibility needs *admin* — today only `OnOApps-Admin`. That account: repo **Settings → Danger Zone → Change visibility → Make public** (or `gh repo edit OnOAppsDev/yes-platform-guardian --visibility public --accept-visibility-change-consequences`). After the flip: check an install works without credentials (`git ls-remote` with no auth).

Background:

The marketplace and all six Ono plugin repos are **public**; `yes-platform-guardian` was **private** (until 2026-11-09). Plugins install by cloning on the employee's machine with their stored git credentials and no prompt — so with a private repo, every employee needs GitHub read access to it **and** working git credentials (e.g. `gh auth setup-git`), or the install fails. Background auto-update has the same requirement.

| Option | Effect |
|---|---|
| Make `yes-platform-guardian` public (like the other six) | Installs work everywhere, no setup. Guardian holds no secrets — only scripts, skills and routing data. |
| Keep it private | Every employee needs org repo access + git credentials before Guardian can install; failures will look like "plugin not found". |

**Pre-public audit (2026-11-08)** — full history (27 commits, one author `tom@onoapps.com`): no tokens, keys, passwords or personal emails. Not secret, but internal — decide before flipping:

- `archive/2026-07-mcp-plan/docs/backlog.md` and `docs/marketplace-gap-audit.md` name colleagues as task owners (magen, Boris, Guy, Arditi) and an internal tool (Opium); the archive also links the old `appsadmin-design` repo.
- The repo name starts with `yes-` — if that names a client, it becomes public too.

Deleting those files only hides them from the current tree; they stay in history. Clean ways: (a) accept them as-is; (b) publish the plugin from a fresh public repo (plugin files only, new history) and keep this one private for planning; (c) rewrite history before flipping — not recommended (breaks every clone and PR #3).

## G4.2 — managed settings (claude.ai admin console)

Who: an **Owner** of the Claude organization. Where: **Organization settings → Claude Code → Managed settings** (server-managed; applies to every member). Users can't disable a plugin enabled here.

```json
{
  "extraKnownMarketplaces": {
    "ono-plugin-marketplace": {
      "source": { "source": "github", "repo": "OnOAppsDev/ono-plugin-marketplace" },
      "autoUpdate": true
    }
  },
  "enabledPlugins": {
    "platform-guardian@ono-plugin-marketplace": true
  }
}
```

Enabling Guardian alone is enough — its `dependencies` install and enable the six Ono plugins (bundle pattern).

Notes for the Owner:

- Takes effect at each member's **next session start**. Check on one machine with `/status` (`Enterprise managed settings` in *Setting sources*) and `/plugin`.
- If server-managed settings are used, MDM / `managed-settings.json` plugin keys on the same machine are ignored (unless `managedSourcesBehavior: "merge"`).
- Optional: if Figma ever needs one org-wide definition, add it under `managedMcpServers` (needs Claude Code 2.1.259+) — it then wins over the four plugin copies. Not needed today: the plugins' four `figma` entries share one URL, so Claude Code already connects once (MGA-83).
- Optional lockdown (later, not for the pilot): `strictKnownMarketplaces` allowing only `anthropics/claude-plugins-official` + `OnOAppsDev/*` (+ `{ "source": "skills-dir" }`), and `disableSideloadFlags: true`. Note: `MatrixStudioPlugin` lives under `OnOApps-Admin`, but the allowlist matches the **marketplace** source, not each plugin's — so `OnOAppsDev/*` is enough.

## Open

- Who is the org Owner? (vision open question 2)
- ~~Repo visibility~~ — public since 2026-11-09.

## Minimum Claude Code version: 2.1.140

From the official [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md) (checked 2026-11-08; current is 2.1.280):

| Needed for | Since |
|---|---|
| Dependencies declared in `plugin.json` installed even though the marketplace entry doesn't list them (ours doesn't) | 2.1.110 |
| Background auto-update installs missing dependencies (a new Ono plugin added to Guardian reaches everyone) | 2.1.116 |
| Managed `extraKnownMarketplaces` auto-update setting actually persisted | 2.1.140 |

Guardian's hooks (`SessionStart` startup/clear, `UserPromptSubmit`, `PreToolUse` ask/deny) need nothing newer. Anyone on an older version: `claude update`.
