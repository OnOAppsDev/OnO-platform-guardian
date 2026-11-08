#!/usr/bin/env bash
# Tests for scripts/git-status.sh against throwaway git repos.
# Usage: tests/git-status.test.sh        (needs git + jq; jq is test-only)
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../scripts/git-status.sh"

command -v jq >/dev/null || { echo "jq is required to run the tests"; exit 1; }

# Isolate from the developer's git config and identity.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
unset CLAUDE_PROJECT_DIR GIT_SSH_COMMAND PG_NO_FETCH PG_FETCH_TIMEOUT

WORK="$(mktemp -d "${TMPDIR:-/tmp}/pg-git-status.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PASS=0 FAIL=0 CASE=""
OUT=""

g() { git -c init.defaultBranch=main "$@" >/dev/null 2>&1; }

commit() { # commit <repo> <file> [msg]
  echo "$RANDOM$RANDOM" >>"$1/$2"
  g -C "$1" add "$2" && g -C "$1" commit -m "${3:-change $2}"
}

# new_remote <name> [branches...] → bare repo with main + optional extra branches.
new_remote() {
  local name="$1"; shift
  local seed="$WORK/$name-seed"
  g init "$seed"
  commit "$seed" README.md init
  for b in "$@"; do g -C "$seed" branch "$b"; done
  g clone --bare "$seed" "$WORK/$name.git"
  echo "$WORK/$name.git"
}

clone() { g clone "$1" "$WORK/$2"; echo "$WORK/$2"; }

run() { # run [env...] -- args
  OUT="$("$SCRIPT" "$@")"
  RC=$?
}

case_() { CASE="$1"; }

check() { # check <jq-boolean-expr> [description]
  if [ "$RC" -ne 0 ]; then
    FAIL=$((FAIL + 1)); echo "FAIL [$CASE] exit code $RC"; return
  fi
  if ! printf '%s' "$OUT" | jq -e . >/dev/null 2>&1; then
    FAIL=$((FAIL + 1)); echo "FAIL [$CASE] invalid JSON: $OUT"; return
  fi
  if [ "$(printf '%s' "$OUT" | jq -r "$1" 2>/dev/null)" = "true" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1)); echo "FAIL [$CASE] ${2:-$1}"; echo "      got: $OUT"
  fi
}

has_warning() { printf '(.warnings | index("%s")) != null' "$1"; }
no_warning()  { printf '(.warnings | index("%s")) == null' "$1"; }

# ---------------------------------------------------------------------------

case_ "outside git"
mkdir -p "$WORK/plain"
run "$WORK/plain"
check '.repo == false and .schema == 1'

case_ "dir not found"
run "$WORK/does-not-exist"
check ".repo == false and $(has_warning dir-not-found)"

case_ "clean feature branch, origin/HEAD = main"
R="$(new_remote basic)"
C="$(clone "$R" basic)"
g -C "$C" checkout -b feature/x
run "$C"
check '.repo == true and .branch == "feature/x" and .detached == false'
check '.fetch == "ok" and .remote == "origin"'
check '.central.branch == "main" and .central.ref == "origin/main"'
check '.central.source == "origin-head" and .central.confidence == "high"'
check '.onCentral == false and .ahead == 0 and .behind == 0'
check '.dirty == false and .changes.total == 0 and .operation == null'
check '.warnings == []' "no warnings"

case_ "on central branch"
g -C "$C" checkout main
run "$C"
check ".onCentral == true and $(has_warning on-central)"
check '.upstream.ref == "origin/main" and .upstream.ahead == 0 and .upstream.behind == 0'

case_ "dirty: staged, unstaged, untracked"
g -C "$C" checkout feature/x
echo a >"$C/staged.txt"; g -C "$C" add staged.txt
echo b >>"$C/README.md"
echo c >"$C/new.txt"
run "$C"
check '.dirty == true and .changes.staged == 1 and .changes.unstaged == 1 and .changes.untracked == 1'
check '.changes.total == 3 and (.changes.files | length) == 3 and .changes.truncated == false'
check '[.changes.files[].path] | index("new.txt") != null'
g -C "$C" reset --hard; rm -f "$C/new.txt" "$C/staged.txt"

case_ "behind central (remote advanced, fetch picks it up)"
O="$(clone "$R" basic-other)"
commit "$O" other.txt; g -C "$O" push origin main
run "$C"
check '.fetch == "ok" and .behind == 1 and .ahead == 0'
check "$(has_warning behind-central)"

case_ "PG_NO_FETCH=1 skips the fetch"
commit "$O" other2.txt; g -C "$O" push origin main
OUT="$(PG_NO_FETCH=1 "$SCRIPT" "$C")"; RC=$?
check '.fetch == "skipped" and .behind == 1' "still the last fetched count"

case_ "ahead + diverged"
run "$C"   # fetch → behind 2
commit "$C" mine.txt
run "$C"
check '.ahead == 1 and .behind == 2'
check "$(has_warning behind-central)"

case_ "ahead of upstream (unpushed commits)"
g -C "$C" push -u origin feature/x
commit "$C" mine2.txt
run "$C"
check '.upstream.ref == "origin/feature/x" and .upstream.ahead == 1 and .upstream.behind == 0'

case_ "detached HEAD"
g -C "$C" checkout --detach HEAD
run "$C"
check ".detached == true and .branch == null and (.head | length) >= 7"
check ".upstream == null and $(has_warning detached-head)"
g -C "$C" checkout feature/x

case_ "subdirectory + CLAUDE_PROJECT_DIR"
mkdir -p "$C/a/b"
OUT="$(cd / && CLAUDE_PROJECT_DIR="$C/a/b" "$SCRIPT")"; RC=$?
check ".repo == true and (.root | endswith(\"/basic\"))"
rmdir "$C/a/b" "$C/a"

