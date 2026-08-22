# shellcheck shell=bash
# runlog.sh — open an eval run log without destroying the one already there.
#
# Sourced by the eval harnesses; not executed directly.
#
# Every harness here used to open its log with `printf '<header>\n' > "$RUNLOG"`, which truncates
# unconditionally. That is fine for the default, where RUNLOG lands in a fresh mktemp directory,
# and destructive the moment a caller passes RUNLOG= to accumulate across arms -- which is
# necessary, because one model-calling arm does not fit in a single fifteen-minute invocation.
# Each arm silently overwrote the arm before it and the summary awk reported the survivor as the
# whole experiment.
#
# This is not hypothetical and it is not only a risk. .audit/run/falsedone-*.tsv retains nine
# rows, all arm=vstack; the twelve-run `none` baseline quoted in docs/research/do-harnesses-help.md
# was overwritten and has no surviving raw rows. The loss surfaced because somebody happened to
# read the raw file for an unrelated reason.
#
# The truncating line was copied into three harnesses before anyone noticed it was one line. A
# shared opener is worth more than three patched call sites mainly because it gives the assertion
# somewhere to live: check 36 exercises this function and requires every RUNLOG= assignment under
# tests/evals/ to name this file, so a fourth harness cannot quietly reintroduce it.
#
# Empty counts as new. optimize.sh hands us `log=$(mktemp)`, which creates a zero-length file, so
# a refusal keyed on `[ -f ]` would break the optimiser on its first call. `[ -s ]` is the test.
open_runlog() { # <path> <header-line>
  local f="$1" hdr="$2" have
  if [ -s "$f" ]; then
    have=$(head -1 "$f")
    if [ "$have" = "$hdr" ]; then
      return 0                      # same experiment, append to it
    fi
    printf 'runlog %s already holds a different schema:\n  have: %s\n  want: %s\nmove it aside or unset RUNLOG\n' \
      "$f" "$have" "$hdr" >&2
    return 2
  fi
  printf '%s\n' "$hdr" > "$f"
}
