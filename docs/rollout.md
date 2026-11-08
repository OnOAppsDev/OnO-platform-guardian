# Rollout (G4) — marketplace + org-wide install

Verified against the official docs on 2026-11-08: [Manage plugins for your organization](https://code.claude.com/docs/en/plugins/org.md), [Plugin dependencies](https://code.claude.com/docs/en/plugins/dependencies.md).

## Order

1. **PR #3 merged** into `master` of this repo — the marketplace entry tracks `master`.
2. **G4.1 — marketplace entry.** Ready on a local branch `add-platform-guardian` in the `ono-plugin-marketplace` clone (not pushed): manifest entry (`ref: master`), version 1.5.0 → 1.6.0, README + CHANGELOG in the marketplace's own style; `claude plugin validate .` passes. All six dependencies are already listed in that marketplace, so they resolve.
3. **Pilot install by hand** (one team) — `/plugin install platform-guardian@ono-plugin-marketplace`, confirm the six plugins come with it.
4. **G4.2 — managed settings** (org Owner), below.

## Decision needed before G4.1: repo visibility

The marketplace and all six Ono plugin repos are **public**; `yes-platform-guardian` is **private**. Plugins install by cloning on the employee's machine with their stored git credentials and no prompt — so with a private repo, every employee needs GitHub read access to it **and** working git credentials (e.g. `gh auth setup-git`), or the install fails. Background auto-update has the same requirement.

| Option | Effect |
|---|---|
| Make `yes-platform-guardian` public (like the other six) | Installs work everywhere, no setup. Guardian holds no secrets — only scripts, skills and routing data. |
| Keep it private | Every employee needs org repo access + git credentials before Guardian can install; failures will look like "plugin not found". |

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
- Optional lockdown (later, not for the pilot): `strictKnownMarketplaces` allowing only `anthropics/claude-plugins-official` + `OnOAppsDev/*` (+ `{ "source": "skills-dir" }`), and `disableSideloadFlags: true`. Note: `MatrixStudioPlugin` lives under `OnOApps-Admin`, but the allowlist matches the **marketplace** source, not each plugin's — so `OnOAppsDev/*` is enough.

## Open

- Who is the org Owner? (vision open question 2)
- Minimum Claude Code version for employees (vision open question 3) — Guardian's hooks need nothing new; only a future mods-based context meter would.
