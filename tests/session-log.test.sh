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

# --- hook: first-time onboarding offer, exactly once ---
g -C "$R" checkout feature/login
out="$(echo '{"source":"startup"}' | CLAUDE_PROJECT_DIR="$R" "$HOOK")"
expect_contains "first session offers the tour" "$out" "FIRST TIME WITH GUARDIAN"
expect_contains "offer names the onboarding skill" "$out" "platform-guardian:onboarding"
expect_contains "offer says how to get it later" "$out" "type **onboarding** any time"
expect_contains "offer says exactly what to type" "$out" "👉 Type **yes** for the tour, or **later**"
[ -s "$PG_LOG_DIR/.state/onboarding-offered" ] && ok || fail "marker written" "$(ls -la "$PG_LOG_DIR/.state" 2>&1)"
out="$(echo '{"source":"clear"}' | CLAUDE_PROJECT_DIR="$R" "$HOOK")"
case "$out" in *"FIRST TIME"*) fail "offer shown only once" "$out" ;; *) ok ;; esac
out="$(echo '{}' | CLAUDE_PROJECT_DIR="$WORK/plain" "$HOOK")"
case "$out" in *"FIRST TIME"*) fail "not again outside git either" "$out" ;; *) ok ;; esac
out="$(echo '{}' | PG_LOG_DIR="$WORK/fresh" PG_ONBOARDING=off CLAUDE_PROJECT_DIR="$R" "$HOOK")"
case "$out" in *"FIRST TIME"*) fail "PG_ONBOARDING=off" "$out" ;; *) ok ;; esac
[ -e "$WORK/fresh/.state/onboarding-offered" ] && fail "off writes no marker" "" || ok
if [ "$(id -u)" != 0 ]; then   # root ignores permissions
  mkdir -p "$WORK/fresh" && chmod 500 "$WORK/fresh"
  out="$(echo '{}' | PG_LOG_DIR="$WORK/fresh" CLAUDE_PROJECT_DIR="$R" "$HOOK" 2>&1)"; rc=$?
  case "$rc:$out" in 0:*"FIRST TIME"*) fail "unwritable state dir → no offer (it would repeat every session)" "$out" ;; 0:*) ok ;; *) fail "unwritable state dir fails open" "$rc" ;; esac
  chmod 700 "$WORK/fresh"
fi

# --- hook ---
out="$(echo '{"source":"startup"}' | CLAUDE_PROJECT_DIR="$R" "$HOOK")"; rc=$?
expect_eq "hook exits 0" "$rc" "0"
expect_contains "hook names the skill" "$out" "platform-guardian:session-opener"
expect_contains "hook embeds the git report" "$out" '"branch":"feature/login"'
expect_contains "hook includes last log entry" "$out" "login form done"
expect_contains "hook lists other logged branches" "$out" "bugfix_crash"

case "$out" in *"Unfinished work found"*) fail "no resume section without plugin documents" "$out" ;; *) ok ;; esac

# Unfinished work in the plugins' documents → its own section, exact line format.
mkdir -p "$R/docs"
printf '# FA\n\n```yaml\nfeature: login\ndd_link:\nsurface: app\nstatus: proposed\n```\n' >"$R/docs/login-feature-analysis.md"
out="$(echo '{"source":"clear"}' | CLAUDE_PROJECT_DIR="$R" "$HOOK" 2>"$WORK/err")"
expect_contains "hook has the resume section" "$out" "Unfinished work found in the Ono plugins' documents (scripts/resume-state.sh — apparent stage; the plugin confirms when it runs):"
expect_contains "hook lists the resume line" "$out" "- ono-mobile-dev-plugin · feature login · feature analysis waiting for approval · next: your step — approve the analysis (status: approved), then /dev-design-start login  [docs/login-feature-analysis.md]"
expect_eq "hook writes nothing to stderr" "$(cat "$WORK/err")" ""
out="$(echo '{}' | PG_RESUME=off CLAUDE_PROJECT_DIR="$R" "$HOOK")"
case "$out" in *"Unfinished work found"*) fail "PG_RESUME=off removes the section" "$out" ;; *) ok ;; esac
rm -rf "$R/docs"

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
