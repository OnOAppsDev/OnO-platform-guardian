#!/usr/bin/env bash
# Open pull requests waiting for the employee's review (asked personally, not through a team;
# drafts left out), from GitHub through the employee's own `gh` login.
# bash 3.2, no jq (gh's built-in --jq). Always exits 0; prints nothing when gh is missing, not
# logged in, offline, slow, or nothing waits. Otherwise one line per PR:
#   <here|other><TAB><owner/repo>#<number><TAB><author><TAB><title><TAB><url>
# "here" = the PR belongs to the repo at dir (its origin remote), so the employee can review it
# in this session. At most PG_REVIEWS_LIMIT (default 10) PRs, newest activity first.
# Env: PG_REVIEWS=off (off switch) · PG_GH (gh binary, tests) · PG_REVIEWS_TIMEOUT (seconds, default 3)

[ "${PG_REVIEWS:-}" = off ] && exit 0
dir="${1:-${CLAUDE_PROJECT_DIR:-$PWD}}"
gh="${PG_GH:-gh}"
command -v "$gh" >/dev/null 2>&1 || exit 0

out="$(mktemp "${TMPDIR:-/tmp}/pg-reviews.XXXXXX" 2>/dev/null)" || exit 0
trap 'rm -f "$out"' EXIT

# Titles are written by other people and land in Claude's context: only PRs by people inside the
# org / repo (CODEOWNERS also requests reviews on outsiders' PRs), every control character
# replaced, cut to 80 characters. Exported for the tests, which run it through jq.
PG_REVIEWS_JQ='.[] | select(.authorAssociation == "MEMBER" or .authorAssociation == "OWNER" or .authorAssociation == "COLLABORATOR")
  | (.title | explode | map(if . < 32 or . == 127 or . == 96 then 32 else . end) | implode
     | if length > 80 then .[0:79] + "…" else . end) as $t
  | "\(.repository.nameWithOwner)#\(.number)\t\(.author.login // "unknown")\t\($t)\t\(.url)"'
[ "${PG_REVIEWS_PRINT_JQ:-}" = 1 ] && { printf '%s\n' "$PG_REVIEWS_JQ"; exit 0; }

# Same watchdog pattern as git-status.sh: a hung network call must not hold up the opener.
"$gh" search prs "user-review-requested:@me" "draft:false" --state=open --sort=updated \
  --limit "${PG_REVIEWS_LIMIT:-10}" --json number,title,url,repository,author,authorAssociation \
  --jq "$PG_REVIEWS_JQ" \
  </dev/null >"$out" 2>/dev/null &
pid=$!
( sleep "${PG_REVIEWS_TIMEOUT:-3}"; kill -TERM "$pid" ) >/dev/null 2>&1 &
dog=$!
wait "$pid" 2>/dev/null; rc=$?
if kill -0 "$dog" 2>/dev/null; then pkill -TERM -P "$dog" 2>/dev/null; kill -TERM "$dog" 2>/dev/null; fi
wait "$dog" 2>/dev/null
[ "$rc" -eq 0 ] || exit 0

# owner/repo of this checkout: git@github.com:o/r.git · https://github.com/o/r(.git) · ssh://…/o/r
here="$(git -C "$dir" remote get-url origin 2>/dev/null | tr -d '\r' |
        sed -e 's#\.git$##' -e 's#/$##' -e 's#^.*[:/]\([^/:]*/[^/]*\)$#\1#' | tr 'A-Z' 'a-z')"

while IFS="$(printf '\t')" read -r ref author title url; do
  [ -n "$ref" ] || continue
  repo="$(printf '%s' "${ref%#*}" | tr 'A-Z' 'a-z')"
  where=other; [ -n "$here" ] && [ "$repo" = "$here" ] && where=here
  printf '%s\t%s\t%s\t%s\t%s\n' "$where" "$ref" "$author" "$title" "$url"
done < <(tr -d '\r' <"$out")
exit 0
