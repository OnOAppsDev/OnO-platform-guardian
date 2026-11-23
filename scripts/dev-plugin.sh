#!/usr/bin/env bash
# The installed ono-mobile-dev-plugin, for the closer and the router (0.7.0, dev plugin 0.8.0+).
#
#   dev-plugin.sh path        → its installPath (exit 1 when not installed)
#   dev-plugin.sh version     → its installed version (exit 1 when not installed)
#   dev-plugin.sh has-review-pr → exit 0 when it ships /review-pr (0.8.0+)
#   dev-plugin.sh readiness [--base <branch>] [--work <bug:key|feature:name>]
#       → one JSON object: the plugin's PR-readiness contract v1
#         (scripts/pr-readiness.ts check --contract 1, read-only, docs/pr-readiness-contract.md),
#         or Guardian's own {"guardian":"…"} when it can't be asked:
#           dev-plugin-not-installed · dev-plugin-too-old (no pr-readiness.ts) · node-missing · not-a-repo
#
# The list of installed plugins: $PG_PLUGINS_FILE, else $CLAUDE_CONFIG_DIR/plugins/installed_plugins.json
# (default ~/.claude). First entry of ono-mobile-dev-plugin@<any marketplace>. Always exits 0 for readiness.

plugins="${PG_PLUGINS_FILE:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/installed_plugins.json}"

entry_field() { # entry_field KEY → KEY's string value in the first ono-mobile-dev-plugin@… entry
  [ -f "$plugins" ] || return 1
  # any layout (pretty-printed or one line): from the plugin's key to the end of its entry list
  tr -d '\n\r' <"$plugins" | sed -n 's/.*"ono-mobile-dev-plugin@[^"]*"[[:space:]]*:[[:space:]]*\[\([^]]*\)\].*/\1/p' \
    | tr ',' '\n' | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -n 1 | grep .
}

guardian() { printf '{"guardian":"%s"%s}\n' "$1" "${2:+,$2}"; exit 0; }

case "${1:-}" in
  path) entry_field installPath ;;
  version) entry_field version ;;
  has-review-pr) p="$(entry_field installPath)" && [ -f "$p/commands/review-pr.md" ] ;;
  readiness)
    shift
    p="$(entry_field installPath)" || guardian dev-plugin-not-installed
    v="$(entry_field version)"
    [ -f "$p/scripts/pr-readiness.ts" ] || guardian dev-plugin-too-old "\"version\":\"${v:-?}\""
    node_bin="${PG_NODE:-node}"
    command -v "$node_bin" >/dev/null 2>&1 || guardian node-missing
    root="$(git rev-parse --show-toplevel 2>/dev/null)" || guardian not-a-repo
    out="$("$node_bin" --no-warnings "$p/scripts/pr-readiness.ts" check --root "$root" --contract 1 "$@" 2>/dev/null)"
    case "$out" in
      '{'*) printf '%s\n' "$out" ;;   # the contract always prints one JSON object and exits 0
      *) guardian error "\"note\":\"pr-readiness.ts gave no answer (Node.js too old? run node -v)\"" ;;
    esac
    ;;
  *) echo "usage: dev-plugin.sh path | version | has-review-pr | readiness [--base B] [--work W]" >&2; exit 2 ;;
esac
