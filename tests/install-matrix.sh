#!/usr/bin/env bash
# install-matrix.sh — prove install.sh works in the environments strangers actually have.
#
# The gate checks that the repo is internally consistent. It cannot tell you the installer
# works, because the only way to know that is to run it and look at the resulting files. So
# this runs it, for real, into throwaway HOMEs, and asserts the tree afterwards.
#
# Every case here is a bug that shipped:
#
#   config-dir   Claude Code reads $CLAUDE_CONFIG_DIR when set. install.sh hardcoded
#                ~/.claude, so anyone with it pointed elsewhere — VMs, containers, anyone
#                running separate profiles — got a complete, clean-looking install into a
#                directory Claude Code never opens. Silent, and it looked like success.
#   bash-only    Only .zshrc/.zshenv were written. A default Debian, Ubuntu or Alpine box,
#                which is every cloud VM and nearly every container, installed fine and then
#                ran with none of the environment the setup depends on.
#   spaces       An unquoted path breaks for anyone whose home has a space in it.
#   no-jq        Sandboxes often lack it. Skills and hooks are still worth installing.
#   idempotent   The README says re-running is safe. That is a claim, so test it.
#   uninstall    Must remove what it installed, restore what it replaced, and keep both the
#                user's own files and anything they have edited since.
#
# Everything happens under a temp dir. Nothing here touches the real HOME — that is the whole
# point, and it is why this is safe to run on the machine you actually work on.
#
# Usage: tests/install-matrix.sh [case-name ...]     (default: all)

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
SRC=$(pwd)

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/vstack-matrix.XXXXXX")
trap 'rm -rf "$ROOT"' EXIT

PASS=0; FAIL=0
ok(){   printf 'ok    %s\n' "$1"; PASS=$((PASS+1)); }
bad(){  printf 'FAIL  %s\n      %s\n' "$1" "$2"; FAIL=$((FAIL+1)); }

# assert helpers — each takes the case name so a failure says which environment broke
count_dirs(){  find "$1" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l | tr -d ' '; }
count_files(){ find "$1" -maxdepth 1 -type f -name "$2" 2>/dev/null | wc -l | tr -d ' '; }

NSK=$(count_dirs "$SRC/claude/skills")
NAG=$(count_files "$SRC/claude/agents" '*.md')
NCM=$(count_files "$SRC/claude/commands" '*.md')
NHK=$(count_files "$SRC/claude/hooks" '*.sh')
NWR=$(find "$SRC/bin" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')

# A full install, asserted against the tree rather than against the installer's own summary.
assert_install(){ # <label> <config-dir> <home>
  lbl="$1"; cdir="$2"; h="$3"; errs=""
  [ "$(count_dirs "$cdir/skills")"          = "$NSK" ] || errs="$errs; skills $(count_dirs "$cdir/skills")/$NSK"
  [ "$(count_files "$cdir/agents" '*.md')"  = "$NAG" ] || errs="$errs; agents $(count_files "$cdir/agents" '*.md')/$NAG"
  [ "$(count_files "$cdir/commands" '*.md')" = "$NCM" ] || errs="$errs; commands $(count_files "$cdir/commands" '*.md')/$NCM"
  [ "$(count_files "$cdir/hooks" '*.sh')"   = "$NHK" ] || errs="$errs; hooks $(count_files "$cdir/hooks" '*.sh')/$NHK"
  [ "$(find "$h/.config/agents/bin" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')" = "$NWR" ] \
    || errs="$errs; wrappers missing"
  [ -f "$cdir/CLAUDE.md" ]     || errs="$errs; no CLAUDE.md"
  [ -f "$cdir/statusline.sh" ] || errs="$errs; no statusline.sh"
  [ -x "$cdir/hooks/verify-gate.sh" ] || errs="$errs; verify-gate.sh not executable"
  [ -f "$h/.config/agents/secrets.env" ] || errs="$errs; no secrets.env"
  # The installer must never leave a trace of the machine that built it.
  if grep -rqI "$SRC" "$cdir/settings.json" 2>/dev/null; then errs="$errs; repo path leaked into settings"; fi
  printf '%s' "$errs"
}

want(){ case " ${CASES:-} " in " all ") return 0 ;; *" $1 "*) return 0 ;; *) return 1 ;; esac; }
CASES="${*:-all}"

