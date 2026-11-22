#!/usr/bin/env bash
# Tests for scripts/protected-branch.sh + hooks/write-guard.sh (+ the central-branch cache that
# hooks/session-start.sh writes) against throwaway repos. Needs git + jq (jq is test-only).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
PB="$HERE/../scripts/protected-branch.sh"
WG="$HERE/../hooks/write-guard.sh"
SS="$HERE/../hooks/session-start.sh"

command -v jq >/dev/null || { echo "jq is required to run the tests"; exit 1; }
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 PG_NO_FETCH=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
unset CLAUDE_PLUGIN_ROOT CLAUDE_PROJECT_DIR PG_WRITE_GUARD

WORK="$(mktemp -d "${TMPDIR:-/tmp}/pg-write.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
export PG_LOG_DIR="$WORK/state" PG_REVIEWS=off

PASS=0 FAIL=0
ok()   { PASS=$((PASS + 1)); }
fail() { FAIL=$((FAIL + 1)); echo "FAIL [$1]"; [ -n "${2:-}" ] && printf '      got: %s\n' "$2"; }
eq()   { [ "$2" = "$3" ] && ok || fail "$1" "$2 (want $3)"; }

R="$WORK/app"
fresh() {
  rm -rf "$R" "$WORK/origin.git"; mkdir -p "$R"
  git -c init.defaultBranch=main init -q "$R"; echo a >"$R/a.txt"; printf 'build/\n' >"$R/.gitignore"
  git -C "$R" add -A; git -C "$R" commit -qm init
  "$PB" forget "$R"
}
# wg TOOL PATH [CWD] → DEC (deny | none | invalid | stderr)
wg() {
  local key=file_path payload
  [ "$1" = NotebookEdit ] && key=notebook_path
  payload="$(jq -cn --arg t "$1" --arg p "$2" --arg d "${3:-$R}" --arg k "$key" \
    '{hook_event_name:"PreToolUse", tool_name:$t, cwd:$d, tool_input:({($k):$p, content:"x"})}')"
  OUT="$(printf '%s' "$payload" | "$WG" 2>"$WORK/err")"
  if [ -s "$WORK/err" ]; then DEC=stderr
  elif [ -z "$OUT" ]; then DEC=none
  elif printf '%s' "$OUT" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; then DEC=deny
  else DEC=invalid; fi
}
check() { "$PB" check "$R" | cut -f1; }

# --- protected-branch.sh ---
fresh
eq "main → protected" "$(check)" protected
git -C "$R" switch -q -c master; eq "master → protected" "$(check)" protected
git -C "$R" switch -q -c develop; eq "develop, central unknown → ok" "$(check)" ok
"$PB" remember "$R" develop;      eq "develop, central cached → protected" "$(check)" protected
"$PB" forget "$R";                eq "cache dropped → ok again" "$(check)" ok
printf '{"centralBranch": "develop", "commitPaths": []}\n' >"$R/.platform-guardian.json"
eq "develop, centralBranch recorded → protected" "$(check)" protected
"$PB" remember "$R" main;         eq "recorded centralBranch wins over the cache" "$(check)" protected
rm -f "$R/.platform-guardian.json"; "$PB" forget "$R"
git -C "$R" switch -q -c feature/x; eq "work branch → ok" "$(check)" ok
"$PB" is main "$R" && ok || fail "is main"
"$PB" is feature/x "$R" && fail "is feature/x" || ok
"$PB" is "" "$R" && fail "is empty name" || ok
git -C "$R" switch -q --detach; eq "detached HEAD → ok" "$(check)" ok
eq "not a git repo → skip" "$("$PB" check "$WORK" | cut -f1)" skip
[ -z "$(find "$R" -name 'central-*')" ] && ok || fail "cache never written inside the repo"

