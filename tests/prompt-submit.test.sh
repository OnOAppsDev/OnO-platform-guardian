#!/usr/bin/env bash
# Tests for hooks/prompt-submit.sh (session-length signal).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../hooks/prompt-submit.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/pg-prompt.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
export PG_LOG_DIR="$WORK/logs" PG_CLOSEOUT_TOKENS=100000 PG_CLOSEOUT_STEP=40000

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

echo
echo "prompt-submit.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
