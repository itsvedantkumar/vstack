#!/usr/bin/env bash
# bin-scripts.sh — exercise the three shipped bin/ scripts that nothing else touches.
#
# install.sh copies bin/* wholesale into every user's ~/.config/agents/bin/, so
# claude-bg.sh, claude-task.sh and deploy-auto.sh ship whether or not anyone has ever run
# them. Nothing in .claude/verify.sh, tests/, or CI exercised their behaviour before this
# suite -- only their syntax. Static analysis (bash -n, shellcheck -S warning) already runs
# on these three files via check 1 and check 29 of the gate, so "never linted" would be a
# false claim; "never run" is the true one, and running is where all the defects below live.
#
# bin/claude-task.sh gets the most attention. It is the unattended path README.md markets
# safety around -- cron or launchd invoke it with no TTY, and it calls
# `claude -p --dangerously-skip-permissions --max-turns 50` unattended. Nobody had run it
# and looked. This suite does, without spending a single model call: every `claude` in here
# is a local stub script, never the real CLI.
#
# Usage: tests/bin-scripts.sh [case-name ...]     (default: all)

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
SRC=$(pwd)

ROOT=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/vstack-binscripts.XXXXXX")" && pwd)
trap 'rm -rf "$ROOT"' EXIT

# --- the no-model-calls claim, enforced rather than asserted -------------------------------------
# The header above says every `claude` in here is a local stub, never the real CLI. That was a
# description of the intent with no mechanism behind it, and it was false: bin/claude-bg.sh
# PREPENDED /usr/local/bin and friends to the caller's PATH, so a case's stub lost to whatever
# real CLI the machine had installed. CI ran the real binary and printed "Not logged in - Please
# run /login". On a logged-in machine that is a real model call with a real prompt, from a test
# suite whose whole selling point is that it costs nothing.
#
# Two things make the claim true. bin/claude-bg.sh and bin/claude-task.sh now append those
# locations instead of prepending, so the caller's PATH wins; and this poison sits first on the
# PATH every case inherits, so a case that reaches no stub of its own gets a loud refusal
# instead of the operator's real CLI. The poison is not a substitute for the fix -- with the
# prepend live it was shadowed too -- it is the backstop for the next script that forgets.
POISON="$ROOT/poison"
mkdir -p "$POISON"
cat > "$POISON/claude" <<'PSN'
#!/bin/sh
echo "POISONED CLAUDE: tests/bin-scripts.sh reached a real CLI lookup with no stub in front of it." >&2
echo "  argv: $*" >&2
exit 97
PSN
chmod +x "$POISON/claude"
export PATH="$POISON:$PATH"

PASS=0; FAIL=0; SKIP=0
ok(){   printf 'ok    %s\n' "$1"; PASS=$((PASS+1)); }
bad(){  printf 'FAIL  %s\n      %s\n' "$1" "$2"; FAIL=$((FAIL+1)); }
skip(){ printf 'skip  %s (%s)\n' "$1" "$2"; SKIP=$((SKIP+1)); }
note(){ printf 'note  %s\n' "$1"; }

want(){ case " ${CASES:-} " in " all ") return 0 ;; *" $1 "*) return 0 ;; *) return 1 ;; esac; }
CASES="${*:-all}"

# A message is only "sensible" per the task brief if it is one the script chose to print,
# not bash's own parameter-expansion or `cd` builtin decoration leaking through. Both read
# as "an error happened" to a human, but only one of them is a message the author wrote, and
# a cron mailbox full of "line 34: claude: command not found" is exactly the failure mode
# this suite exists to surface rather than paper over.
raw_shell_error(){ grep -qE ': line [0-9]+: ' <<<"$1"; }

