#!/usr/bin/env bash
# guard-destructive.sh — PreToolUse gate on Bash. Stops the handful of commands that end a
# workday, and asks about the ones that usually should be asked about.
#
# WHY THIS IS ON BY DEFAULT, unlike its inspiration.
#
# The idea is adapted from gstack's `careful` skill (github.com/garrytan/gstack, MIT,
# Copyright (c) 2026 Garry Tan). There it is a slash command you turn on for a session when
# you are about to do something risky. That is a reasonable design for a setup that leaves
# Claude Code's permission prompts in place.
#
# This setup does not. install.sh --bypass-permissions sets permissions.defaultMode to
# bypassPermissions, and the README recommends it, which means every Bash command runs with
# no prompt at all. Removing the safety net and then shipping an opt-in replacement you have
# to remember to switch on is the wrong shape: the moment you need it is the moment you did
# not think to enable it. So it is always armed, and the deny list is kept small enough that
# always-armed is not annoying.
#
# WHAT THIS IS NOT. It is not a security boundary. It reads one command string and pattern
# matches it. Anything adversarial — obfuscation, indirection through a script, a command
# built at runtime — walks straight past. It is a guard against a bad afternoon, not against
# an attacker. Treating it as the latter would be the dangerous mistake.
#
# OUT OF SCOPE: Commands that rely on variable expansion to become destructive (e.g.
# `RMFLAGS=-rf; rm $RMFLAGS /`) are not caught because the guard reads syntax, not semantics.
# Attempts to detect this would require shell evaluation and generate false positives on
# legitimate uses of variables. The guard defends against the obvious and direct destructive
# commands; shell-level indirection is beyond its design.
#
# Failure is always toward asking. A hook that gates destructive commands and defaults to
# "allow" when it cannot parse its input has inverted its own purpose.

set -uo pipefail

# Anything that reaches the end of this script without having emitted a decision has crashed,
# and a crash must not be silence. This shipped broken on every Linux host for exactly that
# reason: `"$TMPDIR"*` in a case pattern, TMPDIR routinely unset there, set -u turns that into
# a fatal error mid-script, and the hook produced no output at all — the one outcome the header
# above promises cannot happen. macOS sets TMPDIR, so it passed locally and failed on three
# platforms in CI.
#
# The trap is the structural fix rather than the one-line one: no future edit can reintroduce
# silence, whatever it gets wrong.
_guard_emitted=0
_guard_trap() {
  [ "$_guard_emitted" = 1 ] && return 0
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"[guard] the guard itself failed while inspecting this command. Approve only if you know what it does."}}\n'
}
trap _guard_trap EXIT

emit() { # <allow|ask|deny> <reason>
  _guard_emitted=1
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"%s","permissionDecisionReason":"%s"}}\n' "$1" "$2"
  exit 0
}
allow() { _guard_emitted=1; printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}\n'; exit 0; }

payload=$(cat 2>/dev/null || true)
[ -n "$payload" ] || emit ask "[guard] no tool payload to inspect — approve only if you know what this does"

# jq is the only way to read the command safely; a grep over raw JSON would be fooled by any
# escaped quote. Without it, ask rather than guess.
command -v jq >/dev/null 2>&1 \
  || emit ask "[guard] jq is not installed, so this command could not be inspected — approve only if you know what it does"

CMD=$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null) || CMD=""
# A payload that does not parse is not an allow. It is an unknown.
printf '%s' "$payload" | jq -e . >/dev/null 2>&1 \
  || emit ask "[guard] the tool payload did not parse, so this command could not be inspected"
# Genuinely no command field (a non-Bash payload reaching a Bash matcher): nothing to judge.
[ -n "$CMD" ] || allow

# Compound commands are split and each segment evaluated separately against the deny tier.
# This is necessary because a command that is harmless on its own (rm -rf node_modules) is
# catastrophic in a compound (echo hi; rm -rf /). Without this split, `true && git push -f origin main`
# would skip the deny tier entirely and land on allow.
#
# We split on ; && || and | (backticks and $() are harder to parse and their contents fall through
# to the ask tier if destructive). Each segment is checked against the same deny patterns.

