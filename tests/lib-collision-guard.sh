#!/usr/bin/env bash
# lib-collision-guard.sh — sourceable library for test harnesses that mutate the shared checkout.
#
# Two failure modes motivated this, both already recorded as having cost real work here:
#
# 1. A save/restore EXIT trap in a test harness deleted two agents' uncommitted work, because the
#    restore was unconditional: save original content, mutate the file, and on EXIT overwrite it
#    back to the original no matter what the file looks like by then. If a peer agent edited the
#    file while the harness was running — reasonably, since nothing told them it was borrowed —
#    their edit sat on top of the harness's mutation, and the unconditional restore discarded it
#    along with the mutation. cg_save/cg_checkpoint/cg_restore below fix this by refusing to
#    restore unless the file's current content still matches what the harness itself last wrote.
#
# 2. tests/gate-falsifiability.sh has no restore on SIGTERM at all (EXIT-only trap), so killing a
#    sweep mid-run — `pkill`, a timeout, Ctrl-C from a terminal that does not forward SIGTERM as
#    SIGINT — leaves the last mutation live in the tree. It happened: a killed sweep left a
#    mutation behind in claude/commands/test.md. cg_install_trap below installs on EXIT INT TERM
#    HUP together, the same set tests/plugin-manifests.sh already uses correctly.
#
# Separately: tests/gate-falsifiability.sh's collision lock is keyed on
# `git rev-parse --git-dir`, which returns a PER-WORKTREE path (.git/worktrees/<name> in a linked
# worktree) — verified empirically (see docs/worktree-collision-detection.md). Two agents in two
# worktrees of the same repo do not see each other's lock. `git rev-parse --git-common-dir` and
# `git worktree list` are both anchored on the repo's one shared .git, verified identical from
# every worktree of the same repo. cg_worktree_report below uses the shared anchor.
#
# Nothing here is wired into any existing harness (this is a sourceable library and a repro test,
# not a running gate) -- integration into tests/gate-falsifiability.sh is out of this file's
# ownership; see docs/worktree-collision-detection.md for the exact patch to hand to its owner.
set -uo pipefail

_cg_hash(){ # path
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1
  elif command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" 2>/dev/null | cut -d' ' -f1
  else cksum "$1" 2>/dev/null | tr ' ' '_'
  fi
}
# A missing file hashes to a fixed sentinel distinct from any real content hash, so
# save/checkpoint/restore all compose correctly around a file that does not exist yet.
_cg_hash_or_absent(){ [ -f "$1" ] && _cg_hash "$1" || printf 'ABSENT'; }

# cg_save(path): record the file's current content and hash before this harness's first mutation.
# Call once, before the first write. Backup lives at "$path.cg-orig"; state at "$path.cg-state".
cg_save(){
  local p="$1"
  if [ -f "$p" ]; then cp "$p" "$p.cg-orig"; else rm -f "$p.cg-orig"; : > "$p.cg-orig.absent"; fi
  _cg_hash_or_absent "$p" > "$p.cg-orighash"
  _cg_hash_or_absent "$p" > "$p.cg-lasthash"
}

# cg_checkpoint(path): call immediately after EVERY mutation this harness makes to $path. Records
# what "our own last write" looked like, which is the value cg_restore trusts.
cg_checkpoint(){ _cg_hash_or_absent "$1" > "$1.cg-lasthash"; }

# cg_restore(path): on EXIT/INT/TERM/HUP. Restores $path to its pre-cg_save content ONLY if the
# file's current content still equals what cg_checkpoint (or cg_save, if no checkpoint followed)
# last recorded. Otherwise something else wrote to the file since this harness's own last known
# state -- refuse, leave the file untouched, and say so on stderr naming the path. Exit status:
# 0 restored, 1 refused (foreign change detected), 2 nothing to restore (cg_save was never called).
cg_restore(){
  local p="$1"
  [ -f "$p.cg-orighash" ] || { return 2; }
  local now last
  now=$(_cg_hash_or_absent "$p")
  last=$(cat "$p.cg-lasthash" 2>/dev/null || cat "$p.cg-orighash" 2>/dev/null || echo UNKNOWN)
  if [ "$now" = "$last" ]; then
    if [ -f "$p.cg-orig.absent" ]; then rm -f "$p"; else mv "$p.cg-orig" "$p"; fi
    rm -f "$p.cg-orig" "$p.cg-orighash" "$p.cg-lasthash" "$p.cg-orig.absent"
    return 0
  else
    printf 'REFUSED restore: %s changed since this harness last wrote it (expected hash %s, found %s).\n' \
      "$p" "$last" "$now" >&2
    printf '        Not overwritten. This harness'\''s own saved copy is at %s if you need it;\n' "$p.cg-orig" >&2
    printf '        the current content on disk is someone else'\''s work -- leave it.\n' >&2
    return 1
  fi
}

