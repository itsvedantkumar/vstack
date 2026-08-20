#!/usr/bin/env bash
# preflight.sh — converge this machine, then run every gate. Use before committing.
#
# This exists because the same mistake happened twice in one session: edit a hook or a skill in
# the repo, run the gates, watch `doctor --drift` go red, and spend a minute rediscovering that
# the installed copy under ~/.claude was simply stale. Nothing was broken either time. The
# drift check was correctly reporting that the repo and the machine had diverged, because they
# had, because the edit had not been installed yet.
#
# Doing it by hand in the right order is a step that gets skipped exactly when there is
# something more interesting to think about, so it is a script.
#
# It runs install.sh against the real HOME on purpose — that is what converging means here, and
# every file it touches is backed up first. The install matrix is the thing that runs in
# throwaway homes; this is not that.

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

FAIL=0
step() { # <label> <command...>
  printf '%-34s' "$1"
  if "${@:2}" >/tmp/preflight-$$.log 2>&1; then
    printf 'ok\n'
  else
    printf 'FAILED\n'
    sed 's/^/    /' /tmp/preflight-$$.log | tail -20
    FAIL=1
  fi
  rm -f /tmp/preflight-$$.log
}

# Converge first. Without this the drift check reports an edit you have not installed as a
# problem with the machine, which it is not.
step "install (converge this machine)" ./install.sh

step "verify.sh"              ./.claude/verify.sh
step "gate-falsifiability.sh" ./tests/gate-falsifiability.sh
step "install-matrix.sh"      ./tests/install-matrix.sh
step "doctor"                 ./bin/doctor
step "doctor --drift"         ./bin/doctor --drift

# Untracked files are invisible to the gate's secret and home-path scanners, which read
# `git grep`. A clean run before `git add` proves nothing about what is about to be pushed.
if command -v git >/dev/null 2>&1; then
  untracked=$(git ls-files --others --exclude-standard | head -5)
  if [ -n "$untracked" ]; then
    printf '%-34s%s\n' "untracked files present" "stage them and re-run — the scanners only read tracked files"
    printf '    %s\n' $untracked
    FAIL=1
  fi
fi

echo
[ "$FAIL" -eq 0 ] && echo "PREFLIGHT OK — safe to commit" || echo "PREFLIGHT FAILED"
exit "$FAIL"