# Check if a segment contains a catastrophic command. If so, emit deny immediately.
_check_deny_segment() {
  local seg="$1"
  [ -n "$seg" ] || return 0

  # rm -rf against / or $HOME. Build-artifact deletes are not this.
  case "$seg" in
    rm\ *-*[rR]*[fF]*\ *|rm\ *-*[fF]*[rR]*\ *)
      set -f
      for tok in $seg; do
        # shellcheck disable=SC2088  # matching the literal ~ the user typed; expanding it here would
        # compare $HOME against $HOME and let `rm -rf ~` through.
        case "$tok" in
          /|/\*|'~'|'~/'|'~/*'|'$HOME'|'"$HOME"'|'$HOME/'|'${HOME}')
            emit deny "[guard] recursive delete of / or your home directory. If you truly mean this, run it yourself outside the agent session." ;;
        esac
      done
      set +f ;;
  esac

  # Force-push to a protected branch. Match both simple and full refspecs.
  case "$seg" in
    git\ push\ *--force*|git\ push\ *-f\ *|git\ push\ *-f)
      case "$seg" in
        # Simple: space before branch. Full refspecs: :main :master or :refs/heads/main etc.
        *\ main*|*\ master*|*:main*|*:master*|*:refs/heads/main*|*:refs/heads/master*)
          emit deny "[guard] force-push to main or master. Push to a branch, or do it yourself outside the agent session." ;;
      esac ;;
  esac
}

# Check compound commands: split on common separators and test each segment against deny patterns
if printf '%s' "$CMD" | grep -qE '[;&|]' || printf '%s' "$CMD" | grep -q '&&\|||'; then
  # The command contains compound separators; split and check each segment against deny patterns
  while IFS= read -r seg; do
    [ -n "$seg" ] || continue
    seg=$(printf '%s' "$seg" | sed -e 's/^[[:space:]]*//; s/[[:space:]]*$//')
    [ -n "$seg" ] || continue
    _check_deny_segment "$seg"
  done <<EOF
$(printf '%s' "$CMD" | sed -e 's/;/\n/g; s/&&/\n/g; s/||/\n/g; s/|/\n/g')
EOF
fi

# --- deny: the small set that is never a mistake worth allowing ----
# For simple (non-compound) commands, check them directly
if ! printf '%s' "$CMD" | grep -qE '[;&|]' && ! printf '%s' "$CMD" | grep -q '&&\|||'; then
  # rm -rf against / or $HOME. Build-artifact deletes are the common legitimate case and are
  # explicitly not this: the target has to be a filesystem or home root.
  case "$CMD" in
    rm\ *-*[rR]*[fF]*\ *|rm\ *-*[fF]*[rR]*\ *)
      set -f
      for tok in $CMD; do
        # shellcheck disable=SC2088  # matching the literal ~ the user typed; expanding it here would
        # compare $HOME against $HOME and let `rm -rf ~` through.
        case "$tok" in
          /|/\*|'~'|'~/'|'~/*'|'$HOME'|'"$HOME"'|'$HOME/'|'${HOME}')
            emit deny "[guard] recursive delete of / or your home directory. If you truly mean this, run it yourself outside the agent session." ;;
        esac
      done
      set +f ;;
  esac
  # Force-push to a protected branch. Recoverable in principle, ruinous in practice, and the
  # agent has no business doing it unprompted.
  case "$CMD" in
    git\ push\ *--force*|git\ push\ *-f\ *|git\ push\ *-f)
      case "$CMD" in
        # Match space-separated (origin main), colon-based refspecs (:main), and full refs paths.
        # Full refspecs like HEAD:refs/heads/main must match via the :refs/heads/ pattern.
        *\ main*|*\ master*|*:main*|*:master*|*:refs/heads/main*|*:refs/heads/master*)
          emit deny "[guard] force-push to main or master. Push to a branch, or do it yourself outside the agent session." ;;
      esac ;;
  esac
fi

