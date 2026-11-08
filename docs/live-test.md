# Live test (G1.7) — run on the test machine

Goal: prove Guardian works inside a real Claude Code session, not just in unit tests. About 45 minutes. **Never on the development machine.**

Fill the **Result** column as you go (✅ / ❌ + one line of what you saw), then paste this whole file back into a session in this repo — every ❌ becomes a fix.

---

## 0. Setup (once)

```bash
claude --version                                   # note it below
git clone -b platform-guardian-v0.1 https://github.com/OnOAppsDev/yes-platform-guardian.git ~/pg-test/guardian
```

Guardian is loaded **for one session at a time** with `--plugin-dir` (no install, nothing to undo). That flag does not install Guardian's dependencies — the six Ono plugins must already be installed from `ono-plugin-marketplace` on this machine (check with `/plugin`). Installing them *through* Guardian is tested later, in G4.1.

Two test repos:

```bash
mkdir -p ~/pg-test && cd ~/pg-test
# A: a real work repo with a develop branch (any Ono app repo you can clone)
git clone <an Ono app repo> app && cd app && git switch develop && cd ..
# B: a throwaway repo with no remote
mkdir scratch && cd scratch && git init -q && echo hi > a.txt && git add a.txt && git commit -qm init && cd ..
```

| Item | Value |
|---|---|
| Claude Code version | |
| OS | |
| Ono plugins installed (`/plugin`) | |

---

## 1. Opener — fires on startup

In each case: `cd` into the repo, start `claude --plugin-dir ~/pg-test/guardian`, type **`hi`**.

| # | Situation | How to set it up (in `app`) | Expected | Result |
|---|---|---|---|---|
| 1.1 | On the central branch | `git switch develop` | Greeting · "you're on `develop`" · offers to create a work branch, waits for your answer · then asks what we're working on | |
| 1.2 | Behind central | `git switch -c pg/behind origin/develop~3` | ⚠️🚨 "N commits behind `develop`" (N ≥ 3 — more if develop has merges) · explains merge / rebase / continue · **does nothing until you choose** | |
| 1.3 | Clean, up to date | `git switch -c pg/clean origin/develop` | One line "✅ up to date" · asks what we're working on | |
| 1.4 | Dirty | on `pg/clean`: `echo x >> README.md` | Mentions 1 modified file · asks if it's yours · doesn't stash / discard | |
| 1.5 | Central unclear | in `scratch` (no remote, branch `main`/`master`) | Mentions no remote; if unsure of central branch, **asks** which branch to branch from | |
| 1.6 | Not a git folder | `cd ~/pg-test` (parent folder) | Says it's not a git project · skips checks · asks what we're doing | |
| 1.7 | First message is a task, not a greeting | on `pg/clean`, first message: `fix the login crash` | Opener runs first (git state), then comes back to the bug — routes to `/analyze-bug` | |
| 1.8 | First message is a slash command | first message: `/help` | `/help` output first, then the opener | |

## 2. Opener — fires after `/clear`

| # | Step | Expected | Result |
|---|---|---|---|
| 2.1 | In any session above, type `/clear`, then `hi` | Opener runs again (git state shown again) | |
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
| 5.4 | `/clear`, then `hi` | Opener starts with "Last time you stopped at …" | |
| 5.5 | Session-length signal: start with `PG_CLOSEOUT_TOKENS=20000 claude --plugin-dir ~/pg-test/guardian`, work a few turns | After ~20k tokens: answer first, then the 💡 close-out suggestion with 3 steps — once, not every turn | |

## 6. Performance + Figma (MGA-83)

| # | Check | Expected | Result |
|---|---|---|---|
| 6.1 | `cd ~/pg-test/app && time ~/pg-test/guardian/hooks/session-start.sh </dev/null >/dev/null` | < 3 s with the real remote (fetch is capped at 5 s) | |
| 6.2 | Same with Wi-Fi off | Still returns (≤ ~6 s); opener says the numbers may be outdated | |
| 6.3 | Startup of a session with all six Ono plugins | How many Figma MCP auth prompts / duplicate `figma` servers do you see in `/mcp`? (count them) | |
| 6.4 | Startup feels slow? | Note seconds from `claude` to first prompt, with vs without `--plugin-dir` | |

---

## Notes / anything surprising

-
