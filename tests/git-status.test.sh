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
# the employee's remembered answer lives here (protected-branch.sh answer) — never the real ~/.claude
export PG_LOG_DIR="$WORK/state"
PB="$HERE/../scripts/protected-branch.sh"

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

case_ "origin/HEAD = unusual branch (staging) while dev exists → low, ask (tester bug)"
R6="$(new_remote odd dev Back-key-on-Webos-stg)"
git -C "$R6" symbolic-ref HEAD refs/heads/Back-key-on-Webos-stg
C6="$(clone "$R6" odd)"
run "$C6"
check '.central.branch == "Back-key-on-Webos-stg" and .central.confidence == "low"'
check "(.central.candidates | index(\"dev\")) != null and (.central.candidates | index(\"Back-key-on-Webos-stg\")) != null and $(has_warning central-ambiguous)"

case_ "origin/HEAD = main, dev exists → medium ambiguous (dev counts like develop)"
R7="$(new_remote devb dev)"
C7="$(clone "$R7" devb)"
run "$C7"
check ".central.branch == \"main\" and .central.confidence == \"medium\" and $(has_warning central-ambiguous)"

case_ "thousands of commits ahead of central → suspect, low"
g -C "$C7" checkout -b feature/huge
i=0; while [ $i -lt 6 ]; do commit "$C7" big.txt; i=$((i + 1)); done
OUT="$(PG_NO_FETCH=1 PG_SUSPECT_AHEAD=5 "$SCRIPT" "$C7")"; RC=$?
check '.ahead == 6 and .central.confidence == "low"'
printf '{"centralBranch": "main"}\n' >"$C7/.platform-guardian.json"
OUT="$(PG_NO_FETCH=1 PG_SUSPECT_AHEAD=5 "$SCRIPT" "$C7")"; RC=$?
check '.central.source == "override" and .central.confidence == "high"' "an override is never second-guessed"
rm -f "$C7/.platform-guardian.json"

case_ "no origin/HEAD, develop + main on remote → develop, low"
g -C "$C2" remote set-head origin -d
# git >= 2.48 re-creates a missing origin/HEAD on fetch (followRemoteHEAD=create); keep it gone.
g -C "$C2" config remote.origin.followRemoteHEAD never
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
g -C "$C3" config remote.origin.followRemoteHEAD never
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

