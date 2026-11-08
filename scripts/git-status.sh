#!/usr/bin/env bash
# Platform Guardian — deterministic git report for the session opener.
#
# Usage: git-status.sh [dir]
#   dir defaults to $CLAUDE_PROJECT_DIR, then the current directory.
#
# Prints exactly one JSON object on stdout and always exits 0 (fails open):
# outside a repo, or on any git error, it still prints valid JSON.
#
# Central-branch detection order (docs/vision.md):
#   .platform-guardian.json "centralBranch" → origin/HEAD → develop → main → master
#
# Environment:
#   PG_NO_FETCH=1         skip `git fetch` (numbers reflect the last fetch)
#   PG_FETCH_TIMEOUT=N    seconds before the fetch is abandoned (default 5)
#
# Portable to macOS bash 3.2; needs only git (no jq).

SCHEMA=1
FETCH_TIMEOUT="${PG_FETCH_TIMEOUT:-5}"
case "$FETCH_TIMEOUT" in ''|*[!0-9]*) FETCH_TIMEOUT=5 ;; esac
MAX_FILES=20

# ---------- JSON helpers ----------

json_str() {
  # JSON-encode $1 (quoted). Escapes \, ", and control characters.
  local s="$1" out="" c i
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  # Any remaining C0 control characters → \u00XX.
  case "$s" in
    *[$'\001'-$'\037']*)
      for ((i = 0; i < ${#s}; i++)); do
        c="${s:i:1}"
        case "$c" in
          [$'\001'-$'\037']) out="$out$(printf '\\u%04x' "'$c")" ;;
          *) out="$out$c" ;;
        esac
      done
      s="$out"
      ;;
  esac
  printf '"%s"' "$s"
}

json_str_or_null() {
  if [ -n "$1" ]; then json_str "$1"; else printf 'null'; fi
}

json_num_or_null() {
  case "$1" in
    ''|*[!0-9]*) printf 'null' ;;
    *) printf '%s' "$1" ;;
  esac
}

WARNINGS=""
warn() {
  WARNINGS="$WARNINGS${WARNINGS:+,}$(json_str "$1")"
}

# ---------- target directory ----------

target="${1:-${CLAUDE_PROJECT_DIR:-$PWD}}"

if ! cd "$target" 2>/dev/null; then
  printf '{"schema":%s,"repo":false,"cwd":%s,"warnings":["dir-not-found"]}\n' \
    "$SCHEMA" "$(json_str "$target")"
  exit 0
fi

if ! command -v git >/dev/null 2>&1; then
  printf '{"schema":%s,"repo":false,"cwd":%s,"warnings":["git-not-installed"]}\n' \
    "$SCHEMA" "$(json_str "$PWD")"
  exit 0
fi

if [ "$(git rev-parse --is-inside-work-tree 2>/dev/null)" != "true" ]; then
  printf '{"schema":%s,"repo":false,"cwd":%s,"warnings":[]}\n' \
    "$SCHEMA" "$(json_str "$PWD")"
  exit 0
fi

start_dir="$PWD"
root="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -n "$root" ] && cd "$root" 2>/dev/null

# ---------- HEAD ----------

branch="$(git symbolic-ref -q --short HEAD 2>/dev/null)"
head="$(git rev-parse -q --verify --short HEAD 2>/dev/null)"
detached=false
[ -z "$branch" ] && detached=true && warn "detached-head"
unborn=false
[ -z "$head" ] && unborn=true && warn "unborn-head"

# ---------- remote + fetch ----------

remote=""
remotes="$(git remote 2>/dev/null)"
if [ -n "$remotes" ]; then
  if printf '%s\n' "$remotes" | grep -qx origin; then
    remote=origin
  else
    remote="$(printf '%s\n' "$remotes" | head -n 1)"
  fi
fi

fetch="no-remote"
if [ -z "$remote" ]; then
  warn "no-remote"
elif [ "${PG_NO_FETCH:-}" = "1" ]; then
  fetch="skipped"
else
  # Never prompt for credentials; never hang the session start.
  export GIT_TERMINAL_PROMPT=0 GCM_INTERACTIVE=never
  [ -z "${GIT_SSH_COMMAND:-}" ] && \
    export GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=$FETCH_TIMEOUT"
  git fetch --quiet --no-tags "$remote" </dev/null >/dev/null 2>&1 &
  pid=$!
  ticks=0
  limit=$((FETCH_TIMEOUT * 10))
  timed_out=false
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$ticks" -ge "$limit" ]; then
      pkill -TERM -P "$pid" 2>/dev/null
      kill -TERM "$pid" 2>/dev/null
      timed_out=true
      break
    fi
    sleep 0.1
    ticks=$((ticks + 1))
  done
  wait "$pid" 2>/dev/null
  rc=$?
  if $timed_out; then
    fetch="timeout"; warn "fetch-timeout"
  elif [ "$rc" -eq 0 ]; then
    fetch="ok"
  else
    fetch="failed"; warn "fetch-failed"
  fi
