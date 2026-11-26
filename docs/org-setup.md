# Turn on OnO Platform Guardian for the whole org

**For:** Magen / Yagil (Owners of the Claude organization) · **Time:** ~5 minutes · one time

**Result:** every employee gets Guardian and the developer setup (the Ono dev plugin and the Ono Project Inspector) automatically, always up to date — nobody installs or updates anything by hand.

---

## Step 1 — Open the managed settings

claude.ai → **Organization settings** → **Claude Code** → **Managed settings**.

**What it gives:** one place that applies to every member of the org. Settings here win over each employee's own settings.

## Step 2 — Paste this and save

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

**What each part gives:**

| Part | What it gives |
|---|---|
| `extraKnownMarketplaces` → `ono-plugin-marketplace` | Every employee has the Ono marketplace — no need to add it themselves. |
| `"autoUpdate": true` | Guardian and the plugins it brings **update by themselves** (it's off by default for org marketplaces). A fix we publish reaches everyone within their next sessions. |
| `enabledPlugins` → `platform-guardian` | Guardian is installed and on for everyone — and it brings the developer setup with it: the Ono dev plugin and the Ono Project Inspector. Employees can't turn it off by mistake. |

**The QA plugin is the QA team's (Guardian 0.8.0).** `ono-plugin-qa` is no longer one of Guardian's dependencies, so developers don't get it. The QA team installs it themselves (`/plugin install ono-plugin-qa@ono-plugin-marketplace`). The two sides share work through documents (bug ledgers, QA handoffs, QA results, release readiness), not through each other's plugins. Installs from before 0.8.0 keep the QA plugin; Guardian tells each computer once that developers can remove it.

If the box already has settings, merge these keys into what's there (don't replace it).

## Step 3 — Check it worked (one computer)

On any employee's computer: close Claude Code, open it again, then:
- type `/status` → under *Setting sources* you see **Enterprise managed settings**;
- type `/plugin` → **platform-guardian**, the Ono dev plugin and the Ono Project Inspector are installed and enabled (the QA plugin only where the QA team installed it).

**What it gives:** confirmation it reached everyone — it takes effect for each employee at their **next session start**.

---

Questions → Tom. Background and options (e.g. a later lockdown to Ono-only marketplaces): [`rollout.md`](rollout.md).