# --- write-guard.sh ---
fresh
wg Write "$R/src/New.swift";            eq "main: Write in repo → deny" "$DEC" deny
case "$OUT" in *'`main`'*"git switch -c"*) ok ;; *) fail "deny names the branch and the way out" "$OUT" ;; esac
wg Edit "a.txt";                        eq "main: Edit, relative path → deny" "$DEC" deny
wg NotebookEdit "$R/n.ipynb";           eq "main: NotebookEdit → deny" "$DEC" deny
wg Write "$R/deep/new/dir/f.md";        eq "main: file in a folder that doesn't exist yet → deny" "$DEC" deny
wg Write "$R/build/out.txt";            eq "main: git-ignored file → none" "$DEC" none
wg Write "$WORK/outside.txt";           eq "main: file outside any repo → none" "$DEC" none
wg Read "$R/a.txt";                     eq "other tools → none" "$DEC" none
git -C "$R" switch -q -c feature/x
wg Write "$R/src/New.swift";            eq "work branch → none" "$DEC" none
git -C "$R" switch -q -c develop
wg Write "$R/src/New.swift";            eq "develop, central unknown → none" "$DEC" none
"$PB" remember "$R" develop
wg Write "$R/src/New.swift";            eq "develop, central certain → deny" "$DEC" deny
# the repo of the FILE decides, not the session folder
O="$WORK/other"; git -c init.defaultBranch=main init -q "$O"; git -C "$O" commit -q --allow-empty -m i
git -C "$R" switch -q feature/x
wg Write "$O/x.swift" "$R";             eq "file in another repo on main → deny" "$DEC" deny
wg Write "$R/x.swift" "$O";             eq "file in this repo on a work branch, cwd elsewhere → none" "$DEC" none
OUT="$(jq -cn --arg p "$R/a.txt" '{tool_name:"Write",tool_input:{file_path:$p}}' | PG_WRITE_GUARD=off "$WG")"
eq "PG_WRITE_GUARD=off → none" "${OUT:-none}" none
OUT="$(echo 'not json' | "$WG" 2>&1)";  eq "garbage payload → none" "${OUT:-none}" none

# review fixes: case-insensitive names, a brand-new project, ~/.claude, the QA plugins' repos
git -C "$R" switch -q -c Mainline; eq "Mainline isn't main" "$(check)" ok
"$PB" is Main "$R" && ok || fail "is Main (macOS: same ref as main)"
"$PB" is MASTER "$R" && ok || fail "is MASTER"
N="$WORK/newp"; git -c init.defaultBranch=main init -q "$N"
wg Write "$N/README.md" "$N";           eq "brand-new project (no commits) on main → none" "$DEC" none
git -C "$N" commit -q --allow-empty -m i
wg Write "$N/README.md" "$N";           eq "…after the first commit → deny" "$DEC" deny
H="$WORK/home"; mkdir -p "$H/.claude/projects"; git -c init.defaultBranch=main init -q "$H"; git -C "$H" commit -q --allow-empty -m i
OUT="$(jq -cn --arg p "$H/.claude/projects/m.md" '{tool_name:"Write",tool_input:{file_path:$p}}' | HOME="$H" "$WG")"
eq "home folder is a repo on main: ~/.claude/… → none" "${OUT:-none}" none
QW="$WORK/qaws"; mkdir -p "$QW/.claude"
for r in yes-app yes-app-qa; do git -c init.defaultBranch=main init -q "$QW/$r"; git -C "$QW/$r" commit -q --allow-empty -m i; done
wg Write "$QW/yes-app-qa/login/test-plan.md" "$QW"; eq "ono-plugin-qa: QA repo (auto-detect) on main → none" "$DEC" none
wg Write "$QW/yes-app/src/A.swift" "$QW";           eq "…its code repo on main → deny" "$DEC" deny
printf '{"codeRepoPath": "%s/yes-app", "qaRepoPath": "%s/yes-app"}\n' "$QW" "$QW" >"$QW/.claude/qa-workspace.json"
wg Write "$QW/yes-app-qa/login/test-plan.md" "$QW"; eq "qa-workspace.json names another repo → deny" "$DEC" deny
printf '{"codeRepoPath": "%s/yes-app", "qaRepoPath": "%s/yes-app-qa"}\n' "$QW" "$QW" >"$QW/.claude/qa-workspace.json"
wg Write "$QW/yes-app-qa/login/test-plan.md" "$QW"; eq "qa-workspace.json names it → none" "$DEC" none
git -C "$R" switch -q main; echo '{}' >"$R/matrix-qa.config.json"
wg Write "$R/qa/lld/login.md";          eq "matrix-qa: qa/ next to matrix-qa.config.json → none" "$DEC" none
wg Write "$R/src/login.ts";             eq "…the web app's own code → deny" "$DEC" deny
rm -f "$R/matrix-qa.config.json"
# Claude starting the inspector through a tool
st() { # st TOOL KEY VALUE
  OUT="$(jq -cn --arg t "$1" --arg k "$2" --arg v "$3" --arg d "$R" '{tool_name:$t, cwd:$d, tool_input:{($k):$v}}' | "$WG")"
  DEC=none; [ -n "$OUT" ] && DEC=deny
}
st Skill skill ono-project-inspector:inspect;            eq "main: Skill starts the inspector → deny" "$DEC" deny
st Skill skill ono-project-inspector:project-analysis;   eq "main: an inspector skill → deny" "$DEC" deny
st Agent subagent_type ono-project-inspector:project-inspector; eq "main: inspector agent → deny" "$DEC" deny
st SlashCommand command "/ono-project-inspector:inspect"; eq "main: SlashCommand inspector → deny" "$DEC" deny
st Skill skill ono-project-inspector:inspect-status;     eq "main: read-only inspect-status → none" "$DEC" none
st Skill skill ono-mobile-dev-plugin:analyze-bug;        eq "main: another plugin's skill → none (its writes are guarded)" "$DEC" none
git -C "$R" switch -q feature/x
st Skill skill ono-project-inspector:inspect;            eq "work branch: inspector → none" "$DEC" none

