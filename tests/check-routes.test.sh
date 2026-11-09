#!/usr/bin/env bash
# Tests for scripts/check-routes.sh against fake plugin checkouts built from routes.json.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
CHECK="$HERE/../scripts/check-routes.sh"
ROUTES="$HERE/../routing/routes.json"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/pg-routes.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
PASS=0 FAIL=0
expect() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL $1 (got $2, want $3)"; fi; }

# Build one fake checkout per plugin with every referenced command/skill present.
eval "$(sed -n '/^refs_for()/,/^}/p' "$CHECK")"
for p in $(jq -r '.verifiedAgainst | keys[]' "$ROUTES"); do
  d="$WORK/plugins/$p"; mkdir -p "$d/.claude-plugin" "$d/commands" "$d/skills"
  jq -n --arg n "$p" --arg v "$(jq -r --arg p "$p" '.verifiedAgainst[$p]' "$ROUTES")" '{name:$n, version:$v}' >"$d/.claude-plugin/plugin.json"
  for r in $(refs_for "$p"); do
    case "$r" in skill:*) mkdir -p "$d/skills/${r#skill:}"; touch "$d/skills/${r#skill:}/SKILL.md" ;; *) touch "$d/commands/$r.md" ;; esac
  done
done

"$CHECK" "$WORK/plugins" >/dev/null; expect "all present → exit 0" "$?" "0"

jq '.version="9.9.9"' "$WORK/plugins/ono-plugin-qa/.claude-plugin/plugin.json" >"$WORK/m" && mv "$WORK/m" "$WORK/plugins/ono-plugin-qa/.claude-plugin/plugin.json"
out="$("$CHECK" "$WORK/plugins")"; expect "version drift alone → exit 0" "$?" "0"
case "$out" in *"VERSION DRIFT"*) PASS=$((PASS + 1)) ;; *) FAIL=$((FAIL + 1)); echo "FAIL drift not reported" ;; esac
"$CHECK" "$WORK/plugins" --strict >/dev/null; expect "version drift with --strict → exit 1" "$?" "1"

rm "$WORK/plugins/ono-mobile-dev-plugin/commands/analyze-bug.md"
out="$("$CHECK" "$WORK/plugins")"; expect "missing command → exit 1" "$?" "1"
case "$out" in *"MISSING COMMAND ono-mobile-dev-plugin: analyze-bug"*) PASS=$((PASS + 1)) ;; *) FAIL=$((FAIL + 1)); echo "FAIL missing command not named: $out" ;; esac

rm -rf "$WORK/plugins/spec-team-toolkit"
out="$("$CHECK" "$WORK/plugins")"
case "$out" in *"MISSING PLUGIN  spec-team-toolkit"*) PASS=$((PASS + 1)) ;; *) FAIL=$((FAIL + 1)); echo "FAIL missing plugin not reported" ;; esac

"$CHECK" "$WORK/nope" >/dev/null 2>&1; expect "bad dir → usage error" "$?" "2"

echo
echo "check-routes.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
