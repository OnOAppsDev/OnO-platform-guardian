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
REAL_NODE="$(command -v node 2>/dev/null)"; export REAL_NODE
cat >"$WORK/node" <<'EOF'
#!/usr/bin/env bash
[ "$1" = -e ] && exec "$REAL_NODE" "$@"          # pr-body parses the answer with node -e
case "$1" in *node-preflight.mjs)
  if [ "${FAKE_PREFLIGHT:-ok}" = ok ]; then echo '{"supported":true}'; exit 0; fi
  echo '{"supported":false,"version":"20.19.4","message":"Unsupported Node.js v20.19.4."}'; exit 1 ;;
esac
shift; script="$1"; shift   # --no-warnings <script> check …
case "${FAKE_NODE:-ok}" in
  ok) printf '{"contract":"ono-pr-readiness","args":"%s"}\n' "$*" ;;
  ready) printf '%s\n' '{"contract":"ono-pr-readiness","ready_for_pr":true,"managed":true,"pr_metadata":{"title_suggestion":"Fix \"login\" $HOME `x`\nline2","description_markdown":"## Fix\n\n### Ono references (v1)\n- a \"quoted\" \\ path\n"}}' ;;
  notready) printf '%s\n' '{"contract":"ono-pr-readiness","ready_for_pr":false,"managed":true,"blockers":[{"code":"PRE_PR_MISSING"}],"pr_metadata":{"title_suggestion":"t","description_markdown":"d"}}' ;;
  unmanaged) printf '%s\n' '{"contract":"ono-pr-readiness","ready_for_pr":true,"managed":false,"pr_metadata":null}' ;;
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
eq "no node-preflight.mjs → not run" "$(FAKE_PREFLIGHT=bad PG_PLUGINS_FILE="$WORK/oneline.json" run readiness | cut -c1-29)" '{"contract":"ono-pr-readiness'
: >"$P/scripts/node-preflight.mjs"   # present from here on
eq "unsupported Node.js → the plugin's own preflight message" "$(FAKE_PREFLIGHT=bad PG_PLUGINS_FILE="$WORK/oneline.json" run readiness)" \
  '{"guardian":"node-unsupported","preflight":{"supported":false,"version":"20.19.4","message":"Unsupported Node.js v20.19.4."}}'
eq "node prints nothing" "$(FAKE_NODE=silent PG_PLUGINS_FILE="$WORK/oneline.json" run readiness)" \
  '{"guardian":"error","note":"pr-readiness.ts gave no answer"}'
eq "node crashes" "$(FAKE_NODE=crash PG_PLUGINS_FILE="$WORK/oneline.json" run readiness; echo "rc=$?")" \
  "$(printf '%s\n%s' '{"guardian":"error","note":"pr-readiness.ts gave no answer"}' 'rc=0')"
eq "outside a repo" "$(cd "$WORK" && PG_NODE="$WORK/node" PG_PLUGINS_FILE="$WORK/oneline.json" "$DP" readiness)" '{"guardian":"not-a-repo"}'
"$DP" bogus >/dev/null 2>&1; eq "unknown subcommand → 2" "$?" 2

# --- which entry: this project's, then user scope, then the first; any marketplace key ---
mkdir -p "$WORK/u/scripts" "$WORK/pr/scripts" "$WORK/o/scripts"
printf '{"plugins":{"ono-mobile-dev-plugin@old-mkt":[{"scope":"project","projectPath":"/elsewhere","installPath":"%s","version":"0.7.7"}],"ono-mobile-dev-plugin@ono-plugin-marketplace":[{"scope":"project","projectPath":"/other","installPath":"/x","version":"0.7.0"},{"scope":"user","installPath":"%s","version":"0.8.0"}]}}' "$WORK/o" "$WORK/u" >"$WORK/multi.json"
eq "user scope beats other projects' entries (any marketplace key)" "$(PG_PLUGINS_FILE="$WORK/multi.json" run version)" "0.8.0"
printf '{"plugins":{"ono-mobile-dev-plugin@m":[{"scope":"user","installPath":"%s","version":"0.8.0"},{"scope":"project","projectPath":"%s","installPath":"%s","version":"0.8.1"}]}}' "$WORK/u" "$top" "$WORK/pr" >"$WORK/proj.json"
eq "this project's entry wins" "$(PG_PLUGINS_FILE="$WORK/proj.json" run path)" "$WORK/pr"
printf '{"plugins":{"ono-mobile-dev-plugin@m":[{"scope":"local","projectPath":"/a","installPath":"/first","version":"0.8.0"},{"scope":"local","projectPath":"/b","installPath":"/second","version":"0.8.0"}]}}' >"$WORK/first.json"
eq "nothing better → the first" "$(PG_PLUGINS_FILE="$WORK/first.json" run path)" "/first"
printf '{"plugins":{"ono-mobile-dev-plugin@m":[{"scope":"user","installPath":"C:\\\\Users\\\\dana\\\\.claude\\\\plugins\\\\dev","version":"0.8.0"}]}}' >"$WORK/win.json"
eq "Windows path unescaped" "$(PG_PLUGINS_FILE="$WORK/win.json" run path)" 'C:\Users\dana\.claude\plugins\dev'
printf '{"plugins":{"ono-mobile-dev-plugin-extras@m":[{"scope":"user","installPath":"/extras","version":"9.0.0"}]}}' >"$WORK/prefix.json"
eq "a plugin whose name only starts the same isn't it" "$(PG_PLUGINS_FILE="$WORK/prefix.json" run path; echo "rc=$?")" "rc=1"

# --- pr-body: title + body written exactly from pr_metadata ---
if [ -n "$REAL_NODE" ]; then
  B="$WORK/body"
  eq "pr-body ready → files" "$(FAKE_NODE=ready PG_PLUGINS_FILE="$WORK/oneline.json" run pr-body "$B")" \
    "{\"guardian\":\"pr-body\",\"title\":\"$B/title.txt\",\"body\":\"$B/body.md\"}"
  eq "body byte-for-byte" "$(cat "$B/body.md"; echo .)" "$(printf '## Fix\n\n### Ono references (v1)\n- a "quoted" \\ path\n.')"
  eq "title one line, raw" "$(cat "$B/title.txt")" 'Fix "login" $HOME `x` line2'
  rm -rf "$B"
  out="$(FAKE_NODE=notready PG_PLUGINS_FILE="$WORK/oneline.json" run pr-body "$B")"
  case "$out" in *PRE_PR_MISSING*) eq "not ready → the check's JSON, no files" "$(ls "$B" 2>/dev/null)" "" ;; *) eq "not ready → check JSON" "$out" "(PRE_PR_MISSING)" ;; esac
  case "$(FAKE_NODE=unmanaged PG_PLUGINS_FILE="$WORK/oneline.json" run pr-body "$B")" in *'"managed":false'*) PASS=$((PASS + 1)) ;; *) FAIL=$((FAIL + 1)); echo "FAIL unmanaged → check JSON" ;; esac
  eq "pr-body, not installed" "$(PG_PLUGINS_FILE="$WORK/qa-only.json" run pr-body "$B")" '{"guardian":"dev-plugin-not-installed"}'
else
  echo "(no node on this machine — pr-body checks skipped)"
fi

echo "dev-plugin.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
