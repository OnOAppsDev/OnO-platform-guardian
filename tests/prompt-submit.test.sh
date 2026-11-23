#!/usr/bin/env bash
# Tests for hooks/prompt-submit.sh (routing reminder + session-length signal).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../hooks/prompt-submit.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/pg-prompt.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
export PG_LOG_DIR="$WORK/logs" PG_CLOSEOUT_TOKENS=100000 PG_CLOSEOUT_STEP=40000 PG_ROUTE_REMINDER=off

PASS=0 FAIL=0
expect() { # expect <name> <should-fire:yes|no> <output>
  local fired=no; case "$3" in *"[platform-guardian]"*) fired=yes ;; esac
  if [ "$fired" = "$2" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL $1 (fired=$fired)"; fi
}

T="$WORK/t.jsonl"
turn() { # turn <input> <cache_create> <cache_read>
  printf '{"type":"assistant","message":{"usage":{"input_tokens":%s,"cache_creation_input_tokens":%s,"cache_read_input_tokens":%s,"output_tokens":10,"server_tool_use":{"web_search_requests":0}}}}\n' "$1" "$2" "$3" >>"$T"
}
hook() { printf '{"session_id":"%s","transcript_path":"%s","prompt":"hi"}' "${2:-s1}" "$1" | "$HOOK"; }

: >"$T"
expect "empty transcript" no "$(hook "$T")"
expect "missing transcript" no "$(hook "$WORK/nope.jsonl")"
expect "garbage payload" no "$(echo 'not json' | "$HOOK")"

turn 5 100 50000
expect "below threshold" no "$(hook "$T")"

turn 2 300 99800
out="$(hook "$T")"
expect "crosses threshold (sums all three fields)" yes "$out"
for want in '`/clear`' 'close the session' '`platform-guardian:session-closer`' 'Show this suggestion once' "don't suggest closing now — closing mid-step makes the next session redo it"; do
  case "$out" in *"$want"*) PASS=$((PASS + 1)) ;; *) FAIL=$((FAIL + 1)); echo "FAIL message missing: $want" ;; esac
done
err="$(printf '{"session_id":"s9","transcript_path":"%s"}' "$T" | "$HOOK" 2>&1 >/dev/null)"
[ -z "$err" ] && PASS=$((PASS + 1)) || { FAIL=$((FAIL + 1)); echo "FAIL hook wrote to stderr: $err"; }
case "$out" in *"about 100k tokens"*) PASS=$((PASS + 1)) ;; *) FAIL=$((FAIL + 1)); echo "FAIL token count in message: $out" ;; esac
expect "same band stays quiet" no "$(hook "$T")"

turn 2 0 130000
expect "still same band (<140k)" no "$(hook "$T")"
turn 2 0 141000
expect "next band fires again" yes "$(hook "$T")"

expect "separate session has its own state" yes "$(hook "$T" s2)"

turn 2 0 20000   # after a compact, context drops
expect "after compaction stays quiet" no "$(hook "$T" s3)"

out="$(printf '{"session_id":"s4","transcript_path":"%s"}' "$T" | PG_CLOSEOUT_TOKENS=abc "$HOOK")"; rc=$?
expect "bad threshold config fails open" no "$out"
[ "$rc" -eq 0 ] && PASS=$((PASS + 1)) || { FAIL=$((FAIL + 1)); echo "FAIL exit code $rc"; }

