#!/usr/bin/env bash
# tests/dispatch-fleet.sh
#
# Fleet-wide skill-dispatch measurement over the 54 frozen fixtures in
# ~/vstack-dispatch/fixtures.jsonl (read-only input, never edited by this script -- see that
# directory's README.md for the measurement design and why the fixture set is shaped the way it
# is). This is the broad instrument: four classes (pos/neg/col/var), scored separately, never
# blended into one number. tests/auto-trigger.sh remains the older, narrower, retry-based
# instrument and is not superseded by this file; the two answer different questions and neither
# is sourced or exec'd from here (auto-trigger.sh's own header says not to do that, and the same
# reasoning applies in this direction: sourcing it would run ITS preflight and case list, not
# this one's).
#
# ---------------------------------------------------------------------------
# SAMPLE DEFINITION -- read this before trusting any number this script prints.
#
# One sample is one raw, non-retrying `claude -p` invocation. There is no ATTEMPTS-style retry
# loop here: tests/auto-trigger.sh's own header documents in detail why a stop-at-first-hit loop
# measures "did it ever fire" and not a rate, and why every number this repo published before
# that was understood (19/28, 22/28, 5/8 twice) was wrong for exactly that reason. Getting k/n for
# a fixture means k/n independent invocations, full stop.
# ---------------------------------------------------------------------------
#
# WHAT n CAN AND CANNOT SAY (also printed at the end of every run, so this is not only here):
# two-sided 95% Wilson intervals. At n=10 the interval separates "never fires" (near 0/10) from
# "fires at least about half the time" and nothing finer -- it does NOT separate a 90% behavior
# from a 60% one, which needs n of roughly 32-35 (tests/auto-trigger.sh's own header derives this
# the same way). Report raw k/n always; a bare percentage or a point estimate at this n implies
# precision the sample size does not have, which is why this script never prints one without the
# k/n and the interval beside it.
#
# ---------------------------------------------------------------------------
# Exit codes:
#   0  the run (or the score-only report) completed and at least one fixture was actually
#      measured -- a real pass, not a report about nothing.
#   1  ran, but the property this script exists to protect did not hold: a selector matched no
#      fixture (0 declared/ran), or a sample breached the tool fence (see fence_violations below).
#      A skip is not a pass, and this must never look byte-identical to a clean run.
#   2  could not run at all: claude/jq unavailable, not authenticated, hook drift unresolved,
#      RUNLOG schema mismatch, or the operator declined a spend above the confirmation threshold.
#      CI gets a silent 0 here (same contract as auto-trigger.sh/team-start.sh): GitHub Actions
#      has no ANTHROPIC_API_KEY by design, so an absent session is expected, not broken.
# ---------------------------------------------------------------------------
#
# Parameters (env vars; class/id selector is both a class filter AND positional fixture ids,
# matching auto-trigger.sh's and team-start.sh's "no args = everything, args name cases" idiom):
#   FIXTURES              path to the frozen fixture file (default ~/vstack-dispatch/fixtures.jsonl)
#   CLASS                 comma list of pos,neg,col,var to include (default: all four)
#   N                     samples per selected fixture (default 10 -- see the Wilson note above
#                          for exactly what that n does and does not support)
#   MODEL                 default sonnet
#   MAX_TURNS             default 3, same default as auto-trigger.sh
#   PER_CASE_TIMEOUT      seconds, default 120 -- macOS has no timeout(1), enforced by polling
#   CONFIRM_THRESHOLD     projected-call count above which a spend needs confirmation (default 20)
#   VSTACK_DISPATCH_YES=1 pre-confirms a non-interactive run above CONFIRM_THRESHOLD
#   RUNLOG                path to the durable JSONL result log (default: a fresh mktemp path --
#                          pass the SAME path back in to resume a crashed run or top up N)
#   KEEP_WORKDIRS=1       skip the rm -rf on each sample's /tmp/dispatch-fleet.XXXXXX workdir and
#                          print where it was kept, instead of deleting the transcript the moment
#                          the sample finishes. Default is still delete: this is for diagnosing a
#                          specific finding (a 0/5 that needs its transcripts read), not for every
#                          run. Observed out.jsonl size on this machine ranges ~200B (no_output /
#                          error_max_turns samples) to ~14KB (a normal few-turn dispatch decision,
#                          MAX_TURNS=3, Write/Edit/Bash denied so nothing artifact-heavy gets
#                          written into the transcript); err.log is normally empty;
#                          .delegation-log.jsonl is one short JSON line, well under 1KB. A full
#                          default arm (54 fixtures x N=10 = 540 samples) kept end to end is
#                          therefore on the order of a few MB to worst case ~10MB on this
#                          evidence, NOT the tens-of-MB-per-transcript pathological case a
#                          Task-heavy or ToolSearch-loop-heavy session can produce elsewhere in
#                          this repo's own measurements (auto-trigger.sh's fence comment cites a
#                          single 15MB transcript from a different, unfenced probe) -- that upper
#                          bound is real but has not been observed against THIS fence, and running
#                          a full 540-sample arm under KEEP_WORKDIRS=1 to find out costs real
#                          model spend, not just disk, so do not do that speculatively. Prefer
#                          narrowing with CLASS/positional ids + KEEP_WORKDIRS=1 to the specific
#                          fixtures under diagnosis.
#   VSTACK_ALLOW_HOOK_DRIFT=1  overrides the hook-drift preflight (see check_hook_drift below)
#   positional args        fixture ids to run (e.g. pos-01 col-11); empty = every id in CLASS
#   --score-only            skip the run loop; just re-score an existing RUNLOG (no claude, no
#                            hook-drift preflight, no confirmation -- pure jq over what is on disk)
#
# What this script deliberately does NOT do: no CLAUDE_CONFIG_DIR isolation, no settings.json
# patch-and-restore. Those exist elsewhere in this repo (tests/evals/false-done/run.sh) for
# swapping between COMPETING configs on the same machine -- gstack vs vstack vs none. This
# script measures dispatch against whatever is CURRENTLY INSTALLED under ~/.claude; that is the
# point, not a confound to isolate away, and the hook-drift preflight below is what makes "which
# program did this number measure" answerable instead of isolating the question out of existence.
# CLAUDE_CONFIG_DIR to a fresh dir is also known to break `claude -p` login on this machine, so it
# is not a free substitute even where isolation would otherwise be wanted (see docs/provenance).
#
# The Stop hook's delegation logger still fires against every real sample -- that part IS
# isolated (VSTACK_DELEGATION_LOG pointed at the sample's own throwaway workdir below, exported
# on the same command line as the claude invocation it belongs to, never via a separate `VAR=x
# cmd | ...` pipeline stage, which is how this repo leaked synthetic rows into the real
# operator log once before).
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURES="${FIXTURES:-$HOME/vstack-dispatch/fixtures.jsonl}"
CLASS="${CLASS:-pos,neg,col,var}"
N="${N:-10}"
MODEL="${MODEL:-sonnet}"
MAX_TURNS="${MAX_TURNS:-3}"
PER_CASE_TIMEOUT="${PER_CASE_TIMEOUT:-120}"
CONFIRM_THRESHOLD="${CONFIRM_THRESHOLD:-20}"
KEEP_WORKDIRS="${KEEP_WORKDIRS:-0}"

