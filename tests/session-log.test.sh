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
# No real GitHub call from the opener in tests (the REVIEWS tests below use a fake gh).
export PG_REVIEWS=off
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
# 0.7.0: dev plugin 0.8.0+ reads hook input with Node when jq is missing → no jq line
for v in 0.8.0 0.9.1 0.10.0 1.0.0; do
  printf '{"plugins":{"ono-mobile-dev-plugin@ono-plugin-marketplace":[{"scope":"user","installPath":"/x","version":"%s"}]}}' "$v" >"$WORK/dev-new.json"
  out="$(echo '{}' | PG_JQ=pg-no-such-jq PG_PLUGINS_FILE="$WORK/dev-new.json" PG_ONBOARDING=off CLAUDE_PROJECT_DIR="$R" "$HOOK")"
  expect_absent "no jq, dev plugin $v → no jq line" "$out" "TOOLS: jq is not installed"
done
printf '{"plugins":{"ono-mobile-dev-plugin@ono-plugin-marketplace":[{"scope":"user","installPath":"/x","version":"0.7.7"}]}}' >"$WORK/dev-old.json"
out="$(echo '{}' | PG_JQ=pg-no-such-jq PG_PLUGINS_FILE="$WORK/dev-old.json" PG_ONBOARDING=off CLAUDE_PROJECT_DIR="$R" "$HOOK")"
expect_contains "no jq, dev plugin 0.7.7 → jq line" "$out" "TOOLS: jq is not installed"
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
  expect_contains "node $v + dev plugin → Node TOOLS line" "$out" "this computer's Node.js $v is unsupported"
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
expect_contains "no jq + old node → node line" "$out" "this computer's Node.js v20.19.4 is unsupported"

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

# --- the jq line names the OS, so the opener gives that OS's install command ---
out="$(echo '{}' | PG_JQ=pg-no-such-jq PG_OS=MINGW64_NT-10.0-26100 PG_PLUGINS_FILE="$WORK/with-dev.json" PG_ONBOARDING=off CLAUDE_PROJECT_DIR="$R" "$HOOK")"
expect_contains "Git Bash on Windows → OS: windows" "$out" "jq is not installed on this computer (OS: windows)"
out="$(echo '{}' | PG_JQ=pg-no-such-jq PG_OS=Darwin PG_PLUGINS_FILE="$WORK/with-dev.json" PG_ONBOARDING=off CLAUDE_PROJECT_DIR="$R" "$HOOK")"
expect_contains "macOS → OS: mac" "$out" "(OS: mac)"
out="$(echo '{}' | PG_JQ=pg-no-such-jq PG_OS=Linux PG_PLUGINS_FILE="$WORK/with-dev.json" PG_ONBOARDING=off CLAUDE_PROJECT_DIR="$R" "$HOOK")"
expect_contains "Linux → OS: linux" "$out" "(OS: linux)"

# --- an inspector older than 0.12.0 without Bun → "update the inspector", only when it has something to do here ---
mkdir -p "$WORK/insp-old"
printf '{"plugins":{"ono-project-inspector@ono-plugin-marketplace":[{"scope":"user","installPath":"%s","version":"0.11.3"}]}}' "$WORK/insp-old" >"$WORK/with-insp.json"
OLDLINE="TOOLS: the installed Ono Project Inspector is 0.11.3, which still runs on Bun, and Bun is not installed on this computer"
out="$(echo '{}' | PG_BUN=pg-no-such-bun PG_OS=windows PG_PLUGINS_FILE="$WORK/with-insp.json" PG_ONBOARDING=off CLAUDE_PROJECT_DIR="$R" "$HOOK")"
expect_contains "old inspector, no Bun + not inspected → update line" "$out" "$OLDLINE (OS: windows)"
expect_contains "…the fix is the update, not Bun" "$out" "never suggest installing Bun"
expect_absent "…no Bun install command anywhere" "$out" "bun.sh"
out="$(echo '{}' | PG_NODE="$WORK/node-v20.19.4" PG_BUN=pg-no-such-bun PG_PLUGINS_FILE="$WORK/with-insp.json" PG_ONBOARDING=off CLAUDE_PROJECT_DIR="$R" "$HOOK")"
expect_absent "old inspector only + old node → no Node line (it runs on Bun)" "$out" "Node.js 22.18 or later"
out="$(echo '{}' | PG_BUN=pg-no-such-bun PG_PLUGINS_FILE="$WORK/with-dev.json" PG_ONBOARDING=off CLAUDE_PROJECT_DIR="$R" "$HOOK")"
expect_absent "no Bun, inspector not installed → no Bun line" "$out" "still runs on Bun"
printf '#!/bin/sh\necho 1.2.0\n' >"$WORK/bun"; chmod +x "$WORK/bun"
out="$(echo '{}' | PG_BUN="$WORK/bun" PG_PLUGINS_FILE="$WORK/with-insp.json" PG_ONBOARDING=off CLAUDE_PROJECT_DIR="$R" "$HOOK")"
expect_absent "Bun present → no Bun line" "$out" "still runs on Bun"