# ---- routing reminder (0.5.1) ----
unset PG_ROUTE_REMINDER
R="$WORK/r.jsonl"
rhook() { # rhook <transcript> <prompt>
  printf '{"session_id":"r1","transcript_path":"%s","hook_event_name":"UserPromptSubmit","prompt":"%s"}' "$1" "$2" | "$HOOK"
}
rexpect() { # rexpect <name> <yes|no> <output>   — the full note (session not routed yet)
  local fired=no; case "$3" in *"[platform-guardian] Routing: this session hasn't been routed"*) fired=yes ;; esac
  if [ "$fired" = "$2" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL routing: $1 (fired=$fired)"; fi
}
sexpect() { # sexpect <name> <yes|no> <output>   — the short note (already routed: a NEW task is routed too)
  local fired=no; case "$3" in *"[platform-guardian] Routing: new work — "*) fired=yes ;; esac
  if [ "$fired" = "$2" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL short routing note: $1 (fired=$fired)"; fi
}
opener='{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"Skill","input":{"skill":"platform-guardian:session-opener"}}]}}'
printf '%s\n' "$opener" >"$R"
out="$(rhook "$R" "pausing a linear channel with Iris ads lands on the wrong position")"
rexpect "task after the opener, not routed" yes "$out"
for want in '`platform-guardian:work-router`' 'before you read code, investigate or edit anything' "doesn't skip this" "don't ask again"; do
  case "$out" in *"$want"*) PASS=$((PASS + 1)) ;; *) FAIL=$((FAIL + 1)); echo "FAIL routing message missing: $want" ;; esac
done
rexpect "first message, transcript not written yet" yes "$(rhook "$WORK/none.jsonl" "Morning")"
# 0.6.1: Ono commands come first — on both notes, on the very first message too (bug report 2026-11-22),
# only where the dev plugin is installed (unknown plugins list → assume it is)
printf '{"plugins":{"ono-mobile-dev-plugin@ono-plugin-marketplace":[{"version":"0.7.7"}]}}' >"$WORK/plugins-dev.json"
printf '{"plugins":{"ono-plugin-qa@ono-plugin-marketplace":[{"version":"0.11.0"}]}}' >"$WORK/plugins-qa.json"
printf '%s\n%s\n' "$opener" '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t2","name":"Skill","input":{"skill":"platform-guardian:work-router"}}]}}' >"$WORK/p.jsonl"
for out in "$(PG_PLUGINS_FILE="$WORK/plugins-dev.json" rhook "$WORK/none.jsonl" "code review linear_ads into linear_ads_develop")" \
           "$(PG_PLUGINS_FILE="$WORK/plugins-dev.json" rhook "$WORK/p.jsonl" "which skill did you use for the review?")" \
           "$(PG_PLUGINS_FILE="$WORK/nope.json" rhook "$WORK/none.jsonl" "review my changes")"; do
  for want in 'Ono commands come first' '`/ono-mobile-dev-plugin:review-code`' "a teammate's PR is \`/ono-mobile-dev-plugin:review-pr" '`/ono-mobile-dev-plugin:pre-pr`' 'Skills from outside the Ono plugins with the same job' '`code-review`' 'name the Ono command' 'answer honestly' "or as the running Ono step's next command" "doesn't fit this repo"; do
    case "$out" in *"$want"*) PASS=$((PASS + 1)) ;; *) FAIL=$((FAIL + 1)); echo "FAIL precedence line missing: $want" ;; esac
  done
done
out="$(PG_PLUGINS_FILE="$WORK/plugins-qa.json" rhook "$WORK/none.jsonl" "review my changes")"
rexpect "QA-only machine still gets the routing note" yes "$out"
case "$out" in *"come first"*) FAIL=$((FAIL + 1)); echo "FAIL precedence line without the dev plugin" ;; *) PASS=$((PASS + 1)) ;; esac
case "$(printf '{"session_id":"r1","transcript_path":"%s","prompt":"fix it"}' "$R" | PG_ROUTE_REMINDER=off "$HOOK")" in *"come first"*) FAIL=$((FAIL + 1)); echo "FAIL precedence line shown with reminder off" ;; *) PASS=$((PASS + 1)) ;; esac
rexpect "slash command gets no note" no "$(rhook "$R" "/ono-mobile-dev-plugin:analyze-bug wrong position")"
rexpect "built-in command gets no note" no "$(rhook "$R" "/clear")"
rexpect "empty prompt gets no note" no "$(printf '{"session_id":"r1","transcript_path":"%s"}' "$R" | "$HOOK")"
rexpect "user_prompt field also read" yes "$(printf '{"session_id":"r1","transcript_path":"%s","user_prompt":"fix the login crash"}' "$R" | "$HOOK")"
rexpect "turned off" no "$(printf '{"session_id":"r1","transcript_path":"%s","prompt":"fix it"}' "$R" | PG_ROUTE_REMINDER=off "$HOOK")"

