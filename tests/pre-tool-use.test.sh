#!/usr/bin/env bash
# Tests for hooks/pre-tool-use.sh (commit-hygiene guard) against throwaway repos.
# Needs git + jq (jq is test-only).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../hooks/pre-tool-use.sh"
ALLOW="$HERE/../routing/committed-artifacts.json"

command -v jq >/dev/null || { echo "jq is required to run the tests"; exit 1; }
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
unset PG_COMMIT_GUARD PG_ALLOWLIST PG_GUARD_DUMP_RULES CLAUDE_PLUGIN_ROOT

WORK="$(mktemp -d "${TMPDIR:-/tmp}/pg-guard.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
R="$WORK/repo"

PASS=0 FAIL=0 OUT="" ERR="" RC=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1] $2"; [ -n "$OUT" ] && echo "      got: $OUT"; }

fresh() { # fresh repo with one committed file + .gitignore
  rm -rf "$R"; mkdir -p "$R/src" "$R/sub"
  git -c init.defaultBranch=main init -q "$R"
  printf 'node_modules/\n' >"$R/.gitignore"
  echo old >"$R/tracked.md"
  git -C "$R" add -A && git -C "$R" commit -qm init
}
mk() { mkdir -p "$(dirname "$R/$1")"; printf '%s\n' "${2:-x}" >"$R/$1"; }

# run CMD [CWD] — builds the PreToolUse payload with jq (real JSON escaping).
run() {
  local payload
  payload="$(jq -cn --arg c "$1" --arg d "${2:-$R}" \
    '{session_id:"s",cwd:$d,hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c,description:"x"}}')"
  OUT="$(printf '%s' "$payload" | "$HOOK" 2>"$WORK/err")"; RC=$?
  ERR="$(cat "$WORK/err")"
}

# expect NAME none|ask|deny [must-contain] [must-not-contain]
expect() {
  local got=none
  [ "$RC" -eq 0 ] || { bad "$1" "exit $RC"; return; }
  [ -z "$ERR" ] || { bad "$1" "stderr: $ERR"; return; }
  if [ -n "$OUT" ]; then
    printf '%s' "$OUT" | jq -e '.hookSpecificOutput.hookEventName == "PreToolUse"' >/dev/null 2>&1 \
      || { bad "$1" "invalid hook JSON"; return; }
    got="$(printf '%s' "$OUT" | jq -r .hookSpecificOutput.permissionDecision)"
  fi
  [ "$got" = "$2" ] || { bad "$1" "decision $got, want $2"; return; }
  local reason; reason="$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null)"
  if [ -n "${3:-}" ]; then case "$reason" in *"$3"*) ;; *) bad "$1" "reason lacks: $3"; return ;; esac; fi
  if [ -n "${4:-}" ]; then case "$reason" in *"$4"*) bad "$1" "reason has: $4"; return ;; esac; fi
  ok
}

# --- allowlist parser agrees with jq ------------------------------------------------
want="$(jq -r '[.plugins[] | (.commit // [])[], (.neverCommit // [])[]] + .always.neverCommit | length' "$ALLOW")"
got="$(printf '{"tool_input":{"command":"git status"}}' | PG_GUARD_DUMP_RULES=1 "$HOOK" | grep -c .)"
[ "$want" = "$got" ] && ok || { OUT=""; bad "allowlist parse" "rules $got, jq says $want"; }
dump="$(printf '{"tool_input":{"command":"git status"}}' | PG_GUARD_DUMP_RULES=1 "$HOOK")"
case "$dump" in *"except	.env.example"*) ok ;; *) OUT=""; bad "allowlist parse" "negation !.env.example not parsed" ;; esac

# --- not our business ------------------------------------------------------------------
fresh
run "ls -la";                 expect "non-git command" none
run "git status";             expect "git status" none
run "git log --oneline -5";   expect "git log" none
mk notes.md
run "git add notes.md" "$WORK"; expect "outside a repo (cwd)" none