# --- Inspector 0.12.0+: Node.js only — no Bun line ever; its own preflight decides the Node line ---
mkdir -p "$WORK/insp-new/scripts"; : >"$WORK/insp-new/scripts/node-preflight.mjs"
printf '{"plugins":{"ono-project-inspector@ono-plugin-marketplace":[{"scope":"user","installPath":"%s","version":"0.12.0"}]}}' "$WORK/insp-new" >"$WORK/with-insp-new.json"
printf '{"plugins":{"ono-mobile-dev-plugin@ono-plugin-marketplace":[{}],"ono-project-inspector@ono-plugin-marketplace":[{"scope":"user","installPath":"%s","version":"0.12.0"}]}}' "$WORK/insp-new" >"$WORK/with-both.json"
# fake node: `-v` answers $V; with a script it prints $PF and exits $RC (the preflight contract)
mk_pf() { printf '#!/bin/sh\n[ "$1" = -v ] && { echo %s; exit 0; }\nprintf '"'"'%%s\\n'"'"' '"'"'%s'"'"'\nexit %s\n' "$2" "$3" "$4" >"$WORK/$1"; chmod +x "$WORK/$1"; }
mk_pf pf-ok v20.0.0 '{"supported":true,"version":"24.1.0","execPath":"/n","required":"r","message":"ok"}' 0
mk_pf pf-bad v24.0.0 '{"supported":false,"version":"20.19.4","execPath":"C:\\Program Files\\nodejs\\node.exe","required":"r","message":"Unsupported Node.js v20.19.4 (C:\\Program Files\\nodejs\\node.exe). Check it with `! node -v`."}' 1
mk_pf pf-crash v24.0.0 '' 3
mk_pf pf-nojson v24.0.0 'hello' 0
mk_pf pf-lie v24.0.0 '{"supported":false,"version":"20.1.0","execPath":"/n","required":"r","message":"m"}' 0
out="$(echo '{}' | PG_NODE="$WORK/pf-ok" PG_BUN=pg-no-such-bun PG_PLUGINS_FILE="$WORK/with-insp-new.json" PG_ONBOARDING=off CLAUDE_PROJECT_DIR="$R" "$HOOK")"
expect_absent "0.12.0, no Bun, not inspected → no Bun line" "$out" "Bun"
expect_absent "0.12.0 + preflight ok (node -v would say v20) → no Node line: the preflight decides" "$out" "TOOLS:"
out="$(echo '{}' | PG_NODE="$WORK/pf-bad" PG_OS=windows PG_PLUGINS_FILE="$WORK/with-insp-new.json" PG_ONBOARDING=off CLAUDE_PROJECT_DIR="$R" "$HOOK")"
expect_contains "0.12.0 + preflight unsupported (node -v would say v24) → Node line with its version" "$out" "TOOLS: this computer's Node.js v20.19.4 is unsupported (OS: windows). The Ono Project Inspector (0.12.0+) needs Node.js"
expect_contains "…one plugin → its commands" "$out" "on anything else its commands stop"
expect_absent "…inspector only → no dev-plugin clause" "$out" "Bug Fix Cycle"
out="$(echo '{}' | PG_NODE="$WORK/pf-bad" PG_PLUGINS_FILE="$WORK/with-both.json" PG_ONBOARDING=off CLAUDE_PROJECT_DIR="$R" "$HOOK")"
expect_contains "dev plugin + 0.12.0 → one line naming both" "$out" "The Ono dev plugin (0.7.7+) and the Ono Project Inspector (0.12.0+) need Node.js"
expect_eq "…exactly one Node line (no duplicate)" "$(printf '%s\n' "$out" | grep -c 'Node.js 22.18 or later')" "1"
expect_contains "…their commands" "$out" "on anything else their commands stop"
for b in pf-crash pf-nojson pf-lie; do
  out="$(echo '{}' | PG_NODE="$WORK/$b" PG_PLUGINS_FILE="$WORK/with-both.json" PG_ONBOARDING=off CLAUDE_PROJECT_DIR="$R" "$HOOK")"
  expect_contains "preflight $b → never supported: gave-no-version line" "$out" "TOOLS: Node.js gave no version"