# --- default -----------------------------------------------------------------------------------
if want default; then
  H="$ROOT/default"; mkdir -p "$H"
  out=$(HOME="$H" "$SRC/install.sh" 2>&1); rc=$?
  e=$(assert_install default "$H/.claude" "$H")
  [ "$rc" = 0 ] && [ -z "$e" ] && ok "default HOME" || bad "default HOME" "exit=$rc$e"
fi

# --- $CLAUDE_CONFIG_DIR --------------------------------------------------------------------------
if want config-dir; then
  H="$ROOT/cfgdir"; mkdir -p "$H"
  out=$(HOME="$H" CLAUDE_CONFIG_DIR="$H/custom" "$SRC/install.sh" 2>&1); rc=$?
  e=$(assert_install config-dir "$H/custom" "$H")
  # and nothing may land in the directory Claude Code is NOT reading
  [ -d "$H/.claude" ] && e="$e; stray ~/.claude created"
  # Hook commands must point into the custom dir, or the hooks never fire.
  #
  # Compared by shape, not by string equality against $H. Git Bash hands paths to native
  # Windows binaries in 8.3 short form, so jq writes C:/Users/RUNNER~1/... while the test holds
  # C:/Users/runneradmin/... — same directory, different spelling, and a prefix match called it
  # a failure. What actually matters is that the path lands under the custom config dir and not
  # under a .claude the installer was told not to use.
  hp=$(jq -r '.hooks.Stop[0].hooks[0].command' "$H/custom/settings.json" 2>/dev/null)
  case "$hp" in
    */custom/hooks/verify-gate.sh) ;;
    *) e="$e; Stop hook points at $hp" ;;
  esac
  case "$hp" in *.claude/hooks/*) e="$e; Stop hook still points into ~/.claude" ;; esac
  [ "$rc" = 0 ] && [ -z "$e" ] && ok "CLAUDE_CONFIG_DIR honoured" || bad "CLAUDE_CONFIG_DIR honoured" "exit=$rc$e"
fi

# --- a home directory with a space in it ----------------------------------------------------------
if want spaces; then
  H="$ROOT/home with spaces"; mkdir -p "$H"
  out=$(HOME="$H" "$SRC/install.sh" 2>&1); rc=$?
  e=$(assert_install spaces "$H/.claude" "$H")
  [ "$rc" = 0 ] && [ -z "$e" ] && ok "space in \$HOME" || bad "space in \$HOME" "exit=$rc$e"
fi

# --- no jq ---------------------------------------------------------------------------------------
# Degrade, do not abort: skills and hooks still install, the two merge steps are skipped and
# said out loud. A sandbox without jq is a normal place to land.
if want no-jq; then
  H="$ROOT/nojq"; mkdir -p "$H"
  NOJQ="$ROOT/nojq-path"; mkdir -p "$NOJQ"
  for d in /usr/bin /bin /usr/local/bin /opt/homebrew/bin; do
    [ -d "$d" ] || continue
    for f in "$d"/*; do n=${f##*/}; [ "$n" = jq ] || ln -sf "$f" "$NOJQ/$n" 2>/dev/null; done
  done
  out=$(HOME="$H" PATH="$NOJQ" "$SRC/install.sh" 2>&1); rc=$?
  e=""
  [ "$(count_dirs "$H/.claude/skills")" = "$NSK" ] || e="$e; skills not installed without jq"
  [ "$(count_files "$H/.claude/hooks" '*.sh')" = "$NHK" ] || e="$e; hooks not installed without jq"
  printf '%s' "$out" | grep -q 'jq not found' || e="$e; did not warn about missing jq"
  [ "$rc" = 0 ] && [ -z "$e" ] && ok "no jq (degrades, warns)" || bad "no jq" "exit=$rc$e"
fi

# --- a bash user ----------------------------------------------------------------------------------
# The wrapper is zsh-only by construction. The environment is not, and it is the part that
# changes behaviour, so bash has to receive it.
if want bash-only; then
  H="$ROOT/bashonly"; mkdir -p "$H"; : > "$H/.bashrc"
  out=$(HOME="$H" SHELL=/bin/bash "$SRC/install.sh" 2>&1); rc=$?
  e=""
  grep -q 'ENABLE_PROMPT_CACHING_1H' "$H/.bashrc" 2>/dev/null || e="$e; env snippet missing from .bashrc"
  grep -q 'agents/secrets.env'       "$H/.bashrc" 2>/dev/null || e="$e; secrets not sourced in .bashrc"
  printf '%s' "$out" | grep -q 'zsh-only' || e="$e; did not say the wrapper is zsh-only"
  [ "$rc" = 0 ] && [ -z "$e" ] && ok "bash user gets the env lane" || bad "bash user gets the env lane" "exit=$rc$e"
