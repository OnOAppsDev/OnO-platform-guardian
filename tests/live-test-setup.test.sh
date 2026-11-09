#!/usr/bin/env bash
# Tests for scripts/live-test-setup.sh against a local "remote" and a stub `claude` (offline).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SETUP="$HERE/../scripts/live-test-setup.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/pg-live.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
PASS=0 FAIL=0
expect() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL $1 (got $2, want $3)"; fi; }
has() { case "$2" in *"$3"*) PASS=$((PASS + 1)) ;; *) FAIL=$((FAIL + 1)); echo "FAIL $1: $2" ;; esac; }
hasnt() { case "$2" in *"$3"*) FAIL=$((FAIL + 1)); echo "FAIL $1: $2" ;; *) PASS=$((PASS + 1)) ;; esac; }

# Stub claude: version + a plugin list in the real CLI's block format.
mkdir -p "$WORK/bin"
cat >"$WORK/bin/claude" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  --version) echo "9.9.9 (Claude Code)" ;;
  plugin) printf 'Installed plugins:\n\n  ❯ ono-plugin-qa@ono-plugin-marketplace\n    Version: 1.0.0\n    Scope: user\n    Status: ✔ enabled\n\n  ❯ code-review@claude-plugins-official\n    Version: unknown\n    Status: ✔ enabled\n\n  ❯ matrix-studio@ono-plugin-marketplace\n    Version: 0.2.0\n    Scope: user\n    Status: ✘ disabled\n' ;;
esac
EOF
chmod +x "$WORK/bin/claude"
export PATH="$WORK/bin:$PATH"

# Remote with main + develop (5 commits on develop).
git init -q -b main "$WORK/remote" && echo r >"$WORK/remote/f" && git -C "$WORK/remote" add f && git -C "$WORK/remote" commit -qm c0
git -C "$WORK/remote" checkout -q -b develop
for i in 1 2 3 4; do echo "$i" >>"$WORK/remote/f" && git -C "$WORK/remote" commit -qam "c$i"; done
dev="$(git -C "$WORK/remote" rev-parse develop)"

export PG_TEST_DIR="$WORK/pg"
out="$("$SETUP" "$WORK/remote" 2>&1)"; expect "setup → exit 0" "$?" "0"
expect "app on develop" "$(git -C "$WORK/pg/app" rev-parse --abbrev-ref HEAD)" "develop"
expect "pg/clean = origin/develop" "$(git -C "$WORK/pg/app" rev-parse pg/clean)" "$dev"
expect "pg/* don't track develop (a work branch has no upstream yet)" "$(git -C "$WORK/pg/app" config branch.pg/clean.merge; git -C "$WORK/pg/app" config branch.pg/behind.merge)" ""
expect "pg/behind is 3 behind" "$(git -C "$WORK/pg/app" rev-list --count pg/behind..origin/develop)" "3"
expect "scratch has one commit" "$(git -C "$WORK/pg/scratch" rev-list --count HEAD)" "1"
expect "scratch has no remote" "$(git -C "$WORK/pg/scratch" remote | wc -l | tr -d ' ')" "0"
has "version row" "$out" "| Claude Code version | 9.9.9 (Claude Code) |"
has "ono plugins with status" "$out" "| ono-plugin-qa (enabled), matrix-studio (disabled) |"
hasnt "non-Ono plugins left out" "$out" "code-review"
has "timing row" "$out" "| 6.1 hook time (app, real remote) | "
has "run hint: plain claude, installed plugin" "$out" "Start each §1 case with:  claude   (Guardian installed"

# Re-run: reuses the clone, resets pg/* to the new remote state.
echo 5 >>"$WORK/remote/f" && git -C "$WORK/remote" commit -qam c5
"$SETUP" "$WORK/remote" >/dev/null 2>&1; expect "re-run → exit 0" "$?" "0"
expect "pg/clean follows the remote" "$(git -C "$WORK/pg/app" rev-parse pg/clean)" "$(git -C "$WORK/remote" rev-parse develop)"

# Central branch argument + missing central branch.
out="$("$SETUP" "$WORK/remote" main 2>&1)"; expect "main as central → exit 0" "$?" "0"
has "short history noted" "$out" "fewer than 4 commits"
out="$("$SETUP" "$WORK/remote" release 2>&1)"; expect "no such central → exit 1" "$?" "1"
has "missing central explained" "$out" "no origin/release"
out="$(PG_TEST_DIR="$WORK/pg2" "$SETUP" "$WORK/nope" 2>&1)"; expect "bad url → exit 1" "$?" "1"
"$SETUP" >/dev/null 2>&1; expect "no args → exit 2" "$?" "2"

# No claude on PATH → still prints the table.
out="$(PATH="/usr/bin:/bin" "$SETUP" "$WORK/remote" 2>&1)"; expect "no claude → exit 0" "$?" "0"
has "no plugins found" "$out" "| none found |"

echo "live-test-setup.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