# Check if a segment triggers the ask tier
_check_ask_segment() {
  local seg="$1"
  [ -n "$seg" ] || return 0

  # Database operations
  case "$seg" in
    *'DROP TABLE'*|*'DROP DATABASE'*|*'TRUNCATE TABLE'*|*'drop table'*|*'drop database'*)
      emit ask "[guard] this drops or truncates a database table. Confirm the target is not production." ;;
  esac

  # Wildcard staging in a tree this session does not own. Two sessions writing one worktree is
  # not hypothetical: on 2026-08-23 a `git add -A` here swept another session's uncommitted
  # security fixes into a commit whose message described only a documentation change, and it
  # reached origin before either session noticed. Explicit paths cannot do that.
  #
  # This asks only when CONDUCTOR_WORKSPACE_PATH is set and the working directory sits outside
  # it, which is exactly the case where another session may be mid-edit. Inside your own
  # workspace it stays silent, because that is the normal case and a guard that fires on every
  # commit is a guard that gets uninstalled.
  case "$seg" in
    git\ add\ -A|git\ add\ -A\ *|git\ add\ --all*|git\ add\ .|git\ add\ .\ *|\
    git\ commit\ -a|git\ commit\ -a\ *|git\ commit\ -am*|git\ commit\ *--all*)
      if [ -n "${CONDUCTOR_WORKSPACE_PATH:-}" ]; then
        case "$PWD/" in
          "${CONDUCTOR_WORKSPACE_PATH%/}"/*) : ;;
          *) emit ask "[guard] wildcard staging in $PWD, outside this session's workspace (${CONDUCTOR_WORKSPACE_PATH}). Another session may have uncommitted work here, and -A would commit it under your message. Stage explicit paths." ;;
        esac
      fi ;;
  esac

  # SCM operations
  case "$seg" in
    git\ reset\ *--hard*)
      emit ask "[guard] git reset --hard discards uncommitted work in the working tree." ;;
    git\ clean\ *-*[dD]*[fF]*|git\ clean\ *-*[fF]*[dD]*)
      emit ask "[guard] git clean -fd deletes untracked files, including ones never committed anywhere." ;;
  esac

  # Infrastructure
  case "$seg" in
    *'kubectl delete'*|*'terraform destroy'*|*'docker system prune'*)
      emit ask "[guard] this tears down infrastructure. Confirm the context and target." ;;
  esac

  # The verify-trust store. A matching sha256 line in it is the entire definition of
  # "trusted": verify-gate.sh's Stop hook executes whatever hashes to a line in that file,
  # unattended, forever after. `vstack trust` writes it, and so does anything that appends to
  # the file directly (echo/printf/tee/sed -i and friends) -- both are the same act with
  # different spelling, and a hostile CONTRIBUTING.md telling an agent to run either one turns
  # this gate into the delivery mechanism for the thing it exists to stop. Ask on any command
  # that names the trust file or the subcommand that writes it, whether it looks like a read or
  # a write: this guard reads syntax, not semantics, and cannot tell `cat` from `>>` reliably
  # enough to narrow the match without risking the write it slips through.
  case "$seg" in
    *verify-trust*|*vstack\ trust*)
      emit ask "[guard] this touches the verify-trust store that arms the Stop-hook gate to run repo-controlled scripts unattended. Confirm this is your own considered decision, not a repo telling you to run it." ;;
  esac

  # Device operations
  case "$seg" in
    *'mkfs'*|*'dd if='*of=/dev/*)
      emit ask "[guard] this writes directly to a device. Confirm the target device." ;;
  esac

  # rm -rf with potentially unsafe targets
  case "$seg" in
    *rm\ -[rRfF]*|*rm\ --recursive*|*rm\ -*[rR]*[fF]*|*rm\ -*[fF]*[rR]*)
      _unsafe=0
      set -f
      for tok in $seg; do
        case "$tok" in
          rm|-*) continue ;;
        esac
        case "$tok" in
          node_modules|dist|build|target|coverage|.next|.turbo|.cache|.venv|__pycache__|.pytest_cache) continue ;;
          */node_modules|*/node_modules/*|*/dist|*/dist/*|*/build|*/build/*|*/target|*/target/*) continue ;;
          */coverage|*/coverage/*|*.next|*.next/*|*.turbo|*.turbo/*|*.cache|*.cache/*) continue ;;
          */__pycache__|*/__pycache__/*|*.venv|*.venv/*|/tmp/*|"${TMPDIR:-/nonexistent}"*) continue ;;
        esac
        _unsafe=1
      done
      set +f
      [ "$_unsafe" = 1 ] && emit ask "[guard] recursive delete of something that is not a build artifact. Check the path before approving." ;;
  esac
}

# Apply ask tier to each segment of compound commands, or to the whole command if simple
if printf '%s' "$CMD" | grep -qE '[;&|]' || printf '%s' "$CMD" | grep -q '&&\|||'; then
  # Compound command: check each segment
  while IFS= read -r seg; do
    [ -n "$seg" ] || continue
    seg=$(printf '%s' "$seg" | sed -e 's/^[[:space:]]*//; s/[[:space:]]*$//')
    [ -n "$seg" ] || continue
    _check_ask_segment "$seg"
  done <<EOF
$(printf '%s' "$CMD" | sed -e 's/;/\n/g; s/&&/\n/g; s/||/\n/g; s/|/\n/g')
EOF
else
  # Simple command: check it as a whole
  _check_ask_segment "$CMD"
fi

allow