routed_by() { # routed_by <name> <transcript line>
  printf '%s\n%s\n' "$opener" "$2" >"$R"
  out="$(rhook "$R" "and now the next bug")"
  rexpect "routed: $1" no "$out"
  sexpect "routed, short note: $1" yes "$out"
}
routed_by "work-router skill" '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t2","name":"Skill","input":{"skill":"platform-guardian:work-router"}}]}}'
routed_by "work-router skill, short name" '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t2","name":"Skill","input":{"skill":"work-router"}}]}}'
routed_by "dev plugin pre-pr (0.8.0)" '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t2","name":"Skill","input":{"skill":"ono-mobile-dev-plugin:pre-pr","args":"bug:X-1"}}]}}'
routed_by "dev plugin review-pr typed" '{"type":"user","message":{"role":"user","content":"<command-name>/ono-mobile-dev-plugin:review-pr</command-name>"}}'
# Guardian's own pre-PR skill is gone (0.7.0): a stale name doesn't count as routed
printf '%s\n%s\n' "$opener" '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t2","name":"Skill","input":{"skill":"platform-guardian:pre-pr"}}]}}' >"$R"
rexpect "old platform-guardian:pre-pr no longer routes" yes "$(rhook "$R" "and now the next bug")"
routed_by "Ono plugin skill started by Claude" '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t2","name":"Skill","input":{"skill":"ono-mobile-dev-plugin:analyze-bug","args":"x"}}]}}'
routed_by "Ono command typed (full name)" '{"type":"user","message":{"role":"user","content":"<command-message>analyze-bug</command-message>\n<command-name>/ono-mobile-dev-plugin:analyze-bug</command-name>"}}'
routed_by "Ono command typed (short form in routes.json)" '{"type":"user","message":{"role":"user","content":"<command-name>/analyze-bug</command-name>"}}'

routed_by "skill started without plugin prefix (short form)" '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t2","name":"Skill","input":{"skill":"analyze-bug"}}]}}'
routed_by "SlashCommand tool" '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t2","name":"SlashCommand","input":{"command":"/ono-mobile-dev-plugin:analyze-bug x"}}]}}'
routed_by "typed command, real line order (name first)" '{"type":"user","message":{"role":"user","content":"<command-name>/ono-plugin-qa:qa-plan</command-name>\n<command-message>qa-plan</command-message>"}}'

not_routed_by() {
  printf '%s\n%s\n' "$opener" "$2" >"$R"
  out="$(rhook "$R" "fix the crash")"
  rexpect "still not routed: $1" yes "$out"
  sexpect "not routed, no short note: $1" no "$out"
}
not_routed_by "session-closer skill" '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t2","name":"Skill","input":{"skill":"platform-guardian:session-closer"}}]}}'
not_routed_by "report-bug skill" '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t2","name":"Skill","input":{"skill":"platform-guardian:report-bug"}}]}}'
not_routed_by "built-in /clear typed" '{"type":"user","message":{"role":"user","content":"<command-name>/clear</command-name>"}}'
not_routed_by "unknown short command" '{"type":"user","message":{"role":"user","content":"<command-name>/my-own-thing</command-name>"}}'
not_routed_by "work-router only mentioned in text" '{"type":"assistant","message":{"content":[{"type":"text","text":"I will hand over to platform-guardian:work-router"}]}}'