done
out="$(echo '{}' | PG_NODE=pg-no-such-node PG_PLUGINS_FILE="$WORK/with-insp-new.json" PG_ONBOARDING=off CLAUDE_PROJECT_DIR="$R" "$HOOK")"
expect_contains "0.12.0 + no node → no-Node line" "$out" "TOOLS: no Node.js was found"
out="$(echo '{}' | PG_NODE="$WORK/pf-bad" PG_BUN=pg-no-such-bun PG_PLUGINS_FILE="$WORK/no-such-list.json" PG_ONBOARDING=off CLAUDE_PROJECT_DIR="$R" "$HOOK")"
expect_absent "no plugins list → no inspector line (version unknown)" "$out" "still runs on Bun"
# node-check.sh on its own: the preflight's message comes back unescaped (a Windows path)
nc="$(PG_NODE="$WORK/pf-bad" "$ROOT/scripts/node-check.sh" "$WORK/insp-new/scripts/node-preflight.mjs")"
expect_eq "node-check: unsupported + version" "$(printf '%s' "$nc" | cut -f1-2)" "unsupported	v20.19.4"
expect_eq "node-check: message unescaped" "$(printf '%s' "$nc" | cut -f3)" 'Unsupported Node.js v20.19.4 (C:\Program Files\nodejs\node.exe). Check it with `! node -v`.'
expect_eq "node-check: ok" "$(PG_NODE="$WORK/pf-ok" "$ROOT/scripts/node-check.sh" x)" "ok	v24.1.0"
expect_eq "node-check: no preflight → node -v" "$(PG_NODE="$WORK/pf-ok" "$ROOT/scripts/node-check.sh")" "unsupported	v20.0.0	"
expect_eq "ono-plugin: 0.12.0 → node + preflight" "$(PG_PLUGINS_FILE="$WORK/with-insp-new.json" "$ROOT/scripts/ono-plugin.sh" inspector-runtime)" "node $WORK/insp-new/scripts/node-preflight.mjs"
expect_eq "ono-plugin: 0.11.3 → bun" "$(PG_PLUGINS_FILE="$WORK/with-insp.json" "$ROOT/scripts/ono-plugin.sh" inspector-runtime)" "bun 0.11.3"
PG_PLUGINS_FILE="$WORK/with-dev.json" "$ROOT/scripts/ono-plugin.sh" inspector-runtime >/dev/null; expect_eq "ono-plugin: not installed → exit 1" "$?" "1"
# inspector-runtime: version strings when there's no preflight file
for vv in "0.12:unknown" "0.12.0:unknown" "1.0.0:unknown" "unknown:unknown" "0.9.5:bun 0.9.5" "0.11.3:bun 0.11.3"; do
  printf '{"plugins":{"ono-project-inspector@m":[{"scope":"user","installPath":"%s","version":"%s"}]}}' "$WORK/insp-old" "${vv%%:*}" >"$WORK/v.json"
  expect_eq "ono-plugin: version ${vv%%:*} → ${vv#*:}" "$(PG_PLUGINS_FILE="$WORK/v.json" "$ROOT/scripts/ono-plugin.sh" inspector-runtime)" "${vv#*:}"
