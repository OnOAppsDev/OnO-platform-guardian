#!/usr/bin/env bash
# Tests for scripts/hook-eol.sh and its HOOK FIX / HOOK PROBLEM lines in hooks/session-start.sh:
# other Ono plugins installed with Windows line endings (their hooks can't start) are fixed in place.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
EOL="$ROOT/scripts/hook-eol.sh"
HOOK="$ROOT/hooks/session-start.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/pg-hookeol.XXXXXX")"
C="$WORK/plugins/cache"   # Claude Code's plugin cache: the only place Guardian writes
trap 'chmod -R u+w "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT
PASS=0 FAIL=0
eq() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL $1"; echo "     got:  $2"; echo "     want: $3"; fi; }
has() { case "$2" in *"$3"*) PASS=$((PASS + 1)) ;; *) FAIL=$((FAIL + 1)); echo "FAIL $1"; echo "     missing: $3" ;; esac; }
hasnt() { case "$2" in *"$3"*) FAIL=$((FAIL + 1)); echo "FAIL $1"; echo "     unexpected: $3" ;; *) PASS=$((PASS + 1)) ;; esac; }
crs() { tr -cd '\r' <"$1" | wc -c | tr -d ' '; }

# a hook script as the plugins write it: runs by its shebang, blocks with exit 2
hook_body() { printf '#!/usr/bin/env bash\n# guard\necho "guard ran"\nexit 2\n'; }
crlf() { hook_body | awk '{ printf "%s\r\n", $0 }' >"$1"; chmod 755 "$1"; }
lf() { hook_body >"$1"; chmod 755 "$1"; }

# installs: dev (all CRLF, incl. hooks/lib), qa (one CRLF hook + a CRLF test script, never touched),
# insp (LF), guardian (CRLF, but Guardian is never touched), other marketplace (CRLF, never touched)
mkdir -p "$C/dev/hooks/lib" "$C/qa/hooks" "$C/insp/scripts" "$C/pg/hooks" "$C/other/hooks" "$WORK/local/hooks"
crlf "$C/dev/hooks/block-main-branch-changes.sh"; crlf "$C/dev/hooks/scan-for-secrets.sh"; crlf "$C/dev/hooks/lib/hook-json.sh"
crlf "$C/qa/hooks/block-qa-repo-git-writes.sh"; crlf "$C/qa/hooks/block-qa-repo-git-writes.test.sh"
lf "$C/insp/scripts/write-guard.sh"
crlf "$C/pg/hooks/session-start.sh"; crlf "$C/other/hooks/x.sh"
printf 'notes\r\n' >"$C/dev/hooks/README.md"   # not a script: never touched
crlf "$C/dev/hooks/review-pr-guard.sh"; { head -n 1 "$C/dev/hooks/review-pr-guard.sh" | tr -d '\r'; tail -n +2 "$C/dev/hooks/review-pr-guard.sh"; } >"$WORK/t" && cat "$WORK/t" >"$C/dev/hooks/review-pr-guard.sh"   # LF shebang, CRLF body
crlf "$WORK/elsewhere.sh"; ln -s "$WORK/elsewhere.sh" "$C/dev/hooks/linked.sh"   # a symlink: never followed
crlf "$WORK/local/hooks/guard.sh"   # an install outside the plugin cache (a local marketplace = a working copy)
entry() { printf '"%s@%s":[{"scope":"user","installPath":"%s","version":"%s"}]' "$1" "$2" "$3" "$4"; }
printf '{"version":2,"plugins":{%s,%s,%s,%s,%s}}' \
  "$(entry ono-mobile-dev-plugin ono-plugin-marketplace "$C/dev" 0.9.0)" \
  "$(entry ono-plugin-qa ono-plugin-marketplace "$C/qa" 0.11.0)" \
  "$(entry ono-project-inspector ono-plugin-marketplace "$C/insp" 0.13.0)" \
  "$(entry platform-guardian ono-plugin-marketplace "$C/pg" 0.7.3)" \
  "$(entry other-plugin elsewhere "$C/other" 1.0.0)" >"$WORK/oneline.json"
sed -i.bak 's|}}$|,'"$(entry ono-local ono-plugin-marketplace "$WORK/local" 0.1.0)"'}}|' "$WORK/oneline.json"
# the same list, pretty-printed (Claude Code writes it that way)
tr ',' '\n' <"$WORK/oneline.json" >"$WORK/pretty.json"

