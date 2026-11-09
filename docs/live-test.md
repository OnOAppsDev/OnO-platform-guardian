# Live test (G1.7) — run on the test machine

Goal: prove Guardian works inside a real Claude Code session, not just in unit tests. About 35 minutes. **Never on the development machine.**

New to this? Start with the one-page [`tester-guide.md`](tester-guide.md).

Fill the **Result** column as you go (✅ / ❌ + one line of what you saw), then paste this whole file back into a session in this repo — every ❌ becomes a fix.

---

## 0. Setup (once)

**Install Guardian exactly the way every employee will** — in Claude Code:

```
/plugin marketplace add OnOAppsDev/ono-plugin-marketplace
/plugin install platform-guardian@ono-plugin-marketplace
```

| # | Check | Expected | Result |
|---|---|---|---|
| 0.1 | `claude --version` | 2.1.140 or newer | |
| 0.2 | The install above | Succeeds with no GitHub sign-in or error | |
| 0.2b | `/plugin` → **Marketplaces** → **ono-plugin-marketplace** → **Enable auto-update** | The option exists and turns on | |
| 0.3 | `/plugin` → installed plugins | `platform-guardian` **plus all six** Ono plugins (ono-project-inspector, ono-mobile-dev-plugin, ono-plugin-qa, spec-team-toolkit, matrix-qa-plugin, matrix-studio) — the six came with Guardian | |

Quit Claude Code, then download the test kit (the setup script and this checklist — not loaded as a plugin):

```bash
git clone https://github.com/OnOAppsDev/ono-platform-guardian.git ~/pg-test/guardian
```

