# Platform Guardian — tester guide

Thanks for testing! About **45 minutes**, on **your** computer (not Tom's). Nothing gets permanently installed — Guardian is loaded for one session at a time and is gone when you close Claude.

At the end you send back **one file**. That's it.

---

## What you need

- A Mac with **Claude Code 2.1.140 or newer** — check with `claude --version`, update with `claude update`.
- Access to the **OnOAppsDev** GitHub org (you can clone its repos).
- The URL of **any Ono app repo** you can clone (it should have a `develop` branch — if not, note which branch is the main one).

## Step 1 — the six Ono plugins (5 min)

Open Claude Code anywhere and type `/plugin`. If you don't see these six, install them:

```
/plugin marketplace add OnOAppsDev/ono-plugin-marketplace
/plugin install ono-project-inspector@ono-plugin-marketplace
/plugin install ono-mobile-dev-plugin@ono-plugin-marketplace
/plugin install ono-plugin-qa@ono-plugin-marketplace
/plugin install spec-team-toolkit@ono-plugin-marketplace
/plugin install matrix-qa-plugin@ono-plugin-marketplace
/plugin install matrix-studio@ono-plugin-marketplace
```

Then quit Claude Code.

## Step 2 — download Guardian and prepare test folders (5 min)

In the terminal:

```bash
git clone https://github.com/OnOAppsDev/yes-platform-guardian.git ~/pg-test/guardian
~/pg-test/guardian/scripts/live-test-setup.sh <Ono app repo URL>
```

(If the app's main branch isn't `develop`, add its name at the end: `... <URL> main`.)

The second command creates test folders under `~/pg-test` and prints a small table. **Copy that table** — it goes into the file you send back.

## Step 3 — run the checklist (about 35 min)

Open `~/pg-test/guardian/docs/live-test.md` in any editor. Paste the table from step 2 over the empty one in §0.

Each row is one small scenario. The pattern is always the same:

1. Do what the "How to set it up" column says (e.g. `cd ~/pg-test/app` and `git switch develop`).
2. Start Claude **with Guardian**: `claude --plugin-dir ~/pg-test/guardian`
3. Type what the row says (usually just `hi`).
4. Compare Claude's answer with the **Expected** column.
5. Write in the **Result** column: **✅** if it matches, or **❌ + one line of what actually happened**.
6. Quit Claude (`/exit`) and go to the next row.

Tips:
- Not sure if it's ✅ or ❌? Write ❌ and describe what you saw — that's more useful than guessing.
- Anything surprising (slow, confusing text, an unexpected question) → write it in **Notes** at the bottom.
- Section 4 asks you to tell Claude to run git commands — that's safe, it's a throwaway test folder.
- Skip a row you can't do and write "skipped — why".

## Step 4 — send it back

Send Tom the file `~/pg-test/guardian/docs/live-test.md` (the whole file, filled in).

## Clean up (optional)

```bash
rm -rf ~/pg-test ~/.claude/platform-guardian
```

Nothing else was changed on your computer.