fi

# ---------- central branch ----------

# ref_for NAME → prints the ref to compare against (remote-tracking if a remote
# exists, else the local branch), or nothing if the branch is unknown.
ref_for() {
  if [ -n "$remote" ]; then
    git show-ref -q --verify "refs/remotes/$remote/$1" 2>/dev/null && { printf '%s/%s' "$remote" "$1"; return; }
  fi
  git show-ref -q --verify "refs/heads/$1" 2>/dev/null && printf '%s' "$1"
}

central="" central_ref="" source="none" confidence="none"

# 1. Project override.
override=""
if [ -f .platform-guardian.json ]; then
  override="$(sed -n 's/.*"centralBranch"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' .platform-guardian.json | head -n 1)"
  if [ -n "$override" ]; then
    if git check-ref-format --branch "$override" >/dev/null 2>&1 && r="$(ref_for "$override")" && [ -n "$r" ]; then
      central="$override"; central_ref="$r"; source="override"; confidence="high"
    else
      warn "override-not-found"
    fi
  fi
fi

# Fallback candidates that exist (develop/main/master).
candidates=""
for name in develop main master; do
  [ -n "$(ref_for "$name")" ] && candidates="$candidates $name"
done
candidates="${candidates# }"
n_candidates=0
for _ in $candidates; do n_candidates=$((n_candidates + 1)); done

# 2. origin/HEAD (the remote's default branch, as recorded at clone time).
if [ -z "$central" ] && [ -n "$remote" ]; then
  sym="$(git symbolic-ref -q --short "refs/remotes/$remote/HEAD" 2>/dev/null)"
  if [ -n "$sym" ] && git show-ref -q --verify "refs/remotes/$sym" 2>/dev/null; then
    central="${sym#"$remote"/}"; central_ref="$sym"; source="origin-head"
    # Default is main/master but a develop branch also exists → ambiguous.
    if [ "$central" != "develop" ] && printf ' %s ' "$candidates" | grep -q ' develop '; then
      confidence="medium"; warn "central-ambiguous"
    else
      confidence="high"
    fi
  fi
fi

# 3–5. develop → main → master.
if [ -z "$central" ] && [ -n "$candidates" ]; then
  set -- $candidates
  central="$1"; central_ref="$(ref_for "$1")"; source="$1"
  # Medium only for a single candidate that exists on the remote.
  if [ "$n_candidates" -eq 1 ] && [ "$central_ref" = "$remote/$1" ]; then
    confidence="medium"
  else
    confidence="low"; warn "central-ambiguous"
  fi
fi

[ -z "$central" ] && warn "central-unknown"

# ---------- position vs central / upstream ----------

on_central=false
[ -n "$central" ] && [ "$branch" = "$central" ] && on_central=true && warn "on-central"

ahead="" behind=""
if [ -n "$central_ref" ] && ! $unborn; then
  counts="$(git rev-list --left-right --count "HEAD...$central_ref" 2>/dev/null)"
  ahead="${counts%%[[:space:]]*}"
  behind="${counts##*[[:space:]]}"
  case "$behind" in ''|*[!0-9]*) ;; 0) ;; *) warn "behind-central" ;; esac
fi

upstream="" up_ahead="" up_behind=""
if [ -n "$branch" ] && ! $unborn; then
  upstream="$(git rev-parse -q --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)"
  if [ -n "$upstream" ]; then
    counts="$(git rev-list --left-right --count "HEAD...$upstream" 2>/dev/null)"
    up_ahead="${counts%%[[:space:]]*}"
    up_behind="${counts##*[[:space:]]}"
  fi
fi

# ---------- working tree ----------

staged=0 unstaged=0 untracked=0 conflicted=0 n_files=0 files="" skip_next=false
# -z: NUL-separated, paths never quoted; a rename/copy is followed by its source path.
while IFS= read -r -d '' rec; do
  if $skip_next; then skip_next=false; continue; fi
  [ -z "$rec" ] && continue
  xy="${rec:0:2}"
  path="${rec:3}"
  case "$xy" in
    R*|C*) skip_next=true ;;
  esac
  case "$xy" in
    '??') untracked=$((untracked + 1)) ;;
    DD|AU|UD|UA|DU|AA|UU) conflicted=$((conflicted + 1)) ;;
    *)
      [ "${xy:0:1}" != " " ] && staged=$((staged + 1))
      [ "${xy:1:1}" != " " ] && unstaged=$((unstaged + 1))
      ;;
  esac
  n_files=$((n_files + 1))
  if [ "$n_files" -le "$MAX_FILES" ]; then
    files="$files${files:+,}{\"status\":$(json_str "$xy"),\"path\":$(json_str "$path")}"
  fi
