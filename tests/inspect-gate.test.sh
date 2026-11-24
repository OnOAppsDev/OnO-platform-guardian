#!/usr/bin/env bash
# Tests for scripts/inspect-status.sh + hooks/inspect-gate.sh against throwaway repos.
# Needs git + jq (jq is test-only).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ST="$HERE/../scripts/inspect-status.sh"
GATE="$HERE/../hooks/inspect-gate.sh"

command -v jq >/dev/null || { echo "jq is required to run the tests"; exit 1; }
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 PG_NO_FETCH=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
unset CLAUDE_PLUGIN_ROOT CLAUDE_PROJECT_DIR PG_INSPECT_GATE PG_TODAY

WORK="$(mktemp -d "${TMPDIR:-/tmp}/pg-inspect.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
export PG_LOG_DIR="$WORK/state"
# hermetic: an installed inspector, no user settings (the machine's own lists never leak in)
mkdir -p "$WORK/claude"; export PG_CLAUDE_DIR="$WORK/claude" PG_PLUGINS_FILE="$WORK/claude/installed.json"
printf '{"version":2,"plugins":{"ono-project-inspector@ono-plugin-marketplace":[{"version":"0.11.2"}]}}\n' >"$PG_PLUGINS_FILE"

PASS=0 FAIL=0
ok()   { PASS=$((PASS + 1)); }
fail() { FAIL=$((FAIL + 1)); echo "FAIL [$1]"; [ -n "${2:-}" ] && printf '      got: %s\n' "$2"; }
eq()   { [ "$2" = "$3" ] && ok || fail "$1" "$2 (want $3)"; }

R="$WORK/app"
fresh() {
  rm -rf "$R" "$WORK/origin.git"; mkdir -p "$R"
  git -c init.defaultBranch=develop init -q "$R"; echo a >"$R/a.txt"
  git -C "$R" add -A; git -C "$R" commit -qm init
}
inspect_files() { # inspect_files [skip-file]
  mkdir -p "$R/docs/project"
  printf '# AUDIT.md\n\n| # | Status | Topic | x | y |\n' >"$R/AUDIT.md"; echo c >"$R/CLAUDE.md"
  for p in overview components patterns integrations capabilities; do echo d >"$R/docs/project/$p.md"; done
  [ -n "${1:-}" ] && rm -f "$R/$1"
  return 0
}
status() { "$ST" check "$R" | cut -f1; }

# --- status ---
fresh;                      eq "never inspected → missing" "$(status)" missing
inspect_files;              eq "all stage 1–2 files → done" "$(status)" done
inspect_files docs/project/patterns.md
out="$("$ST" check "$R")";  eq "a doc missing → partial" "${out%%	*}" partial
case "$out" in *docs/project/patterns.md*) ok ;; *) fail "partial names the missing file" "$out" ;; esac
inspect_files docs/project/capabilities.md
out="$("$ST" check "$R")";  eq "older knowledge model (no capabilities.md) → still done" "${out%%	*}" done
case "$out" in *"refresh-recommended: docs/project/capabilities.md"*) ok ;; *) fail "done carries the refresh hint" "$out" ;; esac
fresh; echo "# Audit" >"$R/AUDIT.md"; echo c >"$R/CLAUDE.md"
eq "someone else's AUDIT.md doesn't count" "$(status)" missing
fresh; printf '{"centralBranch": "develop", "inspectRequired": false}\n' >"$R/.platform-guardian.json"
eq "inspectRequired false → exempt" "$(status)" exempt
eq "not a git repo → skip" "$("$ST" check "$WORK" | cut -f1)" skip