# --- add: classification --------------------------------------------------------------
fresh
mk notes.md;               run "git add notes.md";          expect "stray .md → deny" deny "notes.md"
mk src/App.swift;          run "git add src/App.swift";     expect "new source → none" none
mk .env "K=1";             run "git add .env";              expect ".env → deny" deny ".env"
mk .env.local;             run "git add .env.local";        expect ".env.local → deny" deny
mk .env.example;           run "git add .env.example";      expect ".env.example → none" none
mk sub/cert.pem;           run "git add sub/cert.pem";      expect "key at depth → deny" deny "sub/cert.pem"
mk docs/tasks/T-1.md;      run "git add docs/tasks/T-1.md"; expect "dev-plugin task doc → stays out" deny "docs/tasks/T-1.md"
mk docs/specs/login/hld.md;   run "git add docs/specs/login/hld.md";   expect "spec .md → stays out unless asked" deny
mk docs/specs/login/hld.html; run "git add docs/specs/login/hld.html"; expect "spec .html preview → deny" deny
mk AUDIT.md;               run "git add AUDIT.md";          expect "inspector AUDIT.md → stays out unless asked" deny
mk CLAUDE.md.bak;          run "git add CLAUDE.md.bak";     expect "inspector .bak → deny" deny
mk README.md;              run "git add README.md";         expect "README → none" none
mk docs/login-plan.md "$(printf -- '---\ndoc_schema_version: 1\nfeature: login\n---\n# Plan')"
run "git add docs/login-plan.md";                           expect "frontmatter planning doc → stays out" deny
mk docs/random.md "$(printf -- '---\nfeature: login\n---\n')"
run "git add docs/random.md";                               expect "frontmatter without schema → deny" deny "docs/random.md"
mk debug.log;              run "git add debug.log";         expect ".log → deny" deny

# --- 0.2.6: only code by default (any flow, not just bugs) ---
mk docs/bugs/ABC-1/plan.md; run "git add docs/bugs/ABC-1/plan.md"; expect "bug work plan → stays out" deny "docs/bugs/ABC-1/plan.md"
mk docs/bugs/ABC-1/state.json; run "git add docs/bugs/ABC-1/state.json"; expect "plugin .json → stays out" deny "state.json"
mk tool-output.json;       run "git add tool-output.json";   expect "stray .json → deny" deny "tool-output.json"
mk notes.yaml;             run "git add notes.yaml";         expect "stray .yaml → deny" deny
mk package.json;           run "git add package.json";       expect "new package.json → none" none
mk ios/App/Assets.xcassets/Icon.imageset/Contents.json; run "git add ios"; expect "Xcode Contents.json → none" none
mk tsconfig.app.json;      run "git add tsconfig.app.json";  expect "tsconfig → none" none
mk .github/workflows/ci.yml; run "git add .github";          expect "CI workflow → none" none
mk docs/specs/login/lld.md; run "PG_INCLUDE_FILES=1 git add docs/specs/login/lld.md"; expect "employee asked → included" none
mk sub/k.pem;              run "PG_INCLUDE_FILES=1 git add sub/k.pem"; expect "include never bypasses secrets" deny "sub/k.pem"
printf '{"centralBranch": "develop", "commitPaths": ["docs/specs/**", "AUDIT.md"]}\n' >"$R/.platform-guardian.json"
mk docs/specs/pay/hld.md;  run "git add docs/specs/pay/hld.md"; expect "project commitPaths → none" none
run "git add AUDIT.md";                                       expect "project commitPaths exact file → none" none
mk docs/bugs/X-2/plan.md;  run "git add docs/bugs/X-2/plan.md"; expect "not in commitPaths → still out" deny
rm -f "$R/.platform-guardian.json"

echo more >>"$R/tracked.md"
run "git add tracked.md";                                   expect "modified tracked .md → none" none

# --- add: whole-tree and mixed --------------------------------------------------------
fresh
mk src/Main.kt; mk scratch.md; mk key.p12
run "git add .";      expect "add . with secret → deny lists only the secret" deny "key.p12" "scratch.md"
rm "$R/key.p12"
run "git add -A";     expect "add -A with stray → deny" deny "scratch.md" "src/Main.kt"
run "git add --all";  expect "add --all → deny" deny
run "git add src";    expect "add src/ only → none" none
mk node_modules/x/index.js
run "git add .";      expect "ignored dir not included without -f" deny "scratch.md" "node_modules"
run "git add -f node_modules/x/index.js"; expect "add -f ignored node_modules → deny" deny "node_modules"
run "git add -p";     expect "interactive add → skipped" none

