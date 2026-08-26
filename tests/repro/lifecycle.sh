#!/usr/bin/env bash
# lifecycle.sh — regression test for P0-1: does uninstall.sh actually return a machine to its
# pre-vstack state, across the install/uninstall sequences a real user hits?
#
# Audit claim: uninstall.sh selects the LATEST per-run backup (tests/repro/../../uninstall.sh:
# `list_timestamps | head -1`). install.sh's `back()` copies a file into the CURRENT run's
# backup dir unconditionally, before overwriting it -- even when the new content is identical
# to the old. So a second `install.sh` run backs up vstack's OWN payload (written by the first
# run), not the pre-vstack original. `uninstall.sh` with no --from then restores/keeps that
# vstack payload instead of removing it, and vstack stays installed.
#
# This file does not trust that description -- it runs install.sh and uninstall.sh for real,
# in throwaway HOMEs, and inspects the resulting tree. It fails (non-zero exit) while the
# defect is live and passes (zero) once uninstall.sh no longer exhibits it.
#
# Usage: bash tests/repro/lifecycle.sh
set -uo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FAIL=0
CHECK_N=0

say()  { printf '%s\n' "$*"; }
hr()   { printf -- '---------------------------------------------------------------\n'; }

# A vstack-shipped hook script and skill, used as canaries for "is the payload still here".
CANARY_HOOK="verify-gate.sh"
CANARY_SKILL="swarm"

# check <name> <expected> <found-desc> <0-pass/1-fail>
check() {
  name="$1"; expected="$2"; found="$3"; status="$4"
  CHECK_N=$((CHECK_N + 1))
  if [ "$status" = 0 ]; then
    say "PASS  [$name]"
  else
    say "FAIL  [$name]"
    say "      expected: $expected"
    say "      found:    $found"
    FAIL=$((FAIL + 1))
  fi
}

# --- sandbox plumbing -------------------------------------------------------------------------
# Named var, never the literal string "$HOME" -- this repo's own guard blocks `rm -rf "$HOME"`
# even with HOME reassigned, and the instruction is to use a named sandbox path instead.
new_sandbox() {
  SBOX=$(mktemp -d) || { echo "cannot create sandbox" >&2; exit 1; }
  export HOME="$SBOX/home"
  mkdir -p "$HOME"
}

# Seeds pre-existing, identifiable user state so a restore can be judged against something
# real: a settings.json with a foreign key, a user-authored hook, and a file in skills/.
seed_user_state() {
  mkdir -p "$HOME/.claude/hooks" "$HOME/.claude/skills/my-own-skill"
  printf '{\n  "foreignVendorKey": "acme-widgets-prod-42"\n}\n' > "$HOME/.claude/settings.json"
  printf '#!/bin/sh\necho "this is the operator'"'"'s own hook, not vstack'"'"'s"\n' \
    > "$HOME/.claude/hooks/user-own-hook.sh"
  chmod +x "$HOME/.claude/hooks/user-own-hook.sh"
  printf '# my own skill, predates vstack\n' > "$HOME/.claude/skills/my-own-skill/SKILL.md"
  printf '# USER-OWN-CLAUDE-MD-MARKER-8f2c\n' > "$HOME/.claude/CLAUDE.md"
}

# True (0) iff every seeded artifact from seed_user_state is intact and unmodified.
user_state_intact() {
  [ "$(cat "$HOME/.claude/settings.json" 2>/dev/null | tr -d '[:space:]')" = \
    '{"foreignVendorKey":"acme-widgets-prod-42"}' ] || return 1
  [ -f "$HOME/.claude/hooks/user-own-hook.sh" ] || return 1
  grep -q "operator's own hook" "$HOME/.claude/hooks/user-own-hook.sh" 2>/dev/null || return 1
  [ -f "$HOME/.claude/skills/my-own-skill/SKILL.md" ] || return 1
  return 0
}

# True (0) iff no trace of the vstack payload remains: the canary hook script is gone, the
# canary skill directory is gone, and settings.json neither references the (now-deleted) hook
# nor still carries vstack's statusLine.
vstack_payload_gone() {
  [ -e "$HOME/.claude/hooks/$CANARY_HOOK" ] && return 1
  [ -e "$HOME/.claude/skills/$CANARY_SKILL" ] && return 1
  # A CLAUDE.md that still carries the user's marker is theirs and may stay; one without it is
  # vstack's and must be gone. Only the second case is a payload-removal failure.
  if [ -e "$HOME/.claude/CLAUDE.md" ] \
     && ! grep -q "USER-OWN-CLAUDE-MD-MARKER-8f2c" "$HOME/.claude/CLAUDE.md" 2>/dev/null; then
    return 1
  fi
  if [ -f "$HOME/.claude/settings.json" ]; then
    grep -q "$CANARY_HOOK" "$HOME/.claude/settings.json" 2>/dev/null && return 1
    grep -q "statusline.sh" "$HOME/.claude/settings.json" 2>/dev/null && return 1
  fi
  return 0
}

