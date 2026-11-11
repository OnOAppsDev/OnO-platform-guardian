#!/usr/bin/env bash
# Bug-report helper for the report-bug skill. bash 3.2, no jq, no python; fails open.
#
#   bug-report.sh env [dir]   → markdown "Environment" section: versions (Claude Code,
#                               Guardian, every installed Ono plugin), macOS, repo, branch,
#                               git state. Facts only — no file contents.
#   bug-report.sh new <slug>  → creates the reports folder and prints a fresh report path
#                               (outside any repo, never committed)
#
# Env: PG_LOG_DIR (base folder, default ~/.claude/platform-guardian),
#      PG_PLUGINS_FILE (installed-plugins list, default ~/.claude/plugins/installed_plugins.json),
#      PG_NO_FETCH=1 is passed through to git-status.sh.

here="$(cd "$(dirname "$0")" && pwd)"
base="${PG_LOG_DIR:-$HOME/.claude/platform-guardian}"
plugins_file="${PG_PLUGINS_FILE:-$HOME/.claude/plugins/installed_plugins.json}"

# json_val KEY JSON → first "KEY": value (string, number or bool), unquoted
json_val() {
  printf '%s' "$2" | tr ',' '\n' | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\{0,1\}\([^\"}]*\)\"\{0,1\}.*/\1/p" | head -n 1
}

ono_plugins() {
  [ -f "$plugins_file" ] || { echo "- (installed-plugins list not found)"; return; }
  awk '
    /"[^"]+@ono-plugin-marketplace"[[:space:]]*:/ {
      if (name != "") print "- " name " · " (ver == "" ? "?" : ver) (sha == "" ? "" : " · " substr(sha, 1, 7))
      match($0, /"[^"@]+@/); name = substr($0, RSTART + 1, RLENGTH - 2); ver = ""; sha = ""; next
    }
    /"[^"]+@[^"]+"[[:space:]]*:[[:space:]]*\[/ {
      if (name != "") print "- " name " · " (ver == "" ? "?" : ver) (sha == "" ? "" : " · " substr(sha, 1, 7))
      name = ""; next
    }
    name != "" && ver == "" && /"version"[[:space:]]*:/ { v = $0; sub(/.*"version"[[:space:]]*:[[:space:]]*"/, "", v); sub(/".*/, "", v); ver = v }
    name != "" && sha == "" && /"gitCommitSha"[[:space:]]*:/ { v = $0; sub(/.*"gitCommitSha"[[:space:]]*:[[:space:]]*"/, "", v); sub(/".*/, "", v); sha = v }
    END { if (name != "") print "- " name " · " (ver == "" ? "?" : ver) (sha == "" ? "" : " · " substr(sha, 1, 7)) }
  ' "$plugins_file" | sort -u | grep . || echo "- (no Ono plugins installed)"
}

cmd_env() {
  local dir="${1:-${CLAUDE_PROJECT_DIR:-$PWD}}" cc gv os who report
  cc="$( (claude --version) 2>/dev/null | head -n 1)"
  gv="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${CLAUDE_PLUGIN_ROOT:-$here/..}/.claude-plugin/plugin.json" 2>/dev/null | head -n 1)"
  os="$(v="$(sw_vers -productVersion 2>/dev/null)" && echo "macOS $v" || uname -sr 2>/dev/null)"
  who="$(git -C "$dir" config user.name 2>/dev/null)"
  echo "## Environment"
  echo
  echo "- Date: $(date '+%Y-%m-%d %H:%M %Z')"
  echo "- Reported by: ${who:-unknown}"
  echo "- Claude Code: ${cc:-unknown}"
  echo "- Platform Guardian: ${gv:-unknown}"
  echo "- OS: ${os:-unknown}"
  echo
  echo "Ono plugins installed:"
  ono_plugins
  echo
  report="$("$here/git-status.sh" "$dir" 2>/dev/null)"
  if [ -z "$report" ] || [ "$(json_val repo "$report")" = "false" ]; then
    echo "Git: not a git project ($(basename "$dir"))"
    return 0
  fi
  local remote repo branch central behind ahead files
  remote="$(git -C "$dir" remote get-url origin 2>/dev/null)"
  repo="$(basename "${remote:-$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)}" .git)"
  branch="$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)"
  central="$(json_val branch "${report#*\"central\"}")"
  behind="$(json_val behind "$report")"; ahead="$(json_val ahead "$report")"
  files="$(git -C "$dir" status --porcelain 2>/dev/null | grep -c .)"
  echo "Git:"
  echo "- Repo: ${repo:-unknown}"
  echo "- Branch: ${branch:-unknown} · central: ${central:-unknown} · behind ${behind:-?} / ahead ${ahead:-?}"
  echo "- Uncommitted files: ${files:-0}"
  local warn
  warn="$(printf '%s' "$report" | sed -n 's/.*"warnings":\[\([^]]*\)\].*/\1/p' | tr -d '"' | sed 's/,/, /g')"
  [ -n "$warn" ] && echo "- Warnings: $warn"
  printf '%s' "$report" | grep -Eq '"fetch":"(failed|timeout)"' && echo "- Note: couldn't reach the server — behind/ahead may be out of date"
  return 0
}

cmd_new() {
  local slug
  slug="$(printf '%s' "${1:-bug}" | tr '[:upper:]' '[:lower:]' | sed -e 's/[^a-z0-9]\{1,\}/-/g' -e 's/^-//' -e 's/-$//' | cut -c1-50)"
  [ -n "$slug" ] || slug="bug"
  mkdir -p "$base/bug-reports" 2>/dev/null || { echo "cannot create $base/bug-reports" >&2; return 1; }
  local path="$base/bug-reports/$(date '+%Y-%m-%d-%H%M')-$slug.md" n=2
  while [ -e "$path" ]; do path="$base/bug-reports/$(date '+%Y-%m-%d-%H%M')-$slug-$n.md"; n=$((n + 1)); done
  printf '%s\n' "$path"
}

case "${1:-}" in
  env) shift; cmd_env "$@" ;;
  new) shift; cmd_new "$@" ;;
  *) echo "usage: bug-report.sh env [dir] | new <slug>" >&2; exit 2 ;;
esac