SCORE_ONLY=0
ARGS=()
for a in "$@"; do
  case "$a" in
    --score-only) SCORE_ONLY=1 ;;
    *) ARGS+=("$a") ;;
  esac
done
SELECTED=("${ARGS[@]+"${ARGS[@]}"}")

: "${RUNLOG:=$(mktemp "${TMPDIR:-/tmp}/dispatch-fleet.XXXXXX.jsonl")}"

. "$REPO_ROOT/tests/evals/lib/runlog.sh"

# ---------------------------------------------------------------------------
# The tool fence. Ported from auto-trigger.sh's --disallowedTools, with the decisions recorded
# here because a mistake in either direction would look like a clean run while measuring the
# wrong fleet:
#
# 1. "Skill" must NEVER appear in this list, in this harness or any other. ZEEP's dispatch-arm
#    probe (2026-08-23) denied it on plausible-sounding reasoning -- Skill only INVOKES a skill,
#    it doesn't mutate anything -- and got skill descriptions absent from context entirely on all
#    3 samples; one transcript's only text was the hook's routing line, nothing to dispatch to.
#    The skill listing rides on the Skill tool being callable, not just visible. A harness that
#    denies it isn't measuring suppressed dispatch, it's measuring a fleet that was never
#    mounted. GUARD_NO_SKILL_DENY below makes this a runtime assertion, not just a comment, so a
#    future edit that adds "Skill" here fails loudly instead of silently.
#
# 2. "ToolSearch" is deliberately NOT denied, and is NOT free of scrutiny either. Same ZEEP probe:
#    a --max-turns 2 run hit error_max_turns on all 3 samples with both turns spent inside
#    ToolSearch ("No matching deferred tools found" + an unrelated tool_reference) -- this build
#    has a deferred-tool registry and ToolSearch is an unrecorded turn sink that predates this
#    harness and is not in auto-trigger.sh's fence either. Denying it would change the
#    environment away from the one real sessions actually run in, which defeats the point of
#    measuring real dispatch. Logging it instead: extract_toolsearch_calls() below counts
#    ToolSearch tool_use blocks per sample and every row carries the count, so a fixture that
#    reads as "never fires" is distinguishable after the fact from one that spent its turn
#    budget on tool discovery before ever reaching a Skill decision -- the same
#    turn-starved-vs-broken distinction case_max_turns()'s table draws in auto-trigger.sh, just
#    measured instead of guessed at. See the "ToolSearch usage" report section for the numbers.
#    This is not yet evidence any fixture here has lost turns this way -- MAX_TURNS defaults to
#    3, not 2, and no real sample has been run against this checkout. It is untested exposure,
#    logged rather than ignored.
#
# 3. "Workflow" is now denied on its own live-transcript evidence, not on the convenience of
#    matching a runlog header (E-45, 2026-08-23, same audit shape as E-44's auto-trigger.sh fence
#    review). A live sample called Workflow, which launched in the background, wrote an 863-byte
#    generator script into ~/.claude/projects/.../workflows/scripts/, and fanned out to 8 parallel
#    subagents each told to Edit or Write a fixture (this is the ZEEP Z-3 sample auto-trigger.sh's
#    own fence comment already documents in full; not reproduced here). Workflow is Agent's
#    capability class -- a spawn that gets its own tool access this process cannot reliably fence
#    after the fact -- so it belongs wherever Agent does. auto-trigger.sh denies it as of 2e7d1e5;
#    this harness runs the same kind of samples against the same binary and had not caught up.
#    GUARD_SPAWN_TOOLS_PRESENT below makes Agent's and Workflow's presence a runtime assertion,
#    the same way GUARD_NO_SKILL_DENY does for Skill's absence, so an override that silently drops
#    either turns this into an unfenced dispatch run without printing anything.
#
# 4. "Explore" and "Task" are denied by DEFAULT below but deliberately NOT covered by
#    GUARD_SPAWN_TOOLS_PRESENT. auto-trigger.sh denies both on reasoned-but-not-live-verified
#    grounds -- spawn-class by name and shape, and Task measured emitting zero tool_use blocks
#    against a real 15MB transcript while Agent emitted 70 (see that file's tool-fence comment,
#    2026-08-23 audit, for the full per-tool table; not reproduced here) -- and denying either
#    here costs nothing, since no fixture in this set needs them, so the default below matches
#    auto-trigger.sh's stricter fence. They are left out of the hard guard because, unlike
#    Agent/Workflow, no live sample has yet forced either open: a future arm that deliberately
#    wants to measure Explore- or Task-shaped dispatch should be able to narrow DISALLOWED_TOOLS
#    via the override below without editing this file. If either is ever caught live the way
#    Workflow was, promote it into GUARD_SPAWN_TOOLS_PRESENT the same way Workflow was promoted
#    here, with the transcript that justifies it.
#
# DISALLOWED_TOOLS is env-overridable. The alternative -- a literal with no override -- is what
# produced 55 uncommitted samples (tests/dispatch-fleet.sh @ 7140218, S-3's collision-pilot arm):
# the fence needed to change, the file offered no way to do that without editing source, so the
# source got edited and never committed, and the instrument that produced a published finding
# stopped existing in git. An override does not weaken the default -- nothing here is looser
# unless an operator explicitly sets DISALLOWED_TOOLS -- and the schema=2 RUNLOG header below
# records the tools string actually used on every invocation, override or not, so a runlog always
# names its own instrument and check_runlog_params() still refuses a mismatched resume regardless
# of whether the difference came from a source edit or an env var. GUARD_SPAWN_TOOLS_PRESENT
# below runs against whatever value ends up in DISALLOWED_TOOLS -- override or default -- so it
# still refuses an override that drops Agent or Workflow instead of silently running unfenced.
# ---------------------------------------------------------------------------
DISALLOWED_TOOLS="${DISALLOWED_TOOLS:-Write,Edit,MultiEdit,NotebookEdit,Bash,Agent,Workflow,Explore,Task}"
case ",$DISALLOWED_TOOLS," in
  *,Skill,*)
    echo "BUG: DISALLOWED_TOOLS contains Skill -- this would deny the harness the only tool that" >&2
    echo "     makes skill descriptions reachable at all. Refusing to run. See the fence comment" >&2
    echo "     above dated 2026-08-23 (ZEEP's probe) for why this is a hard guard, not advice." >&2
    exit 2
    ;;