case_ "fast fetch doesn't wait out the timeout"
start=$(date +%s)
OUT="$(PG_FETCH_TIMEOUT=4 "$SCRIPT" "$F")"; RC=$?   # fails fast: remote path missing
elapsed=$(( $(date +%s) - start ))
check '.fetch == "failed"'
if [ "$elapsed" -le 2 ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL [$CASE] took ${elapsed}s"; fi

case_ "fetch timeout is wall-clock, not a count of sleeps (slow machine)"
# Each `sleep` costs 0.3 s here; a cap counted as 10 sleeps per second would take ~6 s instead of ~2.
mkdir -p "$WORK/slowbin"
printf '#!/bin/sh\n/bin/sleep 0.3; /bin/sleep "$@"\n' >"$WORK/slowbin/sleep"; chmod +x "$WORK/slowbin/sleep"
start=$(date +%s)
OUT="$(PATH="$WORK/slowbin:$PATH" GIT_SSH_COMMAND='/bin/sleep 30 #' PG_FETCH_TIMEOUT=2 "$SCRIPT" "$T")"; RC=$?
elapsed=$(( $(date +%s) - start ))
check ".fetch == \"timeout\""
if [ "$elapsed" -le 4 ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL [$CASE] took ${elapsed}s"; fi

case_ "Matrix QA repo → git writes blocked flag"
MQ="$(clone "$R" matrix)"
run "$MQ"
check '.guards.matrixQa == false'
mkdir -p "$MQ/qa/lld"; echo '{}' >"$MQ/matrix-qa.config.json"
printf '{"plugins":{"matrix-qa-plugin@ono-plugin-marketplace":[{}]}}' >"$WORK/mqa-installed.json"
printf '{"plugins":{"ono-plugin-qa@ono-plugin-marketplace":[{}]}}' >"$WORK/mqa-removed.json"
PG_PLUGINS_FILE="$WORK/mqa-installed.json" run "$MQ/qa/lld"
check ".guards.matrixQa == true and $(has_warning matrix-qa-git-blocked)"
PG_PLUGINS_FILE="$WORK/no-such-list.json" run "$MQ/qa/lld"
check ".guards.matrixQa == true"   # unknown plugin list → assume installed
PG_PLUGINS_FILE="$WORK/mqa-removed.json" run "$MQ/qa/lld"
check ".guards.matrixQa == false"  # plugin uninstalled → nothing blocks Claude's git writes

case_ "ono-plugin-qa: repo folder name contains qa → commit blocked"
run "$C"
check '.guards.onoQaCommitBlocked == false'
QW="$WORK/ws"; mkdir -p "$QW"
g clone "$R" "$QW/app-ios"; g clone "$R" "$QW/App-QA"
run "$QW/App-QA"
check ".guards.onoQaCommitBlocked == true and $(has_warning ono-qa-commit-blocked)"

case_ "ono-plugin-qa: qa-workspace.json is authoritative"
mkdir -p "$QW/.claude"; echo '{"qaRepoPath": "app-ios", "codeRepoPath": "x"}' >"$QW/.claude/qa-workspace.json"
run "$QW/App-QA"
check '.guards.onoQaCommitBlocked == false' "named repo is app-ios, so App-QA is not blocked"
run "$QW/app-ios"
check '.guards.onoQaCommitBlocked == true'

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

# --- main/master + develop: the history decides (Guy's report, 2026-11-24) ---
case_ "git-flow: develop has work master lacks, master nothing develop lacks → develop, high"
RG="$(new_remote gflow develop)"; CG="$(clone "$RG" gflow)"
g -C "$CG" checkout develop; commit "$CG" f.txt; commit "$CG" f.txt; g -C "$CG" push origin develop
run "$CG"
check '.central.branch == "develop" and .central.ref == "origin/develop" and .central.source == "gitflow" and .central.confidence == "high"'
check ".onCentral == true and $(no_warning central-ambiguous)" "on develop → on central, no question"
g -C "$CG" checkout -b feature/x; commit "$CG" x.txt
run "$CG"
check '.central.branch == "develop" and .ahead == 1 and .behind == 0 and .onCentral == false'

case_ "release: develop merged into master with a merge commit → develop stays central"
g -C "$CG" checkout main; g -C "$CG" merge --no-ff -m "release 1.0" develop; g -C "$CG" push origin main
g -C "$CG" checkout feature/x
run "$CG"
check '.central.branch == "develop" and .central.source == "gitflow" and .behind == 0' "a release merge on master isn't master's own work"
g -C "$CG" checkout develop; commit "$CG" f2.txt; g -C "$CG" push origin develop
run "$CG"
check '.central.branch == "develop" and .central.confidence == "high"' "…and after develop moves on"

case_ "git-flow with dev instead of develop"
RD="$(new_remote gdev dev)"; CD="$(clone "$RD" gdev)"
g -C "$CD" checkout dev; commit "$CD" f.txt; g -C "$CD" push origin dev
run "$CD"
check '.central.branch == "dev" and .central.source == "gitflow"'

case_ "master has commits of its own (stale develop, or a hotfix) → ambiguous, never master-high"
RS="$(new_remote stale develop)"; CS="$(clone "$RS" stale)"
commit "$CS" m.txt; g -C "$CS" push origin main
run "$CS"
check ".central.branch == \"main\" and .central.confidence == \"medium\" and $(has_warning central-ambiguous)"

case_ "both have their own commits → still ambiguous (the opener asks)"
g -C "$CS" checkout develop; commit "$CS" d.txt; g -C "$CS" push origin develop
run "$CS"
check ".central.branch == \"main\" and .central.confidence == \"medium\" and $(has_warning central-ambiguous)"

# --- the employee's answer, remembered on this computer ---
case_ "answered → that branch, high, no question"
eq_out="$("$PB" answer "$CS" origin/develop)"; RC=$?
OUT="{\"stored\":\"$eq_out\",\"rc\":$RC}"; RC=0
check '.stored == "develop" and .rc == 0' "origin/develop is stored as develop, and printed"
run "$CS"
check ".central.branch == \"develop\" and .central.source == \"answered\" and .central.confidence == \"high\" and $(no_warning central-ambiguous)"
OUT="{\"check\":\"$("$PB" check "$CS" | cut -f1)\"}"; RC=0
check '.check == "protected"' "protected right away, in the same session (on develop)"
"$PB" forget "$CS"
run "$CS"
check '.central.source == "answered"' "the answer survives forget (only the guess cache is dropped)"
OUT="$(PG_NO_FETCH=1 PG_SUSPECT_AHEAD=0 "$SCRIPT" "$CS")"; RC=$?
check '.central.source == "answered" and .central.confidence == "high"' "an answer is never second-guessed as suspect"

case_ "a name that isn't a branch here is refused, the earlier answer kept"
"$PB" answer "$CS" release/nope >/dev/null; r1=$?
"$PB" answer "$CS" "bad..name" >/dev/null; r2=$?
OUT="{\"r1\":$r1,\"r2\":$r2,\"kept\":\"$("$PB" answered "$CS")\"}"; RC=0
check '.r1 == 1 and .r2 == 1 and .kept == "develop"'

case_ "the team's .platform-guardian.json wins over the local answer"
printf '{"centralBranch": "main"}\n' >"$CS/.platform-guardian.json"
run "$CS"
check '.central.branch == "main" and .central.source == "override"'
rm -f "$CS/.platform-guardian.json"

case_ "answers are per repo"
RP="$(new_remote other2 develop)"; CP="$(clone "$RP" other2)"
commit "$CP" m.txt; g -C "$CP" push origin main    # ambiguous on its own
run "$CP"
check ".central.source != \"answered\" and $(has_warning central-ambiguous)" "another repo doesn't get CS's answer"

case_ "an answered branch that was deleted since → ignored, normal detection"
g -C "$CS" checkout -b team/main2; g -C "$CS" push origin team/main2
"$PB" answer "$CS" team/main2 >/dev/null
g -C "$CS" checkout develop; g -C "$CS" branch -D team/main2; g -C "$CS" push origin --delete team/main2; g -C "$CS" fetch --prune origin
run "$CS"
check ".central.source != \"answered\" and $(has_warning central-ambiguous)"

# ---------------------------------------------------------------------------

echo
echo "git-status.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
