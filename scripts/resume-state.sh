#!/usr/bin/env bash
# Platform Guardian — "where was I": in-progress work found in the Ono plugins' own documents.
#
# Usage: resume-state.sh [dir]
#   dir defaults to $CLAUDE_PROJECT_DIR, then the current directory (the repo root is used).
#
# Prints one plain-text line per piece of unfinished work, nothing when there is none:
#   - <plugin> · <what> · <stage> · next: <command or step>  [<evidence path>]
# Finished work (handed to QA, all topics approved, …) is not listed. Documents are the
# truth; tool state files only add task progress. Stages are "apparent": fingerprints and
# freshness need the plugins' own helpers, which the router can run afterwards.
# Formats: routing/routes.json "resume" + docs/resume-state.md (traced to plugin source).
#
# Environment: PG_RESUME_MAX (default 8) — maximum lines; PG_RESUME=off disables.
# Portable to macOS bash 3.2; needs only git, find, awk, sed (no jq, no node). Always exits 0.

[ "${PG_RESUME:-}" = "off" ] && exit 0
MAX="${PG_RESUME_MAX:-8}"
case "$MAX" in ''|*[!0-9]*) MAX=8 ;; esac
MAX_DOCS=400   # planning docs scanned per repo — bounds hook latency in huge docs/ trees

start="${1:-${CLAUDE_PROJECT_DIR:-$PWD}}"
start="$(cd "$start" 2>/dev/null && pwd)" || exit 0   # absolute — the upward walks rely on it
root="$(git -C "$start" rev-parse --show-toplevel 2>/dev/null)" || root=""
[ -n "$root" ] || root="$(cd "$start" && pwd)"
cd "$root" 2>/dev/null || exit 0

OUT=""; COUNT=0
emit() { # emit <plugin> <what> <stage> <next> <path>
  COUNT=$((COUNT + 1))
  OUT="$OUT- $1 · $2 · $3 · next: $4  [$5]
"
}

# ---------- document helpers ----------

# fm <file>: the frontmatter block as "key: value" lines — `---` delimited (first line), else
# the first ```yaml / ```yml fence before the first "## " heading outside an HTML comment.
fm() {
  awk '
    NR == 1 && /^---[ \t]*$/ { mode = "dash"; next }
    mode == "dash" { if (/^---[ \t]*$/) exit; print; next }
    /<!--/ { incomment = 1 }
    incomment { if (/-->/) incomment = 0; next }
    mode == "" && /^## / { exit }
    mode == "" && /^```(yaml|yml)[ \t]*$/ { mode = "fence"; next }
    mode == "fence" { if (/^```[ \t]*$/) exit; print }
  ' "$1" 2>/dev/null
}

