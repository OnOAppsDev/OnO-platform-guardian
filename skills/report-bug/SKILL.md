---
name: report-bug
description: Platform Guardian bug report — drafts a short summary, lets the employee confirm or correct it (one bug or several), then writes one organized report file per bug about something that went wrong in Guardian, an Ono plugin or Claude Code during this session, for the employee to send to Tom (Guardian's maintainer), who decides where the bug is and who fixes it. Run when the employee says "report a bug", "this is a bug", "something's broken", "tell Tom", "send this to Tom" (in any language), or accept your offer after you concluded that a tool misbehaved — a plugin command failed or returned an error, a command name didn't run, a Guardian hook blocked something wrongly, routing picked the wrong process, a script crashed. Not for bugs in the employee's own app — that's their work (the bug flow, /analyze-bug).
---

# Bug report

You turn "something went wrong" into a report Tom can analyze without going back to the employee — and that says what *they* mean: they confirm a short draft before anything is written. Plain language with the employee; the report itself in English (the people fixing it read English). Nothing in the repo changes.

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

If something essential is missing (usually "what did you expect to happen?"), ask it inside the draft in step 3 — not as a separate round.

### 2. Pick the suspected component

One of: **Platform Guardian** (its hooks, skills, routing, scripts) · **‹Ono plugin name›** (from the command / skill prefix, or the plugin's files in the error) · **Claude Code** · **the employee's setup** (missing tool, permissions, network) · **unclear**. Give the evidence in one or two lines. You suggest; Tom decides — don't name a person to fix it.

### 3. Show the draft — write nothing until they agree

The facts come from the session; **what the report is about is the employee's call.** Even when they only typed "report a bug", and even when you offered it, show a short draft first — never write the file, run the script or open Finder before they agree:

> 🐞 Here's what I'd report — correct anything, or add what's missing:
> **‹title›** — suspected: ‹component›
> • What happened: ‹one line›
> • Expected: ‹one line›
> ‹the missing question, if any›
> Is this one bug, or several? Anything to add? (**OK** to write it)

If they describe something else, or more, redraft and show it again. **Several bugs → one report each:** a draft per bug in the same message, then one file per bug (step 5 for each), each listing the others under "Related reports from this session". Keep it short — this is about intent and scope, not an interview.

### 4. Environment — facts from the script, not from memory

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/bug-report.sh" env
```

It prints the Environment section (Claude Code, Guardian and every Ono plugin's version, macOS, repo, branch, git state). Paste it as-is.

### 5. Write the file — outside the project (after their OK)

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

<Several reports from one session: "Related reports from this session: ‹titles›">

<Environment section from step 4>

---
Local file — not in the repo. Send it to Tom.
~~~

**Privacy — check before writing:** no secrets (tokens, keys, passwords, `.env` values — mask as `***`), no customer or user data, no email addresses, and no app source code beyond a few lines needed to show a plugin / Guardian bug. Plugin or Guardian code snippets: at most ~15 lines.

### 6. Hand it over

Open Finder with the file selected so it's easy to send: `open -R "<path>"` (macOS; elsewhere just give the path). Several reports → open their folder once (`open "<folder>"`) and list every title. Then tell the employee, in their language:

> 🐞 **Bug report ready:** ‹title› — suspected: ‹component›.
> 👉 Send the file to Tom (Finder just opened with it selected — drag it into Slack / WhatsApp).
> It's saved outside the project and won't go into any commit.

Then go back to what they were doing. Don't try to fix a plugin's or Guardian's files yourself — they belong to their owners and are overwritten on update.
