#!/usr/bin/env bash
# SessionStart hook (startup | clear): injects the git report, the last local
# session-log entry and any unfinished work found in the Ono plugins' documents
# as context, and instructs Claude to run the session-opener skill. Plain stdout from a SessionStart hook is added to Claude's context.
# Fails open: any problem → minimal or no output, always exit 0.

cat >/dev/null 2>&1   # drain the hook payload; we only need the project dir

here="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
scripts="${CLAUDE_PLUGIN_ROOT:-$here/..}/scripts"
dir="${CLAUDE_PROJECT_DIR:-$PWD}"

report="$("$scripts/git-status.sh" "$dir" 2>/dev/null)"
[ -z "$report" ] && exit 0

# the write guard / commit guard / inspect gate protect the central branch only when it's certain
case "$report" in
  *'"confidence":"high"'*)
    central="$(printf '%s' "$report" | sed -n 's/.*"central":{"branch":"\([^"]*\)".*/\1/p')"
    "$scripts/protected-branch.sh" remember "$dir" "$central" ;;
  *) "$scripts/protected-branch.sh" forget "$dir" ;;
esac

# Guardian needs neither jq nor Node, but the Ono dev plugin does. Its hooks (0.7.6+) read every
# file change with jq and, without it, block every write; its scripts (0.7.7+) need Node 22.18+ on
# the 22 line or Node 24+, and every command stops on anything older. The Matrix QA plugin (0.1.0)
# starts `node` for its guard before almost every tool call, in every repo: with no node, or one
# that crashes, every call shows "PreToolUse:… hook failed" and, inside QA repos, its guard is off
# (a crashing hook doesn't block). Checked only when one of them is installed (unknown list →
# assume both are). This sees the node on Claude Code's own PATH; the dev plugin's commands run
# node through the Bash tool, which can load a different one (nvm set up only in the shell), so
# the opener line also says how to check inside Claude Code.
no_jq=""
old_node=""
plugins="${PG_PLUGINS_FILE:-$HOME/.claude/plugins/installed_plugins.json}"
has_dev="" has_mqa=""
if [ ! -f "$plugins" ]; then has_dev=1 has_mqa=1; else
  grep -q '"ono-mobile-dev-plugin@' "$plugins" 2>/dev/null && has_dev=1
  grep -q '"matrix-qa-plugin@' "$plugins" 2>/dev/null && has_mqa=1
fi
[ -n "$has_dev" ] && { command -v "${PG_JQ:-jq}" >/dev/null 2>&1 || no_jq=1; }
if [ -n "$has_dev$has_mqa" ]; then
  node_bin="${PG_NODE:-node}"
  if ! command -v "$node_bin" >/dev/null 2>&1; then
    old_node="none"
  else
    # A broken shim must not eat the whole opener (the hook has 20 s): one watchdog, as in git-status.sh.
    node_out="$(mktemp "${TMPDIR:-/tmp}/pg-node.XXXXXX" 2>/dev/null)"
    if [ -n "$node_out" ]; then
      "$node_bin" -v </dev/null >"$node_out" 2>/dev/null &
      pid=$!
      ( sleep "${PG_NODE_TIMEOUT:-2}"; kill -TERM "$pid" ) >/dev/null 2>&1 &
      dog=$!
      wait "$pid" 2>/dev/null
      if kill -0 "$dog" 2>/dev/null; then pkill -TERM -P "$dog" 2>/dev/null; kill -TERM "$dog" 2>/dev/null; fi
      wait "$dog" 2>/dev/null
      node_v="$(head -1 "$node_out" | tr -d '\r')"
      rm -f "$node_out"
      node_major="${node_v#v}"; node_major="${node_major%%.*}"
      node_minor="${node_v#v*.}"; node_minor="${node_minor%%.*}"
      case "$node_v:$node_major:$node_minor" in
        v*:*[!0-9:]*|v*::*|v*:*:|[!v]*|"":*) old_node="unreadable" ;;
        *) if [ "${#node_major}" -le 4 ] && { [ "$node_major" -ge 24 ] || { [ "$node_major" -eq 22 ] && [ "$node_minor" -ge 18 ]; }; }; then :
           else old_node="$node_v"; fi ;;
      esac
    fi
  fi
fi

node_warn=""
[ -n "$old_node" ] && [ -n "$has_dev" ] && node_warn=1
case "$has_mqa:$old_node" in 1:none|1:unreadable) node_warn=1 ;; esac

last="$("$scripts/session-log.sh" last "$dir" 2>/dev/null)"
others="$("$scripts/session-log.sh" others "$dir" 2>/dev/null | paste -sd, - | sed 's/,/, /g')"

cat <<MSG
[platform-guardian] New session. Whatever the user's first message is — a greeting, a question, a task, a single word — run the \`platform-guardian:session-opener\` skill first, using the data below, then return to their message. No specific trigger word is needed.
Exception: if the first message is a slash command, run that command first and open the session right after its output.

Git report (scripts/git-status.sh, schema 1):
$report
MSG

# First time on this machine → offer the onboarding tour once. The marker is
# written here, at the moment the offer is injected, so it shows exactly once.
state_dir="${PG_LOG_DIR:-$HOME/.claude/platform-guardian}/.state"
marker="$state_dir/onboarding-offered"
if [ "${PG_ONBOARDING:-}" != "off" ] && [ ! -e "$marker" ] &&
   mkdir -p "$state_dir" 2>/dev/null && date '+%Y-%m-%d %H:%M' >"$marker" 2>/dev/null; then
  cat <<MSG