Test repos + the automatic checks, in one command (any Ono app repo you can clone; add its central branch if it isn't `develop`):

```bash
~/pg-test/guardian/scripts/live-test-setup.sh <an Ono app repo URL>
```

It creates `~/pg-test/app` (on `develop`, plus the branches `pg/behind` and `pg/clean` that §1 uses) and `~/pg-test/scratch` (no remote), then prints the table below — filled in, including the §6.1 hook time. Paste it over this one. Safe to re-run.

| Item | Value |
|---|---|
| Claude Code version | |
| OS | |
| Ono plugins installed (`/plugin`) | |
| 6.1 hook time (app, real remote) | |

---

## 0b. First session — welcome + onboarding tour (new)

Do this **first**, before §1 — the offer appears only once per computer. After the setup script: `cd ~/pg-test/app && git switch pg/clean`, start `claude`, type `let's start`.

| # | Step | Expected | Result |
|---|---|---|---|
| 0b.1 | First message after installing: `let's start` | Enthusiastic welcome with emojis 🎉 · one line on what Guardian does · clear offer of the tour that says exactly what to type (👉 **yes** / **later**) | |
| 0b.2 | Say **yes** | Tour, one short step per message, **each step ends with a clear "👉 Type next …" line** and waits for you, **no second welcome**: how a session starts (shows *your* branch) → "just tell me what you're doing" (try it — it shows what it *would* start, starts nothing) → what it never does for you (approvals, commit guard) → closing → cheat sheet + "what are we working on?" | |
| 0b.3 | Mid-tour, ask a question, then say **skip** | Answers briefly · skip jumps to the cheat sheet | |
| 0b.4 | Did anything change? `git status` in `app` | Nothing changed — the tour never touches git or files | |
| 0b.5 | `/clear`, then `let's start` | **No** welcome offer again — normal opener | |
| 0b.6 | Type `onboarding` | The tour starts again (on request) | |
| 0b.6b | End of the tour (cheat sheet) | Includes the one-time auto-update setup line | |
| 0b.7 | How did the tour *feel*? | Write a line: clear? exciting? too long? anything confusing | |

## 1. Opener — fires on startup

In each case: `cd` into the repo, start `claude`, type **`let's start`**. There is no trigger word — any first message must work, so in at least two cases write something else instead (a question, "good morning", a task).

| # | Situation | How to set it up (in `app`) | Expected | Result |
|---|---|---|---|---|
| 1.1 | On the central branch | `git switch develop` | Greeting · "you're on `develop`" · offers to create a work branch, waits for your answer · then asks what we're working on | |
| 1.2 | Behind central | `git switch pg/behind` (made by the setup script) | ⚠️🚨 "N commits behind `develop`" (N ≥ 3 — more if develop has merges) · explains merge / rebase / continue · **does nothing until you choose** | |
| 1.3 | Clean, up to date | `git switch pg/clean` | One line "✅ up to date" · asks what we're working on | |
| 1.4 | Dirty | on `pg/clean`: `echo x >> README.md` | Mentions 1 modified file · asks if it's yours · doesn't stash / discard | |
| 1.5 | Central unclear | in `scratch` (no remote, branch `main`/`master`) | Mentions no remote; if unsure of central branch, **asks** which branch to branch from | |
| 1.6 | Not a git folder | `cd ~/pg-test` (parent folder) | Says it's not a git project · skips checks · asks what we're doing | |
| 1.7 | First message is a task, not a greeting | on `pg/clean`, first message: `fix the login crash` | Opener runs first (git state), then comes back to the bug — routes to `/analyze-bug` | |
| 1.8 | First message is a slash command | first message: `/help`, then `let's start` | `/help` output (built-in — Claude doesn't see it); the opener runs on `let's start` | |

## 2. Opener — fires after `/clear`

| # | Step | Expected | Result |
|---|---|---|---|
| 2.1 | In any session above, type `/clear`, then `let's start` | Opener runs again (git state shown again) | |
| 2.2 | Same after `/compact` | Opener does **not** re-run (only startup + clear) | |

## 3. Router

On `pg/clean` in `app`. After the opener asks what we're doing:

| # | You say | Expected | Result |
|---|---|---|---|
| 3.1 | "new feature: dark mode" | Confirms "a new feature" + `/analyze-feature` · asks OK before starting | |
| 3.2 | "write a test plan for login" | Picks `qa-mobile` or asks mobile vs web (doesn't guess wrong) | |
| 3.3 | "write a SPAC" | Starts the spec toolkit's SPAC skill, saves to `docs/specs/<slug>/` | |
| 3.4 | "approve the QA plan" | **Refuses to run it** · tells you the exact command to type yourself | |
| 3.5 | Disable one Ono plugin (`/plugin`), ask for its intent | Gives the exact `/plugin install …@ono-plugin-marketplace` line | |

## 4. Commit guard (new — G3.5)

On `pg/clean` in `app`. Ask Claude to run each command **exactly** (e.g. "run `git add notes.md`").

| # | Setup | Ask Claude to run | Expected | Result |
|---|---|---|---|---|
| 4.1 | `echo x > notes.md` | `git add notes.md` | A permission prompt naming `notes.md` as a working file | |
| 4.2 | `echo K=1 > .env.test` | `git add .env.test` | **Blocked** — "must never be committed" | |
| 4.3 | create `src/Foo.kt` (any source file) | `git add src/Foo.kt` | No prompt from Guardian | |
| 4.4 | — | `git status` | No prompt from Guardian | |

Clean up: `git reset -q && rm -f notes.md .env.test src/Foo.kt`.

## 5. Closer + session log

| # | Step | Expected | Result |
|---|---|---|---|
| 5.1 | On `pg/clean` with one small change, say "close the session" | Lists will commit / will ignore · waits for OK · commits on the work branch · asks before push / PR (say **no push** for the test) | |
| 5.2 | — | Ends with "✅ Everything is saved" + the 3 numbered `/clear` steps | |
| 5.3 | `cat ~/.claude/platform-guardian/*/pg_clean.md` | Entry with what we did / where we stopped / next step | |
| 5.4 | `/clear`, then `let's start` | Opener starts with "Last time you stopped at …" | |
| 5.5 | Session-length signal: start with `PG_CLOSEOUT_TOKENS=20000 claude`, work a few turns | After ~20k tokens: answer first, then the 💡 close-out suggestion with 3 steps — once, not every turn | |

## 5b. Resume — "where was I" (new — G2.3)

On `pg/clean`, create a planning doc the way the dev plugin writes it (or use a repo where `/analyze-feature` already ran):

```bash
mkdir -p docs && printf '# FA\n\n```yaml\nfeature: dark-mode\ndd_link:\nsurface: app\nstatus: proposed\n```\n' > docs/dark-mode-feature-analysis.md
~/pg-test/guardian/scripts/resume-state.sh      # prints one "- ono-mobile-dev-plugin · feature dark-mode · …" line
```

| # | Step | Expected | Result |
|---|---|---|---|
| 5b.1 | Start `claude`, say `let's start` | Opener mentions *dark-mode*: analysis waiting for **your** approval → then `/dev-design-start dark-mode` · offers "continue dark-mode, or something new?" | |
| 5b.2 | Say "approve it for me" | **Refuses** to flip `status` — tells you to change it yourself | |
| 5b.3 | Set `status: approved` in the file, `/clear`, `let's start` | Now: "analysis approved, next `/dev-design-start dark-mode`" | |
| 5b.4 | In a real repo where an Ono plugin already ran (features / bugs / QA repo / inspector) | Lines match what you know is unfinished — note anything wrong or missing | |

Clean up: `rm -rf docs`.

## 6. Performance + Figma (MGA-83)

| # | Check | Expected | Result |
|---|---|---|---|
| 6.1 | Hook time — already measured by the setup script (§0 table) | < 3 s with the real remote (fetch is capped at 5 s) | see §0 |
| 6.2 | Re-run the setup script with Wi-Fi off (hook-time row) | Still returns (≤ ~6 s); opener says the numbers may be outdated | |
| 6.3 | Startup of a session with all six Ono plugins | `/mcp` shows **one** active Figma server (the other three listed as duplicates / hidden) and at most **one** Figma sign-in — the four plugins use the same URL, which Claude Code connects once. Count what you see | |
| 6.4 | Startup feels slow? | Note seconds from `claude` to the first prompt | |

---

## Notes / anything surprising

-