# central has it, this branch doesn't
fresh; git -C "$R" switch -q -c feature/old; git -C "$R" switch -q develop
inspect_files; git -C "$R" add -A; git -C "$R" commit -qm inspect
git clone -q --bare "$R" "$WORK/origin.git"; git -C "$R" remote add origin "$WORK/origin.git"; git -C "$R" fetch -q origin
git -C "$R" remote set-head origin develop >/dev/null 2>&1
git -C "$R" switch -q feature/old
out="$("$ST" check "$R")";  eq "central has it → on-central" "${out%%	*}" on-central
case "$out" in *origin/develop*) ok ;; *) fail "on-central names the ref" "$out" ;; esac

# nested project folder (yestvos/YesTVOS/): the inspection lives in a subfolder of the git root
fresh; mkdir -p "$R/App/docs/project" "$R/App/.ono" "$R/App/Sources"
printf '# AUDIT.md\n' >"$R/App/AUDIT.md"; echo c >"$R/App/CLAUDE.md"; echo '{}' >"$R/App/.ono/state.json"
for p in overview components patterns integrations capabilities; do echo d >"$R/App/docs/project/$p.md"; done
eq "nested: session in the project folder → done" "$("$ST" check "$R/App" | cut -f1)" done
eq "nested: session deeper inside → done" "$("$ST" check "$R/App/Sources" | cut -f1)" done
eq "nested: session at the git root, one inspected subfolder → done" "$("$ST" check "$R" | cut -f1)" done
eq "nested: root reports the project folder" "$(basename "$("$ST" root "$R/App/Sources")")" App
rm "$R/App/docs/project/overview.md"
out="$("$ST" check "$R/App")"; eq "nested: missing doc → partial" "${out%%	*}" partial
fresh; mkdir -p "$R/A/.ono" "$R/B/.ono"; printf '# AUDIT.md\n' >"$R/A/AUDIT.md"; printf '# AUDIT.md\n' >"$R/B/AUDIT.md"
echo '{}' >"$R/A/.ono/state.json"; echo '{}' >"$R/B/.ono/state.json"
eq "two inspected subfolders, session at root → not guessed (missing)" "$("$ST" check "$R" | cut -f1)" missing

# elsewhere: a complete current-model inspection on another remote branch (FYI)
fresh
git -C "$R" switch -q -c feature/inspect-v2; inspect_files; git -C "$R" add -A; git -C "$R" commit -qm "inspect v2"
git -C "$R" switch -q develop
git clone -q --bare "$R" "$WORK/origin2.git"; git -C "$R" remote add origin "$WORK/origin2.git"; git -C "$R" fetch -q origin
eq "elsewhere finds the branch with the inspection" "$("$ST" elsewhere "$R")" "origin/feature/inspect-v2"
git -C "$R" switch -q feature/inspect-v2; rm -f "$R/docs/project/capabilities.md"; git -C "$R" commit -qam "older model"; git -C "$R" push -q origin feature/inspect-v2 2>/dev/null; git -C "$R" fetch -q origin
git -C "$R" switch -q develop
eq "older-model inspection elsewhere doesn't count" "$("$ST" elsewhere "$R")" ""
eq "no remote → nothing" "$(cd "$WORK" && mkdir -p lone && git -c init.defaultBranch=main init -q lone && "$ST" elsewhere "$WORK/lone")" ""
rm -rf "$WORK/origin2.git" "$WORK/lone"
# one cat-file call for all branches: the right branch among several, and a nested project folder
fresh; mkdir -p "$R/App"; printf '# AUDIT.md\n' >"$R/App/AUDIT.md"; git -C "$R" add -A; git -C "$R" commit -qm app
for b in a-old b-partial c-full d-newest-partial; do git -C "$R" switch -q -c "feature/$b" develop; done
git -C "$R" switch -q feature/c-full; mkdir -p "$R/App/docs/project"
for p in overview capabilities; do echo d >"$R/App/docs/project/$p.md"; done; git -C "$R" add -A; git -C "$R" commit -qm full
git -C "$R" switch -q feature/d-newest-partial; mkdir -p "$R/App/docs/project"; echo d >"$R/App/docs/project/overview.md"
git -C "$R" add -A; git -C "$R" commit -qm partial; git -C "$R" switch -q develop
git clone -q --bare "$R" "$WORK/origin3.git"; git -C "$R" remote add origin "$WORK/origin3.git"; git -C "$R" fetch -q origin
eq "elsewhere: nested folder, newest complete branch among several" "$("$ST" elsewhere "$R/App")" "origin/feature/c-full"
rm -rf "$WORK/origin3.git"

