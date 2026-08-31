#!/usr/bin/env bash
# gate-falsifiability.sh — proof that each check in .claude/verify.sh can actually fail.
#
# A check that cannot fail is indistinguishable from a check that is not there, and this repo
# has shipped both. Check 11 read two of three hook lanes while its label claimed otherwise.
# Check 12 asserted only that a correct number appeared somewhere, so a wrong one shipped
# beside it. Three checks were wrapped in a bare `if command -v jq` with no else and printed
# nothing at all on a host without jq. Every one of those was green the whole time.
#
# So: for each declared check, break exactly the thing it watches, require the gate to go red
# naming that check, put the tree back, and confirm the tree is clean afterwards.
#
# Adding a check to verify.sh without adding a row here fails check 16 of the gate itself.
#
# Runs offline in about 30 seconds. CI runs it on every push.

set -uo pipefail

# macOS ships `shasum` and no `sha256sum`; BusyBox ships `sha256sum` and no `shasum`. The no-op
# mutation detector below used bare `shasum ... 2>/dev/null`, which on Alpine returns the empty
# string for EVERY file -- so every before-hash equals every after-hash and the detector reports
# that no mutation changed anything, for reasons that have nothing to do with the mutations. A
# hash function that cannot hash must say so, not return "".
_fhash(){ # <file> -> hex digest, or dies naming what is missing
  if command -v sha256sum >/dev/null 2>&1; then sha256sum < "$1" | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 < "$1" | cut -d' ' -f1
  else
    echo "gate-falsifiability: neither sha256sum nor shasum is on PATH; the no-op mutation detector cannot run, and a run without it is not evidence" >&2
    exit 3
  fi
}
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
# shellcheck source=tests/lib-collision-guard.sh
. "$(pwd)/tests/lib-collision-guard.sh"

# One id per `# --- N.` section in .claude/verify.sh. Check 16 parses this line.
CHECKS="0 1 1b 2 2b 3 3b 4 5 6 7 8 9 9b 10 10b 11 12 13 13b 13c 14 14b 14c 15 16 17 18 18b 18c 18d 19 20 20b 20c 21 22 23 24 25 26 27 28 29 29b 30 31 32 33 34 35 35b 35c 35d 35e 35f 35g 36 37 38 39 40 44 44b 44c 44d 44e 44f 44g 45 46 47 48 49 50 50b 50c 50d 51 51b 52 53 54 54b 55 55b 55c 56 56b 57 57b 57c 57d 58 58b 58c 27b 27c 59"
CHECKS_ALL="$CHECKS"
# Scoped runs: VSTACK_FALSIFY_ROWS="31 32 33" limits the mutation loop below to those ids, for
# exercising a subset within a time budget instead of the full ~15 minute sweep. The CHECKS line
# above is left untouched for check 16's `^CHECKS="[^"]*"` parser, which greps only its first
# match, so a scoped run cannot silently narrow what check 16 believes is declared. $CHECKS_ALL
# is that same master list, captured before any override, so a scoped run can validate its own
# ids against it below.
#
# Space-separated, matching the form documented two paragraphs up -- not comma-separated, which
# is rejected rather than accepted. `VSTACK_FALSIFY_ROWS=23,27,40` used to become one word,
# "23,27,40", that matched no case arm anywhere below, mutated nothing, and printed "did NOT fail
# when broken" -- the same words this suite prints for an actual defect. Reject the format
# outright rather than silently mistaking an unparsed value for a falsifiability failure.
if [ -n "${VSTACK_FALSIFY_ROWS:-}" ]; then
  case "$VSTACK_FALSIFY_ROWS" in
    *,*)
      printf 'ERROR VSTACK_FALSIFY_ROWS takes ids separated by spaces, not commas: %s\n' \
        "$VSTACK_FALSIFY_ROWS"
      printf '      example: VSTACK_FALSIFY_ROWS="23 27 40"\n'
      exit 1 ;;
  esac
  CHECKS="$VSTACK_FALSIFY_ROWS"
  # An id with no break_it/label_for arm, or one simply absent from the declared master list, is
  # not a check this run found unfalsifiable -- it is a check this run never looked at. The two
  # read identically as "did NOT fail when broken" unless this says otherwise up front: fail
  # before anything is mutated, name every bad id in one message, and never enter the loop below.
  _unknown=""
  for _id in $CHECKS; do
    _found=0
    for _k in $CHECKS_ALL; do [ "$_k" = "$_id" ] && { _found=1; break; }; done
    [ "$_found" -eq 1 ] || _unknown="$_unknown $_id"
  done
  if [ -n "$_unknown" ]; then
    printf 'ERROR unknown check id(s):%s -- not declared in CHECKS, no break_it/label_for arm\n' \
      "$_unknown"
    printf '      nothing was mutated; this is not a falsifiability failure\n'
    exit 1
  fi
fi

BK=$(mktemp -d)
NOJQ=$(mktemp -d)
# EXP holds, per backed-up file, the content this suite itself last wrote there -- the
# pre-mutation copy the instant save() runs, updated to the post-mutation copy the instant
# break_it() returns, and updated again to the pre-mutation copy the instant a restore succeeds.
# It is what restore() and restore_all() compare the live file against before writing $BK back
# over it, and it has to move every time this suite itself writes the file or the comparison
# lies: leaving $EXP on its post-mutation value after a successful restore made the *next* row
# to touch the same file (27 then 40, both claude/hooks/skill-mandate.sh) read its own correctly
# restored file as a stranger's edit -- a false positive caught by running rows 27 and 40 back to
# back before trusting this. See the restore()/conflict_guard() comment below for why a plain
# "always copy $BK back" was the defect this file exists to not have.
EXP=$(mktemp -d)
# Where a refused restore's pre-mutation backup goes so it is not lost along with $BK on exit.
# Created unconditionally and removed empty by cleanup() when nothing ever refused; kept, and
# its path printed, when something did.
CONFLICT_DIR=$(mktemp -d)
# Announce that this tree is being mutated on purpose, so a concurrent verify.sh refuses to run
# rather than reporting a mutation as a real failure. Three sessions sharing one checkout got
# three plausible-looking wrong answers out of that window -- "README pins v1.13.3" when HEAD
# plainly said v1.13.4, and so on. A wrong answer that reads as a finding is worse than an error.
#
# The lock lives in .git, not the worktree, so it can never show up in the tree-unchanged diff at
# the end. It carries this pid, and verify.sh ignores a lock whose process is gone, so a killed
# run cannot wedge the gate for everyone -- which matters, because this suite does get killed.
# --git-common-dir, not --git-dir: the latter is PER-WORKTREE (.git/worktrees/<name> from a
# linked worktree), so a lock written there is invisible to a peer session working a different
# worktree of the same repo. --git-common-dir resolves to the same path from every worktree.
# See docs/worktree-collision-detection.md.
LOCK="$(git rev-parse --git-common-dir 2>/dev/null)/vstack-falsifiability.lock"
# Line 2 is this process's cwd, not just its pid -- a reader refusing to run because this lock
# is live used to say "this working tree" unconditionally, which is false for any lock holder
# working a *different* worktree of the same repo (the lock is deliberately keyed on
# --git-common-dir so it spans all of them). Cheap to record, no lsof dependency.
printf '%s\n%s\n' "$$" "$(pwd)" > "$LOCK" 2>/dev/null || LOCK=""
# EXIT alone does not fire when the shell is killed, and this suite gets killed: someone restarts
# it at a later commit, or a wrapper times it out. Both times that happened today it left a
# mutated file on disk -- install.sh once, README.md once in another worktree -- and the tree
# looked like it carried a real defect.
#
# The baseline check does catch it on the next run, loudly, which is the safety net working. But
# "your repository is now wrong and the next run will tell you why" is a poor answer when putting
# it back is this cheap. INT, TERM and HUP restore too.
#
# Restoring everything in $BK rather than tracking the row in flight: save() overwrites its
# backup before each mutation, so the newest copy of each file is always its pre-mutation state,
# and re-copying a file that was already restored writes identical bytes. Idempotent, and it does
# not depend on knowing where the run stopped -- which is the one thing a killed run cannot tell
# you.
#
# That "just copy $BK back" used to be the whole function, and it was the defect: a row's window
# runs from save() through the check that follows, and anything another writer put into that file
# during the window -- an unrelated edit landing on this repo while the suite happened to be
# mutating the same file -- got silently overwritten with this row's pre-mutation copy. No error,
# no diff, the edit just reverted. Confirmed twice: a five-line README edit reverted mid-sweep,
# noticed only because a second reader was watching; a real test-command fix reverted the same
# way and shipped lost, noticed only because its author had quoted the diff elsewhere. Neither
# was a mutation that "did NOT fail when broken" -- both were correct, committed-worthy edits
# this suite ate.
#
# conflict_guard() is the fix: before writing $BK back over a file, compare the file's current
# bytes against $EXP, this suite's own record of what it last wrote there (pre-mutation the
# instant save() ran, post-mutation the instant break_it() returned -- see $EXP above). Equal
# means the only writer since was this suite, and restoring is safe. Different means somebody
# else wrote to it inside the window: restoring now would silently destroy that write, which is
# worse than leaving the tree mutated, because a mutation left in place shows up in `git status`
# and a silently reverted edit does not. So it refuses, names the file loudly, tucks this row's
# pre-mutation backup under $CONFLICT_DIR instead of overwriting anything, and records the file
# in $CONFLICT_DIR/.conflicts so cleanup() and the end-of-run summary both fail the whole run
# over it -- a sweep that could not restore has not proven the tree is unchanged, and a green
# verdict on top of that is void. The foreign edit itself is never touched either way.
conflict_guard(){
  local _f="$1"
  [ -f "$EXP/$_f" ] || return 0
  cmp -s "$_f" "$EXP/$_f" 2>/dev/null && return 0
  if [ -f "$CONFLICT_DIR/.conflicts" ] && grep -qxF "$_f" "$CONFLICT_DIR/.conflicts" 2>/dev/null; then
    return 1
  fi
  mkdir -p "$CONFLICT_DIR/$(dirname "$_f")" 2>/dev/null
  cp "$BK/$_f" "$CONFLICT_DIR/$_f" 2>/dev/null
  printf 'REFUSED restore: %s changed on disk since this run wrote it last -- a concurrent edit, not this run'"'"'s own mutation.\n' "$_f" >&2
  printf '        leaving the concurrent edit exactly as found. this run'"'"'s pre-mutation backup is kept at: %s\n' "$CONFLICT_DIR/$_f" >&2
  printf '%s\n' "$_f" >> "$CONFLICT_DIR/.conflicts"
  return 1
}
restore_all(){
  [ -d "$BK" ] || return 0
  ( cd "$BK" 2>/dev/null && find . -type f -print ) | sed 's|^\./||' | while IFS= read -r f; do
    [ -n "$f" ] || continue
    conflict_guard "$f" && { cp "$BK/$f" "$f" 2>/dev/null; cp "$BK/$f" "$EXP/$f" 2>/dev/null; }
  done
}
cleanup(){
  _rc=$?
  trap - EXIT INT TERM HUP
  restore_all
  if [ -n "${ORPHAN_PROBE:-}" ] && [ -e "$ORPHAN_PROBE" ]; then
    git rm -q -f --cached "$ORPHAN_PROBE" >/dev/null 2>&1
    rm -f "$ORPHAN_PROBE"
  fi
  # A killed run never reaches the end-of-loop summary below, so this is the only place a
  # conflict born in the last row in flight is guaranteed to be reported. It leaves the foreign
  # edit on disk untouched (conflict_guard already refused to overwrite it) and forces a failing
  # exit even though a killed shell's $? rarely says so on its own -- "the process died" must not
  # read as "the tree was proven clean" just because nothing printed FAIL.
  if [ -s "$CONFLICT_DIR/.conflicts" ] 2>/dev/null; then
    printf 'FAIL  restore integrity: refused to overwrite %s concurrently-edited file(s) -- this sweep cannot vouch for the tree; its verdict is void\n' \
      "$(grep -c '' "$CONFLICT_DIR/.conflicts" 2>/dev/null)" >&2
    sed 's/^/      /' "$CONFLICT_DIR/.conflicts" >&2
    printf '      pre-mutation backups kept at: %s\n' "$CONFLICT_DIR" >&2
    [ "$_rc" -eq 0 ] && _rc=1
  else
    rm -rf "$CONFLICT_DIR" 2>/dev/null
  fi
  rm -rf "$BK" "$NOJQ" "$EXP"
  [ -n "${LOCK:-}" ] && rm -f "$LOCK"
  exit "$_rc"
}
trap cleanup EXIT INT TERM HUP
export VSTACK_FALSIFY=1
# A PATH holding every system binary except jq, for the toolchain row.
for d in /usr/bin /bin; do
  for f in "$d"/*; do n=${f##*/}; [ "$n" = jq ] || ln -sf "$f" "$NOJQ/$n" 2>/dev/null; done
