#!/usr/bin/env bash
# UserPromptSubmit hook: session-length signal (G3.1).
#
# Reads the context size of the last assistant turn from the transcript's
# `usage` block (input + cache_creation + cache_read tokens). When it crosses
# the threshold, injects a one-time instruction to suggest the close-out; it
# repeats only after another PG_CLOSEOUT_STEP tokens. Plain stdout from a
# UserPromptSubmit hook is added to Claude's context. Fails open, exit 0.
#
# Env: PG_CLOSEOUT_TOKENS (default 120000), PG_CLOSEOUT_STEP (default 40000),
#      PG_LOG_DIR (state lives in $PG_LOG_DIR/.state).

payload="$(cat 2>/dev/null)"

field() { # field NAME → first "NAME":"value" string in the payload
  printf '%s' "$payload" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -n 1
}
num() { # num NAME TEXT → integer value of "NAME":N in TEXT, or 0
  local v
  v="$(printf '%s' "$2" | sed -n "s/.*\"$1\":\([0-9][0-9]*\).*/\1/p" | head -n 1)"
  printf '%s' "${v:-0}"
}

transcript="$(field transcript_path)"
session="$(field session_id)"
[ -f "$transcript" ] || exit 0

threshold="${PG_CLOSEOUT_TOKENS:-120000}"
step="${PG_CLOSEOUT_STEP:-40000}"
case "$threshold$step" in *[!0-9]*) exit 0 ;; esac
[ "$step" -gt 0 ] || step=40000

usage="$(tail -c 500000 "$transcript" 2>/dev/null | grep -o '"usage":{[^}]*}' | tail -n 1)"
[ -n "$usage" ] || exit 0
tokens=$(( $(num input_tokens "$usage") + $(num cache_creation_input_tokens "$usage") + $(num cache_read_input_tokens "$usage") ))
[ "$tokens" -ge "$threshold" ] || exit 0

# Remind once per band: threshold, threshold+step, threshold+2*step, ...
band=$(( (tokens - threshold) / step ))
state_dir="${PG_LOG_DIR:-$HOME/.claude/platform-guardian}/.state"
state="$state_dir/$(printf '%s' "${session:-unknown}" | tr -c 'A-Za-z0-9._-' '_').closeout"
last="$(cat "$state" 2>/dev/null)"
case "$last" in ''|*[!0-9]*) last=-1 ;; esac
[ "$band" -gt "$last" ] || exit 0
mkdir -p "$state_dir" 2>/dev/null && printf '%s' "$band" >"$state" 2>/dev/null

k=$(( tokens / 1000 ))
cat <<MSG
[platform-guardian] This session's context is about ${k}k tokens — long sessions get slower and less accurate.
Answer the user's message first. Then end your reply with a short close-out suggestion that tells the employee exactly what to do — never just "it's a good time to stop". Use this shape (in their language):

---
💡 This session is getting long. Good moment to save and start fresh:
1. Say **"close the session"** — I'll save everything: commit, PR, and a note of where we stopped.
2. When I say it's saved, type **\`/clear\`** and press Enter.
3. In the fresh session, write your next message — anything, e.g. "continue" — and I'll open with where we stopped.
---

Don't start the close-out until they say so (it runs the \`platform-guardian:session-closer\` skill).
Show this suggestion once — don't repeat it in later replies unless a new [platform-guardian] notice arrives.
MSG
exit 0
