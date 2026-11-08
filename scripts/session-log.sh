#!/usr/bin/env bash
# Platform Guardian — local session log (never committed to git).
#
# One Markdown file per repo + branch:
#   ${PG_LOG_DIR:-~/.claude/platform-guardian}/<repo>/<branch>.md
# Entries are appended; each starts with a "## " heading line.
#
# Usage:
#   session-log.sh path   [dir]   print the log file path for dir's repo + branch
#   session-log.sh last   [dir]   print the last entry (nothing if none)
#   session-log.sh others [dir]   print up to 5 other branches of this repo with logs, newest first
#   session-log.sh append [dir]   append stdin as a new entry under a dated heading
#
# dir defaults to $CLAUDE_PROJECT_DIR, then the current directory.
# Always exits 0 except for usage errors; prints nothing outside a git repo.

cmd="${1:-}"
target="${2:-${CLAUDE_PROJECT_DIR:-$PWD}}"
base="${PG_LOG_DIR:-$HOME/.claude/platform-guardian}"

sanitize() { printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_'; }

cd "$target" 2>/dev/null || exit 0
[ "$(git rev-parse --is-inside-work-tree 2>/dev/null)" = "true" ] || exit 0
root="$(git rev-parse --show-toplevel 2>/dev/null)"

# Repo key: the remote's repository name (stable across clone folders), else the folder name.
url="$(git remote get-url origin 2>/dev/null || git remote get-url "$(git remote 2>/dev/null | head -n 1)" 2>/dev/null)"
name=""
if [ -n "$url" ]; then
  name="${url%/}"; name="${name%.git}"; name="${name##*/}"; name="${name##*:}"
fi
[ -z "$name" ] && name="$(basename "$root")"
repo_dir="$base/$(sanitize "$name")"

branch="$(git symbolic-ref -q --short HEAD 2>/dev/null)"
[ -z "$branch" ] && branch="detached"
file="$repo_dir/$(sanitize "$branch").md"

case "$cmd" in
  path)
    printf '%s\n' "$file"
    ;;
  last)
    [ -f "$file" ] || exit 0
    # From the last "## " heading to the end of the file.
    awk '/^## /{buf=""} {buf=buf $0 "\n"} END{printf "%s", buf}' "$file"
    ;;
  others)
    [ -d "$repo_dir" ] || exit 0
    self="$(basename "$file")"
    ls -t "$repo_dir" 2>/dev/null | grep '\.md$' | grep -vx "$self" | head -n 5 | sed 's/\.md$//'
    ;;
  append)
    entry="$(cat)"
    [ -z "$entry" ] && { echo "session-log.sh append: empty entry on stdin" >&2; exit 1; }
    mkdir -p "$repo_dir" || exit 1
    {
      [ -s "$file" ] && printf '\n'
      printf '## %s · %s\n\n%s\n' "$(date '+%Y-%m-%d %H:%M')" "$branch" "$entry"
    } >>"$file"
    printf '%s\n' "$file"
    ;;
  *)
    echo "usage: session-log.sh {path|last|others|append} [dir]" >&2
    exit 2
    ;;
esac
exit 0