done

# Snapshot the working tree up front and compare against that, not against HEAD: this has to
# be runnable mid-change without reporting the operator's own edits as a failed restore.
#
# tree_fingerprint() (tests/lib-collision-guard.sh), not bare `git status --porcelain`: porcelain
# alone cannot see a directory a row's mutation creates and forgets to remove -- git does not
# track empty directories -- so a leaked directory would compose into a silent pass here instead
# of the "tree unchanged" check below catching it. Catalogued as entry eleven in
# docs/checks-that-inherit-their-answer.md; this is the same invariant, same hole, this file's
# own instance of it.
TREE_BEFORE=""
if command -v git >/dev/null && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  TREE_BEFORE=$(tree_fingerprint .)
fi

PASSED=0
SKIPPED=0; FAILED=0
pass(){ printf 'ok    check %-3s falsifiable (%s)\n' "$1" "$2"; PASSED=$((PASSED+1)); }
fail(){ printf 'FAIL  check %-3s did NOT fail when broken\n      expected label: %s\n%s\n' \
        "$1" "$2" "${3:-}"; FAILED=$((FAILED+1)); }

# save() seeds $EXP with the same pre-mutation copy it puts in $BK: until break_it() runs, "what
# this suite last wrote" and "what it will restore to" are the same file, and the fingerprint
# loop below moves $EXP forward to the post-mutation bytes right after break_it() returns.
save(){ for f in "$@"; do mkdir -p "$BK/$(dirname "$f")" "$EXP/$(dirname "$f")"; cp "$f" "$BK/$f"; cp "$f" "$EXP/$f"; done; }
# Goes through conflict_guard() first -- see the comment on it above restore_all() -- so a file
# a concurrent writer touched during this row's window is named and left alone instead of
# silently overwritten with $BK's pre-mutation copy.
restore(){ for f in "$@"; do conflict_guard "$f" && { cp "$BK/$f" "$f"; cp "$BK/$f" "$EXP/$f" 2>/dev/null; }; done; }

# Rows whose mutation creates a file instead of editing one. save()/restore() work by copying, so
# a planted file has no backup to be put back from and has to be removed by name. Leaving it
# behind fails the tree-unchanged check at the end, which is correct, and then fails every run
# after this one too, which is not.
#
# The name is assembled from the PID rather than written out, for the same reason checks 4-6
# assemble their secret probes: this file is a tracked file, so a literal basename here is a
# referrer as far as check 31 is concerned. The first draft spelled the name out, the check found
# it named in this very script, and the row reported "did NOT fail when broken" while the
# mutation was working perfectly.
# The basename is assembled from an existing, well-referenced path rather than typed, for two
# reasons. The old one: a literal name in this file is itself a referrer, which is how the first
# draft reported "did NOT fail when broken" while the mutation worked perfectly. The new one:
# since 1.15.0 check 31 matches paths instead of basenames, and this probe is what proves it --
# the assembled path collides on basename with a file named in eighteen places, so the old
# basename match called it referenced and the path match does not.
#
# Then I spelled that path out in this comment and in the changelog, and the row reported "did
# NOT fail when broken" while the mutation worked perfectly -- the same failure the paragraph
# above documents, committed by the person writing the paragraph. Describe the probe; never
# type it.
ORPHAN_PROBE="ui-gate/$(basename bin/doctor)"

creates_for(){ case "$1" in
  31)  printf '%s' "$ORPHAN_PROBE" ;;
esac }

# Files each row edits, so it can be put back byte for byte. Backing up beats `git checkout`
# here: this has to be safe to run on a dirty tree.
files_for(){ case "$1" in
  0)   printf '' ;;
  1)   printf 'claude/hooks/format.sh' ;;
  1b)  printf 'ui-gate/rules/tokens.sh' ;;
  2)   printf 'mcp/servers.json' ;;
  2b)  printf '.github/branch-protection-ruleset.json' ;;
  3)   printf 'claude/skills/unslop/SKILL.md' ;;
  3b)  printf 'claude/skills/unslop/SKILL.md' ;;
  4|5|6) printf 'README.md' ;;
  7)   printf 'claude/CLAUDE.md' ;;
  8|9|11) printf 'install.sh' ;;
  47)  printf 'claude/hooks/hooks.json' ;;
  48)  printf 'claude/inventory.json' ;;
  49)  printf 'bin/doctor' ;;
  50)  printf '.github/workflows/verify.yml' ;;
  50b) printf '.github/workflows/release.yml' ;;
  50c) printf '.github/workflows/verify.yml' ;;
  50d) printf '.claude/verify.sh' ;;
  51)  printf '.github/scripts/should-delete-candidate-tag.sh' ;;
  51b) printf '.github/workflows/release.yml' ;;
  52)  printf 'bin/claude-bg.sh' ;;
  53)  printf 'tests/inventory-contract.sh' ;;
  54)  printf '.github/workflows/release.yml' ;;
  54b) printf '.github/scripts/require-checks-green.sh' ;;
  55)  printf 'bin/claude-task.sh' ;;
  55b) printf 'bin/claude-task.sh' ;;
  55c) printf 'bin/claude-task.sh claude/hooks/dispatch-counter.sh claude/hooks/skill-mandate.sh claude/hooks/verify-gate.sh' ;;
  56)  printf 'claude/hooks/verify-gate.sh' ;;
  56b) printf 'claude/hooks/format.sh' ;;
  57)  printf 'bin/doctor' ;;
  57b) printf 'claude/statusline.sh' ;;
  57c) printf 'bin/doctor' ;;
  57d) printf 'claude/statusline.sh' ;;
  58)  printf '.github/workflows/release.yml' ;;
  58b) printf 'claude/inventory.json' ;;
  58c) printf 'claude/inventory.json' ;;
  59)  printf 'claude/hooks/goal-gate.sh' ;;
  9b)  printf 'overlay.sh' ;;
  10)  printf 'claude/agents/debugger.md' ;;
  10b) printf 'claude/agents/debugger.md' ;;
  12)  printf 'README.md' ;;
  13)  printf 'claude/.claude-plugin/plugin.json' ;;
  13b) printf 'claude/inventory.json' ;;
  13c) printf 'claude/inventory.json' ;;
  14)  printf 'claude/hooks/verify-gate.sh' ;;
  14b) printf '.claude/verify.sh' ;;
  14c) printf '.claude/verify.sh' ;;
  15)  printf 'claude/settings.json' ;;
  16)  printf 'tests/gate-falsifiability.sh' ;;
  17)  printf 'overlay.sh' ;;
  18)  printf 'claude/hooks/inject-session-context.sh' ;;
  18b) printf 'README.md' ;;
  18c) printf 'claude/hooks/inject-session-context.sh' ;;
  18d) printf 'claude/hooks/inject-session-context.sh' ;;
  19)  printf 'claude/.claude-plugin/plugin.json' ;;
  20)  printf 'claude/commands/test.md' ;;
  20c) printf 'install.sh' ;;
  20b) printf 'claude/commands/test.md' ;;
  21)  printf 'install.sh' ;;
  22)  printf 'claude/skills/swarm/SKILL.md' ;;
  23)  printf 'claude/hooks/guard-destructive.sh' ;;
  24)  printf 'claude/.claude-plugin/plugin.json' ;;
  25)  printf 'claude/hooks/failure-diagnose.sh' ;;
  26)  printf 'README.md' ;;
  27)  printf 'claude/hooks/skill-mandate.sh' ;;
  27b) printf 'claude/hooks/skill-mandate.sh' ;;
  27c) printf 'claude/hooks/skill-mandate.sh' ;;
  28)  printf 'README.md' ;;
  29)  printf 'bin/cloudflare-mcp' ;;
  29b) printf 'ui-gate/rules/browser.sh' ;;
  30)  printf 'claude/hooks/format.sh' ;;
  31)  printf '' ;;   # plants a new file rather than editing one
  32|33) printf 'claude/hooks/inject-session-context.sh' ;;
  35)  printf 'ui-gate/ui-gate.sh' ;;
  35b) printf 'bin/doctor' ;;
  35c) printf 'bin/doctor' ;;
  35d) printf 'bin/doctor' ;;
  35e) printf 'bin/doctor' ;;
  35f) printf 'bin/doctor' ;;
  35g) printf 'bin/doctor' ;;
  36)  printf 'tests/evals/lib/runlog.sh' ;;
  37)  printf 'tests/evals/optimize.sh' ;;
  38)  printf 'tests/README.md' ;;
  34)  printf 'overlay.sh' ;;
  39)  printf 'CHANGELOG.md' ;;
  40)  printf 'claude/hooks/skill-mandate.sh' ;;
  44)  printf 'install.sh' ;;
  44b|44c|44d|44e|44f) printf 'claude/hooks/dispatch-counter.sh' ;;
  44g) printf 'claude/settings.json' ;;
  45)  printf 'uninstall.sh' ;;
  46)  printf 'overlay.sh' ;;
