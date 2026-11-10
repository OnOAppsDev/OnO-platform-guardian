#!/usr/bin/env bash
# PreToolUse hook (Bash): commit-hygiene guard (G3.5).
#
# When a Bash command runs `git add` / `git stage` / `git commit`, works out
# which NEW files (not yet tracked) it would put into git — `git add --dry-run`
# with the same arguments, plus new files already staged for a commit — and
# checks them against routing/committed-artifacts.json and the project's
# .platform-guardian.json "commitPaths":
#   - on a `neverCommit` list (secrets, plugin scratch)        → deny, always
#   - a document / data / working file (.md .json .yaml .txt .log .html …),
#     or a file an Ono plugin writes (plugin `commit` lists, frontmatter
#     planning docs)                                            → deny: it stays OUT of
#     the commit unless the employee asked for it in chat (the command then
#     carries PG_INCLUDE_FILES=1) or the project lists it in "commitPaths"
#   - anything else (new source code, README / CHANGELOG, known config files) → no output
# Fails open: anything it can't parse → no output, exit 0. Never writes stderr.
#
# Env: PG_COMMIT_GUARD=off disables it; PG_ALLOWLIST overrides the allowlist path.

[ "${PG_COMMIT_GUARD:-}" = "off" ] && exit 0
exec 2>/dev/null

payload="$(cat)"
case "$payload" in *git*) ;; *) exit 0 ;; esac
command -v git >/dev/null || exit 0

here="$(cd "$(dirname "$0")" && pwd)"
allowlist="${PG_ALLOWLIST:-${CLAUDE_PLUGIN_ROOT:-$here/..}/routing/committed-artifacts.json}"
[ -f "$allowlist" ] || exit 0

nl='
'

# json_str KEY [ANCHOR] → unescaped value of the first "KEY":"…" (after ANCHOR, if given).
json_str() {
  printf '%s' "$payload" | awk -v key="$1" -v anchor="${2:-}" '
    { s = s $0 "\n" }
    END {
      if (anchor != "") { i = index(s, "\"" anchor "\""); if (!i) exit; s = substr(s, i) }
      if (!match(s, "\"" key "\"[ \t\r\n]*:[ \t\r\n]*\"")) exit
      s = substr(s, RSTART + RLENGTH); out = ""
      for (j = 1; j <= length(s); j++) {
        c = substr(s, j, 1)
        if (c == "\\") {
          j++; e = substr(s, j, 1)
          if (e == "n") out = out "\n"; else if (e == "t") out = out "\t"
          else if (e == "u") { out = out "?"; j += 4 } else if (e != "r") out = out e
          continue
        }
        if (c == "\"") break
        out = out c
      }
      printf "%s", out
    }'
}

cmd="$(json_str command tool_input)"
case "$cmd" in *git*) ;; *) exit 0 ;; esac
dir="$(json_str cwd)"
[ -d "$dir" ] || dir="${CLAUDE_PROJECT_DIR:-$PWD}"

# --- allowlist → lines "commit<TAB>glob" / "never<TAB>glob" / "except<TAB>glob" --------
rules="$(awk '
  /"(commit|neverCommit|doNotTouch)"[ \t]*:[ \t]*\[/ {
    mode = ($0 ~ /"commit"/) ? "commit" : (($0 ~ /"neverCommit"/) ? "never" : "skip")
    if ($0 ~ /\]/) mode = ""
    next
  }
  mode != "" && /\]/ { mode = ""; next }
  mode == "commit" || mode == "never" {
    if (match($0, /"[^"]*"/)) {
      p = substr($0, RSTART + 1, RLENGTH - 2)
      if (mode == "never" && substr(p, 1, 1) == "!") print "except\t" substr(p, 2)
      else print mode "\t" p
    }
  }' "$allowlist")"
[ -n "$rules" ] || exit 0
[ -n "${PG_GUARD_DUMP_RULES:-}" ] && { printf '%s\n' "$rules"; exit 0; }   # tests only