# get <frontmatter-text> <key>: the value, without inline " #" comment, quotes, or null.
get() {
  printf '%s\n' "$1" | awk -v k="$2" -v q="'" '
    index($0, k ":") == 1 {
      v = substr($0, length(k) + 2)
      sub(/[ \t]#.*$/, "", v); gsub(/^[ \t]+|[ \t]+$/, "", v)
      if (length(v) >= 2 && (v ~ /^".*"$/ || (substr(v, 1, 1) == q && substr(v, length(v)) == q))) v = substr(v, 2, length(v) - 2)
      if (v == "null" || v == "~") v = ""
      print v; exit
    }'
}

# task_ids <markdown> [cycle]: task ids from the first column of task tables. With a cycle
# (bug work plans): cycle 1 → the "## Tasks" section, cycle n → "### Cycle n".
task_ids() {
  awk -v cyc="${2:-}" '
    function cell1(line,   a) { split(line, a, "|"); gsub(/^[ \t]+|[ \t]+$/, "", a[2]); return a[2] }
    cyc != "" {
      if (cyc == 1) { if (/^## /) { on = ($0 ~ /^## Tasks[ \t]*$/) } }
      else if (/^##+ /) { on = ($0 ~ ("^### Cycle " cyc "[ \t]*$")) }
      if (!on) next
    }
    /^\|/ { id = cell1($0); if (id ~ /^([A-Za-z]+[0-9]+|C[1-9][0-9]*-T[1-9][0-9]*)$/) print id }
  ' "$1" 2>/dev/null
}

# task_states <task-state.json>: "<id> <state>" per recorded task (2-space pretty JSON).
task_states() {
  [ -f "$1" ] || return 0
  awk '
    /^  "tasks": \{/ { intasks = 1; next }
    intasks && /^  [}"]/ { intasks = 0 }
    intasks && /^    "[^"]+": \{/ { id = $0; sub(/^    "/, "", id); sub(/".*/, "", id); next }
    intasks && id != "" && /^      "state": "/ { s = $0; sub(/^      "state": "/, "", s); sub(/".*/, "", s); print id, s }
  ' "$1" 2>/dev/null
}

# progress <ids> <states>: "<done> <total> <first-not-complete>" (first is empty when all done).
progress() {
  local id done=0 total=0 first="" st
  for id in $1; do
    total=$((total + 1))
    st="$(printf '%s\n' "$2" | awk -v i="$id" '$1 == i { print $2; exit }')"
    if [ "$st" = "complete" ]; then done=$((done + 1)); elif [ -z "$first" ]; then first="$id"; fi
  done
  echo "$done $total $first"
}

# ---------- ono-mobile-dev-plugin: features ----------
# Planning docs are found the way the plugin finds them: *.md under docs/ (depth ≤ 6, not in
# bugs/ or tasks/), typed by frontmatter keys (no doc_type key exists).

dev_features() {
  [ -d docs ] || return 0
  # One awk pass over every candidate doc (one process, not several per file): the frontmatter
  # rules of fm() + get(), then one record per planning doc: feature<TAB>kind<TAB>status<TAB>len<TAB>path
  local recs; recs="$(find docs -maxdepth 6 \( -name node_modules -o -name .git -o -name bugs -o -name tasks \) -prune \
      -o -type f -name '*.md' -print 2>/dev/null | head -n "$MAX_DOCS" | tr '\n' '\0' \
    | xargs -0 awk -v q="'" '
      function val(s) {
        sub(/^[^:]*:/, "", s); sub(/[ \t]#.*$/, "", s); gsub(/^[ \t]+|[ \t]+$/, "", s)
        if (length(s) >= 2 && (s ~ /^".*"$/ || (substr(s, 1, 1) == q && substr(s, length(s)) == q))) s = substr(s, 2, length(s) - 2)
        if (s == "null" || s == "~") s = ""
        return s
      }
      function finish(   kind) {
        if (k["feature"] == "") return   # bug plans (work_type) live in the pruned bugs/ and carry no feature key
        if ("dev_plan_link" in k) kind = "tb"
        else if (("detail_level" in k) || ("dd_generation" in k)) kind = "dd"
        else if (k["generated_by"] == "create-dev-qa-notes") kind = "handoff"
        else if ("dd_link" in k) {
          if (("repo_knowledge_status" in k) || ("surface" in k) || ("capability" in k) || ("design_reference_fingerprint" in k)) kind = "fa"
          else kind = (FILENAME ~ /dev-plan/) ? "dp" : "fa"
        } else return
        printf "%s\t%s\t%s\t%d\t%s\n", k["feature"], kind, k["status"], length(FILENAME), FILENAME
      }
      FNR == 1 { split("", k); mode = ""; incomment = 0
                 if (/^---[ \t]*$/) { mode = "dash"; next } }
      mode == "dash" || mode == "fence" {
        if ((mode == "dash" && /^---[ \t]*$/) || (mode == "fence" && /^```[ \t]*$/)) { finish(); nextfile }
        if (match($0, /^[A-Za-z_][A-Za-z0-9_]*:/)) { k[substr($0, 1, RLENGTH - 1)] = val($0) }
        next
      }
      /<!--/ { incomment = 1 }
      incomment { if (/-->/) incomment = 0; next }
      /^## / { nextfile }
      /^```(yaml|yml)[ \t]*$/ { mode = "fence" }
    ' 2>/dev/null)"
  [ -n "$recs" ] || return 0
  recs="$recs
"

  local feats; feats="$(printf '%s' "$recs" | cut -f1 | sort -u)"
  local doc ids states p done total first
  for feat in $feats; do
    # pick <kind>: status<TAB>path of that doc kind for this feature (shortest path wins over -v1 copies)
    pick() { printf '%s' "$recs" | awk -F'\t' -v f="$feat" -v k="$1" '$1 == f && $2 == k' \
               | sort -t'	' -k4,4n | head -1 | cut -f3,5; }
    doc="$(pick handoff)"
    if [ -n "$doc" ]; then
      [ "${doc%%	*}" = "ready-for-qa" ] && continue   # handed to QA — done on the dev side
      emit ono-mobile-dev-plugin "feature $feat" "QA notes drafted, waiting for your sign-off" \
        "your step — check the notes, set status: ready-for-qa" "${doc#*	}"; continue
    fi
    local tb dp dd fa; tb="$(pick tb)"; dp="$(pick dp)"; dd="$(pick dd)"; fa="$(pick fa)"
    if [ -n "$tb" ]; then
      if [ "${tb%%	*}" != "approved" ] || { [ -n "$dp" ] && [ "${dp%%	*}" != "approved" ]; }; then
        emit ono-mobile-dev-plugin "feature $feat" "dev plan + task breakdown waiting for approval" \
          "your step — approve both (status: approved), then /implement-task $feat T1" "${tb#*	}"; continue
      fi
      ids="$(task_ids "${tb#*	}")"
      states="$(task_states "docs/tasks/$feat-task-state.json")"
      set -- $(progress "$ids" "$states"); done=$1 total=$2 first=${3:-}
      if [ -n "$first" ]; then
        emit ono-mobile-dev-plugin "feature $feat" "implementing ($done/$total tasks complete)" \
          "/implement-task $feat $first" "${tb#*	}"
      else
        emit ono-mobile-dev-plugin "feature $feat" "all $total tasks complete, not handed to QA yet" \
          "/review-code (if not done yet), then /create-dev-qa-notes $feat" "${tb#*	}"
      fi
    elif [ -n "$dd" ]; then
      if [ "${dd%%	*}" != "approved" ]; then
        emit ono-mobile-dev-plugin "feature $feat" "design doc waiting for approval" \
          "your step — approve the DD (status: approved), then /dev-feature-start $feat" "${dd#*	}"
      else
        emit ono-mobile-dev-plugin "feature $feat" "design approved, no task breakdown yet" \
          "/dev-feature-start $feat" "${dd#*	}"
      fi
    elif [ -n "$fa" ]; then
      if [ "${fa%%	*}" != "approved" ]; then
        emit ono-mobile-dev-plugin "feature $feat" "feature analysis waiting for approval" \
          "your step — approve the analysis (status: approved), then /dev-design-start $feat" "${fa#*	}"
      else
        emit ono-mobile-dev-plugin "feature $feat" "analysis approved, no design doc yet" \
          "/dev-design-start $feat" "${fa#*	}"
      fi
    fi
  done
}

# ---------- ono-mobile-dev-plugin: bugs ----------

dev_bugs() {
  [ -d docs/bugs ] || return 0
  local d key plan m st cyc acyc ids states done total first ver vst h hm
  for d in docs/bugs/*/; do
    [ -d "$d" ] || continue
    key="$(basename "$d")"; plan="${d}bug-work-plan.md"
    if [ ! -f "$plan" ]; then
      emit ono-mobile-dev-plugin "bug $key" "analysis started, no work plan yet" "/analyze-bug $key" "$d"; continue
    fi
    m="$(fm "$plan")"; st="$(get "$m" status)"; cyc="$(get "$m" fix_cycle)"; acyc="$(get "$m" approved_cycle)"
    case "$cyc" in ''|*[!0-9]*) cyc=1 ;; esac
    if [ "$st" != "approved" ] || [ "$acyc" != "$cyc" ]; then
      emit ono-mobile-dev-plugin "bug $key" "work plan (cycle $cyc) waiting for approval" \
        "/analyze-bug $key — it resumes at the approval step, which is yours" "$plan"; continue
    fi
    ids="$(task_ids "$plan" "$cyc")"
    states="$(task_states "docs/tasks/bugs/$key.task-state.json")"
    set -- $(progress "$ids" "$states"); done=$1 total=$2 first=${3:-}
    if [ -n "$first" ]; then
      emit ono-mobile-dev-plugin "bug $key" "fixing, cycle $cyc ($done/$total tasks complete)" \
        "/implement-task bug:$key $first" "$plan"; continue
    fi
    ver="${d}verification-c$cyc.md"
    vst="$( [ -f "$ver" ] && get "$(fm "$ver")" status )"
    if [ "$vst" != "passed" ]; then
      emit ono-mobile-dev-plugin "bug $key" "fix done (cycle $cyc), not verified yet" \
        "your step — /verify-fix-cycle bug:$key (you record pass / fail)" "$plan"; continue
    fi
    if [ ! -f "${d}review-c$cyc.md" ]; then
      emit ono-mobile-dev-plugin "bug $key" "fix verified (cycle $cyc), not reviewed yet" \
        "/review-code --bug $key" "$plan"; continue
    fi
    h="docs/qa/bug-$key-qa-handoff.md"; hm="$( [ -f "$h" ] && fm "$h" )"
    if [ "$(get "$hm" status)" = "ready-for-qa" ] && [ "$(get "$hm" fix_cycle)" = "$cyc" ]; then
      continue   # handed to QA — waiting for QA
    fi
    if [ -n "$hm" ] && [ "$(get "$hm" fix_cycle)" = "$cyc" ]; then
      emit ono-mobile-dev-plugin "bug $key" "QA notes drafted (cycle $cyc), waiting for sign-off" \
        "/create-dev-qa-notes bug:$key — it resumes at the approval, which is yours" "$h"
    else
      emit ono-mobile-dev-plugin "bug $key" "fix reviewed (cycle $cyc), not handed to QA" \
        "/create-dev-qa-notes bug:$key" "$plan"
    fi
  done
}

# ---------- ono-project-inspector ----------
# AUDIT.md is the truth (Status: Pending Breakdown | Draft | Approved); .ono/state.json is a hint.

inspector() {
  [ -f AUDIT.md ] || return 0
  head -5 AUDIT.md | grep -q '^# AUDIT\.md' || [ -f .ono/state.json ] || return 0
  local missing="" p
  for p in overview components patterns integrations capabilities; do
    [ -f "docs/project/$p.md" ] || missing="$missing $p"
  done
  if [ ! -f CLAUDE.md ] || [ -n "$missing" ]; then
    emit ono-project-inspector "repo inspection" "project analysis done, project docs not finished" \
      "your step — /inspect-approve to approve stage 1 and continue (or /inspect → Continue)" "AUDIT.md"
    return 0
  fi
  local counts; counts="$(awk -F'|' '
    tolower($0) ~ /^\|[ \t]*#[ \t]*\|[ \t]*status[ \t]*\|[ \t]*topic[ \t]*\|/ { t = 1; next }
    t && !/^\|/ { t = 0 }
    t && /^\|[ \t]*-+[ \t]*\|/ { next }
    t && NF >= 7 {
      s = $3; gsub(/^[ \t]+|[ \t]+$/, "", s); n++
      if (s == "Draft") { d++; if (dt == "") { dt = $4; gsub(/^[ \t]+|[ \t]+$/, "", dt); df = $6; gsub(/^[ \t]+|[ \t]+$/, "", df) } }
      else if (s == "Approved") a++
      else if (s == "Pending Breakdown") pb++
    }
    END { printf "%d\t%d\t%d\t%d\t%s\t%s", n, a, d, pb, dt, df }' AUDIT.md)"
  local n a d pb dt df
  IFS='	' read -r n a d pb dt df <<EOF
$counts
EOF
  if [ "$n" -eq 0 ]; then
    emit ono-project-inspector "repo inspection" "AUDIT.md has no readable topics" "/inspect-status" "AUDIT.md"
  elif [ "$d" -gt 0 ]; then
    emit ono-project-inspector "audit topic $dt" "drafted, waiting for your review ($a/$n topics approved)" \
      "your step — review ${df:-the draft}, then /inspect-approve" "AUDIT.md"
  elif [ "$pb" -gt 0 ]; then
    emit ono-project-inspector "repo inspection" "audit topics in progress ($a/$n approved)" \
      "/inspect-topic (next pending topic)" "AUDIT.md"
  fi
}

# ---------- spec-team-toolkit ----------
# Only documents saved into the repo (Guardian convention docs/specs/<feature-slug>/) — the
# toolkit itself writes outside the repo (MGA-68).

specs() {
  [ -d docs/specs ] || return 0
  local f s open total
  for f in docs/specs/*/spac_*.md docs/specs/spac_*.md; do
    [ -f "$f" ] || continue
    s="$(grep -m1 '^\*\*Status:\*\*' "$f" 2>/dev/null)"
    case "$s" in
      *READY*) [ -f "$(dirname "$f")/dd_$(basename "$f" | sed 's/^spac_//')" ] || \
                 emit spec-team-toolkit "SPAC $(basename "$f" .md | sed 's/^spac_//')" "READY, DD starter not generated" \
                   "spec-team-toolkit:lld-mobile-spec — generate the DD starter" "$f" ;;
      *DRAFT*) emit spec-team-toolkit "SPAC $(basename "$f" .md | sed 's/^spac_//')" "draft — reviewers approve, then mark it ready" \
                 "spec-team-toolkit:lld-mobile-spec (continue the draft)" "$f" ;;
    esac
  done
  for f in docs/specs/*/hld-draft.md docs/specs/hld-draft.md; do
    [ -f "$f" ] || continue
    set -- $(awk '
      /\[סטטוס: [^]]+\]/ {
        t++; s = $0; sub(/.*\[סטטוס: /, "", s); sub(/\].*/, "", s)
        if (s != "הושלם" && index(s, "לא רלוונטי") != 1) o++
      }
      END { print o + 0, t + 0 }' "$f")
    open=$1 total=$2
    [ "$total" -gt 0 ] || continue
    if [ "$open" -gt 0 ]; then
      emit spec-team-toolkit "HLD $(basename "$(dirname "$f")")" "draft — $open of $total sections still open" \
        "spec-team-toolkit:hld-builder (continue the draft)" "$f"
    fi
  done
  for f in docs/specs/*/*.md; do
    [ -f "$f" ] || continue
    head -3 "$f" | grep -q '^# LLD:' || continue
    grep -m1 -q '^\*\*Status:\*\* DRAFT' "$f" && \
      emit spec-team-toolkit "LLD $(basename "$f" .md)" "draft — open questions to resolve" \
        "spec-team-toolkit:lld-backend-spec (continue the draft)" "$f"
  done
}

# ---------- ono-plugin-qa (mobile / TV QA repo) ----------
# The QA repo: .claude/qa-workspace.json qaRepoPath (next to the repo or in the session folder),
# else this repo when its folder name contains "qa". Per feature: <qa>/<slug>/test-plan.md.
# Smoke / bug / regression detail is derived by the plugin's node ledger — past the functional
# run we hand over to /qa-readiness, which lists the exact blockers.

qa_repo() {
  local w p
  for w in "$start/.claude/qa-workspace.json" "$(dirname "$root")/.claude/qa-workspace.json"; do
    [ -f "$w" ] || continue
    p="$(sed -n 's/.*"qaRepoPath"[ \t]*:[ \t]*"\([^"]*\)".*/\1/p' "$w" | head -1)"
    [ -n "$p" ] || continue
    case "$p" in /*) ;; *) p="$(dirname "$w")/../$p" ;; esac
    [ -d "$p" ] && { (cd "$p" && pwd); return; }
  done
  case "$(basename "$root" | tr '[:upper:]' '[:lower:]')" in
    *qa*) [ -d "$root/.ono" ] || [ -f "$root/matrix-qa.config.json" ] || echo "$root" ;;
  esac
}

ono_qa() {
  local qa; qa="$(qa_repo)"; [ -n "$qa" ] || return 0
  local plan slug st rd verdict so
  for plan in "$qa"/*/test-plan.md; do
    [ -f "$plan" ] || continue
    slug="$(basename "$(dirname "$plan")")"
    st="$(get "$(fm_fence_anywhere "$plan")" status)"
    if [ "$st" != "approved" ]; then
      emit ono-plugin-qa "test plan $slug" "draft, waiting for QA approval" \
        "your step — /approve-qa-test-plan $slug" "$plan"; continue
    fi
    rd="$qa/readiness/feature/$slug.md"
    if [ -f "$rd" ]; then
      verdict="$(get "$(fm "$rd")" verdict)"; so="$(get "$(fm "$rd")" signoff_status)"
      [ "$so" = "valid" ] && continue   # signed off — done
      case "$verdict" in READY|READY_WITH_EXCEPTIONS)
        emit ono-plugin-qa "feature $slug" "readiness $verdict, not signed off" \
          "your step — /qa-signoff $slug (re-run /qa-readiness first if testing continued)" "$rd"; continue ;;
      esac
    fi
    if [ ! -f "$qa/$slug/coverage-report.md" ]; then
      emit ono-plugin-qa "feature $slug" "test plan approved, coverage not checked" \
        "/check-qa-coverage $slug (needs the dev QA handoff)" "$plan"
    elif ! grep -qil "\"feature:$slug\"" "$qa"/qa-ledger/builds/*.json 2>/dev/null; then
      emit ono-plugin-qa "feature $slug" "coverage checked, no build registered" \
        "/register-build $slug <build-id>" "$plan"
    elif ! grep -qs '"field":"surfaces"' "$qa/qa-ledger/scopes/feature/$slug.jsonl"; then
      emit ono-plugin-qa "feature $slug" "build registered, QA scope not set" \
        "your step — /set-qa-scope $slug" "$plan"
    elif ! grep -ls "\"scope\":\"feature:$slug\"" "$qa"/qa-ledger/runs/functional-*.jsonl 2>/dev/null \
           | xargs grep -ls '"kind":"run.closed"' 2>/dev/null | grep -q .; then
      emit ono-plugin-qa "feature $slug" "scope set, functional run not finished" \
        "/record-execution $slug (smoke first if the build has none)" "$plan"
    else
      emit ono-plugin-qa "feature $slug" "testing in progress${verdict:+, last readiness $verdict}" \
        "/qa-readiness $slug — it lists what still blocks sign-off" "$plan"
    fi
  done
}

# The ono-plugin-qa test-plan header: the first ```yaml block anywhere in the file.
fm_fence_anywhere() {
  awk '/^```ya?ml[ \t]*$/ { on = 1; next } on { if (/^```/) exit; print }' "$1" 2>/dev/null
}

# ---------- matrix-qa-plugin (web QA repo) ----------
# Exact port of mqa.mjs fingerprints (verified byte-identical against node on examples/login).

sha() { if command -v shasum >/dev/null 2>&1; then shasum -a 256; else sha256sum; fi | cut -d' ' -f1; }
mqa_norm() {
  local bom; bom="$(printf '\357\273\277')"
  LC_ALL=C sed -e "1s/^$bom//" -e "s/$(printf '\r')\$//" | LC_ALL=C tr '\r' '\n' \
    | LC_ALL=C sed -e "s/[ $(printf '\t')]*\$//" \
    | LC_ALL=C awk '{ l[NR] = $0 } END { s = 1; while (s <= NR && l[s] == "") s++; e = NR; while (e >= s && l[e] == "") e--
        for (i = s; i <= e; i++) { x = l[i]; if (i == s) sub(/^[ \t\f\v]+/, "", x); printf "%s%s", x, (i < e ? "\n" : "") } }'
}
mqa_fp_file() { echo "sha256:$(mqa_norm <"$1" | sha)"; }
mqa_content_fp() {
  local bom; bom="$(printf '\357\273\277')"
  echo "sha256:$(LC_ALL=C sed -e "1s/^$bom//" -e "s/$(printf '\r')\$//" "$1" | LC_ALL=C tr '\r' '\n' | LC_ALL=C awk '
    NR == 1 { if ($0 == "---") { f = 1; next } }
    f == 1 { if ($0 ~ /^---/) f = 0; next }
    { t = $0; gsub(/^[ \t]+|[ \t]+$/, "", t)
      if (t ~ /^<!--[ \t]*mqa:section[ \t]+[a-z-]+[ \t]*-->$/) {
        n = t; sub(/^<!--[ \t]*mqa:section[ \t]+/, "", n); sub(/[ \t]*-->$/, "", n); skip = (n == "change-log" || n == "approval") }
      if (!skip) print }' | mqa_norm | sha)"
}

mqa_path() { # mqa_path <config> <key> <default>
  local v; v="$(sed -n "s/.*\"$2\"[ \t]*:[ \t]*\"\([^\"]*\)\".*/\1/p" "$1" | head -1)"
  echo "${v:-$3}"
}

matrix_qa() {
  local d="$start" cfg="" up=0 stop; stop="$(dirname "$root")"
  while [ "$up" -lt 32 ]; do   # bounded: from the session folder up to the repo's parent
    [ -f "$d/matrix-qa.config.json" ] && { cfg="$d/matrix-qa.config.json"; break; }
    { [ "$d" = "/" ] || [ "$d" = "$stop" ]; } && break
    d="$(dirname "$d")"; up=$((up + 1))
  done
  [ -n "$cfg" ] || return 0
  local q; q="$(dirname "$cfg")"
  local lld_dir tc_dir test_dir; lld_dir="$(mqa_path "$cfg" lldDir qa/lld)"
  tc_dir="$(mqa_path "$cfg" testCasesDir qa/test-cases)"; test_dir="$(mqa_path "$cfg" testDir tests/e2e)"
  local lld f plan m st lp lfp fid
  for lld in "$q/$lld_dir"/*.md; do
    [ -f "$lld" ] || continue
    f="$(basename "$lld" .md)"
    [ -f "$q/$tc_dir/$f.md" ] || emit matrix-qa-plugin "feature $f" "LLD ready, no test plan yet" \
      "/qa-plan $lld_dir/$f.md" "$lld_dir/$f.md"
  done
  for plan in "$q/$tc_dir"/*.md; do
    [ -f "$plan" ] || continue
    f="$(basename "$plan" .md)"; m="$(fm "$plan")"
    st="$(get "$m" status)"; lfp="$(get "$m" lld_fingerprint)"; lp="$(get "$m" lld_path)"
    lld="$q/${lp:-$lld_dir/$f.md}"
    if [ -f "$lld" ] && [ -n "$lfp" ] && [ "$(mqa_fp_file "$lld")" != "$lfp" ]; then
      emit matrix-qa-plugin "feature $f" "the LLD changed since the plan was written ($st)" "/qa-sync $f" "$tc_dir/$f.md"; continue
    fi
    case "$st" in
      DRAFT|CHANGES_REQUIRED)
        emit matrix-qa-plugin "feature $f" "test plan $st" "/qa-review $f" "$tc_dir/$f.md"; continue ;;
      REVIEWED)
        if [ "$(get "$m" reviewed_fingerprint)" != "$(mqa_content_fp "$plan")" ]; then
          emit matrix-qa-plugin "feature $f" "plan changed after review" "/qa-review $f" "$tc_dir/$f.md"
        else
          emit matrix-qa-plugin "feature $f" "test plan reviewed, waiting for QA approval" \
            "your step — /qa-approve $f" "$tc_dir/$f.md"
        fi
        continue ;;
      APPROVED)
        if [ "$(get "$m" approved_fingerprint)" != "$(mqa_content_fp "$plan")" ]; then
          emit matrix-qa-plugin "feature $f" "plan changed after approval" \
            "/qa-review $f, then your /qa-approve $f" "$tc_dir/$f.md"; continue
        fi
        [ -f "$lld" ] || { emit matrix-qa-plugin "feature $f" "approved, but its LLD is missing" \
          "restore ${lp:-$lld_dir/$f.md} or re-plan" "$tc_dir/$f.md"; continue; }
        fid="$(get "$m" feature_id)"
        if [ -n "$fid" ] && ! grep -rEqs --include='*.spec.*' --include='*.test.*' \
             "test(\.(only|skip|fixme|fail|slow))?[[:space:]]*\([[:space:]]*['\"\`]$fid-TC-[0-9]{3,}" "$q/$test_dir"; then
          emit matrix-qa-plugin "feature $f" "test plan approved, not automated yet" "/qa-automate $f" "$tc_dir/$f.md"
        fi ;;
    esac
  done
}

dev_features
dev_bugs
inspector
specs
ono_qa
matrix_qa

[ "$COUNT" -gt 0 ] || exit 0
printf '%s' "$OUT" | head -n "$MAX"
[ "$COUNT" -gt "$MAX" ] && echo "- … and $((COUNT - MAX)) more (raise PG_RESUME_MAX to list them)"
exit 0