esac }

# The label the gate must print. Matched against the FAIL lines only.
label_for(){ case "$1" in
  0)   printf 'toolchain' ;;
  1)   printf 'shell syntax' ;;
  1b)  printf 'shell syntax' ;;
  2)   printf 'json valid' ;;
  2b)  printf 'json valid' ;;
  3)   printf 'skills loadable' ;;
  3b)  printf 'skills loadable' ;;
  4)   printf 'no hardcoded home paths' ;;
  5)   printf 'no committed secrets' ;;
  6)   printf 'no infrastructure ids' ;;
  7)   printf 'referenced skills exist' ;;
  8)   printf 'settings merge program' ;;
  9)   printf 'install.sh --dry-run' ;;
  47)  printf 'plugin-lane hooks run standalone' ;;
  48)  printf 'inventory contract matches the tree' ;;
  49)  printf "doctor's CI lane answers for HEAD" ;;
  50)  printf 'every CI job is a required check' ;;
  50b) printf 'every CI job is a required check' ;;
  50c) printf 'every CI job is a required check' ;;
  50d) printf 'every CI job is a required check' ;;
  51)  printf 'release cleanup decides correctly' ;;
  51b) printf 'release cleanup decides correctly' ;;
  52)  printf 'the bin-scripts suite can actually fail' ;;
  53)  printf 'hashers work on every documented platform' ;;
  54)  printf "the release gate's inputs are supplied by the workflow" ;;
  54b) printf "the release gate's inputs are supplied by the workflow" ;;
  55)  printf 'the mtime probe returns an integer on every platform' ;;
  55b) printf 'the mtime probe returns an integer on every platform' ;;
  55c) printf 'the mtime probe returns an integer on every platform' ;;
  56)  printf 'every hook decides with a stripped environment' ;;
  56b) printf 'every hook decides with a stripped environment' ;;
  57)  printf "every reader of the trust store answers the gate's question" ;;
  57b) printf "every reader of the trust store answers the gate's question" ;;
  57c) printf "every reader of the trust store answers the gate's question" ;;
  57d) printf "every reader of the trust store answers the gate's question" ;;
  58)  printf "the release gate's wait ceiling clears the job it waits for" ;;
  58b) printf "the release gate's wait ceiling clears the job it waits for" ;;
  58c) printf "the release gate's wait ceiling clears the job it waits for" ;;
  59)  printf "the goal gate blocks on an open goal and only on an open goal" ;;
  9b)  printf 'overlay merge path' ;;
  10)  printf 'agents + commands loadable' ;;
  10b) printf 'agents + commands loadable' ;;
  11)  printf 'hook wiring' ;;
  12)  printf 'doc counts match tree' ;;
  13)  printf 'plugin manifest versions' ;;
  13b) printf 'plugin manifest versions' ;;
  13c) printf 'plugin manifest versions' ;;
  14)  printf 'stop-hook gate blocks' ;;
  14b) printf 'the gate refuses a tree under mutation' ;;
  14c) printf 'the gate refuses a tree under mutation' ;;
  15)  printf 'skillOverrides' ;;
  16)  printf 'falsifiability coverage' ;;
  17)  printf 'overlay ships project keys only' ;;
  18)  printf 'injected context bounded' ;;
  18b) printf 'injected context bounded' ;;
  18c) printf 'injected context bounded' ;;
  18d) printf 'injected context bounded' ;;
  19)  printf 'plugin manifests valid' ;;
  20)  printf 'referenced install paths exist' ;;
  20b) printf 'referenced install paths exist' ;;
  20c) printf 'referenced install paths exist' ;;
  21)  printf 'RETIRED names only retired keys' ;;
  22)  printf 'skills disclose what they do not ship' ;;
  23)  printf 'destructive guard decides correctly' ;;
  24)  printf 'declared version matches what installs' ;;
  25)  printf 'failure tail redacts credentials' ;;
  26)  printf 'documented platforms match CI' ;;
  27)  printf 'skill mandate decides correctly' ;;
  27b) printf 'skill mandate decides correctly' ;;
  27c) printf 'skill mandate decides correctly' ;;
  28)  printf 'every doc is reachable' ;;
  29)  printf 'shellcheck clean' ;;
  29b) printf 'shellcheck clean' ;;
  30)  printf 'shellcheck suppressions carry a reason' ;;
  31)  printf 'every shipped file has a referrer' ;;
  32)  printf 'grill trigger decides correctly' ;;
  33)  printf 'project overlay stands down when the user-scope hook is live' ;;
  34)  printf 'the policy document reaches a session exactly once' ;;
  35)  printf 'gates refuse a green on nothing measured' ;;
  35b) printf 'gates refuse a green on nothing measured' ;;
  35c) printf 'gates refuse a green on nothing measured' ;;
  35d) printf 'gates refuse a green on nothing measured' ;;
  35e) printf 'gates refuse a green on nothing measured' ;;
  35f) printf 'gates refuse a green on nothing measured' ;;
  35g) printf 'gates refuse a green on nothing measured' ;;
  36)  printf 'run logs are opened append-safe' ;;
  37)  printf 'optimiser decides correctly' ;;
  38)  printf 'every repository path named in prose exists' ;;
  39)  printf 'CHANGELOG.md structure' ;;
  40)  printf 'latched session still logs a delegation-drift row' ;;
  44)  printf 'dispatch counter join, both directions' ;;
  44b) printf 'dispatch counter join, both directions' ;;
  44c) printf 'dispatch counter join, both directions' ;;
  44d) printf 'dispatch counter join, both directions' ;;
  44e) printf 'dispatch counter join, both directions' ;;
  44f) printf 'dispatch counter join, both directions' ;;
  44g) printf 'dispatch counter join, both directions' ;;
  45)  printf 'uninstall keeps foreign settings, drops its own' ;;
  46)  printf 'no accidental agents under claude/agents' ;;
esac }