# the CRLF hook can't start — the bug itself (exit 126/127, never the guard's exit 2)
out="$("$C/dev/hooks/scan-for-secrets.sh" 2>&1)"; rc=$?
[ "$rc" -ne 2 ] && [ "$rc" -ne 0 ] && PASS=$((PASS + 1)) || { FAIL=$((FAIL + 1)); echo "FAIL a CRLF hook can't start (rc=$rc: $out)"; }

for list in oneline pretty; do
  out="$(PG_PLUGINS_FILE="$WORK/$list.json" "$EOL" check)"
  eq "check ($list): the CRLF installs, their scripts" "$out" "$(printf 'ono-mobile-dev-plugin\t0.9.0\thooks/block-main-branch-changes.sh, hooks/review-pr-guard.sh, hooks/scan-for-secrets.sh, hooks/lib/hook-json.sh')"
done
eq "check changes nothing" "$(crs "$C/dev/hooks/scan-for-secrets.sh")" 4

out="$(PG_PLUGINS_FILE="$WORK/pretty.json" "$EOL" fix)"
eq "fix: one line per fixed install" "$out" "$(printf 'fixed\tono-mobile-dev-plugin\t0.9.0\thooks/block-main-branch-changes.sh, hooks/review-pr-guard.sh, hooks/scan-for-secrets.sh, hooks/lib/hook-json.sh')"
for f in dev/hooks/block-main-branch-changes.sh dev/hooks/scan-for-secrets.sh dev/hooks/lib/hook-json.sh; do
  eq "fix: $f has no CR" "$(crs "$C/$f")" 0
  [ -x "$C/$f" ] && PASS=$((PASS + 1)) || { FAIL=$((FAIL + 1)); echo "FAIL fix keeps $f executable"; }
  eq "fix: $f is byte-for-byte the LF original" "$(cmp -s "$C/$f" <(hook_body) && echo same)" same
done
eq "never a *.test.sh" "$(crs "$C/qa/hooks/block-qa-repo-git-writes.test.sh")" 4
eq "never ono-plugin-qa (0.8.0: not in the dev setup; its folder-name rule could block a developer)" "$(crs "$C/qa/hooks/block-qa-repo-git-writes.sh")" 4
eq "never Guardian itself" "$(crs "$C/pg/hooks/session-start.sh")" 4
eq "never another marketplace" "$(crs "$C/other/hooks/x.sh")" 4
eq "never a non-script file" "$(crs "$C/dev/hooks/README.md")" 1
eq "never through a symlink" "$(crs "$WORK/elsewhere.sh")" 4
eq "never outside the plugin cache" "$(crs "$WORK/local/hooks/guard.sh")" 4
eq "a CRLF body behind an LF shebang is fixed too" "$(crs "$C/dev/hooks/review-pr-guard.sh")" 0
eq "no temp files left" "$(find "$WORK" -name '*.pg-eol.*' | wc -l | tr -d ' ')" 0
out="$("$C/dev/hooks/scan-for-secrets.sh" 2>&1)"; rc=$?
eq "the fixed hook starts and blocks (exit 2)" "$rc:$out" "2:guard ran"
eq "second run: nothing to fix" "$(PG_PLUGINS_FILE="$WORK/pretty.json" "$EOL" fix)" ""

# no write access → failed, the file untouched (root can write anyway: skipped there)
crlf "$C/dev/hooks/lib/hook-json.sh"; chmod 555 "$C/dev/hooks/lib/hook-json.sh" "$C/dev/hooks/lib"
if [ "$(id -u)" != 0 ]; then
  out="$(PG_PLUGINS_FILE="$WORK/pretty.json" "$EOL" fix)"
  eq "read-only: failed" "$out" "$(printf 'failed\tono-mobile-dev-plugin\t0.9.0\thooks/lib/hook-json.sh')"
  eq "read-only: untouched" "$(crs "$C/dev/hooks/lib/hook-json.sh")" 4
fi
chmod 755 "$C/dev/hooks/lib" "$C/dev/hooks/lib/hook-json.sh"
PG_PLUGINS_FILE="$WORK/pretty.json" "$EOL" fix >/dev/null   # back to a clean cache

