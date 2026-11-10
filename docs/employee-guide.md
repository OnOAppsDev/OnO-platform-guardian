# OnO Platform Guardian — getting started

One plugin to install. One place to start. The right Ono process every time.

---

## Before you start (1 min)

- In the terminal: `claude --version` → you need **2.1.140 or newer**. Older? Run `claude update`.
- You need access to the **OnOAppsDev** org on GitHub.

## Install (once, 3 min)

1. Open Claude Code anywhere (`claude`).
2. Type these two lines, one at a time:
   ```
   /plugin marketplace add OnOAppsDev/ono-plugin-marketplace
   /plugin install platform-guardian@ono-plugin-marketplace
   ```
3. Turn on automatic updates: `/plugin` → **Marketplaces** → **ono-plugin-marketplace** → **Enable auto-update**.
4. Check: `/plugin` shows **platform-guardian + 6 Ono plugins** that came with it.
5. Quit Claude Code (`/exit`).

## Every day

1. **Go into your project folder** and start Claude:
   ```bash
   cd ~/path/to/your-app
   claude
   ```
2. **Write anything** — "hi", "let's start", whatever. Guardian:
   - checks your git state — which branch you're on, whether you're behind your project's **main branch** (each project has its own — often `develop`; if Guardian isn't sure, it asks you). Something off → you'll see ⚠️🚨 and **you** decide what to do;
   - reminds you where you stopped last time;
   - asks: **bug, feature, QA, spec…?**
3. **Say what you're doing in plain words** — "fix bug ABC-123", "new login screen", "write a QA plan". Guardian starts the right Ono plugin for you. No commands to remember.
4. **Approvals are yours.** When a step needs a human (approving a plan, QA sign-off), Guardian stops and tells you exactly what to type.
5. **Done** (or Guardian shows 💡 because the session got long) → say **"close the session"**. Guardian commits, pushes and opens a PR — never straight to the main branch, and it asks before each step. Then type **`/clear`** to start fresh. Nothing is lost.

## Good to know

- Tired of the "which branch is the main one?" question in a project? Add `.platform-guardian.json` to that project with `{"centralBranch": "<its main branch>"}` and commit it — the whole team stops getting asked.
- 🎉 Your **first** session after installing opens with a welcome and a 3-minute tour — say yes.
- 🎓 Type **onboarding** any time to see the tour again.
- Guardian never pushes to the main branch, never updates your branch without asking, never commits secrets.
- In QA repos the QA plugins block Claude from committing — Guardian gives you the commands to run yourself.
- Something looks wrong? Tell Tom — a screenshot of the Claude message is the most useful thing.
