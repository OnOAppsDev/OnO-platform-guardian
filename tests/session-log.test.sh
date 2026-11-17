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
# The machine's own node must not decide the TOOLS lines: default to a supported one.
printf '#!/bin/sh\necho v24.0.0\n' >"$WORK/node-ok"; chmod +x "$WORK/node-ok"
export PG_NODE="$WORK/node-ok"

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
expect_contains "welcome uses the product name" "$out" "welcome to **OnO Platform Guardian**"
expect_contains "offer says how to get it later" "$out" "type **onboarding** any time"
expect_contains "offer says exactly what to type" "$out" "👉 Type **yes** for the tour, or **later**"
expect_contains "offer is the whole first reply — nothing after it" "$out" "Then STOP and wait. No git summary, no git questions"
expect_contains "offer includes the one-time auto-update setup" "$out" "**Marketplaces** → **ono-plugin-marketplace** → **Enable auto-update**"
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

# --- jq missing → TOOLS line (the dev plugin 0.7.6+ blocks writes without it) ---
printf '{"plugins":{"ono-mobile-dev-plugin@ono-plugin-marketplace":[{}]}}' >"$WORK/with-dev.json"
printf '{"plugins":{"spec-team-toolkit@ono-plugin-marketplace":[{}]}}' >"$WORK/no-dev.json"
out="$(echo '{}' | PG_JQ=pg-no-such-jq PG_PLUGINS_FILE="$WORK/with-dev.json" PG_ONBOARDING=off CLAUDE_PROJECT_DIR="$R" "$HOOK")"; rc=$?
expect_eq "no jq → still exits 0" "$rc" "0"
expect_contains "no jq + dev plugin → TOOLS line" "$out" "TOOLS: jq is not installed"
expect_absent "TOOLS line never says 'Open with'" "$out" "Open with one ⚠️ line: install jq"
out="$(echo '{}' | PG_JQ=pg-no-such-jq PG_PLUGINS_FILE="$WORK/no-dev.json" PG_ONBOARDING=off CLAUDE_PROJECT_DIR="$R" "$HOOK")"
expect_absent "no jq, dev plugin not installed → no TOOLS line" "$out" "TOOLS:"
out="$(echo '{}' | PG_JQ=pg-no-such-jq PG_PLUGINS_FILE="$WORK/nowhere.json" PG_ONBOARDING=off CLAUDE_PROJECT_DIR="$R" "$HOOK")"
expect_contains "no jq, unknown plugin list → TOOLS line" "$out" "TOOLS: jq is not installed"
out="$(echo '{}' | PG_PLUGINS_FILE="$WORK/with-dev.json" PG_ONBOARDING=off CLAUDE_PROJECT_DIR="$R" "$HOOK")"
expect_absent "jq present → no TOOLS line" "$out" "TOOLS:"
# first time on the machine: the jq line is part of the welcome (item 3b), not a second opener line
out="$(echo '{}' | PG_JQ=pg-no-such-jq PG_PLUGINS_FILE="$WORK/with-dev.json" PG_LOG_DIR="$WORK/fresh" CLAUDE_PROJECT_DIR="$R" "$HOOK")"
expect_contains "first time + no jq → item 3b in the welcome" "$out" "3b. The TOOLS line below"
out="$(echo '{}' | PG_PLUGINS_FILE="$WORK/with-dev.json" PG_LOG_DIR="$WORK/fresh2" CLAUDE_PROJECT_DIR="$R" "$HOOK")"
expect_contains "first time + jq → welcome still there" "$out" "FIRST TIME WITH GUARDIAN"
expect_absent "first time + jq → no item 3b" "$out" "3b."

# --- Node.js too old for the dev plugin (0.7.7+: 22.18+ on 22, or 24+) → TOOLS line ---
mk_node() { printf '#!/bin/sh\necho %s\n' "$2" >"$WORK/$1"; chmod +x "$WORK/$1"; }
for v in v20.19.4 v22.17.1 v23.11.0 v18.0.0 v8.17.0; do
  mk_node "node-$v" "$v"
  out="$(echo '{}' | PG_NODE="$WORK/node-$v" PG_PLUGINS_FILE="$WORK/with-dev.json" PG_ONBOARDING=off CLAUDE_PROJECT_DIR="$R" "$HOOK")"
  expect_contains "node $v + dev plugin → Node TOOLS line" "$out" "this computer's Node.js is $v (unsupported)"
