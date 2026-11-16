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
# On top of that, the EMPLOYEE confirms in a permission prompt ("ask"), never Claude alone:
#   - every `git commit` and `git push` — no commit or push without the employee's explicit OK;
#   - every PG_INCLUDE_FILES=1 add of non-code files — the flag alone no longer lets them in.
# Protected branches (scripts/protected-branch.sh: main, master, the project's central branch when
# certain): a `git commit` on one, or a `git push` whose target is one → deny, before anything else.
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
  # the Ono Project Inspector's outputs are mandatory project infrastructure (the inspect gate
  # reads them) — committed so the whole team shares one inspection
  case "$path" in AUDIT.md|CLAUDE.md|docs/project/*|audits/*|.ono/state.json|.ono/repo-knowledge.json) echo ok; return ;; esac
  # …also when the project lives in a subfolder (yestvos/YesTVOS/): <sub>/docs/project/x.md is an
  # inspector output if <sub> holds the inspector's AUDIT.md or .ono/state.json
  local sub=""
  case "$path" in
    */docs/project/*) sub="${path%%/docs/project/*}" ;;
    */audits/*)       sub="${path%%/audits/*}" ;;
    */.ono/state.json|*/.ono/repo-knowledge.json) sub="${path%/.ono/*}" ;;
    */AUDIT.md|*/CLAUDE.md) sub="${path%/*}" ;;
  esac
  if [ -n "$sub" ] && { [ -f "$3/$sub/.ono/state.json" ] ||
       { [ -f "$3/$sub/AUDIT.md" ] && head -5 "$3/$sub/AUDIT.md" | grep -q '^# AUDIT\.md'; }; }; then
    echo ok; return
  fi
  rule_match commit "$path" && { echo stray; return; }
  case "$base" in
    *.md|*.markdown|*.txt|*.log|*.html|*.htm|*.csv|*.tsv|*.tmp|*.out|*.orig|*.rej|*.patch|*.diff|*.swp|\
    *.json|*.jsonl|*.yaml|*.yml) echo stray ;;
    *) echo ok ;;
  esac
}

# --- walk the command: `cd X`, `git [-C X] add|stage|commit …` -------------------------
new_files=""   # lines "<toplevel><TAB><repo-relative path>"
commits="" pushes=""   # branch per `git commit` / `git push` in the command
blocked=""             # "commit on X" / "push to X" where X is a protected branch
switched=""            # `git switch -c X` / `checkout -b X` earlier in the same command → later
                       # commits / pushes happen on X, not on today's branch

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

segments="$(printf '%s\n' "$cmd" | awk '{ if (sub(/\\$/, "")) printf "%s ", $0; else print }' | sed -e 's/&&/\
/g' -e 's/[;|]/\
/g')"

while IFS= read -r seg; do
  # leading VAR=value assignments (e.g. PG_INCLUDE_FILES=1 git add …) don't hide the git command
  # …nor do shell wrappers: ( { if/then/do/else, env, command; and a trailing ) or }
  seg="$(printf '%s' "$seg" | sed -E -e 's/^[[:space:]]+//' \
    -e 's/^(([({][[:space:]]*)|((if|then|do|else|env|command|exec|time)[[:space:]]+))*//' \
    -e 's/^([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*//' \
    -e 's/[[:space:]]*[)}]+[[:space:]]*$//')"
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

  branch_now() { [ -n "$switched" ] && printf '%s' "$switched" ||
    git -C "$top" symbolic-ref --short -q HEAD 2>/dev/null || git -C "$top" rev-parse --abbrev-ref HEAD 2>/dev/null; }
  case "$sub" in
    switch|checkout)
      while [ "$#" -gt 0 ]; do
        case "$1" in
          -c|-C|-b|-B|--create|--force-create) [ -n "${2:-}" ] && switched="$2"; break ;;
          --create=*|--force-create=*) switched="${1#*=}"; break ;;
          -c?*|-C?*|-b?*|-B?*) switched="${1#-?}"; break ;;
          --detach|-d|--) break ;;
          -) switched="$(git -C "$top" rev-parse --abbrev-ref '@{-1}' 2>/dev/null)"; break ;;
          -*) ;;
          *) # the last argument and an existing local branch (`checkout <branch> -- <file>` is a file)
             [ "$#" -eq 1 ] && git -C "$top" show-ref --verify -q "refs/heads/$1" && switched="$1"; break ;;
        esac
        shift
      done
      ;;
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
    push)
      cur="$(branch_now)"
      pushes="$pushes$cur$nl"
      # targets: refspec destinations (src:dst, or a bare name), none given → the current branch
      remote="" targets="" skip="" every="" tags=""
      for a in "$@"; do
        [ -n "$skip" ] && { skip=""; continue; }
        case "$a" in
          --repo) remote="(repo)"; skip=1; continue ;;
          --repo=*) remote="(repo)"; continue ;;
          -o|--push-option|--receive-pack|--exec) skip=1; continue ;;
          --all|--mirror|--branches) every=1; continue ;;
          --tags) tags=1; continue ;;
          -*) continue ;;
        esac
        [ -z "$remote" ] && { remote="$a"; continue; }
        t="${a#+}"; t="${t##*:}"; t="${t#refs/}"; t="${t#heads/}"
        [ "$t" = HEAD ] || [ "$t" = @ ] || [ -z "$t" ] && t="$cur"
        targets="$targets$t$nl"
      done
      # --all / --mirror push every local branch; --tags alone pushes no branch
      [ -n "$every" ] && targets="$targets$(git -C "$top" for-each-ref --format='%(refname:short)' refs/heads)$nl"
      [ -n "$targets" ] || [ -n "$tags" ] || targets="$cur$nl"
      while IFS= read -r t; do
        [ -n "$t" ] && "$here/../scripts/protected-branch.sh" is "$t" "$top" &&
          blocked="${blocked}push to $t$nl"
      done <<EOF
