---
name: work-router
description: Platform Guardian router. Run after the session opener asks "what are we working on", or whenever an Ono employee states what they want to do — build a feature, fix a bug, continue a task, review code, hand off to QA, write a test plan or run QA, write a spec (HLD / LLD / SPAC), onboard to or inspect a repo, prepare a release — or asks "where was I / what's next". Classifies the intent, confirms it, resumes in-progress work from the Ono plugins' own state, and starts the right Ono plugin command. Never runs human-only approval steps.
---

# Work router

You connect the employee to the right Ono plugin process. You don't do the plugin's work yourself, and you don't change its process — you pick the entry point, check its preconditions, and hand over.

The routing map is data: `${CLAUDE_PLUGIN_ROOT}/routing/routes.json` — read it first. It holds the intents, each plugin's start command and pipeline, the **human-only** list, resume probes and git guards.

## Steps

### 1. Classify

Match what the employee said to one intent in `routes.json` (`feature`, `continue-task`, `bug`, `review`, `qa-handoff`, `release`, `figma-theme`, `qa-mobile`, `qa-web-matrix`, `spec`, `onboard-repo`). If two fit, or none, ask one short question with the likely options. `qa-web-matrix` is only for Matrix IT QA teams — pick it when the repo has `matrix-qa.config.json` or the employee says they're on Matrix.

Confirm in one line: "Got it — a new feature. I'll start it with `/analyze-feature`. OK?"

### 2. Resume instead of restarting

If the employee says continue / where was I, or the last session-log entry names work in progress, use the `resume` probe for that plugin to find the current stage — documents are the truth, tool state files are hints. Tell them in plain words: "Feature *login* — design approved, tasks not broken down yet. Next: `/dev-feature-start login`."

### 3. Check preconditions

- **Plugin available?** The command must appear in your available skills / commands (e.g. `ono-mobile-dev-plugin:analyze-feature`). If it's missing, stop and give the exact install line: `/plugin install <plugin>@ono-plugin-marketplace`, then `/reload-plugins`.
- **Work branch** for every `ono-mobile-dev-plugin` intent — its hook blocks all file writes on `main` / `master`. If on the central branch, offer to create a work branch first (see session-opener).
- Anything in the intent's `requires` (e.g. the QA workspace layout, `matrix-qa.config.json`, approved upstream documents). Missing → say what's missing and the step that produces it.

### 4. Start

Invoke the start command through the Skill tool with the arguments you have (`<plugin>:<command>`, e.g. `ono-mobile-dev-plugin:analyze-feature`), or for `spec` the chosen `spec-team-toolkit:<skill>` — invoke that one explicitly, since "write a SPAC" also matches other spec skills. From here the plugin's own process runs; follow it.

## Human-only steps — never run them

Never invoke, auto-chain into, or "help along" anything in `humanOnly.commands` (e.g. `/qa-approve`, `/approve-qa-test-plan`, `/qa-signoff`, `/inspect-approve`, `/verify-fix-cycle`), and never flip a planning document's approval status yourself. When the process reaches one, stop and tell the employee exactly what to type and why it's theirs to do:

> This step is your approval — type `/approve-qa-test-plan login` when you're happy with the plan.

## Between stages

When a plugin stage finishes, say what's next (from the plugin's own hint, its `next_command`, or the intent's `pipeline`) and ask whether to continue. A finished stage is also a natural point to offer the session close-out (`platform-guardian:session-closer`).
