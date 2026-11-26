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

# --- a plugin installed more than once (user + project scope), pretty-printed like Claude Code writes it ---
cat >"$WORK/multi.json" <<JSON
{
  "version": 2,
  "plugins": {
    "platform-guardian@ono-plugin-marketplace": [
      {
        "scope": "user",
        "installPath": "/c/ono-plugin-marketplace/platform-guardian/0.5.1",
        "version": "0.5.1",
        "gitCommitSha": "dbede1d000000000"
      },
      {
        "scope": "project",
        "projectPath": "$R",
        "installPath": "/c/ono-plugin-marketplace/platform-guardian/0.7.2",
        "version": "0.7.2",
        "gitCommitSha": "7272727000000000"
      },
      {
        "scope": "local",
        "projectPath": "/somewhere/other-app",
        "installPath": "/c/ono-plugin-marketplace/platform-guardian/0.6.0",
        "version": "0.6.0"
      }
    ],
    "ono-mobile-dev-plugin@ono-plugin-marketplace": [
      {
        "scope": "user",
        "installPath": "/c/ono-plugin-marketplace/ono-mobile-dev-plugin/0.8.0/",
        "version": "0.7.7",
        "gitCommitSha": "6ce121c000000000"
      }
    ],
    "other@elsewhere": [
      { "scope": "user", "version": "1.0.0" }
    ]
  }
}
JSON
out="$(PG_PLUGINS_FILE="$WORK/multi.json" CLAUDE_PLUGIN_ROOT=/c/ono-plugin-marketplace/platform-guardian/0.7.2 "$BR" env "$R")"
has "every install entry listed: user"           "$out" "- platform-guardian · 0.5.1 · dbede1d · user scope"
has "project entry of this repo + running copy"  "$out" "- platform-guardian · 0.7.2 · 7272727 · project scope: this repo · running"
has "local entry of another folder"              "$out" "- platform-guardian · 0.6.0 · local scope: other-app (not this repo)"
has "cache folder differs from recorded version" "$out" "- ono-mobile-dev-plugin · 0.7.7 · 6ce121c · files 0.8.0"
lacks "single entry gets no scope"               "$out" "0.7.7 · 6ce121c · files 0.8.0 · user"
lacks "non-Ono plugin left out"                  "$out" "- other ·"
mkdir -p "$R/sub"; out="$(PG_PLUGINS_FILE="$WORK/multi.json" "$BR" env "$R/sub")"
has "project entry matched from a subfolder"     "$out" "0.7.2 · 7272727 · project scope: this repo"
lacks "no running mark without CLAUDE_PLUGIN_ROOT" "$out" "running"

# --- Windows: Claude Code writes C:\\… paths; Git Bash sees /c/…; case may differ ---
cat >"$WORK/win.json" <<'JSON'
{"version":2,"plugins":{"platform-guardian@ono-plugin-marketplace":[
 {"scope":"user","installPath":"C:\\Users\\Eka\\.claude\\plugins\\cache\\ono-plugin-marketplace\\platform-guardian\\0.8.1","version":"0.8.1"},
 {"scope":"project","projectPath":"C:\\Work\\YesTV","installPath":"C:\\Users\\Eka\\.claude\\plugins\\cache\\ono-plugin-marketplace\\platform-guardian\\0.8.0","version":"0.8.1"}]}}
JSON
WR="$WORK/c/work/yestv"; mkdir -p "$WR"; git -C "$WR" init -q
out="$(cd "$WORK" && PG_PLUGINS_FILE="$WORK/win.json" CLAUDE_PLUGIN_ROOT='C:\Users\Eka\.claude\plugins\cache\ono-plugin-marketplace\platform-guardian\0.8.1' "$BR" env "$WR")"
has "windows: running copy matched across \\ and \\\\" "$out" "- platform-guardian · 0.8.1 · user scope · running"
has "windows: cache folder from a backslash path"     "$out" "- platform-guardian · 0.8.1 · files 0.8.0 · project scope: yestv (not this repo)"
# --- a "{" or "," in a folder name keeps the plugin (and the value) whole ---
cat >"$WORK/odd.json" <<'JSON'
{"version":2,"plugins":{"platform-guardian@ono-plugin-marketplace":[
 {"scope":"project","projectPath":"/w/re,po","installPath":"/x/{we}ird/0.8.0","version":"0.8.1"}]}}
JSON
out="$(PG_PLUGINS_FILE="$WORK/odd.json" "$BR" env "$R")"
has "brace + comma inside strings" "$out" "- platform-guardian · 0.8.1 · files 0.8.0 · project scope: re,po (not this repo)"
# --- a relative folder (env .) still matches the project entry ---
out="$(cd "$R/sub" && PG_PLUGINS_FILE="$WORK/multi.json" "$BR" env .)"
has "relative folder: this repo" "$out" "0.7.2 · 7272727 · project scope: this repo"

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
