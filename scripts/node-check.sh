#!/usr/bin/env bash
# Can this computer's Node.js run the Ono plugins? (0.7.3)
#
#   node-check.sh [<preflight.mjs>] → one line, tab-separated:
#       ok          <version>
#       unsupported <version> <message>   too old / Node 23 / earlier 22
#       none                               no node on Claude Code's PATH
#       unreadable  -         <message>   it ran, but gave no answer (broken install, NODE_OPTIONS,
#                                          a hang, a crash) — never treated as supported
#   Always exits 0.
#
# With a preflight script (the inspector's scripts/node-preflight.mjs, 0.12.0+) its verdict decides:
# exit 0 + JSON → ok · exit 1 + JSON → unsupported (its own message) · anything else → unreadable.
# Without one: `node -v` against the same rule the dev plugin and the inspector use (Node 22.18+ on
# the 22 line, or Node 24+). One node process either way, under a watchdog (PG_NODE_TIMEOUT: 2 s for
# `node -v`, 3 s for the preflight, which loads a script — a cold start on Windows with antivirus is
# slow): a broken shim must not eat the session-start hook's 20 s.
# This sees the node on Claude Code's own PATH; the plugins' commands run node through the Bash tool,
# which can load a different one (nvm set up only in the shell).

node_bin="${PG_NODE:-node}"
pf="${1:-}"
command -v "$node_bin" >/dev/null 2>&1 || { echo none; exit 0; }

out="$(mktemp "${TMPDIR:-/tmp}/pg-node.XXXXXX" 2>/dev/null)" || { printf 'unreadable\t-\t\n'; exit 0; }
if [ -n "$pf" ]; then "$node_bin" "$pf" </dev/null >"$out" 2>/dev/null &
else "$node_bin" -v </dev/null >"$out" 2>/dev/null &
fi
pid=$!
( sleep "${PG_NODE_TIMEOUT:-$([ -n "$pf" ] && echo 3 || echo 2)}"; kill -TERM "$pid" ) >/dev/null 2>&1 &
dog=$!
wait "$pid" 2>/dev/null; rc=$?
if kill -0 "$dog" 2>/dev/null; then pkill -TERM -P "$dog" 2>/dev/null; kill -TERM "$dog" 2>/dev/null; fi
wait "$dog" 2>/dev/null
first="$(head -1 "$out" | tr -d '\r')"
rm -f "$out"

if [ -n "$pf" ]; then
  # {"supported":…,"version":"22.18.0","execPath":"…","required":"…","message":"…"} — one line
  case "$first" in '{'*'"supported":'*'}') ;; *) printf 'unreadable\t-\tthe Node.js preflight gave no answer\n'; exit 0 ;; esac
  v="$(printf '%s' "$first" | sed -n 's/.*"version":"\([^"\\]*\)".*/\1/p')"
  case "$rc:$first" in
    0:*'"supported":true'*) printf 'ok\tv%s\n' "${v#v}" ;;
    1:*'"supported":false'*)
      msg="$(printf '%s' "$first" | sed -En 's/.*"message":"(([^"\\]|\\.)*)".*/\1/p' | sed 's/\\"/"/g; s/\\\\/\\/g')"
      printf 'unsupported\tv%s\t%s\n' "${v#v}" "$msg" ;;
    *) printf 'unreadable\t-\tthe Node.js preflight failed\n' ;;
  esac
  exit 0
fi

major="${first#v}"; major="${major%%.*}"
minor="${first#v*.}"; minor="${minor%%.*}"
case "$first:$major:$minor" in
  v*:*[!0-9:]*|v*::*|v*:*:|[!v]*|"":*) printf 'unreadable\t-\t\n' ;;
  *) if [ "${#major}" -le 4 ] && { [ "$major" -ge 24 ] || { [ "$major" -eq 22 ] && [ "$minor" -ge 18 ]; }; }
     then printf 'ok\t%s\n' "$first"
     else printf 'unsupported\t%s\t\n' "$first"; fi ;;
esac
