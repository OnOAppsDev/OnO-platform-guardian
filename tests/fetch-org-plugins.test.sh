#!/usr/bin/env bash
# Tests for scripts/fetch-org-plugins.sh against local git repos (offline).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
FETCH="$HERE/../scripts/fetch-org-plugins.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/pg-fetch.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
PASS=0 FAIL=0
expect() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL $1 (got $2, want $3)"; fi; }
has() { case "$2" in *"$3"*) PASS=$((PASS + 1)) ;; *) FAIL=$((FAIL + 1)); echo "FAIL $1: $2" ;; esac; }

# repo <dir> <file> <content> [branch] — a one-commit repo, optionally with an extra branch.
repo() {
  mkdir -p "$1" && git -C "$1" init -q -b main && mkdir -p "$(dirname "$1/$2")" && printf '%s' "$3" >"$1/$2"
  git -C "$1" add -A && git -C "$1" commit -q -m init
  if [ -n "${4:-}" ]; then
    git -C "$1" checkout -q -b "$4" && echo "$4" >"$1/branch.txt" && git -C "$1" add -A && git -C "$1" commit -q -m "$4"
    git -C "$1" checkout -q main
  fi
}

repo "$WORK/src/alpha" ".claude-plugin/plugin.json" '{"name":"alpha"}' release
repo "$WORK/src/beta" ".claude-plugin/plugin.json" '{"name":"beta"}'
manifest() {
  cat <<EOF
{"plugins":[
 {"name":"alpha","source":{"source":"url","url":"$WORK/src/alpha","ref":"release"}},
 {"name":"beta","source":{"source":"url","url":"$WORK/src/beta"}},
 {"name":"platform-guardian","source":{"source":"url","url":"$WORK/src/nope"}},
 {"name":"local","source":"./plugins/local"}$1
]}
EOF
}
repo "$WORK/src/market" ".claude-plugin/marketplace.json" "$(manifest "")"

out="$("$FETCH" "$WORK/out" "$WORK/src/market" 2>&1)"; expect "all clones ok → exit 0" "$?" "0"
expect "alpha cloned at its ref" "$(cat "$WORK/out/alpha/branch.txt" 2>/dev/null)" "release"
expect "beta cloned (default branch)" "$(test -f "$WORK/out/beta/.claude-plugin/plugin.json" && echo y)" "y"
expect "platform-guardian skipped" "$(test -e "$WORK/out/platform-guardian" && echo y || echo n)" "n"
expect "relative-path source skipped" "$(test -e "$WORK/out/local" && echo y || echo n)" "n"
has "reports each clone" "$out" "OK      beta"

# Re-run into the same folder replaces the old checkouts.
"$FETCH" "$WORK/out" "$WORK/src/market" >/dev/null 2>&1; expect "re-run → exit 0" "$?" "0"

repo "$WORK/src/market2" ".claude-plugin/marketplace.json" \
  "$(manifest ',{"name":"gone","source":{"source":"url","url":"'"$WORK"'/src/missing"}}')"
out="$("$FETCH" "$WORK/out2" "$WORK/src/market2" 2>&1)"; expect "failed clone → exit 1" "$?" "1"
has "names the failed plugin" "$out" "FAILED  gone"
expect "others still cloned" "$(test -d "$WORK/out2/beta" && echo y)" "y"

out="$("$FETCH" "$WORK/out3" "$WORK/src/missing" 2>&1)"; expect "bad marketplace → exit 1" "$?" "1"
has "names the marketplace failure" "$out" "FAILED  marketplace"
"$FETCH" >/dev/null 2>&1; expect "no args → usage error" "$?" "2"

echo
echo "fetch-org-plugins.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
