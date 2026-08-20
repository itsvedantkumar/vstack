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
CHECKS="0 1 2 3 4 5 6 7 8 9 9b 10 11 12 13 14 15 16 17 18 19"

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
  17)  printf 'claude/settings.project-keys' ;;
  18)  printf 'claude/hooks/inject-session-context.sh' ;;
  19)  printf 'claude/.claude-plugin/plugin.json' ;;
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
      # substring grep could not see
      perl -0pi -e 's/^        PostToolUse: \[\n.*?\n.*?\n//m' install.sh ;;
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
  17) # allow a personal key through, which is the whole failure this check exists to stop
      printf '\ntheme\n' >> claude/settings.project-keys ;;
  18) # pad the per-prompt digest past its cap
      perl -0pi -e 's/(DELEGATE: mechanical)/("padding " x 60) . $1/e' claude/hooks/inject-session-context.sh ;;
  19) # a field the schema does not recognise; --strict rejects it
      sed -i.t 's/"version":/"verzion":/' claude/.claude-plugin/plugin.json \
        && rm -f claude/.claude-plugin/plugin.json.t ;;
esac }

echo "falsifying $(printf '%s' "$CHECKS" | wc -w | tr -d ' ') checks"
echo

for id in $CHECKS; do
  fs=$(files_for "$id")
  lbl=$(label_for "$id")

  # Check 19 runs `claude plugin validate`; where the CLI is absent the check itself reports a
  # skip, so its mutation cannot produce the expected FAIL. Skip visibly rather than fail
  # wrongly — CI installs the CLI, so this branch only fires on machines without it.
  if [ "$id" = 19 ] && ! command -v claude >/dev/null 2>&1; then
    printf 'skip  check %-3s not falsifiable here (claude CLI not installed; %s)\n' "$id" "$lbl"
    continue
  fi

  [ -n "$fs" ] && save $fs

  if [ "$id" = 0 ]; then
    # Nothing to edit: the toolchain check is about the environment, so remove jq from it.
    out=$(env PATH="$NOJQ" ./.claude/verify.sh 2>&1)
  else
    break_it "$id"
    out=$(./.claude/verify.sh 2>&1)
  fi

  if printf '%s' "$out" | grep -q '^FAIL  '"$lbl"; then
    pass "$id" "$lbl"
  else
    fail "$id" "$lbl" "$(printf '%s' "$out" | grep -E '^(FAIL|VERIF)' | sed 's/^/      got: /')"
  fi

  [ -n "$fs" ] && restore $fs
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
