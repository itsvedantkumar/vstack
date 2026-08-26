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
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

# One id per `# --- N.` section in .claude/verify.sh. Check 16 parses this line.
CHECKS="0 1 2 3 4 5 6 7 8 9 9b 10 11 12 13 14 14b 15 16 17 18 18b 18c 19 20 20b 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 44 44b 44c 44d 44e 44f 44g 45 46"
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
LOCK="$(git rev-parse --git-dir 2>/dev/null)/vstack-falsifiability.lock"
printf '%s\n' "$$" > "$LOCK" 2>/dev/null || LOCK=""
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
TREE_BEFORE=""
if command -v git >/dev/null && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  TREE_BEFORE=$(git status --porcelain -- . 2>/dev/null)
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
  1)   printf 'claude/hooks/format.sh ui-gate/rules/tokens.sh' ;;
  2)   printf 'mcp/servers.json' ;;
  3)   printf 'claude/skills/unslop/SKILL.md' ;;
  4|5|6) printf 'README.md' ;;
  7)   printf 'claude/CLAUDE.md' ;;
  8|9|11) printf 'install.sh' ;;
  9b)  printf 'overlay.sh' ;;
  10)  printf 'claude/agents/debugger.md' ;;
  12)  printf 'README.md' ;;
  13)  printf 'claude/.claude-plugin/plugin.json' ;;
  14)  printf 'claude/hooks/verify-gate.sh' ;;
  14b) printf '.claude/verify.sh' ;;
  15)  printf 'claude/settings.json' ;;
  16)  printf 'tests/gate-falsifiability.sh' ;;
  17)  printf 'overlay.sh' ;;
  18)  printf 'claude/hooks/inject-session-context.sh' ;;
  18b) printf 'README.md' ;;
  18c) printf 'claude/hooks/inject-session-context.sh' ;;
  19)  printf 'claude/.claude-plugin/plugin.json' ;;
  20)  printf 'claude/commands/test.md' ;;
  20b) printf 'claude/commands/test.md' ;;
  21)  printf 'install.sh' ;;
  22)  printf 'claude/skills/swarm/SKILL.md' ;;
  23)  printf 'claude/hooks/guard-destructive.sh' ;;
  24)  printf 'claude/.claude-plugin/plugin.json' ;;
  25)  printf 'claude/hooks/failure-diagnose.sh' ;;
  26)  printf 'README.md' ;;
  27)  printf 'claude/hooks/skill-mandate.sh' ;;
  28)  printf 'README.md' ;;
  29)  printf 'bin/cloudflare-mcp ui-gate/rules/browser.sh' ;;
  30)  printf 'claude/hooks/format.sh' ;;
  31)  printf '' ;;   # plants a new file rather than editing one
  32|33) printf 'claude/hooks/inject-session-context.sh' ;;
  35)  printf 'ui-gate/ui-gate.sh' ;;
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
  2)   printf 'json valid' ;;
  3)   printf 'skills loadable' ;;
  4)   printf 'no hardcoded home paths' ;;
  5)   printf 'no committed secrets' ;;
  6)   printf 'no infrastructure ids' ;;
  7)   printf 'referenced skills exist' ;;
  8)   printf 'settings merge program' ;;
  9)   printf 'install.sh --dry-run' ;;
  9b)  printf 'overlay merge path' ;;
  10)  printf 'agents + commands loadable' ;;
  11)  printf 'hook wiring' ;;
  12)  printf 'doc counts match tree' ;;
  13)  printf 'plugin manifest versions' ;;
  14)  printf 'stop-hook gate blocks' ;;
  14b) printf 'the gate refuses a tree under mutation' ;;
  15)  printf 'skillOverrides' ;;
  16)  printf 'falsifiability coverage' ;;
  17)  printf 'overlay ships project keys only' ;;
  18)  printf 'injected context bounded' ;;
  18b) printf 'injected context bounded' ;;
  18c) printf 'injected context bounded' ;;
  19)  printf 'plugin manifests valid' ;;
  20)  printf 'referenced install paths exist' ;;
  20b) printf 'referenced install paths exist' ;;
  21)  printf 'RETIRED names only retired keys' ;;
  22)  printf 'skills disclose what they do not ship' ;;
  23)  printf 'destructive guard decides correctly' ;;
  24)  printf 'declared version matches what installs' ;;
  25)  printf 'failure tail redacts credentials' ;;
  26)  printf 'documented platforms match CI' ;;
  27)  printf 'skill mandate decides correctly' ;;
  28)  printf 'every doc is reachable' ;;
  29)  printf 'shellcheck clean' ;;
  30)  printf 'shellcheck suppressions carry a reason' ;;
  31)  printf 'every shipped file has a referrer' ;;
  32)  printf 'grill trigger decides correctly' ;;
  33)  printf 'project overlay stands down when the user-scope hook is live' ;;
  34)  printf 'the policy document reaches a session exactly once' ;;
  35)  printf 'gates refuse a green on nothing measured' ;;
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
  1)  # Both lanes of the file selector. format.sh has a shebang; ui-gate/rules/tokens.sh has
      # none, only a `# shellcheck shell=` directive, and for four versions nothing in this gate
      # parsed it. Mutating one leaves the other exactly as unproven as it was.
      for _f in claude/hooks/format.sh ui-gate/rules/tokens.sh; do
        printf '\nif [ -z\n' >> "$_f"
      done ;;
  2)  printf '{' >> mcp/servers.json ;;
  3)  # a description past the 200-char listing cap, which silently stops the skill triggering
      awk 'BEGIN{d="x"; for(i=0;i<209;i++) d=d "y"}
           /^description:/{print "description: " d; next} {print}' \
          claude/skills/unslop/SKILL.md > /tmp/fx.$$ && mv /tmp/fx.$$ claude/skills/unslop/SKILL.md ;;
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
  9b) perl -0pi -e 's{\.hooks = \(}{.hooks = (\$ship.hooks) | .DEADCODE = (}' overlay.sh ;;
  10) sed -i.t '/^description:/d' claude/agents/debugger.md && rm -f claude/agents/debugger.md.t ;;
  11) # drop the PostToolUse key while PostToolUseFailure stays: the exact shape the old
      # substring grep could not see. Indentation-tolerant on purpose — this row silently
      # stopped mutating anything when the merge program was reindented, and a mutation that
      # lands nowhere reports the check as unfalsifiable while proving nothing about it.
      perl -0pi -e 's/^[ ]*PostToolUse: \[\n.*?\n.*?\n//m' install.sh ;;
  12) sed -i.t 's/| Commands | [0-9]* |/| Commands | 99 |/' README.md && rm -f README.md.t ;;
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
      sed -i.t 's/ && kill -0 "$(cat "$_lk" 2>\/dev\/null)" 2>\/dev\/null//' \
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
      # Both lanes, since 1.14.0 folded four copies of the selector into one sh_files().
      # cloudflare-mcp is the shebang-without-suffix lane; ui-gate/rules/browser.sh is the
      # directive-only lane, a sourced fragment with no shebang at all that the shebang scan
      # could not see. One mutation per lane, or half the selector stays unproven.
      for _f in bin/cloudflare-mcp ui-gate/rules/browser.sh; do
        printf '\nsc_probe=$HOME/some path\nls $sc_probe >/dev/null 2>&1 || true\n' >> "$_f"
      done ;;
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
      for _f in $fs; do _before="$_before$(shasum < "$_f" 2>/dev/null | cut -d' ' -f1) "; done
      break_it "$id"
      _i=0
      for _f in $fs; do
        _i=$((_i+1))
        _b=$(printf '%s' "$_before" | cut -d' ' -f"$_i")
        _a=$(shasum < "$_f" 2>/dev/null | cut -d' ' -f1)
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
  if [ "$(git status --porcelain -- . 2>/dev/null)" != "$TREE_BEFORE" ]; then
    printf 'FAIL  a mutation was not restored:\n%s\n' \
      "$(diff <(printf '%s\n' "$TREE_BEFORE") <(git status --porcelain -- .) | sed 's/^/      /')"
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