# Break exactly what the check watches, and nothing else. Surgical matters: a mutation that
# trips four checks proves far less than one that trips the intended one.
break_it(){ case "$1" in
  1)  # The shebang lane of the file selector: format.sh names bash on its first line.
      # This row and 1b were one row until 2026-08-27. Two mutations under one oracle means
      # either alone turns the check red and carries the row, so the other lane stays exactly as
      # unproven as it was before anyone widened anything -- the defect the widening was for.
      printf '\nif [ -z\n' >> claude/hooks/format.sh ;;

  1b) # The directive lane: ui-gate/rules/tokens.sh has no shebang and no .sh dispatch of its
      # own, only a `# shellcheck shell=` line, and for four versions nothing in this gate
      # parsed it.
      printf '\nif [ -z\n' >> ui-gate/rules/tokens.sh ;;
  2)  printf '{' >> mcp/servers.json ;;

  2b) # A file the hardcoded five-path list never covered. Until 2026-08-27 check 2's label said
      # every JSON file and its body named five, so a malformed protection ruleset, a broken
      # brand.schema.json or a corrupt ground-truth fixture all shipped green.
      printf '{' >> .github/branch-protection-ruleset.json ;;
  3)  # a description past the 200-char listing cap, which silently stops the skill triggering
      awk 'BEGIN{d="x"; for(i=0;i<209;i++) d=d "y"}
           /^description:/{print "description: " d; next} {print}' \
          claude/skills/unslop/SKILL.md > /tmp/fx.$$ && mv /tmp/fx.$$ claude/skills/unslop/SKILL.md ;;

  3b) # The closing --- of the frontmatter, deleted. Every key stays where it was; the block just
      # never ends, so the loader reads no frontmatter at all and the skill stops being listed.
      awk 'BEGIN{c=0} /^---$/{c++; if(c==2) next} {print}' claude/skills/unslop/SKILL.md \
        > /tmp/fx3b.$$ && mv /tmp/fx3b.$$ claude/skills/unslop/SKILL.md ;;
  # Assembled at runtime, never written out whole. Checks 4-6 scan every tracked file, and
  # this is a tracked file: a literal probe here is a real hit on the repo itself, which is
  # how these three rows turned the gate red the moment the suite was committed.
  4)  printf '\npath /Users/%s/notes\n' 'realperson' >> README.md ;;
  5)  printf '\napi%s=AbCdEf0123456789AbCdEf0123456789\n' '_key' >> README.md ;;
  6)  printf '\nproject prj%sA1b2C3d4E5f6G7h8\n' '_' >> README.md ;;
  7)  printf '\nRoute this to the totally-invented-skill when it matters.\n' >> claude/CLAUDE.md ;;
  8)  sed -i.t 's/as \$portable/as $portable @@@/' install.sh && rm -f install.sh.t ;;
  9)  # Early, not appended: the dry-run path exits 0 partway down install.sh, so anything
      # added at the end is unreachable and the row would silently prove nothing.
      sed -i.t '1a\
exit 7
' install.sh && rm -f install.sh.t ;;
  # `exit 4` only proved the check notices overlay crashing. The assertions that matter are the
  # merge ones, so mutate the merge: go back to the wholesale array replace this check exists to
  # catch, and the target repo's own Stop hook disappears.
  # Put verify-gate.sh back in the plugin lane. It tells the operator to run `vstack trust`,
  # a command this lane never installs, which is exactly what shipped for three releases while
  # README said the lane installed no hooks at all.
  47) jq '.hooks.Stop[0].hooks = ([{type:"command",shell:"bash",command:"\"${CLAUDE_PLUGIN_ROOT}/hooks/verify-gate.sh\""}] + .hooks.Stop[0].hooks)' \
        claude/hooks/hooks.json > /tmp/c47row.$$ && cat /tmp/c47row.$$ > claude/hooks/hooks.json && rm -f /tmp/c47row.$$ ;;
  48) # An unrecognised contract_version: tests/inventory-contract.sh must fail loudly rather
      # than silently reading fields whose meaning may have changed under it.
      jq '.contract_version = 999' claude/inventory.json > /tmp/c48row.$$ \
        && cat /tmp/c48row.$$ > claude/inventory.json && rm -f /tmp/c48row.$$ ;;
  49) # The commit filter, removed. Every run gh reports comes back regardless of which commit
      # it belongs to, which is precisely the shipped defect: `--branch main --limit 1` answered
      # for whatever was newest on the branch, so an older commit's green spoke for the one you
      # were standing on. Check 49's first case plants a success for a foreign SHA and requires
      # doctor NOT to call it green; with the filter gone, it does.
      sed -i.t 's/select(.headSha == \$s)/select(true)/' bin/doctor && rm -f bin/doctor.t ;;

  50) # A CI lane whose verdict no gate reads. This is the shape that shipped: install-macos was
      # added to verify.yml, went red on its first run, and nothing in the release path asked it
      # anything, because REQUIRED_CHECKS is a hand-maintained list beside the workflow.
      printf '\n  install-freebsd:\n    runs-on: ubuntu-latest\n    steps:\n      - run: "true"\n' >> .github/workflows/verify.yml ;;

  50d) # The guard that stops the join executor running a non-join's script. Without it check 50
      # extracted and ran the first run: block of every required job, and install-macos's is
      # `./.claude/verify.sh` -- the gate running itself, once per candidate job, on every
      # runner where RUNNER_TEMP is set. It hung seven CI shards for 78 minutes. The mutation
      # narrows the guard rather than removing it: a removed guard would recurse here too, and a
      # falsifiability row must make the gate go red, not make it never return.
      perl -0pi -e "s/\*'needs\.'\*'\.result'\*\)/*'NO_SUCH_TOKEN_IN_ANY_SCRIPT'*)/" \
        .claude/verify.sh ;;

  50c) # The join stops acting on a shard's verdict while still listing it in needs:. The
      # falsify matrix cannot be a required check by name -- its check-runs are `falsify (0,
      # ...)`, so a required context spelled `falsify` never matches and the release deadlocks --
      # so `verify` fans it in instead. That is only worth anything if the join actually exits
      # non-zero on it, which check 50 proves by running the join's own script with this job's
      # result set to failure. Deleting the assertion leaves needs: intact and the reference
      # gone, which is what a careless edit to that loop looks like.
      perl -0pi -e 's/^\s*"falsify:\$\{\{ needs\.falsify\.result \}\}" \\\n//m' \
        .github/workflows/verify.yml ;;

  50b) # The other direction: a required name with no job behind it. require-checks-green.sh
      # reports MISSING for it on every commit, so the release gate sits UNDECIDED forever --
      # the deadlock this session fixed from the other end, reachable again by a typo in a list.
      sed -i.t 's/^  REQUIRED_CHECKS: \(.*\)$/  REQUIRED_CHECKS: \1 install-plan9/' .github/workflows/release.yml \
        && rm -f .github/workflows/release.yml.t ;;


  51) # The production defect itself, restored. Delete the carve-out that keeps a tag alive
      # while the gate is undecided, and the decider goes back to deleting on "not yet" -- the
      # deadlock of 2026-08-27, where verify could not go green until the tag was on origin and
      # the tag was deleted before verify could finish.
      sed -i.t 's/if \[ "$gate" = undecided \]; then/if false; then/' \
        .github/scripts/should-delete-candidate-tag.sh && rm -f .github/scripts/should-delete-candidate-tag.sh.t ;;

  51b) # The join. A tested decider the workflow does not call is a test of nothing. Point the
      # cleanup job at a script that does not exist and check 51's coupling assertion must
      # notice, because the truth table alone would still pass.
      sed -i.t 's|should-delete-candidate-tag\.sh|should-delete-candidate-tag-DISCONNECTED.sh|g' \
        .github/workflows/release.yml && rm -f .github/workflows/release.yml.t ;;

  52) # Delete the no-args guard the bg-args case is about. Check 52's first direction requires
      # tests/bin-scripts.sh to pass against the tree as it stands, so this turns it red -- and
      # it turns the shipped suite red too, which is the point: the guard is real behaviour.
      sed -i.t 's/^if \[ $# -eq 0 \]; then/if false; then/' bin/claude-bg.sh \
        && rm -f bin/claude-bg.sh.t ;;

  53) # Put the platform-specific call back. Strip the sha256sum branch out of the digest's
      # fallback and the file names only `shasum` again -- which is exactly what it looked like
      # when it computed an empty payload digest on Alpine.
      sed -i.t '/sha256sum/d' tests/inventory-contract.sh && rm -f tests/inventory-contract.sh.t ;;

  54) # Unwire the input. The gate keeps reading CANDIDATE_CREATED_AT and its own test keeps
      # passing, because that test supplies the variable itself -- which is the whole reason
      # check 54 exists. Renaming it in the workflow is precisely how this would rot: nothing
      # errors, the export just stops reaching the reader, and the staleness rule silently
      # turns off while every suite stays green.
      sed -i.t 's/CANDIDATE_CREATED_AT/RENAMED_AWAY/g' .github/workflows/release.yml \
        && rm -f .github/workflows/release.yml.t ;;

  54b) # The other direction: break the extractor rather than the wiring. Switching the gate's
      # defaults from ${VAR:-x} to ${VAR-x} changes nothing about how it runs and empties the
      # derived census, so the check would have nothing left to compare and must say so instead
      # of printing ok on a list of length zero.
      sed -i.t 's/=\${\([A-Z][A-Z0-9_]*\):-/="${\1-/; s/:-0}$/-0}"/' .github/scripts/require-checks-green.sh \
        && rm -f .github/scripts/require-checks-green.sh.t ;;

  55) # The shipped defect itself, put back INSIDE mtime_of() so the census still finds the file
      # and only the execution lane can notice. This is the line that ran in four files until
      # 1.49.0: it exits 0 on GNU and BusyBox with a five-line paragraph about the mount, so the
      # `||` never falls through and the caller compares a paragraph against an integer.
      perl -0pi -e 's/mtime_of\(\) \{.*?\n\}/mtime_of() {\n  stat -f %m "\$1" 2>\/dev\/null || stat -c %Y "\$1" 2>\/dev\/null || echo 0\n}/s' \
        bin/claude-task.sh ;;

  55b) # The other way this rots: a fifth copy typed inline instead of calling the function. The
      # function stays correct and keeps passing all three stubs, so only the count of stat calls
      # inside versus outside it can tell. Adding a probe by hand is exactly how the first four
      # got there.
      printf '%s\n' 'stale=$(stat -f %m "$0" 2>/dev/null || stat -c %Y "$0" 2>/dev/null || echo 0)' \
        >> bin/claude-task.sh ;;

  55c) # Empty the census. Rename the tool in every file that calls it and the loop above has
      # nothing left to execute -- three platform stubs applied zero times, which is a green
      # about nothing unless the check refuses on a census of length zero.
      for _c55f in bin/claude-task.sh claude/hooks/dispatch-counter.sh \
                   claude/hooks/skill-mandate.sh claude/hooks/verify-gate.sh; do
        sed -i.t -e 's/stat -c %Y/stat -Q %Z/g' -e 's/stat -f %m/stat -Q %Z/g' "$_c55f"
        rm -f "$_c55f.t"
      done ;;

  56) # Put the bare expansion back in the Stop hook's trust-store lookup. Under `set -u` with
      # HOME absent this aborts on line 34, before the gate has allowed or blocked anything --
      # the runtime gets a shell error where a decision belongs. Every other hook keeps working,
      # and so does this one on any machine that has a HOME, which is why nothing noticed.
      sed -i.t 's|"${HOME:-}/.config/agents/verify-trust"|"$HOME/.config/agents/verify-trust"|' \
        claude/hooks/verify-gate.sh && rm -f claude/hooks/verify-gate.sh.t ;;

  56b) # A hook that was never broken, broken. Proves the census actually runs every file rather
      # than the two that happened to be wrong when the check was written: format.sh has no HOME
      # problem at all, so if this row stays green the loop is not reaching it.
      # Anchored on the exact line, not on `0,/^dir=/`: BSD sed rejects the 0 address, so that
      # form matched nothing on macOS and the row reported "did not fail" against a mutation that
      # had never landed. ${x?} rather than a bare $x because format.sh does not set -u.
      sed -i.t 's|^dir=$(dirname "$f")$|dir=${UNSET_ON_PURPOSE?}|' \
        claude/hooks/format.sh && rm -f claude/hooks/format.sh.t ;;

  57) # Doctor back to matching the trust record as a substring. A store holding only
      # <path>/verify.sh.orig then satisfies a query for <path>/verify.sh, so doctor reports
      # trusted on a checkout whose Stop gate refuses to run. The two disagree and only the
      # gate's answer is the one that happens.
      sed -i.t 's|grep -qxF "$_th  $_tvp"|grep -qF "$_th  $_tvp"|' \
        bin/doctor && rm -f bin/doctor.t ;;

  57b) # The statusline back to asking for the path alone. Every scenario then renders shield,
      # including a verify.sh edited after `vstack trust` ran, which is the one case the store
      # exists to catch. This row is here because that green was on screen every turn for
      # months and no check looked at it.
      sed -i.t 's|grep -qxF "$_th  $_tv" "$_tr"|grep -qF "$_tv" "$_tr"|' \
        claude/statusline.sh && rm -f claude/statusline.sh.t ;;

  57c) # Doctor hashing the entry point and stopping there. verify.sh still matches, so it
      # reports trusted, while the gate re-hashes the companion scripts `vstack trust` recorded
      # and refuses. Rows 57 and 57b both leave this green: they mutate how the verify.sh line is
      # matched, and this defect is about the lines below it never being read at all.
      sed -i.t 's|if \[ -n "$_tmm" \]; then|if false; then|' \
        bin/doctor && rm -f bin/doctor.t ;;

  57d) # The same omission in the statusline, where it renders every turn.
      sed -i.t 's|\[ -z "$_tm" \] && _tok=1|_tok=1|' \
        claude/statusline.sh && rm -f claude/statusline.sh.t ;;

  58) # Cut the wait ceiling under the floor check 58 derives from the tree. Matched on the key
      # and not on the current value: a row pinned to "3600" would stop mutating anything the
      # next time the number is re-derived, and report the check unfalsifiable while proving
      # nothing about it.
      sed -i.t 's|\(REQUIRE_CHECKS_WAIT_SECONDS: \)"[0-9]*"|\1"600"|' \
        .github/workflows/release.yml && rm -f .github/workflows/release.yml.t ;;

  58b) # Raise the RECORDED per-row measurement past what the ceiling can absorb. Check 58 does
      # not hardcode a per-row cost; it scales this number by the gate's size. If the recorded
      # measurement were decorative -- present, cited in a comment, read by nothing -- this
      # mutation would change no verdict at all, which is the exact failure mode check 58 exists
      # to prevent, one level down inside the checker.
      sed -i.t 's|\("seconds_per_row": \)[0-9]*|\1650|' \
        claude/inventory.json && rm -f claude/inventory.json.t ;;

  59) # Invert the gate's one decision: block when nothing is pending, go silent when something
      # is. That flips BOTH directions at once -- the repo that must block goes quiet and the
      # three that must stay quiet start blocking -- so a check exercising only one direction
      # could not report this green. Anchored on the predicate, not on any message, so rewording
      # the block reason cannot quietly disarm the row.
      sed -i.t 's/^\[ -n "\$pending" \] || exit 0$/[ -z "$pending" ] || exit 0/' claude/hooks/goal-gate.sh \
        && rm -f claude/hooks/goal-gate.sh.t ;;
  58c) # Remove the check count the measurement was taken at. Without it the recorded cost cannot
      # be scaled to this gate's size, so it would silently stay frozen at the size it was
      # measured on, which is how the constant it replaced went stale in the first place. A
      # missing anchor has to be a failure and not a skip.
      sed -i.t '/"checks_at_measurement":/d' \
        claude/inventory.json && rm -f claude/inventory.json.t ;;

  9b) perl -0pi -e 's{\.hooks = \(}{.hooks = (\$ship.hooks) | .DEADCODE = (}' overlay.sh ;;
  10) sed -i.t '/^description:/d' claude/agents/debugger.md && rm -f claude/agents/debugger.md.t ;;

  10b) # The frontmatter block itself, not its contents. Both keys stay present and correct; what
      # goes is the --- that opens the block, so the loader sees a plain markdown file. Checks 3
      # and 10 grepped for a line starting with name:/description: anywhere in the file, so this
      # exact shape passed them both until fm_block() replaced the grep on 2026-08-27.
      sed -i.t '1{/^---$/d;}' claude/agents/debugger.md && rm -f claude/agents/debugger.md.t ;;
  11) # drop the PostToolUse key while PostToolUseFailure stays: the exact shape the old
      # substring grep could not see. Indentation-tolerant on purpose — this row silently
      # stopped mutating anything when the merge program was reindented, and a mutation that
      # lands nowhere reports the check as unfalsifiable while proving nothing about it.
      perl -0pi -e 's/^[ ]*PostToolUse: \[\n.*?\n.*?\n//m' install.sh ;;
  12) sed -i.t 's/| Commands | [0-9]* |/| Commands | 99 |/' README.md && rm -f README.md.t ;;
  13b) # The lane that was live and unwatched. inventory.json's product.version names the two
      # manifests as its version_source and was 1.46.0 while they said 1.48.0, wrong across two
      # shipped releases, because nothing compared the number against the files it cites.
      sed -i.t 's/"version": "[0-9][^"]*"/"version": "0.0.1"/' claude/inventory.json \
        && rm -f claude/inventory.json.t ;;

  13c) # Empty the derived census. version_source is what the check builds its file list from, so
      # emptying it leaves nothing to compare -- which must be refused, not reported as ok over a
      # list of length zero.
      perl -0pi -e 's/"version_source":\s*\[[^\]]*\]/"version_source": []/' claude/inventory.json ;;

  13) sed -i.t 's/"version": "[^"]*"/"version": "9.9.9"/' claude/.claude-plugin/plugin.json \
        && rm -f claude/.claude-plugin/plugin.json.t ;;
  14) sed -i.t '1a\
exit 0
' claude/hooks/verify-gate.sh && rm -f claude/hooks/verify-gate.sh.t ;;
  15) sed -i.t 's/"skillOverrides": {/"skillOverrides": {\n    "someplugin:do": "off",/' \
        claude/settings.json && rm -f claude/settings.json.t ;;
  18b) # Move the anchor the published-figure comparison keys on, without touching the figures
      # themselves. This is what cc76ba8 did by accident, and for eleven commits the check went on
      # printing ok while comparing nothing. The row exists because the fix is an `else`, and an
      # `else` nobody has seen fire is indistinguishable from the missing one it replaced.
      sed -i.t 's| KB full / ~| KB total / ~|' README.md && rm -f README.md.t ;;

  18c) # The floor lane. Check 18's three assertions were all upper caps, so a hook emitting
      # nothing satisfied every one and printed "ok injected context bounded (digest 0 B,
      # baseline 0 B)". The floor that fixed that had no mutation behind it -- it was proven by
      # a hand-run, which by this repository's own standard is not evidence. Stub the hook to
      # say nothing at all and the floors must name it.
      printf '#!/usr/bin/env bash\nexit 0\n' > claude/hooks/inject-session-context.sh ;;
  14b) # Honour a stale lock. A killed run leaves its lock behind, and a gate that refuses on a
      # dead pid is wedged for everyone until someone deletes a file they do not know about --
      # the failure mode that makes people delete locks reflexively and defeat the whole thing.
      #
      # Anchored on the liveness test as a whole, not on how the pid is read out of the lock
      # file. The original pattern spelled `$(cat "$_lk" ...)` literally and stopped matching
      # the day the lock grew a second line and the reader became `head -1` -- one refactor,
      # one silently disarmed row, caught only by this suite's own no-op detector. `kill -0`
      # through the end of the condition is the decision; the pid's spelling is not.
      sed -i.t 's/ && kill -0 .*2>\/dev\/null;/;/' \
        .claude/verify.sh && rm -f .claude/verify.sh.t ;;

  14c) # Take away the refusal's terminator. The exit code stays 2 and the REFUSED line stays
      # first, so every assertion this check had before 2026-08-27 still passes -- and the output
      # now ends on "Wait for it to finish", which is what a reader tailing the last lines, or
      # counting FAIL lines, will call green. That reading is not hypothetical; it is how this
      # row came to exist.
      sed -i.t "s/^    printf 'NOT RUN  (refused;/    : 'NOT RUN  (refused;/" \
        .claude/verify.sh && rm -f .claude/verify.sh.t ;;
  16) sed -i.t 's/^CHECKS="0 /CHECKS="/' tests/gate-falsifiability.sh \
        && rm -f tests/gate-falsifiability.sh.t ;;
  17) # Restore the deletion overlay.sh used to do: strip every destination key that is not on
      # vstack's project allowlist. That silently destroyed target-owned enabledPlugins, theme,
      # and forceLoginMethod, and the old version of this row -- appending theme to
      # settings.project-keys -- could not see it, because the check it armed was asserting the
      # deletion as correct. The row now mutates the behaviour, not the allowlist.
      perl -0pi -e 's/\| \(\$dest \* \$ship\)/| (\$dest * \$ship)\n    | delpaths([(keys - \$A)[] | [.]])/' overlay.sh ;;
  18) # The cap lane: pad the per-prompt digest past its 512 byte ceiling.
      perl -0pi -e 's/(DELEGATE: mechanical)/("padding " x 60) . $1/e' claude/hooks/inject-session-context.sh ;;
  18d) # The path-invariance lane. Check 18 normalizes every environment-dependent string out of
      # the WORKSPACE CONVENTIONS block before capping or publishing it -- $root twice, $branch
      # once, $base three times. Splice $base a fourth time and the correction subtracts less
      # than the hook added, so two checkouts on differently-named default branches stop
      # agreeing. This is the lane that was missing when the published figure was compared
      # against a raw count: the check passed on the author's directory and failed in a clone.
      perl -0pi -e 's/Open PRs against \$base\./Open PRs against \$base (see \$base)./' claude/hooks/inject-session-context.sh ;;
  19) # A schema type violation, which is what check 19 is actually for.
      #
      # This used to rename "version" to "verzion", and that never tested check 19 directly:
      # it tripped check 13 (the two manifests no longer agreed on a version), and check 19
      # only went red as a side effect of the marketplace manifest complaining about its
      # plugin. Whether that side effect happened at all depended on the CLI version, so the
      # row passed on a pinned local CLI and failed on CI's freshly installed one, which is
      # a falsifiability suite reporting on something other than the check it names.
      #
      # keywords-as-a-string is a plain schema error: --strict rejects it, check 13 does not
      # care because the version is untouched, and no CLI is going to start accepting it.
      jq '.keywords = "not-an-array"' claude/.claude-plugin/plugin.json > /tmp/fx19.$$ \
        && mv /tmp/fx19.$$ claude/.claude-plugin/plugin.json ;;
  20) # a command telling the model to run something no lane ever installs — exactly the
      # shape of the /bootstrap defect this check was written for
      printf '\nRun `~/.claude/scripts/does-not-exist.sh` first.\n' >> claude/commands/test.md ;;

  20c) # install_generated()'s floor: the literal path install.sh must still contain for
      # ~/.config/agents/vstack-installed to stay a legitimate exemption rather than a stale
      # allow-list entry. Renaming the string OWNED_PATHS assigns is a defect no prose mutation
      # can reach. This lived inside row 20 until 2026-08-27, with a comment arguing that two
      # files and two non-overlapping patterns made it "genuinely two lanes under one label".
      # They are two lanes; one label is the problem. Either mutation alone satisfied the row's
      # single oracle, so neither lane was ever proven on its own.
      sed -i.t 's#\$HOME/\.config/agents/vstack-installed#$HOME/.config/agents/renamed-installed-record#' install.sh \
        && rm -f install.sh.t ;;
  20b) # The same promise, one namespace over. `/push` shipped `~/.100xprompt/hooks/pre-push.sh`
      # -- another tool's template path, referenced by a command this repo installs -- and the
      # extractor could not see it, because it matched only ~/.claude, ~/.config/agents and
      # ~/.conductor. Row 20 mutates inside a blessed prefix and so proves only the half that
      # already worked. This row is the half that did not: a foreign namespace must be declared
      # foreign, with a reason, rather than pass by never being matched at all.
      printf '\nRun `~/.someothertool/hooks/pre-push.sh` first.\n' >> claude/commands/test.md ;;
  21) # the exact list that was nearly shipped: Claude Code's own sandbox setting, named as if
      # it were vstack's to delete
      sed -i.t "s/^RETIRED='\[\]'/RETIRED='[\"sandbox\"]'/" install.sh && rm -f install.sh.t ;;
  22) # a skill telling the model to run a helper the port does not vendor, with no notice —
      # the shape that shipped in impeccable and in brainstorming's visual companion
      printf '\n```bash\nnode scripts/not-vendored-probe.mjs --run\n```\n' >> claude/skills/swarm/SKILL.md ;;
  23) # the failure that matters: a guard that stops denying. Make the deny tier unreachable
      # and the ask/allow tiers keep working, so only a test of the decisions notices.
      #
      # Anchored on the decision itself -- every `emit deny` call site, function and inline
      # duplicate alike -- rather than on a `$SIMPLE` gate variable that the file no longer has.
      # d1b96bd split the old single simple/compound branch into `_check_deny_segment()` plus a
      # second, duplicated inline block for non-compound commands, and the old `$SIMPLE` pattern
      # stopped matching either one: the mutation landed nowhere and the row reported "did NOT
      # fail when broken" while proving nothing. `: emit deny ...` is the colon builtin no-opping
      # the call (ignores its args, returns 0), so every deny case arm falls through to the
      # ask/allow tiers below it exactly as if the deny tier were absent, in both the function and
      # its inline duplicate, in one edit. Anchored on leading whitespace so the prose comment
      # above line 81 ("If so, emit deny immediately.") is not also mangled.
      #
      # Widens to the permission-mode lane for free, not by a second edit: `emit_unattended_ask`'s
      # `bypassPermissions)` case arm (the g_pm assertions added alongside docs/guard-
      # enforcement-gap.md's fix) is itself a call to `emit deny`, so this one sed also no-ops it.
      # Confirmed empirically rather than assumed -- run against a tree with the g_pm rows landed,
      # this row's single mutation prints both `'rm -rf /' -> ask, expected deny` (the pre-
      # existing tier) and `'git stash' under permission_mode=bypassPermissions -> allow,
      # expected deny` (the new one) in the same FAIL block, from the one sed above. A second,
      # narrower sed targeting only the bypassPermissions arm was tried and rejected: applied
      # after this one it matches nothing (the line already reads `: emit deny`), and applied
      # before it, this blanket pattern immediately reprocesses the same line anyway -- there is
      # no ordering in which both add independent signal, only one in which the second is inert.
      sed -i.t 's/^\( *\)emit deny /\1: emit deny /' claude/hooks/guard-destructive.sh \
        && rm -f claude/hooks/guard-destructive.sh.t ;;
  24) # claim an already-tagged version while the payload has moved on — the exact state that
      # ships three lanes three different trees under one label
      sed -i.t 's/"version": "[0-9.]*"/"version": "1.4.0"/' claude/.claude-plugin/plugin.json \
        && rm -f claude/.claude-plugin/plugin.json.t ;;
  29) # An unquoted expansion, which is the single most common way a shell script breaks on
      # somebody else's machine: a path with a space in it silently becomes two arguments.
      #
      # Broken in bin/cloudflare-mcp on purpose. It is a #!/bin/sh script with no .sh suffix, so
      # the old `git ls-files '*.sh' bin/doctor bin/vstack` selector never linted it and this
      # exact mutation left the check green. Mutating a file the selector already covered would
      # prove the linter runs; mutating this one proves it runs over everything.
      # This row's own comment already said "one mutation per lane, or half the selector stays
      # unproven", and then ran both lanes in one row, which is the same thing as not splitting
      # them: one oracle, either mutation carries it. Split on 2026-08-27; 29b is the other lane.
      printf '\nsc_probe=$HOME/some path\nls $sc_probe >/dev/null 2>&1 || true\n' >> bin/cloudflare-mcp ;;

  29b) # The directive-only lane: a sourced fragment with no shebang at all, which the shebang
      # scan could not see until sh_files() folded four copies of the selector into one.
      printf '\nsc_probe=$HOME/some path\nls $sc_probe >/dev/null 2>&1 || true\n' >> ui-gate/rules/browser.sh ;;
  30) # A bare disable, no reason on the line and none above it. This is the shape bootstrap.sh
      # carried for several versions while check 29's own header claimed the rule was kept.
      printf '\n# shellcheck disable=SC2086\nsup_probe=$HOME/x\nls $sup_probe >/dev/null 2>&1 || true\n' \
        >> claude/hooks/format.sh ;;
  31) # A file nothing points at. It has to be tracked to be visible to the check, so it is added
      # to the index and removed again after the row -- the same shape as every other row, except
      # the mutation creates rather than edits, so creates_for() cleans up instead of restore().
      printf '#!/usr/bin/env bash\necho probe\n' > "$ORPHAN_PROBE"
      chmod +x "$ORPHAN_PROBE"
      git add -f "$ORPHAN_PROBE" >/dev/null 2>&1 ;;
  32) # Make it fire on everything. A trigger that always fires is the failure this check exists
      # for, and it is the one an edit reaches for first -- lowering a threshold looks harmless.
      #
      # sed on the default, not perl on the whole condition. \Q quotes metacharacters but does not
      # stop interpolation, so perl read $_n as one of its own variables, substituted empty, and
      # the pattern matched nothing -- a mutation that lands nowhere reports the check as
      # unfalsifiable while proving nothing about it.
      sed -i.t 's/VSTACK_GRILL_CHARS:-320/VSTACK_GRILL_CHARS:-0/' \
        claude/hooks/inject-session-context.sh && rm -f claude/hooks/inject-session-context.sh.t ;;
  33) # Turn the suppression off by default, which is precisely the state the tree was in before
      # it existed: the project copy and the user-scope copy both injecting, everything twice.
      # Flipping the default rather than deleting the block keeps the mutation to one token, so a
      # red row points at the suppression and not at a syntax error.
      sed -i.t 's/VSTACK_DUPE_SUPPRESS:-1/VSTACK_DUPE_SUPPRESS:-0/' \
        claude/hooks/inject-session-context.sh && rm -f claude/hooks/inject-session-context.sh.t ;;
  34) # Stop the overlay clearing a .claude/CLAUDE.md it finds, which is the pre-v1.13.3 state:
      # the policy sitting in a project-memory path beside the identical ~/.claude/CLAUDE.md.
      #
      # The obvious mutation -- add a second `cp` that writes .claude/CLAUDE.md -- is the one this
      # row shipped with, and it proved nothing: the convergence `rm -f` five lines below deleted
      # the planted file before the check ever looked, so the gate stayed green and the row
      # reported a falsifiability it had not demonstrated. Delete the removal instead. The check
      # plants a stale .claude/CLAUDE.md before overlaying, so this is exactly the defect it
      # watches for, and nothing downstream can undo it.
      sed -i.t '/^  rm -f "\$DEST\/\.claude\/CLAUDE\.md"$/d' \
        overlay.sh && rm -f overlay.sh.t ;;

  35) # Put the floor back the way it read for four versions: an accounting rule satisfied at
      # zero. `-lt 0` can never be true, so the OK below fires again over a target where every
      # rule skipped. One comparison, which is all it took the first time.
      sed -i.t 's/\[ "\$RAN" -eq 0 \]/[ "$RAN" -lt 0 ]/' ui-gate/ui-gate.sh \
        && rm -f ui-gate/ui-gate.sh.t ;;

  35b) # The same check has a second subject, and row 35 only ever mutated the first. Neuter
      # doctor's per-family floor so a family that matched nothing is accepted: -ge 0 is true
      # for every count, including zero. CLAUDE.md and statusline.sh are compared
      # unconditionally, so COMPARED stays above zero and the total-count floor below cannot
      # catch it -- the empty-family stub then prints "no drift" over four families that
      # compared nothing, which is the state bin/doctor shipped in before 1.14.0.
      sed -i.t 's/\[ "\$2" -gt 0 \] && return 0/[ "$2" -ge 0 ] \&\& return 0/' bin/doctor \
        && rm -f bin/doctor.t ;;

  35c) # The mcp family's comparison, and nothing else. The mirrored stub cannot catch this on its
      # own -- five other families satisfy it either way -- so this is the row that proves the
      # probe added for a5c4c05's sixth family is measuring that family and not its neighbours.
      # Verified to trip exactly two assertion lines and leave the rest of the check standing.
      sed -i.t 's/if \[ "\$h" != "\$w" \]; then/if false; then/' bin/doctor \
        && rm -f bin/doctor.t ;;

  35d) # Take away the verdict WORD while leaving the exit status. A negative probe that only
      # asserts the absence of "no drift" passes a doctor that says nothing at all, which is the
      # asymmetry this check carried until the ui-gate half's positive marker was mirrored here.
      sed -i.t 's/echo "DRIFT ✖"/:/g' bin/doctor \
        && rm -f bin/doctor.t ;;

  35e) # Take away the exit STATUS: the drift branch is never taken, so a caller scripting on
      # `doctor --drift` reads success over a tree it just described as broken.
      sed -i.t 's/if \[ "\$DRIFT" = 1 \]; then/if [ "$DRIFT" = 9 ]; then/' bin/doctor \
        && rm -f bin/doctor.t ;;

  35f) # The reverse-direction lane: a server vstack installed and no longer ships stays
      # registered forever. Skip the ownership record entirely and the lane silently reports
      # nothing, which is indistinguishable from a clean machine.
      sed -i.t 's|if \[ -f "\$_owned" \]; then|if false; then|' bin/doctor \
        && rm -f bin/doctor.t ;;

  35g) # The still-shipped guard. Drop it and every owned key reads as stale, including the ones
      # this repo ships right now -- doctor would tell you to remove the servers it just
      # installed. The third assertion in check 35's reverse-lane probe is what catches it.
      #
      # The probe's fourth assertion (a user's own server is never reported) has no row of its
      # own, deliberately: the loop reads the ownership record, so breaking it means changing
      # what the loop iterates, which is a rewrite rather than a defect shape a mutation can
      # express. Said here rather than left for someone to notice the row count.
      sed -i.t 's#>/dev/null 2>&1 && continue#>/dev/null 2>\&1 \&\& :#' bin/doctor \
        && rm -f bin/doctor.t ;;

  36) # Restore the truncation: treat every log as new, which is the line that shipped three
      # times and threw away the previous arm each time.
      sed -i.t 's/if \[ -s "\$f" \]; then/if false; then/' tests/evals/lib/runlog.sh \
        && rm -f tests/evals/lib/runlog.sh.t ;;

  37) # Put back the zero that reads as a finding. A run whose fixtures planted nothing scores
      # f1 0.0000 instead of saying so, delta goes hugely negative, and the loop reverts a good
      # change for being "measurably worse".
      sed -i.t 's/INVALID zero planted defects[^"]*/0 0 0/' tests/evals/optimize.sh \
        && rm -f tests/evals/optimize.sh.t ;;

  38) # A doc pointing at a script that is not there -- exactly the state this file was left in
      # the moment tests/evals/run.sh was deleted, and the shape check 20 already catches on the
      # ~/ side but never did on the repo-relative one.
      printf '\nRun `tests/evals/does-not-exist.sh` before committing.\n' >> tests/README.md ;;
  28) # Strand a document by removing the only link to it, which is how a 783-line research
      # handoff came to sit in docs/ reachable from nothing.
      perl -ni -e 'print unless m{\]\(docs/provenance/README\.md\)}' README.md ;;
  27) # Make the mandate unconditional. A gate that always blocks passes any test that only ever
      # checks that it blocks, which is why check 27 exercises both directions.
      #
      # Anchored on the actual block/no-block decision gate, `[ -n "$unmet" ] || exit 0`, rather
      # than on the old combined `[ -n "$unmet" ] || { rm -f "$cnt_file"; exit 0; }` line. Splitting
      # the mandate latch into independent skill/delegation families moved the cnt_file cleanup to
      # its own per-family bookkeeping block above this line, so the old regex stopped matching
      # anything and the row reported "did NOT fail when broken" while proving nothing. `true ||
      # exit 0` always falls through past the early-exit, so the hook reaches the block/reason
      # path regardless of whether anything is actually unmet -- unconditional, in the direction
      # the check exists to catch, surviving the exact rewrite that broke the old anchor because
      # this line is the decision itself, not bookkeeping beside it.
      sed -i.t 's/^\[ -n "\$unmet" \] || exit 0$/true || exit 0/' claude/hooks/skill-mandate.sh \
        && rm -f claude/hooks/skill-mandate.sh.t ;;
  27b) # Put the breadth mandate back on task_count. This is the defect 1.57.0 fixed, restored
      # exactly: task_count asks only "was anything dispatched", so ONE agent sent on its own
      # satisfies a rule whose entire subject is doing the work concurrently. Both of check 27's
      # new fixtures have task_count=2; only fanout_batches tells them apart, so this mutation is
      # invisible to every assertion except the one that reads the reason text.
      sed -i.t 's/\[ "\$fanout_batches" -eq 0 \]/[ "$task_count" -lt 2 ]/' \
        claude/hooks/skill-mandate.sh && rm -f claude/hooks/skill-mandate.sh.t ;;
  27c) # Make the swarm mandate unreachable without deleting it, so the code still reads as though
      # dispatch is routed through the skill. A deleted block is conspicuous in review; a
      # threshold nobody can reach is not, and it is the likelier way this rule dies.
      sed -i.t 's/^if \[ "\$task_count" -ge 1 \] && \[ "\$eval_swarm" = 1 \]/if [ "$task_count" -ge 99999 ] \&\& [ "$eval_swarm" = 1 ]/' \
        claude/hooks/skill-mandate.sh && rm -f claude/hooks/skill-mandate.sh.t ;;
  26) # Claim a platform nobody tests. This is the state the repo was actually in: three README
      # passages describing a Windows lane, with the Windows job red.
      perl -0pi -e 's/CI runs `ubuntu-latest`/CI runs `windows-latest`, `ubuntu-latest`/' README.md ;;
  25) # Put back the redactor that shipped for five versions: known token prefixes plus bare
      # NAME=value. It masked one of the nine shapes the check feeds it, and no gate could see
      # the other eight, because nothing ever handed the hook a secret.
      perl -0pi -e 's/^redact\(\)\{.*?\n\}$/redact(){ sed -E "s\/(sk-ant-|ghp_)[A-Za-z0-9_]+\/\\1[REDACTED]\/g"; }/ms' \
        claude/hooks/failure-diagnose.sh ;;
  39) # The exact shape of 2cda849: duplicate the top heading directly beneath itself. Only the
      # first "## " line is touched -- no /g -- so this proves the duplicate-heading assertion
      # in isolation rather than also tripping the ordering one.
      perl -0pi -e 's/(^## \S.*\n)/$1$1/m' CHANGELOG.md ;;
  40) # MEESEEKS's own reproduction of the regression this check exists to catch: reinstate the
      # latch's old shape, which returned before the delegation-drift logger ever got to write a
      # row for it. cnt>=2 still exits 0 and stays silent -- blocking is untouched -- only the
      # row is lost, which is what isolates this from check 27's blocking assertions.
      #
      # The old anchor, `^if \[ "\$cnt" -ge 2 \]; then$`, was the latch's condition line before
      # the delegation family split it into a combined guard: `if [ "$cnt" -ge 2 ] && { [ "$dcnt"
      # -ge 2 ] || [ "$dscan_recent" = 1 ]; }; then`. That line no longer starts and ends exactly
      # where the old regex anchored, so the mutation landed nowhere -- the same stale-anchor
      # defect as rows 23 and 27, on the same rewrite. Target the row-write instead of the outer
      # condition: two lines below the latch sit an inner `if [ "${VSTACK_NO_DELEGATION_LOG:-0}"
      # != "1" ]; then` (2-space indented, distinct from the top-level logger's own copy of that
      # same test further down the file) guarding the subshell that writes the latched row, and
      # the `exit 0` that keeps the latch silent sits after its `fi`, outside it. Disabling only
      # the inner if reproduces exactly the regression this check exists to catch: silence and
      # non-blocking preserved, only the row lost. sed's BSD/macOS build treats the literal `{`
      # and `}` in `${VSTACK_NO_DELEGATION_LOG:-0}` as an interval expression and errors with
      # "invalid repetition count(s)", so this uses perl, not sed, to apply it.
      perl -pi -e 's/^  if \[ "\$\{VSTACK_NO_DELEGATION_LOG:-0\}" != "1" \]; then$/  if false; then/' \
        claude/hooks/skill-mandate.sh ;;
  44) # Drop "Agent" from the matcher on dispatch-counter.sh's install.sh entry, leaving "Task"
      # wired and every other event untouched. This is the shape check 11's own coverage cannot
      # see: the hook is still referenced, still under PostToolUse, so the referrer/coverage
      # loops in check 11 stay green while every session that dispatches via Agent (not Task)
      # goes uncounted. Only a check that reads the matcher value itself notices.
      sed -i.t 's/matcher:"Agent|Task"/matcher:"Task"/' install.sh && rm -f install.sh.t ;;
  44b) # Direction 3a (the row lands): redirect the replay-row append to a decoy file, one line,
      # nothing else touched. The row is still built, dispatch_index still substituted, the
      # counter file still advances -- it just never reaches $log_file, which is exactly the
      # regression "a dispatch writes a row, and it lands in the replay log" exists to catch and
      # a source grep for the literal path string cannot: the path is still IN the file, spelled
      # correctly, one variable reference away from where check 44's fixture looks for it.
      perl -pi -e 's/>> "\$log_file" 2>\/dev\/null$/>> "\$log_file.decoy" 2>\/dev\/null/' \
        claude/hooks/dispatch-counter.sh ;;
  44c) # Direction 3c (nothing lands in the delegation log): dispatch-counter.sh does not
      # reference VSTACK_DELEGATION_LOG at all today, so this row manufactures the regression
      # rather than toggling an existing guard -- it inserts one line right after the replay-row
      # append that writes the SAME row to the delegation log too, the exact conflation this
      # assertion exists to catch if the two loggers are ever merged carelessly.
      perl -pi -e '$_ .= "  printf \x27%s\\n\x27 \"\$row\" >> \"\${VSTACK_DELEGATION_LOG:-\$HOME/.claude/vstack-delegation-log.jsonl}\" 2>/dev/null\n" if /^  printf \x27%s\\n\x27 "\$row" >> "\$log_file" 2>\/dev\/null$/' \
        claude/hooks/dispatch-counter.sh ;;
  44d) # Direction 3b, prompt half: drop the `| length` off prompt_bytes so the field carries the
      # raw prompt text instead of its byte count -- same key name, same schema shape from the
      # outside, only the content behind it changed. A grep for the field name would stay green
      # through this; only reading the field's actual content catches it.
      perl -pi -e 's/\(\$ti\.prompt \/\/ "" \| length\)/(\$ti.prompt \/\/ "")/' \
        claude/hooks/dispatch-counter.sh ;;
  44e) # Direction 3b, result half: same shape as 44d, on result_bytes -- drop the `| length` so
      # the field carries tool_response's serialized text instead of its byte count.
      perl -pi -e 's/\(\.tool_response \| tostring \| length\)/(.tool_response | tostring)/' \
        claude/hooks/dispatch-counter.sh ;;
  44f) # Direction 3d (the escape hatch): drop the VSTACK_NO_REPLAY_LOG guard from the row-append
      # condition, leaving only the "$encoded_row is non-empty" half. Setting the var no longer
      # does anything -- the row is written regardless -- which is the exact regression "the
      # hatch works" exists to catch.
      perl -pi -e 's/^if \[ "\$\{VSTACK_NO_REPLAY_LOG:-0\}" != "1" \] && \[ -n "\$encoded_row" \]; then$/if [ -n "\$encoded_row" ]; then/' \
        claude/hooks/dispatch-counter.sh ;;
  44g) # Direction 4 (the pin): wire dispatch-counter.sh into claude/settings.json's own
      # PostToolUseFailure array, next to failure-diagnose.sh -- the exact silent rewiring the
      # pin exists to surface, since nothing about this edit is invalid JSON or a broken matcher;
      # it is a config change that quietly starts feeding this hook a payload shape it was never
      # written to expect.
      cp claude/settings.json claude/settings.json.t44g \
        && jq '.hooks.PostToolUseFailure[0].hooks += [{"type":"command","command":"\"$CLAUDE_PROJECT_DIR/.claude/hooks/dispatch-counter.sh\""}]' \
             claude/settings.json.t44g > claude/settings.json \
        && rm -f claude/settings.json.t44g ;;
  45) # Put back the directory-prefix ownership test uninstall.sh shipped with: treat every hook
      # entry whose command starts with the config dir's hooks/ path as vstack's. $h is still
      # bound, so this is a one-line revert to the real defect rather than an invented one -- the
      # user's own scripts live in that same directory, so their entries go too, and the tool
      # still prints that it removed vstack's. Nothing about the edit is invalid jq; the program
      # runs clean and deletes more than it says.
      perl -pi -e 's/^ +\| map\(\. as \$c \| \$ourbase \| any\(\. as \$b \| \$c \| endswith\("\/hooks\/" \+ \$b\)\)\)\n$/              | map(startswith(\$h))\n/' \
        uninstall.sh ;;
  46) # Send the overlay's reference copy to a directory that does not exist. The line already
      # ends in `2>/dev/null || true`, so the failure is silent by construction and overlay.sh
      # still exits 0 -- nine agent prompts go on naming a path with nothing behind it and the
      # only way to notice is to read the destination rather than the installer's exit code.
      sed -i.t 's#"$DEST/.claude/agents/reference/" 2>/dev/null#"$DEST/.claude/agents/reference-decoy/" 2>/dev/null#' \
        overlay.sh && rm -f overlay.sh.t ;;