FIRST TIME WITH GUARDIAN on this computer — this notice appears once (already marked as shown in $marker).
Your reply to their first message is ONLY the welcome, so the tour offer can't get buried:
1. An enthusiastic welcome to **OnO Platform Guardian** full of emojis (🎉👋🚀), and one line on what Guardian does for them.
2. Their first message was a task or a question → one short line that you got it and will get to it right after the tour question (don't start on it).
3. The git report needs attention (behind central, on central, central unclear) → at most one line that you'll sort it out right after — no question, no options.
${no_jq:+3b. The TOOLS line below (jq missing) → its one ⚠️ line here, before the tour offer.
}${node_warn:+3c. The TOOLS line(s) below about Node.js → one ⚠️ line here, before the tour offer.
}4. Last, on its own line, in bold: "Want a quick 3-minute tour of how to work with me? 👉 Type **yes** for the tour, or **later** to skip it for now."
Then STOP and wait. No git summary, no git questions, no "what are we working on", nothing after the offer — a second question gets answered instead and the tour is missed.
If yes → run the \`platform-guardian:onboarding\` skill. If later → tell them they can type **onboarding** any time, plus the one-time setup so they always get the latest version: \`/plugin\` → **Marketplaces** → **ono-plugin-marketplace** → **Enable auto-update** — then run the normal opener (session-opener steps 1–4) and get back to their first message.
MSG
fi

if [ -n "$last" ]; then
  printf '\nLast session-log entry for this branch:\n%s\n' "$last"
else
  printf '\nNo session-log entry for this branch yet.\n'
fi
[ -n "$others" ] && printf 'Other branches of this repo with session logs (newest first): %s\n' "$others"

inspect="$("$scripts/inspect-status.sh" check "$dir" 2>/dev/null)"
case "${inspect%%	*}" in
  missing|partial|on-central)
    newer="$("$scripts/inspect-status.sh" elsewhere "$dir" 2>/dev/null)"
    [ -n "$newer" ] && printf '\nINSPECT: FYI — a complete inspection exists on %s (never merged into this branch).\n' "$newer"
    d="${inspect#*	}"
    printf '\nINSPECT GATE: %s%s — this project has NOT been through the Ono Project Inspector. The inspect-gate hook blocks the employee'"'"'s messages and Ono plugin commands with a red ⛔ banner until they run /ono-project-inspector:inspect or type the manager-approval sentence. If a message reaches you anyway (they started the inspector, or typed the sentence), follow session-opener step 0b.\n' \
      "${inspect%%	*}" "${d:+ ($d)}" ;;
  done)
    case "${inspect#*	}" in refresh-recommended:*)
      newer="$("$scripts/inspect-status.sh" elsewhere "$dir" 2>/dev/null)"
      printf '\nINSPECT: complete, but made with an older inspector knowledge model (missing:%s)%s. Not a block — follow session-opener step 0b (offer the refresh).\n' \
        "${inspect#*refresh-recommended:}" "${newer:+; a current-model inspection exists on $newer (never merged into this branch)}" ;;
    esac ;;
  override)
    printf '\nINSPECT GATE: override — not inspected; the employee typed the manager-approval sentence today. Open with one ⚠️ line: working without the inspection today, with manager approval — run /ono-project-inspector:inspect as soon as possible.\n' ;;
esac

if [ -n "$no_jq" ]; then
  printf '\nTOOLS: jq is not installed on this computer, and the Ono dev plugin (0.7.6+) checks every file change with it: without jq it blocks file changes on every branch. Add one ⚠️ line (information, not a question) with the fix — see session-opener step 1.\n'
fi
if [ -n "$old_node" ] && [ -n "$has_dev" ]; then
  case "$old_node" in
    none) node_found="no Node.js was found" ;;
    unreadable) node_found="\`node -v\` gave no version (broken install or NODE_OPTIONS)" ;;
    *) node_found="this computer's Node.js is $old_node (unsupported)" ;;
  esac
  printf '\nTOOLS: %s, and the Ono dev plugin (0.7.7+) needs Node.js 22.18 or later on Node 22, or Node.js 24 or later: on anything else every dev-plugin command stops at its Node check, and an approved Bug Fix Cycle no longer skips the code-edit approval prompt. Add one ⚠️ line (information, not a question) with the fix — see session-opener step 1.\n' "$node_found"
fi
case "$has_mqa:$old_node" in 1:none|1:unreadable)
  if [ "$old_node" = none ]; then mqa_found="no Node.js was found"; else mqa_found="\`node -v\` gave no version (Node.js crashes on start or is broken)"; fi
  printf '\nTOOLS: %s, and the Matrix QA plugin starts node for its safety guard before almost every tool call, in every repo: every Bash / Read / Edit / Grep call will show "PreToolUse:… hook failed" (often a raw error with no plugin name, such as "dyld: Library not loaded"). Outside Matrix QA repos it is only noise; inside them the guard is off (no git-write, .env or Figma protection). Add one ⚠️ line (information, not a question) — see session-opener step 1.\n' "$mqa_found" ;;
esac

resume="$("$scripts/resume-state.sh" "$dir" 2>/dev/null)"
if [ -n "$resume" ]; then
  printf '\nUnfinished work found in the Ono plugins'"'"' documents (scripts/resume-state.sh — apparent stage; the plugin confirms when it runs):\n%s\n' "$resume"
fi
exit 0
