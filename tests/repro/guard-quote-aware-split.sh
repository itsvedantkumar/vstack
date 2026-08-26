#!/usr/bin/env bash
# guard-quote-aware-split.sh — repro for RICK's follow-up on the bypassPermissions escalation:
# guard-destructive.sh split compound commands on `;`, `&&`, `||`, `|` by blind text substitution
# (sed), with no notion of quoting. A `;` typed as ordinary punctuation inside a quoted argument
# -- e.g. a commit message describing this very guard's own rules -- was treated exactly like a
# real shell separator, producing a phantom segment that began at the next word. When that word
# happened to be `git reset`, `git clean`, `git stash`, etc., the anchored ask-tier pattern for it
# matched a sentence fragment that never was, was not, and could never become that command, and
# under bypassPermissions the escalation this session added denied the ENTIRE tool call before any
# of it ran. Confirmed by hand: my own commit message with "...blocked; git reset --hard got..."
# in it, later rephrased around, and reproduced deliberately below with a minimal case.
#
# RICK's literal repro command (a two-line, bare `-m "prose about git reset --hard as
# documentation"` with no semicolon inside the quoted string) does NOT reproduce against this
# guard, in either newline-joined or semicolon-joined form -- checked directly below (direction 0)
# and disclosed as such. The real discriminator is not "does the segment start with git" in
# general; it is "does a `;`/`&&`/`||`/`|` inside a quoted argument land immediately before text
# that itself starts with an anchored keyword." RICK's own diagnosis was the right instinct aimed
# at an example that happened not to trigger it -- this file pins down the actual mechanism.
set -uo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
GUARD="$REPO/claude/hooks/guard-destructive.sh"

PASS=0
FAIL=0
ok(){ printf 'ok    %s\n' "$1"; PASS=$((PASS+1)); }
bad(){ printf 'FAIL  %s\n' "$1"; FAIL=$((FAIL+1)); }

decide(){ # <command> <permission_mode-or-"">
  local payload
  if [ -n "${2:-}" ]; then
    payload=$(jq -cn --arg c "$1" --arg pm "$2" '{tool_input:{command:$c},permission_mode:$pm}')
  else
    payload=$(jq -cn --arg c "$1" '{tool_input:{command:$c}}')
  fi
  printf '%s' "$payload" | bash "$GUARD" 2>/dev/null | jq -r '.hookSpecificOutput.permissionDecision // "NO-OUTPUT"'
}

want(){ # <label> <command> <permission_mode-or-""> <expected>
  local got
  got=$(decide "$2" "$3")
  if [ "$got" = "$4" ]; then ok "$1"; else bad "$1 -- got '$got', want '$4' (cmd=[$2] pm='${3:-<absent>}')"; fi
}

echo "=== direction 0: RICK's literal repro -- disclosed as non-reproducing, asserted so it stays that way ==="
want "newline-joined literal repro stays allow"    $'d=$(mktemp -d); cd "$d"; git init -q .; touch a; git add a\ngit commit -q -m "prose about git reset --hard as documentation"' bypassPermissions allow
want "semicolon-joined literal repro stays allow"  'd=$(mktemp -d); cd "$d"; git init -q .; touch a; git add a; git commit -q -m "prose about git reset --hard as documentation"' bypassPermissions allow

echo "=== direction 1: the real mechanism -- a ';' INSIDE a quoted arg must not act as a separator ==="
want "semicolon inside a -m string before 'git reset --hard' -> allow, not deny" \
  'git commit -m "line one; git reset --hard: docs"' bypassPermissions allow
want "semicolon inside a -m string before 'git clean -fd' -> allow, not deny" \
  'git commit -m "notes; git clean -fd is mentioned here"' bypassPermissions allow
want "semicolon inside a -m string before 'git stash' -> allow, not deny" \
  'git commit -m "aside; git stash can lose work"' bypassPermissions allow
want "single-quoted arg with an internal semicolon before 'git reset --hard' -> allow" \
  "git commit -m 'one; git reset --hard: docs'" bypassPermissions allow
want "an apostrophe inside a double-quoted arg does not desync quote tracking" \
  'git commit -m "it'"'"'s fine; git reset --hard is safe to mention"' bypassPermissions allow

echo "=== direction 2: a REAL top-level separator outside quotes must still catch the real command ==="
want "a genuine ';' before an unquoted git reset --hard is still denied under bypass" \
  'echo x; git reset --hard' bypassPermissions deny
want "a genuine '&&' before an unquoted git clean -fd is still denied under bypass" \
  'echo x && git clean -fd' bypassPermissions deny
want "a genuine top-level ';' after a quoted arg containing one still catches a REAL trailing reset" \
  'echo "a;b" && git reset --hard' bypassPermissions deny

echo "=== direction 3: no regression on what already worked (existing deny tier, unaffected) ==="
want "force-push to main is still denied (unrelated to this fix)" 'git push --force origin main' bypassPermissions deny
want "rm -rf / is still denied" 'rm -rf /' bypassPermissions deny
want "compound rm -rf / after a harmless command is still denied" 'echo hi; rm -rf /' bypassPermissions deny

echo "=== direction 4: RICK's counter-case -- does quote-awareness cost us anything we actually catch today? ==="
echo "=== these were already 'allow' before this fix (anchored git-family patterns don't see inside a subshell arg) ==="
want "bash -c \"git clean -fd\" was already allow (anchoring, unrelated to quoting)" \
  'bash -c "git clean -fd"' bypassPermissions allow
echo "=== these rely on UNANCHORED patterns (rm-family) and must still catch destructive text inside a quoted subshell arg ==="
want "bash -c \"rm -rf /etc\" is still caught (unanchored rm pattern sees inside the quotes)" \
  'bash -c "rm -rf /etc"' bypassPermissions ask

echo "=== direction 5: this repo's own mandated commit convention -- heredoc-wrapped -m, not a plain string ==="
echo "=== quote-tracking alone is not enough here: the heredoc body has its own, unrelated '\"' characters ==="
echo "=== that desync a flat quote-toggle against the OUTER -m \"...\" quote on the first one it hits ==="
HD_CMD=$'git commit -m "$(cat <<\'EOF\'\nsome context; the phrase "quoted example" appears here, then later: git reset --hard\nmore words after that with another "quote" for good measure\nEOF\n)" -- some/path'
want "heredoc-wrapped -m message mentioning a hard-reset in prose, with unrelated quotes before it, stays allow" \
  "$HD_CMD" bypassPermissions allow
HD_REAL=$'git commit -m "$(cat <<\'EOF\'\necho x; git reset --hard\nEOF\n)" -- some/path'
want "a genuine top-level ';' INSIDE a heredoc body is still opaque (heredoc content is never split)" \
  "$HD_REAL" bypassPermissions allow

echo "=== direction 6: heredoc opacity must not become a new hiding place for a real injected command ==="
INJECT_REAL=$'echo pre; git commit -m "$(cat <<EOF\nharmless body\nEOF\n)"; rm -rf /'
want "a genuine ';' well after the heredoc and the outer quote both close is still denied" \
  "$INJECT_REAL" bypassPermissions deny

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
