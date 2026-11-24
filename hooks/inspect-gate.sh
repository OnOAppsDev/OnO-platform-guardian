#!/usr/bin/env bash
# Inspect gate (UserPromptSubmit + UserPromptExpansion): Ono rule — every project goes through
# the Ono Project Inspector before work starts. While scripts/inspect-status.sh says the
# project isn't inspected, the employee's messages and Ono plugin commands are BLOCKED with a
# red ⛔ banner, except:
#   - the inspector itself (/ono-project-inspector:…, /inspect…) — and, once it ran in this
#     session, every following message (answering the inspector's questions);
#   - the manager-approval sentence (exact, Hebrew or English) → today's override for this repo;
#   - built-in commands (/clear, /plugin, /exit, …) and Guardian's own (/platform-guardian:…);
#   - creating a work branch: exactly `git switch -c <name> [<start>]` / `git checkout -b …`
#     (with or without a leading `!`), one command, <name> not a protected branch.
# Protected branch (scripts/protected-branch.sh — main, master, the central branch when certain):
# the inspector writes files (also through bun scripts, which no write hook sees), so its
# commands are blocked there whatever the inspect status — first inspection and refresh alike —
# except the read-only inspect-status. The banner then starts with "create a work branch".
# Fails open: anything unexpected → exit 0 with no output. Never writes stderr.
#
# Env: PG_INSPECT_GATE=off disables it; PG_LOG_DIR (state dir); PG_PLUGINS_FILE / PG_CLAUDE_DIR
# (installed-plugins list / user settings — tests); PG_BUN / PG_OS (Bun binary, OS — tests).

[ "${PG_INSPECT_GATE:-}" = "off" ] && exit 0
here="$(cd "$(dirname "$0")" && pwd)"
scripts="${CLAUDE_PLUGIN_ROOT:-$here/..}/scripts"
payload="$(cat 2>/dev/null)"
nl='
'

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

trimmed="$(printf '%s' "$text" | tr '\n\t' '  ' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
pb="$("$scripts/protected-branch.sh" check "$dir" 2>/dev/null)"
on_protected=""; [ "${pb%%	*}" = protected ] && { on_protected=1; pb_rest="${pb#*	}"; branch="${pb_rest%%	*}"; }

json_esc() {
  printf '%s' "$1" | tr -d '\000-\011\013-\037' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' \
    | awk '{ printf "%s%s", (NR > 1 ? "\\n" : ""), $0 }'
}
context() { # allow, and tell Claude something
  printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' \
    "${event:-UserPromptSubmit}" "$(json_esc "$1")"
  exit 0
}

block() { printf '{"decision":"block","reason":"%s"}\n' "$(json_esc "$1")"; exit 0; }
is_inspector=""
case "$trimmed" in
  /ono-project-inspector:inspect-status|/ono-project-inspector:inspect-status\ *|/inspect-status|/inspect-status\ *) ;;
  /ono-project-inspector:*|/inspect|/inspect\ *|/inspect-*) is_inspector=1 ;;
esac

# the inspector writes files → never on a protected branch (first inspection and refresh alike)
[ -n "$is_inspector" ] && [ -n "$on_protected" ] && block "⛔ STOP — CREATE A WORK BRANCH FIRST ⛔

You're on \`$branch\`, a protected branch. The Ono Project Inspector writes files, so it never runs here.

👉 1. Create a work branch (type this, with the !):   ! git switch -c chore/project-inspection
👉 2. Then run the inspector:   ${trimmed%% *}

Any branch name works. The inspection then goes into a PR, so the whole team gets it."

status_line="$("$scripts/inspect-status.sh" check "$dir" 2>/dev/null)"
status="${status_line%%	*}"; detail="${status_line#*	}"
case "$status" in missing|partial|on-central) ;; *) exit 0 ;; esac

state="${PG_LOG_DIR:-$HOME/.claude/platform-guardian}/.state"
flag="$state/inspecting-${session:-none}"

# the inspector already started in this session → let the conversation with it flow
[ -n "$session" ] && [ -f "$flag" ] && exit 0