# --- stub builders: never the real `claude`, `vercel`, `wrangler`, `curl` or `osascript` ---
stub_claude(){ # <path> <exit-code>
  # Deliberately does not read stdin. claude-bg.sh never redirects it (the prompt is an
  # argument), so a stub that blocks on `cat` waiting for EOF hangs forever on whatever stdin
  # it inherited -- truncating the log after the first line and producing a false "did not
  # dispatch" reading. claude-task.sh does redirect stdin from the SKILL.md file; a stub that
  # ignores it is still safe there; nothing depends on the stub having consumed it.
  cat > "$1" <<STUB
#!/bin/sh
printf 'STUB CLAUDE args: %s\n' "\$*" >&2
exit ${2:-0}
STUB
  chmod +x "$1"
}
stub_bin(){ # <path> <stdout-line> <exit-code>
  cat > "$1" <<STUB
#!/bin/sh
printf '%s\n' "$2" >&2
exit ${3:-0}
STUB
  chmod +x "$1"
}
stub_curl(){ # <path> <http-code>
  cat > "$1" <<STUB
#!/bin/sh
printf '%s' '$2'
STUB
  chmod +x "$1"
}
# claude-bg.sh writes its first log line (the "▶ headless run" banner) the instant the
# backgrounded subshell starts, well before the `claude` call inside it returns. A file that is
# merely non-empty is not a file that is done: waiting on `-s` alone raced the background job and
# read a log truncated after line 1, misreporting a live dispatch as one that never happened.
# claude-bg.sh's own last line is always "◀ exit N", win or lose, so wait for that marker instead.
wait_done(){ # <file> [tenths, default 30 = 3s]
  n=${2:-30}
  while ! grep -q '^◀ exit' "$1" 2>/dev/null && [ "$n" -gt 0 ]; do sleep 0.1; n=$((n-1)); done
}
# claude-bg.sh names its log by timestamp, so the filename is not known in advance. Poll for it
# to appear (it backgrounds with `&` and returns immediately), then wait for the run to finish.
bg_logfile(){ # <H> [tenths, default 30 = 3s]
  d="$1/.config/agents/bg"; n=${2:-30}; f=""
  while [ -z "$f" ] && [ "$n" -gt 0 ]; do
    f=$(find "$d" -maxdepth 1 -name '*.log' 2>/dev/null | head -1)
    [ -n "$f" ] || { sleep 0.1; n=$((n-1)); }
  done
  [ -n "$f" ] && wait_done "$f" "$n"
  printf '%s' "$f"
}

# =================================================================================================
# 1. Static analysis, asserted directly rather than assumed. check 1 and check 29 of the gate
#    already run bash -n and shellcheck -S warning over these files; run here at shellcheck's
#    *default* severity (which includes info) so this suite is not just re-proving what the gate
#    already covers. That is not pedantry: it is what actually found the first defect below.
# =================================================================================================
if want static; then
  for f in bin/claude-bg.sh bin/claude-task.sh bin/deploy-auto.sh; do
    out=$(bash -n "$SRC/$f" 2>&1)
    [ -z "$out" ] && ok "$f: bash -n clean" || bad "$f: bash -n clean" "$out"
  done
  if command -v shellcheck >/dev/null 2>&1; then
    for f in bin/claude-bg.sh bin/claude-task.sh bin/deploy-auto.sh; do
      out=$(shellcheck "$SRC/$f" 2>&1); rc=$?
      [ "$rc" -eq 0 ] && ok "$f: shellcheck clean (default severity)" \
        || bad "$f: shellcheck clean (default severity)" "$(printf '%s' "$out" | head -8)"
    done
  else
    skip "shellcheck clean (all three)" "shellcheck not installed"
  fi
fi

# --- positive control: prove this harness can see a failure before trusting it to see none -----
# Without this, "clean" and "the check never ran" look identical from the output. Mirrors the
# control gate-falsifiability.sh and check 29 both already carry for the same reason.
if want control; then
  broken="$ROOT/broken-syntax.sh"
  printf '#!/usr/bin/env bash\necho "unterminated string\n' > "$broken"
  out=$(bash -n "$broken" 2>&1)
  [ -n "$out" ] && ok "positive control: bash -n catches broken syntax" \
    || bad "positive control: bash -n catches broken syntax" "reported clean on a script with an unterminated string -- every bash -n check above proves nothing"

  if command -v shellcheck >/dev/null 2>&1; then
    ctl=$(printf '#!/bin/bash\nx=$HOME/a b\nls $x\n' | shellcheck -f gcc - 2>/dev/null)
    [ -n "$ctl" ] && ok "positive control: shellcheck catches a known-bad script" \
      || bad "positive control: shellcheck catches a known-bad script" "found nothing wrong with an unquoted expansion -- every shellcheck check above proves nothing"
  else
    skip "positive control: shellcheck" "shellcheck not installed"
  fi

  # The poison, watched firing. Without this the guard is exactly the shape this repository
  # exists to catch: a safety net that is reported as present and has never been shown to hold
  # anything. Resolve `claude` the way the shipped scripts do -- with the fallbacks appended --
  # from a HOME that has none, and require the poison, not the machine's real CLI.
  _pc_home="$ROOT/poison-control"; mkdir -p "$_pc_home"
  _pc_out=$(env HOME="$_pc_home" PATH="$POISON:/usr/bin:/bin" sh -c \
    'export PATH="$PATH:$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"; claude -p hi' 2>&1)
  _pc_rc=$?
  if [ "$_pc_rc" = 97 ] && grep -q 'POISONED CLAUDE' <<<"$_pc_out"; then
    ok "positive control: the poison outranks any real claude on this machine"
  else
    bad "positive control: the poison outranks any real claude on this machine" \
        "exit $_pc_rc, output: $(printf '%s' "$_pc_out" | head -2 | tr '\n' ' ') -- every 'no model call' claim in this file is unenforced"
  fi
