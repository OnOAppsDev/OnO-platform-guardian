#!/usr/bin/env bash
# Tests for scripts/dev-plugin.sh — finding the installed dev plugin and asking its PR-readiness contract.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
DP="$HERE/../scripts/dev-plugin.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/pg-devplugin.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
PASS=0 FAIL=0
eq() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL $1"; echo "     got:  $2"; echo "     want: $3"; fi; }

# a fake plugin install: <dir>/scripts/pr-readiness.ts is run by a fake node that echoes its arguments as JSON
P="$WORK/dev"; mkdir -p "$P/scripts" "$P/commands"
: >"$P/scripts/pr-readiness.ts"; : >"$P/commands/review-pr.md"
cat >"$WORK/node" <<'EOF'
#!/usr/bin/env bash
shift; script="$1"; shift   # --no-warnings <script> check …
case "${FAKE_NODE:-ok}" in
  ok) printf '{"contract":"ono-pr-readiness","args":"%s"}\n' "$*" ;;
  silent) exit 0 ;;
  crash) echo "SyntaxError: something" >&2; exit 1 ;;
esac
EOF
chmod +x "$WORK/node"
pretty() { printf '{\n  "version": 2,\n  "plugins": {\n    "other@x": [\n      {\n        "installPath": "/nope",\n        "version": "9.9.9"\n      }\n    ],\n    "ono-mobile-dev-plugin@ono-plugin-marketplace": [\n      {\n        "scope": "user",\n        "installPath": "%s",\n        "version": "%s"\n      }\n    ]\n  }\n}\n' "$1" "$2"; }
pretty "$P" 0.8.0 >"$WORK/pretty.json"
printf '{"version":2,"plugins":{"ono-mobile-dev-plugin@ono-plugin-marketplace":[{"scope":"user","installPath":"%s","version":"0.8.0"}],"zz@x":[{"installPath":"/z","version":"1.0.0"}]}}' "$P" >"$WORK/oneline.json"
printf '{"version":2,"plugins":{"ono-plugin-qa@ono-plugin-marketplace":[{"installPath":"/q","version":"0.11.0"}]}}' >"$WORK/qa-only.json"

R="$WORK/repo"; git -c init.defaultBranch=main init -q "$R"
run() { (cd "$R" && PG_NODE="$WORK/node" "$DP" "$@" 2>/dev/null); }

for f in pretty oneline; do
  eq "path ($f)" "$(PG_PLUGINS_FILE="$WORK/$f.json" run path)" "$P"
  eq "version ($f)" "$(PG_PLUGINS_FILE="$WORK/$f.json" run version)" "0.8.0"
done
eq "not another plugin's fields" "$(PG_PLUGINS_FILE="$WORK/qa-only.json" run version; echo "rc=$?")" "rc=1"
eq "missing list → not installed" "$(PG_PLUGINS_FILE="$WORK/none.json" run path; echo "rc=$?")" "rc=1"
eq "CLAUDE_CONFIG_DIR relocates the list" "$(mkdir -p "$WORK/cfg/plugins" && cp "$WORK/oneline.json" "$WORK/cfg/plugins/installed_plugins.json" && CLAUDE_CONFIG_DIR="$WORK/cfg" run version)" "0.8.0"

PG_PLUGINS_FILE="$WORK/oneline.json" run has-review-pr; eq "has-review-pr (0.8.0)" "$?" 0
rm "$P/commands/review-pr.md"
PG_PLUGINS_FILE="$WORK/oneline.json" run has-review-pr; eq "no review-pr.md → 1" "$?" 1
PG_PLUGINS_FILE="$WORK/qa-only.json" run has-review-pr; eq "not installed → 1" "$?" 1

top="$(cd "$R" && git rev-parse --show-toplevel)"
eq "readiness passes root, contract 1 and extra args" "$(PG_PLUGINS_FILE="$WORK/oneline.json" run readiness --base develop --work bug:X-1)" \
  "{\"contract\":\"ono-pr-readiness\",\"args\":\"check --root $top --contract 1 --base develop --work bug:X-1\"}"
eq "not installed" "$(PG_PLUGINS_FILE="$WORK/qa-only.json" run readiness)" '{"guardian":"dev-plugin-not-installed"}'
pretty "$WORK/old" 0.7.7 >"$WORK/old.json"; mkdir -p "$WORK/old/scripts"
eq "older than 0.8.0 (no pr-readiness.ts)" "$(PG_PLUGINS_FILE="$WORK/old.json" run readiness)" '{"guardian":"dev-plugin-too-old","version":"0.7.7"}'
eq "no node" "$(cd "$R" && PG_NODE=pg-no-such-node PG_PLUGINS_FILE="$WORK/oneline.json" "$DP" readiness)" '{"guardian":"node-missing"}'
eq "node prints nothing" "$(FAKE_NODE=silent PG_PLUGINS_FILE="$WORK/oneline.json" run readiness)" \
  '{"guardian":"error","note":"pr-readiness.ts gave no answer (Node.js too old? run node -v)"}'
eq "node crashes" "$(FAKE_NODE=crash PG_PLUGINS_FILE="$WORK/oneline.json" run readiness; echo "rc=$?")" \
  "$(printf '%s\n%s' '{"guardian":"error","note":"pr-readiness.ts gave no answer (Node.js too old? run node -v)"}' 'rc=0')"
eq "outside a repo" "$(cd "$WORK" && PG_NODE="$WORK/node" PG_PLUGINS_FILE="$WORK/oneline.json" "$DP" readiness)" '{"guardian":"not-a-repo"}'
"$DP" bogus >/dev/null 2>&1; eq "unknown subcommand → 2" "$?" 2

echo "dev-plugin.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
