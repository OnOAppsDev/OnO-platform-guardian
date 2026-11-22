#!/usr/bin/env bash
# Tests for scripts/review-requests.sh with a fake gh (no network).
# Usage: tests/review-requests.test.sh
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
RR="$HERE/../scripts/review-requests.sh"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
unset PG_REVIEWS PG_REVIEWS_LIMIT PG_REVIEWS_TIMEOUT CLAUDE_PROJECT_DIR

WORK="$(mktemp -d "${TMPDIR:-/tmp}/pg-reviews.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PASS=0 FAIL=0
ok()   { PASS=$((PASS + 1)); }
fail() { FAIL=$((FAIL + 1)); echo "FAIL $1"; [ -n "${2:-}" ] && printf '      got: %s\n' "$2"; }
eq()   { [ "$2" = "$3" ] && ok || fail "$1" "$2"; }
has()  { case "$2" in *"$3"*) ok ;; *) fail "$1 (missing: $3)" "$2" ;; esac; }

git init -q "$WORK/r"; R="$WORK/r"
T="$(printf '\t')"

# fake gh: records its arguments, prints the lines gh's --jq would
fake() { # fake <name> <body>
  printf '#!/bin/sh\nprintf "%%s\\n" "$@" >"%s/args"\n%s\n' "$WORK" "$2" >"$WORK/$1"; chmod +x "$WORK/$1"
}
fake gh-ok 'printf "OnOAppsDev/My-App#12\tdana\tFix login\thttps://x/12\nOnOAppsDev/other#3\tavi\tSplash\thttps://x/3\n"'

git -C "$R" remote add origin git@github.com:OnOAppsDev/my-app.git
out="$(PG_GH="$WORK/gh-ok" "$RR" "$R")"
eq "ssh remote, other case → here" "$(printf '%s\n' "$out" | sed -n 1p)" "here${T}OnOAppsDev/My-App#12${T}dana${T}Fix login${T}https://x/12"
eq "another repo → other" "$(printf '%s\n' "$out" | sed -n 2p | cut -f1,2)" "other${T}OnOAppsDev/other#3"
args="$(cat "$WORK/args")"
has "asks for personal review requests only" "$args" "user-review-requested:@me"
has "leaves drafts out" "$args" "draft:false"
has "open PRs only" "$args" "--state=open"
has "default limit 10" "$args" "10"

git -C "$R" remote set-url origin https://github.com/OnOAppsDev/My-App/
eq "https remote with trailing slash → here" "$(PG_GH="$WORK/gh-ok" "$RR" "$R" | sed -n 1p | cut -f1)" here
git -C "$R" remote set-url origin ssh://git@github.com/OnOAppsDev/My-App.git
eq "ssh:// remote → here" "$(PG_GH="$WORK/gh-ok" "$RR" "$R" | sed -n 1p | cut -f1)" here
git -C "$R" remote remove origin
eq "no remote → everything is other" "$(PG_GH="$WORK/gh-ok" "$RR" "$R" | cut -f1 | sort -u)" other
eq "outside git → still listed (other)" "$(PG_GH="$WORK/gh-ok" "$RR" "$WORK" | wc -l | tr -d ' ')" 2

fake gh-crlf 'printf "o/r#1\tdana\tTitle\thttps://x/1\r\n"'
eq "CRLF output (Windows gh) → no stray CR" "$(PG_GH="$WORK/gh-crlf" "$RR" "$R" | cut -f5)" "https://x/1"

fake gh-fail 'echo "error: not logged in" >&2; exit 4'
out="$(PG_GH="$WORK/gh-fail" "$RR" "$R" 2>&1)"; rc=$?
eq "gh not logged in → silent, exit 0" "$rc:$out" "0:"
out="$(PG_GH=pg-no-such-gh "$RR" "$R" 2>&1)"; rc=$?
eq "gh missing → silent, exit 0" "$rc:$out" "0:"
out="$(PG_REVIEWS=off PG_GH="$WORK/gh-ok" "$RR" "$R")"
eq "PG_REVIEWS=off → nothing" "$out" ""

fake gh-hang 'sleep 20; echo "o/r#1	a	t	u"'
start=$(date +%s)
out="$(PG_REVIEWS_TIMEOUT=1 PG_GH="$WORK/gh-hang" "$RR" "$R")"; rc=$?
took=$(( $(date +%s) - start ))
eq "hung gh → nothing" "$rc:$out" "0:"
[ "$took" -le 4 ] && ok || fail "hung gh → stopped by the watchdog (took ${took}s)"

PG_REVIEWS_LIMIT=3 PG_GH="$WORK/gh-ok" "$RR" "$R" >/dev/null
has "PG_REVIEWS_LIMIT passed to gh" "$(cat "$WORK/args")" "3"

echo
echo "review-requests.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