describe_residue() {
  out=""
  [ -e "$HOME/.claude/hooks/$CANARY_HOOK" ] && out="$out vstack hook still present ($HOME/.claude/hooks/$CANARY_HOOK);"
  [ -e "$HOME/.claude/skills/$CANARY_SKILL" ] && out="$out vstack skill still present ($HOME/.claude/skills/$CANARY_SKILL/);"
  if [ -f "$HOME/.claude/settings.json" ]; then
    grep -q "$CANARY_HOOK" "$HOME/.claude/settings.json" 2>/dev/null && \
      out="$out settings.json still references $CANARY_HOOK;"
    grep -q "statusline.sh" "$HOME/.claude/settings.json" 2>/dev/null && \
      out="$out settings.json still points statusLine at statusline.sh;"
  fi
  [ -z "$out" ] && out="(no residue found)"
  printf '%s\n' "$out"
}

run_install()   { ( cd "$1" && bash ./install.sh )   >>"$LOG" 2>&1; }
run_uninstall() { ( cd "$SRC" && bash ./uninstall.sh --yes ) >>"$LOG" 2>&1; }

# =================================================================================================
hr; say "sequence 1: install -> uninstall"; hr
new_sandbox
LOG="$SBOX/log"
seed_user_state
run_install "$SRC"; i1=$?
run_uninstall; u1=$?
if [ "$i1" != 0 ] || [ "$u1" != 0 ]; then
  check "seq1: exit codes" "install=0 uninstall=0" "install=$i1 uninstall=$u1 (log: $LOG)" 1
else
  user_state_intact; usi=$?
  vstack_payload_gone; vpg=$?
  check "seq1: user state survives a clean install/uninstall cycle" \
    "settings.json foreignVendorKey, user-own-hook.sh, my-own-skill/ all intact" \
    "$( user_state_intact >/dev/null 2>&1 || echo one or more seeded artifacts missing/changed )" \
    "$usi"
  check "seq1: vstack payload fully removed after a single install/uninstall" \
    "no vstack hook/skill files, no dangling settings.json references" \
    "$(describe_residue)" \
    "$vpg"
fi
rm -rf "$SBOX"

# =================================================================================================
hr; say "sequence 1b: fresh HOME (no pre-existing settings.json) install -> uninstall"; hr
# Isolates a second mechanism from the same failure class: when settings.json does not exist
# before install, install.sh's back() has nothing to copy (it no-ops on a missing source), so
# uninstall's *literal* file restore never touches settings.json at all. The only thing that
# can still clean it is uninstall.sh's ownership-diff pass, which matches hook ownership by
# comparing live command basenames against basenames derived from the REPO'S RAW project-scope
# claude/settings.json template. That template quotes its command strings
# ("\"$CLAUDE_PROJECT_DIR/.claude/hooks/x.sh\""), so the derived basename carries a trailing
# literal `"` character and never matches the unquoted absolute path install.sh actually
# installs -- the match is permanently empty, independent of which backup is selected.
new_sandbox
LOG="$SBOX/log"
run_install "$SRC"; i1b=$?
run_uninstall; u1b=$?
if [ "$i1b" != 0 ] || [ "$u1b" != 0 ]; then
  check "seq1b: exit codes" "install=0 uninstall=0" "install=$i1b uninstall=$u1b (log: $LOG)" 1
else
  vstack_payload_gone; vpg1b=$?
  check "seq1b: uninstall on a fresh HOME leaves no dangling hook/statusLine references" \
    "settings.json has no hooks/statusLine after uninstall (scripts were just deleted)" \
    "$(describe_residue)" \
    "$vpg1b"
fi
rm -rf "$SBOX"

# =================================================================================================
hr; say "sequence 2: install -> install -> uninstall (the claimed P0)"; hr
new_sandbox
LOG="$SBOX/log"
seed_user_state
run_install "$SRC"; i2a=$?
sleep 1.1   # BK_BASE has second resolution; force install #2 into a distinct backup dir
run_install "$SRC"; i2b=$?
run_uninstall; u2=$?
if [ "$i2a" != 0 ] || [ "$i2b" != 0 ] || [ "$u2" != 0 ]; then
  check "seq2: exit codes" "install=0 install=0 uninstall=0" \
    "install1=$i2a install2=$i2b uninstall=$u2 (log: $LOG)" 1
else
  vstack_payload_gone; vpg2=$?
  check "seq2: install->install->uninstall removes vstack payload (not just restores install #1's copy)" \
    "no vstack hook/skill files, no dangling settings.json references" \
    "$(describe_residue)" \
    "$vpg2"
  user_state_intact; usi2=$?
  check "seq2: pre-vstack user state (settings key, hook, skill) still recoverable" \
    "settings.json foreignVendorKey, user-own-hook.sh, my-own-skill/ all intact" \
    "$( user_state_intact >/dev/null 2>&1 || echo one or more seeded artifacts missing/changed )" \
    "$usi2"
