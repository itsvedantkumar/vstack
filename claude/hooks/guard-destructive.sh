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

# Quoting must not change a verdict. This hook compares the token the operator typed against
# literal patterns, so `node_modules` matched the allowlist and `"node_modules"` did not -- the
# quote characters are part of the token here, not shell syntax we ever consumed. That cut both
# ways: every quoted build-artifact delete prompted, which is how a guard gets turned off, and
# four quoted spellings of the home directory reached `ask` while the bare ones were denied.
#
# Stripping quotes wherever they sit, rather than only at the ends, is what handles `"$HOME"/*`
# and `"/tmp"/x`. Pure parameter expansion, no subshell: this runs before every Bash command.
_gd_unquote() { # <token> -> the token with every ' and " removed
  _u=$1
  while :; do
    case "$_u" in
      *[\"\']*) _u="${_u%%[\"\']*}${_u#*[\"\']}" ;;
      *) break ;;
    esac
  done
  printf '%s' "$_u"
}

emit() { # <allow|ask|deny> <reason>
  _guard_emitted=1
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"%s","permissionDecisionReason":"%s"}}\n' "$1" "$2"
  exit 0
}
allow() { _guard_emitted=1; printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}\n'; exit 0; }

# emit_unattended_ask <reason> — for the subset of the ask tier that has no legitimate
# unattended-agent use: destroying another session's uncommitted work. `ask` only means anything
# if a human is there to see it. Measured live, twice, in this session under bypassPermissions
# (this bundle's shipped default — install.sh --bypass-permissions, README recommends it):
# `git reset --hard` got `ask` and ran anyway, rc=0, no prompt, no block; `git push --force`
# got `deny` and was actually blocked. `ask` is decoration under bypass; `deny` bites.
#
# permission_mode arrives on the PreToolUse payload (confirmed against the live installed hook
# this session, not assumed from docs — see docs/guard-enforcement-gap.md). Its observed/known
# values are default, acceptEdits, plan (a human can see and act on a prompt in all three) and
# bypassPermissions (nothing prompts, ever). Only bypassPermissions escalates. An absent or
# unrecognized value is not treated as "safe to escalate" or "safe to leave as ask" by
# assumption — it stays exactly today's ask decision, with the reason saying plainly that
# enforceability could not be confirmed, rather than silently guessing either way.
emit_unattended_ask() { # <reason>
  case "${PMODE:-}" in
    bypassPermissions)
      emit deny "[guard] $1 This session is in bypassPermissions mode, where an 'ask' decision is auto-approved with nobody to see it — for this command that is the same as allow. Denied instead. If you mean this, run it yourself outside the agent session." ;;
    default|acceptEdits|plan)
      emit ask "[guard] $1" ;;
    *)
      emit ask "[guard] $1 (permission_mode was not present on this payload, so whether a human will see this ask could not be confirmed; treating it as visible rather than guessing)" ;;
  esac
}

payload=$(cat 2>/dev/null || true)
[ -n "$payload" ] || emit ask "[guard] no tool payload to inspect — approve only if you know what this does"

# jq is the only way to read the command safely; a grep over raw JSON would be fooled by any
# escaped quote. Without it, ask rather than guess.
command -v jq >/dev/null 2>&1 \
  || emit ask "[guard] jq is not installed, so this command could not be inspected — approve only if you know what it does"