done
# another project's install doesn't count here; this project's beats the user one
printf '{"plugins":{"ono-project-inspector@m":[{"scope":"project","projectPath":"/elsewhere","installPath":"%s","version":"0.11.3"}]}}' "$WORK/insp-old" >"$WORK/foreign.json"
(cd "$R" && PG_PLUGINS_FILE="$WORK/foreign.json" "$ROOT/scripts/ono-plugin.sh" inspector-runtime >/dev/null); expect_eq "ono-plugin: only another project's install → not installed (exit 1)" "$?" "1"
out="$(echo '{}' | PG_BUN=pg-no-such-bun PG_PLUGINS_FILE="$WORK/foreign.json" PG_ONBOARDING=off CLAUDE_PROJECT_DIR="$R" "$HOOK")"
expect_absent "another project's old inspector → no update line here" "$out" "still runs on Bun"
printf '{"plugins":{"ono-project-inspector@m":[{"scope":"user","installPath":"%s","version":"0.11.3"},{"scope":"project","projectPath":"%s","installPath":"%s","version":"0.12.0"}]}}' "$WORK/insp-old" "$R" "$WORK/insp-new" >"$WORK/mine.json"
expect_eq "ono-plugin: this project's install beats the user one" "$(CLAUDE_PROJECT_DIR="$R" PG_PLUGINS_FILE="$WORK/mine.json" "$ROOT/scripts/ono-plugin.sh" inspector-runtime)" "node $WORK/insp-new/scripts/node-preflight.mjs"
# a Windows installPath (JSON-escaped backslashes) comes back as a Windows path
printf '{"plugins":{"ono-project-inspector@m":[{"scope":"user","installPath":"C:\\\\Users\\\\a b\\\\.claude\\\\insp","version":"0.11.3"}]}}' >"$WORK/win.json"
expect_eq "ono-plugin: Windows installPath unescaped" "$(PG_PLUGINS_FILE="$WORK/win.json" "$ROOT/scripts/ono-plugin.sh" path ono-project-inspector)" 'C:\Users\a b\.claude\insp'
# turned off in the user settings → no inspector line at all at session start
mkdir -p "$WORK/cfg-off"; printf '{"enabledPlugins":{"ono-project-inspector@ono-plugin-marketplace":false}}' >"$WORK/cfg-off/settings.json"
out="$(echo '{}' | PG_CLAUDE_DIR="$WORK/cfg-off" PG_NODE="$WORK/pf-bad" PG_PLUGINS_FILE="$WORK/with-insp-new.json" PG_ONBOARDING=off CLAUDE_PROJECT_DIR="$R" "$HOOK")"
expect_absent "0.12.0 turned off + bad node → no Node line" "$out" "Ono Project Inspector (0.12.0+)"
out="$(echo '{}' | PG_CLAUDE_DIR="$WORK/cfg-off" PG_BUN=pg-no-such-bun PG_PLUGINS_FILE="$WORK/with-insp.json" PG_ONBOARDING=off CLAUDE_PROJECT_DIR="$R" "$HOOK")"
expect_absent "0.11.3 turned off, no Bun → no update line" "$out" "still runs on Bun"
# a hanging preflight → stopped by the watchdog, never supported
printf '#!/bin/sh\nexec sleep 30\n' >"$WORK/pf-hang"; chmod +x "$WORK/pf-hang"
t0=$(date +%s); nc="$(PG_NODE="$WORK/pf-hang" PG_NODE_TIMEOUT=1 "$ROOT/scripts/node-check.sh" x)"; t1=$(date +%s)
expect_eq "node-check: hanging preflight → unreadable" "${nc%%	*}" "unreadable"
if [ $((t1 - t0)) -lt 10 ]; then ok; else fail "hanging preflight → watchdog" "$((t1 - t0)) s"; fi
# first time on the computer: inspector-only Node line → item 3c; old inspector → item 3d
out="$(echo '{}' | PG_NODE="$WORK/pf-bad" PG_PLUGINS_FILE="$WORK/with-insp-new.json" PG_LOG_DIR="$WORK/fresh-i" CLAUDE_PROJECT_DIR="$R" "$HOOK")"
expect_contains "first time + inspector-only Node line → item 3c" "$out" "3c. The TOOLS line below (Node.js)"
out="$(echo '{}' | PG_BUN=pg-no-such-bun PG_PLUGINS_FILE="$WORK/with-insp.json" PG_LOG_DIR="$WORK/fresh-o" CLAUDE_PROJECT_DIR="$R" "$HOOK")"
expect_contains "first time + old inspector → item 3d" "$out" "3d. If a TOOLS line below is about updating the Ono Project Inspector"
expect_contains "…and the line itself" "$out" "still runs on Bun"

