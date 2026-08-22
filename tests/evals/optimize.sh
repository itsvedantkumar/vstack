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
#    than MIN_GAIN. That default is 0.05 and it is UNCALIBRATED: nothing in this repository
#    derives it, and it has never once executed, because --try hard-exits without .opt-state and
#    .opt-state has never existed. It was described here as "wider than the run-to-run spread
#    observed here" and no run measured that spread. Treat it as a stated default, not evidence.
#    Calibrating it means three unchanged --measure runs and taking the observed spread; with
#    SAMPLES=3 over 8 fixtures a single f1 step is roughly 1/35, about 0.029, so 0.05 is the
#    right order of magnitude and that is the most that can honestly be said for it.
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
# Uncalibrated; see note 2 in the header. Stated default, not a measured threshold.
MIN_GAIN="${MIN_GAIN:-0.05}"
STATE="$SRC/tests/evals/.opt-state"

command -v jq >/dev/null || { echo "needs jq"; exit 2; }
[ -f "$LEDGER" ] || printf 'ts\tphase\tchange\trecall\tprecision\tf1\tdelta\tkept\n' > "$LEDGER"

# Run the benchmark for the vstack arm only and return recall/precision/f1.
# The pure half, separated so it can be tested without spending a model call. Check 37 drives it.
#
# The old version collapsed three different situations into "0 0 0": a run that scored zero, a
# run that produced no rows at all, and a run whose fixtures planted no defects. Only the first
# is a result. The other two are a broken harness, and they read as f1 0.0000 -- which makes
# delta hugely negative, trips the revert branch, and tells you a good change "made things
# measurably worse". A zero that means "no data" is the same defect RESULTS.md catalogues twice.
f1_from_log() { # <path> -> "recall precision f1" | "INVALID <why>"
  awk -F'\t' 'NR>1{n++;h+=$4;p+=$5;f+=$6}
    END{ if(n==0){ print "INVALID the run produced no rows"; exit }
         if(p==0){ print "INVALID zero planted defects: the scorer never ran"; exit }
         r=h/p; pr=(h+f>0)?h/(h+f):0;
         f1=(r+pr>0)?2*r*pr/(r+pr):0;
         printf "%.4f %.4f %.4f\n", r, pr, f1 }' "$1"
}

score_now() { # <fixtures> -> "recall precision f1" | "INVALID <why>"
  local set="$1" log out
  log=$(mktemp)
  FIXTURES="$set" RUNLOG="$log" ./tests/evals/run-pathways.sh --samples "$SAMPLES" --arms vstack >/dev/null 2>&1
  out=$(f1_from_log "$log")
  rm -f "$log"
  printf '%s\n' "$out"
}

# keep|revert|noise, as one comparison in one place. The boundary is strictly greater than, so
# exactly +MIN_GAIN is noise; that is the case an edit moves by accident.
#
# The epsilon is not decoration. 0.55 - 0.50 is 0.050000000000000044 in binary floating point,
# so a bare `d > g` called the documented boundary a keep, and which side of MIN_GAIN a change
# landed on depended on the bit pattern of two decimals rather than on the measurement. A
# threshold nobody can state the behaviour of at its own boundary is not a threshold.
decide() { # <prev> <now> <min_gain> -> keep|revert|noise
  awk -v prev="$1" -v now="$2" -v g="$3" \
    'BEGIN{ e=1e-9; d=now-prev;
            if(d>g+e){print "keep"} else if(d<-g-e){print "revert"} else {print "noise"} }'
}

# Refuse to treat a broken run as a measurement. Written as a guard on an already-captured value
# rather than a wrapper that exits: `$(score_or_die ...)` would run the exit in a subshell, kill
# only that subshell, and hand the caller an empty string to read three fields out of -- which is
# the same "absence read as a value" bug one layer up.
die_if_invalid() { # <captured-output>
  case "$1" in
    INVALID*)
      printf '%s\n' "$1" >&2
      echo "  the harness did not produce a scoreable run; this is not a score of zero" >&2
      exit 2 ;;
  esac
}

emit() { # <phase> <change> <r> <p> <f1> <delta> <kept>
  printf '%s\t%s\t%s\t%.4f\t%.4f\t%.4f\t%s\t%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2" "$3" "$4" "$5" "$6" "$7" >> "$LEDGER"
}

case "${1:---measure}" in
  --measure)
    raw=$(score_now dev); die_if_invalid "$raw"
    read -r r p f1 <<< "$raw"
    printf '%.4f\n' "$f1" > "$STATE"
    printf 'dev set — recall %.0f%%  precision %.0f%%  f1 %.3f\n' \
      "$(echo "$r*100"|bc -l)" "$(echo "$p*100"|bc -l)" "$f1"
    emit measure baseline "$r" "$p" "$f1" "-" "-"
    ;;
  --validate)
    # The independent number. Scored once, never inside an accept decision.
    raw=$(score_now holdout); die_if_invalid "$raw"
    read -r r p f1 <<< "$raw"
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
    raw=$(score_now dev); die_if_invalid "$raw"
    read -r r p f1 <<< "$raw"
    delta=$(echo "$f1 - $prev" | bc -l)
    case "$(decide "$prev" "$f1" "$MIN_GAIN")" in
    keep)
      kept=yes; printf '%.4f\n' "$f1" > "$STATE"
      printf 'KEEP    f1 %.3f -> %.3f (+%.3f)  %s\n' "$prev" "$f1" "$delta" "$what"
      ;;
    revert)
      kept=no
      printf 'REVERT  f1 %.3f -> %.3f (%.3f)  %s\n' "$prev" "$f1" "$delta" "$what"
      echo "  git checkout the change: it made things measurably worse."
      ;;
    *)
      kept=noise
      printf 'NOISE   f1 %.3f -> %.3f (%+.3f)  %s\n' "$prev" "$f1" "$delta" "$what"
      echo "  Inside the run-to-run spread. Revert it: a config built from differences this small"
      echo "  fits the fixtures that produced them and generalises to nothing."
      ;;
    esac
    emit try "$what" "$r" "$p" "$f1" "$(printf '%+.4f' "$delta")" "$kept"
    ;;
  *) sed -n '2,30p' "$0"; exit 0 ;;
esac
