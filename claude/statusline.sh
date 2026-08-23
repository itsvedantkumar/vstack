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
# The gate indicator. This repository spent a day removing greens that measured nothing, so an
# indicator that only ever says "protected" would be the same defect wearing better clothes.
# Three states, and two of them are bad news:
#
#   shield  the repo has a .claude/verify.sh AND it is trusted, so Stop actually blocks
#   open    the repo has a gate but it is not armed -- a gate nobody trusts does not run
#   (none)  no gate here at all, and the statusline says nothing rather than implying safety
#
# Cheap on purpose: two stat calls, no subprocess, because this renders on every turn.
if [ -f "$cdir/.claude/verify.sh" ]; then
  _tr="$HOME/.config/agents/verify-trust"
  if [ -f "$_tr" ] && grep -qF "$cdir/.claude/verify.sh" "$_tr" 2>/dev/null; then
    out="${out} ${D}·${R} ${G}shield${R}"
  else
    out="${out} ${D}·${R} ${Y}gate open${R}"
  fi
fi
[ -d "$HOME/.claude-mem" ] && out="${out} ${D}·${R} 🧠"
[ -n "$style" ] && out="${out} ${D}· ${C}${style}${R}"
printf '%s' "$out"