# glob_match PATH GLOB — git-style: no "/" → basename at any depth; trailing "/" →
# that directory at any depth; `*` (and "**") also cross "/".
glob_match() {
  local path="$1" p="$2"
  case "$p" in
    */) p="${p%/}"; case "/$path/" in */"$p"/*) return 0 ;; esac; return 1 ;;
  esac
  case "$p" in
    */*) p="${p#/}"; case "$path" in $p) return 0 ;; esac ;;
    *) case "${path##*/}" in $p) return 0 ;; esac ;;
  esac
  return 1
}

rule_match() { # rule_match KIND PATH
  local kind glob
  while IFS="	" read -r kind glob; do
    [ "$kind" = "$1" ] && glob_match "$2" "$glob" && return 0
  done <<EOF
$rules
EOF
  return 1
}

# project_paths TOPLEVEL → the project's .platform-guardian.json "commitPaths" globs, one per line
# (read without jq: keep the array on one line).
project_paths() {
  [ -f "$1/.platform-guardian.json" ] || return 0
  sed -n 's/.*"commitPaths"[[:space:]]*:[[:space:]]*\[\([^]]*\)\].*/\1/p' "$1/.platform-guardian.json" \
    | head -n 1 | tr ',' '\n' | sed -n 's/^[[:space:]]*"\([^"]*\)"[[:space:]]*$/\1/p'
}

# classify PATH FILE TOPLEVEL (PATH repo-relative; FILE absolute) → never | stray | ok
classify() {
  local path="$1" file="$2" base="${1##*/}" g
  if ! rule_match except "$path" && rule_match never "$path"; then echo never; return; fi
  while IFS= read -r g; do
    [ -n "$g" ] && glob_match "$path" "$g" && { echo ok; return; }
  done <<PATHS
$(project_paths "$3")
PATHS
  case "$base" in
    README*|CHANGELOG*|LICENSE*|CONTRIBUTING*|CODEOWNERS|SECURITY*|.platform-guardian.json) echo ok; return ;;
    # config files a code change legitimately adds
    .env.example|package.json|package-lock.json|tsconfig*.json|jsconfig*.json|app.json|eas.json|babel.config.json|\
    .eslintrc*|.prettierrc*|Contents.json|pubspec.yaml|pnpm-workspace.yaml|\
    docker-compose*.yml|docker-compose*.yaml) echo ok; return ;;
  esac
  case "$path" in .github/*|.gitlab-ci.yml|.circleci/*) echo ok; return ;; esac
  rule_match commit "$path" && { echo stray; return; }
  case "$base" in
    *.md|*.markdown|*.txt|*.log|*.html|*.htm|*.csv|*.tsv|*.tmp|*.out|*.orig|*.rej|*.patch|*.diff|*.swp|\
    *.json|*.jsonl|*.yaml|*.yml) echo stray ;;
    *) echo ok ;;
  esac
}

# --- walk the command: `cd X`, `git [-C X] add|stage|commit …` -------------------------
new_files=""   # lines "<toplevel><TAB><repo-relative path>"

add_new() { # add_new TOPLEVEL PATHS(newline-separated, repo-relative)
  local top="$1" tracked p
  [ -n "$2" ] || return
  tracked="$(printf '%s\n' "$2" | tr '\n' '\0' | xargs -0 git -C "$top" --literal-pathspecs ls-files --cached -- )"
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    case "$nl$tracked$nl" in *"$nl$p$nl"*) continue ;; esac
    new_files="$new_files$top	$p$nl"
  done <<EOF
$2
EOF
}

segments="$(printf '%s\n' "$cmd" | sed -e 's/&&/\
/g' -e 's/[;|]/\
/g')"

while IFS= read -r seg; do
  # leading VAR=value assignments (e.g. PG_INCLUDE_FILES=1 git add …) don't hide the git command
  seg="$(printf '%s' "$seg" | sed -e 's/^[[:space:]]*//' -e 's/^\([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]][[:space:]]*\)*//')"
  case "$seg" in
    cd|cd\ *|git|git\ *) ;;
    *) continue ;;
  esac
  tokens="$(printf '%s' "$seg" | xargs printf '%s\n')" || tokens=""
  # unbalanced quotes (e.g. a split commit message): still check what a commit would take
  [ -z "$tokens" ] && case "$seg" in git*commit*) tokens="git${nl}commit" ;; esac
  set --
  while IFS= read -r t; do set -- "$@" "$t"; done <<EOF
