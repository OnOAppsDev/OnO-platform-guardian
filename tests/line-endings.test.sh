#!/usr/bin/env bash
# Every text file of the plugin is checked out with LF on every computer (.gitattributes):
# Claude Code installs plugins with Git, and Git for Windows defaults to core.autocrlf=true,
# which gave the hooks CRLF endings — the shebang becomes `bash\r` and the hook never starts.
# The hook runs directly, as hooks.json does, so the shebang and the executable bit are tested too.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/pg-eol.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
PASS=0 FAIL=0
ok() { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL $1"; [ -n "${2:-}" ] && printf '     got: %s\n' "$2"; }

if ! git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  echo "line-endings: not a git checkout — skipped"; exit 0
fi
# every tracked text file resolves to eol=lf, whatever core.autocrlf says
notlf="$(git -C "$ROOT" ls-files -z | xargs -0 git -C "$ROOT" check-attr text eol -- |
  awk -F': ' '$2 == "text" && $3 == "unset" { bin[$1] = 1 } $2 == "eol" && $3 != "lf" { e[$1] = 1 }
              END { for (f in e) if (!(f in bin)) print f }')"
[ -z "$notlf" ] && ok || bad "every text file is eol=lf" "$notlf"

# a Windows-style install (autocrlf=true) of the committed tree: the hooks stay LF and run
if git -c core.autocrlf=true clone -q --no-local "$ROOT" "$WORK/win" 2>/dev/null; then
  crlf="$(git -C "$WORK/win" ls-files --eol | awk '$2 == "w/crlf" { print $NF }')"
  [ -z "$crlf" ] && ok || bad "autocrlf=true clone has no CRLF files" "$crlf"
  out="$(cd "$WORK" && echo '{}' | CLAUDE_PROJECT_DIR="$WORK" PG_NO_FETCH=1 "$WORK/win/hooks/session-start.sh" 2>&1)"
  case "$out" in *"No such file"*|*"command not found"*|*"syntax error"*|*"Permission denied"*) bad "hook from an autocrlf=true clone runs" "$out" ;; *"[platform-guardian]"*) ok ;; *) bad "hook from an autocrlf=true clone runs" "$out" ;; esac
else
  bad "clone the repo"
fi

echo
echo "line-endings: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