fi
rm -rf "$SBOX"

# =================================================================================================
hr; say "sequence 3: install vA -> install vB -> uninstall (two different commits)"; hr
# Do NOT move the branch in the shared checkout: check out an older tag into a disposable git
# worktree instead. Never `git fetch` (prune settings here nuke local tags) -- worktree add
# against an already-fetched local tag is enough.
VA_TAG=""
for t in $(git -C "$SRC" tag --sort=v:refname 2>/dev/null); do
  [ "$t" = "$(git -C "$SRC" describe --tags --exact-match 2>/dev/null)" ] && continue
  VA_TAG="$t"
done
WT=""
if [ -z "$VA_TAG" ]; then
  say "SKIP  [seq3] no older tag found distinct from HEAD -- cannot construct two versions"
else
  WT=$(mktemp -d)
  if git -C "$SRC" worktree add --detach --quiet "$WT" "$VA_TAG" >/dev/null 2>&1; then
    new_sandbox
    LOG="$SBOX/log"
    seed_user_state
    run_install "$WT"; i3a=$?
    sleep 1.1
    run_install "$SRC"; i3b=$?
    run_uninstall; u3=$?
    if [ "$i3a" != 0 ] || [ "$i3b" != 0 ] || [ "$u3" != 0 ]; then
      check "seq3: exit codes" "install=0 install=0 uninstall=0" \
        "install($VA_TAG)=$i3a install(HEAD)=$i3b uninstall=$u3 (log: $LOG)" 1
    else
      vstack_payload_gone; vpg3=$?
      check "seq3: install $VA_TAG -> install HEAD -> uninstall removes vstack payload" \
        "no vstack hook/skill files, no dangling settings.json references" \
        "$(describe_residue)" \
        "$vpg3"
    fi
    rm -rf "$SBOX"
  else
    say "SKIP  [seq3] could not create worktree for $VA_TAG"
  fi
  git -C "$SRC" worktree remove --force "$WT" >/dev/null 2>&1
  rm -rf "$WT"
fi

# =================================================================================================
hr; say "sequence 4: repeated uninstall (idempotency)"; hr
new_sandbox
LOG="$SBOX/log"
seed_user_state
run_install "$SRC"; i4=$?
run_uninstall; u4a=$?
run_uninstall; u4b=$?
if [ "$i4" != 0 ] || [ "$u4a" != 0 ] || [ "$u4b" != 0 ]; then
  check "seq4: exit codes" "install=0 uninstall=0 uninstall=0" \
    "install=$i4 uninstall1=$u4a uninstall2=$u4b (log: $LOG)" 1
else
  user_state_intact; usi4=$?
  check "seq4: a second uninstall does not corrupt the already-restored user state" \
    "settings.json foreignVendorKey, user-own-hook.sh, my-own-skill/ all intact" \
    "$( user_state_intact >/dev/null 2>&1 || echo one or more seeded artifacts missing/changed )" \
    "$usi4"
fi
rm -rf "$SBOX"

# =================================================================================================
hr; say "sequence 5: partially failed install -> uninstall"; hr
new_sandbox
LOG="$SBOX/log"
seed_user_state
mkdir -p "$HOME/.claude/skills"
chmod 555 "$HOME/.claude/skills"   # forces install.sh to fail partway through the skills loop
run_install "$SRC"; i5=$?
chmod 755 "$HOME/.claude/skills"
if [ "$i5" = 0 ]; then
  check "seq5: setup" "install.sh should fail partway (skills dir made read-only)" \
    "install.sh exited 0 -- the failure injection did not take, sequence not exercised" 1
else
  run_uninstall; u5=$?
  if [ "$u5" != 0 ]; then
    check "seq5: exit codes" "uninstall=0 after a partial install" "uninstall=$u5 (log: $LOG)" 1
  else
    user_state_intact; usi5=$?
    check "seq5: user state survives uninstall of a partially failed install" \
      "settings.json foreignVendorKey, user-own-hook.sh, my-own-skill/ all intact" \
      "$( user_state_intact >/dev/null 2>&1 || echo one or more seeded artifacts missing/changed )" \
      "$usi5"
    vstack_payload_gone; vpg5=$?
    check "seq5: uninstall cleans up whatever the partial install did write" \
      "no vstack hook/skill files, no dangling settings.json references" \
      "$(describe_residue)" \
      "$vpg5"
  fi
fi
rm -rf "$SBOX"

# =================================================================================================
hr
say "checks run: $CHECK_N   failed: $FAIL"
if [ "$FAIL" -gt 0 ]; then
  say "RESULT: FAIL -- uninstall.sh does not return the machine to its pre-vstack state (P0-1 live)"
else
  say "RESULT: PASS -- uninstall.sh returns the machine to its pre-vstack state in every sequence tried"
fi
exit "$FAIL"
