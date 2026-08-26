#!/usr/bin/env bash
# backup-self-claim.sh — regression test: does install.sh still copy a user's pre-existing file
# into the backup directory before overwriting it?
#
# The defect this pins, shipped in 1.46.0 and caught by CI, not by the gate:
#
#   back(){ ...
#     own "$1"                                                    # writes $1 into $OWNED_PATHS
#     ...
#     if [ -f "$OWNED_PATHS" ] && grep -qxF "$1" "$OWNED_PATHS"; then return 0; fi
#
# The guard's stated intent is "an EARLIER install already claimed this path, so it is ours and
# must not be recorded as the user's". Its implementation reads the record live -- and back()'s
# own own() call, two lines above, has just written $1 into that record. So the guard matched
# every path on every run and back() returned before its `cp`. Nothing was ever backed up, on a
# fresh machine or otherwise, and uninstall had nothing to restore.
#
# What makes it worth a file of its own: `$BK` was still created, still announced on the last
# line of a successful install ("backup: /Users/you/.config/agents/backups/install-..."), and
# still named in abort_note's promise that "every file this run touched was copied there first".
# A directory exists at that path. It is empty. Every check that asked whether the install
# succeeded said yes.
#
# Runs one real install into a throwaway HOME. No network, no model calls.
# Usage: bash tests/repro/backup-self-claim.sh   -- exit 0 clean, 1 while the defect is live.
set -uo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FAIL=0
H=$(mktemp -d)
trap 'rm -rf "$H"' EXIT

mkdir -p "$H/.claude"
USER_SETTINGS="$H/.claude/settings.json"
printf '{"theirKey":"do not lose me"}\n' > "$USER_SETTINGS"
USER_CLAUDE="$H/.claude/CLAUDE.md"
printf 'their own policy file, written before vstack existed\n' > "$USER_CLAUDE"

# The default profile, not --profile=core: core does not install CLAUDE.md at all, so it never
# overwrites the user's and there is correctly nothing to back up. Asserting a copy exists under
# core would be asserting a backup of a file nothing touched.
out=$(env HOME="$H" VSTACK_ASSUME_YES=1 bash "$SRC/install.sh" 2>&1); rc=$?
BK=$(printf '%s\n' "$out" | sed -n 's/^backup: //p' | tail -1)

check(){ # <name> <ok?> <detail>
  if [ "$2" = 0 ]; then printf 'ok    %s\n' "$1"
  else printf 'FAIL  %s\n      %s\n' "$1" "$3"; FAIL=$((FAIL + 1)); fi
}

if [ "$rc" -ne 0 ]; then
  printf 'FAIL  install.sh exited %s; nothing else could be measured\n' "$rc"
  printf '%s\n' "$out" | tail -20
  exit 1
fi

check "install.sh names a backup directory on its last lines" \
      "$([ -n "$BK" ] && echo 0 || echo 1)" \
      "no 'backup: <path>' line in the output"

check "the backup directory it names exists" \
      "$([ -n "$BK" ] && [ -d "$BK" ] && echo 0 || echo 1)" \
      "install.sh said backup: $BK, and no directory is there"

# The defect proper. Both files existed before the install and both were overwritten by it, so
# both must be under $BK/files/. A pre-existing settings.json is the one every user has.
for rel in .claude/settings.json .claude/CLAUDE.md; do
  copy="$BK/files/$rel"
  check "back() copied the user's pre-existing $rel" \
        "$([ -f "$copy" ] && echo 0 || echo 1)" \
        "$copy does not exist; the install overwrote $H/$rel with no copy of what was there"
done

# Content, not just presence: a copy taken AFTER the overwrite is not a backup either.
copy="$BK/files/.claude/CLAUDE.md"
if [ -f "$copy" ]; then
  check "the copy holds the user's bytes, not vstack's" \
        "$(grep -q 'written before vstack existed' "$copy" && echo 0 || echo 1)" \
        "$copy exists but does not contain the user's original text"
fi

# The guard is meant to fire for a path an EARLIER run installed. Prove it still does: vstack's
# own hook was written by this run, so a second install must not record it as the user's.
out2=$(env HOME="$H" VSTACK_ASSUME_YES=1 bash "$SRC/install.sh" 2>&1)
BK2=$(printf '%s\n' "$out2" | sed -n 's/^backup: //p' | tail -1)
hook=".claude/hooks/verify-gate.sh"
if [ -f "$H/$hook" ]; then
  check "a second install does not launder vstack's own payload into the backup" \
        "$([ ! -f "$BK2/files/$hook" ] && echo 0 || echo 1)" \
        "$BK2/files/$hook exists; a later uninstall would restore vstack's own hook as if the user had written it"
fi

printf '\n%s check(s) failed\n' "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
