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
#   existing-config  The case a real adopter is in, and the last one to get covered. Every
#                other case starts from an empty home, which is the one situation where a
#                merge cannot lose anything. This one seeds a lived-in ~/.claude — their own
#                skills, agents, commands, settings keys, permissions and MCP servers — and
#                requires all of it to survive.
#   bootstrap    The README's headline curl command, against the published URL.
#   marketplace  The plugin lane, installed from public GitHub into a throwaway config dir.
#
# The last two reach the network and skip with a reason when they cannot; the rest are offline.
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

PASS=0; FAIL=0; SKIP=0
ok(){   printf 'ok    %s\n' "$1"; PASS=$((PASS+1)); }
bad(){  printf 'FAIL  %s\n      %s\n' "$1" "$2"; FAIL=$((FAIL+1)); }
# Two cases reach the network and one needs the Claude CLI. Skipping is honest when the
# prerequisite is genuinely absent; skipping silently is how a lane goes untested for months,
# so a skip always says which prerequisite was missing.
skip(){ printf 'skip  %s (%s)\n' "$1" "$2"; SKIP=$((SKIP+1)); }

# assert helpers — each takes the case name so a failure says which environment broke
count_dirs(){  find "$1" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l | tr -d ' '; }
count_files(){ find "$1" -maxdepth 1 -type f -name "$2" 2>/dev/null | wc -l | tr -d ' '; }

