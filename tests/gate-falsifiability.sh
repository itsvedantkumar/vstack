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
CHECKS="0 1 2 3 4 5 6 7 8 9 9b 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32"

BK=$(mktemp -d)
NOJQ=$(mktemp -d)
trap 'rm -rf "$BK" "$NOJQ"' EXIT
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

PASSED=0; FAILED=0
pass(){ printf 'ok    check %-3s falsifiable (%s)\n' "$1" "$2"; PASSED=$((PASSED+1)); }
fail(){ printf 'FAIL  check %-3s did NOT fail when broken\n      expected label: %s\n%s\n' \
        "$1" "$2" "${3:-}"; FAILED=$((FAILED+1)); }

save(){ for f in "$@"; do mkdir -p "$BK/$(dirname "$f")"; cp "$f" "$BK/$f"; done; }
restore(){ for f in "$@"; do cp "$BK/$f" "$f"; done; }

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
ORPHAN_PROBE="bin/zz-unreferenced-$$.sh"

creates_for(){ case "$1" in
  31)  printf '%s' "$ORPHAN_PROBE" ;;
esac }

# Files each row edits, so it can be put back byte for byte. Backing up beats `git checkout`
# here: this has to be safe to run on a dirty tree.
files_for(){ case "$1" in
  0)   printf '' ;;
  1)   printf 'claude/hooks/format.sh' ;;
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
  15)  printf 'claude/settings.json' ;;
  16)  printf 'tests/gate-falsifiability.sh' ;;
  17)  printf 'overlay.sh' ;;
  18)  printf 'claude/hooks/inject-session-context.sh' ;;
  19)  printf 'claude/.claude-plugin/plugin.json' ;;
  20)  printf 'claude/commands/test.md' ;;
  21)  printf 'install.sh' ;;
  22)  printf 'claude/skills/swarm/SKILL.md' ;;
  23)  printf 'claude/hooks/guard-destructive.sh' ;;
  24)  printf 'claude/.claude-plugin/plugin.json' ;;
  25)  printf 'claude/hooks/failure-diagnose.sh' ;;
  26)  printf 'README.md' ;;
  27)  printf 'claude/hooks/skill-mandate.sh' ;;
  28)  printf 'README.md' ;;
  29)  printf 'bin/cloudflare-mcp' ;;
  30)  printf 'claude/hooks/format.sh' ;;
  31)  printf '' ;;   # plants a new file rather than editing one
  32)  printf 'claude/hooks/inject-session-context.sh' ;;
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
  15)  printf 'skillOverrides' ;;
  16)  printf 'falsifiability coverage' ;;
  17)  printf 'overlay ships project keys only' ;;
  18)  printf 'injected context bounded' ;;
  19)  printf 'plugin manifests valid' ;;
  20)  printf 'referenced install paths exist' ;;
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
esac }

