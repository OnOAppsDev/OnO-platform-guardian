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
Open your reply to their first message with an enthusiastic welcome full of emojis (🎉👋🚀), say in one line what Guardian does for them, then clearly offer the interactive tour: "Want a quick 3-minute tour of how to work with this? (yes / later)". If yes → run the \`platform-guardian:onboarding\` skill. If later → tell them they can type **onboarding** any time, and continue the normal opener. Still show any git warning that needs attention (behind central, on central) — briefly.
MSG
fi

if [ -n "$last" ]; then
  printf '\nLast session-log entry for this branch:\n%s\n' "$last"
else
  printf '\nNo session-log entry for this branch yet.\n'
fi
[ -n "$others" ] && printf 'Other branches of this repo with session logs (newest first): %s\n' "$others"

resume="$("$scripts/resume-state.sh" "$dir" 2>/dev/null)"
if [ -n "$resume" ]; then
  printf '\nUnfinished work found in the Ono plugins'"'"' documents (scripts/resume-state.sh — apparent stage; the plugin confirms when it runs):\n%s\n' "$resume"
fi
exit 0