esac }

# Three rows outside this count also report a result every run: the green-at-baseline probe
# below, the restore-integrity summary, and the tree-unchanged comparison, both at the end. They
# are not optional even in a scoped run, so the declared total is the mutation rows plus those
# three, not the mutation rows alone. This used to print the mutation-row count here and the
# mutation-row-plus-two count in the footer for the same run -- "falsifying 1 checks" above
# "3 declared" below -- which reads as two runs disagreeing about their own size rather than one
# run reporting two different things. Restore-integrity was added as a third fixed row rather
# than folded into tree-unchanged's count because they name different things: tree-unchanged
# says the tree differs from where it started; restore-integrity says why -- this run refused to
# overwrite someone else's edit rather than silently eating it.
N_MUTATION=0
for _ in $CHECKS; do N_MUTATION=$((N_MUTATION+1)); done
DECLARED=$((N_MUTATION+3))
echo "falsifying $N_MUTATION checks ($DECLARED declared rows this run: $N_MUTATION mutation + 3 fixed)"
echo

# A green baseline, taken before anything is mutated.
#
# Every row here asserts "the gate goes red when I break this". A row that is already red before
# the mutation passes for free, and that is not theoretical: a crashed row once left its edit on
# disk, the next run's save() captured the broken file as its own baseline, restore() put the
# break back, and the suite printed FALSIFIABLE over a repo that still carried the defect. The
# tree-unchanged check at the end cannot see that -- it compares the run against a start that was
# already wrong. Only a baseline can.
# Captured to a variable and grepped from a here-string, never `printf ... | grep -q`. Under
# `set -o pipefail` grep -q exits the moment it matches, the writer upstream takes SIGPIPE, and
# the pipeline reports 141 -- which reads as "no FAIL found" and declares a red baseline green.
if ! base=$(./.claude/verify.sh 2>&1) || grep -q '^FAIL  ' <<<"$base"; then
  printf 'FAIL  gate is not green before any mutation; nothing here would be evidence:\n%s\n' \
    "$(printf '%s' "$base" | grep -E '^(FAIL|VERIFICATION)' | sed 's/^/      /')"
  printf '\n0 passed, 1 failed\nNOT FALSIFIABLE\n'
  exit 1
