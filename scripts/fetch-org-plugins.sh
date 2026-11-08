#!/usr/bin/env bash
# Platform Guardian — clone every org plugin the marketplace lists (maintainer / CI tool; needs jq).
#
# Usage: fetch-org-plugins.sh <dest-dir> [marketplace-git-url]
#   Clones the marketplace (default: OnOAppsDev/ono-plugin-marketplace), then each plugin
#   in its .claude-plugin/marketplace.json ("url" or "github" sources) at the listed ref
#   (shallow), skipping
#   platform-guardian itself. The result is a <plugins-dir> for check-routes.sh.
# Exit 1 if any clone fails.

set -u
dest="${1:-}"
market="${2:-https://github.com/OnOAppsDev/ono-plugin-marketplace.git}"

command -v jq >/dev/null || { echo "fetch-org-plugins.sh needs jq" >&2; exit 2; }
[ -n "$dest" ] || { echo "usage: fetch-org-plugins.sh <dest-dir> [marketplace-git-url]" >&2; exit 2; }
mkdir -p "$dest" || exit 2

clone() { # clone <url> <ref|""> <dir>
  rm -rf "$3"
  if [ -n "$2" ]; then
    git clone -q --depth 1 --branch "$2" "$1" "$3"
  else
    git clone -q --depth 1 "$1" "$3"
  fi
}

clone "$market" "" "$dest/.marketplace" || { echo "FAILED  marketplace $market" >&2; exit 1; }
manifest="$dest/.marketplace/.claude-plugin/marketplace.json"
[ -f "$manifest" ] || { echo "no .claude-plugin/marketplace.json in $market" >&2; exit 1; }

failed=0
# One line per URL-sourced plugin: name<TAB>url<TAB>ref
while IFS="$(printf '\t')" read -r name url ref; do
  [ "$name" = "platform-guardian" ] && continue
  if clone "$url" "$ref" "$dest/$name"; then
    echo "OK      $name ($url${ref:+ @ $ref})"
  else
    echo "FAILED  $name ($url${ref:+ @ $ref})" >&2; failed=$((failed + 1))
  fi
done <<EOF
$(jq -r '.plugins[] | select(.source | type == "object")
  | (if .source.source == "github" then "https://github.com/\(.source.repo).git" else .source.url end) as $u
  | select($u != null) | [.name, $u, (.source.ref // "")] | @tsv' "$manifest")
EOF

[ "$failed" -eq 0 ]