CMD=$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null) || CMD=""
PMODE=$(printf '%s' "$payload" | jq -r '.permission_mode // empty' 2>/dev/null) || PMODE=""
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
# We split on ; && || and | -- but only where they are real shell separators, not where they
# appear as ordinary characters inside a quoted argument or a heredoc. A `;` typed as punctuation
# in a commit message ("...blocked; git reset --hard got...") is not a separator, and treating it
# as one manufactured a phantom segment that began at the next word; when that word matched an
# anchored ask-tier pattern (git reset, git clean, git stash, ...), the guard denied a sentence
# describing the command, not the command. Quote-tracking alone was not enough: this repo's own
# mandated multi-line commit convention is `git commit -m "$(cat <<'EOF' ... EOF)"`, and a heredoc
# body is verbatim text with no quote-matching semantics of its own -- treating every `"` inside
# it as a toggle of the OUTER `-m "..."` quote desyncs on the first unrelated `"` the prose
# contains, which any paragraph describing a quoting bug reliably does. So heredocs (`<<DELIM`,
# `<<'DELIM'`, `<<"DELIM"`, `<<-DELIM`) are detected and their entire body, up to and including the
# line that is exactly DELIM, is treated as one opaque span: not scanned for quotes or separators,
# appended to the current segment verbatim. docs/guard-enforcement-gap.md has the incident.
#
# This is still not full shell parsing, and does not claim to be: escaped quotes (`\"` inside a
# double-quoted string) are not tracked, and backticks / bare $(...) without a heredoc inside are
# still opaque only in the pre-existing sense -- their contents fall through to the ask tier if
# destructive, same as before this change, not specially detected as a nested context. A literal
# `<<WORD` inside an ordinary quoted argument (rare, and not this repo's own convention) is treated
# as a heredoc marker too; the failure mode is over-widening what counts as opaque text, which can
# only make the guard MORE permissive of anchored patterns hiding inside it, never blind to the
# unanchored families (rm/DB/infra/device), which scan the full segment regardless of internal
# structure. That tradeoff is deliberate and disclosed, not an accident of the implementation.
_gd_heredoc_skip() { # <remaining-text-after-the-marker> <delimiter> -> bytes through the terminator line (or full length if the delimiter never appears on its own line)
  local tail="$1" delim="$2" n total
  n=$(printf '%s' "$tail" | grep -n -x -F -- "$delim" 2>/dev/null | head -n1 | cut -d: -f1)
  if [ -z "$n" ]; then
    printf '%s' "${#tail}"
    return
  fi
  total=$(printf '%s' "$tail" | awk -v n="$n" 'NR<=n{c+=length($0)+1} END{print c+0}')
  printf '%s' "$total"
}