$targets
EOF
      ;;
    commit)
      cur="$(branch_now)"
      commits="$commits$cur$nl"
      # a first commit in a brand-new project (no commits yet) isn't guarded — nothing to protect
      if [ -n "$switched" ] || git -C "$top" rev-parse -q --verify HEAD >/dev/null; then
        "$here/../scripts/protected-branch.sh" is "$cur" "$top" && blocked="${blocked}commit on $cur$nl"
      fi
      staged="$(git -C "$top" -c core.quotepath=false diff --cached --name-only --diff-filter=A)"
      [ -n "$staged" ] && new_files="$new_files$(printf '%s\n' "$staged" | sed "s|^|$top	|")$nl"
      ;;
  esac
done <<EOF
$segments
EOF

if [ -z "$commits$pushes" ] && printf '%s' "$cmd" | grep -Eq \
   '(^|[^[:alnum:]_./-])git([[:space:]]+(-[Cc][[:space:]]+[^[:space:]]+|-[^[:space:]]+))*[[:space:]]+(commit|push)([^[:alnum:]_-]|$)'; then
  unparsed=1
fi
[ -n "$new_files$commits$pushes${unparsed:-}" ] || exit 0

# the employee asked in chat to include specific files → Claude re-runs with PG_INCLUDE_FILES=1,
# and the employee still confirms them in the permission prompt below
include=""; case "$cmd" in *PG_INCLUDE_FILES=1*) include=1 ;; esac
never="" stray="" included="" seen="$nl"
while IFS="	" read -r top p; do
  [ -n "$p" ] || continue
  case "$seen" in *"$nl$top/$p$nl"*) continue ;; esac
  seen="$seen$top/$p$nl"
  case "$(classify "$p" "$top/$p" "$top")" in
    never) never="$never$p$nl" ;;
    stray) if [ -n "$include" ]; then included="$included$p$nl"; else stray="$stray$p$nl"; fi ;;
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

if [ -n "$blocked" ]; then
  emit deny "[platform-guardian] Blocked: $(list "$(printf '%s' "$blocked" | sort -u)") — a protected branch (main, master or this project's central branch). Ono rule: work goes into a PR, never straight onto a protected branch.
Tell the employee in one line. If the work is on the protected branch, offer to move it to a work branch: ask for a short name, then \`git switch -c <name>\` (uncommitted changes move with it), commit there and open a PR. If they really need it, they run the git command themselves."
elif [ -n "$never" ]; then
  emit deny "[platform-guardian] Blocked: these new files must never be committed — secrets or plugin scratch files (routing/committed-artifacts.json): $(list "$never").
Stage only the other files (list paths explicitly, not \`git add .\`) and add these to .gitignore. If the employee really needs one of them in git, they run the git command themselves."
elif [ -n "$stray" ]; then
  emit deny "[platform-guardian] Left out of the commit: these new files are documents, data or plugin working files, not code: $(list "$stray").
Ono rule: only code goes into a commit unless the employee asks for a file. Stage only the other files (list paths explicitly, not \`git add .\` / \`-A\`) and keep these on disk — don't delete them and don't add them to .gitignore. Then tell the employee in one line which files stayed out. Only if the employee explicitly named a file to include, re-run with that path only: \`PG_INCLUDE_FILES=1 git add <path>\` — the employee then confirms it in a permission prompt; never use it on your own. A project can always commit some paths by listing them in .platform-guardian.json \"commitPaths\"."
else
  why=""
  [ -n "$included" ] && why="$why
• Add non-code files to git: $(list "$included") — approve only if YOU asked for these files."
  [ -n "$commits" ] && why="$why
• Commit on $(list "$(printf '%s' "$commits" | sort -u)") — approve only if you asked for a commit (e.g. \"close the session\")."
  [ -n "$pushes" ] && why="$why
• Push $(list "$(printf '%s' "$pushes" | sort -u)") to the server — approve only if you asked for it."
  [ -n "${unparsed:-}" ] && why="$why
• Run a git commit or push (inside a command Guardian can't fully read) — approve only if you asked for it, and never onto main, master or the project's main branch."
  [ -n "$why" ] && emit ask "[platform-guardian] Claude wants to:$why
Nothing goes into git or to the server without your OK. Not sure? Choose No and ask Claude why."
fi
exit 0
