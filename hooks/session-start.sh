#!/usr/bin/env bash
# SessionStart hook (startup | clear): injects the git report and the last local
# session-log entry as context, and instructs Claude to run the session-opener
# skill. Plain stdout from a SessionStart hook is added to Claude's context.
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
[platform-guardian] New session. Before anything else, run the \`platform-guardian:session-opener\` skill and follow it, using the data below.
Exception: if the user's first message is a slash command, run that command first and open the session right after its output.

Git report (scripts/git-status.sh, schema 1):
$report
MSG

if [ -n "$last" ]; then
  printf '\nLast session-log entry for this branch:\n%s\n' "$last"
else
  printf '\nNo session-log entry for this branch yet.\n'
fi
[ -n "$others" ] && printf 'Other branches of this repo with session logs (newest first): %s\n' "$others"
exit 0
