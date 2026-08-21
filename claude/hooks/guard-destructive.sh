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

# Compound commands are not decomposed. `a && rm -rf /` would need real shell parsing to judge,
# and a half-parse that misreads it is worse than no parse, so anything with a separator falls
# through to the pattern families below rather than reaching the deny tier.
SIMPLE=1
case "$CMD" in
  *';'*|*'&&'*|*'||'*|*'|'*|*'`'*|*'$('*|*$'\n'*) SIMPLE=0 ;;
esac

# --- deny: the small set that is never a mistake worth allowing -----------------------------
# Deliberately tiny. Every entry is something with no plausible legitimate use from an agent
# session, and each is only denied in its unambiguous simple form.
if [ "$SIMPLE" = 1 ]; then
  # rm -rf against / or $HOME. Build-artifact deletes are the common legitimate case and are
  # explicitly not this: the target has to be a filesystem or home root.
  case "$CMD" in
    rm\ *-*[rR]*[fF]*\ *|rm\ *-*[fF]*[rR]*\ *)
      for tok in $CMD; do
        # shellcheck disable=SC2088  # matching the literal ~ the user typed; expanding it here would
        # compare $HOME against $HOME and let `rm -rf ~` through.
        case "$tok" in
          /|/\*|'~'|'~/'|'$HOME'|'"$HOME"'|'$HOME/'|'${HOME}')
            emit deny "[guard] recursive delete of / or your home directory. If you truly mean this, run it yourself outside the agent session." ;;
        esac
      done ;;
  esac
  # Force-push to a protected branch. Recoverable in principle, ruinous in practice, and the
  # agent has no business doing it unprompted.
  case "$CMD" in
    git\ push\ *--force*|git\ push\ *-f\ *|git\ push\ *-f)
      case "$CMD" in
        # `* main*` already covers `*origin main`, and `* master*` covers `*origin master`;
        # both were listed and neither could ever be reached. The colon forms are not redundant:
        # `git push --force origin HEAD:main` contains no space before "main".
        *\ main*|*\ master*|*:main*|*:master*)
          emit deny "[guard] force-push to main or master. Push to a branch, or do it yourself outside the agent session." ;;
      esac ;;
  esac
fi

# --- ask: destructive families that are usually deliberate but sometimes are not -------------
# These stay overridable on purpose. The cost of a wrong deny here is a blocked legitimate
# command and an annoyed human, which is how a guard gets switched off for good.
case "$CMD" in
  *'DROP TABLE'*|*'DROP DATABASE'*|*'TRUNCATE TABLE'*|*'drop table'*|*'drop database'*)
    emit ask "[guard] this drops or truncates a database table. Confirm the target is not production." ;;
  git\ reset\ *--hard*)
    emit ask "[guard] git reset --hard discards uncommitted work in the working tree." ;;
  git\ clean\ *-*[dD]*[fF]*|git\ clean\ *-*[fF]*[dD]*)
    emit ask "[guard] git clean -fd deletes untracked files, including ones never committed anywhere." ;;
  *'kubectl delete'*|*'terraform destroy'*|*'docker system prune'*)
    emit ask "[guard] this tears down infrastructure. Confirm the context and target." ;;
  *'mkfs'*|*'dd if='*of=/dev/*)
    emit ask "[guard] this writes directly to a device. Confirm the target device." ;;
esac

# rm -rf on anything else is worth a beat, unless every target is clearly a build artifact.
#
# Matched anywhere in the string, not just at the start. An anchored pattern let
# `echo x && rm -rf /` through untouched: the deny tier skips compound commands by design,
# and an anchored ask tier then never looked at it either, so the most obvious way to phrase
# the worst command in the file was the one shape that reached "allow".
#
# Targets are tokenised rather than substring-matched. `*/dist*` did not match a bare `dist`,
# so `rm -rf dist` prompted every time — and a guard that interrupts routine work is a guard
# that gets switched off. Checking each token also means one dangerous target among safe ones
# still asks, instead of a single `node_modules` anywhere in the line excusing the whole command.
case "$CMD" in
  *rm\ -[rRfF]*|*rm\ --recursive*|*rm\ -*[rR]*[fF]*|*rm\ -*[fF]*[rR]*)
    _unsafe=0
    for tok in $CMD; do
      case "$tok" in
        rm|-*) continue ;;                           # the command and its flags (-* covers --*)
      esac
      case "$tok" in
        node_modules|dist|build|target|coverage|.next|.turbo|.cache|.venv|__pycache__|.pytest_cache) continue ;;
        */node_modules|*/node_modules/*|*/dist|*/dist/*|*/build|*/build/*|*/target|*/target/*) continue ;;
        */coverage|*/coverage/*|*.next|*.next/*|*.turbo|*.turbo/*|*.cache|*.cache/*) continue ;;
        */__pycache__|*/__pycache__/*|*.venv|*.venv/*|/tmp/*|"${TMPDIR:-/nonexistent}"*) continue ;;
      esac
      _unsafe=1
    done
    [ "$_unsafe" = 1 ] && emit ask "[guard] recursive delete of something that is not a build artifact. Check the path before approving." ;;
esac

allow