NSK=$(count_dirs "$SRC/claude/skills")
NAG=$(count_files "$SRC/claude/agents" '*.md')
NCM=$(count_files "$SRC/claude/commands" '*.md')
NHK=$(count_files "$SRC/claude/hooks" '*.sh')
NWR=$(find "$SRC/bin" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')

# A full install, asserted against the tree rather than against the installer's own summary.
assert_install(){ # <label> <config-dir> <home> [atleast]
  # Counts are exact by default, which is what catches an install that scatters extra files.
  # With `atleast` they become a floor: a home that already held the user's own skills and
  # agents legitimately ends up with more than this repo ships, and demanding equality there
  # reports their surviving files as a defect.
  lbl="$1"; cdir="$2"; h="$3"; mode="${4:-exact}"; errs=""
  cmp_count(){ # <what> <got> <want>
    if [ "$mode" = atleast ]; then
      [ "$2" -ge "$3" ] || errs="$errs; $1 $2/$3"
    else
      [ "$2" = "$3" ] || errs="$errs; $1 $2/$3"
    fi
  }
  cmp_count skills   "$(count_dirs "$cdir/skills")"           "$NSK"
  cmp_count agents   "$(count_files "$cdir/agents" '*.md')"   "$NAG"
  cmp_count commands "$(count_files "$cdir/commands" '*.md')" "$NCM"
  cmp_count hooks    "$(count_files "$cdir/hooks" '*.sh')"    "$NHK"
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
  # Windows binaries in 8.3 short form, so jq writes the shortened spelling of the home
  # directory into settings.json while the test still holds the long one — same directory, two
  # spellings, and a prefix match called it a failure. What actually matters is that the path
  # lands under the custom config dir and not under a .claude the installer was told not to
  # use. (Spelling the two forms out literally here is what tripped check 4, which scans
  # tracked files for real home paths and cannot tell a comment from a config value.)
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

# --- installing over somebody else's existing setup ---------------------------------------------------
# The case a real adopter is actually in, and the one nothing tested until now: every other case
# here starts from an empty home, which is the one situation where a merge cannot lose anything.
#
# install.sh writes into files the user already owns — settings.json and .claude.json are merged,
# not copied — so the question is not whether vstack lands but whether anything of theirs goes
# missing while it does. Seed a home that looks lived-in and check every category survives.
if want existing-config; then
  H="$ROOT/existing"; mkdir -p "$H/.claude/skills/my-own-skill" "$H/.claude/agents" "$H/.claude/commands"
  printf -- '---\nname: my-own-skill\ndescription: theirs, not ours\n---\nbody\n' > "$H/.claude/skills/my-own-skill/SKILL.md"
  printf 'THEIR AGENT\n'   > "$H/.claude/agents/their-agent.md"
  printf 'THEIR COMMAND\n' > "$H/.claude/commands/their-command.md"
  # a settings file with their own preferences, including keys vstack also ships
  cat > "$H/.claude/settings.json" <<'J'
{"theirOwnKey":"keep me","theme":"dark","cleanupPeriodDays":99,
 "permissions":{"allow":["Bash(ls:*)"]},
 "hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"their-hook.sh"}]}]}}
J
  cat > "$H/.claude.json" <<'J'
{"mcpServers":{"their-server":{"type":"stdio","command":"their-mcp","args":["--flag"]}},
 "theirTopLevel":"keep me too"}
J
  out=$(HOME="$H" "$SRC/install.sh" 2>&1); rc=$?
  e=$(assert_install existing-config "$H/.claude" "$H" atleast)
  # their content, category by category
  [ -f "$H/.claude/skills/my-own-skill/SKILL.md" ] || e="$e; their skill was deleted"
  grep -q 'THEIR AGENT'   "$H/.claude/agents/their-agent.md"     2>/dev/null || e="$e; their agent was deleted"
  grep -q 'THEIR COMMAND' "$H/.claude/commands/their-command.md" 2>/dev/null || e="$e; their command was deleted"
  if command -v jq >/dev/null 2>&1; then
    [ "$(jq -r '.theirOwnKey // "GONE"' "$H/.claude/settings.json")" = "keep me" ] \
      || e="$e; their settings key was dropped"
    [ "$(jq -r '.permissions.allow[0] // "GONE"' "$H/.claude/settings.json")" = "Bash(ls:*)" ] \
      || e="$e; their permissions were dropped"
    [ "$(jq -r '.mcpServers["their-server"].command // "GONE"' "$H/.claude.json")" = "their-mcp" ] \
      || e="$e; their MCP server was dropped"
    [ "$(jq -r '.theirTopLevel // "GONE"' "$H/.claude.json")" = "keep me too" ] \
      || e="$e; their .claude.json top-level key was dropped"
    # vstack's own MCP servers must arrive alongside theirs, not instead of them
    [ "$(jq -r '.mcpServers | keys | length' "$H/.claude.json")" -ge 2 ] \
      || e="$e; vstack's MCP servers did not merge in"
  fi
  # anything overwritten must be recoverable, or "we back everything up" is not true
  bk=$(find "$H/.config/agents/backups" -name 'settings.json' -path '*files*' 2>/dev/null | head -1)
  [ -n "$bk" ] && grep -q 'theirOwnKey' "$bk" 2>/dev/null || e="$e; their settings.json was not backed up"
  [ "$rc" = 0 ] && [ -z "$e" ] && ok "installs over an existing setup without losing it" \
    || bad "installs over an existing setup without losing it" "exit=$rc$e"
fi

# --- the curl bootstrap lane, against the real published URL --------------------------------------
# The headline install command in the README, and until now the only proof it worked was a human
# running it once. It reaches the network on purpose: the thing being tested is that the URL
# serves, the clone succeeds, and install.sh runs from a directory nobody prepared by hand.
if want bootstrap; then
  if ! command -v curl >/dev/null 2>&1; then
    skip "curl bootstrap lane" "curl not installed"
  elif ! curl -fsSL --max-time 20 -o "$ROOT/bootstrap.sh" \
       https://raw.githubusercontent.com/itsvedantkumar/vstack/main/bootstrap.sh 2>/dev/null; then
    skip "curl bootstrap lane" "could not fetch the published bootstrap.sh (offline?)"
  else
    H="$ROOT/boot"; mkdir -p "$H"
    # --skip-deps: setup-machine.sh installs packages, which is not what this case is measuring.
    out=$(HOME="$H" VSTACK_DIR="$H/.vstack" bash "$ROOT/bootstrap.sh" --skip-deps 2>&1); rc=$?
    e=$(assert_install bootstrap "$H/.claude" "$H")
    [ -d "$H/.vstack/.git" ] || e="$e; bootstrap did not leave a clone at VSTACK_DIR"
    [ "$rc" = 0 ] && [ -z "$e" ] && ok "curl bootstrap lane" || bad "curl bootstrap lane" "exit=$rc$e"
  fi
fi

# --- the plugin marketplace lane, as a stranger ------------------------------------------------------
# Installs from the public GitHub repo into a throwaway CLAUDE_CONFIG_DIR. This is the only lane
# that reaches someone who never clones anything, and the only one where a malformed manifest is
# the user's first experience rather than ours.
if want marketplace; then
  if ! command -v claude >/dev/null 2>&1; then
    skip "plugin marketplace lane" "claude CLI not installed"
  elif ! claude --version >/dev/null 2>&1; then
    skip "plugin marketplace lane" "claude CLI present but not runnable here"
  else
    CFG="$ROOT/mkt"; mkdir -p "$CFG"; e=""
    CLAUDE_CONFIG_DIR="$CFG" claude plugin marketplace add itsvedantkumar/vstack >/dev/null 2>&1 \
      || e="$e; marketplace add failed"
    CLAUDE_CONFIG_DIR="$CFG" claude plugin install vstack@vstack >/dev/null 2>&1 \
      || e="$e; plugin install failed"
    pd=$(find "$CFG" -type d -path '*vstack*/skills' 2>/dev/null | head -1)
    if [ -z "$pd" ]; then
      e="$e; no skills directory delivered by the plugin"
    else
      n=$(count_dirs "$pd")
      [ "$n" -ge "$NSK" ] || e="$e; plugin delivered $n skills, repo has $NSK"
      [ -f "$pd/ATTRIBUTION.md" ] || e="$e; ATTRIBUTION.md missing from the plugin payload"
    fi
    [ -z "$e" ] && ok "plugin marketplace lane" || bad "plugin marketplace lane" "${e#; }"
  fi
fi

echo
printf '%d passed, %d failed' "$PASS" "$FAIL"
[ "$SKIP" -gt 0 ] && printf ', %d skipped' "$SKIP"
printf '\n'
[ "$FAIL" -eq 0 ] && echo "MATRIX OK" || echo "MATRIX FAILED"
exit "$FAIL"