fi
printf 'ok    gate green at baseline (%s checks)\n\n' \
  "$(printf '%s' "$base" | grep -c '^ok    ')"
PASSED=$((PASSED+1))

for id in $CHECKS; do
  fs=$(files_for "$id")
  lbl=$(label_for "$id")

  # Check 19 runs `claude plugin validate`; where the CLI is absent the check itself reports a
  # skip, so its mutation cannot produce the expected FAIL. Skip visibly rather than fail
  # wrongly — CI installs the CLI, so this branch only fires on machines without it.
  # Ask the check itself whether it can measure, rather than inferring it from the CLI being on
  # PATH. On CI the CLI was installed and `claude plugin validate` still exited 0 on a manifest
  # it rejects locally, so this row demanded a FAIL the check could never produce and CI went
  # red over the harness rather than the repo. Check 19 now reports a skip when its own positive
  # control fails; honour that instead of second-guessing it.
  # Same shape as 19: the check can legitimately decline to measure, so ask it rather than
  # assuming. Without tags there is nothing for it to compare, and demanding a FAIL it cannot
  # produce turns a correct skip into a red build.
  if [ "$id" = 24 ]; then
    # Not `verify.sh | grep -q`: verify writes for ~20s, grep -q exits on the first match, verify
    # dies of SIGPIPE, and pipefail turns the whole pipeline into 141. That read as "the check did
    # not skip", so this branch never fired and the row claimed a falsifiability it had not shown.
    _probe=$(./.claude/verify.sh 2>&1)
    if grep -q "^skip  $lbl" <<<"$_probe"; then
      printf 'skip  check %-3s not falsifiable here (no tags to compare against; %s)\n' "$id" "$lbl"
      SKIPPED=$((SKIPPED+1)); continue
    fi
  fi

  if [ "$id" = 19 ]; then
    if ! command -v claude >/dev/null 2>&1; then
      printf 'skip  check %-3s not falsifiable here (claude CLI not installed; %s)\n' "$id" "$lbl"
      SKIPPED=$((SKIPPED+1)); continue
    fi
    _probe=$(./.claude/verify.sh 2>&1)      # not a pipe: see the 141 note on check 24 above
    if grep -q "^skip  $lbl" <<<"$_probe"; then
      printf 'skip  check %-3s not falsifiable here (validator is not validating; %s)\n' "$id" "$lbl"
      SKIPPED=$((SKIPPED+1)); continue
    fi
  fi

  [ -n "$fs" ] && save $fs

  if [ "$id" = 0 ]; then
    # Nothing to edit: the toolchain check is about the environment, so remove jq from it.
    out=$(env PATH="$NOJQ" ./.claude/verify.sh 2>&1)
  else
    # Fingerprint the files first. A mutation anchored to prose stops matching the moment the
    # prose is rewritten, and then the row reports "did NOT fail when broken" -- which reads as a
    # weak check when the truth is a mutation that landed nowhere. That has now happened three
    # times: rows 11, 26 and 28, the last two on the same README rewrite. Distinguish the two
    # cases instead of leaving the reader to guess.
    # Fingerprinted per file, not over the concatenation. Rows 1, 18 and 29 each mutate two
    # files now -- two lanes of a check that makes two promises -- and a combined hash goes on
    # matching as long as either lane still lands, which is precisely the rot this detector
    # exists to catch, one level finer. Naming the file that stopped changing is also the whole
    # value of the message.
    _stale=""
    if [ -n "$fs" ]; then
      _before=""
      for _f in $fs; do _before="$_before$(_fhash "$_f") "; done
      break_it "$id"
      _i=0
      for _f in $fs; do
        _i=$((_i+1))
        _b=$(printf '%s' "$_before" | cut -d' ' -f"$_i")
        _a=$(_fhash "$_f")
        # Move $EXP to the post-mutation bytes now, while they are known-good: this is the
        # instant the window conflict_guard() polices actually opens. Anything that writes to
        # $_f between this line and this row's restore() is a concurrent edit, not us.
        cp "$_f" "$EXP/$_f" 2>/dev/null
        [ "$_b" = "$_a" ] && _stale="$_stale $_f"
      done
    else
      break_it "$id"
    fi
    if [ -n "$_stale" ]; then
      printf 'FAIL  check %-3s mutation changed nothing in:%s (its pattern no longer matches)\n' "$id" "$_stale"
      FAILED=$((FAILED+1))
      restore $fs
      continue
    fi
    out=$(./.claude/verify.sh 2>&1)
  fi

  if grep -q '^FAIL  '"$lbl" <<<"$out"; then
    pass "$id" "$lbl"
  else
    fail "$id" "$lbl" "$(printf '%s' "$out" | grep -E '^(FAIL|VERIF)' | sed 's/^/      got: /')"
  fi

  [ -n "$fs" ] && restore $fs
  cr=$(creates_for "$id")
  if [ -n "$cr" ]; then
    git rm -q -f --cached "$cr" >/dev/null 2>&1
    rm -f "$cr"
  fi
