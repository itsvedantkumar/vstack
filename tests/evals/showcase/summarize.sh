#!/usr/bin/env bash
# summarize.sh -- one table from every run file in runs/, grouped by model, fixture and arm.
# Reads runs/*.jsonl plus runs/INDEX.tsv (engine, model, valid/invalid per file). Rows from
# files marked invalid are dropped; a row's model is the modelUsage entry that cost the most
# (Claude Code bills background Haiku calls inside an Opus run, so the alphabetical first key
# is wrong), falling back to INDEX.tsv for rows recorded before model_cost existed.
# Prints Markdown (default), JSON (--json), or writes summary.json next to this file (--write).
# Every number the README or the hosted page shows must come out of this script; if it does
# not, it is not a result.
set -u
cd "$(dirname "$0")" || exit 1
FMT=${1:---md}
[ -f runs/INDEX.tsv ] || { echo "runs/INDEX.tsv missing" >&2; exit 1; }
for f in runs/*.jsonl; do
  /usr/bin/grep -q "^${f#runs/}	" runs/INDEX.tsv || { echo "runs/INDEX.tsv has no row for ${f#runs/}" >&2; exit 1; }
done
idx=$(awk -F'\t' 'NR>1{printf "{\"file\":\"%s\",\"engine\":\"%s\",\"model\":\"%s\",\"status\":\"%s\",\"note\":\"%s\"}\n",$1,$2,$3,$4,$5}' runs/INDEX.tsv | jq -s 'map({(.file):.})|add')
# jq -s consumes every input before the program runs, so input_filename would name the LAST
# file for every row; tag each row with its file first.
for f in runs/*.jsonl; do jq -c --arg f "${f#runs/}" '. + {file:$f}' "$f"; done \
| jq -s --argjson idx "$idx" --arg commit "$(git rev-parse --short HEAD)" '
  def agg: {
      model: .[0].model, engine: .[0].engine, fixture: .[0].fixture, arm: .[0].arm,
      n: length,
      green: (map(select(.tests_green==1)) | length),
      said_done: (map(select(.said==1)) | length),
      false_completion: (map(select(.false_completion==1)) | length),
      spawned: (map(.spawned // 0) | add),
      cost_mean: ((map(.cost_usd // 0) | add / length) * 10000 | round / 10000),
      cost_total: ((map(.cost_usd // 0) | add) * 100 | round / 100),
      wall_s: ((map(.duration_ms // 0) | add / length / 1000) | round),
      turns: ((map(.turns // 0) | add / length * 10 | round) / 10),
      files: (map(.file) | unique) };
  [ .[] | .file as $f
    | select($idx[$f].status == "valid")
    | select(.is_error != true and .is_error != 1)
    | select(.arm == "vstack" or .arm == "gstack")
    | . + { engine: $idx[$f].engine,
            model: (((.model_cost // {}) | to_entries | max_by(.value) | .key) // $idx[$f].model) } ]
  | . as $all
  | { generated: (now | todate), commit: $commit,
      rows: ($all | group_by([.model, .fixture, .arm]) | map(agg) | sort_by(.engine, .model, .fixture, .arm)),
      # head_to_head: one group per run file and arm, only for files whose INDEX note says
      # "vstack vs gstack": the paired runs where both harnesses saw the same fixture, model and
      # vstack version. Never pooled across files. The rule from Vedant (2026-09-04): the
      # comparison is vstack against gstack; rows from any other arm are excluded everywhere.
      head_to_head: ($all | map(select(($idx[.file].note | test("vstack vs gstack")) and .arm != "none"))
                     | group_by([.file, .arm]) | map(agg + {file: .[0].file, note: $idx[.[0].file].note})
                     | sort_by(.file, .fixture, .arm)),
      files: $idx }
' > /tmp/showcase-summary.json || exit 1
case "$FMT" in
  --json) cat /tmp/showcase-summary.json; exit 0 ;;
  --write) cp /tmp/showcase-summary.json summary.json; echo "wrote summary.json ($(jq '.rows|length' summary.json) groups)"; exit 0 ;;
esac
printf '| engine | model | fixture | arm | n | held-out green | said DONE | false completions | spawned | mean cost | mean wall | mean turns |\n|---|---|---|---|---|---|---|---|---|---|---|---|\n'
jq -r '.rows[] | "| \(.engine) | \(.model) | \(.fixture) | \(.arm) | \(.n) | \(.green) | \(.said_done) | \(.false_completion) | \(.spawned) | $\(.cost_mean) | \(.wall_s) s | \(.turns) |"' /tmp/showcase-summary.json
