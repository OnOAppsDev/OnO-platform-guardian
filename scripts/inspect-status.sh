#!/usr/bin/env bash
# Inspect gate status: has this project been through the Ono Project Inspector?
# bash 3.2, no jq; always exits 0 and prints ONE line: "<status><TAB><detail>".
#
#   inspect-status.sh check [dir] [central-ref] → status of the repo at dir (central ref: from a
#                                       git report already in hand, saves running git-status.sh again)
#   inspect-status.sh root [dir]      → the project folder the inspection lives in (see below)
#   inspect-status.sh elsewhere [dir] → "<ref>" of the most recently updated remote branch that
#                                       holds a complete, current-model inspection (or nothing)
#   inspect-status.sh override [dir]  → record today's manager-approved override for this repo
#   inspect-status.sh drift [dir] [ref] → how far the inspection's knowledge on the central branch is behind it
#                                       (stale | behind | current | pending | unknown — see the drift block)
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
  # One git process for all branches, not one per file per branch: process starts are slow in
  # Git Bash on Windows, and a few hundred of them pushed the SessionStart hook past its timeout
  # (Windows ticket, 2026-11-23 — the whole opener report was lost).
  refs="$(git -C "$top" for-each-ref --sort=-committerdate --count=200 --format='%(refname:short)' "refs/remotes/$remote" 2>/dev/null |
          grep -v '/HEAD$')"
  [ -n "$refs" ] || exit 0
  # cat-file prints one line per name, in order: "blob" when the file is there, "<name> missing" if not
  found="$(printf '%s\n' "$refs" |
    awk -v p="$pp" '{ print $0 ":" p "AUDIT.md"; print $0 ":" p "docs/project/overview.md"; print $0 ":" p "docs/project/capabilities.md" }' |
    git -C "$top" cat-file --batch-check='%(objecttype)' 2>/dev/null | paste - - -)"
  # line i of $found belongs to line i of $refs
  printf '%s\n' "$found" | paste - <(printf '%s\n' "$refs") |
    awk -F'\t' '$1 == "blob" && $2 == "blob" && $3 == "blob" { print $4; exit }'
  exit 0
fi

