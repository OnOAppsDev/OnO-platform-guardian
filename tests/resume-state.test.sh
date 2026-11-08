#!/usr/bin/env bash
# Tests for scripts/resume-state.sh — fixtures in the exact formats the Ono plugins write
# (docs/resume-state.md). Matrix fingerprints are also checked against the plugin's own
# node helper when a checkout is available (PG_MQA=<path to mqa.mjs>).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
RS="$HERE/../scripts/resume-state.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/pg-resume.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
PASS=0 FAIL=0
ok() { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL $1"; [ -n "${2:-}" ] && printf '     got: %s\n' "$2"; }
# expect <name> <dir> <substring>  — output contains it
expect() { local o; o="$("$RS" "$2" 2>&1)"; case "$o" in *"$3"*) ok ;; *) bad "$1" "$o" ;; esac; }
# expect_none <name> <dir> [substring] — no output (or not containing substring)
expect_none() {
  local o; o="$("$RS" "$2" 2>&1)"
  if [ -n "${3:-}" ]; then case "$o" in *"$3"*) bad "$1" "$o" ;; *) ok ;; esac
  else [ -z "$o" ] && ok || bad "$1" "$o"; fi
}
w() { mkdir -p "$(dirname "$1")" && cat >"$1"; }   # w <path> <<EOF … EOF
repo() { mkdir -p "$1" && git -C "$1" init -q; }

