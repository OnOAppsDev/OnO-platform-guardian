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

# one line per install entry of every Ono plugin. A plugin can be installed more than once
# (user scope + project/local scope for one folder); then each line names its scope, and a
# project entry says whether it is this repo's. "files <dir>" = the cache folder holds another
# version than the list records; "running" = the copy this script runs from.
ono_plugins() {
  local dir="$1" top="" prefix
  [ -f "$plugins_file" ] || { echo "- (installed-plugins list not found)"; return; }
  dir="$(cd "$dir" 2>/dev/null && pwd)" || dir="$1"   # absolute, symlinks kept (projectPath is absolute)
  dir="${dir%/}"
  # repo root as the folder was named (show-toplevel resolves symlinks: /var → /private/var)
  if prefix="$(git -C "$dir" rev-parse --show-prefix 2>/dev/null)"; then
    prefix="${prefix%/}"; top="$dir"; [ -n "$prefix" ] && top="${dir%/"$prefix"}"
  fi
  # 1st awk: JSON punctuation onto its own line, outside strings only (a "{" or "," in a folder
  # name stays in its value); 2nd awk: one record per install entry
  awk '{ s = $0; out = ""
         for (i = 1; i <= length(s); i++) { c = substr(s, i, 1)
           if (esc) { esc = 0; out = out c; continue }
           if (ins) { if (c == "\\") esc = 1; else if (c == "\"") ins = 0; out = out c; continue }
           if (c == "\"") { ins = 1; out = out c; continue }
           if (c ~ /[][{},]/) { out = out "\n" c "\n"; continue }
           out = out c }
         print out }' "$plugins_file" |
  # values via the environment: awk -v would eat the backslashes of a Windows path
  PG_DIR="$dir" PG_TOP="$top" PG_SELF="${CLAUDE_PLUGIN_ROOT:-}" awk '
    BEGIN { dir = ENVIRON["PG_DIR"]; top = ENVIRON["PG_TOP"]; self = ENVIRON["PG_SELF"] }
    function val(line,   v) { v = line; sub(/^[^:]*:[[:space:]]*"/, "", v); sub(/"[[:space:]]*$/, "", v); return v }
    # Windows: JSON "C:\\Users\\x" and Git Bash /c/Users/x compare equal, case-insensitively
    function norm(p) {
      gsub(/\\/, "/", p); gsub(/\/+/, "/", p)
      if (p ~ /^[A-Za-z]:\//) p = "/" substr(p, 1, 1) substr(p, 3)
      sub(/\/+$/, "", p)
      if (p ~ /^\/[A-Za-z]\//) p = tolower(p)
      return p
    }
    function base(p) { p = norm(p); sub(/.*\//, "", p); return p }
    function flush(   i, line, b, s, pp) {
      for (i = 1; i <= n; i++) {
        line = "- " name " · " (ver[i] == "" ? "?" : ver[i]) (sha[i] == "" ? "" : " · " substr(sha[i], 1, 7))
        b = base(path[i])
        if (b ~ /^[0-9]+\.[0-9]+/ && ver[i] != "" && b != ver[i]) line = line " · files " b
        s = scope[i]; pp = norm(proj[i])
        if (s == "project" || s == "local") {
          if (pp != "" && (pp == norm(dir) || pp == norm(top))) line = line " · " s " scope: this repo"
          else line = line " · " s " scope: " (pp == "" ? "?" : base(pp)) " (not this repo)"
        } else if (n > 1 && s != "") line = line " · " s " scope"
        if (self != "" && path[i] != "" && norm(path[i]) == norm(self)) line = line " · running"
        print line
      }
      name = ""; n = 0
    }
    { sub(/^[[:space:]]+/, ""); sub(/[[:space:]]+$/, "") }
    $0 == "" { next }
    /^"[^"]+@ono-plugin-marketplace"[[:space:]]*:/ { name = $0; sub(/^"/, "", name); sub(/@.*/, "", name); n = 0; depth = 0; next }
    name == "" { next }
    $0 == "{" { depth++; if (depth == 1) { n++; ver[n] = sha[n] = scope[n] = proj[n] = path[n] = "" } next }
    $0 == "}" { depth--; next }
    $0 == "]" && depth == 0 { flush(); next }
    depth == 1 && /^"version"[[:space:]]*:/      { ver[n] = val($0) }
    depth == 1 && /^"gitCommitSha"[[:space:]]*:/ { sha[n] = val($0) }
    depth == 1 && /^"scope"[[:space:]]*:/        { scope[n] = val($0) }
    depth == 1 && /^"projectPath"[[:space:]]*:/  { proj[n] = val($0) }
    depth == 1 && /^"installPath"[[:space:]]*:/  { path[n] = val($0) }
  ' | sort -u | grep . || echo "- (no Ono plugins installed)"
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
  ono_plugins "$dir"
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
