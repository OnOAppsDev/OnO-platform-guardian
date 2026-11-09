# Turn on OnO Platform Guardian for the whole org

**For:** Magen / Yagil (Owners of the Claude organization) · **Time:** ~5 minutes · one time

**Result:** every employee gets Guardian and the six Ono plugins automatically, always up to date — nobody installs or updates anything by hand.

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
| `"autoUpdate": true` | Guardian and the six plugins **update by themselves** (it's off by default for org marketplaces). A fix we publish reaches everyone within their next sessions. |
| `enabledPlugins` → `platform-guardian` | Guardian is installed and on for everyone — and it brings the six Ono plugins with it (dev, two QA, specs, inspector, Matrix Studio). Employees can't turn it off by mistake. |

If the box already has settings, merge these keys into what's there (don't replace it).

## Step 3 — Check it worked (one computer)

On any employee's computer: close Claude Code, open it again, then:
- type `/status` → under *Setting sources* you see **Enterprise managed settings**;
- type `/plugin` → **platform-guardian** and the six Ono plugins are installed and enabled.

**What it gives:** confirmation it reached everyone — it takes effect for each employee at their **next session start**.

---

Questions → Tom. Background and options (e.g. a later lockdown to Ono-only marketplaces): [`rollout.md`](rollout.md).