# an inspected repo: no manifest → one line a day; with the manifest → nothing; no Bun line unless needed
g init "$WORK/insp"; I="$WORK/insp"
mkdir -p "$I/docs/project" "$I/.ono"
printf '# AUDIT.md\n' >"$I/AUDIT.md"; echo x >"$I/CLAUDE.md"
for f in overview components patterns integrations capabilities; do echo x >"$I/docs/project/$f.md"; done
echo '{}' >"$I/.ono/state.json"; g -C "$I" add -A; g -C "$I" commit -m inspected; g -C "$I" checkout -b work
out="$(echo '{}' | PG_LOG_DIR="$WORK/mlog" PG_BUN=pg-no-such-bun PG_OS=windows PG_PLUGINS_FILE="$WORK/with-insp.json" PG_ONBOARDING=off CLAUDE_PROJECT_DIR="$I" "$HOOK")"
expect_contains "inspected, no manifest → INSPECT manifest line" "$out" ".ono/repo-knowledge.json is missing"
expect_contains "no manifest + old inspector, no Bun → update line too" "$out" "$OLDLINE"
out="$(echo '{}' | PG_LOG_DIR="$WORK/mlog" PG_BUN=pg-no-such-bun PG_PLUGINS_FILE="$WORK/with-insp.json" PG_ONBOARDING=off CLAUDE_PROJECT_DIR="$I" "$HOOK")"
expect_absent "manifest line only once a day" "$out" "repo-knowledge.json is missing"
expect_absent "…and then no Bun line either" "$out" "still runs on Bun"
echo '{}' >"$I/.ono/repo-knowledge.json"
out="$(echo '{}' | PG_LOG_DIR="$WORK/mlog2" PG_BUN=pg-no-such-bun PG_PLUGINS_FILE="$WORK/with-insp.json" PG_ONBOARDING=off CLAUDE_PROJECT_DIR="$I" "$HOOK")"
expect_absent "manifest present → no line" "$out" "repo-knowledge.json is missing"
expect_absent "fully inspected + no Bun → no Bun line (nothing to run)" "$out" "still runs on Bun"

# --- PRs waiting for review → REVIEWS block (fake gh; the real call is tested in review-requests.test.sh) ---
g -C "$R" remote set-url origin "https://github.com/OnOAppsDev/My-App.git"
printf '#!/bin/sh\nprintf "OnOAppsDev/My-App#12\\tdana\\tFix login crash\\thttps://github.com/OnOAppsDev/My-App/pull/12\\nOnOAppsDev/other#3\\tavi\\tNew splash\\thttps://github.com/OnOAppsDev/other/pull/3\\n"\n' >"$WORK/gh-two"; chmod +x "$WORK/gh-two"
out="$(echo '{}' | PG_REVIEWS= PG_GH="$WORK/gh-two" PG_PLUGINS_FILE="$WORK/with-dev.json" PG_ONBOARDING=off CLAUDE_PROJECT_DIR="$R" "$HOOK")"
expect_contains "reviews → REVIEWS header" "$out" "REVIEWS: open pull requests waiting for your review"
expect_contains "reviews → this repo's PR marked here" "$out" "- here · OnOAppsDev/My-App#12 · by dana · Fix login crash · https://github.com/OnOAppsDev/My-App/pull/12"
expect_contains "reviews → other repo's PR marked other" "$out" "- other · OnOAppsDev/other#3 · by avi"
printf '#!/bin/sh\nexit 0\n' >"$WORK/gh-none"; chmod +x "$WORK/gh-none"
out="$(echo '{}' | PG_REVIEWS= PG_GH="$WORK/gh-none" PG_PLUGINS_FILE="$WORK/with-dev.json" PG_ONBOARDING=off CLAUDE_PROJECT_DIR="$R" "$HOOK")"
expect_absent "no PRs waiting → no REVIEWS block" "$out" "REVIEWS:"
out="$(echo '{}' | PG_REVIEWS=off PG_GH="$WORK/gh-two" PG_PLUGINS_FILE="$WORK/with-dev.json" PG_ONBOARDING=off CLAUDE_PROJECT_DIR="$R" "$HOOK")"
expect_absent "PG_REVIEWS=off → no REVIEWS block" "$out" "REVIEWS:"