esac
case ",$DISALLOWED_TOOLS," in
  *,Agent,*) : ;;
  *)
    echo "BUG: DISALLOWED_TOOLS does not contain Agent -- this build's actual dispatch tool_use" >&2
    echo "     name. An override that drops it turns every sample into an unfenced subagent" >&2
    echo "     launch. Refusing to run. See the fence comment above (item 3) for the reasoning." >&2
    exit 2
    ;;
esac
case ",$DISALLOWED_TOOLS," in
  *,Workflow,*) : ;;
  *)
    echo "BUG: DISALLOWED_TOOLS does not contain Workflow -- a live transcript (ZEEP Z-3, cited in" >&2
    echo "     auto-trigger.sh's fence comment) proved a live sample can call it to launch a" >&2
    echo "     background fan-out past this process's own kill -9. An override that drops it" >&2
    echo "     turns every sample into an unfenced dispatch run. Refusing to run. See the fence" >&2
    echo "     comment above (item 3) for the reasoning." >&2
    exit 2
    ;;
esac

# ---------------------------------------------------------------------------
# RUNLOG header carries the invocation parameters, not just a schema tag. RICK, 2026-08-23: a
# 540-call run is hours long, resumption after a crash is the EXPECTED path (see the
# resumability proof this file was built against), and resuming into a log that was started
# under a different MODEL/MAX_TURNS/tool-fence/fixture-set would silently mix two arms into one
# k/n -- this repo's founding defect (a green number that measured the wrong thing) wearing a
# different hat, and worse here because nothing downstream would ever see the seam. schema=2
# (not 1) so an old schema=1 log from before this fix is treated as a hard mismatch rather than
# silently accepted -- there is no real one yet, this only matters if this file is ever back-
# ported against an in-flight run.
#
# tests/evals/lib/runlog.sh's own open_runlog() already refuses on ANY byte-level header
# mismatch; folding these fields into RUNLOG_HEADER means that existing, already-load-bearing
# check now also happens to catch this. check_runlog_params() below is not a second copy of that
# mechanism -- it runs first, against the same file, so it can name WHICH field differs instead
# of open_runlog's generic have/want dump, then still lets open_runlog do the actual create-or-
# confirm. Only gated behind SCORE_ONLY==0: a --score-only read of a log produced under a
# different MODEL is legitimate (you are reading what is there, not appending to it), so nothing
# is at risk of mixing.
# ---------------------------------------------------------------------------
RUNLOG_HEADER="# dispatch-fleet runlog schema=2 model=$MODEL max_turns=$MAX_TURNS tools=$DISALLOWED_TOOLS fixtures=$FIXTURES"

check_runlog_params() {
  local path="$1"
  [[ -s "$path" ]] || return 0   # fresh/empty log -- nothing to compare, open_runlog will seed it
  local have have_model have_maxturns have_tools have_fixtures named=0
  have="$(head -1 "$path")"
  [[ "$have" == "$RUNLOG_HEADER" ]] && return 0

  echo "PREFLIGHT: RUNLOG $path already holds samples from a DIFFERENT invocation." >&2
  echo "           Resuming into it now would silently mix two arms into one k/n." >&2
  have_model="$(sed -n 's/.* model=\([^ ]*\).*/\1/p' <<<"$have")"
  have_maxturns="$(sed -n 's/.* max_turns=\([^ ]*\).*/\1/p' <<<"$have")"
  have_tools="$(sed -n 's/.* tools=\([^ ]*\).*/\1/p' <<<"$have")"
  have_fixtures="$(sed -n 's/.*fixtures=\(.*\)$/\1/p' <<<"$have")"
  if [[ -n "$have_model" && "$have_model" != "$MODEL" ]]; then
    echo "  MODEL differs: log has '$have_model', this invocation has '$MODEL'" >&2; named=1
  fi
  if [[ -n "$have_maxturns" && "$have_maxturns" != "$MAX_TURNS" ]]; then
    echo "  MAX_TURNS differs: log has '$have_maxturns', this invocation has '$MAX_TURNS'" >&2; named=1
  fi
  if [[ -n "$have_tools" && "$have_tools" != "$DISALLOWED_TOOLS" ]]; then
    echo "  DISALLOWED_TOOLS differs: log has '$have_tools', this invocation has '$DISALLOWED_TOOLS'" >&2; named=1
  fi
  if [[ -n "$have_fixtures" && "$have_fixtures" != "$FIXTURES" ]]; then
    echo "  FIXTURES differs: log has '$have_fixtures', this invocation has '$FIXTURES'" >&2; named=1
  fi
  if [[ "$named" == "0" ]]; then
    echo "  (existing header does not match this schema at all -- treating as schema=1 or older, hard mismatch)" >&2
    echo "  have: $have" >&2
    echo "  want: $RUNLOG_HEADER" >&2
  fi
  echo "  Fix: use a fresh RUNLOG path for this arm, or re-invoke matching the parameters above." >&2
  return 2
}

