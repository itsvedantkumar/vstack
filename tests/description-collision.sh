#!/usr/bin/env bash
# tests/description-collision.sh
#
# Scores the shipped skill descriptions for shared trigger n-grams and names the pairs that
# overlap. No model calls, no network, no writes outside a self-test temp dir.
#
# WHAT THIS IS NOT
#
# This is not evidence that overlapping triggers suppress dispatch. That claim was published
# here as "measured over 80 samples to suppress both skills, not one" and was formally withdrawn
# in 1.47.0: no 80-sample runlog exists in this repository's history or on the machine that
# produced it (CHANGELOG.md, docs/research/fake-greens-2026-08.md). The replacement arm was
# pre-registered before the first sample and run on a committed instrument
# (tests/evals/collision/PREREGISTRATION.md, RESULTS.md, n=25, 2026-08-27); it found the
# hypothesis NOT supported -- the collision fixture fired more than either clean control -- and
# instead confirmed that the harness supplies no situation and denies the tools several skills
# exist to use.
#
# So this script encodes DESIGN DISCIPLINE, not a measured law. The discipline is the one
# aebeebb applied by hand to six pairs: put the discriminator in the first clause, because that
# is the part a matcher weighs hardest, and do not let two skills open on the same words. It is
# cheap, it is deterministic, and it is worth keeping green for the same reason a style rule is
# -- not because a violation is proven to break dispatch.
#
# SCORING
#
#   Each description splits at its first ':', '.' or em dash into HEAD (the discriminator
#   clause) and TAIL. Shared 2- and 3-grams are scored per pair, weighted by where they land:
#   3 for HEAD/HEAD, 2 for one HEAD, 1 for TAIL/TAIL.
#
# THE ONLY FAILING CONDITION
#
#   A 3-gram appearing in BOTH skills' HEAD. That is exactly the defect aebeebb fixed, where
#   grill-me and interrogate both opened on "tear this apart". Everything else prints and
#   passes, and the threshold is echoed on every run so a green cannot be read as "no overlap".
#
# Usage:
#   tests/description-collision.sh              # score claude/skills/*/SKILL.md
#   tests/description-collision.sh --self-test  # prove the check can fail, then that it passes
#   tests/description-collision.sh DIR          # score an arbitrary skills dir
set -uo pipefail

# One line, deliberately. BSD awk rejects a newline inside a -v assignment ("newline in
# string") and then exits non-zero having scored nothing -- which the first run of this
# script's own self-test caught, printing a clean rc=0 on the live corpus while awk had
# failed on every invocation. A wrapped stoplist is a green that measures nothing.
STOP=" use when the a an and or of to in on for it is are this that with before after one its you your any not no into from at by as be been has have had they them their we our i me my do does did so than then there here what which who whom whose will would can could should may might must if else while each per via over under again more most other some such only own same too very just now new old first second third next last thing things something anything nothing "

# ---------------------------------------------------------------------------
# extract_descriptions DIR
# Prints "skillname<TAB>description" per skill. Uses the same closed-frontmatter-block rule as
# .claude/verify.sh check 3 rather than a bare grep: a line that merely looks like frontmatter
# further down a body must not be scored as a description.
# ---------------------------------------------------------------------------
extract_descriptions() {
  local dir="$1" f name
  for f in "$dir"/*/SKILL.md; do
    [ -f "$f" ] || continue
    name="$(basename "$(dirname "$f")")"
    awk -v skill="$name" '
      NR==1 { if ($0 != "---") exit; infm=1; next }
      infm && $0 == "---" { exit }
      infm && /^description:[[:space:]]/ {
        line=$0
        sub(/^description:[[:space:]]*/, "", line)
        gsub(/^"|"$/, "", line)
        printf "%s\t%s\n", skill, line
        exit
      }
    ' "$f"
  done
}

