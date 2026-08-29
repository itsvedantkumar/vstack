#!/usr/bin/env bash
# Claude Code statusline: model | dir | git branch+dirty | +/- | cost | mem | style
# Perf: ONE jq invocation (was 7) and ONE git invocation (was 3). ~14 spawns -> ~3.
input=$(cat)

# Single jq pass -> tab-separated fields.
# Separator is US (\037), not tab. Tab is IFS-whitespace, so bash coalesces runs of it and a
# single empty field shifts every field after it -- an absent output_style rendered the cost as
# the style and the token count as the cost. @tsv has the same hazard for the same reason, so the
# fields are joined on a control character that cannot appear in a display name, path or number.
IFS=$'\037' read -r model cdir style cost added removed ctxused <<<"$(
  printf '%s' "$input" | jq -r '[
    (.model.display_name // "Claude"),
    (.workspace.current_dir // .cwd // ""),
    (.output_style.name // ""),
    (.cost.total_cost_usd   // ""),
    (.cost.total_lines_added   // ""),
    (.cost.total_lines_removed // ""),
    (.context_window.total_input_tokens // "")
  ] | map(tostring) | join("\u001f")' 2>/dev/null
)"
[ -z "$cdir" ] && cdir="$PWD"
dir=${cdir##*/}

# Lead and delegation: read dispatch count from counter file, written by a hook after each Agent
# or Task tool_use. Session-scoped, /tmp-resident like vstack-mandate-$sid. Scales O(1), unlike
# prior grep-based approach which cost ~128ms end-to-end and scaled with transcript size.
# Renders nothing if counter is absent (fresh session, no dispatches yet) — this is correct,
# not a zero. Correctness note (preserved from prior): any transcript-based counting must account
# for tool_result blocks that might quote '"name":"Agent"' or '"name":"Task"' — grep would
# over-count such quotations. Counter incremented by the runtime avoids this; it counts real
# dispatches by definition.
dispatch_count=""
sid=$(printf '%s' "$input" | jq -r '.session_id // ""' 2>/dev/null)
if [ -n "$sid" ]; then
  cnt_file="${TMPDIR:-/tmp}/vstack-dispatch-count-$sid"
  [ -f "$cnt_file" ] && dispatch_count=$(cat "$cnt_file" 2>/dev/null | tr -d ' ')
  case "$dispatch_count" in
    "" | "0") dispatch_count="" ;;
  esac
fi
# Single git call: branch name on line 1, dirty marker on line 2.
# `status --porcelain` (27ms, walks the whole tree) replaced by `diff --quiet` short-circuits.
branch=""; dirty=""
if gitout=$(git -C "$cdir" rev-parse --abbrev-ref HEAD 2>/dev/null); then
  branch=$gitout
  [ "$branch" = "HEAD" ] && branch=$(git -C "$cdir" rev-parse --short HEAD 2>/dev/null)
  git -C "$cdir" diff --quiet --ignore-submodules HEAD 2>/dev/null || dirty="*"
fi

R=$'\e[0m'; D=$'\e[2m'; B=$'\e[34m'; G=$'\e[32m'; Y=$'\e[33m'; M=$'\e[35m'; C=$'\e[36m'; RED=$'\e[31m'
out="${M}${model}${R} ${D}·${R} ${B}${dir}${R}"
[ -n "$branch" ] && out="${out} ${D}·${R} ${G}⎇ ${branch}${Y}${dirty}${R}"
[ -n "$added$removed" ] && out="${out} ${D}·${R} ${G}+${added:-0}${R}/${Y}-${removed:-0}${R}"
if [ -n "$cost" ]; then
  # Pure-bash thresholds — drops the 2 awk spawns.
  cc=$(printf '%.2f' "$cost" 2>/dev/null) || cc=$cost
  whole=${cc%%.*}
  col=$G
  if [ "${whole:-0}" -ge 8 ] 2>/dev/null; then col=$RED
  elif [ "${whole:-0}" -ge 2 ] 2>/dev/null; then col=$Y; fi
  out="${out} ${D}·${R} ${col}\$${cc}${R}"
fi
# Context occupancy, measured against the window compaction actually fires at -- not against
# the model's 1M, which is the number that makes 300k look like nothing. `total_input_tokens` is
# input + cache_creation + cache_read, i.e. what occupies the window; it is null before the first
# API call of a session and again after a compaction until the next one, so an absent value
# renders nothing rather than a confident "0%".
#
# CTX_COMPACT_WINDOW must equal autoCompactWindow in claude/settings.json. It is duplicated here
# rather than read per render because this runs on every turn and a second jq spawn is the cost
# this file was rewritten to avoid. doctor asserts the two agree: a statusline warning at a
# threshold the runtime does not use is exactly the green that measures nothing.
CTX_COMPACT_WINDOW=300000
if [ -n "$ctxused" ] && [ "$ctxused" -gt 0 ] 2>/dev/null; then
  col=$G
  if   [ "$ctxused" -ge "$CTX_COMPACT_WINDOW" ] 2>/dev/null; then col=$RED
  elif [ "$ctxused" -ge $(( CTX_COMPACT_WINDOW * 2 / 3 )) ] 2>/dev/null; then col=$Y; fi
  out="${out} ${D}·${R} ${col}ctx $(( ctxused / 1000 ))k${R}${D}/$(( CTX_COMPACT_WINDOW / 1000 ))k${R}"
fi
# Lead and delegation count: shows RICK and how many agents dispatched in this session.
if [ -n "$dispatch_count" ]; then
  out="${out} ${D}·${R} ${M}RICK${R} ${G}·${dispatch_count}▸${R}"
fi
# The gate indicator. This repository spent a day removing greens that measured nothing, so an
# indicator that only ever says "protected" would be the same defect wearing better clothes.
# Three states, and two of them are bad news:
#
#   shield  the repo has a .claude/verify.sh AND it is trusted, so Stop actually blocks
#   open    the repo has a gate but it is not armed -- a gate nobody trusts does not run
#   (none)  no gate here at all, and the statusline says nothing rather than implying safety
#
# This asked for the path and nothing else. The gate keys on the hash as well, so a verify.sh
# edited after `vstack trust` ran still rendered shield while the gate skipped it -- the exact
# "only ever says protected" shape the paragraph above rejects, on the indicator a reader sees
# most often. The reason given was cost: no subprocess, because this renders on every turn.
# Measured on this repository's own verify.sh, shasum -a 256 costs 9 ms against the 12 ms git
# call three lines up, so the saving bought a wrong answer for less than one spawn. Same query
# as claude/hooks/verify-gate.sh and claude/hooks/format.sh make, and .claude/verify.sh check 57
# runs all three against one store and fails if any of them lands somewhere else.
if [ -f "$cdir/.claude/verify.sh" ]; then
  _tr="$HOME/.config/agents/verify-trust"
  _tv="$(cd "$cdir/.claude" 2>/dev/null && pwd)/verify.sh"
  if command -v shasum >/dev/null 2>&1; then _th=$(shasum -a 256 "$_tv" 2>/dev/null | cut -d' ' -f1)
  else _th=$(sha256sum "$_tv" 2>/dev/null | cut -d' ' -f1); fi
  # No hasher means nothing on this machine can tell trusted from stale, and the honest render
  # is the one that claims less.
  # verify.sh's hash alone is not what the gate keys on. `vstack trust` records the repo-root
  # scripts too and claude/hooks/verify-gate.sh:44-63 re-hashes all of them, so a changed
  # install.sh makes the gate refuse while this rendered shield -- the same "only ever says
  # protected" failure the paragraph above rejects, one layer in. Re-check the gate's whole set,
  # skipping recorded files that no longer exist exactly as the gate does. Still one extra spawn
  # regardless of how many companions there are: shasum takes many operands and prints the
  # store's own format, so grep -vxF against the store lists precisely the drifted ones.
  _tok=""
  if [ -n "$_th" ] && grep -qxF "$_th  $_tv" "$_tr" 2>/dev/null; then
    _tk="$(cd "$cdir" 2>/dev/null && pwd)"
    _tp=$(grep -F "  $_tk/" "$_tr" 2>/dev/null | cut -d' ' -f3-)
    _tl=""; _ti=$IFS; IFS='
'
    set -f
    for _tf in $_tp; do [ -f "$_tf" ] && _tl="$_tl$_tf
"; done
    if [ -n "$_tl" ]; then
      if command -v shasum >/dev/null 2>&1; then _tm=$(shasum -a 256 -- $_tl 2>/dev/null | grep -vxF -f "$_tr" -)
      else _tm=$(sha256sum -- $_tl 2>/dev/null | grep -vxF -f "$_tr" -); fi
    else _tm=""; fi
    set +f; IFS=$_ti
    [ -z "$_tm" ] && _tok=1
  fi
  if [ -n "$_tok" ]; then
    out="${out} ${D}·${R} ${G}shield${R}"
  else
    out="${out} ${D}·${R} ${Y}gate open${R}"
  fi
fi
[ -n "$style" ] && out="${out} ${D}· ${C}${style}${R}"
printf '%s' "$out"