# override: today only
fresh
eq "override recorded" "$(PG_TODAY=2026-11-15 "$ST" override "$R" | cut -f1)" override
eq "override valid today" "$(PG_TODAY=2026-11-15 "$ST" check "$R" | cut -f1)" override
eq "override gone tomorrow" "$(PG_TODAY=2026-11-16 "$ST" check "$R" | cut -f1)" missing
[ -z "$(find "$R" -name 'inspect-override*')" ] && ok || fail "override never written inside the repo"
rm -rf "$PG_LOG_DIR"

# --- gate ---
# gate EVENT TEXT [SESSION] → sets OUT, DEC (block | context | none)
gate() {
  local key=user_prompt payload
  [ "$1" = UserPromptExpansion ] && key=prompt
  payload="$(jq -cn --arg e "$1" --arg t "$2" --arg s "${3:-s1}" --arg d "$R" --arg k "$key" \
    '{hook_event_name:$e, session_id:$s, cwd:$d} + {($k):$t}')"
  OUT="$(printf '%s' "$payload" | "$GATE" 2>"$WORK/err")"; RC=$?
  if [ -s "$WORK/err" ]; then DEC="stderr"; return; fi
  if [ -z "$OUT" ]; then DEC=none
  elif printf '%s' "$OUT" | jq -e '.decision == "block"' >/dev/null 2>&1; then DEC=block
  elif printf '%s' "$OUT" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1; then DEC=context
  else DEC="invalid"; fi
}

fresh
gate UserPromptSubmit "hi";                         eq "missing: plain message blocked" "$DEC" block
reason="$(printf '%s' "$OUT" | jq -r .reason)"
case "$reason" in *"⛔"*"/ono-project-inspector:inspect"*"I have manager approval to work without inspect"*) ok ;; *) fail "banner: red, command, sentence" "$reason" ;; esac
gate UserPromptSubmit "fix bug YEA-1";              eq "missing: task blocked" "$DEC" block
# Bun missing → the banner says to install it first, with this OS's command
printf '#!/bin/sh\necho 1.2.0\n' >"$WORK/bun"; chmod +x "$WORK/bun"
PG_BUN=pg-no-such-bun PG_OS=MINGW64_NT-10.0 gate UserPromptSubmit "hi"
case "$(printf '%s' "$OUT" | jq -r .reason)" in *"First install Bun"*'powershell -c "irm bun.sh/install.ps1 | iex"'*"Ask IT"*"/ono-project-inspector:inspect"*) ok ;; *) fail "no Bun on Windows → the inspector PowerShell line + no-admin hint before inspect" "$OUT" ;; esac
PG_BUN=pg-no-such-bun PG_OS=Darwin gate UserPromptSubmit "hi"
case "$(printf '%s' "$OUT" | jq -r .reason)" in *"brew install oven-sh/bun/bun"*) ok ;; *) fail "no Bun on macOS → brew line" "$OUT" ;; esac
PG_BUN="$WORK/bun" gate UserPromptSubmit "hi"
case "$(printf '%s' "$OUT" | jq -r .reason)" in *"Bun"*) fail "Bun present → no Bun line" "$OUT" ;; *) ok ;; esac
gate UserPromptExpansion "/ono-mobile-dev-plugin:analyze-bug YEA-1"; eq "Ono plugin command blocked" "$DEC" block
gate UserPromptExpansion "/analyze-bug YEA-1";      eq "short Ono command blocked" "$DEC" block
gate UserPromptExpansion "/clear";                  eq "built-in /clear allowed" "$DEC" none
gate UserPromptExpansion "/plugin";                 eq "built-in /plugin allowed" "$DEC" none
gate UserPromptExpansion "/platform-guardian:onboarding"; eq "Guardian's own command allowed" "$DEC" none
gate UserPromptSubmit "I have manager approval"      ; eq "partial sentence still blocked" "$DEC" block
gate UserPromptExpansion "/ono-project-inspector:inspect" s2; eq "inspector allowed" "$DEC" none
gate UserPromptSubmit "1" s2;                       eq "then answers to the inspector flow (same session)" "$DEC" none
gate UserPromptSubmit "1" s3;                       eq "…but not in another session" "$DEC" block
gate UserPromptSubmit "  I have Manager approval to work without inspect. " s4; eq "sentence (case/space/punct) → allowed" "$DEC" context
case "$(printf '%s' "$OUT" | jq -r .hookSpecificOutput.additionalContext)" in *"manager"*) ok ;; *) fail "context tells Claude" "$OUT" ;; esac
gate UserPromptSubmit "fix bug YEA-1" s5;           eq "override holds for the day, new session too" "$DEC" none
rm -rf "$PG_LOG_DIR"
gate UserPromptSubmit "יש לי אישור מנהל לעבוד בלי inspect" s6; eq "Hebrew sentence → allowed" "$DEC" context
rm -rf "$PG_LOG_DIR"

