#!/usr/bin/env bash
# Tests for scripts/inspect-status.sh + hooks/inspect-gate.sh against throwaway repos.
# Needs git + jq (jq is test-only).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ST="$HERE/../scripts/inspect-status.sh"
GATE="$HERE/../hooks/inspect-gate.sh"

command -v jq >/dev/null || { echo "jq is required to run the tests"; exit 1; }
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 PG_NO_FETCH=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
unset CLAUDE_PLUGIN_ROOT CLAUDE_PROJECT_DIR PG_INSPECT_GATE PG_TODAY

WORK="$(mktemp -d "${TMPDIR:-/tmp}/pg-inspect.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
export PG_LOG_DIR="$WORK/state"

PASS=0 FAIL=0
ok()   { PASS=$((PASS + 1)); }
fail() { FAIL=$((FAIL + 1)); echo "FAIL [$1]"; [ -n "${2:-}" ] && printf '      got: %s\n' "$2"; }
eq()   { [ "$2" = "$3" ] && ok || fail "$1" "$2 (want $3)"; }

R="$WORK/app"
fresh() {
  rm -rf "$R" "$WORK/origin.git"; mkdir -p "$R"
  git -c init.defaultBranch=develop init -q "$R"; echo a >"$R/a.txt"
  git -C "$R" add -A; git -C "$R" commit -qm init
}
inspect_files() { # inspect_files [skip-file]
  mkdir -p "$R/docs/project"
  printf '# AUDIT.md\n\n| # | Status | Topic | x | y |\n' >"$R/AUDIT.md"; echo c >"$R/CLAUDE.md"
  for p in overview components patterns integrations capabilities; do echo d >"$R/docs/project/$p.md"; done
  [ -n "${1:-}" ] && rm -f "$R/$1"
  return 0
}
status() { "$ST" check "$R" | cut -f1; }

# --- status ---
fresh;                      eq "never inspected → missing" "$(status)" missing
inspect_files;              eq "all stage 1–2 files → done" "$(status)" done
inspect_files docs/project/patterns.md
out="$("$ST" check "$R")";  eq "a doc missing → partial" "${out%%	*}" partial
case "$out" in *docs/project/patterns.md*) ok ;; *) fail "partial names the missing file" "$out" ;; esac
inspect_files docs/project/capabilities.md
out="$("$ST" check "$R")";  eq "older knowledge model (no capabilities.md) → still done" "${out%%	*}" done
case "$out" in *"refresh-recommended: docs/project/capabilities.md"*) ok ;; *) fail "done carries the refresh hint" "$out" ;; esac
fresh; echo "# Audit" >"$R/AUDIT.md"; echo c >"$R/CLAUDE.md"
eq "someone else's AUDIT.md doesn't count" "$(status)" missing
fresh; printf '{"centralBranch": "develop", "inspectRequired": false}\n' >"$R/.platform-guardian.json"
eq "inspectRequired false → exempt" "$(status)" exempt
eq "not a git repo → skip" "$("$ST" check "$WORK" | cut -f1)" skip

# central has it, this branch doesn't
fresh; git -C "$R" switch -q -c feature/old; git -C "$R" switch -q develop
inspect_files; git -C "$R" add -A; git -C "$R" commit -qm inspect
git clone -q --bare "$R" "$WORK/origin.git"; git -C "$R" remote add origin "$WORK/origin.git"; git -C "$R" fetch -q origin
git -C "$R" remote set-head origin develop >/dev/null 2>&1
git -C "$R" switch -q feature/old
out="$("$ST" check "$R")";  eq "central has it → on-central" "${out%%	*}" on-central
case "$out" in *origin/develop*) ok ;; *) fail "on-central names the ref" "$out" ;; esac

# override: today only
fresh
eq "override recorded" "$(PG_TODAY=2026-11-15 "$ST" override "$R" | cut -f1)" override
eq "override valid today" "$(PG_TODAY=2026-11-15 "$ST" check "$R" | cut -f1)" override
eq "override gone tomorrow" "$(PG_TODAY=2026-11-16 "$ST" check "$R" | cut -f1)" missing
[ -z "$(find "$R" -name 'inspect-override*')" ] && ok || fail "override never written inside the repo"
rm -rf "$PG_LOG_DIR"

# --- gate ---
# gate EVENT TEXT [SESSION] → sets OUT, DEC (block | context | none)
gate() {
  local key=user_prompt payload
  [ "$1" = UserPromptExpansion ] && key=prompt
  payload="$(jq -cn --arg e "$1" --arg t "$2" --arg s "${3:-s1}" --arg d "$R" --arg k "$key" \
    '{hook_event_name:$e, session_id:$s, cwd:$d} + {($k):$t}')"
  OUT="$(printf '%s' "$payload" | "$GATE" 2>"$WORK/err")"; RC=$?
  if [ -s "$WORK/err" ]; then DEC="stderr"; return; fi
  if [ -z "$OUT" ]; then DEC=none
  elif printf '%s' "$OUT" | jq -e '.decision == "block"' >/dev/null 2>&1; then DEC=block
  elif printf '%s' "$OUT" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1; then DEC=context
  else DEC="invalid"; fi
}