# a gh that ignores the watchdog's TERM must not hold up the opener; no temp file left behind
printf '#!/bin/sh\ntrap "" TERM\nsleep 8\n' >"$WORK/gh-stubborn"; chmod +x "$WORK/gh-stubborn"
mkdir -p "$WORK/tmp1"
start=$(date +%s)
out="$(echo '{}' | TMPDIR="$WORK/tmp1" PG_REVIEWS= PG_REVIEWS_TIMEOUT=1 PG_REVIEWS_WAIT=15 PG_GH="$WORK/gh-stubborn" PG_PLUGINS_FILE="$WORK/with-dev.json" PG_ONBOARDING=off CLAUDE_PROJECT_DIR="$R" "$HOOK")"
took=$(( $(date +%s) - start ))
[ "$took" -le 5 ] && ok || fail "stubborn gh → hook still bounded (took ${took}s)"
expect_contains "stubborn gh → the opener is still there" "$out" "Git report"
sleep 1
expect_eq "no pg-reviews temp files left" "$(ls "$WORK/tmp1" | grep -c pg-reviews)" "0"

# the manifest line only when the inspector is installed; Node line names the OS
rm -rf "$WORK/mlog3"
out="$(echo '{}' | PG_LOG_DIR="$WORK/mlog3" PG_PLUGINS_FILE="$WORK/with-dev.json" PG_ONBOARDING=off CLAUDE_PROJECT_DIR="$I" "$HOOK")"
rm -f "$I/.ono/repo-knowledge.json"
out="$(echo '{}' | PG_LOG_DIR="$WORK/mlog3" PG_PLUGINS_FILE="$WORK/with-dev.json" PG_ONBOARDING=off CLAUDE_PROJECT_DIR="$I" "$HOOK")"
expect_absent "no manifest, inspector not installed → no manifest line" "$out" "repo-knowledge.json is missing"
out="$(echo '{}' | PG_OS=windows PG_NODE="$WORK/node-v20.19.4" PG_PLUGINS_FILE="$WORK/with-dev.json" PG_ONBOARDING=off CLAUDE_PROJECT_DIR="$R" "$HOOK")"
expect_contains "Node line names the OS" "$out" "is unsupported (OS: windows)"

# project docs behind the code → INSPECT DOCS line, once a day, only with the inspector installed
echo '{}' >"$I/.ono/repo-knowledge.json"
g -C "$I" switch main
KH="$(git -C "$I" rev-parse HEAD)"
printf '{\n  "repository": {\n    "knowledgeHead": "%s"\n  },\n  "inspection": {\n    "stage3Complete": true\n  }\n}\n' "$KH" >"$I/.ono/state.json"
g -C "$I" add -A; g -C "$I" commit -m state
g -C "$I" switch work; echo '{"y":1}' >"$I/package.json"; g -C "$I" add -A; g -C "$I" commit -m "own change"
out="$(echo '{}' | PG_LOG_DIR="$WORK/dlog0" PG_PLUGINS_FILE="$WORK/with-insp.json" PG_ONBOARDING=off CLAUDE_PROJECT_DIR="$I" "$HOOK")"
expect_absent "a change on the employee's own branch → no INSPECT DOCS line" "$out" "INSPECT DOCS"
g -C "$I" switch main; echo '{"x":1}' >"$I/package.json"; g -C "$I" add -A; g -C "$I" commit -m deps; g -C "$I" switch work
out="$(echo '{}' | PG_LOG_DIR="$WORK/dlog" PG_PLUGINS_FILE="$WORK/with-insp.json" PG_ONBOARDING=off CLAUDE_PROJECT_DIR="$I" "$HOOK")"
expect_contains "docs behind the code → INSPECT DOCS line" "$out" "INSPECT DOCS: the project docs (CLAUDE.md, docs/project/*) on the central branch are behind its code — files=1"
expect_contains "…naming the signal" "$out" "package.json"
out="$(echo '{}' | PG_LOG_DIR="$WORK/dlog" PG_PLUGINS_FILE="$WORK/with-insp.json" PG_ONBOARDING=off CLAUDE_PROJECT_DIR="$I" "$HOOK")"
expect_absent "INSPECT DOCS only once a day" "$out" "INSPECT DOCS"
out="$(echo '{}' | PG_LOG_DIR="$WORK/dlog2" PG_PLUGINS_FILE="$WORK/with-dev.json" PG_ONBOARDING=off CLAUDE_PROJECT_DIR="$I" "$HOOK")"
expect_absent "inspector not installed → no INSPECT DOCS line" "$out" "INSPECT DOCS"