inspect_files docs/project/overview.md
gate UserPromptSubmit "hi";                         eq "partial: blocked" "$DEC" block
case "$(printf '%s' "$OUT" | jq -r .reason)" in *"started but not finished"*) ok ;; *) fail "partial banner" "$OUT" ;; esac
inspect_files
gate UserPromptSubmit "hi";                         eq "done: allowed, silent" "$DEC" none
inspect_files docs/project/capabilities.md
gate UserPromptSubmit "hi";                         eq "older knowledge model: NOT blocked (tester bug)" "$DEC" none
fresh
OUT="$(printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","user_prompt":"hi"}' "$R" | PG_INSPECT_GATE=off "$GATE")"
eq "PG_INSPECT_GATE=off" "$OUT" ""
OUT="$(printf 'garbage' | "$GATE" 2>&1)"; RC=$?
eq "garbage payload fails open (exit 0)" "$RC" 0
OUT="$(printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"hi"}' "$R" | "$GATE")"
printf '%s' "$OUT" | jq -e '.decision == "block"' >/dev/null && ok || fail "older 'prompt' field also read" "$OUT"

# the live UserPromptExpansion envelope (pinned by another plugin's live drill)
fresh
OUT="$(printf '{"session_id":"x","cwd":"%s","hook_event_name":"UserPromptExpansion","expansion_type":"slash_command","command_name":"ono-mobile-dev-plugin:analyze-bug","command_args":"YEA-1","command_source":"plugin","prompt":"/ono-mobile-dev-plugin:analyze-bug YEA-1"}' "$R" | "$GATE")"
printf '%s' "$OUT" | jq -e '.decision == "block"' >/dev/null && ok || fail "live envelope: plugin command blocked" "$OUT"
OUT="$(printf '{"session_id":"x","cwd":"%s","hook_event_name":"UserPromptExpansion","command_name":"ono-project-inspector:inspect","command_args":"","command_source":"plugin"}' "$R" | "$GATE")"
eq "live envelope without prompt: inspector via command_name allowed" "$OUT" ""

