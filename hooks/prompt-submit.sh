#!/usr/bin/env bash
# UserPromptSubmit hook: routing reminder + session-length signal (G3.1).
#
# Routing reminder (0.5.1): until this session has been routed — the work-router
# or pre-pr skill ran, or an Ono plugin skill / command ran (Claude or the
# employee started it) — every typed message in a git repo gets a note: a task goes
# through platform-guardian:work-router before any investigation or edit. The
# opener's hand-off alone was lost when the task arrived in the next turn
# (bug report 2026-11-18). After that (0.5.2) a shorter note stays on every
# message: a NEW task mid-session is routed too, while replies inside the running
# Ono step just continue it. A slash command gets no note (a pasted /path does).
#
# Reads the context size of the last assistant turn from the transcript's
# `usage` block (input + cache_creation + cache_read tokens). When it crosses
# the threshold, injects a one-time instruction to suggest the close-out; it
# repeats only after another PG_CLOSEOUT_STEP tokens. Plain stdout from a
# UserPromptSubmit hook is added to Claude's context. Fails open, exit 0.
#
# Env: PG_CLOSEOUT_TOKENS (default 120000), PG_CLOSEOUT_STEP (default 40000),
#      PG_LOG_DIR (state lives in $PG_LOG_DIR/.state),
#      PG_ROUTE_REMINDER=off turns the routing reminder off.

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

routes="$(dirname "$0")/../routing/routes.json"
routed() { # has this session been routed into an Ono process?
  # Only real JSON structure counts: inside a tool result the same text is a string with
  # escaped quotes (\"skill\":…), and a typed command is the user message's own content.
  grep -Eq '"name":"Skill","input":\{"skill":"((platform-guardian:)?(work-router|pre-pr)|ono-[a-z0-9-]+:[^"]*)"|"name":"SlashCommand","input":\{"command":"/(ono-[a-z0-9-]+:|platform-guardian:(work-router|pre-pr))|"role":"user","content":"(<command-message>[^"]*)?<command-name>/(ono-[a-z0-9-]+:|platform-guardian:(work-router|pre-pr))' "$transcript" 2>/dev/null && return 0
  local c   # a short form (/analyze-bug, or skill "analyze-bug") that routes.json knows
  for c in $( { grep -Eo '"role":"user","content":"(<command-message>[^"]*)?<command-name>/[a-z0-9-]+</command-name>' "$transcript" \
                  | sed 's/.*<command-name>\/\([a-z0-9-]*\)<.*/\1/'
                grep -Eo '"name":"Skill","input":\{"skill":"[a-z0-9-]+"' "$transcript" | sed 's/.*"skill":"//; s/"$//'
              } 2>/dev/null | sort -u); do
    grep -q "\"/$c[\" ]" "$routes" 2>/dev/null && return 0
  done
  return 1
}
in_repo() { # the reminder only matters where Ono work can happen: inside a git repo
  local d; d="$(field cwd)"; [ -d "$d" ] || d="${CLAUDE_PROJECT_DIR:-$PWD}"
  git -C "$d" rev-parse --git-dir >/dev/null 2>&1
}
prompt="$(field prompt)"; [ -n "$prompt" ] || prompt="$(field user_prompt)"
case "${prompt%% *}" in
  ''|/*/*) is_cmd= ;;                          # a pasted path (/Users/…) is not a command
  /*) is_cmd=1 ;;
  *) is_cmd= ;;
esac
# no transcript yet = not routed yet
if [ -n "$prompt" ] && [ -z "$is_cmd" ] && [ "${PG_ROUTE_REMINDER:-on}" != off ] && in_repo; then
  if routed; then
    cat <<'MSG'
[platform-guardian] Routing: new work — a different bug, feature or task, or any code change after the Ono step has finished — goes through the `platform-guardian:work-router` skill before you read code or edit. If you last asked a question for the running Ono step (approve, continue, results, details), this message answers it, even when it describes a failure or a new symptom: continue that step; "yes" / "continue" to a Continue? offer follows its next_command. Questions with no change asked for: just answer. Work outside the Ono flow only when the employee said so for this task or the whole session.
MSG
  else
    cat <<'MSG'
[platform-guardian] Routing: this session hasn't been routed into an Ono process yet. If this message asks for work — a bug, a feature, a fix, a task, tests, a review, "continue" — run the `platform-guardian:work-router` skill now, before you read code, investigate or edit anything (if the session opener is still due, run it first). It confirms the task with the employee and starts the right Ono plugin command (a bug → the dev plugin's bug analysis, which finds the root cause and gets a plan approved before any code changes). A general preference for lean or fast work doesn't skip this — only the employee saying they don't want the Ono plugin flow (for this task or the whole session) does — then don't ask again for it. If the message is a greeting, an answer to the opener's git question, a question or explanation with no change asked for, a close-out request or a question about Guardian, just answer it.
MSG
  fi
fi

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
Answer the user's message first. **Timing:** if an Ono plugin step is in the middle of running and hasn't saved its result yet (e.g. a bug analysis whose platform was detected / confirmed but whose plan file isn't written, a task half implemented), don't suggest closing now — closing mid-step makes the next session redo it (re-run the analysis, re-do a half-implemented task). Hold the suggestion and show it once, right after that step saves its result. Otherwise, end your reply with a short close-out suggestion that tells the employee exactly what to do — never just "it's a good time to stop". Use this shape (in their language):

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