fresh
gate UserPromptSubmit "hi";                         eq "missing: plain message blocked" "$DEC" block
reason="$(printf '%s' "$OUT" | jq -r .reason)"
case "$reason" in *"⛔"*"/ono-project-inspector:inspect"*"I have manager approval to work without inspect"*) ok ;; *) fail "banner: red, command, sentence" "$reason" ;; esac
gate UserPromptSubmit "fix bug YEA-1";              eq "missing: task blocked" "$DEC" block
gate UserPromptExpansion "/ono-mobile-dev-plugin:analyze-bug YEA-1"; eq "Ono plugin command blocked" "$DEC" block
gate UserPromptExpansion "/analyze-bug YEA-1";      eq "short Ono command blocked" "$DEC" block
gate UserPromptExpansion "/clear";                  eq "built-in /clear allowed" "$DEC" none
gate UserPromptExpansion "/plugin";                 eq "built-in /plugin allowed" "$DEC" none
gate UserPromptExpansion "/platform-guardian:onboarding"; eq "Guardian's own command allowed" "$DEC" none
gate UserPromptSubmit "I have manager approval"      ; eq "partial sentence still blocked" "$DEC" block
gate UserPromptExpansion "/ono-project-inspector:inspect" s2; eq "inspector allowed" "$DEC" none
gate UserPromptSubmit "1" s2;                       eq "then answers to the inspector flow (same session)" "$DEC" none
gate UserPromptSubmit "1" s3;                       eq "…but not in another session" "$DEC" block
gate UserPromptSubmit "  I have Manager approval to work without inspect. " s4; eq "sentence (case/space/punct) → allowed" "$DEC" context
case "$(printf '%s' "$OUT" | jq -r .hookSpecificOutput.additionalContext)" in *"manager"*) ok ;; *) fail "context tells Claude" "$OUT" ;; esac
gate UserPromptSubmit "fix bug YEA-1" s5;           eq "override holds for the day, new session too" "$DEC" none
rm -rf "$PG_LOG_DIR"
gate UserPromptSubmit "יש לי אישור מנהל לעבוד בלי inspect" s6; eq "Hebrew sentence → allowed" "$DEC" context
rm -rf "$PG_LOG_DIR"

inspect_files docs/project/overview.md
gate UserPromptSubmit "hi";                         eq "partial: blocked" "$DEC" block
case "$(printf '%s' "$OUT" | jq -r .reason)" in *"started but not finished"*) ok ;; *) fail "partial banner" "$OUT" ;; esac
inspect_files
gate UserPromptSubmit "hi";                         eq "done: allowed, silent" "$DEC" none
inspect_files docs/project/capabilities.md
gate UserPromptSubmit "hi";                         eq "older knowledge model: NOT blocked (tester bug)" "$DEC" none
fresh
OUT="$(printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","user_prompt":"hi"}' "$R" | PG_INSPECT_GATE=off "$GATE")"
eq "PG_INSPECT_GATE=off" "$OUT" ""
OUT="$(printf 'garbage' | "$GATE" 2>&1)"; RC=$?
eq "garbage payload fails open (exit 0)" "$RC" 0
OUT="$(printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"hi"}' "$R" | "$GATE")"
printf '%s' "$OUT" | jq -e '.decision == "block"' >/dev/null && ok || fail "older 'prompt' field also read" "$OUT"

# the live UserPromptExpansion envelope (pinned by another plugin's live drill)
fresh
OUT="$(printf '{"session_id":"x","cwd":"%s","hook_event_name":"UserPromptExpansion","expansion_type":"slash_command","command_name":"ono-mobile-dev-plugin:analyze-bug","command_args":"YEA-1","command_source":"plugin","prompt":"/ono-mobile-dev-plugin:analyze-bug YEA-1"}' "$R" | "$GATE")"
printf '%s' "$OUT" | jq -e '.decision == "block"' >/dev/null && ok || fail "live envelope: plugin command blocked" "$OUT"
OUT="$(printf '{"session_id":"x","cwd":"%s","hook_event_name":"UserPromptExpansion","command_name":"ono-project-inspector:inspect","command_args":"","command_source":"plugin"}' "$R" | "$GATE")"
eq "live envelope without prompt: inspector via command_name allowed" "$OUT" ""

echo
echo "inspect-status.sh + inspect-gate.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
