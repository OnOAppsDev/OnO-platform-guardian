#!/usr/bin/env bash
# Windows line endings in the other Ono plugins' shell scripts (0.7.5).
#
#   hook-eol.sh check → "<plugin><TAB><version><TAB><script, script…>" per installed copy with CRLF scripts
#   hook-eol.sh fix   → the same scripts with the CRs removed; one line per installed copy:
#                       "fixed<TAB><plugin><TAB><version><TAB><scripts>" and/or "failed<TAB>…" (couldn't write those)
#
# Why: Claude Code installs plugins with Git, and Git for Windows defaults to core.autocrlf=true. A
# plugin without `.gitattributes` (eol=lf) is then installed with CRLF scripts: the shebang reads
# `bash\r`, the hook can't start, and Claude Code treats that as a non-blocking error — the guard
# blocks nothing. Guardian had it until 0.7.4; on 2026-11-25 ono-mobile-dev-plugin 0.9.0 (all
# hooks) and ono-plugin-qa 0.11.0 (its git-write guard) still did on a real Windows machine.
# Removing the CRs gives back the plugin's own committed files; the next plugin version is a
# fresh copy (fixed again, until the plugin ships its own .gitattributes).
#
# Scope: every ono-plugin-marketplace install in installed_plugins.json except Guardian itself and
# ono-plugin-qa (0.8.0, see the awk below),
# only inside Claude Code's plugin cache (…/plugins/cache/…), its hooks/*.sh, hooks/*/*.sh and
# scripts/*.sh — never *.test.sh, never a symlink. A script counts when it has any CR (the shebang
# breaks first, but `then\r` breaks too). Counted with tr (Git Bash's grep can't see CR). The fixed
# file replaces the old one by rename (atomic); the executable bit is kept.
# Fails open: no list, no installs → no output, exit 0.

cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
plugins="${PG_PLUGINS_FILE:-$cfg/plugins/installed_plugins.json}"
mode="${1:-}"
case "$mode" in check|fix) ;; *) echo "usage: hook-eol.sh check|fix" >&2; exit 2 ;; esac
[ -f "$plugins" ] || exit 0

# name<TAB>version<TAB>installPath — every Ono install, any scope
installs="$(tr -d '\n\r' <"$plugins" | grep -o '"[^"@]*@ono-plugin-marketplace"[[:space:]]*:[[:space:]]*\[[^]]*\]' |
  awk '{
    match($0, /^"[^"@]*@/); name = substr($0, 2, RLENGTH - 2)
    # never Guardian itself; never ono-plugin-qa (0.8.0): the QA team works on Macs, so on Windows it is a
    # leftover of Guardian <0.8.0 on a developer computer, and its guard treats any "…qa…" folder as the
    # QA repo — switching it on could block commits of the developer
    if (name == "platform-guardian" || name == "ono-plugin-qa") next
    sub(/^[^[]*\[/, ""); n = split($0, e, "}")
    for (i = 1; i <= n; i++) {
      p = e[i]; v = e[i]
      if (!match(p, /"installPath"[[:space:]]*:[[:space:]]*"([^"\\]|\\.)*"/)) continue
      p = substr(p, RSTART, RLENGTH); sub(/^"installPath"[[:space:]]*:[[:space:]]*"/, "", p); sub(/"$/, "", p)
      gsub(/\\\//, "/", p); gsub(/\\\\/, "\\", p)
      if (match(v, /"version"[[:space:]]*:[[:space:]]*"[^"]*"/)) { v = substr(v, RSTART, RLENGTH); sub(/^"version"[[:space:]]*:[[:space:]]*"/, "", v); sub(/"$/, "", v) } else v = "?"
      if (!(p in seen)) { seen[p] = 1; print name "\t" v "\t" p }
    }
  }')"
[ -n "$installs" ] || exit 0

shopt -s nullglob
tab="$(printf '\t')"
while IFS="$tab" read -r name ver path; do
  # only Claude Code's plugin cache: a marketplace added from a local folder is someone's working copy
  case "$path" in */plugins/cache/*|*\\plugins\\cache\\*) ;; *) continue ;; esac
  [ -d "$path" ] || continue
  files=()
  for f in "$path"/hooks/*.sh "$path"/hooks/*/*.sh "$path"/scripts/*.sh; do
    case "$f" in *.test.sh) continue ;; esac
    [ -f "$f" ] && [ ! -L "$f" ] && files+=("$f")
  done
  [ "${#files[@]}" -gt 0 ] || continue
  # one pass for the whole install (a CR anywhere breaks bash: `then\r`, `exit 2\r`); tr is CR-safe everywhere
  [ "$(cat "${files[@]}" 2>/dev/null | tr -cd '\r' | wc -c | tr -d ' ')" -gt 0 ] 2>/dev/null || continue
  bad=() names=""
  for f in "${files[@]}"; do
    [ "$(tr -cd '\r' <"$f" 2>/dev/null | wc -c | tr -d ' ')" -gt 0 ] 2>/dev/null || continue
    bad+=("$f"); names="$names${names:+, }${f#"$path"/}"
  done
  if [ "$mode" = check ]; then printf '%s\t%s\t%s\n' "$name" "$ver" "$names"; continue; fi
  # a new file renamed over the old one: atomic, so a second session starting at the same moment, a
  # hook running right now (it keeps the old file) or a kill halfway never sees a half-written script
  fixed="" failed=""
  for f in "${bad[@]}"; do
    tmp="$f.pg-eol.$$"
    if { tr -d '\r' <"$f" >"$tmp" && { [ ! -x "$f" ] || chmod +x "$tmp"; } && mv -f "$tmp" "$f"; } 2>/dev/null; then
      fixed="$fixed${fixed:+, }${f#"$path"/}"
    else
      failed="$failed${failed:+, }${f#"$path"/}"; rm -f "$tmp" 2>/dev/null
    fi
  done
  [ -n "$fixed" ] && printf 'fixed\t%s\t%s\t%s\n' "$name" "$ver" "$fixed"
  [ -n "$failed" ] && printf 'failed\t%s\t%s\t%s\n' "$name" "$ver" "$failed"
done <<EOF
$installs
EOF
exit 0
