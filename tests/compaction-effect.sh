#!/usr/bin/env bash
# compaction-effect.sh -- does auto-compaction at this machine's configured window
# (autoCompactWindow=300000, observed firing near ~230K tokens) correlate with worse agent
# behaviour in the turns right after it, on THIS machine's own transcript history?
#
# CAUSAL LIMIT, stated here because it is the most important line in the file: this is
# correlational, not an experiment. A session long enough to hit auto-compaction is not a
# random draw from the same population as a short one -- it is already doing something bigger,
# harder, or messier. A rate difference measured here is evidence of association between
# compaction and a proxy metric, not evidence that compaction CAUSED the difference. The one
# published result in this space (Governance Decay, arXiv 2606.22528: 0% policy-violation with
# the policy in full context, 30-59% after compaction) is suggestive and is about a different
# harness under a different task; it does not transfer here by citation. Read every number below
# as "associated with", never as "caused by".
#
# PRE-REGISTRATION (written before this script was run against real data; see
# tests/compaction-effect.py's own header for the exact metric definitions):
#   Primary comparison: auto-trigger boundaries only (unplanned, mid-task), is_error rate in a
#   window of TURN_WINDOW=15 tool-calls immediately before vs immediately after the boundary.
#   Declared SIGNAL if the pooled post-window rate is >= SIGNAL_RATIO=1.5x the pooled pre-window
#   rate, computed only over boundaries with >= MIN_WINDOW_CALLS=3 resolved tool-calls on both
#   sides, and only when >= MIN_BOUNDARIES_FOR_SIGNAL=3 boundaries qualify and each pooled side
#   has >= MIN_POOLED_CALLS_FOR_SIGNAL=15 tool-calls. Below those floors the result is reported
#   as NOT EVALUATED, not as a rate -- a ratio built on four boundaries is not a finding.
#   Same test repeated for manual-trigger boundaries and for two secondary proxies (re-read rate,
#   near-duplicate user turns; DUP_RATIO=0.6, difflib.SequenceMatcher). If auto shows a signal
#   and manual does not under the identical rule, that points at the trigger point (compacting
#   mid-task, unplanned) rather than the compaction event itself -- this is the sharpest
#   available comparison at zero cost and is reported first.
#   Abandonment (session ends within ABANDON_CALLS=3 tool-calls of a session's LAST boundary) is
#   reported as a rate with no pre/post comparison possible; it cannot distinguish abandonment
#   from a session that simply finished, and the report says so.
#   These thresholds were fixed by looking only at STRUCTURAL facts available before any outcome
#   metric was computed (this machine has 8 sessions with >=1 compact_boundary, 12 boundaries
#   total, 6 auto / 6 manual, tool-calls per boundary ranging 2-658) -- never by looking at an
#   is_error, re-read or near-dup rate first and picking a threshold that flatters it.
#
# Zero model calls. Pure local JSONL parsing of ~/.claude/projects/*/*.jsonl via
# tests/compaction-effect.py (needs only python3 + stdlib: json, difflib, math -- no pip install).
#
# Usage: tests/compaction-effect.sh
#   Override PROJECTS_DIR to point at a different ~/.claude/projects for testing.
#   Override TURN_WINDOW / MIN_WINDOW_CALLS / DUP_RATIO / ABANDON_CALLS / SIGNAL_RATIO /
#   MIN_BOUNDARIES_FOR_SIGNAL / MIN_POOLED_CALLS_FOR_SIGNAL to re-run at different floors --
#   doing so invalidates comparison against a run at the defaults above (see tests/README.md,
#   "A harness change invalidates its own prior findings until the control re-runs").

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
SRC=$(pwd)
PY="$SRC/tests/compaction-effect.py"

PROJECTS_DIR="${PROJECTS_DIR:-$HOME/.claude/projects}"

if ! command -v python3 >/dev/null 2>&1; then
  echo "SKIP: python3 not on PATH; this analysis needs stdlib json/difflib/math."
  exit 0
fi

if [ ! -d "$PROJECTS_DIR" ]; then
  echo "INCONCLUSIVE: $PROJECTS_DIR does not exist -- no transcripts to analyze."
  echo "accounting: 0 declared / 0 ran / 0 skipped"
  exit 1
fi

TMP=$(mktemp -d "${TMPDIR:-/tmp}/compaction-effect.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

ALL_FILE="$TMP/all.txt"
CANDIDATES_FILE="$TMP/candidates.txt"
find "$PROJECTS_DIR" -type f -name '*.jsonl' > "$ALL_FILE" 2>/dev/null
TOTAL_SESSIONS=$(wc -l < "$ALL_FILE" | tr -d ' ')

# Cheap pre-filter in the shell: grep -l is far faster than asking python to open and stream
# every transcript in the tree just to find the ~0.3% that contain a compact_boundary at all.
#
# Deliberately NOT filtering out */subagents/*.jsonl here, unlike delegation-drift.sh's live-run
# find. A compact_boundary inside a subagent's own leaf transcript is a real compaction event
# with real pre/post tool-calls, not invalid data -- excluding it at candidate-collection time
# would hide it from the "sessions excluded from pooling" count tests/compaction-effect.py prints
# unconditionally. The independence problem (a parent session and its own subagent leaf are not
# two independent boundaries) is handled downstream in tests/compaction-effect.py, right where
# the pooling itself happens, with the full reasoning in a comment there -- not here, where only
# the candidate list is being built.
: > "$CANDIDATES_FILE"
if [ "$TOTAL_SESSIONS" -gt 0 ]; then
  while IFS= read -r f <&3; do
    [ -n "$f" ] || continue
    grep -q '"compact_boundary"' "$f" 2>/dev/null && echo "$f" >> "$CANDIDATES_FILE"
  done 3< "$ALL_FILE"
fi

TOTAL_SESSIONS="$TOTAL_SESSIONS" python3 "$PY" "$CANDIDATES_FILE"
exit $?
