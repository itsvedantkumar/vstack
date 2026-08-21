#!/usr/bin/env bash
# compare-baseline.sh — measure what this configuration does that an unconfigured Claude Code
# does not, and what it costs to have it.
#
# WHY THIS EXISTS, AND WHAT IT REFUSES TO CLAIM.
#
# Every setup like this one says it makes you better. Almost none of them can show it, because
# the claim is usually about outcomes — better code, faster shipping — and those depend far more
# on the person and the problem than on the config. A benchmark that claimed otherwise would be
# marketing with a shell script attached.
#
# So this measures something narrower and checkable: which safety and routing MECHANISMS exist,
# and what they do when fired with identical input. "Bare" here means Claude Code with no hooks
# configured, which is what you have before installing anything. The comparison is not a
# simulation of how a model behaves — it is a statement about whether a mechanism is present and
# what it decides, run for real, both ways.
#
# WHAT THIS DOES NOT MEASURE, and nobody should read it as measuring:
#   - whether the skills produce better work. That needs a live model and human judgement;
#     tests/auto-trigger.sh measures whether they FIRE, which is a different and smaller claim.
#   - speed, cost-in-dollars, or how any of this feels to use.
#   - whether any other setup is worse. Other setups have mechanisms this one does not.
#     gstack's `careful` covers similar ground for destructive commands, opt-in per session.
#
# The last column is the honest one: this configuration is not free. It spends context on every
# session, every session, whether or not a skill fires. That number is printed here rather than
# buried, because a comparison that only lists what you gain is an advertisement.
#
# Usage: tests/compare-baseline.sh [--json]

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

JSON=0
[ "${1:-}" = "--json" ] && JSON=1

# cd/pwd to canonicalise. On macOS $TMPDIR ends in a slash, so mktemp -d "$TMPDIR/x" yields a
# path with a double slash in it — and the verify gate resolves its own path with cd+pwd, which
# does not. The two spellings then fail to match in the trust file and the gate skips, which
# reads exactly like the gate being broken.
ROOT=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/vstack-compare.XXXXXX")" && pwd)
trap 'rm -rf "$ROOT"' EXIT

ROWS=""
FAIL=0
# Every row carries the value it is supposed to produce, so this is a regression test that
# happens to print a table rather than a table that happens to be true today. A comparison
# nobody can make fail is a brochure.
row() { # <scenario> <bare> <vstack> <expected|-> <matters>
  if [ "$4" != "-" ] && [ "$3" != "$4" ]; then
    printf 'REGRESSION  %s: expected "%s", got "%s"\n' "$1" "$4" "$3" >&2
    FAIL=1
  fi
  ROWS="$ROWS$1|$2|$3|$5
"
}

need_jq() { command -v jq >/dev/null 2>&1; }
if ! need_jq; then echo "compare-baseline.sh needs jq"; exit 2; fi

# --- 1. an agent that says it is done while verification fails --------------------------------
# The single behaviour this configuration exists for. With no Stop hook there is nothing between
# an agent's claim and you believing it. Both sides are run for real: the vstack side fires the
# actual hook against a repo whose gate exits non-zero.
gd="$ROOT/gate"; mkdir -p "$gd/repo/.claude" "$gd/home/.config/agents" "$gd/tmp"
printf '#!/usr/bin/env bash\necho "two tests failing"\nexit 1\n' > "$gd/repo/.claude/verify.sh"
chmod +x "$gd/repo/.claude/verify.sh"
if command -v shasum >/dev/null 2>&1; then gh_=$(shasum -a 256 "$gd/repo/.claude/verify.sh" | cut -d' ' -f1)
else gh_=$(sha256sum "$gd/repo/.claude/verify.sh" | cut -d' ' -f1); fi
printf '%s  %s\n' "$gh_" "$gd/repo/.claude/verify.sh" > "$gd/home/.config/agents/verify-trust"
vs_gate=$(printf '{"session_id":"cmp-gate"}' \
  | env HOME="$gd/home" TMPDIR="$gd/tmp" CLAUDE_PROJECT_DIR="$gd/repo" \
    bash claude/hooks/verify-gate.sh 2>/dev/null | jq -r '.decision // "no decision"')
row "agent claims done, tests fail" \
    "nothing intervenes" \
    "$vs_gate" block \
    "incomplete work is reported as finished"

# --- 2 to 4. destructive commands, with permissions bypassed ------------------------------------
# This configuration recommends --bypass-permissions, which removes the prompt that would
# otherwise catch these. A guard is not a bonus in that arrangement; it is the replacement for
# something that was taken away.
guard() { printf '{"tool_input":{"command":%s}}' "$(jq -Rn --arg c "$1" '$c')" \
          | bash claude/hooks/guard-destructive.sh 2>/dev/null \
          | jq -r '.hookSpecificOutput.permissionDecision // "no decision"'; }