$tokens
EOF
  [ "$#" -gt 0 ] || continue

  if [ "$1" = cd ]; then
    case "${2:-}" in ''|*'$'*|*'`'*|'~'*) continue ;; esac
    case "$2" in /*) d="$2" ;; *) d="$dir/$2" ;; esac
    [ -d "$d" ] && dir="$d"
    continue
  fi

  shift   # git
  gdir="$dir"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -C) gdir="$(cd "$gdir" && cd "${2:-.}" && pwd)" || continue 2; shift 2 ;;
      -c) shift 2 ;;
      --git-dir*|--work-tree*) continue 2 ;;
      -*) shift ;;
      *) break ;;
    esac
  done
  [ "$#" -gt 0 ] || continue
  sub="$1"; shift
  top="$(git -C "$gdir" rev-parse --show-toplevel)" || continue

  case "$sub" in
    add|stage)
      case "$seg" in *'$'*|*'`'*) continue ;; esac
      # interactive modes would wait for input (and -i ignores --dry-run)
      for a in "$@"; do
        case "$a" in -p|--patch|-i|--interactive|-e|--edit) continue 2 ;; esac
      done
      paths="$(git -C "$gdir" -c core.quotepath=false add --dry-run "$@" \
               | sed -n "s/^add '\(.*\)'\$/\1/p")"
      add_new "$top" "$paths"
      ;;
    commit)
      staged="$(git -C "$top" -c core.quotepath=false diff --cached --name-only --diff-filter=A)"
      [ -n "$staged" ] && new_files="$new_files$(printf '%s\n' "$staged" | sed "s|^|$top	|")$nl"
      ;;
  esac
done <<EOF
$segments
EOF

[ -n "$new_files" ] || exit 0

# the employee asked in chat to include specific files → Claude re-runs with PG_INCLUDE_FILES=1
include=""; case "$cmd" in *PG_INCLUDE_FILES=1*) include=1 ;; esac
never="" stray="" seen="$nl"
while IFS="	" read -r top p; do
  [ -n "$p" ] || continue
  case "$seen" in *"$nl$top/$p$nl"*) continue ;; esac
  seen="$seen$top/$p$nl"
  case "$(classify "$p" "$top/$p" "$top")" in
    never) never="$never$p$nl" ;;
    stray) [ -n "$include" ] || stray="$stray$p$nl" ;;
  esac
done <<EOF
$new_files
EOF

list() { # list LINES → "a, b, c (+N more)"
  printf '%s' "$1" | awk 'NF { n++; if (n <= 10) out = out (n > 1 ? ", " : "") $0 }
    END { if (n > 10) out = out " (+" n - 10 " more)"; printf "%s", out }'
}
json_esc() {
  printf '%s' "$1" | tr -d '\000-\011\013-\037' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' \
    | awk '{ printf "%s%s", (NR > 1 ? "\\n" : ""), $0 }'
}
emit() { # emit DECISION REASON
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"%s","permissionDecisionReason":"%s"}}\n' \
    "$1" "$(json_esc "$2")"
}

if [ -n "$never" ]; then
  emit deny "[platform-guardian] Blocked: these new files must never be committed — secrets or plugin scratch files (routing/committed-artifacts.json): $(list "$never").
Stage only the other files (list paths explicitly, not \`git add .\`) and add these to .gitignore. If the employee really needs one of them in git, they run the git command themselves."
elif [ -n "$stray" ]; then
  emit deny "[platform-guardian] Left out of the commit: these new files are documents, data or plugin working files, not code: $(list "$stray").
Ono rule: only code goes into a commit unless the employee asks for a file. Stage only the other files (list paths explicitly, not \`git add .\` / \`-A\`) and keep these on disk — don't delete them and don't add them to .gitignore. Then tell the employee in one line which files stayed out. If they explicitly want one in, re-run with that path only: \`PG_INCLUDE_FILES=1 git add <path>\`. A project can always commit some paths by listing them in .platform-guardian.json \"commitPaths\"."
fi
exit 0