# the cache: one file per repo (no two paths share one)
A="$WORK/x/a/b_c"; B="$WORK/x/a/b/c"
for r in "$A" "$B"; do mkdir -p "$r"; git -c init.defaultBranch=develop init -q "$r"; git -C "$r" commit -q --allow-empty -m i; done
"$PB" remember "$A" develop
"$PB" is develop "$A" && ok || fail "cache: remembered repo"
"$PB" is develop "$B" && fail "cache: a look-alike path shares the file" || ok
# a big Write stays fast (the payload body is never walked)
big="$(head -c 2000000 /dev/zero | tr '\0' x)"
start=$(date +%s)
OUT="$(jq -cn --arg p "$R/big.txt" --arg c "$big" --arg d "$R" '{tool_name:"Write",cwd:$d,tool_input:{file_path:$p,content:$c}}' | "$WG")"
[ $(( $(date +%s) - start )) -le 3 ] && ok || fail "speed: a 2 MB Write took >3s"

# speed: runs before every file write — the common case is a work branch
git -C "$R" switch -q feature/x
start=$(date +%s); i=0
while [ $i -lt 10 ]; do wg Write "$R/src/New.swift"; i=$((i + 1)); done
[ $(( $(date +%s) - start )) -le 3 ] && ok || fail "speed: 10 writes took >3s"

# --- session-start caches the central branch only when detection is certain ---
fresh; git -C "$R" switch -q -c develop
git clone -q --bare "$R" "$WORK/origin.git"; git -C "$R" remote add origin "$WORK/origin.git"; git -C "$R" fetch -q origin
git -C "$R" remote set-head origin develop >/dev/null 2>&1
CLAUDE_PROJECT_DIR="$R" PG_ONBOARDING=off "$SS" </dev/null >/dev/null 2>&1
eq "session start, origin/HEAD = develop → develop protected" "$(check)" protected
"$PB" remember "$R" develop
git -C "$R" remote set-head origin -d >/dev/null 2>&1; git -C "$R" branch -q -D main 2>/dev/null
git -C "$R" push -q origin --delete main 2>/dev/null; git -C "$R" fetch -q --prune origin
git -C "$R" branch -q staging; git -C "$R" push -q origin staging 2>/dev/null; git -C "$R" fetch -q origin
git -C "$R" remote set-head origin staging >/dev/null 2>&1
CLAUDE_PROJECT_DIR="$R" PG_ONBOARDING=off "$SS" </dev/null >/dev/null 2>&1
eq "session start, central uncertain → cache dropped" "$(check)" ok

echo
echo "protected-branch.sh + write-guard.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
