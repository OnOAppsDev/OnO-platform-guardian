#!/usr/bin/env bash
# Tests for scripts/check-version-bump.sh.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../scripts/check-version-bump.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/pg-bump.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com

PASS=0 FAIL=0
expect() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL $1 (got $2, want $3)"; fi; }

R="$WORK/r"
git init -q -b master "$R" && cd "$R" || exit 1
mkdir -p .claude-plugin skills/x scripts docs
setv() { printf '{\n  "name": "p",\n  "version": "%s"\n}\n' "$1" >.claude-plugin/plugin.json; }
setv 0.2.0; echo a >skills/x/SKILL.md; echo a >scripts/git-status.sh; echo a >scripts/check-routes.sh; echo a >docs/d.md
git add -A && git commit -qm base && git branch base

case_() { git checkout -q -B work base; }
run() { git add -A && git commit -qm change && "$SCRIPT" base >"$WORK/out" 2>&1; echo $?; }

case_; echo b >docs/d.md
expect "docs only → no bump needed" "$(run)" 0

case_; echo b >scripts/check-routes.sh
expect "maintainer-only script → no bump needed" "$(run)" 0

case_; echo b >skills/x/SKILL.md
expect "skill changed, no bump → fail" "$(run)" 1
grep -q 'skills/x/SKILL.md' "$WORK/out" && PASS=$((PASS + 1)) || { FAIL=$((FAIL + 1)); echo "FAIL message lists the changed file"; }

case_; echo b >scripts/git-status.sh
expect "shipped script changed, no bump → fail" "$(run)" 1

case_; echo b >skills/x/SKILL.md; setv 0.2.1
expect "patch bump → ok" "$(run)" 0

case_; echo b >skills/x/SKILL.md; setv 0.10.0
expect "0.10.0 > 0.2.0 (numeric, not string) → ok" "$(run)" 0

case_; echo b >skills/x/SKILL.md; setv 0.1.9
expect "version went down → fail" "$(run)" 1

case_; setv 0.3.0
expect "manifest-only bump → ok" "$(run)" 0

"$SCRIPT" >/dev/null 2>&1; expect "no base → usage error" "$?" 2
"$SCRIPT" nope >/dev/null 2>&1; expect "unknown base → error" "$?" 2

echo
echo "check-version-bump.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
