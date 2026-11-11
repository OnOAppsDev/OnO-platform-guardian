#!/usr/bin/env bash
# Tests for scripts/bug-report.sh against throwaway repos and a fake installed-plugins list.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
BR="$HERE/../scripts/bug-report.sh"

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 PG_NO_FETCH=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
unset CLAUDE_PLUGIN_ROOT CLAUDE_PROJECT_DIR

WORK="$(mktemp -d "${TMPDIR:-/tmp}/pg-bugreport.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
export PG_LOG_DIR="$WORK/state"

PASS=0 FAIL=0
ok()   { PASS=$((PASS + 1)); }
fail() { FAIL=$((FAIL + 1)); echo "FAIL [$1]"; [ -n "${2:-}" ] && printf '      got: %s\n' "$2"; }
has()  { case "$2" in *"$3"*) ok ;; *) fail "$1" "$2" ;; esac; }
lacks(){ case "$2" in *"$3"*) fail "$1" "$2" ;; *) ok ;; esac; }

cat >"$WORK/plugins.json" <<'JSON'
{
  "version": 2,
  "plugins": {
    "frontend-design@claude-plugins-official": [
      { "scope": "user", "version": "9.9.9", "gitCommitSha": "ffffffffffffffff" }
    ],
    "platform-guardian@ono-plugin-marketplace": [
      { "scope": "user", "installPath": "/x", "version": "0.2.7", "gitCommitSha": "abcdef1234567890" }
    ],
    "ono-mobile-dev-plugin@ono-plugin-marketplace": [
      { "scope": "user", "version": "3.1.0" }
    ]
  }
}
JSON
export PG_PLUGINS_FILE="$WORK/plugins.json"

# --- env in a git repo ---
R="$WORK/app"; mkdir -p "$R"
git -c init.defaultBranch=develop init -q "$R"; git -C "$R" config user.name "Dana Dev"
echo a >"$R/a.txt"; git -C "$R" add a.txt; git -C "$R" commit -qm init
git -C "$R" switch -q -c bugfix/x; echo b >"$R/b.txt"
out="$("$BR" env "$R")"; rc=$?
[ "$rc" -eq 0 ] && ok || fail "env exits 0" "$rc"
has "section heading" "$out" "## Environment"
has "reporter from git" "$out" "Reported by: Dana Dev"
has "guardian version from manifest" "$out" "Platform Guardian: $(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$HERE/../.claude-plugin/plugin.json")"
has "ono plugin with version + short sha" "$out" "- platform-guardian · 0.2.7 · abcdef1"
has "ono plugin without sha" "$out" "- ono-mobile-dev-plugin · 3.1.0"
lacks "non-Ono plugins left out" "$out" "frontend-design"
has "branch line" "$out" "Branch: bugfix/x"
has "uncommitted count" "$out" "Uncommitted files: 1"
lacks "no file contents" "$out" "b.txt"

# --- env outside git / missing plugins list ---
mkdir -p "$WORK/plain"
out="$(PG_PLUGINS_FILE="$WORK/nope.json" "$BR" env "$WORK/plain")"; rc=$?
[ "$rc" -eq 0 ] && ok || fail "env outside git exits 0" "$rc"
has "outside git says so" "$out" "Git: not a git project"
has "missing plugins list says so" "$out" "installed-plugins list not found"

# --- new ---
p="$("$BR" new "Verify Fix Cycle: REPOSITORY_UNAVAILABLE!")"
case "$p" in "$PG_LOG_DIR/bug-reports/"*-verify-fix-cycle-repository-unavailable.md) ok ;; *) fail "new: path + slug" "$p" ;; esac
[ -d "$PG_LOG_DIR/bug-reports" ] && ok || fail "new creates the folder"
touch "$p"; p2="$("$BR" new "Verify Fix Cycle: REPOSITORY_UNAVAILABLE!")"
[ "$p2" != "$p" ] && ok || fail "new never reuses an existing file" "$p2"
p3="$("$BR" new "!!!")"; case "$p3" in *-bug.md) ok ;; *) fail "empty slug → bug" "$p3" ;; esac
p4="$("$BR" new "../../etc/passwd")"; case "$p4" in "$PG_LOG_DIR/bug-reports/"*-etc-passwd.md) ok ;; *) fail "slug can't escape the folder" "$p4" ;; esac

"$BR" bogus >/dev/null 2>&1; [ "$?" -eq 2 ] && ok || fail "unknown command → usage (2)"

echo
echo "bug-report.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
