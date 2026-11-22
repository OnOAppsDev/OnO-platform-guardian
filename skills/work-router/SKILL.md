---
name: work-router
description: Platform Guardian router. Run after the session opener asks "what are we working on", or whenever an Ono employee states what they want to do — build a feature, fix a bug, continue a task, review code, hand off to QA, write a test plan or run QA, onboard to or inspect a repo, prepare a release — or asks "where was I / what's next", or wants a pre-PR regression check ("ready for PR", "what could I have broken"). Classifies the intent, confirms it, resumes in-progress work from the Ono plugins' own state, and starts the right Ono plugin command. Never runs human-only approval steps.
---

# Work router

You connect the employee to the right Ono plugin process. You don't do the plugin's work yourself, and you don't change its process — you pick the entry point, check its preconditions, and hand over.

The routing map is data: `${CLAUDE_PLUGIN_ROOT}/routing/routes.json` — read it first. It holds the intents, each plugin's start command and pipeline, the **human-only** list, resume probes and git guards.

## Steps

### 1. Classify

Match what the employee said to one intent in `routes.json` (`feature`, `continue-task`, `bug`, `review`, `qa-handoff`, `release`, `figma-theme`, `qa-mobile`, `onboard-repo`). If two fit, or none, ask one short question with the likely options. **Guardian's own intent — not in `routes.json`:** "ready for PR", "pre-PR", "what could I have broken", "regression checklist" → run the `platform-guardian:pre-pr` skill directly (no confirmation needed; it changes nothing). The session closer also runs it automatically before the PR, when the bug or feature is finished. "Report a bug", "this is a bug in the tool", "tell Tom" → run `platform-guardian:report-bug` (bugs in Guardian / the Ono plugins / Claude Code — not in the employee's app, that's the `bug` intent). **Reviewing a teammate's PR** (picked from the opener's 🔎 list, or "review PR #12") → the `review` intent with the PR as its scope: `/ono-mobile-dev-plugin:review-code ‹PR url›` — for a PR of this repo only; for another repo's PR, give its link and say to open Claude Code in that project. The review stays in the session: approving, requesting changes or posting comments on GitHub is the employee's call — post nothing for them unless they ask. If the request is itself a human-only step ("approve the plan", "sign off", "resolve this bug") → don't classify or ask; answer as in **Human-only steps** below, with the command for this repo's plugin.

Check the plugin is available (step 3) before confirming, so the employee doesn't say OK to something that can't start. Confirm in one line: "Got it — a new feature. I'll start it with `/analyze-feature`. OK?" If the start command needs something you don't have (a bug key, a feature name), ask for it in the same line; never invent one.

### 2. Resume instead of restarting

If the employee says continue / where was I, or the last session-log entry names work in progress, find the current stage:

1. **Scripted first.** Use the "Unfinished work found" lines from the session start, or run `"${CLAUDE_PLUGIN_ROOT}/scripts/resume-state.sh"` — one line per unfinished item across the dev plugin (features, bugs), the QA plugin and the inspector, with the next step. Finished work isn't listed.
2. **Probe when the script is silent or unsure** about that piece of work (e.g. a QA repo it couldn't locate, smoke / regression detail): use the plugin's `resume` probe in `routes.json` — documents are the truth, tool state files are hints.

The stage is "apparent": the plugin's own command re-checks approvals and fingerprints when it runs, so start it and let it decide. Tell them in plain words: "Feature *login* — design approved, tasks not broken down yet. Next: `/dev-feature-start login`." A "your step" item is an approval or sign-off — tell them what to type, never run it (see below).

### 3. Check preconditions

- **Plugin available?** The command must appear in your available skills / commands (e.g. `ono-mobile-dev-plugin:analyze-feature`). If it's missing, stop and give the exact install line: `/plugin install <plugin>@ono-plugin-marketplace`, then `/reload-plugins`. If it's installed but disabled, tell them to open `/plugin`, enable it, then `/reload-plugins`. Don't substitute a similar skill from elsewhere.
- **Work branch** for every intent that writes files: dev, QA, onboarding / inspection. Guardian's own write guard blocks file changes on a protected branch (`main`, `master`, and the project's central branch when it's certain), and its commit guard blocks commits and pushes there. This doesn't depend on any plugin's hook; the dev plugin also guards `main` / `master` on its own, and both stay. If on a protected branch, offer to create a work branch first (see session-opener), before starting the plugin, so it doesn't fail halfway.
- Anything in the intent's `requires` (e.g. the QA workspace layout, approved upstream documents). Missing → say what's missing and the step that produces it.

### 4. Start

Invoke the start command through the Skill tool with the arguments you have (`<plugin>:<command>`, e.g. `ono-mobile-dev-plugin:analyze-feature`). From here the plugin's own process runs; follow it.

## Human-only steps — never run them

Never invoke, auto-chain into, or "help along" anything in `humanOnly.commands` (e.g. `/approve-qa-test-plan`, `/qa-signoff`, `/inspect-approve`, `/verify-fix-cycle`), and never flip a planning document's approval status yourself — **even when the employee asks you to**; tell them the file and the line to change. When the process reaches one, stop and tell the employee exactly what to type and why it's theirs to do:

> This step is your approval — type `/ono-plugin-qa:approve-qa-test-plan login` when you're happy with the plan.

**Always give the full command name: `/‹plugin›:‹command› ‹args›`** (the plugin is in `humanOnly.commands[].plugin`, or the intent's plugin) — e.g. `/ono-mobile-dev-plugin:verify-fix-cycle bug:YEA-1311`, never just `/verify-fix-cycle`. The short form doesn't run everywhere (a tester's "unknown command"), and the employee can't tell why. Same for every command you hand them to type, not only approvals.

## Between stages

**A new task mid-session goes through the router too.** When the employee brings a different bug, feature or task than the one in progress, classify and confirm it like the first one (steps 1–4) before reading code or editing. Once a stage has finished, any further code change is new work too. But when you last asked a question for the running Ono step (approve, continue, results, details), the reply answers it — even when it describes a failure or a new symptom — so continue the step. A `[platform-guardian] Routing:` note on each message is the reminder.

When a plugin stage finishes, say what's next (from the plugin's own hint, its `next_command`, or the intent's `pipeline`) and ask whether to continue. If the next step is human-only, a "yes" doesn't change that — tell them what to type, with the full `/‹plugin›:‹command›` name. A finished stage is also a natural point to offer the session close-out — say how, not just when: "Want to stop here? Say **close the session** and I'll save where we stopped (no PR until the work is finished); then type `/clear` to start fresh." Offer it once per session, and not if a 💡 close-out suggestion was already shown.
