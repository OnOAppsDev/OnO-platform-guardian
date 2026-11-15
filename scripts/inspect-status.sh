#!/usr/bin/env bash
# Inspect gate status: has this project been through the Ono Project Inspector?
# bash 3.2, no jq; always exits 0 and prints ONE line: "<status><TAB><detail>".
#
#   inspect-status.sh check [dir]     → status of the repo at dir
#   inspect-status.sh override [dir]  → record today's manager-approved override for this repo
#
# Status:
#   done        stages 1–2 complete: AUDIT.md (inspector's) + CLAUDE.md + docs/project/{overview,
#               components,patterns,integrations}.md — audit topics may still be open.
#               detail "refresh-recommended: <files>" when a knowledge-model artifact is missing
#               (docs/project/capabilities.md): the inspection predates the current knowledge
#               model. The inspector's registry: such an absence "never reopens an otherwise
#               complete stage" (inspection-state.ts skips knowledgeModel artifacts) → not a block.
#   partial     inspection started (AUDIT.md) but not finished          detail: missing files
#   on-central  not on this branch, but the central branch has it       detail: central ref
#   missing     never inspected
#   override    not done, but the employee typed the manager-approval sentence today  detail: date
#   exempt      .platform-guardian.json "inspectRequired": false (a committed, reviewed choice)
#   skip        not a git repository
#
# Override lives outside the repo: ~/.claude/platform-guardian/<repo>/inspect-override
# (one line: date, branch, git user). Valid for the local day it was written.
# Env: PG_LOG_DIR (base folder), PG_TODAY (tests only).

here="$(cd "$(dirname "$0")" && pwd)"
cmd="${1:-check}"; dir="${2:-${CLAUDE_PROJECT_DIR:-$PWD}}"
today="${PG_TODAY:-$(date '+%Y-%m-%d')}"

out() { printf '%s\t%s\n' "$1" "${2:-}"; exit 0; }

top="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" || out skip
state_dir="$(dirname "$("$here/session-log.sh" path "$top" 2>/dev/null)")"
[ -n "$state_dir" ] && [ "$state_dir" != "." ] || state_dir="${PG_LOG_DIR:-$HOME/.claude/platform-guardian}/$(basename "$top")"
override_file="$state_dir/inspect-override"

if [ "$cmd" = "override" ]; then
  mkdir -p "$state_dir" 2>/dev/null &&
    printf '%s\t%s\t%s\n' "$today" "$(git -C "$top" rev-parse --abbrev-ref HEAD 2>/dev/null)" \
      "$(git -C "$top" config user.name 2>/dev/null)" >>"$override_file" 2>/dev/null &&
    out override "$today"
  out error "could not write $override_file"
fi

if [ -f "$top/.platform-guardian.json" ] &&
   grep -Eq '"inspectRequired"[[:space:]]*:[[:space:]]*false' "$top/.platform-guardian.json"; then
  out exempt
fi

inspector_audit() { # the inspector's AUDIT.md, not just any file with that name
  [ -f "$top/AUDIT.md" ] && { head -5 "$top/AUDIT.md" | grep -q '^# AUDIT\.md' || [ -f "$top/.ono/state.json" ]; }
}

missing=""
# stage artifacts (registry `produces` minus `knowledgeModel` artifacts) — these decide completion
for f in CLAUDE.md docs/project/overview.md docs/project/components.md docs/project/patterns.md \
         docs/project/integrations.md; do
  [ -f "$top/$f" ] || missing="$missing $f"
done
# knowledge-model artifacts (registry `knowledgeModel`) — missing → refresh recommended, never a block
stale=""
for f in docs/project/capabilities.md; do
  [ -f "$top/$f" ] || stale="$stale $f"
done

if inspector_audit && [ -z "$missing" ]; then out done "${stale:+refresh-recommended:$stale}"; fi

# not done here — a manager-approved override for today?
if [ -f "$override_file" ] && tail -n 1 "$override_file" | grep -q "^$today	"; then out override "$today"; fi

if inspector_audit; then out partial "${missing# }"; fi

# never inspected on this branch — does the central branch already have it?
ref="$(PG_NO_FETCH=1 "$here/git-status.sh" "$top" 2>/dev/null | sed -n 's/.*"central":{[^}]*"ref":"\([^"]*\)".*/\1/p')"
if [ -n "$ref" ] && git -C "$top" cat-file -e "$ref:AUDIT.md" 2>/dev/null &&
   git -C "$top" cat-file -e "$ref:docs/project/overview.md" 2>/dev/null; then
  out on-central "$ref"
fi
out missing