fi

# --- idempotency ------------------------------------------------------------------------------------
# The README says re-running is safe. Two runs must leave the same tree, and the rc files must
# not accumulate a second copy of the guarded blocks.
if want idempotent; then
  H="$ROOT/idem"; mkdir -p "$H"
  HOME="$H" "$SRC/install.sh" >/dev/null 2>&1
  a=$(cd "$H/.claude" && find . -type f | sort | xargs shasum 2>/dev/null | shasum)
  HOME="$H" "$SRC/install.sh" >/dev/null 2>&1; rc=$?
  b=$(cd "$H/.claude" && find . -type f | sort | xargs shasum 2>/dev/null | shasum)
  e=""
  [ "$a" = "$b" ] || e="$e; second run changed the tree"
  [ "$(grep -c '>>> claude-parity >>>' "$H/.zshrc" 2>/dev/null)" = 1 ] || e="$e; .zshrc block duplicated"
  [ "$(grep -c '>>> claude-parity env >>>' "$H/.zshenv" 2>/dev/null)" = 1 ] || e="$e; .zshenv block duplicated"
  [ "$rc" = 0 ] && [ -z "$e" ] && ok "idempotent re-run" || bad "idempotent re-run" "exit=$rc$e"
fi

# --- uninstall --------------------------------------------------------------------------------------
# Three things at once: what vstack added is removed, what it replaced is restored to the
# user's version, and what the user has since edited is left alone.
if want uninstall; then
  H="$ROOT/uninst"; mkdir -p "$H/.claude/commands" "$H/.claude/agents"
  echo "MY OWN REVIEW"  > "$H/.claude/commands/review.md"     # vstack overwrites this one
  echo "MY OWN AGENT"   > "$H/.claude/agents/mine.md"         # vstack never touches this one
  HOME="$H" "$SRC/install.sh" >/dev/null 2>&1
  printf '\n# my notes\n' >> "$H/.claude/CLAUDE.md"           # edited after install
  out=$(HOME="$H" "$SRC/uninstall.sh" --yes 2>&1); rc=$?
  e=""
  [ "$(count_dirs "$H/.claude/skills")" = 0 ] || e="$e; skills survived"
  [ -e "$H/.claude/hooks/verify-gate.sh" ] && e="$e; hooks survived"
  [ "$(count_files "$H/.claude/commands" '*.md')" = 1 ] || e="$e; commands not cleaned to just the user's"
  grep -q 'MY OWN REVIEW' "$H/.claude/commands/review.md" 2>/dev/null || e="$e; user's review.md not restored"
  grep -q 'MY OWN AGENT'  "$H/.claude/agents/mine.md"     2>/dev/null || e="$e; user's own agent removed"
  grep -q 'my notes'      "$H/.claude/CLAUDE.md"          2>/dev/null || e="$e; edited CLAUDE.md was deleted"
  [ -f "$H/.config/agents/secrets.env" ] || e="$e; secrets.env removed"
  [ "$rc" = 0 ] && [ -z "$e" ] && ok "uninstall restores and preserves" || bad "uninstall restores and preserves" "exit=$rc$e"
fi

# --- refusing to act without --yes --------------------------------------------------------------------
# Read the exit status directly. Piping this to anything returns the pipe's status, which is how
# this was measured wrong the first time.
if want refuse; then
  H="$ROOT/refuse"; mkdir -p "$H"
  HOME="$H" "$SRC/install.sh" >/dev/null 2>&1
  HOME="$H" "$SRC/uninstall.sh" >/dev/null 2>&1; rc=$?
  [ "$rc" = 1 ] && [ "$(count_dirs "$H/.claude/skills")" = "$NSK" ] \
    && ok "uninstall refuses without --yes" \
    || bad "uninstall refuses without --yes" "exit=$rc (want 1), skills=$(count_dirs "$H/.claude/skills")"
fi

echo
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] && echo "MATRIX OK" || echo "MATRIX FAILED"
exit "$FAIL"
