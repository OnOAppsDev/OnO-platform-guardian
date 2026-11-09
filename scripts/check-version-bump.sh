#!/usr/bin/env bash
# Platform Guardian — version-bump guard (maintainer / CI tool).
#
# Usage: check-version-bump.sh <base-ref>
#   Compares HEAD with <base-ref> (e.g. origin/master). If anything employees
#   run changed — hooks/, skills/, routing/, .claude-plugin/, or a script the
#   hooks and skills call — the "version" in .claude-plugin/plugin.json must be
#   higher than at <base-ref>. Claude Code detects plugin updates by that
#   version, not by commits: without a bump, installed copies never update.
# Exit 0 OK · 1 bump missing / version went down · 2 usage or git error.

set -u
base="${1:-}"
[ -n "$base" ] || { echo "usage: check-version-bump.sh <base-ref>" >&2; exit 2; }
git rev-parse -q --verify "$base^{commit}" >/dev/null 2>&1 || { echo "unknown base ref: $base" >&2; exit 2; }

manifest=.claude-plugin/plugin.json
version_at() { # version_at <rev> → the manifest's "version" at that revision
  git show "$1:$manifest" 2>/dev/null | sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1
}

# Maintainer-only scripts don't change what employees run.
shipped="$(git diff --name-only "$base"...HEAD | grep -E '^(hooks|skills|routing|\.claude-plugin|scripts)/' |
  grep -vE '^scripts/(check-routes|fetch-org-plugins|live-test-setup|check-version-bump|report-drift)\.sh$')"
[ -n "$shipped" ] || { echo "OK — no plugin files changed, no version bump needed."; exit 0; }

old="$(version_at "$base")"
new="$(version_at HEAD)"

# 1 if $1 > $2 (numeric x.y.z; missing parts count as 0)
greater() {
  awk -v a="$1" -v b="$2" 'BEGIN {
    n = split(a, x, "."); m = split(b, y, "."); k = (n > m) ? n : m
    for (i = 1; i <= k; i++) { if (x[i] + 0 > y[i] + 0) exit 0; if (x[i] + 0 < y[i] + 0) exit 1 }
    exit 1 }'
}

if [ -n "$new" ] && { [ -z "$old" ] || greater "$new" "$old"; }; then
  echo "OK — version $old → $new."
  exit 0
fi

echo "Version bump needed: plugin files changed but .claude-plugin/plugin.json is still \"$new\" (was \"$old\")."
echo "Installed copies only update when this number goes up. Bump it (e.g. patch for fixes) and add a CHANGELOG line."
echo "Changed plugin files:"
printf '  %s\n' $shipped
exit 1