# --- protected branches: the inspector writes files → a work branch first ---
PB="$HERE/../scripts/protected-branch.sh"
reason() { printf '%s' "$OUT" | jq -r .reason; }
fresh; git -C "$R" branch -q -m main; rm -rf "$PG_LOG_DIR"
gate UserPromptSubmit "hi" p1;                      eq "main, not inspected: blocked" "$DEC" block
case "$(reason)" in *"protected branch"*"1."*"! git switch -c chore/project-inspection"*"2."*"/ono-project-inspector:inspect"*) ok ;; *) fail "banner: ① work branch ② inspect" "$(reason)" ;; esac
gate UserPromptExpansion "/ono-project-inspector:inspect" p1; eq "main: inspector blocked" "$DEC" block
case "$(reason)" in *"CREATE A WORK BRANCH FIRST"*"git switch -c"*) ok ;; *) fail "inspector-on-main banner" "$(reason)" ;; esac
gate UserPromptSubmit "1" p1;                       eq "…and the session isn't opened by the refused inspector" "$DEC" block
gate UserPromptExpansion "/ono-project-inspector:inspect-status" p1; eq "main: read-only inspect-status allowed" "$DEC" none
gate UserPromptSubmit "! git switch -c chore/project-inspection" p1; eq "branch command (with !) → allowed" "$DEC" context
case "$(printf '%s' "$OUT" | jq -r .hookSpecificOutput.additionalContext)" in *"exactly"*"git switch -c chore/project-inspection"*"run nothing"*) ok ;; *) fail "context: exactly that command, or nothing" "$OUT" ;; esac
gate UserPromptSubmit "git checkout -b feature/inspect main" p1; eq "checkout -b with a real start point → allowed" "$DEC" context
gate UserPromptSubmit "git switch -c x then/implement/the/login/screen" p1; eq "start point that isn't a commit → blocked" "$DEC" block
gate UserPromptSubmit "git switch -c x
implement the login screen" p1;                     eq "branch command + a second line → blocked" "$DEC" block
gate UserPromptSubmit "git merge origin/develop" p1; eq "merge, not on-central → blocked" "$DEC" block
gate UserPromptSubmit "git switch -c main" p1;     eq "branch command to a protected name → blocked" "$DEC" block
gate UserPromptSubmit "git switch -c x; rm -rf ." p1; eq "branch command + more → blocked" "$DEC" block
gate UserPromptSubmit 'git switch -c $(whoami)' p1; eq "branch command with substitution → blocked" "$DEC" block
gate UserPromptSubmit "git switch -c x y z" p1;    eq "branch command, extra args → blocked" "$DEC" block
gate UserPromptSubmit "git switch -c x --force" p1; eq "branch command, extra flag → blocked" "$DEC" block
gate UserPromptSubmit "please create branch x" p1; eq "plain-language branch request → still blocked" "$DEC" block
git -C "$R" switch -q -c chore/project-inspection
gate UserPromptSubmit "hi" p2;                      eq "work branch, not inspected: blocked" "$DEC" block
case "$(reason)" in *"protected branch"*) fail "work branch: no branch step" "$(reason)" ;; *) ok ;; esac
gate UserPromptExpansion "/ono-project-inspector:inspect" p2; eq "work branch: inspector allowed" "$DEC" none
gate UserPromptSubmit "1" p2;                       eq "…then the inspector flow flows" "$DEC" none
# develop as the certain central branch
fresh; rm -rf "$PG_LOG_DIR"
gate UserPromptExpansion "/ono-project-inspector:inspect" p3; eq "develop, central unknown: inspector allowed" "$DEC" none
rm -rf "$PG_LOG_DIR"; printf '{"centralBranch": "develop"}\n' >"$R/.platform-guardian.json"
gate UserPromptExpansion "/ono-project-inspector:inspect" p4; eq "develop recorded as central: inspector blocked" "$DEC" block
gate UserPromptSubmit "hi" p4
case "$(reason)" in *'`develop`, a protected branch'*) ok ;; *) fail "develop banner names the branch" "$(reason)" ;; esac
# refresh (inspected, older model) on central → still blocked; on a work branch → allowed
rm -f "$R/.platform-guardian.json"; git -C "$R" branch -q -m main; inspect_files docs/project/capabilities.md; rm -rf "$PG_LOG_DIR"
gate UserPromptSubmit "hi" p5;                      eq "main, inspected (older model): messages allowed" "$DEC" none
gate UserPromptExpansion "/ono-project-inspector:inspect" p5; eq "main, inspected: refresh blocked" "$DEC" block
git -C "$R" switch -q -c chore/refresh
gate UserPromptExpansion "/ono-project-inspector:inspect" p5; eq "work branch, inspected: refresh allowed" "$DEC" none
# on-central: the banner's own `git merge <central ref>` is let through, nothing else
fresh; git -C "$R" switch -q -c feature/old; git -C "$R" switch -q develop
inspect_files; git -C "$R" add -A; git -C "$R" commit -qm inspect
git clone -q --bare "$R" "$WORK/origin.git"; git -C "$R" remote add origin "$WORK/origin.git"; git -C "$R" fetch -q origin
git -C "$R" remote set-head origin develop >/dev/null 2>&1; git -C "$R" switch -q feature/old; rm -rf "$PG_LOG_DIR"
gate UserPromptSubmit "hi" oc1;                    eq "on-central: blocked" "$DEC" block
gate UserPromptSubmit "! git merge origin/develop" oc1; eq "on-central: the banner's exact merge → allowed" "$DEC" context
gate UserPromptSubmit "git merge origin/develop && rm -rf ." oc1; eq "on-central: merge + more → blocked" "$DEC" block
gate UserPromptSubmit "git merge origin/feature/old" oc1; eq "on-central: merge of another branch → blocked" "$DEC" block