# Break exactly what the check watches, and nothing else. Surgical matters: a mutation that
# trips four checks proves far less than one that trips the intended one.
break_it(){ case "$1" in
  1)  printf '\nif [ -z\n' >> claude/hooks/format.sh ;;
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
  9b) printf '\nexit 4\n' >> overlay.sh ;;
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
  15) sed -i.t 's/"skillOverrides": {/"skillOverrides": {\n    "claude-mem:do": "off",/' \
        claude/settings.json && rm -f claude/settings.json.t ;;
  16) sed -i.t 's/^CHECKS="0 /CHECKS="/' tests/gate-falsifiability.sh \
        && rm -f tests/gate-falsifiability.sh.t ;;
  17) # Restore the deletion overlay.sh used to do: strip every destination key that is not on
      # vstack's project allowlist. That silently destroyed target-owned enabledPlugins, theme,
      # and forceLoginMethod, and the old version of this row -- appending theme to
      # settings.project-keys -- could not see it, because the check it armed was asserting the
      # deletion as correct. The row now mutates the behaviour, not the allowlist.
      perl -0pi -e 's/\| \(\$dest \* \$ship\)/| (\$dest * \$ship)\n    | delpaths([(keys - \$A)[] | [.]])/' overlay.sh ;;
  18) # pad the per-prompt digest past its cap
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
  21) # the exact list that was nearly shipped: Claude Code's own sandbox setting, named as if
      # it were vstack's to delete
      sed -i.t "s/^RETIRED='\[\]'/RETIRED='[\"sandbox\"]'/" install.sh && rm -f install.sh.t ;;
  22) # a skill telling the model to run a helper the port does not vendor, with no notice —
      # the shape that shipped in impeccable and in brainstorming's visual companion
      printf '\n```bash\nnode scripts/not-vendored-probe.mjs --run\n```\n' >> claude/skills/swarm/SKILL.md ;;
  23) # the failure that matters: a guard that stops denying. Make the deny tier unreachable
      # and the ask/allow tiers keep working, so only a test of the decisions notices.
      sed -i.t 's/^if \[ "\$SIMPLE" = 1 \]; then/if false; then/' claude/hooks/guard-destructive.sh \
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
      printf '\nsc_probe=$HOME/some path\nls $sc_probe >/dev/null 2>&1 || true\n' \
        >> bin/cloudflare-mcp ;;
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
  28) # Strand a document by removing the only link to it, which is how a 783-line research
      # handoff came to sit in docs/ reachable from nothing.
      perl -ni -e 'print unless m{\]\(docs/provenance/README\.md\)}' README.md ;;
  27) # Make the mandate unconditional. A gate that always blocks passes any test that only ever
      # checks that it blocks, which is why check 27 exercises both directions.
      perl -0pi -e 's/\[ -n "\$unmet" \] \|\| \{ rm -f "\$cnt_file"; exit 0; \}/unmet="\$unmet\\n  always"/' \
        claude/hooks/skill-mandate.sh ;;
  26) # Claim a platform nobody tests. This is the state the repo was actually in: three README
      # passages describing a Windows lane, with the Windows job red.
      perl -0pi -e 's/CI runs `ubuntu-latest`/CI runs `windows-latest`, `ubuntu-latest`/' README.md ;;
  25) # Put back the redactor that shipped for five versions: known token prefixes plus bare
      # NAME=value. It masked one of the nine shapes the check feeds it, and no gate could see
      # the other eight, because nothing ever handed the hook a secret.
      perl -0pi -e 's/^redact\(\)\{.*?\n\}$/redact(){ sed -E "s\/(sk-ant-|ghp_)[A-Za-z0-9_]+\/\\1[REDACTED]\/g"; }/ms' \
        claude/hooks/failure-diagnose.sh ;;
esac }

echo "falsifying $(printf '%s' "$CHECKS" | wc -w | tr -d ' ') checks"
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
      continue
    fi
  fi

  if [ "$id" = 19 ]; then
    if ! command -v claude >/dev/null 2>&1; then
      printf 'skip  check %-3s not falsifiable here (claude CLI not installed; %s)\n' "$id" "$lbl"
      continue
    fi
    _probe=$(./.claude/verify.sh 2>&1)      # not a pipe: see the 141 note on check 24 above
    if grep -q "^skip  $lbl" <<<"$_probe"; then
      printf 'skip  check %-3s not falsifiable here (validator is not validating; %s)\n' "$id" "$lbl"
      continue
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
    _before=""
    [ -n "$fs" ] && _before=$(cat $fs 2>/dev/null | shasum | cut -d' ' -f1)
    break_it "$id"
    _after=""
    [ -n "$fs" ] && _after=$(cat $fs 2>/dev/null | shasum | cut -d' ' -f1)
    if [ -n "$fs" ] && [ "$_before" = "$_after" ]; then
      printf 'FAIL  check %-3s mutation changed nothing (its pattern no longer matches %s)\n' "$id" "$fs"
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
printf '%d passed, %d failed\n' "$PASSED" "$FAILED"
[ "$FAILED" -eq 0 ] && echo "FALSIFIABLE" || echo "NOT FALSIFIABLE"
[ "$FAILED" -eq 0 ]