row "rm -rf / from an agent" "runs" "$(guard 'rm -rf /')" deny "unrecoverable"
row "git push --force origin main" "runs" "$(guard 'git push --force origin main')" deny "history loss on a shared branch"
row "git reset --hard, uncommitted work" "runs" "$(guard 'git reset --hard HEAD~3')" ask "silent loss of work in progress"
# The row that proves the guard is not simply blocking everything. A guard that interrupts
# routine work gets disabled, and a disabled guard measures zero.
row "rm -rf node_modules (routine)" "runs" "$(guard 'rm -rf node_modules')" allow "a guard that nags gets switched off"

# --- 5. a cloned repo's gate, unarmed ----------------------------------------------------------
# The other direction: what this configuration refuses to do. An untrusted repo's verify.sh is
# repo-controlled code, and running it on Stop just because it exists would be a handout.
ud="$ROOT/untrusted"; mkdir -p "$ud/repo/.claude" "$ud/home/.config/agents" "$ud/tmp"
printf '#!/usr/bin/env bash\nexit 1\n' > "$ud/repo/.claude/verify.sh"; chmod +x "$ud/repo/.claude/verify.sh"
un=$(printf '{"session_id":"cmp-untrusted"}' \
  | env HOME="$ud/home" TMPDIR="$ud/tmp" CLAUDE_PROJECT_DIR="$ud/repo" \
    bash claude/hooks/verify-gate.sh 2>/dev/null | jq -r '.decision // "did not run it"')
row "untrusted repo's gate on Stop" "no gate at all" "$un" "did not run it" "executing a stranger's code unasked"

# --- 6. the cost ---------------------------------------------------------------------------------
# Printed as a first-class result, not a footnote. Every session pays this whether or not a skill
# fires, and anyone deciding whether to install this deserves the number.
# Measured the way a stranger experiences it, and measured the same way check 18 does.
#
# These two disagreed at first — 2825 B here against 3655 B there — because this was being run
# inside Conductor, which sets CONDUCTOR_WORKSPACE_PATH, which makes the hook skip a block it
# emits everywhere else. Reporting the smaller number would have been quietly flattering: the
# figure a reader gets is the one without that variable set. Same probe as the gate now, so the
# two cannot drift apart again.
probe_ctx(){ # <profile-or-empty>
  printf '{"hook_event_name":"SessionStart"}' \
    | env CONDUCTOR_WORKSPACE_PATH="" ${1:+VSTACK_PROFILE=$1} \
      bash claude/hooks/inject-session-context.sh 2>/dev/null | wc -c | tr -d ' '
}
full=$(probe_ctx "")
skills=$(probe_ctx skills)
# Rounded, because the exact count is environment-dependent — it embeds text that differs
# between machines. Publishing a precise-looking number that is only true where it was measured
# is the kind of false precision this repo keeps deleting from its own docs.
fullkb=$(awk -v b="$full" 'BEGIN{printf "%.1f", b/1024}')
skkb=$(awk -v b="$skills" 'BEGIN{printf "%.1f", b/1024}')
row "context spent per session (cost)" "0 B" "~${fullkb} KB full / ~${skkb} KB plugin" - "you pay this every session"

if [ "$JSON" = 1 ]; then
  printf '%s' "$ROWS" | jq -Rs 'split("\n")|map(select(length>0))|map(split("|"))|map({scenario:.[0],bare:.[1],vstack:.[2],matters:.[3]})'
  exit 0
fi

echo "vstack vs an unconfigured Claude Code — mechanisms, measured by running them"
echo
printf '%-36s %-18s %-26s %s\n' "scenario" "bare" "vstack" "why it matters"
printf '%-36s %-18s %-26s %s\n' "------------------------------------" "------------------" "--------------------------" "--------------"
printf '%s' "$ROWS" | while IFS='|' read -r a b c d; do
  [ -n "$a" ] && printf '%-36s %-18s %-26s %s\n' "$a" "$b" "$c" "$d"
done
echo
echo "Measured by firing the real hooks with identical input, not by asking a model."
echo "It says nothing about whether the skills produce better work — tests/auto-trigger.sh"
echo "measures whether they fire, which is a smaller claim, and no test here measures quality."
echo
[ "$FAIL" -eq 0 ] && echo "every mechanism produced the decision it is supposed to" \
  || echo "A MECHANISM REGRESSED — see the REGRESSION lines above"
exit "$FAIL"