# the Windows ticket (2026-11-23): inspection made with an older model + no Bun → refresh line AND Bun line
g -C "$I" switch work; rm -f "$I/docs/project/capabilities.md"
out="$(echo '{}' | PG_LOG_DIR="$WORK/rlog" PG_BUN=pg-no-such-bun PG_OS=MINGW64_NT-10.0-26100 PG_PLUGINS_FILE="$WORK/with-insp.json" PG_ONBOARDING=off CLAUDE_PROJECT_DIR="$I" "$HOOK")"
expect_contains "older model → refresh line" "$out" "INSPECT: complete, but made with an older inspector knowledge model"
expect_contains "older model + old inspector, no Bun → update line (OS: windows)" "$out" "$OLDLINE (OS: windows)"

# time budget: past it, the optional checks are skipped and named; the git report and TOOLS lines stay
out="$(echo '{}' | PG_HOOK_BUDGET=0 PG_LOG_DIR="$WORK/blog" PG_BUN=pg-no-such-bun PG_OS=windows PG_PLUGINS_FILE="$WORK/with-insp.json" PG_ONBOARDING=off CLAUDE_PROJECT_DIR="$I" "$HOOK")"
expect_contains "budget spent → git report still there" "$out" "Git report"
expect_contains "budget spent → inspector update line still there" "$out" "$OLDLINE"
expect_contains "budget spent → SKIPPED line" "$out" "SKIPPED (this computer is slow"
expect_contains "…naming the branch search" "$out" "inspection on other branches"
expect_contains "…and the resume list" "$out" "unfinished work in the Ono plugins' documents"
g -C "$I" checkout -q -- docs/project/capabilities.md
out="$(echo '{}' | PG_HOOK_BUDGET=0 PG_LOG_DIR="$WORK/blog2" PG_PLUGINS_FILE="$WORK/with-insp.json" PG_ONBOARDING=off CLAUDE_PROJECT_DIR="$I" "$HOOK")"
expect_contains "budget spent → docs freshness skipped" "$out" "project-docs freshness"
expect_absent "…and no INSPECT DOCS line" "$out" "INSPECT DOCS"
out="$(echo '{}' | PG_HOOK_BUDGET=0 PG_REVIEWS= PG_REVIEWS_TIMEOUT=5 PG_GH="$WORK/gh-stubborn" PG_PLUGINS_FILE="$WORK/with-dev.json" PG_ONBOARDING=off CLAUDE_PROJECT_DIR="$R" "$HOOK")"
expect_contains "budget spent → a slow review lookup is dropped and named" "$out" "PRs waiting for your review"
out="$(echo '{}' | SECONDS=50 PG_LOG_DIR="$WORK/blog5" PG_PLUGINS_FILE="$WORK/with-insp.json" PG_ONBOARDING=off CLAUDE_PROJECT_DIR="$I" "$HOOK")"
expect_absent "an inherited SECONDS doesn't spend the budget" "$out" "SKIPPED"
out="$(echo '{}' | PG_HOOK_BUDGET=abc PG_LOG_DIR="$WORK/blog3" PG_PLUGINS_FILE="$WORK/with-insp.json" PG_ONBOARDING=off CLAUDE_PROJECT_DIR="$I" "$HOOK")"
expect_absent "bad budget value → default, nothing skipped" "$out" "SKIPPED"
out="$(echo '{}' | PG_LOG_DIR="$WORK/blog4" PG_PLUGINS_FILE="$WORK/with-insp.json" PG_ONBOARDING=off CLAUDE_PROJECT_DIR="$I" "$HOOK")"
expect_absent "normal run → no SKIPPED line" "$out" "SKIPPED"

echo
echo "session-log.sh + session-start.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
