#!/usr/bin/env bash
# Platform Guardian — routing drift guard (maintainer / CI tool; needs jq).
#
# Usage: check-routes.sh <plugins-dir> [--strict]
#   <plugins-dir>  folder whose subfolders are plugin checkouts (each with
#                  .claude-plugin/plugin.json), e.g. fresh clones of the org repos.
#
# Checks every command / skill that routing/routes.json references still exists
# in its plugin (commands/<name>.md or skills/<name>/SKILL.md), and that each
# plugin's version matches routes.json "verifiedAgainst".
# Exit 1 if a referenced command is missing or a plugin is not found;
# version drift is a warning (exit 1 only with --strict).

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROUTES="${PG_ROUTES:-$HERE/../routing/routes.json}"
dir="${1:-}"
strict=false; [ "${2:-}" = "--strict" ] && strict=true

command -v jq >/dev/null || { echo "check-routes.sh needs jq" >&2; exit 2; }
[ -d "$dir" ] || { echo "usage: check-routes.sh <plugins-dir> [--strict]" >&2; exit 2; }

errors=0 drift=0

# plugin name → checkout path
find_plugin() {
  local m
  for m in "$dir"/*/.claude-plugin/plugin.json; do
    [ -f "$m" ] || continue
    [ "$(jq -r '.name // empty' "$m")" = "$1" ] && { dirname "$(dirname "$m")"; return; }
  done
}

# Every "/command" token referenced for a plugin (start, pipeline, alternatives, humanOnly)
# plus explicit "<plugin>:<skill>" references.
refs_for() {
  jq -r --arg p "$1" '
    ([.intents[] | select(.plugin == $p) | (.start, (.pipeline // [])[], (.alternatives // [])[])]
     + [.humanOnly.commands[] | select(.plugin == $p) | .command])
    | .[] | strings' "$ROUTES" \
    | grep -oE '(^|[ (])/[a-z][a-z0-9-]+' | sed 's/^[ (]*\///'
  jq -r --arg p "$1" '[.intents[] | select(.plugin == $p) | (.choices // [])[] | .skill] | .[]' "$ROUTES" \
    | sed -n "s/^$1://p" | sed 's/^/skill:/'
}

for plugin in $(jq -r '.verifiedAgainst | keys[]' "$ROUTES"); do
  want="$(jq -r --arg p "$plugin" '.verifiedAgainst[$p]' "$ROUTES")"
  path="$(find_plugin "$plugin")"
  if [ -z "$path" ]; then
    echo "MISSING PLUGIN  $plugin (not found under $dir)"; errors=$((errors + 1)); continue
  fi
  have="$(jq -r '.version // "?"' "$path/.claude-plugin/plugin.json")"
  if [ "$have" != "$want" ]; then
    echo "VERSION DRIFT   $plugin: routes.json verified $want, plugin is $have — re-verify routes"
    drift=$((drift + 1))
  fi
  for ref in $(refs_for "$plugin" | sort -u); do
    case "$ref" in
      skill:*) name="${ref#skill:}"; f="$path/skills/$name/SKILL.md" ;;
      *) name="$ref"; f="$path/commands/$name.md" ;;
    esac
    if [ ! -f "$f" ]; then
      echo "MISSING COMMAND $plugin: $name (expected ${f#"$path"/})"; errors=$((errors + 1))
    fi
  done
done

# Inspect gate vs the inspector's registry: the files Guardian treats as "inspection complete"
# (scripts/inspect-status.sh STAGE_ARTIFACTS + AUDIT.md) and "older knowledge model"
# (MODEL_ARTIFACTS) must match skills/registry.json — a new inspector artifact would otherwise
# block employees (or let incomplete inspections through) until someone notices.
ipath="$(find_plugin ono-project-inspector)"
if [ -n "$ipath" ] && [ -f "$ipath/skills/registry.json" ]; then
  reg="$ipath/skills/registry.json"; status_sh="$(dirname "$0")/inspect-status.sh"
  want_stage="$(jq -r '[.skills[] | select(.type == "workflow" and ((.workflowRole // "inspection") == "inspection")
      and ((.completion // "artifacts") == "artifacts"))
      | (.produces // []) - [(.knowledgeModel // [])[] | select(contains("#") | not)] | .[]] | .[]' "$reg" | sort -u | tr '\n' ' ')"
  want_model="$(jq -r '[.skills[] | (.knowledgeModel // [])[] | select(contains("#") | not)] | .[]' "$reg" | sort -u | tr '\n' ' ')"
  have_stage="$( { sed -n 's/^STAGE_ARTIFACTS="\(.*\)"$/\1/p' "$status_sh" | tr ' ' '\n'; echo AUDIT.md; } | grep . | sort -u | tr '\n' ' ')"
  have_model="$(sed -n 's/^MODEL_ARTIFACTS="\(.*\)"$/\1/p' "$status_sh" | tr ' ' '\n' | grep . | sort -u | tr '\n' ' ')"
  if [ "$want_stage" != "$have_stage" ]; then
    echo "INSPECT DRIFT   stage artifacts: inspector registry has [${want_stage% }], inspect-status.sh has [${have_stage% }] — update STAGE_ARTIFACTS (resume-state.sh reads the same list)"
    errors=$((errors + 1))
  fi
  if [ "$want_model" != "$have_model" ]; then
    echo "INSPECT DRIFT   knowledge-model artifacts: inspector registry has [${want_model% }], inspect-status.sh has [${have_model% }] — update MODEL_ARTIFACTS"
    errors=$((errors + 1))
  fi
fi

echo "check-routes: $errors error(s), $drift version drift(s)"
[ "$errors" -eq 0 ] || exit 1
$strict && [ "$drift" -gt 0 ] && exit 1
exit 0