case_ "origin/HEAD = main but origin/develop exists → ambiguous"
R2="$(new_remote dev develop)"
C2="$(clone "$R2" dev)"
run "$C2"
check '.central.branch == "main" and .central.confidence == "medium"'
check ".central.candidates == [\"develop\",\"main\"] and $(has_warning central-ambiguous)"

case_ "no origin/HEAD, develop + main on remote → develop, low"
g -C "$C2" remote set-head origin -d
run "$C2"
check '.central.branch == "develop" and .central.source == "develop" and .central.confidence == "low"'

case_ "no origin/HEAD, only develop on remote → develop, medium"
R3="$(new_remote donly develop)"
C3="$(clone "$R3" donly)"
# Make develop the only branch on the remote, and drop origin/HEAD.
git -C "$R3" symbolic-ref HEAD refs/heads/develop
g -C "$C3" checkout develop
g -C "$C3" branch -D main
g -C "$C3" push origin --delete main
g -C "$C3" fetch --prune origin
g -C "$C3" remote set-head origin -d
run "$C3"
check '.central.branch == "develop" and .central.confidence == "medium" and .central.candidates == ["develop"]'
check ".onCentral == true and $(no_warning central-ambiguous)"

case_ "remote exists but central branch is local-only → low"
E="$WORK/emptyremote"
g init --bare "$WORK/empty.git"; g clone "$WORK/empty.git" "$E"; commit "$E" a.txt
run "$E"
check '.central.branch == "main" and .central.ref == "main" and .central.confidence == "low"'

case_ "project override"
echo '{ "centralBranch": "develop", "team": "ios" }' >"$C2/.platform-guardian.json"
run "$C2"
check '.central.branch == "develop" and .central.source == "override" and .central.confidence == "high"'

case_ "override names a missing branch → warning + fallback"
echo '{"centralBranch":"release/9"}' >"$C2/.platform-guardian.json"
run "$C2"
check ".central.source == \"develop\" and $(has_warning override-not-found)"
rm "$C2/.platform-guardian.json"

case_ "no remote, local develop + main"
L="$WORK/local"
g init "$L"; commit "$L" a.txt; g -C "$L" branch develop
run "$L"
check '.remote == null and .fetch == "no-remote" and .upstream == null'
check '.central.branch == "develop" and .central.ref == "develop" and .central.confidence == "low"'
check "$(has_warning no-remote) and $(has_warning central-ambiguous)"
check '.onCentral == false and .ahead == 0 and .behind == 0'

case_ "no remote, no candidate branch"
L2="$WORK/local2"
g init "$L2"; g -C "$L2" checkout -b trunk; commit "$L2" a.txt
run "$L2"
check '.central.branch == null and .central.confidence == "none" and .ahead == null and .behind == null'
check "$(has_warning central-unknown)"

case_ "unborn repo (no commits)"
U="$WORK/unborn"
g init "$U"
run "$U"
check '.repo == true and .head == null and .branch == "main"'
check "$(has_warning unborn-head)"

case_ "merge conflict"
M="$WORK/merge"
g init "$M"; echo base >"$M/f"; g -C "$M" add f; g -C "$M" commit -m base
g -C "$M" checkout -b other; echo theirs >"$M/f"; g -C "$M" commit -am theirs
g -C "$M" checkout main; echo ours >"$M/f"; g -C "$M" commit -am ours
g -C "$M" merge other
run "$M"
check '.operation == "merge" and .changes.conflicted == 1'
check "$(has_warning operation-in-progress)"

case_ "fetch failure (remote gone)"
F="$(clone "$R" fetchfail)"
g -C "$F" remote set-url origin "$WORK/missing.git"
run "$F"
check ".fetch == \"failed\" and $(has_warning fetch-failed)"
check '.central.branch == "main" and .behind == 0' "still reports from cached refs"

case_ "fetch timeout (hung transport) is bounded"
T="$(clone "$R" timeout)"
g -C "$T" remote set-url origin "ssh://example.invalid/repo.git"
start=$(date +%s)
OUT="$(GIT_SSH_COMMAND='sleep 30 #' PG_FETCH_TIMEOUT=1 "$SCRIPT" "$T")"; RC=$?
elapsed=$(( $(date +%s) - start ))
check ".fetch == \"timeout\" and $(has_warning fetch-timeout)"
if [ "$elapsed" -le 4 ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL [$CASE] took ${elapsed}s"; fi

case_ "awkward paths stay valid JSON"
W="$WORK/weird"
g init "$W"; commit "$W" a.txt
touch "$W/with space.txt" "$W/quo\"te.txt" "$W/back\\slash.txt" "$W/tab	here.txt"
run "$W"
check '.changes.untracked == 4' "4 untracked, JSON parses"
touch "$W/שלום.txt" "$W/ctl$(printf '\001')x"
run "$W"
check '[.changes.files[].path] | (index("שלום.txt") != null and index("ctl\u0001x") != null)' "unicode raw, control chars escaped"
rm -f "$W/שלום.txt" "$W/ctl$(printf '\001')x"

case_ "staged rename counts once"
g -C "$W" add a.txt; g -C "$W" commit -m a 2>/dev/null
g -C "$W" mv a.txt renamed.txt
run "$W"
check '.changes.staged == 1 and ([.changes.files[] | select(.status == "R ")] | .[0].path) == "renamed.txt"'
g -C "$W" mv renamed.txt a.txt

case_ "many files → truncated list, exact counts"
for i in $(seq 1 25); do touch "$W/n$i.txt"; done
run "$W"
check '.changes.total == 29 and (.changes.files | length) == 20 and .changes.truncated == true'

# ---------------------------------------------------------------------------

echo
echo "git-status.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