done

echo
# Reported before tree-unchanged below on purpose: this is the mechanism, tree-unchanged is a
# symptom that can follow from it. A file conflict_guard() refused to restore still differs from
# TREE_BEFORE and trips that check too -- correctly, it is still evidence the tree changed -- but
# this is the row that names why, rather than leaving the reader to diff two `git status` dumps
# and guess.
if [ -s "$CONFLICT_DIR/.conflicts" ] 2>/dev/null; then
  printf 'FAIL  restore integrity: refused to overwrite %s concurrently-edited file(s) -- this sweep cannot vouch for the tree; its verdict is void\n' \
    "$(grep -c '' "$CONFLICT_DIR/.conflicts" 2>/dev/null)"
  sed 's/^/      /' "$CONFLICT_DIR/.conflicts"
  printf '      pre-mutation backups kept at: %s\n' "$CONFLICT_DIR"
  FAILED=$((FAILED+1))
else
  printf 'ok    restore integrity: no concurrent edits during the run\n'; PASSED=$((PASSED+1))
fi

echo
# Restoration has to be exact, or a row silently rewrites the repo it is testing.
if command -v git >/dev/null && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  TREE_AFTER=$(tree_fingerprint .)
  if [ "$TREE_AFTER" != "$TREE_BEFORE" ]; then
    printf 'FAIL  a mutation was not restored:\n%s\n' \
      "$(diff <(printf '%s\n' "$TREE_BEFORE") <(printf '%s\n' "$TREE_AFTER") | sed 's/^/      /')"
    FAILED=$((FAILED+1))
  else
    printf 'ok    tree unchanged by the run\n'; PASSED=$((PASSED+1))
  fi