# cg_install_trap(path...): arm EXIT, INT, TERM and HUP together, not EXIT alone. A trap on EXIT
# only does not fire on a SIGTERM that is not also converted to an exit by the shell (bash does
# run the EXIT trap after most signals it does NOT ignore, but a script killed hard -- SIGKILL, or
# a signal the shell has no default disposition to convert -- will not run any trap at all; INT
# TERM HUP are added explicitly so the common "somebody ran `kill $(pgrep ...)`" case is covered
# even where a bare `trap ... EXIT` would have been silently sufficient or silently was not).
cg_install_trap(){
  local paths=("$@")
  # shellcheck disable=SC2064 -- intentional: expand $paths now, not when the trap fires later.
  trap "$(printf 'cg_restore %q; ' "${paths[@]}")" EXIT INT TERM HUP
}

# cg_worktree_report(): names every OTHER worktree of this repo that is holding a live
# collision lock, what it is holding, and what to do. Anchored on --git-common-dir (shared across
# every worktree of one repo) rather than --git-dir (per-worktree; see the header comment). Prints
# one line per live collision found; prints nothing and returns 1 if none. A lock is "live" if its
# recorded PID answers to `kill -0`; a lock whose process is gone is stale and ignored, matching
# tests/gate-falsifiability.sh's own existing rule so this does not introduce a second policy.
cg_worktree_report(){
  local common found=0 lockfile pid name wtpath gitdirfile
  common=$(git rev-parse --git-common-dir 2>/dev/null) || return 1
  common=$(cd "$(dirname "$common")" 2>/dev/null && pwd)/$(basename "$common")
  # Every worktree's own git-dir lives under $common/worktrees/<name>, plus $common itself for
  # the main checkout -- both are where tests/gate-falsifiability.sh's lock (and any lock this
  # library's own callers use) is written, keyed by whichever git-dir that specific process saw.
  for lockfile in "$common"/vstack-*.lock "$common"/worktrees/*/vstack-*.lock; do
    [ -f "$lockfile" ] || continue
    pid=$(cat "$lockfile" 2>/dev/null)
    case "$pid" in ''|*[!0-9]*) continue ;; esac
    kill -0 "$pid" 2>/dev/null || continue
    # Resolve which checkout on disk owns this lock. A lock directly under $common is the main
    # checkout. A lock under $common/worktrees/<name>/ names a linked worktree; git's own
    # plumbing file worktrees/<name>/gitdir holds that worktree's absolute .../.git path -- one
    # dirname strips the trailing /.git to the worktree's own directory.
    case "$lockfile" in
      "$common"/worktrees/*)
        name=${lockfile#"$common"/worktrees/}; name=${name%%/*}
        gitdirfile="$common/worktrees/$name/gitdir"
        wtpath=$(cat "$gitdirfile" 2>/dev/null)
        wtpath=$(dirname "$wtpath" 2>/dev/null)
        [ -n "$wtpath" ] || wtpath="(worktree '$name', path unknown -- $gitdirfile unreadable)"
        ;;
      *) wtpath=$(dirname "$common") ;;
    esac
    found=1
    printf 'COLLISION: pid %s is holding %s in %s\n' "$pid" "$(basename "$lockfile")" "$wtpath"
    printf '           lock file: %s\n' "$lockfile"
    printf '           wait for it to finish, or `ps -p %s` to identify it before touching this tree.\n' "$pid"
  done
  [ "$found" = 1 ] && return 0 || return 1
}
