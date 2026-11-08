#!/usr/bin/env bash
# Platform Guardian — live-test setup (G1.7; test machine only, never the dev machine).
#
# Usage: live-test-setup.sh <ono-app-repo-git-url> [central-branch]
#   Run from the Guardian clone (docs/live-test.md §0). Creates, under ${PG_TEST_DIR:-~/pg-test}:
#     app/      the work repo, on <central-branch> (default develop), plus the §1 branches
#               pg/behind (3 commits behind central) and pg/clean (= central)
#     scratch/  a one-commit repo with no remote (§1.5)
#   Then prints the §0 table and the §6.1 hook timing, ready to paste into docs/live-test.md.
#   Safe to re-run: existing repos are reused, the pg/* branches are reset.
# Exit 1 if the app repo can't be cloned or has no <central-branch>.

set -u
url="${1:-}"
central="${2:-develop}"
[ -n "$url" ] || { echo "usage: live-test-setup.sh <ono-app-repo-git-url> [central-branch]" >&2; exit 2; }

guardian="$(cd "$(dirname "$0")/.." && pwd)"
root="${PG_TEST_DIR:-$HOME/pg-test}"
app="$root/app"
scratch="$root/scratch"
mkdir -p "$root" || exit 1

if [ ! -d "$app/.git" ]; then
  git clone -q "$url" "$app" || { echo "FAILED  clone $url" >&2; exit 1; }
fi
git -C "$app" fetch -q origin 2>/dev/null
git -C "$app" rev-parse -q --verify "origin/$central" >/dev/null ||
  { echo "no origin/$central in $url — pass the central branch: live-test-setup.sh <url> <branch>" >&2; exit 1; }
git -C "$app" checkout -q -B pg/behind "origin/$central~3" 2>/dev/null ||
  echo "note: $central has fewer than 4 commits — §1.2 (behind) can't be set up" >&2
git -C "$app" checkout -q -B pg/clean "origin/$central"
git -C "$app" checkout -q "$central" 2>/dev/null || git -C "$app" checkout -q -b "$central" "origin/$central"

if [ ! -d "$scratch/.git" ]; then
  mkdir -p "$scratch" && git -C "$scratch" init -q && echo hi >"$scratch/a.txt" &&
    git -C "$scratch" add a.txt && git -C "$scratch" -c user.name=pg -c user.email=pg@example.com commit -qm init
fi

# §6.1 — SessionStart hook wall time in app (real remote; fetch is capped at 5 s).
start=$(date +%s)
(cd "$app" && "$guardian/hooks/session-start.sh" </dev/null >/dev/null 2>&1)
secs=$(( $(date +%s) - start ))

# "❯ name@ono-plugin-marketplace" … "Status: ✔ enabled" blocks → "name (enabled), …"
plugins="$(claude plugin list 2>/dev/null | awk '
  /@ono-plugin-marketplace/ { sub(/.*❯ */, ""); sub(/@.*/, ""); name = $0; next }
  name != "" && /Status:/ { s = ($0 ~ /enabled/) ? "enabled" : "disabled"; out = out (out ? ", " : "") name " (" s ")"; name = "" }
  END { print out }')"

cat <<EOF

Ready. Test repos in $root (app on $central; branches pg/behind, pg/clean; scratch).
Start each §1 case with:  claude --plugin-dir $guardian

Paste into docs/live-test.md:

| Item | Value |
|---|---|
| Claude Code version | $(claude --version 2>/dev/null | head -1) |
| OS | $(uname -sr) · bash ${BASH_VERSION} · $(git --version) |
| Ono plugins installed (\`/plugin\`) | ${plugins:-none found} |
| 6.1 hook time (app, real remote) | ${secs} s (expected < 3 s) |
EOF