# the inspector missing / turned off → the banner says how to get it, and the gate stays shut
fresh; git -C "$R" switch -q -c feature/x; rm -rf "$PG_LOG_DIR"
printf '{"version":2,"plugins":{}}\n' >"$WORK/claude/none.json"
PG_PLUGINS_FILE="$WORK/claude/none.json" gate UserPromptSubmit "hi" p6
case "$(reason)" in *"/plugin install ono-project-inspector@ono-plugin-marketplace"*) ok ;; *) fail "not installed: install line" "$(reason)" ;; esac
PG_PLUGINS_FILE="$WORK/claude/none.json" gate UserPromptSubmit "/ono-project-inspector:inspect" p6
eq "not installed: inspector command blocked" "$DEC" block
PG_PLUGINS_FILE="$WORK/claude/none.json" gate UserPromptSubmit "1" p6
eq "…and the session isn't opened" "$DEC" block
printf '{"enabledPlugins":{"ono-project-inspector@ono-plugin-marketplace": false}}\n' >"$WORK/claude/settings.json"
gate UserPromptSubmit "hi" p7
case "$(reason)" in *"turn the inspector on"*) ok ;; *) fail "disabled: enable line" "$(reason)" ;; esac
mkdir -p "$R/.claude"; printf '{"enabledPlugins":{"ono-project-inspector@ono-plugin-marketplace": true}}\n' >"$R/.claude/settings.local.json"
gate UserPromptSubmit "/ono-project-inspector:inspect" p8; eq "off for the user, on in the project's local settings → allowed" "$DEC" none
rm -rf "$R/.claude"
rm -f "$WORK/claude/settings.json"

