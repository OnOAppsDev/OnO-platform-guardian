#!/usr/bin/env bash
# Inspect gate (UserPromptSubmit + UserPromptExpansion): Ono rule — every project goes through
# the Ono Project Inspector before work starts. While scripts/inspect-status.sh says the
# project isn't inspected, the employee's messages and Ono plugin commands are BLOCKED with a
# red ⛔ banner, except:
#   - the inspector itself (/ono-project-inspector:…, /inspect…) — and, once it ran in this
#     session, every following message (answering the inspector's questions);
#   - the manager-approval sentence (exact, Hebrew or English) → today's override for this repo;
#   - built-in commands (/clear, /plugin, /exit, …) and Guardian's own (/platform-guardian:…).
# Fails open: anything unexpected → exit 0 with no output. Never writes stderr.
#
# Env: PG_INSPECT_GATE=off disables it; PG_LOG_DIR (state dir).

[ "${PG_INSPECT_GATE:-}" = "off" ] && exit 0
here="$(cd "$(dirname "$0")" && pwd)"
scripts="${CLAUDE_PLUGIN_ROOT:-$here/..}/scripts"
payload="$(cat 2>/dev/null)"

# json_str KEY → unescaped value of the first "KEY":"…" in the payload
json_str() {
  printf '%s' "$payload" | awk -v key="\"$1\"" '
    { buf = buf $0 "\n" }
    END {
      i = index(buf, key); if (!i) exit
      s = substr(buf, i + length(key)); sub(/^[ \t\r\n]*:[ \t\r\n]*"/, "", s)
      out = ""
      while (length(s) > 0) {
        c = substr(s, 1, 1)
        if (c == "\\") { n = substr(s, 2, 1)
          if (n == "n") out = out "\n"; else if (n == "t") out = out "\t"; else out = out n
          s = substr(s, 3); continue }
        if (c == "\"") break
        out = out c; s = substr(s, 2)
      }
      printf "%s", out
    }'
}

event="$(json_str hook_event_name)"
session="$(json_str session_id)"
dir="$(json_str cwd)"; [ -d "$dir" ] || dir="${CLAUDE_PROJECT_DIR:-$PWD}"
case "$event" in
  # live envelope: command_name ("plugin:cmd"), command_args, command_source, prompt ("/plugin:cmd …")
  UserPromptExpansion) text="$(json_str prompt)"
    [ -n "$text" ] || { n="$(json_str command_name)"; [ -n "$n" ] && text="/$n $(json_str command_args)"; }
    [ -n "$text" ] || { t="$(json_str command_text)"; [ -n "$t" ] && text="/${t#/}"; } ;;   # documented name
  *) text="$(json_str user_prompt)"; [ -n "$text" ] || text="$(json_str prompt)" ;;
esac

status_line="$("$scripts/inspect-status.sh" check "$dir" 2>/dev/null)"
status="${status_line%%	*}"; detail="${status_line#*	}"
case "$status" in missing|partial|on-central) ;; *) exit 0 ;; esac

state="${PG_LOG_DIR:-$HOME/.claude/platform-guardian}/.state"
flag="$state/inspecting-${session:-none}"
json_esc() {
  printf '%s' "$1" | tr -d '\000-\011\013-\037' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' \
    | awk '{ printf "%s%s", (NR > 1 ? "\\n" : ""), $0 }'
}
context() { # allow, and tell Claude something
  printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' \
    "${event:-UserPromptSubmit}" "$(json_esc "$1")"
  exit 0
}

# the inspector already started in this session → let the conversation with it flow
[ -n "$session" ] && [ -f "$flag" ] && exit 0

trimmed="$(printf '%s' "$text" | tr '\n\t' '  ' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

# commands
case "$trimmed" in
  /ono-project-inspector:*|/inspect|/inspect\ *|/inspect-*)
    mkdir -p "$state" 2>/dev/null && : >"$flag" 2>/dev/null
    exit 0 ;;
  /platform-guardian:*) exit 0 ;;
  /*:*) ;;                                   # another plugin's command → gated below
  /*)                                        # short form: gated only if it's an Ono plugin command
    name="${trimmed%% *}"
    grep -q "\"$name[\" ]" "$scripts/../routing/routes.json" 2>/dev/null || exit 0 ;;
esac

# the manager-approval sentence (normalized: case, spaces, final punctuation)
norm="$(printf '%s' "$trimmed" | tr '[:upper:]' '[:lower:]' | tr -s ' ' | sed 's/[.!]*$//')"
case "$norm" in
  "i have manager approval to work without inspect"|"יש לי אישור מנהל לעבוד בלי inspect")
    "$scripts/inspect-status.sh" override "$dir" >/dev/null 2>&1
    context "[platform-guardian] INSPECT GATE — the employee typed the manager-approval sentence: they may work in this repo today WITHOUT the Ono Project Inspector (recorded locally for today). Reply in their language, briefly: ⚠️ confirm they can continue today with manager approval; the inspection is still required — run /ono-project-inspector:inspect as soon as possible; tomorrow the gate asks again. Then ask what we're working on (or continue the session opener)." ;;
esac

case "$status" in
  missing)    why="This project has not been inspected yet."
              fix="👉 Run the inspection now:  /ono-project-inspector:inspect" ;;
  partial)    why="The inspection of this project was started but not finished (missing: $detail)."
              fix="👉 Finish it:  /ono-project-inspector:inspect  → Continue" ;;
  on-central) why="${detail#origin/} already has the inspection, but your branch is older and doesn't."
              fix="👉 Update your branch, then start again:  ! git merge $detail" ;;
esac

reason="⛔🚨⛔ STOP — PROJECT INSPECTION REQUIRED ⛔🚨⛔

⚠️ $why
Ono rule: every project goes through the Ono Project Inspector before any work starts.
Until then, Claude is blocked in this project.

$fix

⚠️ Only with your manager's approval, you can work without it for today.
Type this sentence exactly:
   I have manager approval to work without inspect
   (או בעברית:  יש לי אישור מנהל לעבוד בלי inspect)"

printf '{"decision":"block","reason":"%s"}\n' "$(json_esc "$reason")"
exit 0