# ---------------------------------------------------------------------------
# PUBLICATION GATE (RICK, 2026-08-23): ZEEP's arm A5 (n=10, gated behind v1.40.0 installing)
# tests H11 -- whether denying Write/Edit/MultiEdit above systematically suppresses every skill
# whose expected output is an artifact (a skill asked to build a lever cannot build one with
# Write denied). Do not publish a fleet-wide pos-* recall or neg-* precision figure from this
# script until A5 reports. If A5 comes back k>=8/10, this fence is depressing artifact-producing
# skills and every pos-* number below is wrong by an unknown margin in the pessimistic direction.
# If A5 comes back k<=2/10, H11 is dead and the numbers below stand as measured. This gate is
# about PUBLISHING, not about building or proving the harness: the stub-driven proof this file
# was built against is unaffected either way, because a stub does not read --disallowedTools.
# ---------------------------------------------------------------------------

skip_or_fail() {
  echo "SKIP: $1"
  if [[ "${CI:-}" == "true" ]]; then exit 0; fi
  echo "      (exit 2: nothing was tested. Set CI=true to make this a pass.)"
  exit 2
}

# ---------------------------------------------------------------------------
# Hook-drift preflight -- identical contract to tests/team-start.sh's, because the failure mode
# is identical: a stale ~/.claude/hooks tree measures a different program than this checkout and
# reports it as if it were current. Drift has silently voided measurements in this repo three
# times already. VSTACK_ALLOW_HOOK_DRIFT=1 overrides, loudly.
# ---------------------------------------------------------------------------
CDIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
check_hook_drift() {
  local repo_hooks="$REPO_ROOT/claude/hooks"
  local installed_hooks="$CDIR/hooks"
  local drifted="" f base
  [[ -d "$repo_hooks" ]] || return 0
  [[ -d "$installed_hooks" ]] || { echo "PREFLIGHT: $installed_hooks does not exist -- nothing installed. Run install.sh first."; return 1; }
  for f in "$repo_hooks"/*.sh; do
    base="$(basename "$f")"
    if [[ ! -f "$installed_hooks/$base" ]]; then
      drifted="$drifted
  $base -- not installed at all"
    elif ! diff -q "$f" "$installed_hooks/$base" >/dev/null 2>&1; then
      drifted="$drifted
  $base -- installed copy differs from this checkout"
    fi
  done
  if [[ -n "$drifted" ]]; then
    if [[ "${VSTACK_ALLOW_HOOK_DRIFT:-0}" == "1" ]]; then
      echo "PREFLIGHT: hook drift detected, proceeding anyway because VSTACK_ALLOW_HOOK_DRIFT=1:$drifted"
      echo "PREFLIGHT: every sample below measures the INSTALLED hooks in $installed_hooks, not this checkout ($REPO_ROOT)."
      return 0
    fi
    echo "PREFLIGHT FAILED: installed hooks in $installed_hooks drift from $repo_hooks:$drifted"
    echo "      Fix: re-run install.sh from a clean checkout of the commit you want to measure."
    echo "      Override (measure the stale install on purpose): VSTACK_ALLOW_HOOK_DRIFT=1"
    return 1
  fi
  return 0
}

if [[ "$SCORE_ONLY" == "0" ]]; then
  check_hook_drift || exit 2
  command -v claude >/dev/null 2>&1 || skip_or_fail "'claude' CLI not found on PATH."
  AUTH_JSON="$(claude auth status 2>/dev/null)"
  if [[ -z "$AUTH_JSON" ]] || ! grep -q '"loggedIn": *true' <<<"$AUTH_JSON"; then
    skip_or_fail "'claude' CLI is not authenticated (claude auth status did not report loggedIn: true)."
  fi
fi
command -v jq >/dev/null 2>&1 || skip_or_fail "'jq' not found on PATH; required throughout this script."
[[ -f "$FIXTURES" ]] || skip_or_fail "fixture file not found: $FIXTURES"

if [[ "$SCORE_ONLY" == "0" ]]; then
  # open_runlog's own byte-exact header check would ALSO fire here (RUNLOG_HEADER now carries
  # MODEL/MAX_TURNS/tools/FIXTURES), but check_runlog_params runs first so a mismatch is
  # reported by NAME rather than as a raw have/want dump.
  check_runlog_params "$RUNLOG" || exit 2
  open_runlog "$RUNLOG" "$RUNLOG_HEADER"
  rc=$?
  if [[ "$rc" != "0" ]]; then
    echo "PREFLIGHT: RUNLOG problem at $RUNLOG (exit $rc from open_runlog)"
    exit 2
  fi
else
  # --score-only never appends, so a log produced under a different MODEL/MAX_TURNS/tools is not
  # a mixing risk -- it is just data to read. Do not run it through open_runlog's header check
  # (which would refuse it for the same reason check_runlog_params would if this were a real
  # append) or create a header-only file at RUNLOG if it does not exist yet; require it to
  # already hold something, since there is nothing else --score-only could sensibly do.
  if [[ ! -s "$RUNLOG" ]]; then
    echo "--score-only: RUNLOG $RUNLOG does not exist or is empty -- nothing to score."
    exit 1
  fi
fi

# ---------------------------------------------------------------------------
# Fixture selection. class_of() reads the id prefix ("pos-01" -> "pos"); this file has no
# "class" field of its own, so the id IS the class tag, by the fixture format's own convention.
# ---------------------------------------------------------------------------
class_of() { local id="$1"; echo "${id%%-*}"; }

class_selected() {
  case ",$CLASS," in
    *",$(class_of "$1"),"*) return 0 ;;
    *) return 1 ;;
  esac
}

id_selected() {
  [ ${#SELECTED[@]} -eq 0 ] && return 0
  local want
  for want in "${SELECTED[@]}"; do [ "$want" = "$1" ] && return 0; done
  return 1
}

ALL_IDS=()
while IFS= read -r line || [[ -n "$line" ]]; do ALL_IDS+=("$line"); done < <(jq -r '.id' "$FIXTURES")

DECLARED=0
RUN_IDS=()
for id in "${ALL_IDS[@]}"; do
  class_selected "$id" || continue
  DECLARED=$((DECLARED + 1))
  id_selected "$id" && RUN_IDS+=("$id")
done

if [[ "$DECLARED" == "0" ]]; then
  echo "no fixture matches CLASS=$CLASS in $FIXTURES."
  echo "fixtures: 0 declared / 0 ran / 0 skipped"
  exit 1
fi
if [[ ${#RUN_IDS[@]} -eq 0 ]]; then
  echo "no fixture ran. ${#SELECTED[@]} selector(s) given, none matched a fixture id within CLASS=$CLASS."
  echo "fixtures: $DECLARED declared / 0 ran / $DECLARED skipped"
  exit 1
fi
SKIPPED=$((DECLARED - ${#RUN_IDS[@]}))

echo "Fleet dispatch measurement: FIXTURES=$FIXTURES CLASS=$CLASS N=$N MODEL=$MODEL MAX_TURNS=$MAX_TURNS"
echo "RUNLOG=$RUNLOG"
echo "fixtures: $DECLARED declared (CLASS=$CLASS) / ${#RUN_IDS[@]} selected to run / $SKIPPED skipped by id selector"

# ---------------------------------------------------------------------------
# existing_samples ID -- count of rows already in RUNLOG for this id (resumability: a crash or a
# second invocation at the same RUNLOG path tops off to N rather than re-spending from zero).
# ---------------------------------------------------------------------------
existing_samples() {
  local id="$1"
  tail -n +2 "$RUNLOG" 2>/dev/null | jq -r --arg id "$id" 'select(.id==$id) | .id' 2>/dev/null | wc -l | tr -d ' '
}

if [[ "$SCORE_ONLY" == "0" ]]; then
  PROJECTED=0
  for id in "${RUN_IDS[@]}"; do
    ex="$(existing_samples "$id")"
    need=$((N - ex))
    [[ "$need" -lt 0 ]] && need=0
    PROJECTED=$((PROJECTED + need))
  done
  echo "projected new claude -p calls this invocation: $PROJECTED (N=$N per fixture, resuming from whatever RUNLOG already holds)"

  if [[ "$PROJECTED" -gt 0 && "$PROJECTED" -gt "$CONFIRM_THRESHOLD" ]]; then
    if [[ -n "${VSTACK_DISPATCH_YES:-}" ]]; then
      echo "proceeding: VSTACK_DISPATCH_YES=1 pre-confirmed a spend above CONFIRM_THRESHOLD=$CONFIRM_THRESHOLD"
    elif [[ -t 0 ]]; then
      printf 'this spends %d real claude -p calls (above CONFIRM_THRESHOLD=%d). Proceed? [y/N] ' "$PROJECTED" "$CONFIRM_THRESHOLD"
      read -r ans
      case "$ans" in
        y|Y|yes|YES) : ;;
        *) echo "declined by operator -- nothing was measured."; exit 2 ;;
      esac
    else
      echo "PREFLIGHT: projected $PROJECTED calls exceeds CONFIRM_THRESHOLD=$CONFIRM_THRESHOLD and stdin is not a tty."
      echo "      Set VSTACK_DISPATCH_YES=1 to confirm a non-interactive spend, or lower N / narrow the selector."
      exit 2
    fi
  fi
fi

# ---------------------------------------------------------------------------
# extract_fired_ordered OUT_JSONL -- JSON array of skill names in the order their Skill tool_use
# blocks appear in the transcript (NOT sorted/deduped, unlike auto-trigger.sh's
# extract_fired_skills -- CHAIN and AMBIGUOUS scoring both need first-fired order preserved).
# ---------------------------------------------------------------------------
extract_fired_ordered() {
  local jsonl="$1"
  jq -cn '[inputs | select(.type=="assistant") | (.message.content // [])[]? | select(.type=="tool_use" and .name=="Skill") | (.input.skill // "unknown")]' "$jsonl" 2>/dev/null
}

# extract_toolsearch_calls OUT_JSONL -- count of ToolSearch tool_use blocks in the transcript.
# See the fence comment near DISALLOWED_TOOLS above (2026-08-23, ZEEP's probe): ToolSearch is a
# deferred-tool-discovery call that can consume the entire turn budget before a Skill decision is
# ever reached. Not denied, logged instead -- a fixture with toolsearch_calls>0 AND
# subtype=error_max_turns AND fired=[] is a turn-starvation candidate, not necessarily a routing
# miss, the same distinction case_max_turns() draws in auto-trigger.sh.
extract_toolsearch_calls() {
  local jsonl="$1"
  jq -n '[inputs | select(.type=="assistant") | (.message.content // [])[]? | select(.type=="tool_use" and .name=="ToolSearch")] | length' "$jsonl" 2>/dev/null
}

# top_level_subtype OUT_JSONL -- same discriminator as auto-trigger.sh/team-start.sh: a
# background subagent's own result event carries an "origin" field the top-level run's does not.
top_level_subtype() {
  local jsonl="$1"
  jq -rn '[inputs | select(.type=="result" and (.origin==null))] | last | .subtype // "unknown"' "$jsonl" 2>/dev/null
}

# fence_violations WORKDIR BASELINE -- ported from auto-trigger.sh in spirit (see that file's
# comment for why this exists behind --disallowedTools rather than instead of it: a subagent
# launched via Agent is not guaranteed to inherit the parent's disallowed-tools list on every
# code path, and can run detached past this process's own kill -9), but NOT a literal-path
# exclusion list against BASELINE the way auto-trigger.sh's is.
#
# E-46, 2026-08-23: this used to take OUT_JSONL and ERR_LOG and grep -v -F -x them out of the
# diff by literal path. That went stale the moment run_sample() started isolating the Stop
# hook's delegation-drift write into a THIRD harness-owned file
# ($workdir/.delegation-log.jsonl, see run_sample() below and its header comment) without a
# matching third exclusion here -- 25/25 samples in a real arm (S-5, this file @ 7e8d521) came
# back FENCE BREACH on that one file alone, all false positives; see the handback this fix
# answers for the full account. A second hardcoded literal would fix today's breach and go
# stale again the next time run_sample() starts writing a fourth file, the same way it went
# stale this time.
#
# Fixed by construction instead: run_sample() now creates every file THIS HARNESS owns (out,
# err, delegation log) and captures BASELINE only after they all exist, so they are already
# present in BASELINE and never show up as a diff line here at all -- there is no path string
# to keep in sync in this function anymore, because this function no longer knows any of their
# names. Anything that shows up in the diff below is, by construction, something the harness
# did NOT create itself: a real fence breach. This does not weaken the fence -- it still catches
# any new path a sample writes, and unlike the literal-exclusion list it cannot silently widen
# the exclusion by drifting; adding a fourth harness-owned file now requires creating it before
# BASELINE is captured, which is also what makes it excluded, not a second edit in two places
# that can fall out of step.
fence_violations() {
  local workdir="$1" baseline="$2"
  local now
  now="$(find "$workdir" -mindepth 1 2>/dev/null | sort)"
  diff <(printf '%s\n' "$baseline") <(printf '%s\n' "$now") 2>/dev/null \
    | sed -n 's/^> //p' \
    | grep -v '^$'
}

FENCE_BREACH=0

# ---------------------------------------------------------------------------
# run_sample ID PROMPT -- one raw, non-retrying claude -p invocation. Appends exactly one JSON
# row to RUNLOG on completion (including a crashed/no-output sample, so it counts toward n and
# never silently vanishes from the denominator).
# ---------------------------------------------------------------------------
run_sample() {
  local id="$1" prompt="$2"
  local workdir out_jsonl err_log delegation_log runner_pid waited baseline violations
  local fired subtype ts row toolsearch

  workdir="$(mktemp -d "/tmp/dispatch-fleet.XXXXXX")"
  out_jsonl="$workdir/.out.jsonl"; err_log="$workdir/.err.log"
  delegation_log="$workdir/.delegation-log.jsonl"

  # Pre-create every file THIS HARNESS owns, then capture BASELINE only after they all exist.
  # This is what makes fence_violations()'s exclusion "by construction" instead of a literal
  # list of path strings ported around by hand (see that function's header comment for why the
  # old list went stale). If a fourth harness-owned file is ever added, create it here, above
  # the baseline snapshot, and it is excluded the same way -- no second place to edit.
  : > "$out_jsonl"
  : > "$err_log"
  : > "$delegation_log"
  baseline="$(find "$workdir" -mindepth 1 2>/dev/null | sort)"

  # exec is load-bearing: without it the timeout's kill -9 hits an empty subshell wrapper
  # instead of the claude process, leaking a live billed run past this function's own timeout.
  (
    cd "$workdir" || exit 1
    exec env -u ANTHROPIC_API_KEY -u ANTHROPIC_AUTH_TOKEN \
      VSTACK_DELEGATION_LOG="$delegation_log" \
      claude -p "$prompt" \
        --output-format stream-json --verbose \
        --disallowedTools "$DISALLOWED_TOOLS" \
        --model "$MODEL" --max-turns "$MAX_TURNS" \
        < /dev/null > "$out_jsonl" 2> "$err_log"
  ) &
  runner_pid=$!

  waited=0
  while kill -0 "$runner_pid" 2>/dev/null; do
    sleep 1
    waited=$((waited + 1))
    if (( waited >= PER_CASE_TIMEOUT )); then kill -9 "$runner_pid" 2>/dev/null; break; fi
  done
  wait "$runner_pid" 2>/dev/null

  if [[ ! -s "$out_jsonl" ]]; then
    fired="[]"; subtype="no_output"; toolsearch=0
  else
    fired="$(extract_fired_ordered "$out_jsonl")"
    [[ -z "$fired" ]] && fired="[]"
    subtype="$(top_level_subtype "$out_jsonl")"
    [[ -z "$subtype" ]] && subtype="unknown"
    toolsearch="$(extract_toolsearch_calls "$out_jsonl")"
    [[ -z "$toolsearch" ]] && toolsearch=0
  fi

  violations="$(fence_violations "$workdir" "$baseline")"

  if [[ "$KEEP_WORKDIRS" == "1" ]]; then
    echo "  $id: KEEP_WORKDIRS=1 -- workdir kept at $workdir"
  else
    rm -rf "$workdir"
  fi

  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if [[ -n "$violations" ]]; then
    echo "FENCE BREACH $id: run wrote outside its allowed tools:"
    while IFS= read -r v; do printf '    %s\n' "$v"; done <<< "$violations"
    FENCE_BREACH=1
    row="$(jq -cn --arg id "$id" --argjson fired "$fired" --arg subtype "$subtype" \
      --argjson toolsearch "$toolsearch" --arg ts "$ts" --arg violations "$violations" \
      '{id:$id, fired:$fired, subtype:$subtype, toolsearch_calls:$toolsearch, violations:($violations|split("\n")|map(select(length>0))), ts:$ts}')"
  else
    row="$(jq -cn --arg id "$id" --argjson fired "$fired" --arg subtype "$subtype" \
      --argjson toolsearch "$toolsearch" --arg ts "$ts" \
      '{id:$id, fired:$fired, subtype:$subtype, toolsearch_calls:$toolsearch, violations:[], ts:$ts}')"
  fi
  printf '%s\n' "$row" >> "$RUNLOG"
  echo "  $id: fired=$fired subtype=$subtype toolsearch_calls=$toolsearch"
}

if [[ "$SCORE_ONLY" == "0" ]]; then
  for id in "${RUN_IDS[@]}"; do
    prompt="$(jq -r --arg id "$id" 'select(.id==$id) | .prompt' "$FIXTURES" | head -1)"
    ex="$(existing_samples "$id")"
    need=$((N - ex))
    [[ "$need" -lt 0 ]] && need=0
    if [[ "$need" -eq 0 ]]; then
      echo "$id: already has $ex/$N samples in RUNLOG, nothing to do"
      continue
    fi
    echo "$id: running $need more sample(s) (have $ex/$N)"
    i=1
    while [[ "$i" -le "$need" ]]; do
      run_sample "$id" "$prompt"
      i=$((i + 1))
    done
  done
fi

echo "---"

# ---------------------------------------------------------------------------
# Scoring. Pure jq over the frozen fixture file plus whatever is on disk in RUNLOG right now --
# this runs identically whether the rows above it were just produced or are being re-scored from
# a prior crash/resume, and identically against a stub-produced log, which is how the maths below
# is proven correct without spending a real call (see the proof this script's own commit message
# / handback references).
# ---------------------------------------------------------------------------
CLEAN_ROWS="$(mktemp "${TMPDIR:-/tmp}/dispatch-fleet-rows.XXXXXX.jsonl")"
trap 'rm -f "$CLEAN_ROWS"' EXIT
tail -n +2 "$RUNLOG" 2>/dev/null | grep '^{' > "$CLEAN_ROWS" || true

TOTAL_ROWS=$(wc -l < "$CLEAN_ROWS" | tr -d ' ')
if [[ "$TOTAL_ROWS" == "0" ]]; then
  echo "RUNLOG has zero sample rows -- nothing to score."
  echo "fixtures: $DECLARED declared / 0 ran / $DECLARED skipped"
  exit 1
fi

SCORE_JQ='
def wilson(k; n):
  if n == 0 then {lo:0.0, hi:1.0}
  else
    (1.96) as $z
    | (k/n) as $phat
    | (1 + ($z*$z)/n) as $denom
    | (($phat + ($z*$z)/(2*n)) / $denom) as $center
    | (($z * ((($phat*(1-$phat)/n) + ($z*$z)/(4*n*n)) | sqrt)) / $denom) as $half
    | {lo: ([0.0, ($center-$half)] | max), hi: ([1.0, ($center+$half)] | min)}
  end;

def class_of($id): $id | capture("^(?<c>[a-z]+)-") | .c;

def parse_expect($e):
  if $e == "none" then {kind:"none", candidates: []}
  elif ($e | startswith("AMBIGUOUS:")) then {kind:"ambiguous", candidates: ($e[10:] | split("|"))}
  elif ($e | startswith("CHAIN:")) then {kind:"chain", candidates: [$e[6:]]}
  else {kind:"skill", candidates: [$e]}
  end;

def first_candidate_hit($fired; $candidates):
  ($fired | to_entries | map(select(.value as $v | $candidates | index($v) != null)) | .[0].value) // null;

def histogram($samples):
  ($samples | map((.fired[0] // "(none)")) | group_by(.) | map({label: .[0], n: length}) | sort_by(-.n));

(
  $fixtures | map(. + parse_expect(.expect) + {class: class_of(.id)})
) as $fx
| ($rows | group_by(.id) | map({id: .[0].id, samples: .})) as $grouped
| (
    $fx | map(
      . as $f
      | (($grouped[] | select(.id == $f.id) | .samples) // []) as $samples
      | ($samples | length) as $n
      | ($samples | map(select((.subtype // "") == "error_max_turns")) | length) as $starved
      | ($samples | map(select((.violations // []) | length > 0)) | length) as $breaches
      | ($samples | map(select((.toolsearch_calls // 0) > 0)) | length) as $toolsearch_any
      | ($samples | map(select((.toolsearch_calls // 0) > 0 and (.subtype // "") == "error_max_turns" and (.fired | length) == 0)) | length) as $toolsearch_starved
      | (
          if $f.kind == "skill" then
            ($f.candidates[0]) as $want
            | ($samples | map(select(.fired | index($want) != null)) | length) as $k
            | {k: $k, n: $n}
          elif $f.kind == "none" then
            ($samples | map(select((.fired | length) == 0)) | length) as $k
            | {k: $k, n: $n}
          else
            {k: null, n: $n}
          end
        ) as $score
      | (
          if $f.kind == "ambiguous" then
            ($samples | map(
                (.fired) as $fired
                | if ($fired | length) == 0 then "(none)"
                  else (first_candidate_hit($fired; $f.candidates)) as $c
                    | if $c != null then $c else "other:" + $fired[0] end
                  end
              ) | group_by(.) | map({label: .[0], n: length}) | sort_by(-.n)
            )
          elif $f.kind == "chain" then histogram($samples)
          elif $f.kind == "none" then histogram($samples)
          else null
          end
        ) as $winners
      | {id: .id, class: .class, cluster: .cluster, expect: .expect, note: (.note // ""),
         kind: $f.kind, candidates: $f.candidates, n: $n, starved: $starved, breaches: $breaches,
         toolsearch_any: $toolsearch_any, toolsearch_starved: $toolsearch_starved,
         score: $score, winners: $winners}
    )
  ) as $scored
| ($scored | map(select(.class == "pos" and .kind == "skill"))) as $pos_all
| ($pos_all | map(select(.n > 0))) as $pos
| ($scored | map(select(.class == "var" and .kind == "skill" and .n > 0))) as $var
| ($scored | map(select(.class == "neg" and .kind == "none"))) as $neg
| {
    scored: $scored,
    pos_recall: (
      ($pos | map(.score.k) | add // 0) as $k
      | ($pos | map(.score.n) | add // 0) as $n
      | {k: $k, n: $n, ci: wilson($k; $n)}
    ),
    neg_precision: (
      ($neg | map(.score.k) | add // 0) as $k
      | ($neg | map(.score.n) | add // 0) as $n
      | {k: $k, n: $n, ci: wilson($k; $n)}
    ),
    paraphrase: (
      $var | map(
        . as $v
        | ($v.candidates[0]) as $skill
        | ($pos | map(select(.candidates[0] == $skill))) as $match
        | ($pos_all | map(select(.candidates[0] == $skill))) as $match_all
        | if ($match_all | length) == 0 then
            {skill: $skill, var_id: $v.id, note: "no pos-* fixture targets this skill at all (one of the 3 skills the fixture set has no dedicated positive case for)"}
          elif ($match | length) == 0 then
            {skill: $skill, var_id: $v.id,
             note: ("pos-* fixture " + ($match_all | map(.id) | join(",")) + " exists for this skill but has 0 samples in this run -- select it too for a delta")}
          else
            ($match | map(.score.k) | add) as $pk
            | ($match | map(.score.n) | add) as $pn
            | {skill: $skill, var_id: $v.id,
               pos: {k: $pk, n: $pn}, var: {k: $v.score.k, n: $v.score.n},
               delta: (($pk / $pn) - ($v.score.k / $v.score.n))}
          end
      )
    ),
    toolsearch: (
      ($scored | map(.toolsearch_any) | add // 0) as $any
      | ($scored | map(.toolsearch_starved) | add // 0) as $starved
      | ($scored | map(.n) | add // 0) as $n
      | {samples_calling_toolsearch: $any, samples_total: $n, turn_starved_after_toolsearch: $starved}
    )
  }
'

REPORT="$(jq -n --slurpfile fixtures "$FIXTURES" --slurpfile rows "$CLEAN_ROWS" "$SCORE_JQ")"

echo "$REPORT" > "$CLEAN_ROWS.report.json"

echo "== POS (recall) =="
echo "$REPORT" | jq -r '
  .scored[] | select(.class=="pos" and .kind=="skill") |
  "  \(.id)  \(.expect)  \(.score.k)/\(.score.n)  starved=\(.starved) breaches=\(.breaches)"
'
echo "$REPORT" | jq -r '
  .pos_recall as $p |
  "  AGGREGATE pos recall: \($p.k)/\($p.n)  (95% CI \($p.ci.lo|(.*1000|round)/1000)-\($p.ci.hi|(.*1000|round)/1000))"
'

echo
echo "== NEG (precision -- correct answer is no skill at all) =="
echo "$REPORT" | jq -r '
  .scored[] | select(.class=="neg") |
  "  \(.id)  clean(no false positive) \(.score.k)/\(.score.n)  fired-when-wrong: \(.winners // [] | map("\(.label)x\(.n)") | join(", "))"
'
echo "$REPORT" | jq -r '
  .neg_precision as $p |
  "  AGGREGATE neg precision (rate of firing nothing): \($p.k)/\($p.n)  (95% CI \($p.ci.lo|(.*1000|round)/1000)-\($p.ci.hi|(.*1000|round)/1000))  -- NEVER blend this into the pos number above."
'

echo
echo "== COL (deliberate overlap clusters) =="
echo "$REPORT" | jq -r '
  .scored[] | select(.class=="col" and .kind=="skill") |
  "  \(.id)  \(.expect)  \(.score.k)/\(.score.n)  [\(.cluster)]"
'
echo "$REPORT" | jq -r '
  .scored[] | select(.class=="col" and .kind=="ambiguous") |
  "  \(.id) AMBIGUOUS(\(.candidates|join("|")))  n=\(.n)  split: \(.winners // [] | map("\(.label)x\(.n)") | join(", "))"
'
echo "$REPORT" | jq -r '
  .scored[] | select(.class=="col" and .kind=="chain") |
  "  \(.id) CHAIN(expected first=\(.candidates[0]))  n=\(.n)  fired-first: \(.winners // [] | map("\(.label)x\(.n)") | join(", "))"
'

echo
echo "== VAR (paraphrase -- same intent, none of the description's literal trigger words) =="
echo "$REPORT" | jq -r '
  .scored[] | select(.class=="var" and .kind=="skill") |
  "  \(.id)  \(.expect)  \(.score.k)/\(.score.n)"
'
echo "$REPORT" | jq -r '
  .paraphrase[] |
  if .note then "  \(.var_id) (\(.skill)): \(.note)"
  else "  \(.var_id) (\(.skill)): pos \(.pos.k)/\(.pos.n)  var \(.var.k)/\(.var.n)  delta=\((.delta*1000|round)/1000)"
  end
'

echo
echo "== ToolSearch usage (logged, not denied -- see the fence comment near DISALLOWED_TOOLS) =="
echo "$REPORT" | jq -r '
  .toolsearch as $t |
  "  \($t.samples_calling_toolsearch)/\($t.samples_total) samples called ToolSearch at least once; \($t.turn_starved_after_toolsearch) of those hit error_max_turns with fired=[] -- turn-starvation-via-ToolSearch candidates, not necessarily routing misses."
'

echo
echo "== PUBLICATION GATE (RICK, 2026-08-23) =="
echo "  Do not publish a fleet-wide pos-* recall or neg-* precision figure from a real run of this"
echo "  script until ZEEP's arm A5 (H11, n=10, gated behind v1.40.0) reports whether denying"
echo "  Write/Edit/MultiEdit in DISALLOWED_TOOLS suppresses artifact-producing skills. A5 k>=8/10"
echo "  means the pos-* numbers above are wrong in the pessimistic direction by an unknown margin;"
echo "  A5 k<=2/10 means H11 is dead and they stand as measured. This gate is about publishing a"
echo "  real-call result, not about running this script -- it does not apply to a stub-driven run."

echo
echo "== what N=$N can and cannot say =="
echo "  Two-sided 95% Wilson intervals, raw k/n always printed beside them, no bare point estimates."
echo "  At the n actually run per fixture (see each line above -- resumed fixtures may be below N),"
echo "  this separates 'never fires' from 'fires at least about half the time', and nothing finer:"
echo "  separating a 90% behavior from a 60% one needs n of roughly 32-35 per fixture, not $N."
echo "  AMBIGUOUS splits and CHAIN first-fired are reported as raw distributions, not pass/fail:"
echo "  a 50/50 split and a 100/0 split are different findings and neither is an error by itself."

echo
FBSTR=""
[[ "$FENCE_BREACH" == "1" ]] && FBSTR=" -- FENCE BREACH occurred (see FENCE BREACH lines above); this is a fail regardless of dispatch numbers"
echo "fixtures: $DECLARED declared / ${#RUN_IDS[@]} selected to run / $SKIPPED skipped by id selector$FBSTR"

if [[ "$FENCE_BREACH" == "1" ]]; then
  exit 1
fi
exit 0