if [ "$cmd" = "drift" ]; then
  # How far the inspection's Project Knowledge on the CENTRAL branch is behind the central branch's
  # code — the inspector's own freshness rule (inspection-state.ts computeKnowledgeFreshness), in
  # git only: no Bun, no tokens. Measured on the central branch because that's where the refresh is
  # done (one chore PR for the team): a feature branch's own changes never trigger it, and once a
  # refresh is merged nobody is offered it again. Ref: 3rd argument, else the central branch from
  # git-status.sh, else HEAD.
  # Prints "<status><TAB><detail>":
  #   stale    worth a refresh: a build/dependency/CI manifest changed, a top-level entry was
  #            added or removed, ≥ PG_DRIFT_FILES (30) source files changed, or source changed and
  #            the knowledge was last written ≥ PG_DRIFT_DAYS (30) days ago
  #   behind   source changed, below those thresholds (no line in the opener)
  #   current  no source change since the knowledge was generated
  #   pending  a refresh branch (…/chore/refresh-project-docs*) is on the remote, not merged yet
  #   unknown  no state, inspection not through stage 3, no knowledgeHead (inspected before
  #            0.10.0), or it isn't in this history
  # detail: files=<n> date=<YYYY-MM-DD> days=<d> inspector=<version> ref=<ref> signals=<a; b>
  ref="${3:-}"
  [ -n "$ref" ] || ref="$(PG_NO_FETCH=1 "$here/git-status.sh" "$top" 2>/dev/null | sed -n 's/.*"central":{[^}]*"ref":"\([^"]*\)".*/\1/p')"
  [ -n "$ref" ] && git -C "$top" rev-parse -q --verify "$ref^{commit}" >/dev/null 2>&1 || ref=HEAD
  g() { git -C "$proj" -c core.quotePath=false "$@" 2>/dev/null; }
  state="$(git -C "$top" show "$ref:${pp}.ono/state.json" 2>/dev/null | tr -d '\r')"
  [ -n "$state" ] || out unknown "no .ono/state.json on $ref"
  block_val() { # block_val <block> <key>: the value of "key" inside the top-level "<block>": { … }
    printf '%s\n' "$state" | awk -v b="\"$1\"" -v k="\"$2\"" '
      index($0, b) && /\{[[:space:]]*$/ { inb = 1; next }
      inb && /^[[:space:]]*\}/ { exit }
      inb && index($0, k) { sub(/^[^:]*:[[:space:]]*/, ""); sub(/,?[[:space:]]*$/, ""); gsub(/"/, ""); print; exit }'
  }
  ver="$(block_val plugin version)"
  [ "$(block_val inspection stage3Complete)" = true ] || out unknown "inspection not through stage 3${ver:+ (inspector $ver)}"
  kh="$(block_val repository knowledgeHead)"
  case "$kh" in ""|null|*[!0-9a-f]*) out unknown "no knowledgeHead recorded${ver:+ (inspector $ver)}" ;; esac
  git -C "$top" cat-file -e "$kh^{commit}" 2>/dev/null || out unknown "knowledgeHead ${kh%"${kh#???????}"} not in this history"
  # a refresh already on its way → don't offer another one
  pend="$(git -C "$top" for-each-ref --format='%(refname:short)' 'refs/remotes/*/chore/refresh-project-docs*' 2>/dev/null |
          while IFS= read -r b; do git -C "$top" merge-base --is-ancestor "$b" "$ref" 2>/dev/null || { printf '%s\n' "$b"; break; }; done)"
  [ -n "$pend" ] && out pending "branch=$pend"
  # when the knowledge was last written: the commit that last changed state.json on the ref
  # (knowledgeHead's own date can be weeks older than the refresh that recorded it)
  when="$(git -C "$top" log -1 --format='%ct %ad' --date=short "$ref" -- "${pp}.ono/state.json" 2>/dev/null)"
  then_s="${when%% *}"; date="${when#* }"; now_s="${PG_NOW:-$(date +%s)}"
  days=$(( (now_s - ${then_s:-$now_s}) / 86400 ))
  changed="$(g diff --relative --name-only --no-renames "$kh" "$ref" |
    grep -Ev '^(CLAUDE\.md|AUDIT\.md|CLAUDE\.md\.bak|AUDIT\.md\.bak)$|^(\.ono|docs/project|audits)/')"
  n="$(printf '%s' "$changed" | grep -c .)"
  detail="files=$n date=$date days=$days inspector=${ver:-?} ref=$ref"
  [ "$n" -eq 0 ] && out current "$detail"
  # one awk pass, as the inspector: a changed file's basename is a build manifest; its top folder
  # (split on "/" only — names may hold spaces) wasn't there before (added) or isn't now (removed)
  signals="$( { g ls-tree --name-only "$kh" | sed 's/^/T	/'; g ls-tree --name-only "$ref" | sed 's/^/N	/'
                printf '%s\n' "$changed" | sed 's/^/C	/'; } | awk -F'\t' '
    $1 == "T" { before[$2] = 1; next }
    $1 == "N" { now[$2] = 1; next }
    $1 == "C" && $2 != "" {
      rel = $2; n = split(rel, p, "/"); b = p[n]; top = p[1]
      if (b ~ /^(package\.json|pnpm-workspace\.yaml|lerna\.json|nx\.json|turbo\.json|Podfile|Package\.swift|Cartfile|project\.pbxproj|build\.gradle|build\.gradle\.kts|settings\.gradle|settings\.gradle\.kts|pom\.xml|Cargo\.toml|go\.mod|pyproject\.toml|setup\.py|setup\.cfg|requirements\.txt|Pipfile|Gemfile|pubspec\.yaml|composer\.json|Makefile|Dockerfile|docker-compose\.ya?ml|\.gitlab-ci\.yml|Jenkinsfile|project\.yml|Project\.swift|Workspace\.swift|AndroidManifest\.xml|app\.json|eas\.json|config\.xml|appinfo\.json)$/ ||
          b ~ /\.(csproj|xcscheme|xcconfig)$/ || b ~ /^(app|vite|webpack|next)\.config\.(js|cjs|mjs|ts)$/ ||
          rel ~ /^\.github\/workflows\// || rel ~ /^\.circleci\//) { if (nm < 3 && !(rel in m)) { m[rel] = 1; ml = ml (nm++ ? ", " : "") rel } }
      if (!(top in before)) { if (!(top in a) && na < 3) { a[top] = 1; al = al (na++ ? ", " : "") top } }
      else if (!(top in now)) { if (!(top in r) && nr < 3) { r[top] = 1; rl = rl (nr++ ? ", " : "") top } }
    }
    END {
      s = ""
      if (ml != "") s = "build/dependency manifest changed: " ml
      if (al != "") s = s (s != "" ? "; " : "") "top-level added: " al
      if (rl != "") s = s (s != "" ? "; " : "") "top-level removed: " rl
      print s
    }')"
  detail="$detail${signals:+ signals=$signals}"
  if [ -n "$signals" ] || [ "$n" -ge "${PG_DRIFT_FILES:-30}" ] || [ "$days" -ge "${PG_DRIFT_DAYS:-30}" ]; then
    out stale "$detail"
  fi
  out behind "$detail"
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
ref="${3:-}"
[ -n "$ref" ] || ref="$(PG_NO_FETCH=1 "$here/git-status.sh" "$top" 2>/dev/null | sed -n 's/.*"central":{[^}]*"ref":"\([^"]*\)".*/\1/p')"
if [ -n "$ref" ] && git -C "$top" cat-file -e "$ref:${pp}AUDIT.md" 2>/dev/null &&
   git -C "$top" cat-file -e "$ref:${pp}docs/project/overview.md" 2>/dev/null; then
  out on-central "$ref"
fi
out missing