# ---------- dev features ----------
fa() { # fa <repo> <feature> <status>
  w "$1/docs/$2-feature-analysis.md" <<EOF
# Feature Analysis

\`\`\`yaml
doc_schema_version: 3
feature: $2
dd_link:
surface: app
repo_knowledge_status: complete
status: $3 # proposed | approved
\`\`\`

## Summary
EOF
}
dd() {
  w "$1/docs/$2-DD.md" <<EOF
# DD

\`\`\`yaml
doc_schema_version: 2
feature: $2
feature_analysis_link: docs/$2-feature-analysis.md
detail_level: standard
status: $3
\`\`\`
EOF
}
dp() {
  w "$1/docs/$2-dev-plan.md" <<EOF
# Dev Plan
<!--
## not a heading — inside a comment
-->

\`\`\`yaml
doc_schema_version: 1
feature: $2
dd_link: docs/$2-DD.md
status: $3
\`\`\`
EOF
}
tb() { # tb <repo> <feature> <status> [qa_handoff_link]
  w "$1/docs/$2-task-breakdown.md" <<EOF
# Task Breakdown

\`\`\`yaml
doc_schema_version: 1
feature: $2
feature_analysis_link: docs/$2-feature-analysis.md
dd_link: docs/$2-DD.md
dev_plan_link: docs/$2-dev-plan.md
qa_handoff_link: ${4:-}
status: $3
\`\`\`

## Tasks

| id | description | platform | files touched | depends-on | size | acceptance criteria |
|----|-------------|----------|---------------|------------|------|---------------------|
| T1 | one | rn | a.ts | — | S | x |
| T2 | two | rn | b.ts | T1 | M | y |
| T3 | three | rn | c.ts | T2 | S | z |
EOF
}
state() { # state <repo> <feature> <T1-state> <T2-state> <T3-state>
  w "$1/docs/tasks/$2-task-state.json" <<EOF
{
  "taskStateSchemaVersion": 1,
  "feature": "$2",
  "tasks": {
    "T1": {
      "attempt": 1,
      "validation": [
        {
          "state": "ignored-nested"
        }
      ],
      "state": "$3"
    },
    "T2": {
      "state": "$4"
    },
    "T3": {
      "provenance": "plugin-verified",
      "state": "$5"
    }
  },
  "notTasks": {
    "T2": {
      "state": "complete"
    }
  }
}
EOF
}

R="$WORK/dev"; repo "$R"
expect_none "no docs → silent" "$R"
fa "$R" login proposed
expect "FA proposed → approval" "$R" "feature login · feature analysis waiting for approval · next: your step — approve the analysis (status: approved), then /dev-design-start login"
fa "$R" login approved
expect "FA approved → /dev-design-start" "$R" "analysis approved, no design doc yet · next: /dev-design-start login"
dd "$R" login draft
expect "DD draft → approval" "$R" "design doc waiting for approval · next: your step — approve the DD"
dd "$R" login approved
expect "DD approved → /dev-feature-start" "$R" "design approved, no task breakdown yet · next: /dev-feature-start login"
dp "$R" login draft; tb "$R" login approved
expect "DP draft → plan approval" "$R" "dev plan + task breakdown waiting for approval"
dp "$R" login approved; tb "$R" login draft
expect "TB draft → plan approval" "$R" "dev plan + task breakdown waiting for approval"
tb "$R" login approved
expect "TB approved, no state → T1" "$R" "implementing (0/3 tasks complete) · next: /implement-task login T1"
state "$R" login complete in-progress ""
expect "partial state → first non-complete" "$R" "implementing (1/3 tasks complete) · next: /implement-task login T2"
state "$R" login complete complete failed
expect "failed task → re-run it" "$R" "implementing (2/3 tasks complete) · next: /implement-task login T3"
state "$R" login complete complete complete
expect "all complete → review + QA notes" "$R" "all 3 tasks complete, not handed to QA yet · next: /review-code (if not done yet), then /create-dev-qa-notes login"
w "$R/docs/qa/login-qa-handoff.md" <<'EOF'
---
feature: login
generated_by: create-dev-qa-notes
status: draft
---
EOF
expect "handoff draft → sign-off" "$R" "QA notes drafted, waiting for your sign-off"
sed -i.bak 's/^status: draft/status: ready-for-qa/' "$R/docs/qa/login-qa-handoff.md"
expect_none "handoff ready-for-qa → done, silent" "$R"
# Versioned copy: the shorter (current) path wins.
R2="$WORK/dev2"; repo "$R2"; fa "$R2" pay approved
w "$R2/docs/old/pay-feature-analysis-v1-archived.md" <<'EOF'
```yaml
feature: pay
dd_link:
surface: app
status: proposed
```
EOF
expect "shortest path wins over -v1 copy" "$R2" "feature pay · analysis approved"
# Docs in bugs/ and tasks/ are not planning docs; unrelated frontmatter is ignored.
w "$R2/docs/notes.md" <<'EOF'
---
title: hello
status: draft
---
EOF
expect_none "frontmatter without a planning key → ignored" "$R2" "notes.md"
w "$R2/docs/guide-feature-analysis.md" <<'EOF'
# Guide

## Example

```yaml
feature: example
dd_link:
surface: app
status: proposed
```
EOF
expect_none "yaml fence after a ## heading is not frontmatter" "$R2" "feature example"

# ---------- dev bugs ----------
B="$WORK/bugs"; repo "$B"
mkdir -p "$B/docs/bugs/BUG-7"
expect "bug dir, no plan → /analyze-bug" "$B" "bug BUG-7 · analysis started, no work plan yet · next: /analyze-bug BUG-7"
plan() { # plan <status> <fix_cycle> <approved_cycle>
  w "$B/docs/bugs/BUG-7/bug-work-plan.md" <<EOF
# Bug Work Plan

\`\`\`yaml
work_type: bug
bug_key: BUG-7
status: $1
fix_cycle: $2
approved_cycle: $3
\`\`\`

## Tasks

| id | description |
|----|-------------|
| T1 | first fix |
| T2 | second fix |

## Fix Cycles

### Cycle 2

| id | description |
|----|-------------|
| C2-T1 | reopen fix |
EOF
}
plan draft 1 null
expect "plan draft → approval via /analyze-bug" "$B" "work plan (cycle 1) waiting for approval · next: /analyze-bug BUG-7"
plan approved 2 1
expect "approved_cycle ≠ fix_cycle → approval" "$B" "work plan (cycle 2) waiting for approval"
plan approved 1 1
expect "approved, no state → T1" "$B" "fixing, cycle 1 (0/2 tasks complete) · next: /implement-task bug:BUG-7 T1"
w "$B/docs/tasks/bugs/BUG-7.task-state.json" <<'EOF'
{
  "feature": "bug:BUG-7",
  "tasks": {
    "T1": {
      "state": "complete"
    },
    "T2": {
      "state": "complete"
    }
  }
}
EOF
expect "all done → verify (human)" "$B" "fix done (cycle 1), not verified yet · next: your step — /verify-fix-cycle bug:BUG-7"
w "$B/docs/bugs/BUG-7/verification-c1.md" <<'EOF'
---
status: failed
---
EOF
expect "verification failed → verify again" "$B" "/verify-fix-cycle bug:BUG-7"
sed -i.bak 's/failed/passed/' "$B/docs/bugs/BUG-7/verification-c1.md"
expect "verified → /review-code --bug" "$B" "fix verified (cycle 1), not reviewed yet · next: /review-code --bug BUG-7"
w "$B/docs/bugs/BUG-7/review-c1.md" <<'EOF'
---
review_schema: 1
---
EOF
expect "reviewed → /create-dev-qa-notes" "$B" "fix reviewed (cycle 1), not handed to QA · next: /create-dev-qa-notes bug:BUG-7"
w "$B/docs/qa/bug-BUG-7-qa-handoff.md" <<'EOF'
---
work_type: bug
bug_key: BUG-7
fix_cycle: 1
status: draft
---
EOF
expect "handoff draft → sign-off" "$B" "QA notes drafted (cycle 1), waiting for sign-off"
sed -i.bak 's/status: draft/status: ready-for-qa/' "$B/docs/qa/bug-BUG-7-qa-handoff.md"
expect_none "handed to QA → silent" "$B"
plan approved 2 2
expect "cycle 2 tasks come from ### Cycle 2" "$B" "fixing, cycle 2 (0/1 tasks complete) · next: /implement-task bug:BUG-7 C2-T1"
printf '{\n  "tasks": {\n    "C2-T1": {\n      "state": "complete"\n    }\n  }\n}\n' >"$B/docs/tasks/bugs/BUG-7.task-state.json"
printf -- '---\nstatus: passed\n---\n' >"$B/docs/bugs/BUG-7/verification-c2.md"
printf -- '---\nreview_schema: 1\n---\n' >"$B/docs/bugs/BUG-7/review-c2.md"
expect "cycle-1 handoff does not cover cycle 2" "$B" "fix reviewed (cycle 2), not handed to QA · next: /create-dev-qa-notes bug:BUG-7"

# ---------- inspector ----------
I="$WORK/insp"; repo "$I"
w "$I/AUDIT.md" <<'EOF'
# AUDIT.md — demo

## Audit Topics

| # | Status | Topic | Priority | File | Notes |
|---|--------|-------|----------|------|-------|
| 1 | Approved | Security | High | audits/security/security-audit.md | Approved 2026-11-01 |
| 2 | Draft | Player / Media | High | audits/player-media/player-media-audit.md | |
| 3 | Pending Breakdown | Networking | Medium | Not created yet | |

Other text
EOF
echo "# CLAUDE.md — demo" >"$I/CLAUDE.md"
expect "docs/project missing → stage 1 approval" "$I" "project analysis done, project docs not finished · next: your step — /inspect-approve"
mkdir -p "$I/docs/project"; for p in overview components patterns integrations capabilities; do echo x >"$I/docs/project/$p.md"; done
expect "Draft topic → review + /inspect-approve" "$I" "audit topic Player / Media · drafted, waiting for your review (1/3 topics approved) · next: your step — review audits/player-media/player-media-audit.md, then /inspect-approve"
sed -i.bak 's/| Draft |/| Approved |/' "$I/AUDIT.md"
expect "pending only → /inspect-topic" "$I" "audit topics in progress (2/3 approved) · next: /inspect-topic"
sed -i.bak 's/| Pending Breakdown |/| Approved |/' "$I/AUDIT.md"
expect_none "all approved → silent" "$I"
w "$I/AUDIT.md" <<'EOF'
# AUDIT.md — demo
no table
EOF
expect "unparseable AUDIT.md → /inspect-status" "$I" "next: /inspect-status"
I2="$WORK/insp2"; repo "$I2"; echo "# My own audit" >"$I2/AUDIT.md"
expect_none "hand-written AUDIT.md (no inspector) → ignored" "$I2"

# ---------- spec-team-toolkit ----------
S="$WORK/spec"; repo "$S"
w "$S/docs/specs/login/spac_login.md" <<'EOF'
# SPAC: Login

**Status:** 🟡 DRAFT
**Reviewer:** TBD
EOF
expect "SPAC draft" "$S" "SPAC login · draft — reviewers approve, then mark it ready · next: spec-team-toolkit:lld-mobile-spec"
sed -i.bak 's/🟡 DRAFT/✅ READY/' "$S/docs/specs/login/spac_login.md"
expect "SPAC READY without DD starter" "$S" "SPAC login · READY, DD starter not generated"
echo "# Frontend Technical DD: Login" >"$S/docs/specs/login/dd_login.md"
expect_none "SPAC READY with DD → silent" "$S"
w "$S/docs/specs/portal/hld-draft.md" <<'EOF'
## רקע [סטטוס: הושלם]
## מאגרי מידע [סטטוס: טיוטה חלקית]
## אינטגרציות [סטטוס: ממתין למידע]
## ביצועים [סטטוס: לא רלוונטי לפרויקט זה]
EOF
expect "HLD with open sections" "$S" "HLD portal · draft — 2 of 4 sections still open · next: spec-team-toolkit:hld-builder"
sed -i.bak 's/טיוטה חלקית/הושלם/; s/ממתין למידע/הושלם/' "$S/docs/specs/portal/hld-draft.md"
expect_none "HLD all done → silent" "$S"
w "$S/docs/specs/orders/orders-api.md" <<'EOF'
# LLD: Orders API

**Status:** DRAFT
EOF
expect "backend LLD draft" "$S" "LLD orders-api · draft — open questions to resolve"
sed -i.bak 's/^\*\*Status:\*\* DRAFT/**Status:** READY/' "$S/docs/specs/orders/orders-api.md"
expect_none "backend LLD READY → silent" "$S" "LLD orders-api"

# ---------- ono-plugin-qa ----------
Q="$WORK/ws/app-qa"; repo "$Q"
w "$Q/login/test-plan.md" <<'EOF'
# Test plan

```yaml
feature: login
status: draft # draft | approved — flip via /approve-qa-test-plan, never hand-edit
approved_by: # set by /approve-qa-test-plan
```
EOF
expect "plan draft → /approve-qa-test-plan (human)" "$Q" "test plan login · draft, waiting for QA approval · next: your step — /approve-qa-test-plan login"
sed -i.bak 's/^status: draft/status: approved/' "$Q/login/test-plan.md"
expect "approved → coverage" "$Q" "test plan approved, coverage not checked · next: /check-qa-coverage login"
echo "---" >"$Q/login/coverage-report.md"
expect "coverage → register build" "$Q" "coverage checked, no build registered · next: /register-build login"
mkdir -p "$Q/qa-ledger/builds" "$Q/qa-ledger/scopes/feature" "$Q/qa-ledger/runs"
echo '{"build_id":"b1","kind":"build.registered","related_scopes":["feature:login"]}' >"$Q/qa-ledger/builds/b1.json"
expect "build → set scope (human)" "$Q" "build registered, QA scope not set · next: your step — /set-qa-scope login"
echo '{"field":"surfaces","kind":"context.set","value":["ios"]}' >"$Q/qa-ledger/scopes/feature/login.jsonl"
expect "scope → functional run" "$Q" "scope set, functional run not finished · next: /record-execution login"
printf '%s\n' '{"kind":"run.opened","scope":"feature:login"}' >"$Q/qa-ledger/runs/functional-20261108T100000Z-aaaaaaaa.jsonl"
expect "open run is not finished" "$Q" "functional run not finished"
echo '{"kind":"run.closed"}' >>"$Q/qa-ledger/runs/functional-20261108T100000Z-aaaaaaaa.jsonl"
expect "closed run → /qa-readiness" "$Q" "testing in progress · next: /qa-readiness login"
w "$Q/readiness/feature/login.md" <<'EOF'
---
verdict: NOT_READY
signoff_status: none
---
EOF
expect "NOT_READY → /qa-readiness" "$Q" "testing in progress, last readiness NOT_READY · next: /qa-readiness login"
sed -i.bak 's/NOT_READY/READY/' "$Q/readiness/feature/login.md"
expect "READY, not signed → /qa-signoff (human)" "$Q" "readiness READY, not signed off · next: your step — /qa-signoff login"
sed -i.bak 's/signoff_status: none/signoff_status: valid/' "$Q/readiness/feature/login.md"
expect_none "signed off → silent" "$Q"
# Workspace file: QA repo found from the code repo next to it.
C="$WORK/ws/app"; repo "$C"
w "$WORK/ws/.claude/qa-workspace.json" <<'EOF'
{"codeRepoPath": "app", "qaRepoPath": "app-qa"}
EOF
sed -i.bak 's/signoff_status: valid/signoff_status: stale/' "$Q/readiness/feature/login.md"
expect "QA repo via ../.claude/qa-workspace.json" "$C" "ono-plugin-qa · feature login · readiness READY"
expect_none "code repo without workspace file → no QA lines" "$WORK/dev" "ono-plugin-qa"

# ---------- matrix-qa-plugin (fingerprints) ----------
X="$WORK/mx"; repo "$X"
echo '{"projectId":"p","paths":{"lldDir":"qa/lld","testCasesDir":"qa/test-cases","testDir":"tests/e2e"}}' >"$X/matrix-qa.config.json"
w "$X/qa/lld/login.md" <<'EOF'
# LLD login
EOF
expect "LLD without plan → /qa-plan" "$X" "feature login · LLD ready, no test plan yet · next: /qa-plan qa/lld/login.md"
# fingerprint of "# LLD login" (normalised) and of the plan body below, computed with the
# plugin's algorithm (verified against mqa.mjs in development).
fp() { printf '%s' "$1" | { shasum -a 256 2>/dev/null || sha256sum; } | cut -d' ' -f1; }
LFP="sha256:$(fp '# LLD login')"
CFP="sha256:$(fp '# Tests
LOGIN-TC-001 works')"
mxplan() { # mxplan <status> <reviewed_fp> <approved_fp>
  w "$X/qa/test-cases/login.md" <<EOF
---
feature: login
feature_id: LOGIN
lld_path: qa/lld/login.md
lld_fingerprint: "$LFP"
status: $1
reviewed_fingerprint: "$2"
approved_fingerprint: "$3"
---
# Tests
LOGIN-TC-001 works
<!-- mqa:section approval -->
approved by someone — excluded from the hash
EOF
}
mxplan DRAFT "" ""
expect "DRAFT → /qa-review" "$X" "test plan DRAFT · next: /qa-review login"
printf '\n\n   # LLD login  \r\n\n' >"$X/qa/lld/login.md"
expect "LLD hash ignores outer whitespace + CRLF" "$X" "test plan DRAFT · next: /qa-review login"
printf '# LLD login\n' >"$X/qa/lld/login.md"
mxplan REVIEWED "$CFP" ""
expect "REVIEWED, content unchanged → /qa-approve (human)" "$X" "waiting for QA approval · next: your step — /qa-approve login"
mxplan REVIEWED "sha256:0000" ""
expect "REVIEWED, content changed → /qa-review" "$X" "plan changed after review · next: /qa-review login"
mxplan APPROVED "$CFP" "$CFP"
expect "APPROVED, no tests → /qa-automate" "$X" "test plan approved, not automated yet · next: /qa-automate login"
w "$X/tests/e2e/login.spec.ts" <<'EOF'
test('LOGIN-TC-001 works', async () => {});
EOF
expect_none "APPROVED + automated → silent" "$X"
mxplan APPROVED "$CFP" "sha256:0000"
expect "APPROVED, content changed → re-review" "$X" "plan changed after approval"
mxplan APPROVED "$CFP" "$CFP"; echo "new requirement" >>"$X/qa/lld/login.md"
expect "LLD changed → /qa-sync" "$X" "the LLD changed since the plan was written (APPROVED) · next: /qa-sync login"

# Cross-check against the plugin's own node helper when available.
if [ -n "${PG_MQA:-}" ] && [ -f "$PG_MQA" ] && command -v node >/dev/null; then
  printf '# LLD login\n' >"$X/qa/lld/login.md"
  echo '{"projectId":"p","paths":{"lldDir":"qa/lld","testCasesDir":"qa/test-cases","testDir":"tests/e2e"},"environments":{"l":{"baseUrl":"http://x"}},"defaultEnvironment":"l"}' >"$X/matrix-qa.config.json"
  got="$(cd "$X" && node "$PG_MQA" plan validate login 2>/dev/null | tr -d ' \n')"
  case "$got" in *"\"lldChanged\":false"*"\"contentFingerprint\":\"$CFP\""*|*"\"contentFingerprint\":\"$CFP\""*"\"lldChanged\":false"*) ok ;;
    *) bad "fingerprints match mqa.mjs" "$got" ;; esac
fi

# ---------- global behaviour ----------
M="$WORK/many"; repo "$M"
for n in 1 2 3 4 5 6 7 8 9 10; do fa "$M" "f$n" proposed; done
o="$(PG_RESUME_MAX=3 "$RS" "$M")"
[ "$(printf '%s\n' "$o" | grep -c '^- ono-mobile')" = 3 ] && ok || bad "PG_RESUME_MAX caps lines" "$o"
case "$o" in *"… and 7 more"*) ok ;; *) bad "overflow line" "$o" ;; esac
[ -z "$(PG_RESUME=off "$RS" "$M")" ] && ok || bad "PG_RESUME=off disables"
expect "subfolder → repo root is scanned" "$M/docs" "feature f1"
o="$("$RS" "$WORK/nope" 2>&1)"; rc=$?
[ -z "$o" ] && [ "$rc" = 0 ] && ok || bad "missing dir → silent exit 0" "$o rc=$rc"
o="$(cd "$M" && CLAUDE_PROJECT_DIR="$M" "$RS" 2>&1)"; case "$o" in *"feature f1"*) ok ;; *) bad "CLAUDE_PROJECT_DIR default" "$o" ;; esac
err="$("$RS" "$R" 2>&1 >/dev/null)"; [ -z "$err" ] && ok || bad "no stderr" "$err"
# Regression: a relative path once made the upward config walk loop forever (dirname . = .).
( cd "$WORK" && "$RS" many >"$WORK/rel.out" 2>&1 ) & pid=$!
n=0; while kill -0 "$pid" 2>/dev/null && [ "$n" -lt 50 ]; do sleep 0.2; n=$((n + 1)); done
if kill -0 "$pid" 2>/dev/null; then kill "$pid" 2>/dev/null; bad "relative path finishes (hung > 10s)"
else case "$(cat "$WORK/rel.out")" in *"feature f1"*) ok ;; *) bad "relative path → same result" "$(cat "$WORK/rel.out")" ;; esac; fi

echo
echo "resume-state.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
