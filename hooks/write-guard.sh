#!/usr/bin/env bash
# PreToolUse hook (Write | Edit | NotebookEdit | Skill | SlashCommand | Agent | Task): no file
# writes on a protected branch, and Claude never starts the Ono Project Inspector there (it writes
# files, partly through bun scripts no write hook sees — the inspect gate stops the employee's
# typed command; this stops Claude starting it through a tool). Read-only inspect-status is fine.
# Protected = main, master, and the project's central branch when it's certain
# (scripts/protected-branch.sh). Guardian's own rule — it doesn't rely on any Ono plugin's hook
# (the dev plugin guards main/master on its own, on purpose; both stay).
#
# Only files inside a git repository that git would track: files outside any repo (Claude's
# memory, scratch, /tmp), anything under ~/.claude, and git-ignored files are never blocked.
# The Ono QA plugins own their git flow (the employee reviews and commits in the QA repo), so
# Guardian doesn't block them: the ono-plugin-qa QA repo (named in the workspace's
# .claude/qa-workspace.json, or its auto-detect: a *qa* repo next to the code repo) and the qa/
# folder next to matrix-qa.config.json.
# Writes through Bash aren't seen here; the commit guard (pre-tool-use.sh) denies commit / push
# on a protected branch, and server-side branch protection is the real guarantee.
# Fails open: anything unexpected → exit 0, no output. Never writes stderr.
#
# Env: PG_WRITE_GUARD=off disables it.

[ "${PG_WRITE_GUARD:-}" = "off" ] && exit 0
exec 2>/dev/null
command -v git >/dev/null || exit 0
here="$(cd "$(dirname "$0")" && pwd)"
scripts="${CLAUDE_PLUGIN_ROOT:-$here/..}/scripts"
payload="$(cat)"

# one awk pass (process launches are the cost — this runs before every write): the first
# string value of each key, unescaped, one per line: tool_name, file_path, notebook_path, cwd,
# and what a Skill / SlashCommand / Agent / Task call starts
fields="$(printf '%s' "$payload" | awk '
  { buf = buf $0 "\n" }
  function val(key,   i, s, out, c, n) {
    i = index(buf, "\"" key "\""); if (!i) return ""
    s = substr(buf, i + length(key) + 2); if (!match(s, /^[ \t\r\n]*:[ \t\r\n]*"/)) return ""
    s = substr(s, RLENGTH + 1, 4096); out = ""   # values are short; never walk a big file body
    while (length(s) > 0) {
      c = substr(s, 1, 1)
      if (c == "\\") { n = substr(s, 2, 1)
        if (n == "n" || n == "t") out = out " "; else out = out n
        s = substr(s, 3); continue }
      if (c == "\"") break
      out = out c; s = substr(s, 2)
    }
    return out
  }
  END { printf "%s\n%s\n%s\n%s\n%s %s %s\n", val("tool_name"), val("file_path"), val("notebook_path"),
          val("cwd"), val("skill"), val("command"), val("subagent_type") }')"
{ IFS= read -r tool; IFS= read -r file; IFS= read -r nb; IFS= read -r cwd; IFS= read -r starts; } <<EOF
$fields
EOF

json_esc() {
  printf '%s' "$1" | tr -d '\000-\011\013-\037' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' \
    | awk '{ printf "%s%s", (NR > 1 ? "\\n" : ""), $0 }'
}
deny() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$(json_esc "$1")"
  exit 0
}
[ -d "$cwd" ] || cwd="${CLAUDE_PROJECT_DIR:-$PWD}"

case "$tool" in
  Write|Edit|MultiEdit) ;;
  NotebookEdit) [ -n "$nb" ] && file="$nb" ;;
  Skill|SlashCommand|Agent|Task)
    case "$starts" in *ono-project-inspector*) ;; *) exit 0 ;; esac
    case "$starts" in *inspect-status*) exit 0 ;; esac
    line="$("$scripts/protected-branch.sh" check "$cwd")"
    [ "${line%%	*}" = protected ] || exit 0
    rest="${line#*	}"; branch="${rest%%	*}"
    deny "[platform-guardian] Blocked: the Ono Project Inspector writes files, so it never runs on \`$branch\` (a protected branch).
Tell the employee in one line, then offer to create a work branch first: ask for a short name (suggest chore/project-inspection) and, once they confirm, run \`git switch -c <name>\`. Then start the inspector again." ;;
  *) exit 0 ;;
esac
[ -n "$file" ] || exit 0
case "$file" in /*) ;; *) file="$cwd/$file" ;; esac
case "$file" in "$HOME"/.claude/*) exit 0 ;; esac   # Claude's own memory, plans, settings

# the nearest existing folder of the file → its repository (the file may not exist yet)
d="${file%/*}"; [ -n "$d" ] || d=/
while [ ! -d "$d" ] && [ "$d" != "/" ]; do d="${d%/*}"; [ -n "$d" ] || d=/; done

line="$("$scripts/protected-branch.sh" check "$d")"
[ "${line%%	*}" = protected ] || exit 0        # the common case: a work branch, or no repo
git -C "$d" check-ignore -q -- "$file" && exit 0   # ignored files can't reach the branch
rest="${line#*	}"; branch="${rest%%	*}"

# the Ono QA plugins' own repos / folders (see the header) — rare path, only on a protected branch
top="$(git -C "$d" rev-parse --show-toplevel)"
dp="$(cd "$d" && pwd -P)"; real="$dp${file#"$d"}"        # the file, with the repo's spelling
parent="${top%/*}"; name="${top##*/}"
if [ -f "$parent/.claude/qa-workspace.json" ]; then
  grep -Eq "\"qaRepoPath\"[[:space:]]*:[[:space:]]*\"([^\"]*/)?$name/?\"" "$parent/.claude/qa-workspace.json" && exit 0
else
  case "$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')" in
    *qa*) for sib in "$parent"/*; do
            [ "$sib" != "$top" ] && [ -e "$sib/.git" ] && exit 0
          done ;;
  esac
fi
q="$(dirname "$real")"
while :; do   # the qa/ folder next to the nearest matrix-qa.config.json
  [ -f "$q/matrix-qa.config.json" ] && { case "$real" in "$q"/qa/*) exit 0 ;; esac; break; }
  [ "$q" = "$top" ] || [ "$q" = / ] && break
  q="$(dirname "$q")"
done

deny "[platform-guardian] Blocked: \`$branch\` is a protected branch — no file changes here (Ono rule; work goes into a PR).
Tell the employee in one line, then offer to create a work branch: ask for a short name (follow the repo's naming, e.g. feature/…, bugfix/…) and, once they confirm, run \`git switch -c <name>\` — uncommitted changes move with it. Then redo this change. Never commit on \`$branch\`."
exit 0