# creating a work branch — allowed while gated; exactly one branch command, nothing rides along
bc="$(printf '%s' "$trimmed" | sed -e 's/^![[:space:]]*//')"
case "$bc" in *[\;\&\|\$\`\<\>\(\)\\]*) bc="" ;; esac
case "$text" in *"$nl"*) bc="" ;; esac       # one line only — nothing rides along on a second line
set -f; set -- $bc; set +f
case "${1:-} ${2:-} ${3:-}" in "git switch -c"|"git checkout -b") ;; *) set -- ;; esac
if [ "$#" -ge 4 ] && [ "$#" -le 5 ]; then
  name="$4"
  case "$name ${5:-}" in *[!A-Za-z0-9._/\ -]*|-*|*" -"*) name="" ;; esac
  # a start point must be a real commit (origin/develop, a tag …), not free text
  [ -n "${5:-}" ] && ! git -C "$dir" rev-parse -q --verify "${5}^{commit}" >/dev/null 2>&1 && name=""
  if [ -n "$name" ] && ! "$scripts/protected-branch.sh" is "$name" "$dir"; then
    context "[platform-guardian] WORK BRANCH — the employee asked for exactly this git command: \`$bc\`. If \`git branch --show-current\` already shows \`$name\` (they ran it with !), run nothing; otherwise run exactly that one command and nothing else. Then tell them in one line that they're on \`$name\`, and that the next step is the project inspection: \`/ono-project-inspector:inspect\`. Nothing else until it's done."
  fi
fi

# is the inspector there? A missing or disabled one would leave the employee with a command that
# doesn't exist (and must not open the gate). Unknown (no plugins list) → assume it is.
inspector=""
plugins="${PG_PLUGINS_FILE:-$HOME/.claude/plugins/installed_plugins.json}"
if [ -f "$plugins" ] && ! grep -q '"ono-project-inspector@' "$plugins" 2>/dev/null; then inspector=missing
else
  top="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)"
  # user → project → local: the last file that mentions it decides (Claude Code's precedence)
  for f in "${PG_CLAUDE_DIR:-$HOME/.claude}/settings.json" "$top/.claude/settings.json" "$top/.claude/settings.local.json"; do
    [ -f "$f" ] || continue
    grep -Eq '"ono-project-inspector@[^"]*"[[:space:]]*:[[:space:]]*false' "$f" 2>/dev/null && inspector=disabled
    grep -Eq '"ono-project-inspector@[^"]*"[[:space:]]*:[[:space:]]*true' "$f" 2>/dev/null && inspector=""
  done
fi

# on-central: the banner's own fix — exactly `git merge <central ref>` — is let through too
if [ "$status" = on-central ] && [ "$bc" = "git merge $detail" ]; then
  context "[platform-guardian] UPDATE BRANCH — the employee asked for exactly: \`$bc\` (the central branch already has the project inspection). If it already ran (they used !), run nothing; otherwise run exactly that one command and nothing else. If it hits conflicts, stop and walk them through it. Then tell them in one line that the inspection is now on their branch and they can start working."
fi

# commands
case "$trimmed" in
  /ono-project-inspector:*|/inspect|/inspect\ *|/inspect-*)
    [ -z "$inspector" ] || [ -z "$is_inspector" ] || block "⛔ The Ono Project Inspector is $( [ "$inspector" = missing ] && echo "not installed" || echo "turned off" ) on this computer.

👉 $( [ "$inspector" = missing ] && echo "Install it:  /plugin install ono-project-inspector@ono-plugin-marketplace" || echo "Turn it on:  /plugin → Installed → ono-project-inspector → Enable" )
👉 Then:  /reload-plugins
👉 Then run:  /ono-project-inspector:inspect"
    [ -n "$is_inspector" ] && mkdir -p "$state" 2>/dev/null && : >"$flag" 2>/dev/null
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
case "$inspector" in
  missing)  fix="👉 First install the inspector:  /plugin install ono-project-inspector@ono-plugin-marketplace  → then /reload-plugins
$fix" ;;
  disabled) fix="👉 First turn the inspector on:  /plugin → Installed → ono-project-inspector → Enable  → then /reload-plugins
$fix" ;;
esac
# the inspector runs on Bun and stops without it (its check-bun.sh) — say so before they try
if [ "$status" != on-central ] && ! command -v "${PG_BUN:-bun}" >/dev/null 2>&1; then
  case "${PG_OS:-$(uname -s 2>/dev/null)}" in
    windows|MINGW*|MSYS*|CYGWIN*|Windows_NT)
      bun='in PowerShell (not here):  powershell -c "irm bun.sh/install.ps1 | iex"' ;;
    mac|Darwin)
      bun="in the Terminal app (not here):  brew install oven-sh/bun/bun   (no Homebrew: curl -fsSL https://bun.sh/install | bash)" ;;
    *) bun="in a terminal (not here):  curl -fsSL https://bun.sh/install | bash" ;;
  esac
  fix="👉 First install Bun (the inspector runs on it) — $bun
   then quit Claude Code and open it again from a new window.
   (Not allowed to install software? Ask IT — or a teammate who has Bun can run the inspection.)
$fix"
fi
# the inspector writes files → a work branch first (it's blocked on a protected branch)
if [ -n "$on_protected" ] && [ "$status" != on-central ]; then
  fix="You're on \`$branch\`, a protected branch — the inspection is done on a work branch and reaches the team through a PR.
👉 1. Create a work branch (type this, with the !):   ! git switch -c chore/project-inspection
👉 2. Then:
$fix"
fi

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