done
for v in v22.18.0 v22.20.1 v24.0.0 v24.18.0 v25.1.0 v100.0.0; do
  mk_node "node-$v" "$v"
  out="$(echo '{}' | PG_NODE="$WORK/node-$v" PG_PLUGINS_FILE="$WORK/with-dev.json" PG_ONBOARDING=off CLAUDE_PROJECT_DIR="$R" "$HOOK")"
  expect_absent "node $v → no Node TOOLS line" "$out" "Node.js 22.18 or later"
done
out="$(echo '{}' | PG_NODE=pg-no-such-node PG_PLUGINS_FILE="$WORK/with-dev.json" PG_ONBOARDING=off CLAUDE_PROJECT_DIR="$R" "$HOOK")"; rc=$?
expect_eq "no node → still exits 0" "$rc" "0"
expect_contains "no node + dev plugin → TOOLS line" "$out" "TOOLS: no Node.js was found"
printf '#!/bin/sh\nprintf "v24.1.0\\r\\n"\n' >"$WORK/node-crlf"; chmod +x "$WORK/node-crlf"
out="$(echo '{}' | PG_NODE="$WORK/node-crlf" PG_PLUGINS_FILE="$WORK/with-dev.json" PG_ONBOARDING=off CLAUDE_PROJECT_DIR="$R" "$HOOK")"
expect_absent "CRLF v24 → no Node TOOLS line" "$out" "Node.js 22.18 or later"
printf '#!/bin/sh\nexec sleep 30\n' >"$WORK/node-hang"; chmod +x "$WORK/node-hang"
t0=$(date +%s)
out="$(echo '{}' | PG_NODE="$WORK/node-hang" PG_NODE_TIMEOUT=1 PG_PLUGINS_FILE="$WORK/with-dev.json" PG_ONBOARDING=off CLAUDE_PROJECT_DIR="$R" "$HOOK")"; rc=$?
t1=$(date +%s)
expect_eq "hanging node → exits 0" "$rc" "0"
if [ $((t1 - t0)) -lt 10 ]; then ok; else fail "hanging node → watchdog stops it" "$((t1 - t0)) s"; fi
expect_contains "hanging node → opener still there" "$out" "session-opener"
expect_contains "hanging node → gave no version" "$out" "gave no version"
mk_node node-junk "garbage"
out="$(echo '{}' | PG_NODE="$WORK/node-junk" PG_PLUGINS_FILE="$WORK/with-dev.json" PG_ONBOARDING=off CLAUDE_PROJECT_DIR="$R" "$HOOK")"
expect_contains "unreadable node version → TOOLS line" "$out" "gave no version"
out="$(echo '{}' | PG_NODE="$WORK/node-v20.19.4" PG_PLUGINS_FILE="$WORK/no-dev.json" PG_ONBOARDING=off CLAUDE_PROJECT_DIR="$R" "$HOOK")"
expect_absent "old node, dev plugin not installed → no TOOLS line" "$out" "TOOLS:"
out="$(echo '{}' | PG_NODE="$WORK/node-v20.19.4" PG_PLUGINS_FILE="$WORK/with-dev.json" PG_LOG_DIR="$WORK/fresh3" CLAUDE_PROJECT_DIR="$R" "$HOOK")"
expect_contains "first time + old node → item 3c in the welcome" "$out" "3c. The TOOLS line below (Node.js)"
expect_absent "first time + old node, jq present → no item 3b" "$out" "3b."
out="$(echo '{}' | PG_JQ=pg-no-such-jq PG_NODE="$WORK/node-v20.19.4" PG_PLUGINS_FILE="$WORK/with-dev.json" PG_ONBOARDING=off CLAUDE_PROJECT_DIR="$R" "$HOOK")"
expect_contains "no jq + old node → jq line" "$out" "TOOLS: jq is not installed"
expect_contains "no jq + old node → node line" "$out" "this computer's Node.js is v20.19.4 (unsupported)"