# part fixed, part not: two lines, each naming only its own files
if [ "$(id -u)" != 0 ]; then
  crlf "$C/dev/hooks/scan-for-secrets.sh"; crlf "$C/dev/hooks/lib/hook-json.sh"; chmod 555 "$C/dev/hooks/lib"
  out="$(PG_PLUGINS_FILE="$WORK/pretty.json" "$EOL" fix)"
  eq "partial: fixed + failed lines" "$out" "$(printf 'fixed\tono-mobile-dev-plugin\t0.9.0\thooks/scan-for-secrets.sh\nfailed\tono-mobile-dev-plugin\t0.9.0\thooks/lib/hook-json.sh')"
  chmod 755 "$C/dev/hooks/lib"; PG_PLUGINS_FILE="$WORK/pretty.json" "$EOL" fix >/dev/null
fi

# two sessions starting at the same moment: every script ends up whole (rename, never a truncate)
for i in 1 2 3 4 5 6 7 8; do crlf "$C/dev/hooks/g$i.sh"; done
for i in 1 2 3 4 5 6; do PG_PLUGINS_FILE="$WORK/pretty.json" "$EOL" fix >/dev/null & done; wait
whole=0; for i in 1 2 3 4 5 6 7 8; do cmp -s "$C/dev/hooks/g$i.sh" <(hook_body) && whole=$((whole + 1)); done
eq "concurrent fixes: every script whole and LF" "$whole" 8
eq "concurrent fixes: no temp files left" "$(find "$WORK" -name '*.pg-eol.*' | wc -l | tr -d ' ')" 0
rm -f "$C"/dev/hooks/g?.sh

# fails open
eq "no list" "$(PG_PLUGINS_FILE="$WORK/none.json" "$EOL" fix; echo "rc=$?")" "rc=0"
eq "install folder gone" "$(printf '{"plugins":{%s}}' "$(entry ono-plugin-qa ono-plugin-marketplace "$WORK/gone" 1)" >"$WORK/gone.json"; PG_PLUGINS_FILE="$WORK/gone.json" "$EOL" fix; echo "rc=$?")" "rc=0"
eq "bad mode" "$("$EOL" nope 2>/dev/null; echo "rc=$?")" "rc=2"

# session start: the fix runs and is said once; first-time welcome names it; off switch
R="$WORK/repo"; git -c init.defaultBranch=main init -q "$R"; git -C "$R" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
run_hook() { (cd "$R" && echo '{}' | PG_NO_FETCH=1 PG_PLUGINS_FILE="$WORK/pretty.json" PG_LOG_DIR="$WORK/log" CLAUDE_PROJECT_DIR="$R" "$@" "$HOOK" 2>/dev/null); }
crlf "$C/dev/hooks/scan-for-secrets.sh"
out="$(run_hook env PG_HOOK_EOL=off PG_ONBOARDING=off)"
hasnt "PG_HOOK_EOL=off: no line" "$out" "HOOK FIX"
eq "PG_HOOK_EOL=off: not fixed" "$(crs "$C/dev/hooks/scan-for-secrets.sh")" 4
out="$(run_hook env PG_ONBOARDING=off)"
has "session start: HOOK FIX line" "$out" "HOOK FIX: ono-mobile-dev-plugin 0.9.0 had Windows line endings in its scripts on this computer (hooks/scan-for-secrets.sh)"
eq "session start: fixed" "$(crs "$C/dev/hooks/scan-for-secrets.sh")" 0
out="$(run_hook env PG_ONBOARDING=off)"
hasnt "next session: said once" "$out" "HOOK FIX"
crlf "$C/dev/hooks/scan-for-secrets.sh"
out="$(run_hook env PG_LOG_DIR="$WORK/fresh")"
has "first time: welcome item 3e" "$out" "3e. Each HOOK FIX / HOOK PROBLEM line below"
has "first time: the line itself" "$out" "HOOK FIX: ono-mobile-dev-plugin"
crlf "$C/dev/hooks/scan-for-secrets.sh"; chmod 555 "$C/dev/hooks/scan-for-secrets.sh" "$C/dev/hooks"
if [ "$(id -u)" != 0 ]; then
  out="$(run_hook env PG_ONBOARDING=off)"
  has "session start: HOOK PROBLEM line" "$out" "HOOK PROBLEM: ono-mobile-dev-plugin 0.9.0 has Windows line endings"
fi
chmod 755 "$C/dev/hooks" "$C/dev/hooks/scan-for-secrets.sh"
out="$(run_hook env PG_ONBOARDING=off PG_HOOK_BUDGET=0)"
has "past the budget: named as skipped" "$out" "Windows line endings in the other Ono plugins' scripts"

echo
echo "hook-eol.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