not_routed_by "tool result quoting a typed command" '{"type":"user","message":{"role":"user","content":[{"tool_use_id":"t3","type":"tool_result","content":"x\n<command-name>/ono-mobile-dev-plugin:analyze-bug</command-name>"}]}}'
not_routed_by "tool result quoting a skill call" '{"type":"user","message":{"role":"user","content":[{"tool_use_id":"t3","type":"tool_result","content":"\"name\":\"Skill\",\"input\":{\"skill\":\"platform-guardian:work-router\"}"}]}}'

printf '%s\n' "$opener" >"$R"
rexpect "message starting with a pasted path" yes "$(rhook "$R" "/Users/raz/app/crash.log shows a crash on launch")"
rexpect "path-like single word" yes "$(rhook "$R" "/tmp/x.log")"
nogit="$WORK/plain"; mkdir -p "$nogit"
rexpect "outside a git repo" no "$(printf '{"session_id":"r1","transcript_path":"%s","cwd":"%s","prompt":"fix the crash"}' "$R" "$nogit" | GIT_CEILING_DIRECTORIES="$WORK" "$HOOK")"
git -C "$nogit" init -q 2>/dev/null
rexpect "inside a git repo (cwd)" yes "$(printf '{"session_id":"r1","transcript_path":"%s","cwd":"%s","prompt":"fix the crash"}' "$R" "$nogit" | "$HOOK")"

printf '%s\n%s\n' "$opener" '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t2","name":"Skill","input":{"skill":"platform-guardian:work-router"}}]}}' >"$R"
out="$(rhook "$R" "now a second bug: the EPG freezes")"
for want in '`platform-guardian:work-router`' 'a different bug, feature or task' 'any code change after the Ono step has finished' 'even when it describes a failure or a new symptom: continue that step' 'follows its next_command' 'for this task or the whole session'; do
  case "$out" in *"$want"*) PASS=$((PASS + 1)) ;; *) FAIL=$((FAIL + 1)); echo "FAIL short note missing: $want" ;; esac
done
sexpect "routed: pasted path gets the short note" yes "$(rhook "$R" "/Users/raz/app/epg.log shows the freeze")"
sexpect "routed: slash command gets no short note" no "$(rhook "$R" "/ono-mobile-dev-plugin:analyze-bug EPG")"
sexpect "routed: turned off" no "$(printf '{"session_id":"r1","transcript_path":"%s","prompt":"fix it"}' "$R" | PG_ROUTE_REMINDER=off "$HOOK")"
mkdir -p "$WORK/plain2"
sexpect "routed: outside a git repo (dir exists)" no "$(printf '{"session_id":"r1","transcript_path":"%s","cwd":"%s","prompt":"fix it"}' "$R" "$WORK/plain2" | GIT_CEILING_DIRECTORIES="$WORK" "$HOOK")"

# routed + long session: the short note and the close-out notice both print
printf '%s\n%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t2","name":"Skill","input":{"skill":"platform-guardian:work-router"}}]}}' '{"type":"assistant","message":{"usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":150000}}}' >"$R"
out="$(printf '{"session_id":"r10","transcript_path":"%s","prompt":"another bug"}' "$R" | "$HOOK")"
case "$out" in "[platform-guardian] Routing: new work"*"context is about 150k"*) PASS=$((PASS + 1)) ;; *) FAIL=$((FAIL + 1)); echo "FAIL short note + close-out: $out" ;; esac

# both notices in one reply: routing note first, close-out still fires
: >"$R"; printf '{"type":"assistant","message":{"usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":150000}}}\n' >>"$R"
out="$(printf '{"session_id":"r9","transcript_path":"%s","prompt":"fix the crash"}' "$R" | "$HOOK")"
case "$out" in "[platform-guardian] Routing:"*"context is about 150k"*) PASS=$((PASS + 1)) ;; *) FAIL=$((FAIL + 1)); echo "FAIL both notices: $out" ;; esac

echo
echo "prompt-submit.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
