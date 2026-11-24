#!/usr/bin/env bash
# An installed Ono plugin, from Claude Code's installed-plugins list.
#
#   ono-plugin.sh entry   <plugin> → "installPath<TAB>version" (exit 1 when not installed here)
#   ono-plugin.sh path    <plugin> → its installPath
#   ono-plugin.sh version <plugin> → its installed version (exit 1 when unknown)
#   ono-plugin.sh inspector-runtime → how the installed ono-project-inspector runs (0.7.3):
#       node <preflight.mjs>  0.12.0+ — Node.js only; the path is its own preflight script
#       bun <version>         older — still runs on Bun (the fix is updating it, not installing Bun)
#       unknown               installed, but no version / install folder to tell from
#       (exit 1, nothing)     not installed for this project, or turned off
#
# Which install: installed_plugins.json ($PG_PLUGINS_FILE, else $CLAUDE_CONFIG_DIR/plugins/…, default
# ~/.claude) can hold several entries — per marketplace, and per project (scope "project" / "local" +
# projectPath). The entry for this project wins, then a user-scope one, then the first. For
# inspector-runtime only, another project's entry doesn't count ("not installed here": no inspector line).
# Turned off: enabledPlugins false in user → project → local settings (the last one that names it
# decides — Claude Code's precedence); $PG_CLAUDE_DIR overrides the user settings folder (tests).

cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
plugins="${PG_PLUGINS_FILE:-$cfg/plugins/installed_plugins.json}"

pick_entry() { # pick_entry <plugin> [strict] → exit 1: no usable entry · exit 2 (strict): only other projects' entries
  [ -f "$plugins" ] || return 1
  local here_root="" list
  list="$(tr -d '\n\r' <"$plugins" | grep -o "\"$1@[^\"]*\"[[:space:]]*:[[:space:]]*\\[[^]]*\\]")" || return 1
  # the git root only matters for project-scoped entries — one process saved on most computers
  case "$list" in *'"projectPath"'*) here_root="$(git rev-parse --show-toplevel 2>/dev/null)" ;; esac
  printf '%s' "$list" \
    | sed 's/^[^[]*\[//; s/\]$//' | tr '}' '\n' \
    | awk -v strict="${2:-}" -v root="$here_root" -v pwd="$PWD" -v proj="${CLAUDE_PROJECT_DIR:-}" '
        function field(k,   v) {
          if (!match($0, "\"" k "\"[[:space:]]*:[[:space:]]*\"([^\"\\\\]|\\\\.)*\"")) return ""
          v = substr($0, RSTART, RLENGTH); sub("^\"" k "\"[[:space:]]*:[[:space:]]*\"", "", v); sub(/"$/, "", v)
          gsub(/\\\//, "/", v); gsub(/\\\\/, "\\", v)   # JSON escapes: \/ and \\ (Windows paths)
          return v
        }
        /"installPath"/ {
          p = field("installPath"); if (p == "") next
          s = 1; pp = field("projectPath"); sc = field("scope")
          if (pp != "" && (pp == root || pp == pwd || pp == proj)) s = 3
          else if (strict != "" && (sc == "project" || sc == "local") && pp != "") { foreign = 1; next }
          else if (sc == "user") s = 2
          if (s > best) { best = s; out = p "\t" field("version") }
        }
        END { if (out != "") print out; else if (foreign) exit 2; else exit 1 }'
}

turned_off() { # turned_off <plugin> → exit 0 when the settings say false
  local top f off=1
  top="$(git -C "${CLAUDE_PROJECT_DIR:-.}" rev-parse --show-toplevel 2>/dev/null)"
  for f in "${PG_CLAUDE_DIR:-$cfg}/settings.json" "$top/.claude/settings.json" "$top/.claude/settings.local.json"; do
    [ -f "$f" ] || continue
    grep -Eq "\"$1@[^\"]*\"[[:space:]]*:[[:space:]]*false" "$f" 2>/dev/null && off=0
    grep -Eq "\"$1@[^\"]*\"[[:space:]]*:[[:space:]]*true" "$f" 2>/dev/null && off=1
  done
  return $off
}

case "${1:-}" in
  entry) pick_entry "${2:?plugin}" ;;
  path) e="$(pick_entry "${2:?plugin}")" && printf '%s\n' "${e%%	*}" ;;
  version) e="$(pick_entry "${2:?plugin}")" && [ -n "${e#*	}" ] && printf '%s\n' "${e#*	}" ;;
  inspector-runtime)
    # installed at all? (an entry without installPath — or no list — still counts as installed)
    [ ! -f "$plugins" ] || grep -q '"ono-project-inspector@' "$plugins" 2>/dev/null || exit 1
    turned_off ono-project-inspector && exit 1
    e="$(pick_entry ono-project-inspector strict)"
    case $? in 0) ;; 2) exit 1 ;; *) echo unknown; exit 0 ;; esac
    p="${e%%	*}"; v="${e#*	}"
    # the preflight script is the proof of 0.12.0+; the version decides only when it's missing
    if [ -f "$p/scripts/node-preflight.mjs" ]; then printf 'node %s\n' "$p/scripts/node-preflight.mjs"; exit 0; fi
    case "$v" in
      [1-9]*|0.1[2-9]|0.1[2-9].*|0.[2-9][0-9]|0.[2-9][0-9].*|0.[1-9][0-9][0-9]*) echo unknown ;;  # 0.12+ but no preflight file: can't run it
      0.[0-9]*) printf 'bun %s\n' "$v" ;;
      *) echo unknown ;;
    esac ;;
  *) echo "usage: ono-plugin.sh entry|path|version <plugin> | inspector-runtime" >&2; exit 2 ;;
esac