# --- command shapes --------------------------------------------------------------------
fresh
mk sub/n.md
run "cd sub && git add n.md";           expect "cd then add" deny "sub/n.md"
run "git -C sub add n.md";              expect "git -C" deny "sub/n.md"
run "git -C $R/sub add ." "$WORK";      expect "git -C absolute from outside" deny "sub/n.md"
run "git status; git add sub/n.md";     expect "after ;" deny
run "true || git add sub/n.md";         expect "after ||" deny
run "git add sub/n.md && git commit -m \"wip; more\""; expect "add && commit, quoted ; in msg" deny "sub/n.md"
run "git add 'sub/n.md'";               expect "single-quoted path" deny "sub/n.md"
run "git add \$(ls sub)";               expect "command substitution → skipped" none
mk "sp ace.md"; mk "שלום.md"; mk 'q"uote.md'
run "git add 'sp ace.md' שלום.md 'q\"uote.md'"; expect "space / unicode / quote in names" deny "sp ace.md"
case "$OUT" in *'שלום.md'*) ok ;; *) bad "unicode name in reason" "missing" ;; esac

# --- commit ------------------------------------------------------------------------------
fresh
mk plan-notes.md; git -C "$R" add plan-notes.md
run "git commit -m 'wip'";              expect "commit with staged stray" deny "plan-notes.md"
run "git commit -m \"don't stop\"";      expect "commit, apostrophe in msg" deny
git -C "$R" reset -q
mk src/A.swift; git -C "$R" add src/A.swift
run "git commit -m ok";                 expect "commit with staged source" none
git -C "$R" commit -qm ok
echo more >>"$R/tracked.md"
run "git commit -am tracked";           expect "commit -am, tracked only" none
mk id_rsa.pem; git -C "$R" add id_rsa.pem
run "git commit -m x";                  expect "commit with staged key" deny "id_rsa.pem"

# --- unborn repo (no commits yet) ------------------------------------------------------
rm -rf "$R"; mkdir -p "$R"; git -c init.defaultBranch=main init -q "$R"
mk todo.md; mk app.js
run "git add .";                        expect "unborn: add ." deny "todo.md"
git -C "$R" add todo.md
run "git commit -m first";              expect "unborn: commit" deny "todo.md"

# --- many files are truncated ----------------------------------------------------------
fresh
i=1; while [ $i -le 13 ]; do mk "n$i.md"; i=$((i + 1)); done
run "git add .";                        expect "13 strays → +3 more" deny "(+3 more)"
n="$(printf "%s" "$OUT" | grep -o "n[0-9]*\.md" | wc -l | tr -d " ")"
[ "$n" -eq 10 ] && ok || bad "truncation" "listed $n names, want 10"

# --- switches / robustness -------------------------------------------------------------
fresh; mk notes.md
OUT="$(jq -cn --arg d "$R" '{cwd:$d,tool_input:{command:"git add notes.md"}}' | PG_COMMIT_GUARD=off "$HOOK")"; RC=$?; ERR=""
expect "PG_COMMIT_GUARD=off" none
OUT="$(echo 'not json git' | "$HOOK" 2>&1)"; RC=$?; ERR=""
expect "garbage payload" none
OUT="$(jq -cn --arg d "$R" '{cwd:$d,tool_input:{command:"git add notes.md"}}' | PG_ALLOWLIST=/nope "$HOOK" 2>&1)"; RC=$?; ERR=""
expect "missing allowlist fails open" none
run "git add \"unterminated";           expect "unbalanced quote add → no crash" none

# speed: the common no-git path must be instant
start=$(date +%s)
i=0; while [ $i -lt 20 ]; do run "npm test"; i=$((i + 1)); done
[ $(( $(date +%s) - start )) -le 2 ] && ok || bad "speed" "20 non-git runs took >2s"

echo
echo "pre-tool-use.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