done < <(git status --porcelain=v1 -z --untracked-files=normal 2>/dev/null)
dirty=false
[ "$n_files" -gt 0 ] && dirty=true

# ---------- operation in progress ----------

operation=""
gp() { git rev-parse --git-path "$1" 2>/dev/null; }
if [ -d "$(gp rebase-merge)" ] || [ -d "$(gp rebase-apply)" ]; then operation="rebase"
elif [ -f "$(gp MERGE_HEAD)" ]; then operation="merge"
elif [ -f "$(gp CHERRY_PICK_HEAD)" ]; then operation="cherry-pick"
elif [ -f "$(gp REVERT_HEAD)" ]; then operation="revert"
elif [ -f "$(gp BISECT_LOG)" ]; then operation="bisect"
fi
[ -n "$operation" ] && warn "operation-in-progress"

# ---------- org-plugin guards ----------

# Matrix QA's guard hook denies every git write and `gh pr create` from Claude
# inside a repo that has matrix-qa.config.json at or above the session dir.
matrix_qa=false
d="$start_dir"
while [ -n "$d" ]; do
  [ -f "$d/matrix-qa.config.json" ] && { matrix_qa=true; break; }
  [ "$d" = "/" ] && break
  d="$(dirname "$d")"
done
$matrix_qa && warn "matrix-qa-git-blocked"

# ono-plugin-qa's hook blocks `git commit` / `git push` from Claude in the QA
# repo: the one named by .claude/qa-workspace.json (qaRepoPath), else any repo
# whose folder name contains "qa". Mirrors hooks/block-qa-repo-git-writes.sh.
ono_qa=false
if ! grep -q '"name"[[:space:]]*:[[:space:]]*"ono-plugin-qa"' .claude-plugin/plugin.json 2>/dev/null; then
  ws=""
  for cand in "$(dirname "$PWD")" "$start_dir"; do
    [ -f "$cand/.claude/qa-workspace.json" ] && { ws="$cand"; break; }
  done
  qa_path=""
  [ -n "$ws" ] && qa_path="$(sed -n 's/.*"qaRepoPath"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$ws/.claude/qa-workspace.json" | head -n 1)"
  if [ -n "$qa_path" ]; then
    case "$qa_path" in /*) ;; *) qa_path="$ws/$qa_path" ;; esac
    qa_root="$(cd "$qa_path" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)"
    [ -n "$qa_root" ] && [ "$qa_root" = "$PWD" ] && ono_qa=true
  else
    case "$(basename "$PWD" | tr '[:upper:]' '[:lower:]')" in *qa*) ono_qa=true ;; esac
  fi
fi
$ono_qa && warn "ono-qa-commit-blocked"

# ---------- output ----------

printf '{'
printf '"schema":%s,' "$SCHEMA"
printf '"repo":true,'
printf '"root":%s,' "$(json_str "$PWD")"
printf '"branch":%s,' "$(json_str_or_null "$branch")"
printf '"detached":%s,' "$detached"
printf '"head":%s,' "$(json_str_or_null "$head")"
printf '"remote":%s,' "$(json_str_or_null "$remote")"
printf '"fetch":%s,' "$(json_str "$fetch")"
printf '"central":{"branch":%s,"ref":%s,"source":%s,"confidence":%s,"candidates":[' \
  "$(json_str_or_null "$central")" "$(json_str_or_null "$central_ref")" \
  "$(json_str "$source")" "$(json_str "$confidence")"
sep=""
for name in $candidates; do printf '%s%s' "$sep" "$(json_str "$name")"; sep=","; done
printf ']},'
printf '"onCentral":%s,' "$on_central"
printf '"ahead":%s,' "$(json_num_or_null "$ahead")"
printf '"behind":%s,' "$(json_num_or_null "$behind")"
if [ -n "$upstream" ]; then
  printf '"upstream":{"ref":%s,"ahead":%s,"behind":%s},' \
    "$(json_str "$upstream")" "$(json_num_or_null "$up_ahead")" "$(json_num_or_null "$up_behind")"
else
  printf '"upstream":null,'
fi
printf '"dirty":%s,' "$dirty"
printf '"changes":{"staged":%s,"unstaged":%s,"untracked":%s,"conflicted":%s,"total":%s,"files":[%s],"truncated":%s},' \
  "$staged" "$unstaged" "$untracked" "$conflicted" "$n_files" "$files" \
  "$([ "$n_files" -gt "$MAX_FILES" ] && echo true || echo false)"
printf '"operation":%s,' "$(json_str_or_null "$operation")"
printf '"guards":{"matrixQa":%s,"onoQaCommitBlocked":%s},' "$matrix_qa" "$ono_qa"
printf '"warnings":[%s]' "$WARNINGS"
printf '}\n'
exit 0