# --- drift: how far the central branch's project docs are behind its code (git only) ---
D="$WORK/drift"; rm -rf "$D"; mkdir -p "$D"; git -C "$D" init -q -b master
dg() { git -C "$D" -c user.name=t -c user.email=t@t "$@" >/dev/null 2>&1; }
mkdir -p "$D/src" "$D/docs/project" "$D/.ono" "$D/My App" "$D/old"; echo a >"$D/src/a.kt"; echo '{}' >"$D/package.json"
echo s >"$D/My App/s.swift"; echo o >"$D/old/o.kt"
printf '# AUDIT.md\n' >"$D/AUDIT.md"; echo x >"$D/CLAUDE.md"
for f in overview components patterns integrations capabilities; do echo x >"$D/docs/project/$f.md"; done
dg add -A; dg commit -m base; KH="$(git -C "$D" rev-parse HEAD)"
state() { # state <knowledgeHead json> [stage3Complete] [crlf]
  printf '{\n  "stages": {\n    "s": {\n      "knowledgeHead": "ffffffffffffffffffffffffffffffffffffffff"\n    }\n  },\n  "plugin": {\n    "name": "ono-project-inspector",\n    "version": "0.11.3"\n  },\n  "repository": {\n    "gitRemote": null,\n    "gitHead": "%s",\n    "knowledgeHead": %s\n  },\n  "inspection": {\n    "started": true,\n    "stage3Complete": %s,\n    "currentStage": null\n  }\n}\n' "$KH" "$1" "${2:-true}" |
    { [ -n "${3:-}" ] && sed 's/$/\r/' || cat; } >"$D/.ono/state.json"
  dg add -A; dg commit -m state
}
state "\"$KH\""
dstat() { "$ST" drift "$D" master | cut -f1; }
eq "drift: nothing changed → current" "$(dstat)" current
eq "drift: reads repository.knowledgeHead, not a stage's (listed first)" "$("$ST" drift "$D" master | cut -f2 | sed 's/ date=.*//')" "files=0"
echo y >"$D/docs/project/overview.md"; echo z >"$D/CLAUDE.md"; echo h >"$D/docs/project/שלום.md"; dg add -A; dg commit -m "docs only"
eq "drift: only inspector-owned files changed (also a Hebrew name) → current" "$(dstat)" current
echo b >"$D/src/a.kt"; dg commit -am "one source change"
eq "drift: a source change → behind (no line)" "$(dstat)" behind
case "$("$ST" drift "$D" master)" in *"files=1 "*"inspector=0.11.3 ref=master"*) ok ;; *) fail "drift detail: count, version, ref" "$("$ST" drift "$D" master)" ;; esac
eq "drift: threshold lowered → stale" "$(PG_DRIFT_FILES=1 "$ST" drift "$D" master | cut -f1)" stale
eq "drift: knowledge written 40 days ago + a change → stale" "$(PG_NOW=$(( $(date +%s) + 40*86400 )) "$ST" drift "$D" master | cut -f1)" stale
echo s2 >"$D/My App/s.swift"; dg commit -am "space folder"
eq "drift: a change in an existing folder with a space → still behind" "$(dstat)" behind
# a feature branch's own changes don't count: measured on the central branch
dg switch -c feature/x; echo '{"a":1}' >"$D/package.json"; mkdir -p "$D/newmod"; echo c >"$D/newmod/c.kt"; dg add -A; dg commit -m feat
eq "drift: manifest + new folder on a feature branch → central still behind" "$("$ST" drift "$D" master | cut -f1)" behind
eq "drift: …same answer when the ref comes from git-status (no 3rd arg)" "$("$ST" drift "$D" | cut -f1)" behind
dg switch master; dg merge -q --no-edit feature/x
case "$("$ST" drift "$D" master)" in stale*"build/dependency manifest changed: package.json"*"top-level added: newmod"*) ok ;; *) fail "drift: merged manifest + folder → stale, both named" "$("$ST" drift "$D" master)" ;; esac
git -C "$D" rm -rq old; dg commit -m "rm old"
case "$("$ST" drift "$D" master)" in *"top-level removed: old"*) ok ;; *) fail "drift: removed folder named" "$("$ST" drift "$D" master)" ;; esac
mkdir -p "$D/.github/workflows" "$D/app"; echo w >"$D/.github/workflows/ci.yml"; echo g >"$D/app/build.gradle"; dg add -A; dg commit -m ci
case "$("$ST" drift "$D" master)" in *".github/workflows/ci.yml"*"app/build.gradle"*|*"app/build.gradle"*".github/workflows/ci.yml"*) ok ;; *) fail "drift: CI + nested manifests named" "$("$ST" drift "$D" master)" ;; esac
# a refresh: new knowledgeHead → current, dated today even though knowledgeHead's commit is older
KH="$(git -C "$D" rev-parse HEAD)"; state "\"$KH\""
eq "drift: after a refresh → current" "$(dstat)" current
case "$("$ST" drift "$D" master)" in *"date=$(date +%Y-%m-%d) days=0"*) ok ;; *) fail "drift: date = when the knowledge was written" "$("$ST" drift "$D" master)" ;; esac
state "\"$KH\"" true crlf; eq "drift: CRLF state.json still read" "$(dstat)" current
# a refresh branch already on the remote → pending (no second offer)
git init -q --bare "$WORK/drift-remote.git"; dg remote add origin "$WORK/drift-remote.git"; dg push -q origin master
echo b2 >"$D/src/a.kt"; dg commit -am more; dg push -q origin master
dg switch -c chore/refresh-project-docs-20261122; echo r >"$D/docs/project/overview.md"; dg commit -am refresh; dg push -q origin chore/refresh-project-docs-20261122; dg switch master
case "$("$ST" drift "$D" master)" in pending*"origin/chore/refresh-project-docs-20261122"*) ok ;; *) fail "drift: open refresh branch → pending" "$("$ST" drift "$D" master)" ;; esac
dg merge -q --no-edit chore/refresh-project-docs-20261122
eq "drift: refresh branch merged → no longer pending" "$(dstat)" behind
state "\"$KH\"" false; eq "drift: inspection not through stage 3 → unknown" "$(dstat)" unknown
state null; eq "drift: knowledgeHead null → unknown" "$(dstat)" unknown
state '"0123456789abcdef0123456789abcdef01234567"'; eq "drift: knowledgeHead not in history → unknown" "$(dstat)" unknown
git -C "$D" rm -q .ono/state.json; dg commit -m rm; eq "drift: no state.json → unknown" "$(dstat)" unknown
# nested project: paths relative to the project folder, changes outside it don't count
N="$WORK/nested"; rm -rf "$N"; mkdir -p "$N/App/docs/project" "$N/App/.ono" "$N/App/src" "$N/other"; git -C "$N" init -q -b master
ng() { git -C "$N" -c user.name=t -c user.email=t@t "$@" >/dev/null 2>&1; }
printf '# AUDIT.md\n' >"$N/App/AUDIT.md"; echo x >"$N/App/CLAUDE.md"; echo a >"$N/App/src/a.kt"; echo o >"$N/other/o.txt"
for f in overview components patterns integrations capabilities; do echo x >"$N/App/docs/project/$f.md"; done
ng add -A; ng commit -m base; KH="$(git -C "$N" rev-parse HEAD)"
printf '{\n  "repository": {\n    "knowledgeHead": "%s"\n  },\n  "inspection": {\n    "stage3Complete": true\n  }\n}\n' "$KH" >"$N/App/.ono/state.json"; ng add -A; ng commit -m st
mkdir -p "$N/other2"; echo p >"$N/other2/p"; echo q >"$N/other/o.txt"; ng add -A; ng commit -m outside
eq "drift nested: changes outside the project → current" "$("$ST" drift "$N/App" master | cut -f1)" current
echo b >"$N/App/src/a.kt"; mkdir -p "$N/App/feat"; echo f >"$N/App/feat/f.kt"; ng add -A; ng commit -m inside
case "$("$ST" drift "$N/App" master)" in stale*"top-level added: feat"*) ok ;; *) fail "drift nested: new folder inside the project → stale" "$("$ST" drift "$N/App" master)" ;; esac

echo
echo "inspect-status.sh + inspect-gate.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