# ---------------------------------------------------------------------------
# score SKILLS_DIR
# Emits the pair table and the corpus total on stdout. Returns 1 if any HEAD/HEAD 3-gram exists.
# All grouping lives in awk: bash 3.2 has no associative arrays, which is also why the rest of
# this suite avoids them.
# ---------------------------------------------------------------------------
score() {
  local dir="$1" descs n_desc out rc
  descs="$(extract_descriptions "$dir")"
  n_desc="$(printf '%s' "$descs" | grep -c . || true)"
  # An empty or unreadable corpus must not read as "no collisions". Same failure shape the
  # gate-falsifiability work in this repo exists to catch: a check that passes without running.
  if [ "${n_desc:-0}" -lt 2 ]; then
    echo "REFUSING: extracted $n_desc description(s) from $dir -- nothing to compare." >&2
    return 2
  fi
  # LC_ALL=C is load-bearing. Several descriptions carry an em dash, and BSD awk under a UTF-8
  # locale aborts on it with "illegal byte sequence" -- caught by the REFUSING guard below on the
  # first live run, which is the only reason it was not published as a clean corpus. Under C the
  # em dash is three bytes that [^a-z0-9]+ strips like any other punctuation, and the byte
  # comparison in the HEAD/TAIL split below is written against those bytes deliberately.
  out="$(printf '%s\n' "$descs" | LC_ALL=C awk -F'\t' -v stop="$STOP" '
    function norm(s,   t) {
      t = tolower(s)
      gsub(/[^a-z0-9]+/, " ", t)
      return t
    }
    function emit(skill, text, zone,   n, w, i, j, tok, out) {
      n = split(norm(text), w, " ")
      j = 0
      for (i = 1; i <= n; i++) {
        tok = w[i]
        if (length(tok) < 3) continue
        if (index(stop, " " tok " ") > 0) continue
        j++; keep[j] = tok
      }
      for (i = 1; i <= j - 1; i++) {
        g = keep[i] " " keep[i+1]
        seen[g, skill] = zone; grams[g] = 1
      }
      for (i = 1; i <= j - 2; i++) {
        g = keep[i] " " keep[i+1] " " keep[i+2]
        seen[g, skill] = zone; grams[g] = 1
        len[g] = 3
      }
    }
    {
      skill = $1; desc = $2
      skills[++ns] = skill
      # HEAD is everything up to the first ":", "." or em dash; TAIL is the rest.
      cut = 0
      for (i = 1; i <= length(desc); i++) {
        ch = substr(desc, i, 1)
        two = substr(desc, i, 3)
        if (ch == ":" || ch == "." || two == "\342\200\224") { cut = i; break }
      }
      if (cut == 0) { head = desc; tail = "" }
      else { head = substr(desc, 1, cut - 1); tail = substr(desc, cut + 1) }
      emit(skill, head, "H")
      emit(skill, tail, "T")
    }
    END {
      total = 0; hard = 0
      for (g in grams) {
        nsk = 0
        for (i = 1; i <= ns; i++) {
          s = skills[i]
          if ((g SUBSEP s) in seen) { owners[++nsk] = s; zones[nsk] = seen[g, s] }
        }
        if (nsk < 2) continue
        gl = (g in len) ? 3 : 2
        for (a = 1; a <= nsk - 1; a++) for (b = a + 1; b <= nsk; b++) {
          za = zones[a]; zb = zones[b]
          wt = (za == "H" && zb == "H") ? 3 : ((za == "H" || zb == "H") ? 2 : 1)
          pair = (owners[a] < owners[b]) ? owners[a] " / " owners[b] : owners[b] " / " owners[a]
          pscore[pair] += gl * wt
          pgram[pair] = pgram[pair] (pgram[pair] == "" ? "" : ", ") g
          total += gl * wt
          if (za == "H" && zb == "H" && gl == 3) {
            hard++
            hardline[hard] = pair ": \"" g "\" in both HEAD clauses"
          }
        }
      }
      for (p in pscore) printf "%6d  %s: %s\n", pscore[p], p, pgram[p] | "sort -rn"
      close("sort -rn")
      printf "\ncorpus score %d across %d skills\n", total, ns
      if (hard > 0) {
        printf "\nHARD FAIL -- a 3-gram opens two descriptions:\n"
        for (i = 1; i <= hard; i++) printf "  %s\n", hardline[i]
        exit 1
      }
      printf "hard-fail pairs: none\n"
    }
  ')"
  rc=$?
  printf '%s\n' "$out"
  # awk exiting 2 (a parse or runtime error) is not "no collisions found". Distinguish it from
  # the deliberate exit 1, or a broken scorer reports a clean corpus forever.
  if [ "$rc" -gt 1 ]; then
    echo "REFUSING: awk failed (rc=$rc) -- the corpus was not scored." >&2
    return 2
  fi
  return "$rc"
}

# ---------------------------------------------------------------------------
# Self-test. CONTRIBUTING.md requires a check be seen failing before it is trusted, and this one
# carries its own mutation rather than leaning on tests/gate-falsifiability.sh, which is owned
# elsewhere. Plants a HEAD/HEAD 3-gram, asserts exit 1 and that the planted pair is named; then
# scores a clean corpus and asserts exit 0.
# ---------------------------------------------------------------------------
self_test() {
  local t rc out fails=0
  t="$(mktemp -d "${TMPDIR:-/tmp}/desc-collision-selftest.XXXXXX")"

  mk() {
    mkdir -p "$t/$1"
    printf -- '---\nname: %s\ndescription: "%s"\n---\n# %s\n' "$1" "$2" "$1" > "$t/$1/SKILL.md"
  }

  # The planted 3-gram has to survive normalisation to be a fair test of the scorer. "Tear this
  # apart" does not: "this" is a stopword, so it drops to the 2-gram "tear apart" and the check
  # correctly declines to fail. Content words only.
  mk alpha "Shipping risky payment migration code today: review the blast radius first."
  mk beta  "Shipping risky payment migration code today: interview every reviewer first."
  out="$(score "$t")"; rc=$?
  if [ "$rc" -ne 1 ]; then
    echo "SELF-TEST FAIL: planted HEAD/HEAD 3-gram did not fail the check (rc=$rc)"; fails=1
  elif ! grep -q 'alpha / beta' <<<"$out"; then
    echo "SELF-TEST FAIL: failed, but did not name the planted pair"; fails=1
  else
    echo "self-test 1/2 ok: planted collision fails and names alpha / beta"
  fi

  rm -rf "${t:?}"/*
  mk alpha "A settled spec with nothing written down: produce ordered steps."
  mk beta  "A running dev server and a component that renders wrong: screenshot every breakpoint."
  out="$(score "$t")"; rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "SELF-TEST FAIL: clean corpus was rejected (rc=$rc)"; echo "$out"; fails=1
  else
    echo "self-test 2/2 ok: clean corpus passes"
  fi

  rm -rf "$t"
  return "$fails"
}

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

case "${1:-}" in
  --self-test) self_test; exit $? ;;
  "")          DIR="$REPO_ROOT/claude/skills" ;;
  *)           DIR="$1" ;;
esac

echo "Scoring shared trigger n-grams in $DIR"
echo "Failing condition: a 3-gram appearing in BOTH skills' first clause. Nothing else fails."
echo "This is design discipline, not a dispatch measurement -- see the header, and"
echo "tests/evals/collision/RESULTS.md for what a committed instrument actually found."
echo "---"
score "$DIR"
exit $?
