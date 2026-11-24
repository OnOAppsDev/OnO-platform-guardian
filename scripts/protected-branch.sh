#!/usr/bin/env bash
# Protected branches — the one definition Guardian's hooks share (inspect gate, write guard,
# commit guard). Fast: no fetch, no full central-branch detection — a write hook calls it
# before every file write.
#
#   protected-branch.sh check [dir]           → "<protected|ok|skip><TAB><branch><TAB><central>"
#   protected-branch.sh is <name> [dir]       → exit 0 if <name> is a protected branch, else 1
#   protected-branch.sh remember [dir] <branch> → cache the detected central branch for this repo
#                                               (SessionStart, only when detection is certain)
#   protected-branch.sh forget [dir]          → drop the cache (detection uncertain)
#   protected-branch.sh answer [dir] <branch> → remember the employee's own answer to "which branch
#                                               is central?" on this computer (session opener);
#                                               prints the name stored, exit 1 if it isn't a branch here
#   protected-branch.sh answered [dir]        → print that answer (scripts/git-status.sh), or nothing
#
# Protected = main, master, and the project's central branch when it's known for sure:
#   1. .platform-guardian.json "centralBranch" (committed, the team's choice)
#   2. the cache SessionStart wrote from scripts/git-status.sh at confidence "high"
# An uncertain central branch is never protected — the session opener asks first, so a wrong
# guess can't block a legitimate branch. main/master are always protected.
# Detached HEAD, a branch with no commits yet, or not a git repo → not protected. Names compare
# case-insensitively (macOS: `Main` and `main` are the same ref). Always exits 0 for check (fails open).
#
# Env: PG_LOG_DIR (state dir base).

cmd="${1:-check}"
case "$cmd" in
  is) name="${2:-}"; dir="${3:-${CLAUDE_PROJECT_DIR:-$PWD}}" ;;
  remember|answer) dir="${2:-}"; remember="${3:-}" ;;
  *) dir="${2:-${CLAUDE_PROJECT_DIR:-$PWD}}" ;;
esac
[ -n "$dir" ] || dir="${CLAUDE_PROJECT_DIR:-$PWD}"

# one git call (process launches are the cost here — the write guard runs before every write):
# the toplevel and the git dir; the branch is read from <git-dir>/HEAD (works on an unborn repo)
top="" gitdir=""
{ IFS= read -r top; IFS= read -r gitdir; } <<EOF
$(git -C "$dir" rev-parse --show-toplevel --absolute-git-dir 2>/dev/null)
EOF
cache_file() { # cache_file [kind] — per repo, outside the repo
  local k="${top//_/__}"; k="${k// /+}"   # "_" doubled first, so no two paths share a file
  printf '%s/.state/%s%s' "${PG_LOG_DIR:-$HOME/.claude/platform-guardian}" "${1:-central}" "${k//\//_}"
}

case "$cmd" in
  remember)
    [ -n "$top" ] && [ -n "$remember" ] || exit 0
    f="$(cache_file)"; mkdir -p "$(dirname "$f")" 2>/dev/null && printf '%s\n' "$remember" >"$f" 2>/dev/null
    exit 0 ;;
  forget)
    [ -n "$top" ] && rm -f "$(cache_file)" 2>/dev/null
    exit 0 ;;
  answer) # the employee's answer: an existing branch ("origin/develop" → "develop"). It also
    # protects the branch right away (the guess cache), not only from the next session start.
    # Prints the stored name; exit 1 (nothing stored) if no such branch → the opener must say so.
    [ -n "$top" ] && [ -n "$remember" ] || exit 1
    for r in $(git -C "$top" remote 2>/dev/null); do remember="${remember#"$r"/}"; done
    git check-ref-format --branch "$remember" >/dev/null 2>&1 || exit 1
    git -C "$top" show-ref -q --verify "refs/heads/$remember" 2>/dev/null ||
      git -C "$top" for-each-ref --format='%(refname)' "refs/remotes/*/$remember" 2>/dev/null | grep -q . || exit 1
    f="$(cache_file answered-central)"; mkdir -p "$(dirname "$f")" 2>/dev/null &&
      printf '%s\n' "$remember" >"$f" 2>/dev/null && printf '%s\n' "$remember" >"$(cache_file)" 2>/dev/null || exit 1
    printf '%s\n' "$remember"
    exit 0 ;;
  answered)
    [ -n "$top" ] || exit 0
    f="$(cache_file answered-central)"; [ -f "$f" ] && IFS= read -r a <"$f" && printf '%s\n' "$a"
    exit 0 ;;
esac

central=""
if [ -n "$top" ]; then
  if [ -f "$top/.platform-guardian.json" ]; then
    re='"centralBranch"[[:space:]]*:[[:space:]]*"([^"]*)"'
    while IFS= read -r l || [ -n "$l" ]; do
      [[ $l =~ $re ]] && { central="${BASH_REMATCH[1]}"; break; }
    done <"$top/.platform-guardian.json"
  fi
  if [ -z "$central" ]; then
    f="$(cache_file)"
    [ -f "$f" ] && IFS= read -r central <"$f"
  fi
fi

protected() { # protected NAME — case-insensitive: on macOS `Main` IS `main` (refs are files)
  case "$1" in '') return 1 ;; [Mm][Aa][Ii][Nn]|[Mm][Aa][Ss][Tt][Ee][Rr]) return 0 ;; esac
  [ -n "$central" ] || return 1
  shopt -s nocasematch; [[ $1 == "$central" ]]; local r=$?; shopt -u nocasematch; return $r
}

if [ "$cmd" = "is" ]; then
  [ -n "$top" ] || exit 1
  protected "$name"; exit $?
fi

[ -n "$top" ] || { printf 'skip\t\t\n'; exit 0; }
branch=""
[ -f "$gitdir/HEAD" ] && IFS= read -r head <"$gitdir/HEAD" && case "$head" in "ref: refs/heads/"*) branch="${head#ref: refs/heads/}" ;; esac
# reftable repositories keep a stub HEAD file ("refs/heads/.invalid") → ask git
[ "$branch" = .invalid ] && branch="$(git -C "$dir" symbolic-ref -q --short HEAD 2>/dev/null)"
# a branch with no commits yet (a brand-new project) isn't protected: there's nothing to protect,
# and the first files of a new project must be writable
if protected "$branch" && git -C "$dir" rev-parse -q --verify HEAD >/dev/null 2>&1; then printf 'protected\t%s\t%s\n' "$branch" "$central"
else printf 'ok\t%s\t%s\n' "$branch" "$central"; fi
exit 0
