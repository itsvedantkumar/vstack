#!/usr/bin/env bash
# Claude Code statusline: model | dir | git branch+dirty | +/- | cost | mem | style
# Perf: ONE jq invocation (was 7) and ONE git invocation (was 3). ~14 spawns -> ~3.
input=$(cat)

# Single jq pass -> tab-separated fields.
IFS=$'\t' read -r model cdir style cost added removed <<<"$(
  printf '%s' "$input" | jq -r '[
    (.model.display_name // "Claude"),
    (.workspace.current_dir // .cwd // ""),
    (.output_style.name // ""),
    (.cost.total_cost_usd   // ""),
    (.cost.total_lines_added   // ""),
    (.cost.total_lines_removed // "")
  ] | @tsv' 2>/dev/null
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
[ -d "$HOME/.claude-mem" ] && out="${out} ${D}·${R} 🧠"
[ -n "$style" ] && out="${out} ${D}· ${C}${style}${R}"
printf '%s' "$out"
