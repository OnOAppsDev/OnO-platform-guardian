#!/usr/bin/env bash
# Platform Guardian — turn the daily drift check into one GitHub issue (CI tool; needs gh).
#
# Usage: report-drift.sh open  <check-routes-output-file>
#        report-drift.sh close
#   open  → no open "plugin-drift" issue: create one (assigned to $PG_DRIFT_ASSIGNEE);
#           one exists: comment only if the findings changed since it was last updated.
#   close → close the open "plugin-drift" issue, if any (drift is gone).
# Env: GH_TOKEN (CI), GITHUB_REPOSITORY, PG_DRIFT_ASSIGNEE (default tomzion90).

set -u
cmd="${1:-}"
label="plugin-drift"
assignee="${PG_DRIFT_ASSIGNEE:-tomzion90}"
repo="${GITHUB_REPOSITORY:-OnOAppsDev/ono-platform-guardian}"
marker="<!-- drift-findings -->"

open_issue() { gh issue list -R "$repo" --label "$label" --state open --json number -q '.[0].number' 2>/dev/null; }

case "$cmd" in
  open)
    out="${2:-}"; [ -f "$out" ] || { echo "usage: report-drift.sh open <file>" >&2; exit 2; }
    findings="$(grep -E '^(MISSING|VERSION DRIFT)|^check-routes:' "$out" | head -n 40)"
    [ -n "$findings" ] || findings="$(tail -n 40 "$out")"
    block="$marker
\`\`\`
$findings
\`\`\`"
    gh label create "$label" -R "$repo" --color D93F0B --description "An Ono plugin changed; Guardian's routing needs a look" >/dev/null 2>&1
    n="$(open_issue)"
    if [ -z "$n" ]; then
      gh issue create -R "$repo" --label "$label" --assignee "$assignee" \
        --title "An Ono plugin changed — update Guardian's routing" \
        --body "The daily check found that one of the six Ono plugins changed since Guardian last verified it.

$block

**What to do:** open a Claude Code session in \`ono-platform-guardian\` and say: *\"fix plugin drift issue — see the latest drift issue\"*. Claude updates \`routing/routes.json\` (and the resume formats if a document format changed), bumps the version, and merges. This issue closes by itself once the check passes again.

Until then employees already have the new plugin version, so a routed command may point to something that moved."
    else
      prev="$(gh issue view "$n" -R "$repo" --json body,comments -q '[.body] + [.comments[].body] | map(select(contains("drift-findings"))) | last' 2>/dev/null)"
      case "$prev" in
        *"$findings"*) echo "issue #$n already has these findings" ;;
        *) gh issue comment "$n" -R "$repo" --body "The findings changed:

$block" ;;
      esac
    fi
    ;;
  close)
    n="$(open_issue)"
    [ -n "$n" ] && gh issue close "$n" -R "$repo" --comment "✅ The daily check passes again — Guardian matches the Ono plugins."
    exit 0
    ;;
  *) echo "usage: report-drift.sh open <file> | close" >&2; exit 2 ;;
esac
