#!/usr/bin/env bash
# Tests for scripts/session-log.sh and hooks/session-start.sh.
# Usage: tests/session-log.test.sh
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/.."
LOG="$ROOT/scripts/session-log.sh"
HOOK="$ROOT/hooks/session-start.sh"

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
unset CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_ROOT GIT_SSH_COMMAND PG_FETCH_TIMEOUT

WORK="$(mktemp -d "${TMPDIR:-/tmp}/pg-session-log.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
export PG_LOG_DIR="$WORK/logs" PG_NO_FETCH=1

PASS=0 FAIL=0
ok()   { PASS=$((PASS + 1)); }
fail() { FAIL=$((FAIL + 1)); echo "FAIL $1"; [ -n "${2:-}" ] && printf '      got: %s\n' "$2"; }
expect_eq()       { [ "$2" = "$3" ] && ok || fail "$1" "$2"; }
expect_contains() { case "$2" in *"$3"*) ok ;; *) fail "$1 (missing: $3)" "$2" ;; esac; }
expect_absent()   { case "$2" in *"$3"*) fail "$1 (unexpected: $3)" "$2" ;; *) ok ;; esac; }

g() { git -c init.defaultBranch=main "$@" >/dev/null 2>&1; }

# Repo with a remote whose name differs from the clone folder.
g init --bare "$WORK/My-App.git"
g clone "$WORK/My-App.git" "$WORK/clone-folder"
R="$WORK/clone-folder"
echo x >"$R/a"; g -C "$R" add a; g -C "$R" commit -m init
g -C "$R" checkout -b feature/login

# --- path ---
expect_eq "path uses remote repo name + sanitized branch" \
  "$("$LOG" path "$R")" "$WORK/logs/My-App/feature_login.md"

g -C "$R" remote remove origin
expect_eq "path falls back to folder name without a remote" \
  "$("$LOG" path "$R")" "$WORK/logs/clone-folder/feature_login.md"
g -C "$R" remote add origin "git@github.com:OnOAppsDev/My-App.git"
expect_eq "scp-style remote URL" \
  "$("$LOG" path "$R")" "$WORK/logs/My-App/feature_login.md"

# --- last / append ---
expect_eq "last is empty with no log" "$("$LOG" last "$R")" ""

printf 'What we did: started login.\nNext step: tests.' | "$LOG" append "$R" >/dev/null
printf 'What we did: login form done.\nWhere we stopped: validation.\nNext step: API call.' | "$LOG" append "$R" >/dev/null
last="$("$LOG" last "$R")"
expect_contains "last returns newest entry" "$last" "login form done"
expect_absent   "last excludes older entries" "$last" "started login"
expect_contains "entry heading has branch" "$last" "· feature/login"
expect_eq "two headings in the file" "$(grep -c '^## ' "$WORK/logs/My-App/feature_login.md")" "2"

out="$(printf '' | "$LOG" append "$R" 2>&1)"; rc=$?
expect_eq "append rejects empty stdin" "$rc" "1"

# --- others ---
g -C "$R" checkout -b bugfix/crash
printf 'Next step: repro.' | "$LOG" append "$R" >/dev/null
expect_eq "others lists other branches only" "$("$LOG" others "$R")" "feature_login"

# --- outside git / usage ---
mkdir -p "$WORK/plain"
expect_eq "outside git prints nothing" "$("$LOG" path "$WORK/plain")" ""
"$LOG" bogus "$R" >/dev/null 2>&1; expect_eq "unknown command is a usage error" "$?" "2"

# --- hook ---
g -C "$R" checkout feature/login
out="$(echo '{"source":"startup"}' | CLAUDE_PROJECT_DIR="$R" "$HOOK")"; rc=$?
expect_eq "hook exits 0" "$rc" "0"
expect_contains "hook names the skill" "$out" "platform-guardian:session-opener"
expect_contains "hook embeds the git report" "$out" '"branch":"feature/login"'
expect_contains "hook includes last log entry" "$out" "login form done"
expect_contains "hook lists other logged branches" "$out" "bugfix_crash"

report="$(printf '%s\n' "$out" | grep '^{"schema"')"
if printf '%s' "$report" | jq -e '.repo == true' >/dev/null 2>&1; then ok; else fail "hook report line is valid JSON" "$report"; fi

out="$(echo '{}' | CLAUDE_PROJECT_DIR="$WORK/plain" "$HOOK")"; rc=$?
expect_eq "hook outside git exits 0" "$rc" "0"
expect_contains "hook outside git still reports repo:false" "$out" '"repo":false'
expect_contains "hook outside git has no-log line" "$out" "No session-log entry"

out="$(echo '{}' | CLAUDE_PLUGIN_ROOT="$WORK/nowhere" CLAUDE_PROJECT_DIR="$R" "$HOOK" 2>&1)"; rc=$?
expect_eq "hook with broken plugin root fails open" "$rc:$out" "0:"

echo
echo "session-log.sh + session-start.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