# --- plugins removed from Guardian (0.5.0) still installed → one-time notice ---
printf '{"plugins":{"matrix-qa-plugin@ono-plugin-marketplace":[{}],"ono-mobile-dev-plugin@ono-plugin-marketplace":[{}],"spec-team-toolkit@ono-plugin-marketplace":[{}]}}' >"$WORK/leftover.json"
printf '{"plugins":{"matrix-studio@ono-plugin-marketplace":[{}]}}' >"$WORK/leftover1.json"
L="$WORK/leftlogs"; mkdir -p "$L/.state"; date >"$L/.state/onboarding-offered"
out="$(echo '{}' | PG_LOG_DIR="$L" PG_PLUGINS_FILE="$WORK/leftover.json" CLAUDE_PROJECT_DIR="$R" "$HOOK")"; rc=$?
expect_eq "leftover plugins → exits 0" "$rc" "0"
expect_contains "leftover plugins → notice names them" "$out" "REMOVED PLUGINS (shown once on this computer): matrix-qa-plugin, spec-team-toolkit are still installed"
expect_absent "leftover notice never names a kept plugin" "$(printf '%s' "$out" | grep 'REMOVED PLUGINS')" "ono-mobile-dev-plugin"
out="$(echo '{}' | PG_LOG_DIR="$L" PG_PLUGINS_FILE="$WORK/leftover.json" CLAUDE_PROJECT_DIR="$R" "$HOOK")"
expect_absent "leftover notice shows only once" "$out" "REMOVED PLUGINS"
L2="$WORK/leftlogs2"; mkdir -p "$L2/.state"; date >"$L2/.state/onboarding-offered"
out="$(echo '{}' | PG_LOG_DIR="$L2" PG_PLUGINS_FILE="$WORK/leftover1.json" CLAUDE_PROJECT_DIR="$R" "$HOOK")"
expect_contains "one leftover → singular" "$out" "matrix-studio is still installed"
L3="$WORK/leftlogs3"; mkdir -p "$L3/.state"; date >"$L3/.state/onboarding-offered"
out="$(echo '{}' | PG_LOG_DIR="$L3" PG_PLUGINS_FILE="$WORK/with-dev.json" CLAUDE_PROJECT_DIR="$R" "$HOOK")"
expect_absent "no leftover → no notice" "$out" "REMOVED PLUGINS"
out="$(echo '{}' | PG_LOG_DIR="$L3" PG_PLUGINS_FILE="$WORK/nowhere.json" CLAUDE_PROJECT_DIR="$R" "$HOOK")"
expect_absent "unknown plugin list → no notice" "$out" "REMOVED PLUGINS"
L4="$WORK/leftlogs4"
out="$(echo '{}' | PG_LOG_DIR="$L4" PG_PLUGINS_FILE="$WORK/leftover.json" CLAUDE_PROJECT_DIR="$R" "$HOOK")"
expect_contains "first time → welcome" "$out" "FIRST TIME WITH GUARDIAN"
expect_absent "first time → leftover notice waits" "$out" "REMOVED PLUGINS"
out="$(echo '{}' | PG_LOG_DIR="$L4" PG_PLUGINS_FILE="$WORK/leftover.json" CLAUDE_PROJECT_DIR="$R" "$HOOK")"
expect_contains "next session → leftover notice" "$out" "REMOVED PLUGINS"
# a crashing node no longer gets a Matrix line (the plugin isn't Guardian's any more)
printf '#!/bin/sh\necho "dyld[1]: Library not loaded" >&2\nkill -ABRT $$\n' >"$WORK/node-dyld"; chmod +x "$WORK/node-dyld"
out="$(echo '{}' | PG_NODE="$WORK/node-dyld" PG_PLUGINS_FILE="$WORK/with-dev.json" PG_ONBOARDING=off CLAUDE_PROJECT_DIR="$R" "$HOOK" 2>&1)"
expect_contains "crashing node + dev plugin → dev line" "$out" "gave no version"
expect_absent "crashing node → no Matrix line" "$out" "Matrix QA"
expect_absent "crashing node → dyld noise not passed through" "$out" "dyld["

out="$(echo '{}' | CLAUDE_PLUGIN_ROOT="$WORK/nowhere" CLAUDE_PROJECT_DIR="$R" "$HOOK" 2>&1)"; rc=$?
expect_eq "hook with broken plugin root fails open" "$rc:$out" "0:"

echo
echo "session-log.sh + session-start.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
