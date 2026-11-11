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
5. **Done** (or Guardian shows 💡 because the session got long) → say **"close the session"**. Guardian shows what goes into the commit (**only code** — notes and plugin documents stay out unless you ask), runs a quick **pre-PR check** (a one-page PDF of what to test; type **skip** to skip), then pushes and opens a PR — never straight to the main branch, and it asks before each step. Then type **`/clear`** to start fresh. Nothing is lost.

## Before every PR — the pre-PR check 🔍

When you close a session with changes, Guardian runs a quick safety check **before** it opens the PR. It looks at the code you changed and everything that uses it, and opens a **one-page PDF** with what to test in the app:

- 🔴 **Must test** — check these before you send the PR.
- 🟠 **Should test** — worth a quick look.
- ⚠️ **Watch out** — spots in the code that look risky.

Test the 🔴 items, then type **push**. Found something broken? Great catch — fix it first, then close again.
The PDF is just for you: it's not saved in the project and never goes into the PR. In a hurry? Type **skip**. You can also ask for it any time: "what could I have broken?"

## Good to know

- Want a document in the PR (e.g. a spec)? Just say so — "put docs/specs/login/hld.md in the PR". A project that always commits some paths lists them in `.platform-guardian.json`: `"commitPaths": ["docs/specs/**"]`.
- Tired of the "which branch is the main one?" question in a project? Add `.platform-guardian.json` to that project with `{"centralBranch": "<its main branch>"}` and commit it — the whole team stops getting asked.
- 🎉 Your **first** session after installing opens with a welcome and a 3-minute tour — say yes.
- 🎓 Type **onboarding** any time to see the tour again.
- Guardian never pushes to the main branch, never updates your branch without asking, never commits secrets.
- In QA repos the QA plugins block Claude from committing — Guardian gives you the commands to run yourself.
- 🐞 **Something broken in the tools** (Guardian, a plugin command, an error that isn't your code)? Say **"report a bug"**. Claude writes an organized report — what happened, the exact error, versions — opens it in Finder, and you send the file to Tom. Claude also offers it by itself when it spots a tool bug.
