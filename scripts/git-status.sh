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
#   .platform-guardian.json "centralBranch" → the employee's answer on this computer → origin/HEAD
#   (main/master with a develop/dev beside it: the history decides, see below) → develop → dev → main → master
#   (origin/HEAD with an unusual name while a conventional branch exists, or a branch thousands of
#   commits ahead of it, is suspect → confidence low + central-ambiguous: the opener asks once)
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

gs_scripts="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"   # before the cd below
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
  # One watchdog timer, not a polling loop: a count of `sleep 0.1`s drifts on a slow laptop
  # (each is a process start). If the watchdog is gone when the fetch ends, it fired.
  ( sleep "$FETCH_TIMEOUT"; pkill -TERM -P "$pid"; kill -TERM "$pid" ) >/dev/null 2>&1 &
  dog=$!
  wait "$pid" 2>/dev/null
  rc=$?
  timed_out=true
  if kill -0 "$dog" 2>/dev/null; then
    timed_out=false
    pkill -TERM -P "$dog" 2>/dev/null
    kill -TERM "$dog" 2>/dev/null
  fi
  wait "$dog" 2>/dev/null
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

# 1b. The employee's own answer on this computer (session opener, protected-branch.sh answer):
# asked once per repo, not every session, even before the team's .platform-guardian.json is merged.
if [ -z "$central" ] && [ -z "$override" ]; then
  # read directly (a process start costs on Windows); the key is protected-branch.sh's cache_file
  k="${root//_/__}"; k="${k// /+}"; answered=""
  f="${PG_LOG_DIR:-$HOME/.claude/platform-guardian}/.state/answered-central${k//\//_}"
  [ -f "$f" ] && IFS= read -r answered <"$f"
  if [ -n "$answered" ] && r="$(ref_for "$answered")" && [ -n "$r" ]; then
    central="$answered"; central_ref="$r"; source="answered"; confidence="high"
  fi
fi

# Fallback candidates that exist (develop/dev/main/master).
candidates=""
for name in develop dev main master; do
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
    case "$central" in
      develop|dev|main|master|trunk) unusual=false ;;
      *) unusual=true ;;
    esac
    if $unusual && [ -n "$candidates" ]; then
      # e.g. a feature / staging branch set as the remote's default → don't trust it, ask
      confidence="low"; warn "central-ambiguous"
      printf ' %s ' "$candidates" | grep -q " $central " || candidates="$candidates $central"
    # Default is main/master but a develop / dev branch also exists. The history decides
    # (git-flow — Guy's report, 2026-11-24): when master holds no commit of its own except merge
    # commits (releases merged in from develop / release branches), and the two differ, work lands
    # on develop → develop. A merge commit alone never counts as master's own work: right after a
    # develop→master release, master is 1 merge ahead and develop must still win. Anything else
    # (master has real commits of its own, or the two are identical) → ambiguous: the opener asks
    # once and remembers. The rule never picks master with confidence: a fresh hotfix on master
    # looks just like a stale develop.
    elif [ "$central" != "develop" ] && [ "$central" != "dev" ] &&
         printf ' %s ' "$candidates" | grep -Eq ' (develop|dev) '; then
      case " $candidates " in *" develop "*) dname=develop ;; *) dname=dev ;; esac
      dref="$(ref_for "$dname")"
      split="$(git rev-list --left-right --count "$dref...$central_ref" 2>/dev/null)"
      d_all="${split%%[[:space:]]*}"; m_all="${split##*[[:space:]]}"
      m_real=""
      case "$d_all:$m_all" in
        *[!0-9:]*|:*|*:|0:0) ;;
        *) m_real="$(git rev-list --count --no-merges "$dref..$central_ref" 2>/dev/null)" ;;
      esac
      if [ "$m_real" = 0 ]; then
        central="$dname"; central_ref="$dref"; source="gitflow"; confidence="high"
      else
        confidence="medium"; warn "central-ambiguous"
      fi
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
  # thousands of commits ahead of the "central" branch: almost surely the wrong central → ask
  case "$ahead" in ''|*[!0-9]*) ;; *)
    if [ "$source" != "override" ] && [ "$source" != "answered" ] && [ "$ahead" -gt "${PG_SUSPECT_AHEAD:-1000}" ] && [ "$confidence" != "low" ]; then
      confidence="low"
      case "$WARNINGS" in *central-ambiguous*) ;; *) warn "central-ambiguous" ;; esac
    fi ;;
  esac
fi

upstream="" up_ahead="" up_behind=""
if [ -n "$branch" ] && ! $unborn; then
  # Trust the exit status, not the output: newer git (2.4x) echoes "@{u}" on stdout when there is no upstream.
  upstream="$(git rev-parse -q --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)" || upstream=""
  [ "$upstream" = "@{u}" ] && upstream=""
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
# Guardian no longer brings that plugin (0.5.0): report it only while it's
# installed (unknown plugin list → assume it is).
matrix_qa=false
plugins_file="${PG_PLUGINS_FILE:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/installed_plugins.json}"
d="$start_dir"
[ -f "$plugins_file" ] && ! grep -q '"matrix-qa-plugin@' "$plugins_file" 2>/dev/null && d=""
while [ -n "$d" ]; do
  [ -f "$d/matrix-qa.config.json" ] && { matrix_qa=true; break; }
  [ "$d" = "/" ] && break
  d="$(dirname "$d")"
done
$matrix_qa && warn "matrix-qa-git-blocked"

# ono-plugin-qa's hook blocks `git commit` / `git push` from Claude in the QA
# repo: the one named by .claude/qa-workspace.json (qaRepoPath), else any repo
# whose folder name contains "qa". Mirrors hooks/block-qa-repo-git-writes.sh.
# Only while the QA plugin is installed and on (0.8.0): it's the QA team's plugin,
# not part of the developer setup — without it a "…qa…" folder blocks nothing.
ono_qa=false
if ! grep -q '"name"[[:space:]]*:[[:space:]]*"ono-plugin-qa"' .claude-plugin/plugin.json 2>/dev/null &&
   { [ ! -f "$plugins_file" ] || { grep -q '"ono-plugin-qa@' "$plugins_file" 2>/dev/null &&
     PG_PLUGINS_FILE="$plugins_file" "$gs_scripts/ono-plugin.sh" active ono-plugin-qa; }; }; then
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