fi

echo
# The accounting verify.sh carries, in the twin that enforces it. This printed "N passed, 0
# failed / FALSIFIABLE" with no declared count and no skip line, so rows 19 and 24 could
# `continue` out and the summary read exactly like a run that proved every row. verify.sh's own
# founding lesson, unapplied to the suite that proves verify.sh.
#
# $DECLARED is computed once, up top alongside $N_MUTATION, specifically so the header and this
# footer report the same run the same way. The first version of this counted only one of the two
# always-on pseudo-rows (baseline-green, tree-unchanged) and reported "-1 declared row(s) reported
# nothing" -- an accounting bug announcing itself in the negative, the right failure mode for a
# counter nobody had checked against a known total.
printf '%d declared, %d passed, %d failed, %d skipped\n' "$DECLARED" "$PASSED" "$FAILED" "$SKIPPED"
if [ "$((PASSED + FAILED + SKIPPED))" -ne "$DECLARED" ]; then
  printf 'FAIL  row accounting: %d declared row(s) reported nothing\n' \
    "$((DECLARED - PASSED - FAILED - SKIPPED))"
  FAILED=$((FAILED+1))
fi
[ "$FAILED" -eq 0 ] && echo "FALSIFIABLE" || echo "NOT FALSIFIABLE"
[ "$FAILED" -eq 0 ]
