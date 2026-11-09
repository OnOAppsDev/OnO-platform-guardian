#!/usr/bin/env bash
# Tests for scripts/report-drift.sh — gh is stubbed; the stub keeps one fake issue in a folder.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../scripts/report-drift.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/pg-drift.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin" "$WORK/gh"
export GH_STATE="$WORK/gh" PATH="$WORK/bin:$PATH" GITHUB_REPOSITORY=org/repo
unset PG_DRIFT_ASSIGNEE

# Stub gh: records every call; "issue" state = files in $GH_STATE.
cat >"$WORK/bin/gh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >>"$GH_STATE/calls"
arg() { local want="$1"; shift; while [ $# -gt 0 ]; do [ "$1" = "$want" ] && { echo "$2"; return; }; shift; done; }
case "$1 $2" in
  "label create") exit 0 ;;
  "issue list") [ -f "$GH_STATE/open" ] && cat "$GH_STATE/open"; exit 0 ;;
  "issue create") echo 7 >"$GH_STATE/open"; arg --body "$@" >"$GH_STATE/body"; arg --assignee "$@" >"$GH_STATE/assignee"; exit 0 ;;
  "issue view") cat "$GH_STATE/body" "$GH_STATE/comments" 2>/dev/null; exit 0 ;;
  "issue comment") arg --body "$@" >>"$GH_STATE/comments"; echo x >>"$GH_STATE/ncomments"; exit 0 ;;
  "issue close") rm -f "$GH_STATE/open"; echo closed >"$GH_STATE/closed"; exit 0 ;;
esac
EOF
chmod +x "$WORK/bin/gh"

PASS=0 FAIL=0
expect() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL $1 (got $2, want $3)"; fi; }
has() { case "$2" in *"$3"*) PASS=$((PASS + 1)) ;; *) FAIL=$((FAIL + 1)); echo "FAIL $1: $2" ;; esac; }

printf 'cloned ono-plugin-qa\nMISSING COMMAND ono-mobile-dev-plugin: analyze-bug (expected commands/analyze-bug.md)\ncheck-routes: 1 error(s), 0 version drift(s)\n' >"$WORK/out1"
"$SCRIPT" open "$WORK/out1" >/dev/null 2>&1
expect "first drift → issue created" "$(cat "$GH_STATE/open" 2>/dev/null)" "7"
has "issue body has the finding" "$(cat "$GH_STATE/body")" "MISSING COMMAND ono-mobile-dev-plugin: analyze-bug"
case "$(cat "$GH_STATE/body")" in *"cloned ono-plugin-qa"*) FAIL=$((FAIL + 1)); echo "FAIL noise lines kept out" ;; *) PASS=$((PASS + 1)) ;; esac
has "issue body says what to do" "$(cat "$GH_STATE/body")" "What to do"
expect "assigned to Tom by default" "$(cat "$GH_STATE/assignee")" "tomzion90"

"$SCRIPT" open "$WORK/out1" >/dev/null 2>&1
expect "same findings next day → no new issue, no comment" "$(grep -c 'issue create' "$GH_STATE/calls"):$(cat "$GH_STATE/ncomments" 2>/dev/null | wc -l | tr -d ' ')" "1:0"

printf 'MISSING COMMAND ono-mobile-dev-plugin: analyze-bug (expected commands/analyze-bug.md)\nVERSION DRIFT   ono-plugin-qa: routes.json verified 0.11.0, plugin is 0.12.0 — re-verify routes\ncheck-routes: 1 error(s), 1 version drift(s)\n' >"$WORK/out2"
"$SCRIPT" open "$WORK/out2" >/dev/null 2>&1
expect "changed findings → one comment" "$(cat "$GH_STATE/ncomments" | wc -l | tr -d ' ')" "1"
"$SCRIPT" open "$WORK/out2" >/dev/null 2>&1
expect "…and not again for the same change" "$(cat "$GH_STATE/ncomments" | wc -l | tr -d ' ')" "1"

"$SCRIPT" close >/dev/null 2>&1
expect "drift gone → issue closed" "$(cat "$GH_STATE/closed" 2>/dev/null):$( [ -f "$GH_STATE/open" ] && echo open || echo none)" "closed:none"
rm -f "$GH_STATE/closed"; "$SCRIPT" close; expect "close with no issue → exit 0" "$?" "0"
expect "close with no issue → nothing closed" "$( [ -f "$GH_STATE/closed" ] && echo yes || echo no)" "no"

"$SCRIPT" >/dev/null 2>&1; expect "no command → usage" "$?" "2"
"$SCRIPT" open "$WORK/nope" >/dev/null 2>&1; expect "missing file → usage" "$?" "2"

echo
echo "report-drift.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
