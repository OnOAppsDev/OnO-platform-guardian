#!/usr/bin/env bash
# The installed ono-mobile-dev-plugin, for the closer and the router (0.7.0, dev plugin 0.8.0+).
#
#   dev-plugin.sh path          → its installPath (exit 1 when not installed)
#   dev-plugin.sh version       → its installed version (exit 1 when not installed)
#   dev-plugin.sh has-review-pr → exit 0 when it ships /review-pr (0.8.0+)
#   dev-plugin.sh readiness [--base <branch>] [--work <bug:key|feature:name>]
#       → one JSON object: the plugin's PR-readiness contract v1
#         (scripts/pr-readiness.ts check --contract 1, read-only, docs/pr-readiness-contract.md),
#         or Guardian's own {"guardian":"…"} when it can't be asked:
#           dev-plugin-not-installed · dev-plugin-too-old (no pr-readiness.ts) · node-missing ·
#           node-unsupported (the plugin's own node-preflight.mjs said no — its JSON in "preflight") ·
#           not-a-repo · error
#   dev-plugin.sh pr-body <dir> [--base …] [--work …]
#       → the same check; when it is ready and carries pr_metadata, writes <dir>/title.txt and
#         <dir>/body.md byte-for-byte from it (no hand-copying: /review-pr reads the body back) and
#         prints {"guardian":"pr-body","title":"<dir>/title.txt","body":"<dir>/body.md"};
#         otherwise prints the check's own JSON unchanged.
#
# Which install: installed_plugins.json ($PG_PLUGINS_FILE, else $CLAUDE_CONFIG_DIR/plugins/…, default
# ~/.claude) can hold several entries — per marketplace, and per project (scope "project" +
# projectPath). The entry for this project wins, then a user-scope one, then the first. Always exits 0
# for readiness / pr-body.

plugins="${PG_PLUGINS_FILE:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/installed_plugins.json}"
here_root="$(git rev-parse --show-toplevel 2>/dev/null)"

# pick_entry → "installPath<TAB>version" of the best ono-mobile-dev-plugin@… entry
pick_entry() {
  [ -f "$plugins" ] || return 1
  tr -d '\n\r' <"$plugins" \
    | grep -o '"ono-mobile-dev-plugin@[^"]*"[[:space:]]*:[[:space:]]*\[[^]]*\]' \
    | sed 's/^[^[]*\[//; s/\]$//' | tr '}' '\n' \
    | awk -v root="$here_root" -v pwd="$PWD" -v proj="${CLAUDE_PROJECT_DIR:-}" '
        function field(k,   v) {
          if (!match($0, "\"" k "\"[[:space:]]*:[[:space:]]*\"([^\"\\\\]|\\\\.)*\"")) return ""
          v = substr($0, RSTART, RLENGTH); sub("^\"" k "\"[[:space:]]*:[[:space:]]*\"", "", v); sub(/"$/, "", v)
          gsub(/\\\//, "/", v); gsub(/\\\\/, "\\", v)   # JSON escapes: \/ and \\ (Windows paths)
          return v
        }
        /"installPath"/ {
          p = field("installPath"); if (p == "") next
          s = 1; pp = field("projectPath")
          if (field("scope") == "user") s = 2
          if (pp != "" && (pp == root || pp == pwd || pp == proj)) s = 3
          if (s > best) { best = s; out = p "\t" field("version") }
        }
        END { if (out != "") print out; else exit 1 }'
}

guardian() { printf '{"guardian":"%s"%s}\n' "$1" "${2:+,$2}"; exit 0; }

readiness() { # readiness ARGS… → prints one JSON object; sets $node_bin
  local entry p v out pf
  entry="$(pick_entry)" || guardian dev-plugin-not-installed
  p="${entry%%	*}"; v="${entry#*	}"
  [ -f "$p/scripts/pr-readiness.ts" ] || guardian dev-plugin-too-old "\"version\":\"${v:-?}\""
  node_bin="${PG_NODE:-node}"
  command -v "$node_bin" >/dev/null 2>&1 || guardian node-missing
  if [ -f "$p/scripts/node-preflight.mjs" ]; then
    pf="$("$node_bin" "$p/scripts/node-preflight.mjs" 2>/dev/null)" ||
      { case "$pf" in '{'*) guardian node-unsupported "\"preflight\":$pf" ;; *) guardian node-unsupported ;; esac; }
  fi
  [ -n "$here_root" ] || guardian not-a-repo
  out="$("$node_bin" --no-warnings "$p/scripts/pr-readiness.ts" check --root "$here_root" --contract 1 "$@" 2>/dev/null)"
  case "$out" in
    '{'*) printf '%s\n' "$out" ;;   # the contract always prints one JSON object and exits 0
    *) guardian error "\"note\":\"pr-readiness.ts gave no answer\"" ;;
  esac
}

case "${1:-}" in
  path) e="$(pick_entry)" && printf '%s\n' "${e%%	*}" ;;
  version) e="$(pick_entry)" && [ -n "${e#*	}" ] && printf '%s\n' "${e#*	}" ;;
  has-review-pr) e="$(pick_entry)" && [ -f "${e%%	*}/commands/review-pr.md" ] ;;
  readiness) shift; readiness "$@" ;;
  pr-body)
    shift; dir="${1:-}"; [ "$#" -gt 0 ] && shift
    [ -n "$dir" ] && mkdir -p "$dir" 2>/dev/null || { echo "usage: dev-plugin.sh pr-body <dir> [--base B] [--work W]" >&2; exit 2; }
    json="$(readiness "$@")"
    case "$json" in '{"guardian"'*) printf '%s\n' "$json"; exit 0 ;; esac
    node_bin="${PG_NODE:-node}"
    # the same Node.js that just ran the check parses its answer — no jq needed
    if printf '%s' "$json" | "$node_bin" -e '
        let s = ""; process.stdin.on("data", d => s += d).on("end", () => {
          const r = JSON.parse(s), m = r.pr_metadata;
          if (!r.ready_for_pr || !m || typeof m.description_markdown !== "string") process.exit(3);
          const fs = require("fs"), dir = process.argv[1];
          fs.writeFileSync(dir + "/body.md", m.description_markdown);
          fs.writeFileSync(dir + "/title.txt", String(m.title_suggestion || "").replace(/[\r\n]+/g, " ").trim());
        });' "$dir" 2>/dev/null; then
      printf '{"guardian":"pr-body","title":"%s/title.txt","body":"%s/body.md"}\n' "$dir" "$dir"
    else
      printf '%s\n' "$json"   # not ready, or no metadata (unmanaged work) — the check's own answer
    fi
    ;;
  *) echo "usage: dev-plugin.sh path | version | has-review-pr | readiness [--base B] [--work W] | pr-body <dir> […]" >&2; exit 2 ;;
esac
