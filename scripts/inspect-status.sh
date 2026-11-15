#!/usr/bin/env bash
# Inspect gate status: has this project been through the Ono Project Inspector?
# bash 3.2, no jq; always exits 0 and prints ONE line: "<status><TAB><detail>".
#
#   inspect-status.sh check [dir]     → status of the repo at dir
#   inspect-status.sh root [dir]      → the project folder the inspection lives in (see below)
#   inspect-status.sh elsewhere [dir] → "<ref>" of the most recently updated remote branch that
#                                       holds a complete, current-model inspection (or nothing)
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
# Project folder: the inspector's outputs (AUDIT.md + .ono/) may live in a subfolder of the git
# root (e.g. yestvos/YesTVOS/). The project folder is the nearest folder from the session folder
# up to the git root that holds the inspector's AUDIT.md; if none and exactly one subfolder (≤ 3
# levels) holds .ono/state.json, that one; else the git root.
# Override lives outside the repo: ~/.claude/platform-guardian/<repo>/inspect-override
# (one line: date, branch, git user). Valid for the local day it was written.
# Env: PG_LOG_DIR (base folder), PG_TODAY (tests only).

here="$(cd "$(dirname "$0")" && pwd)"
cmd="${1:-check}"; dir="${2:-${CLAUDE_PROJECT_DIR:-$PWD}}"
today="${PG_TODAY:-$(date '+%Y-%m-%d')}"

out() { printf '%s\t%s\n' "$1" "${2:-}"; exit 0; }

top="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" || out skip
top="$(cd "$top" 2>/dev/null && pwd -P)" || out skip

inspector_audit_in() { # the inspector's AUDIT.md, not just any file with that name
  [ -f "$1/AUDIT.md" ] && { head -5 "$1/AUDIT.md" | grep -q '^# AUDIT\.md' || [ -f "$1/.ono/state.json" ]; }
}
proj=""
d="$(cd "$dir" 2>/dev/null && pwd -P)" || d="$top"
while :; do
  inspector_audit_in "$d" && { proj="$d"; break; }
  [ "$d" = "$top" ] && break
  case "$d" in "$top"/*) d="$(dirname "$d")" ;; *) break ;; esac
done
if [ -z "$proj" ]; then
  found="$(find "$top" -maxdepth 4 \( -name node_modules -o -name Pods -o -name .git -o -name build \) -prune \
            -o -path '*/.ono/state.json' -print 2>/dev/null | sed 's#/\.ono/state\.json$##')"
  [ -n "$found" ] && [ "$(printf '%s\n' "$found" | grep -c .)" = 1 ] && inspector_audit_in "$found" && proj="$found"
fi
[ -n "$proj" ] || proj="$top"
prefix="${proj#"$top"}"; prefix="${prefix#/}"; pp="${prefix:+$prefix/}"   # "" or "YesTVOS/"
[ "$cmd" = "root" ] && { printf '%s\n' "$proj"; exit 0; }
state_dir="$(dirname "$("$here/session-log.sh" path "$top" 2>/dev/null)")"
[ -n "$state_dir" ] && [ "$state_dir" != "." ] || state_dir="${PG_LOG_DIR:-$HOME/.claude/platform-guardian}/$(basename "$top")"
override_file="$state_dir/inspect-override"

if [ "$cmd" = "elsewhere" ]; then   # FYI only — merging another branch is a human decision
  remote="$(git -C "$top" remote 2>/dev/null | head -n 1)"
  [ -n "$remote" ] || exit 0
  git -C "$top" for-each-ref --sort=-committerdate --count=200 --format='%(refname:short)' "refs/remotes/$remote" 2>/dev/null |
  while IFS= read -r r; do
    case "$r" in */HEAD) continue ;; esac
    git -C "$top" cat-file -e "$r:${pp}AUDIT.md" 2>/dev/null &&
      git -C "$top" cat-file -e "$r:${pp}docs/project/overview.md" 2>/dev/null &&
      git -C "$top" cat-file -e "$r:${pp}docs/project/capabilities.md" 2>/dev/null &&
      { printf '%s\n' "$r"; break; }
  done
  exit 0
fi

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

inspector_audit() { inspector_audit_in "$proj"; }

missing=""
# Kept in step with the inspector's skills/registry.json by scripts/check-routes.sh (CI + daily):
# stage artifacts = `produces` of the artifact-completed inspection stages minus `knowledgeModel`
# artifacts (AUDIT.md is checked separately); model artifacts = `knowledgeModel` paths without "#".
STAGE_ARTIFACTS="CLAUDE.md docs/project/overview.md docs/project/components.md docs/project/patterns.md docs/project/integrations.md"
MODEL_ARTIFACTS="docs/project/capabilities.md"

for f in $STAGE_ARTIFACTS; do
  [ -f "$proj/$f" ] || missing="$missing $f"
done
# knowledge-model artifacts (registry `knowledgeModel`) — missing → refresh recommended, never a block
stale=""
for f in $MODEL_ARTIFACTS; do
  [ -f "$proj/$f" ] || stale="$stale $f"
done

if inspector_audit && [ -z "$missing" ]; then out done "${stale:+refresh-recommended:$stale}"; fi

# not done here — a manager-approved override for today?
if [ -f "$override_file" ] && tail -n 1 "$override_file" | grep -q "^$today	"; then out override "$today"; fi

if inspector_audit; then out partial "${missing# }"; fi

# never inspected on this branch — does the central branch already have it?
ref="$(PG_NO_FETCH=1 "$here/git-status.sh" "$top" 2>/dev/null | sed -n 's/.*"central":{[^}]*"ref":"\([^"]*\)".*/\1/p')"
if [ -n "$ref" ] && git -C "$top" cat-file -e "$ref:${pp}AUDIT.md" 2>/dev/null &&
   git -C "$top" cat-file -e "$ref:${pp}docs/project/overview.md" 2>/dev/null; then
  out on-central "$ref"
fi
out missing
