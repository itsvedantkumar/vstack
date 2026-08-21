#!/usr/bin/env bash
# optimize.sh — measure, change one thing, re-measure, keep it only if it actually helped.
#
# The point is to make improvement checkable rather than asserted. Every iteration records the
# score before, the change made, the score after, and whether it was kept — so "we improved the
# reviewer" becomes a row someone can re-run rather than a claim in a commit message.
#
# THREE RULES, each there because the obvious version of this tool lies.
#
# 1. ONE CHANGE PER ITERATION. Change two things and a gain in one can hide a loss in the other,
#    and neither can be attributed.
#
# 2. A CHANGE MUST BEAT NOISE, NOT JUST THE LAST NUMBER. These are model runs; the same config
#    scores differently twice. A change is kept only if it improves the combined score by more
#    than MIN_GAIN, which defaults to a margin wider than the run-to-run spread observed here.
#    Anything smaller is recorded as "noise" and reverted, because a config assembled from
#    coin-flips will look excellent on the set that produced it and average everywhere else.
#
# 3. THE HOLD-OUT IS NOT FOR TUNING. `tests/evals/holdout/` is scored only when this is invoked
#    with `--validate`, and never inside the accept/revert decision. A change that helps the dev
#    fixtures and does nothing on the hold-out fitted the fixtures, and that is exactly what this
#    exists to catch. Optimising against the hold-out would destroy the only independent number
#    available.
#
# Score is recall and precision combined, because either alone is trivially gamed: report
# everything for perfect recall, report nothing for perfect precision. F1 punishes both.
#
# Usage:
#   tests/evals/optimize.sh --measure                 score the current config on the dev set
#   tests/evals/optimize.sh --validate                score it on the hold-out, once
#   tests/evals/optimize.sh --try "<what changed>"    score after an edit; keep or revert it

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 1
SRC=$(pwd)
LEDGER="${LEDGER:-$SRC/tests/evals/optimization-log.tsv}"
SAMPLES="${SAMPLES:-3}"
MIN_GAIN="${MIN_GAIN:-0.05}"
STATE="$SRC/tests/evals/.opt-state"

command -v jq >/dev/null || { echo "needs jq"; exit 2; }
[ -f "$LEDGER" ] || printf 'ts\tphase\tchange\trecall\tprecision\tf1\tdelta\tkept\n' > "$LEDGER"

# Run the benchmark for the vstack arm only and return recall/precision/f1.
score_now() { # <fixtures> -> "recall precision f1"
  local set="$1" log
  log=$(mktemp)
  FIXTURES="$set" RUNLOG="$log" ./tests/evals/run-pathways.sh --samples "$SAMPLES" --arms vstack >/dev/null 2>&1
  awk -F'\t' 'NR>1{h+=$4;p+=$5;f+=$6}
    END{ if(p==0){print "0 0 0"; exit}
         r=h/p; pr=(h+f>0)?h/(h+f):0;
         f1=(r+pr>0)?2*r*pr/(r+pr):0;
         printf "%.4f %.4f %.4f\n", r, pr, f1 }' "$log"
  rm -f "$log"
}

emit() { # <phase> <change> <r> <p> <f1> <delta> <kept>
  printf '%s\t%s\t%s\t%.4f\t%.4f\t%.4f\t%s\t%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2" "$3" "$4" "$5" "$6" "$7" >> "$LEDGER"
}

case "${1:---measure}" in
  --measure)
    read -r r p f1 <<< "$(score_now dev)"
    printf '%.4f\n' "$f1" > "$STATE"
    printf 'dev set — recall %.0f%%  precision %.0f%%  f1 %.3f\n' \
      "$(echo "$r*100"|bc -l)" "$(echo "$p*100"|bc -l)" "$f1"
    emit measure baseline "$r" "$p" "$f1" "-" "-"
    ;;
  --validate)
    # The independent number. Scored once, never inside an accept decision.
    read -r r p f1 <<< "$(score_now holdout)"
    printf 'HOLD-OUT — recall %.0f%%  precision %.0f%%  f1 %.3f\n' \
      "$(echo "$r*100"|bc -l)" "$(echo "$p*100"|bc -l)" "$f1"
    echo "Fixtures this configuration was never tuned against. A dev-set gain that does not show"
    echo "up here fitted the dev fixtures."
    emit validate holdout "$r" "$p" "$f1" "-" "-"
    ;;
  --try)
    what="${2:?describe the change: --try \"what you changed\"}"
    [ -f "$STATE" ] || { echo "run --measure first to establish a baseline"; exit 2; }
    prev=$(cat "$STATE")
    read -r r p f1 <<< "$(score_now dev)"
    delta=$(echo "$f1 - $prev" | bc -l)
    if (( $(echo "$delta > $MIN_GAIN" | bc -l) )); then
      kept=yes; printf '%.4f\n' "$f1" > "$STATE"
      printf 'KEEP    f1 %.3f -> %.3f (+%.3f)  %s\n' "$prev" "$f1" "$delta" "$what"
    elif (( $(echo "$delta < -$MIN_GAIN" | bc -l) )); then
      kept=no
      printf 'REVERT  f1 %.3f -> %.3f (%.3f)  %s\n' "$prev" "$f1" "$delta" "$what"
      echo "  git checkout the change: it made things measurably worse."
    else
      kept=noise
      printf 'NOISE   f1 %.3f -> %.3f (%+.3f)  %s\n' "$prev" "$f1" "$delta" "$what"
      echo "  Inside the run-to-run spread. Revert it: a config built from differences this small"
      echo "  fits the fixtures that produced them and generalises to nothing."
    fi
    emit try "$what" "$r" "$p" "$f1" "$(printf '%+.4f' "$delta")" "$kept"
    ;;
  *) sed -n '2,30p' "$0"; exit 0 ;;
esac