fi

# =================================================================================================
# 2. Argument handling: no args, --help, a bogus flag, too many args. None of the three scripts
#    implement --help, so that case exercises the same code path as the bogus flag.
# =================================================================================================

# --- claude-bg.sh -------------------------------------------------------------------------------
# Always backgrounds a real `claude -p` call; nothing here validates that arg 1 looks like a
# flag rather than a prompt. --help and a bogus flag both get forwarded to the model as the
# prompt text -- in production this is a real headless call the user did not intend, dispatched
# silently under a message that looks identical to a correct dispatch.
if want bg-args; then
  H="$ROOT/bg-noargs"; mkdir -p "$H/.config/agents/bg"
  out=$(HOME="$H" bash "$SRC/bin/claude-bg.sh" 2>&1); rc=$?
  if [ "$rc" -ne 0 ] && ! raw_shell_error "$out"; then
    ok "claude-bg.sh: no args exits nonzero with a clean message"
  else
    bad "claude-bg.sh: no args exits nonzero with a clean message" \
      "rc=$rc, output leaks bash's own parameter-expansion error instead of a message the script wrote: $out"
  fi

  for case_name in help:--help bogus:-x; do
    label=${case_name%%:*}; arg=${case_name#*:}
    H="$ROOT/bg-$label"; mkdir -p "$H/.config/agents/bg" "$H/stubs"
    stub_claude "$H/stubs/claude" 0
    PATH="$H/stubs:$PATH" HOME="$H" bash "$SRC/bin/claude-bg.sh" "$arg" >/dev/null 2>&1
    logf=$(bg_logfile "$H")
    if [ -n "$logf" ] && grep -q 'STUB CLAUDE' "$logf" 2>/dev/null; then
      bad "claude-bg.sh: $label ($arg) is not treated as a real headless prompt" \
        "no --help/flag recognition: '$arg' was forwarded to claude as the prompt and a real headless call was dispatched"
    else
      ok "claude-bg.sh: $label ($arg) is not treated as a real headless prompt"
    fi
  done

  H="$ROOT/bg-extra"; mkdir -p "$H/.config/agents/bg" "$H/stubs"
  stub_claude "$H/stubs/claude" 0
  PATH="$H/stubs:$PATH" HOME="$H" bash "$SRC/bin/claude-bg.sh" "the real prompt" sonnet extra1 extra2 >/dev/null 2>&1
  logf=$(bg_logfile "$H")
  if [ -n "$logf" ] && grep -q "STUB CLAUDE args: -p the real prompt --model sonnet" "$logf" 2>/dev/null; then
    ok "claude-bg.sh: extra positional args do not corrupt the dispatch"
    note "claude-bg.sh: extra args (extra1 extra2) are silently dropped with no warning"
  else
    bad "claude-bg.sh: extra positional args do not corrupt the dispatch" "$(cat "$logf" 2>/dev/null)"
  fi
fi

# --- claude-task.sh ------------------------------------------------------------------------------
if want task-args; then
  H="$ROOT/task-noargs"; mkdir -p "$H/.local/bin"
  out=$(HOME="$H" bash "$SRC/bin/claude-task.sh" 2>&1); rc=$?
  if [ "$rc" -ne 0 ] && ! raw_shell_error "$out"; then
    ok "claude-task.sh: no args exits nonzero with a clean message"
  else
    bad "claude-task.sh: no args exits nonzero with a clean message" \
      "rc=$rc, output leaks bash's own parameter-expansion error instead of a message the script wrote: $out"
  fi

  for case_name in help:--help bogus:-x; do
    label=${case_name%%:*}; arg=${case_name#*:}
    H="$ROOT/task-$label"; mkdir -p "$H/.local/bin" "$H/.claude/scheduled-tasks"
    stub_claude "$H/.local/bin/claude" 0
    out=$(HOME="$H" bash "$SRC/bin/claude-task.sh" "$arg" 2>&1); rc=$?
    if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
      bad "claude-task.sh: $label ($arg) does not fail silently" \
        "exited 0 with zero output and wrote no log -- a typo'd flag in a cron line is indistinguishable from a successful run"
    else
      ok "claude-task.sh: $label ($arg) does not fail silently"
    fi
  done

  H="$ROOT/task-extra"; mkdir -p "$H/.local/bin" "$H/.claude/scheduled-tasks/mytask"
  stub_claude "$H/.local/bin/claude" 0
  printf -- '---\nname: mytask\n---\ndo the thing\n' > "$H/.claude/scheduled-tasks/mytask/SKILL.md"
  # PATH set explicitly. This case is about argument handling, not resolution order, and it
  # used to reach its stub only because claude-task.sh prepended $HOME/.local/bin over the
  # caller's PATH. Resolution order has exactly two cases of its own further down; every other
  # case says where its stub is instead of inheriting the answer.
  PATH="$H/.local/bin:$PATH" HOME="$H" bash "$SRC/bin/claude-task.sh" mytask sonnet extra1 extra2 >/dev/null 2>&1
  logf="$H/.claude/scheduled-tasks/mytask/last-run.log"
  if grep -q 'STUB CLAUDE args: -p --model sonnet' "$logf" 2>/dev/null; then
    ok "claude-task.sh: extra positional args do not corrupt the run"
    note "claude-task.sh: extra args (extra1 extra2) are silently dropped with no warning"
  else
    bad "claude-task.sh: extra positional args do not corrupt the run" "$(cat "$logf" 2>/dev/null)"
  fi
fi

# --- deploy-auto.sh -------------------------------------------------------------------------------
# $1 is a directory, not a flag, and doubles as "no args" (defaults to $PWD). A flag-shaped $1
# reaches a bare `cd "$d"`, so the failure text is whatever the `cd` builtin prints, not a
# message deploy-auto.sh wrote -- and it prints regardless of whether $1 was a real typo'd path
# or something that merely looked like a flag.
if want deploy-args; then
  H="$ROOT/deploy-noargs"; mkdir -p "$H/empty"
  out=$(cd "$H/empty" && bash "$SRC/bin/deploy-auto.sh" 2>&1); rc=$?
  if [ "$rc" -eq 2 ] && ! raw_shell_error "$out"; then
    ok "deploy-auto.sh: no args in a non-target dir exits cleanly (no cd needed, uses \$PWD)"
  else
    bad "deploy-auto.sh: no args in a non-target dir exits cleanly" "rc=$rc: $out"
  fi

  for case_name in help:--help bogus:-x nonexistent:/no/such/dir-xyz; do
    label=${case_name%%:*}; arg=${case_name#*:}
    out=$(bash "$SRC/bin/deploy-auto.sh" "$arg" 2>&1); rc=$?
    if [ "$rc" -ne 0 ] && ! raw_shell_error "$out"; then
      ok "deploy-auto.sh: $label ($arg) exits with a clean message"
    else
      bad "deploy-auto.sh: $label ($arg) exits with a clean message" \
        "rc=$rc; the \`cd\` builtin's own stderr leaks ahead of deploy-auto's own 'cannot enter' line: $out"
    fi
  done

  H="$ROOT/deploy-extra"; mkdir -p "$H/proj"
  out=$(bash "$SRC/bin/deploy-auto.sh" "$H/proj" extra1 extra2 2>&1); rc=$?
  if [ "$rc" -eq 2 ] && grep -q 'no vercel/cloudflare target' <<<"$out"; then
    ok "deploy-auto.sh: extra positional args do not corrupt which dir is entered"
    note "deploy-auto.sh: extra args (extra1 extra2) are silently dropped with no warning"
  else
    bad "deploy-auto.sh: extra positional args do not corrupt which dir is entered" "rc=$rc: $out"
  fi
fi

# =================================================================================================
# 3. Path resolution: run from a cwd that has nothing to do with the repo or the task. These
#    install to ~/.config/agents/bin/ and get invoked from wherever cron/launchd/the calling
#    shell happens to be standing.
# =================================================================================================
if want cwd; then
  H="$ROOT/cwd-bg"; mkdir -p "$H/.config/agents/bg" "$H/elsewhere" "$H/stubs"
  stub_claude "$H/stubs/claude" 0
  ( cd "$H/elsewhere" && PATH="$H/stubs:$PATH" HOME="$H" bash "$SRC/bin/claude-bg.sh" "hi" >/dev/null 2>&1 )
  logf=$(bg_logfile "$H")
  [ -n "$logf" ] && grep -q 'STUB CLAUDE' "$logf" 2>/dev/null \
    && ok "claude-bg.sh: works when invoked from an unrelated cwd" \
    || bad "claude-bg.sh: works when invoked from an unrelated cwd" "no dispatch reached the stub from cwd=$H/elsewhere"

  H="$ROOT/cwd-task"; mkdir -p "$H/.local/bin" "$H/.claude/scheduled-tasks/mytask" "$H/elsewhere"
  stub_claude "$H/.local/bin/claude" 0
  printf -- '---\nname: mytask\n---\ndo it\n' > "$H/.claude/scheduled-tasks/mytask/SKILL.md"
  out=$( ( cd "$H/elsewhere" && PATH="$H/.local/bin:$PATH" HOME="$H" bash "$SRC/bin/claude-task.sh" mytask 2>&1 ) ); rc=$?
  grep -q 'STUB CLAUDE' "$H/.claude/scheduled-tasks/mytask/last-run.log" 2>/dev/null \
    && ok "claude-task.sh: works when invoked from an unrelated cwd" \
    || bad "claude-task.sh: works when invoked from an unrelated cwd" "rc=$rc, out=$out"

  H="$ROOT/cwd-deploy"; mkdir -p "$H/proj" "$H/elsewhere"
  out=$( ( cd "$H/elsewhere" && bash "$SRC/bin/deploy-auto.sh" "$H/proj" 2>&1 ) ); rc=$?
  [ "$rc" -eq 2 ] && grep -q 'no vercel/cloudflare target' <<<"$out" \
    && ok "deploy-auto.sh: works when invoked from an unrelated cwd (resolves \$1, not \$PWD)" \
    || bad "deploy-auto.sh: works when invoked from an unrelated cwd" "rc=$rc: $out"
fi

# =================================================================================================
# 4. The environment they actually run in: cron/launchd give no TTY, a minimal PATH, and no
#    login shell (so none of ~/.zshrc, ~/.bashrc, ~/.profile ran). Simulated with `env -i`, a
#    bare PATH, and stdin from /dev/null.
# =================================================================================================
if want env-sim; then
  # claude-bg.sh does no PATH hardening of its own -- it trusts whatever PATH it inherits.
  # Case A: the stub happens to be reachable via the inherited PATH (best case for cron, if
  # whoever wrote the crontab remembered to set PATH). Case B: a bare PATH with nothing
  # resembling a login shell's additions, which is the *default*, unconfigured cron/launchd
  # environment.
  H="$ROOT/env-bg-ok"; mkdir -p "$H/.config/agents/bg" "$H/stubs"
  stub_claude "$H/stubs/claude" 0
  env -i HOME="$H" PATH="$H/stubs:/usr/bin:/bin" bash "$SRC/bin/claude-bg.sh" "hi" < /dev/null >/dev/null 2>&1
  logf=$(bg_logfile "$H")
  [ -n "$logf" ] && grep -q 'STUB CLAUDE' "$logf" 2>/dev/null \
    && ok "claude-bg.sh: dispatches under env -i when claude is on the minimal PATH" \
    || bad "claude-bg.sh: dispatches under env -i when claude is on the minimal PATH" "no dispatch reached the stub"

  H="$ROOT/env-bg-bad"; mkdir -p "$H/.config/agents/bg"
  out=$(env -i HOME="$H" PATH=/usr/bin:/bin bash "$SRC/bin/claude-bg.sh" "hi" < /dev/null 2>&1); rc=$?
  sleep 0.5
  logf=$(bg_logfile "$H")
  if [ "$rc" -eq 0 ] && grep -q 'dispatched' <<<"$out" && grep -qE 'command not found|127' "$logf" 2>/dev/null; then
    bad "claude-bg.sh: a bare cron-style PATH without claude on it fails visibly" \
      "prints 'dispatched' and exits 0 (a claimed success) while the backgrounded job silently dies with 'claude: command not found'; nothing surfaces this to the caller or to cron"
  else
    ok "claude-bg.sh: a bare cron-style PATH without claude on it fails visibly"
  fi

  # claude-task.sh hardcodes its own PATH (HOME/.local/bin, an nvm guess, then Homebrew/system
  # dirs), specifically to survive launchd's minimal environment. It works when claude lives in
  # one of those locations (true here, and true for a standard `claude` native install)...
  H="$ROOT/env-task-ok"; mkdir -p "$H/.local/bin" "$H/.claude/scheduled-tasks/mytask"
  stub_claude "$H/.local/bin/claude" 0
  printf -- '---\nname: mytask\n---\ndo it\n' > "$H/.claude/scheduled-tasks/mytask/SKILL.md"
  out=$(env -i HOME="$H" PATH=/usr/bin:/bin bash "$SRC/bin/claude-task.sh" mytask < /dev/null 2>&1); rc=$?
  logf="$H/.claude/scheduled-tasks/mytask/last-run.log"
  if [ "$rc" -eq 0 ] && grep -q 'STUB CLAUDE' "$logf" 2>/dev/null; then
    ok "claude-task.sh: runs under env -i / no TTY / minimal PATH when claude is in \$HOME/.local/bin"
  else
    bad "claude-task.sh: runs under env -i / no TTY / minimal PATH when claude is in \$HOME/.local/bin" "rc=$rc out=$out log=$(cat "$logf" 2>/dev/null)"
  fi

  # ...but the moment claude lives anywhere the hardcoded list does not guess -- a plain
  # $HOME/bin, a pnpm/yarn global bin, an npm prefix other than nvm's -- the same minimal
  # environment resolves nothing, and (see section 6) the wrapper still exits 0.
  H="$ROOT/env-task-miss"; mkdir -p "$H/bin" "$H/.claude/scheduled-tasks/mytask"
  stub_claude "$H/bin/claude" 0
  printf -- '---\nname: mytask\n---\ndo it\n' > "$H/.claude/scheduled-tasks/mytask/SKILL.md"
  env -i HOME="$H" PATH="$H/bin:/usr/bin:/bin" bash "$SRC/bin/claude-task.sh" mytask < /dev/null >/dev/null 2>&1
  logf="$H/.claude/scheduled-tasks/mytask/last-run.log"
  if grep -qE 'command not found' "$logf" 2>/dev/null; then
    bad "claude-task.sh: finds claude wherever the caller's PATH puts it" \
      "the script replaces the inherited PATH outright with a hardcoded list (\$HOME/.local/bin, nvm, /opt/homebrew/bin, /usr/local/bin, /usr/bin, /bin); a claude install anywhere else (this case: \$HOME/bin, reachable on the inherited PATH) is invisible to it even though it was right there on PATH"
  else
    ok "claude-task.sh: finds claude wherever the caller's PATH puts it"
  fi

  # deploy-auto.sh: the baseline case (no deploy target present) needs no external tool at all,
  # so this proves it does not hang waiting on a TTY that env -i / stdin </dev/null removes.
  # `timeout` itself must be resolved on the *outer*, unrestricted PATH -- it is not part of the
  # bare PATH being simulated for the script under test, only its wrapper.
  TIMEOUT_BIN=$(command -v timeout || command -v gtimeout || true)
  if [ -z "$TIMEOUT_BIN" ]; then
    skip "deploy-auto.sh: does not hang under env -i / no TTY / minimal PATH" "no timeout/gtimeout on this machine to bound the wait"
  else
    H="$ROOT/env-deploy"; mkdir -p "$H/proj"
    out=$("$TIMEOUT_BIN" 10 env -i PATH=/usr/bin:/bin bash "$SRC/bin/deploy-auto.sh" "$H/proj" < /dev/null 2>&1); rc=$?
    if [ "$rc" -eq 2 ] && grep -q 'no vercel/cloudflare target' <<<"$out"; then
      ok "deploy-auto.sh: does not hang under env -i / no TTY / minimal PATH"
    else
      bad "deploy-auto.sh: does not hang under env -i / no TTY / minimal PATH" "rc=$rc: $out"
    fi
  fi
fi

# =================================================================================================
# 5. claude-task.sh specifically: what happens without a task dir, without a SKILL.md, and with
#    an unwritable log dir. No model call anywhere below -- these are all reached before, or
#    instead of, invoking claude.
# =================================================================================================
if want task-specific; then
  H="$ROOT/task-missing-dir"; mkdir -p "$H/.local/bin" "$H/.claude/scheduled-tasks"
  stub_claude "$H/.local/bin/claude" 0
  out=$(HOME="$H" bash "$SRC/bin/claude-task.sh" no-such-task 2>&1); rc=$?
  if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
    bad "claude-task.sh: missing task directory is reported, not swallowed" \
      "exits 0 with zero output when \$HOME/.claude/scheduled-tasks/no-such-task does not exist at all -- a mistyped task name in a crontab runs forever and reports success every single night"
  else
    ok "claude-task.sh: missing task directory is reported, not swallowed"
  fi

  H="$ROOT/task-missing-skill"; mkdir -p "$H/.local/bin" "$H/.claude/scheduled-tasks/empty-task"
  stub_claude "$H/.local/bin/claude" 0
  out=$(HOME="$H" bash "$SRC/bin/claude-task.sh" empty-task 2>&1); rc=$?
  if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
    bad "claude-task.sh: task dir with no SKILL.md is reported, not swallowed" \
      "exits 0 with zero output when the task directory exists but SKILL.md is missing -- identical failure shape to the missing-directory case"
  else
    ok "claude-task.sh: task dir with no SKILL.md is reported, not swallowed"
  fi

  H="$ROOT/task-unwritable-log"; mkdir -p "$H/.local/bin" "$H/.claude/scheduled-tasks/mytask"
  stub_claude "$H/.local/bin/claude" 0
  printf -- '---\nname: mytask\n---\ndo it\n' > "$H/.claude/scheduled-tasks/mytask/SKILL.md"
  chmod 555 "$H/.claude/scheduled-tasks/mytask"
  out=$(HOME="$H" bash "$SRC/bin/claude-task.sh" mytask 2>&1); rc=$?
  chmod 755 "$H/.claude/scheduled-tasks/mytask"
  if [ "$rc" -ne 0 ] && ! raw_shell_error "$out"; then
    ok "claude-task.sh: unwritable log dir fails with a clean message"
  else
    # This is the one case that at least fails loudly (nonzero exit, non-empty stderr) instead
    # of silently -- graded against the same "no raw decoration" bar as everything else above,
    # so it still shows red, but it is the least-bad of the three claude-task.sh failure shapes:
    # a human tailing cron's mail would see *something* here, unlike the two cases above.
    bad "claude-task.sh: unwritable log dir fails with a clean message" \
      "rc=$rc; fails loudly (good) but the message is bash's own redirection error, not deploy-auto's/claude-task's own: $out"
  fi

  # The headline exit-code question: does claude-task.sh's own exit status ever reflect
  # whether the inner claude run succeeded? cron only acts on this one number.
  H="$ROOT/task-inner-fail"; mkdir -p "$H/.local/bin" "$H/.claude/scheduled-tasks/mytask"
  stub_claude "$H/.local/bin/claude" 1
  printf -- '---\nname: mytask\n---\ndo it\n' > "$H/.claude/scheduled-tasks/mytask/SKILL.md"
  HOME="$H" bash "$SRC/bin/claude-task.sh" mytask < /dev/null >/dev/null 2>&1
  rc=$?
  if [ "$rc" -ne 0 ]; then
    ok "claude-task.sh: exit status reflects an inner claude failure"
  else
    bad "claude-task.sh: exit status reflects an inner claude failure" \
      "stub claude exited 1 (simulating a hard failure -- crash, hit --max-turns, auth error) and the wrapper still exited 0; cron/launchd have no way to ever learn a scheduled run failed, for any reason, because this exit code is not connected to the inner command's"
  fi
fi

# =================================================================================================
# 6. claude-bg.sh specifically: the log directory it writes to is never created by install.sh,
#    so the very first invocation on a freshly installed machine hits a directory that does not
#    exist yet.
# =================================================================================================
if want bg-specific; then
  ! grep -rq 'agents/bg' "$SRC/install.sh" 2>/dev/null || note "install.sh now mentions agents/bg -- re-check this case's premise"
  H="$ROOT/bg-fresh-install"; mkdir -p "$H/stubs"
  stub_claude "$H/stubs/claude" 0
  out=$(PATH="$H/stubs:$PATH" HOME="$H" bash "$SRC/bin/claude-bg.sh" "first run ever" 2>&1); rc=$?
  sleep 0.5
  logf=$(bg_logfile "$H")
  if [ "$rc" -eq 0 ] && grep -q '^dispatched' <<<"$out" && [ -z "$logf" ]; then
    bad "claude-bg.sh: first run on a fresh install (no ~/.config/agents/bg/ yet) does not lie" \
      "prints 'dispatched → .../bg/TS.log (pid N)' and exits 0 even though the directory does not exist, the log was never created, and the background job never ran the stub at all -- install.sh does not mkdir this path either, so this is the default state for anyone who has never run the script before"
  else
    ok "claude-bg.sh: first run on a fresh install (no ~/.config/agents/bg/ yet) does not lie"
  fi
fi

# =================================================================================================
# 7. deploy-auto.sh: the one script here with no `claude` in it at all, and the best-behaved of
#    the three. Included so the report is not one-sided -- these are the paths that work.
# =================================================================================================
if want deploy-behaviour; then
  H="$ROOT/deploy-verify-fails"; mkdir -p "$H/proj/.claude" "$H/stubs"
  cat > "$H/proj/.claude/verify.sh" <<'V'
#!/bin/sh
echo "verify: seeded failure"
exit 1
V
  chmod +x "$H/proj/.claude/verify.sh"
  touch "$H/proj/vercel.json"
  stub_bin "$H/stubs/vercel" "STUB VERCEL: should never be called" 0
  stub_bin "$H/stubs/osascript" "" 0
  out=$(PATH="$H/stubs:$PATH" bash "$SRC/bin/deploy-auto.sh" "$H/proj" 2>&1); rc=$?
  if [ "$rc" -eq 1 ] && ! grep -q 'STUB VERCEL' <<<"$out"; then
    ok "deploy-auto.sh: a failing .claude/verify.sh aborts before any deploy is attempted"
  else
    bad "deploy-auto.sh: a failing .claude/verify.sh aborts before any deploy is attempted" "rc=$rc: $out"
  fi

  H="$ROOT/deploy-unhealthy"; mkdir -p "$H/proj" "$H/stubs"
  touch "$H/proj/vercel.json"
  stub_bin "$H/stubs/vercel" "https://stub-deploy.example.com" 0
  stub_curl "$H/stubs/curl" 500
  stub_bin "$H/stubs/osascript" "" 0
  out=$(PATH="$H/stubs:$PATH" bash "$SRC/bin/deploy-auto.sh" "$H/proj" 2>&1); rc=$?
  if [ "$rc" -eq 1 ] && grep -q '✖ health 500' <<<"$out"; then
    ok "deploy-auto.sh: a 500 health check after deploy is reported as a failure, not swallowed"
  else
    bad "deploy-auto.sh: a 500 health check after deploy is reported as a failure, not swallowed" "rc=$rc: $out"
  fi

  H="$ROOT/deploy-healthy"; mkdir -p "$H/proj" "$H/stubs"
  touch "$H/proj/vercel.json"
  stub_bin "$H/stubs/vercel" "https://stub-deploy.example.com" 0
  stub_curl "$H/stubs/curl" 200
  stub_bin "$H/stubs/osascript" "" 0
  out=$(PATH="$H/stubs:$PATH" bash "$SRC/bin/deploy-auto.sh" "$H/proj" 2>&1); rc=$?
  [ "$rc" -eq 0 ] && grep -q '✔ health 200' <<<"$out" \
    && ok "deploy-auto.sh: a healthy deploy exits 0" \
    || bad "deploy-auto.sh: a healthy deploy exits 0" "rc=$rc: $out"
fi

echo
printf '%d passed, %d failed' "$PASS" "$FAIL"
[ "$SKIP" -gt 0 ] && printf ', %d skipped' "$SKIP"
printf '\n'
[ "$FAIL" -eq 0 ] && echo "BIN SCRIPTS OK" || echo "BIN SCRIPTS HAVE UNFIXED DEFECTS"
exit "$FAIL"