_gd_split() { # <cmd> -> one segment per line, respecting single/double quotes and heredocs
  local cmd="$1" i=0 len ch nxt inq='' buf='' rest matched delim skip
  len=${#cmd}
  while [ "$i" -lt "$len" ]; do
    ch="${cmd:$i:1}"
    if [ "$ch" = '<' ] && [ "${cmd:$((i+1)):1}" = '<' ]; then
      rest="${cmd:$((i+2))}"
      if [[ "$rest" =~ ^-?[[:space:]]*(\'[A-Za-z_][A-Za-z0-9_]*\'|\"[A-Za-z_][A-Za-z0-9_]*\"|[A-Za-z_][A-Za-z0-9_]*) ]]; then
        matched="${BASH_REMATCH[0]}"
        delim="$matched"
        delim="${delim#-}"; delim="${delim# }"
        delim="${delim%\'}"; delim="${delim#\'}"
        delim="${delim%\"}"; delim="${delim#\"}"
        buf="$buf<<$matched"
        i=$((i + 2 + ${#matched}))
        rest="${cmd:$i}"
        skip=$(_gd_heredoc_skip "$rest" "$delim")
        buf="$buf${rest:0:$skip}"
        i=$((i + skip))
        continue
      fi
    fi
    if [ -n "$inq" ]; then
      buf="$buf$ch"
      [ "$ch" = "$inq" ] && inq=''
      i=$((i+1)); continue
    fi
    case "$ch" in
      \'|\") inq="$ch"; buf="$buf$ch" ;;
      ';') printf '%s\n' "$buf"; buf='' ;;
      '&')
        nxt="${cmd:$((i+1)):1}"
        if [ "$nxt" = '&' ]; then printf '%s\n' "$buf"; buf=''; i=$((i+1))
        else buf="$buf$ch"; fi ;;
      '|')
        nxt="${cmd:$((i+1)):1}"
        if [ "$nxt" = '|' ]; then printf '%s\n' "$buf"; buf=''; i=$((i+1))
        else printf '%s\n' "$buf"; buf=''; fi ;;
      *) buf="$buf$ch" ;;
    esac
    i=$((i+1))
  done
  printf '%s\n' "$buf"
}

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
        # Normalise, then compare. The list this replaced was nine literals -- `/`, `/*`, `~`,
        # `~/`, `~/*`, `$HOME`, `"$HOME"`, `$HOME/`, `${HOME}` -- and it still let `$HOME/*`,
        # `"$HOME"/*`, `"${HOME}"` and `${HOME}/*` through to the ask tier, while `~/*` two
        # entries along was denied. Same directory, same outcome, opposite verdict, decided by
        # which way the operator happened to type it. Enumerating spellings loses to whoever
        # thinks of a tenth one, so this reduces the token instead: drop every quote wherever it
        # sits, fold ${HOME} onto $HOME, then remove one trailing `/*` or `/`.
        _t=$(_gd_unquote "$tok")
        case "$_t" in '${HOME}'*) _t="\$HOME${_t#'${HOME}'}" ;; esac
        _t="${_t%/\*}"; _t="${_t%/}"
        case "$_t" in
          # `` is what `/` and `/*` reduce to once the trailing slash comes off.
          ''|'~'|'$HOME')
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

# --- deny: the small set that is never a mistake worth allowing ----
# Always split via _gd_split and check every resulting segment. A command with no real top-level
# separator yields exactly one segment (the whole trimmed command), so this covers the "simple"
# case too without a second, hand-duplicated copy of the same patterns to keep in sync by hand.
while IFS= read -r seg; do
  [ -n "$seg" ] || continue
  seg=$(printf '%s' "$seg" | sed -e 's/^[[:space:]]*//; s/[[:space:]]*$//')
  [ -n "$seg" ] || continue
  _check_deny_segment "$seg"
done <<EOF
$(_gd_split "$CMD")
EOF

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
          *) emit_unattended_ask "wildcard staging in $PWD, outside this session's workspace (${CONDUCTOR_WORKSPACE_PATH}). Another session may have uncommitted work here, and -A would commit it under your message. Stage explicit paths." ;;
        esac
      fi ;;
  esac

  # Bare `git stash` (no explicit pathspec): stashes every uncommitted change in the working
  # tree, including another session's. This is the exact command that scooped up four agents'
  # uncommitted files in this checkout on 2026-08-26 (docs/worktree-collision-detection.md).
  # `git stash push -- <path>` / `git stash save -- <path>` with an explicit pathspec is left
  # alone, same reasoning as explicit-path `git add`. Read-only or apply-only subcommands
  # (pop/apply/list/show/branch) are not stashing anything new and are not matched here.
  case "$seg" in
    git\ stash|git\ stash\ push|git\ stash\ save|\
    git\ stash\ -u|git\ stash\ --include-untracked|\
    git\ stash\ push\ *|git\ stash\ save\ *)
      case "$seg" in
        *\ --\ *) : ;; # explicit pathspec after `--`: scoped, not a bare stash-everything
        *) emit_unattended_ask "bare git stash stashes every uncommitted change in the working tree, including anything another session has not committed yet." ;;
      esac ;;
  esac

  # SCM operations
  case "$seg" in
    git\ reset\ *--hard*)
      emit_unattended_ask "git reset --hard discards uncommitted work in the working tree." ;;
    git\ clean\ *-*[dD]*[fF]*|git\ clean\ *-*[fF]*[dD]*)
      emit_unattended_ask "git clean -fd deletes untracked files, including ones never committed anywhere." ;;
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
        tok=$(_gd_unquote "$tok")
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

# Apply the ask tier the same way: always split via _gd_split, always loop. One segment for a
# simple command, real segments for a compound one, quote-aware either way.
while IFS= read -r seg; do
  [ -n "$seg" ] || continue
  seg=$(printf '%s' "$seg" | sed -e 's/^[[:space:]]*//; s/[[:space:]]*$//')
  [ -n "$seg" ] || continue
  _check_ask_segment "$seg"
done <<EOF
$(_gd_split "$CMD")
EOF

allow
