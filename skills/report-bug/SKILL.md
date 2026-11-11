---
name: report-bug
description: Platform Guardian bug report — writes one organized report file about something that went wrong in Guardian, an Ono plugin or Claude Code during this session, for the employee to send to Tom (Guardian's maintainer), who decides where the bug is and who fixes it. Run when the employee says "report a bug", "this is a bug", "something's broken", "tell Tom", "send this to Tom" (in any language), or accept your offer after you concluded that a tool misbehaved — a plugin command failed or returned an error, a command name didn't run, a Guardian hook blocked something wrongly, routing picked the wrong process, a script crashed. Not for bugs in the employee's own app — that's their work (the bug flow, /analyze-bug).
---

# Bug report

You turn "something went wrong" into one file Tom can analyze without asking the employee anything. Plain language with the employee; the report itself in English (the people fixing it read English). Nothing in the repo changes.

## When to offer it yourself

When you conclude during the session that the **tooling** misbehaved — not the employee's code — offer once, in one line, after you've explained what happened and any workaround:

> 🐞 This looks like a bug in ‹component›, not in your work. Want me to write a short bug report for Tom? (1 minute — type **report**)

Don't offer for: the employee's app bugs, expected blocks (a human-only step, a QA repo blocking commits, the commit guard leaving files out as designed), or a missing setup step you can fix together (Chrome not installed, `gh` not logged in) — unless it keeps failing after the fix.

## Steps

### 1. Collect from the session — don't interview

Everything you can, from this conversation:

- **What they were doing** — the task, and the exact command / skill that was running (`/ono-mobile-dev-plugin:verify-fix-cycle bug:YEA-1311`).
- **What happened** — the error or wrong behavior, **verbatim** (copy the exact message / tool output, trimmed to the relevant lines).
- **What should have happened.**
- **Steps to reproduce** — numbered, the minimum.
- **What you found** if you investigated — the cause as far as you know, with `file:line` in the plugin / Guardian. Mark guesses as guesses.
- **Impact + workaround** — blocked, slowed, or cosmetic; what you did instead.

Ask the employee **one** short question only if something essential is missing (usually "what did you expect to happen?").

### 2. Pick the suspected component

One of: **Platform Guardian** (its hooks, skills, routing, scripts) · **‹Ono plugin name›** (from the command / skill prefix, or the plugin's files in the error) · **Claude Code** · **the employee's setup** (missing tool, permissions, network) · **unclear**. Give the evidence in one or two lines. You suggest; Tom decides — don't name a person to fix it.

### 3. Environment — facts from the script, not from memory

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/bug-report.sh" env
```

It prints the Environment section (Claude Code, Guardian and every Ono plugin's version, macOS, repo, branch, git state). Paste it as-is.

### 4. Write the file — outside the project

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/bug-report.sh" new "<3-6 word title>"
```

prints the path (`~/.claude/platform-guardian/bug-reports/<date>-<title>.md`). Write the report there with your file tool — never inside the repo, never `git add` it. Use this shape:

~~~markdown
# Bug report — <short title>

**Suspected component:** <component> · **Impact:** <blocked / slowed / cosmetic>

## Summary
<1–2 plain sentences: what broke>

## What the employee was doing
<task + the exact command / skill>

## What happened
```
<verbatim error / output, trimmed>
```

## Expected
<one or two lines>

## Steps to reproduce
1. …

## Findings
<cause as far as known, file:line, evidence — guesses marked as guesses; "not investigated" if none>

## Workaround
<what we did instead, or "none">

<Environment section from step 3>

---
Local file — not in the repo. Send it to Tom.
~~~

**Privacy — check before writing:** no secrets (tokens, keys, passwords, `.env` values — mask as `***`), no customer or user data, no email addresses, and no app source code beyond a few lines needed to show a plugin / Guardian bug. Plugin or Guardian code snippets: at most ~15 lines.

### 5. Hand it over

Open Finder with the file selected so it's easy to send: `open -R "<path>"` (macOS; elsewhere just give the path). Then tell the employee, in their language:

> 🐞 **Bug report ready:** ‹title› — suspected: ‹component›.
> 👉 Send the file to Tom (Finder just opened with it selected — drag it into Slack / WhatsApp).
> It's saved outside the project and won't go into any commit.

Then go back to what they were doing. Don't try to fix a plugin's or Guardian's files yourself — they belong to their owners and are overwritten on update.
