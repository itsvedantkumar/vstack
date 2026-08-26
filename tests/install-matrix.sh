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

# Canonicalised: macOS $TMPDIR ends in a slash, so the raw path can carry a double slash that
# cd+pwd elsewhere normalises away, and comparisons between the two spellings silently fail.
ROOT=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/vstack-matrix.XXXXXX")" && pwd)
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
  lbl="$1"; cdir="$2"; h="$3"; mode="${4:-exact}"; from="${5:-$SRC}"; errs=""
  : "$lbl"   # named by the caller and used in the failure text below
  # The two network lanes install whatever `main` currently serves, which is not necessarily
  # what is on this disk. Measuring a published install against local counts made the matrix go
  # red for the entirely correct reason that a new hook had not been pushed yet -- and since
  # preflight gates the commit, that is a state no ordering of commit and push can clear. The
  # expectation comes from the tree that was actually installed.
  NSK=$(count_dirs "$from/claude/skills")
  NAG=$(count_files "$from/claude/agents" '*.md')
  NCM=$(count_files "$from/claude/commands" '*.md')
  NHK=$(count_files "$from/claude/hooks" '*.sh')
  NWR=$(find "$from/bin" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')
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
  # Install and uninstall were separate cases, so a home path with a space was only ever proven
  # to install. It did not uninstall: the removal lists held absolute paths joined by spaces,
  # every one split into fragments matching nothing, and the run removed the skills, left every
  # hook, command, agent and wrapper in place, and printed "restore complete".
  HOME="$H" "$SRC/uninstall.sh" --yes >/dev/null 2>&1
  for leftover in hooks/verify-gate.sh commands/ship.md agents/worker.md; do
    [ -e "$H/.claude/$leftover" ] && e="$e; uninstall left $leftover behind"
  done
  [ -e "$H/.config/agents/bin/vstack" ] && e="$e; uninstall left the bin wrappers behind"
  [ "$rc" = 0 ] && [ -z "$e" ] && ok "space in \$HOME (install and uninstall)" || bad "space in \$HOME" "exit=$rc$e"
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
  # Copying the hook files is not the same as wiring them. The shipped settings.json addresses
  # hooks as $CLAUDE_PROJECT_DIR/... because that is right for the overlay lane; at user scope
  # there is no project dir, so a verbatim copy produced an install that reported success and
  # exited 127 on every hook. This case checked that the files arrived and called it a pass,
  # which is exactly the shape of a test that measures the wrong half of the claim.
  # jq, not python3: Alpine's slim image has no python3, and the jq-less constraint applies to
  # install.sh's PATH, not to this harness. Reading it with a tool the container lacks turned a
  # product assertion into an environment failure.
  cmd=$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$H/.claude/settings.json" 2>/dev/null)
  case "$cmd" in
    *CLAUDE_PROJECT_DIR*) e="$e; hook command still points at \$CLAUDE_PROJECT_DIR" ;;
    "") e="$e; could not read the configured hook command" ;;
    *) proj=$(mktemp -d)
       hout=$(printf '{"hook_event_name":"SessionStart"}' | HOME="$H" CLAUDE_PROJECT_DIR="$proj" bash -c "$cmd" 2>&1); hrc=$?
       [ "$hrc" = 0 ] || e="$e; configured hook exits $hrc when run"
       [ -n "$hout" ] || e="$e; configured hook produced no output"
       rm -rf "$proj" ;;
  esac
  [ "$rc" = 0 ] && [ -z "$e" ] && ok "no jq (degrades, warns, hooks still fire)" || bad "no jq" "exit=$rc$e"
fi

# --- a bash user ----------------------------------------------------------------------------------
# The wrapper is zsh-only by construction. The environment is not, and it is the part that
# changes behaviour, so bash has to receive it.
if want bash-only; then
  H="$ROOT/bashonly"; mkdir -p "$H"; : > "$H/.bashrc"
  out=$(HOME="$H" SHELL=/bin/bash "$SRC/install.sh" 2>&1); rc=$?
  e=""
  grep -q 'ENABLE_PROMPT_CACHING_1H' "$H/.bashrc" 2>/dev/null || e="$e; env snippet missing from .bashrc"
  # Deliberately the opposite of what this used to assert. The env snippet must reach bash —
  # that is the tuning that changes behaviour — but credentials must not, because sourcing
  # secrets.env from an rc file hands every token to every child process of every shell. The
  # wrappers in bin/ load what they need themselves.
  grep -q 'agents/secrets.env'       "$H/.bashrc" 2>/dev/null && e="$e; .bashrc exports credentials to every shell"
  printf '%s' "$out" | grep -q 'zsh-only' || e="$e; did not say the wrapper is zsh-only"
  [ "$rc" = 0 ] && [ -z "$e" ] && ok "bash user gets the env lane" || bad "bash user gets the env lane" "exit=$rc$e"
fi

# --- idempotency ------------------------------------------------------------------------------------
# The README says re-running is safe. Two runs must leave the same tree, and the rc files must
# not accumulate a second copy of the guarded blocks.
if want idempotent; then
  H="$ROOT/idem"; mkdir -p "$H"
  HOME="$H" "$SRC/install.sh" >/dev/null 2>&1
  # BusyBox ships sha256sum and no shasum; macOS ships shasum. Pick whichever is present, or
  # fall back to size+path, which is enough to catch a second run rewriting the tree.
  if command -v shasum >/dev/null 2>&1; then SUM=shasum
  elif command -v sha256sum >/dev/null 2>&1; then SUM=sha256sum
  else SUM=""; fi
  tree_fingerprint(){ # <dir>
    if [ -n "$SUM" ]; then (cd "$1" && find . -type f | sort | xargs $SUM 2>/dev/null | $SUM)
    else (cd "$1" && find . -type f -exec ls -l {} + 2>/dev/null | awk '{print $5, $NF}' | sort); fi
  }
  a=$(tree_fingerprint "$H/.claude")
  HOME="$H" "$SRC/install.sh" >/dev/null 2>&1; rc=$?
  b=$(tree_fingerprint "$H/.claude")
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

# --- install -> install -> uninstall (P0-1) -------------------------------------------------------
# The defect this repo shipped: install.sh's back() copied a file into the CURRENT run's backup
# dir unconditionally, even when the new content was vstack's own previous payload. So a second
# install backed up the FIRST install's copy of e.g. verify-gate.sh, not the pre-vstack original
# (there wasn't one). uninstall.sh restores the latest backup with no --from, so it restored
# vstack's own file and left it in place -- vstack never actually left the machine. Fixed by
# e26bbc2/e66544e: an ownership receipt at ~/.config/agents/vstack-installed that back() checks
# before ever recording a path as "the user's".
#
# This case is the regression test for that fix, run from the matrix rather than only from
# tests/repro/lifecycle.sh, so the coverage does not live in a script nobody runs by default.
if want reinstall-uninstall; then
  H="$ROOT/reinst"; mkdir -p "$H/.claude/hooks" "$H/.claude/skills/my-own-skill"
  printf '{\n  "foreignVendorKey": "acme-widgets-prod-42"\n}\n' > "$H/.claude/settings.json"
  printf '#!/bin/sh\necho "operator'"'"'s own hook, not vstack'"'"'s"\n' > "$H/.claude/hooks/user-own-hook.sh"
  chmod +x "$H/.claude/hooks/user-own-hook.sh"
  printf '# my own skill, predates vstack\n' > "$H/.claude/skills/my-own-skill/SKILL.md"
  HOME="$H" "$SRC/install.sh" >/dev/null 2>&1; i1=$?
  # BK_BASE has second resolution; without this the second install lands in the FIRST install's
  # own backup dir (mkdir -p happily reuses it) and this case would exercise a different bug
  # (backup-collision, covered separately) instead of the one it names.
  sleep 1.1
  HOME="$H" "$SRC/install.sh" >/dev/null 2>&1; i2=$?
  out=$(HOME="$H" "$SRC/uninstall.sh" --yes 2>&1); u=$?
  e=""
  [ "$i1" = 0 ] && [ "$i2" = 0 ] || e="$e; install exit codes i1=$i1 i2=$i2"
  [ "$(count_dirs "$H/.claude/skills")" = 1 ] || e="$e; skills not cleaned to just the user's ($(count_dirs "$H/.claude/skills")/1)"
  [ -e "$H/.claude/hooks/verify-gate.sh" ] && e="$e; vstack's own hook survived a second install+uninstall"
  grep -q 'foreignVendorKey' "$H/.claude/settings.json" 2>/dev/null || e="$e; user's settings key lost"
  grep -q 'statusline.sh' "$H/.claude/settings.json" 2>/dev/null && e="$e; settings.json still points at vstack's statusline"
  [ -f "$H/.claude/hooks/user-own-hook.sh" ] || e="$e; user's own hook was deleted"
  grep -q "operator's own hook" "$H/.claude/hooks/user-own-hook.sh" 2>/dev/null || e="$e; user's own hook was overwritten"
  [ -f "$H/.claude/skills/my-own-skill/SKILL.md" ] || e="$e; user's own skill was deleted"
  [ "$u" = 0 ] && [ -z "$e" ] && ok "install -> install -> uninstall restores the pre-vstack state" \
    || bad "install -> install -> uninstall restores the pre-vstack state" "uninstall exit=$u$e (out: $(printf '%s' "$out" | tail -3 | tr '\n' ' '))"
fi

# --- install vA -> install vB -> uninstall (upgrade across the same defect) -------------------------
# Same claim, harder case: vA and vB are two different commits, so vstack's own files differ byte
# for byte between the two installs and a content-comparison guard (cmp -s) cannot tell "this is
# vstack's own previous payload" from "this is the user's file that happens to match". Only the
# receipt survives a version change; seed_receipt() in install.sh exists for the machines that
# upgraded before the receipt itself existed.
#
# vA runs from a disposable git worktree pinned to the newest tag strictly older than HEAD, never
# by moving this checkout's own branch and never via `git fetch` (fetch.prune/fetch.pruneTags
# nuke local tags in this environment).
if want version-upgrade-uninstall; then
  if ! command -v git >/dev/null 2>&1; then
    skip "install vA -> install vB -> uninstall restores pre-vA state" "git not installed"
  else
    VA_TAG=""
    HEAD_TAG=$(git -C "$SRC" describe --tags --exact-match 2>/dev/null || true)
    for t in $(git -C "$SRC" tag --sort=v:refname 2>/dev/null); do
      [ "$t" = "$HEAD_TAG" ] && continue
      VA_TAG="$t"
    done
    if [ -z "$VA_TAG" ]; then
      skip "install vA -> install vB -> uninstall restores pre-vA state" "no tag older than HEAD found"
    else
      WT="$ROOT/vupg-wt"
      if ! git -C "$SRC" worktree add --detach --quiet "$WT" "$VA_TAG" >/dev/null 2>&1; then
        skip "install vA -> install vB -> uninstall restores pre-vA state" "could not create a worktree for $VA_TAG"
      else
        H="$ROOT/vupg"; mkdir -p "$H/.claude/hooks" "$H/.claude/skills/my-own-skill"
        printf '{\n  "foreignVendorKey": "acme-widgets-prod-42"\n}\n' > "$H/.claude/settings.json"
        printf '#!/bin/sh\necho "operator'"'"'s own hook, not vstack'"'"'s"\n' > "$H/.claude/hooks/user-own-hook.sh"
        chmod +x "$H/.claude/hooks/user-own-hook.sh"
        printf '# my own skill, predates vstack\n' > "$H/.claude/skills/my-own-skill/SKILL.md"
        HOME="$H" "$WT/install.sh" >/dev/null 2>&1; iva=$?
        sleep 1.1
        HOME="$H" "$SRC/install.sh" >/dev/null 2>&1; ivb=$?
        out=$(HOME="$H" "$SRC/uninstall.sh" --yes 2>&1); u=$?
        e=""
        [ "$iva" = 0 ] && [ "$ivb" = 0 ] || e="$e; install exit codes vA($VA_TAG)=$iva vB(HEAD)=$ivb"
        [ "$(count_dirs "$H/.claude/skills")" = 1 ] || e="$e; skills not cleaned to just the user's ($(count_dirs "$H/.claude/skills")/1)"
        [ -e "$H/.claude/hooks/verify-gate.sh" ] && e="$e; vstack's own hook survived an upgrade+uninstall"
        grep -q 'foreignVendorKey' "$H/.claude/settings.json" 2>/dev/null || e="$e; user's settings key lost"
        grep -q 'statusline.sh' "$H/.claude/settings.json" 2>/dev/null && e="$e; settings.json still points at vstack's statusline"
        [ -f "$H/.claude/hooks/user-own-hook.sh" ] || e="$e; user's own hook was deleted"
        grep -q "operator's own hook" "$H/.claude/hooks/user-own-hook.sh" 2>/dev/null || e="$e; user's own hook was overwritten"
        [ -f "$H/.claude/skills/my-own-skill/SKILL.md" ] || e="$e; user's own skill was deleted"
        # uninstall must remove vB's payload outright, not quietly leave vA's version behind as
        # a substitute -- there is no rollback command in this repo, and none is implied here.
        [ -e "$H/.config/agents/vstack-installed" ] && e="$e; the ownership receipt itself survived uninstall"
        git -C "$SRC" worktree remove --force "$WT" >/dev/null 2>&1
        [ "$u" = 0 ] && [ -z "$e" ] && ok "install $VA_TAG -> install HEAD -> uninstall restores the pre-vA state" \
          || bad "install $VA_TAG -> install HEAD -> uninstall restores the pre-vA state" \
                 "uninstall exit=$u$e (out: $(printf '%s' "$out" | tail -3 | tr '\n' ' '))"
      fi
    fi
  fi
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
 "skillOverrides":{"my-private-skill":"off"},
 "hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"their-hook.sh"}]}],
          "Notification":[{"hooks":[{"type":"command","command":"/usr/bin/true"}]}],
          "Stop":[{"hooks":[{"type":"command","command":"/their/own-stop.sh"}]}]}}
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
    # The half this test used to seed and then never look at. install.sh replaced .hooks and
    # .skillOverrides wholesale, so a user's notification, policy or security hooks and their
    # own skill controls were destroyed on install — and this case printed ok while doing it.
    [ "$(jq -r '.skillOverrides["my-private-skill"] // "GONE"' "$H/.claude/settings.json")" = "off" ] \
      || e="$e; their skillOverride was replaced"
    [ "$(jq -r '.skillOverrides | keys | length' "$H/.claude/settings.json")" -gt 17 ] \
      || e="$e; vstack's own overrides did not merge in alongside theirs"
    [ "$(jq -r 'if .hooks.Notification then "kept" else "GONE" end' "$H/.claude/settings.json")" = kept ] \
      || e="$e; their Notification hook was removed"
    [ "$(jq -r '.hooks.PreToolUse[0].hooks[0].command // "GONE"' "$H/.claude/settings.json")" = "their-hook.sh" ] \
      || e="$e; their PreToolUse hook was removed"
    [ -n "$(jq -r '[.hooks.Stop[].hooks[].command] | map(select(test("own-stop"))) | .[0] // ""' "$H/.claude/settings.json")" ] \
      || e="$e; their Stop hook was removed"
    [ -n "$(jq -r '[.hooks.Stop[].hooks[].command] | map(select(test("verify-gate"))) | .[0] // ""' "$H/.claude/settings.json")" ] \
      || e="$e; vstack's own Stop hook is missing"
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
    e=$(assert_install bootstrap "$H/.claude" "$H" exact "$H/.vstack")
    [ -d "$H/.vstack/.git" ] || e="$e; bootstrap did not leave a clone at VSTACK_DIR"
    # Local being ahead of the published tree is normal mid-change, and worth saying out loud
    # so the lane's numbers are never mistaken for this checkout's.
    lh=$(count_files "$SRC/claude/hooks" '*.sh'); rh=$(count_files "$H/.vstack/claude/hooks" '*.sh')
    [ "$lh" = "$rh" ] || printf 'note  published main has %s hooks, this checkout has %s\n' "$rh" "$lh"
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

# --- uninstalling an external config dir ----------------------------------------------------------
# With CLAUDE_CONFIG_DIR outside $HOME there is no home-relative form for those paths, so
# install.sh records them under files_abs/ with their full path. uninstall.sh did not read that
# directory at all: it treated it as a legacy flat name, mapped it under $HOME, and then
# classified the live external files as vstack's to delete. An uninstall destroyed the user's
# real CLAUDE.md and left the only copy somewhere they had no reason to look.
if want external-uninstall; then
  H="$ROOT/extun"; C="$ROOT/extun-cfg"; mkdir -p "$H" "$C"
  printf 'ORIGINAL EXTERNAL CLAUDE\n' > "$C/CLAUDE.md"
  printf '{"userOnly":"keep"}\n'      > "$C/settings.json"
  HOME="$H" CLAUDE_CONFIG_DIR="$C" "$SRC/install.sh" >/dev/null 2>&1
  HOME="$H" CLAUDE_CONFIG_DIR="$C" "$SRC/uninstall.sh" --yes >/dev/null 2>&1; rc=$?
  e=""
  grep -q 'ORIGINAL EXTERNAL CLAUDE' "$C/CLAUDE.md" 2>/dev/null \
    || e="$e; the original CLAUDE.md was not restored to its own path"
  grep -q 'userOnly' "$C/settings.json" 2>/dev/null \
    || e="$e; the original settings.json was not restored"
  [ -e "$C/hooks/verify-gate.sh" ] && e="$e; vstack hooks left in the external config dir"
  [ "$rc" = 0 ] && [ -z "$e" ] && ok "external config dir restores to its own path" \
    || bad "external config dir restores to its own path" "exit=$rc$e"
fi

# --- two installs in the same second ---------------------------------------------------------------
# Backup directories are named to the second and were created with mkdir -p, which happily
# reuses one. The second run then overwrote the first run's copies with files vstack had just
# installed, destroying the only record of what was there before. Retries and automation hit
# this without trying.
if want backup-collision; then
  H="$ROOT/bkcol"; mkdir -p "$H/.claude"
  printf 'ORIGINAL USER CLAUDE\n' > "$H/.claude/CLAUDE.md"
  SHIM="$ROOT/date-shim"; mkdir -p "$SHIM"
  printf '#!/bin/sh\nif [ "$1" = "+%%Y%%m%%d-%%H%%M%%S" ]; then echo 20260101-000000; else exec /bin/date "$@"; fi\n' > "$SHIM/date"
  chmod +x "$SHIM/date"
  PATH="$SHIM:$PATH" HOME="$H" "$SRC/install.sh" >/dev/null 2>&1
  PATH="$SHIM:$PATH" HOME="$H" "$SRC/install.sh" >/dev/null 2>&1
  e=""
  n=$(find "$H/.config/agents/backups" -maxdepth 1 -type d -name 'install-*' 2>/dev/null | wc -l | tr -d ' ')
  [ "$n" -ge 2 ] || e="$e; two same-second installs produced $n backup dir(s)"
  grep -q 'ORIGINAL USER CLAUDE' "$H/.config/agents/backups/install-20260101-000000/files/.claude/CLAUDE.md" 2>/dev/null \
    || e="$e; the first run's backup was overwritten by the second"
  [ -z "$e" ] && ok "same-second installs keep separate backups" \
    || bad "same-second installs keep separate backups" "${e#; }"
fi

# --- bootstrap refuses to discard local work ---------------------------------------------------------
# The documented rerun did `git reset --hard`, so anyone who had edited the managed checkout —
# or pointed VSTACK_DIR at a checkout with work in it — lost tracked changes with no warning,
# bypassing the review that `vstack update` performs.
if want bootstrap-dirty; then
  if ! command -v git >/dev/null 2>&1; then
    skip "bootstrap refuses a dirty checkout" "git not installed"
  else
    H="$ROOT/btd"; V="$H/.vstack"; mkdir -p "$H"
    git clone -q "$SRC" "$V" 2>/dev/null
    printf '\nLOCAL USER EDIT\n' >> "$V/README.md"
    HOME="$H" VSTACK_DIR="$V" bash "$SRC/bootstrap.sh" --skip-deps >/dev/null 2>&1; rc=$?
    e=""
    [ "$rc" = 0 ] && e="$e; bootstrap proceeded over a dirty checkout instead of refusing"
    grep -q 'LOCAL USER EDIT' "$V/README.md" 2>/dev/null || e="$e; the local edit was discarded"
    [ -z "$e" ] && ok "bootstrap refuses a dirty checkout" || bad "bootstrap refuses a dirty checkout" "${e#; }"
  fi
fi

# --- the overlay lane, end to end ----------------------------------------------------------------
# The fourth lane, and the only one that reaches a cloud sandbox, had no case here. Checks 9b and
# 17 exercise its settings merge and prove it strips personal keys, but nothing overlaid into a
# fresh repo and looked at what came out. That is the lane where a mistake lands in somebody
# else's repository and gets committed.
if want overlay; then
  if ! command -v git >/dev/null 2>&1; then
    skip "overlay lane" "git not installed"
  else
    T="$ROOT/ovl"; mkdir -p "$T"
    git -C "$T" init -q 2>/dev/null
    git -C "$T" config user.email t@example.com; git -C "$T" config user.name t
    printf 'x\n' > "$T/file.txt"; git -C "$T" add -A; git -C "$T" commit -qm init
    out=$("$SRC/overlay.sh" "$T" 2>&1); rc=$?
    e=""
    for f in .claude/settings.json .claude/hooks/policy.md .claude/statusline.sh .claude/verify.sh \
             .claude/hooks/verify-gate.sh .conductor/settings.toml CLAUDE.md; do
      [ -e "$T/$f" ] || e="$e; missing $f"
    done
    [ "$(count_dirs "$T/.claude/skills")" = "$NSK" ] || e="$e; skills $(count_dirs "$T/.claude/skills")/$NSK"
    if command -v jq >/dev/null 2>&1; then
      # A cloud sandbox has no $HOME config, so every hook command must resolve through the
      # project. An absolute path here is the machine that ran overlay leaking into a repo.
      hooks=$(jq -r '[.hooks[]?[]?.hooks[]?.command] | join(" ")' "$T/.claude/settings.json" 2>/dev/null)
      case "$hooks" in
        *'$CLAUDE_PROJECT_DIR'*) ;;
        *) e="$e; hook commands are not project-relative: $hooks" ;;
      esac
      case "$hooks" in
        */Users/*|*/home/*) e="$e; an absolute home path leaked into the overlaid settings" ;;
      esac
      # Personal keys must not travel into someone else's repo. Check 17 asserts this too; it is
      # cheap to assert on the real artifact rather than only on a synthetic one.
      for k in forceLoginMethod theme preferredNotifChannel remote; do
        [ "$(jq -r --arg k "$k" 'has($k)' "$T/.claude/settings.json")" = false ] \
          || e="$e; personal key $k was written into the target repo"
      done
    fi
    # The sandbox setup line pins a commit rather than tracking main, which is the whole point:
    # a compromised main must not reach every workspace at once.
    pin=$(grep -oE '/vstack/[0-9a-f]{40}/bootstrap.sh' "$T/.conductor/settings.toml" 2>/dev/null | head -1)
    [ -n "$pin" ] || e="$e; .conductor/settings.toml does not pin a 40-char commit"
    sha=${pin#/vstack/}; sha=${sha%/bootstrap.sh}
    [ -n "$sha" ] && git -C "$SRC" cat-file -e "$sha^{commit}" 2>/dev/null \
      || e="$e; the pinned commit does not exist in this repo"
    # The seeded gate must be inert until armed. A repo that arms someone else's shell on Stop
    # just by being cloned is the thing trust-on-arm exists to prevent.
    # --git-common-dir can answer with a path relative to the repo, so it has to be anchored
    # before use. overlay.sh does this; the test did not, and read a path relative to wherever
    # the harness happened to be standing — green locally, red on a CI checkout.
    gcd=$(git -C "$T" rev-parse --git-common-dir)
    case "$gcd" in /*) ;; *) gcd="$T/$gcd" ;; esac
    grep -q '.context/' "$gcd/info/exclude" 2>/dev/null || e="$e; .context/ was not excluded"
    [ "$rc" = 0 ] && [ -z "$e" ] && ok "overlay lane writes a sandbox-ready repo" \
      || bad "overlay lane writes a sandbox-ready repo" "exit=$rc$e"
  fi
fi

# --- vstack update refuses to trust new code unattended ---------------------------------------------
# `update` re-records the trust hashes for whatever it pulls, so it is the one unattended path
# where new code gets trusted. Without a terminal it must refuse rather than assume.
if want update; then
  if ! command -v git >/dev/null 2>&1; then
    skip "vstack update refuses unattended" "git not installed"
  else
    # A purpose-made origin with two commits, rather than cloning this repo and stepping back
    # one. CI checks out with fetch-depth 1, so HEAD~1 does not exist there: the reset failed,
    # the clone was already up to date, `update` took its reinstall path and exited 0, and the
    # case failed for a reason that had nothing to do with what it tests. `update` refuses long
    # before it needs a real vstack tree, so a minimal repo is enough.
    U="$ROOT/upd"; mkdir -p "$U/origin"
    git -C "$U/origin" init -q
    git -C "$U/origin" config user.email t@example.com; git -C "$U/origin" config user.name t
    # It has to look like a vstack checkout or bin/vstack ignores VSTACK_DIR and resolves the
    # real repo instead — which is up to date, so `update` reinstalls and exits 0, and the case
    # silently tests the wrong repository.
    mkdir -p "$U/origin/claude"
    printf '{}\n' > "$U/origin/claude/settings.json"
    printf 'one\n' > "$U/origin/f"; git -C "$U/origin" add -A; git -C "$U/origin" commit -qm one
    printf 'two\n' > "$U/origin/f"; git -C "$U/origin" add -A; git -C "$U/origin" commit -qm two
    git clone -q "$U/origin" "$U/repo" 2>/dev/null
    git -C "$U/repo" reset -q --hard HEAD~1
    e=""
    before=$(git -C "$U/repo" rev-parse HEAD)
    # No TTY and no --yes: it must refuse. Assert the invariant that matters — the checkout did
    # not move — rather than only a non-zero exit. A non-zero exit passes when the command fails
    # for some unrelated reason, which is how a test ends up green while measuring nothing.
    # Run the working-tree script against the cloned checkout, not the clone's own copy.
    # `git clone` takes the committed HEAD, so invoking "$U/repo/bin/vstack" would test the last
    # commit rather than the change under review — and would make this case unfalsifiable, which
    # is how I discovered it: mutating bin/vstack changed nothing.
    out=$(HOME="$U" VSTACK_DIR="$U/repo" "$SRC/bin/vstack" update < /dev/null 2>&1); rc=$?
    after=$(git -C "$U/repo" rev-parse HEAD)
    [ "$before" = "$after" ] || e="$e; the checkout advanced without confirmation"
    [ "$rc" = 0 ] && e="$e; exited 0 with no terminal and no --yes"
    printf '%s' "$out" | grep -qiE 'terminal|--yes|aborted' || e="$e; refusal did not say why"
    # And it must have shown what it was about to trust before refusing.
    printf '%s' "$out" | grep -qi 'incoming' || e="$e; refused without showing the incoming commits"
    [ -z "$e" ] && ok "vstack update refuses unattended" || bad "vstack update refuses unattended" "${e#; }"
  fi
fi

# --- recovering from a half-finished or damaged install ------------------------------------------
# install.sh is not transactional: a crash, a full disk, or a kill mid-run leaves a partial tree.
# The claim that re-running is safe has to hold from a damaged state, not only a clean one.
#
# The corrupt-settings case is the one that was actually broken. jq printed a raw parse error,
# the merge silently did nothing, the file stayed unreadable, and install.sh exited with jq's
# status — leaving everything else installed and a settings file Claude Code cannot read, with
# nothing saying which of those had happened.
if want recover; then
  e=""
  recover_probe(){ # <label> <damage-command>
    H="$ROOT/rec-$1"; mkdir -p "$H"
    HOME="$H" "$SRC/install.sh" >/dev/null 2>&1
    eval "$2"
    HOME="$H" "$SRC/install.sh" >/dev/null 2>&1; rrc=$?
    [ "$rrc" = 0 ] || e="$e; $1: re-run exited $rrc"
    [ "$(count_dirs "$H/.claude/skills")" = "$NSK" ]        || e="$e; $1: skills did not converge"
    [ "$(count_files "$H/.claude/hooks" '*.sh')" = "$NHK" ] || e="$e; $1: hooks did not converge"
    [ -f "$H/.config/agents/bin/vstack" ]                   || e="$e; $1: wrappers did not converge"
    if command -v jq >/dev/null 2>&1; then
      jq -e . "$H/.claude/settings.json" >/dev/null 2>&1 || e="$e; $1: settings.json is not valid JSON"
    fi
  }
  recover_probe skills-gone   'rm -rf "$H"/.claude/skills/swarm "$H"/.claude/skills/unslop'
  recover_probe hooks-gone    'rm -f "$H"/.claude/hooks/*.sh'
  recover_probe wrappers-gone 'rm -f "$H"/.config/agents/bin/*'
  recover_probe half-skill    'rm -f "$H"/.claude/skills/swarm/SKILL.md'
  recover_probe bad-settings  'printf "{\"broken\": " > "$H"/.claude/settings.json'
  [ -z "$e" ] && ok "re-running converges from a damaged install" \
    || bad "re-running converges from a damaged install" "${e#; }"
fi

# --- the cloud lane's gate must actually gate --------------------------------------------------
# The overlay case above proves the files land. It did not prove the gate works, and it did not:
# verify-gate.sh refuses to execute a repo's verify.sh without a machine-local trust entry, and
# a fresh sandbox has none. So the Stop gate was installed, wired, and silently skipping on every
# Stop — inert in the one lane that exists for cloud work.
#
# This walks the whole sandbox sequence: overlay a repo, install vstack into an empty HOME the
# way the pinned setup line does, run the trust step that line now performs, break the repo's
# gate, and require the Stop hook to block. Asserting the decision, not the file list, is the
# difference between testing that something is installed and testing that it works.
if want cloud-gate; then
  if ! command -v git >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    skip "cloud sandbox gate blocks" "git or jq not installed"
  else
    T="$ROOT/cloud"; H="$ROOT/cloud-home"; mkdir -p "$T/repo" "$H"
    git -C "$T/repo" init -q
    git -C "$T/repo" config user.email t@example.com; git -C "$T/repo" config user.name t
    printf 'x\n' > "$T/repo/f"; git -C "$T/repo" add -A; git -C "$T/repo" commit -qm init
    "$SRC/overlay.sh" "$T/repo" >/dev/null 2>&1
    e=""
    # TOML escapes the quotes, so the line reads ...bin/vstack\" trust. Match on the command
    # rather than a quoted fragment.
    grep -qE 'bin/vstack.*trust' "$T/repo/.conductor/settings.toml" 2>/dev/null \
      || e="$e; the sandbox setup line does not arm trust"
    # the sandbox: empty HOME, vstack installed by the pinned bootstrap, then the trust step
    HOME="$H" "$SRC/install.sh" >/dev/null 2>&1
    printf '#!/usr/bin/env bash\necho "seeded failure"\nexit 1\n' > "$T/repo/.claude/verify.sh"
    chmod +x "$T/repo/.claude/verify.sh"
    # before arming, it must skip — that is the local protection working as designed
    # TMPDIR is scoped to this run. verify-gate.sh caps repeated blocks per session id in a
    # counter file under TMPDIR, so a test that reuses an id eventually gets a silent exit 0 —
    # the loop cap doing its job, read as the gate having stopped working.
    mkdir -p "$ROOT/cloud-tmp"
    d0=$(printf '{"session_id":"c0"}' | env HOME="$H" TMPDIR="$ROOT/cloud-tmp" CLAUDE_PROJECT_DIR="$T/repo" \
         bash "$SRC/claude/hooks/verify-gate.sh" 2>/dev/null | jq -r '.decision // "none"' 2>/dev/null)
    [ "$d0" = none ] || e="$e; an unarmed repo's gate ran without trust (decision=$d0)"
    # --yes: mirrors the pinned setup line in overlay.sh exactly. `vstack trust` (5922ccf)
    # added a TTY confirmation prompt that refuses without one, and this step -- like the real
    # setup line -- runs with no terminal attached. Testing it without --yes was testing a
    # command the setup line does not actually run.
    ( cd "$T/repo" && HOME="$H" "$H/.config/agents/bin/vstack" trust --yes >/dev/null 2>&1 )
    d1=$(printf '{"session_id":"c1"}' | env HOME="$H" TMPDIR="$ROOT/cloud-tmp" CLAUDE_PROJECT_DIR="$T/repo" \
         bash "$SRC/claude/hooks/verify-gate.sh" 2>/dev/null | jq -r '.decision // "none"' 2>/dev/null)
    [ "$d1" = block ] || e="$e; after arming, a failing gate did not block (decision=$d1)"
    [ -z "$e" ] && ok "cloud sandbox gate blocks after the setup line arms it" \
      || bad "cloud sandbox gate blocks after the setup line arms it" "${e#; }"
  fi
fi

# --- credentials must not be ambient ------------------------------------------------------------
# Filling in one token used to hand it to every child process of every shell: every script in
# every repo, every package postinstall, every tool you try once. The bash lane made it worse by
# adding .bashrc and .profile to the list. Every wrapper in bin/ already loads what it needs.
if want no-ambient-secrets; then
  H="$ROOT/amb"; mkdir -p "$H"
  HOME="$H" "$SRC/install.sh" >/dev/null 2>&1
  e=""
  for rc in .zshenv .zshrc .bashrc .profile; do
    [ -f "$H/$rc" ] || continue
    grep -q 'agents/secrets.env' "$H/$rc" 2>/dev/null && e="$e; $rc exports secrets to every shell"
  done
  # the tuning variables are not secrets and must still be there
  grep -q 'ENABLE_PROMPT_CACHING_1H' "$H/.zshenv" 2>/dev/null || e="$e; the parity env block went missing"
  # and the wrapper must still be able to reach them itself
  grep -q 'secrets.env' "$H/.config/agents/bin/cloudflare-mcp" 2>/dev/null \
    || e="$e; the wrapper no longer loads its own credentials"
  [ -z "$e" ] && ok "credentials are not exported into shells" \
    || bad "credentials are not exported into shells" "${e#; }"
fi

# --- uninstall leaves nothing of vstack behind -------------------------------------------------
# An external audit found that a fresh install followed by a fresh uninstall left six hook
# commands pointing at scripts that had just been deleted, plus vstack's model policy and all
# seventeen skillOverrides still in force. That is not a removed tool, it is a broken one, and
# later sessions can error on the dead hooks.
#
# The user's own settings must survive the same operation, which is the harder half: uninstall
# has to unpick its own entries from a file it merged into, not delete the file.
if want uninstall-clean; then
  H="$ROOT/unclean"; mkdir -p "$H/.claude" "$H/.conductor"
  # things that are theirs, which must all still be here afterwards
  printf '{"theirKey":"keep","theme":"dracula","skillOverrides":{"their-skill":"off"}}\n' > "$H/.claude/settings.json"
  printf 'THEIR_MANAGED=true\n' > "$H/.conductor/settings.managed.toml"
  printf '{"mcpServers":{"their-server":{"command":"theirs"}}}\n' > "$H/.claude.json"
  HOME="$H" "$SRC/install.sh" >/dev/null 2>&1
  # Positive control, taken between install and uninstall. Asserting only that vstack's servers
  # are gone afterwards passes for free on any machine where they were never registered, which
  # is the shape of every fake green this repo has shipped.
  installed_srv=0
  command -v jq >/dev/null 2>&1 \
    && installed_srv=$(jq -r '[(.mcpServers // {}) | keys[]] | length' "$H/.claude.json" 2>/dev/null || echo 0)
  installed_cond=0
  [ -f "$H/.conductor/settings.toml" ] && installed_cond=1
  HOME="$H" "$SRC/uninstall.sh" --yes >/dev/null 2>&1
  e=""
  [ "${installed_cond:-0}" -eq 1 ] || e="$e; install never wrote ~/.conductor/settings.toml, so its removal proves nothing"
  if command -v jq >/dev/null 2>&1; then
    want_srv=$(jq -r 'keys | length' "$SRC/mcp/servers.json" 2>/dev/null || echo 0)
    [ "${installed_srv:-0}" -gt "$want_srv" ] \
      || e="$e; install registered ${installed_srv:-0} MCP servers where theirs plus $want_srv were expected, so the removal assertions below prove nothing"
    n=$(jq -r '[.hooks[]?[]?.hooks[]?.command]|length' "$H/.claude/settings.json" 2>/dev/null || echo 0)
    [ "${n:-0}" -eq 0 ] || e="$e; $n hook commands left pointing at deleted scripts"
    [ "$(jq -r '.model // "gone"' "$H/.claude/settings.json")" = gone ] || e="$e; vstack model policy still in force"
    [ "$(jq -r 'if .statusLine then "left" else "gone" end' "$H/.claude/settings.json")" = gone ] || e="$e; statusLine points at a removed file"
    # and the half that matters more: their own settings are untouched
    [ "$(jq -r '.theirKey // "GONE"' "$H/.claude/settings.json")" = keep ] || e="$e; their own settings key was deleted"
    [ "$(jq -r '.skillOverrides["their-skill"] // "GONE"' "$H/.claude/settings.json")" = off ] || e="$e; their own skillOverride was deleted"
  fi
  grep -q THEIR_MANAGED "$H/.conductor/settings.managed.toml" 2>/dev/null \
    || e="$e; their Conductor managed policy was not restored"
  # install.sh writes ~/.conductor/settings.toml where none exists. uninstall.sh had no
  # reference to conductor at all, so an install into a clean home left both files behind for
  # good -- and the managed one is the pinning file, so a removed vstack went on pinning models.
  [ -f "$H/.conductor/settings.toml" ] && e="$e; ~/.conductor/settings.toml was left behind"
  # Same shape one file over: install.sh merges its servers into the global mcpServers map, and
  # nothing subtracted them again. Theirs must survive, ours must not.
  if command -v jq >/dev/null 2>&1; then
    for srv in $(jq -r 'keys[]' "$SRC/mcp/servers.json" 2>/dev/null); do
      [ "$(jq -r --arg s "$srv" 'if (.mcpServers // {}) | has($s) then "left" else "gone" end' "$H/.claude.json" 2>/dev/null)" = gone ] \
        || e="$e; vstack's $srv MCP server was left registered"
    done
    [ "$(jq -r '(.mcpServers // {})["their-server"].command // "GONE"' "$H/.claude.json" 2>/dev/null)" = theirs ] \
      || e="$e; their own MCP server was removed"
  fi
  [ -f "$H/.config/agents/verify-trust" ] && e="$e; the trust store was left behind"
  for rc in .zshrc .zshenv .bashrc; do
    [ -f "$H/$rc" ] && grep -q 'claude-parity' "$H/$rc" 2>/dev/null && e="$e; $rc still sources vstack"
  done
  [ -z "$e" ] && ok "uninstall removes vstack and keeps your own settings" \
    || bad "uninstall removes vstack and keeps your own settings" "${e#; }"
fi

# --- doctor --drift does not mutate the repo it inspects ---------------------------------------
# A bare `git fetch` is not read-only: it does whatever ~/.gitconfig says. With fetch.prune and
# fetch.pruneTags true -- a common pairing -- it deletes every local tag and remote-tracking
# branch the remote does not have. doctor --drift ran one, and during the 1.9.1 audit it silently
# destroyed an unpushed release tag, after which the release check reported ok for a version
# whose tag was already gone. Ambient config must not be able to turn an inspection into an edit.
if want doctor-no-mutate; then
  if ! command -v git >/dev/null 2>&1; then
    skip "doctor --drift leaves the repo alone" "git not installed"
  else
    T="$ROOT/nomutate"; mkdir -p "$T"
    # A real vstack checkout, because --drift refuses to run against anything else and a scratch
    # repo made it bail before ever reaching the fetch -- which is how the first version of this
    # case passed against the unfixed doctor.
    # A copy of the tree with a fresh history, not a clone. --drift only requires that the
    # directory look like a vstack checkout, and cloning inherited the source repo's shape: CI
    # checks out shallow, a clone of a shallow repo is shallow, and pushing one to a bare remote
    # is rejected outright with "shallow update not allowed". One commit is enough for
    # everything --drift reads.
    mkdir -p "$T/work"
    cp -R "$SRC"/. "$T/work"/ 2>/dev/null
    rm -rf "$T/work/.git"
    git -C "$T/work" init -q
    git -C "$T/work" config user.email t@example.com; git -C "$T/work" config user.name t
    git -C "$T/work" add -A >/dev/null 2>&1
    git -C "$T/work" commit -qm probe >/dev/null 2>&1
    git -C "$T/work" checkout -q -B probe-main
    git init -q --bare "$T/remote.git"
    git -C "$T/work" remote add origin "$T/remote.git"
    # the destructive pairing, set locally so the case does not depend on the operator's config
    git -C "$T/work" config fetch.prune true
    git -C "$T/work" config fetch.pruneTags true
    # push -u in one step. Setting the upstream separately depended on the push having created
    # refs/remotes/origin/probe-main, which it did not do on the CI runners, and the case then
    # failed on its own control with no way to see why from the log.
    git -C "$T/work" push -u origin probe-main > "$T/push.log" 2>&1 || true
    git -C "$T/work" tag -a v9.9.9-local -m "never pushed" 2>/dev/null
    e=""
    # Two positive controls. Without them the case passes on any machine where the tag was never
    # created or where --drift declined to run, which is the shape of every fake green here.
    git -C "$T/work" rev-parse -q --verify refs/tags/v9.9.9-local >/dev/null 2>&1 \
      || e="$e; the probe tag was never created, so this case proves nothing"
    git -C "$T/work" rev-parse --symbolic-full-name '@{u}' >/dev/null 2>&1 \
      || e="$e; no upstream, so the code path under test never runs [$(tr '\n' ' ' < "$T/push.log" 2>/dev/null | cut -c1-160)]"
    HOME="$T" VSTACK_DIR="$T/work" "$SRC/bin/doctor" --drift > "$T/out" 2>&1
    grep -q 'no vstack repo found' "$T/out" 2>/dev/null \
      && e="$e; --drift refused to run, so it never reached the fetch this case is about"
    git -C "$T/work" rev-parse -q --verify refs/tags/v9.9.9-local >/dev/null 2>&1 \
      || e="$e; doctor --drift deleted an unpushed local tag"
    [ -z "$e" ] && ok "doctor --drift leaves the repo alone" \
      || bad "doctor --drift leaves the repo alone" "${e#; }"
  fi
fi

# --- overlay does not delete settings the target repo owns -------------------------------------
# It used to delete every key vstack ships that is not on the project allowlist, on the theory
# that it was cleaning up its own past overlays. It cannot know that. A repository that
# independently set enabledPlugins, theme or forceLoginMethod — names vstack happens to use at
# user scope — lost all three.
if want overlay-preserves; then
  if ! command -v git >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    skip "overlay preserves the target's settings" "git or jq not installed"
  else
    T="$ROOT/ovlkeep"; mkdir -p "$T/.claude"
    git -C "$T" init -q; git -C "$T" config user.email t@example.com; git -C "$T" config user.name t
    printf '{"enabledPlugins":{"theirs@x":true},"theme":"dracula","forceLoginMethod":"console","theirOwn":"keep"}\n' > "$T/.claude/settings.json"
    printf 'x\n' > "$T/f"; git -C "$T" add -A; git -C "$T" commit -qm init
    "$SRC/overlay.sh" "$T" >/dev/null 2>&1
    e=""
    for k in enabledPlugins theme forceLoginMethod theirOwn; do
      [ "$(jq -r "if has(\"$k\") then \"kept\" else \"DELETED\" end" "$T/.claude/settings.json")" = kept ] \
        || e="$e; the target's $k was deleted"
    done
    # and vstack's own keys still arrive
    [ "$(jq -r '.skillOverrides|length' "$T/.claude/settings.json")" -gt 0 ] || e="$e; vstack's own keys did not land"
    [ -z "$e" ] && ok "overlay preserves the target's settings" || bad "overlay preserves the target's settings" "${e#; }"
  fi
fi

# --- a stranger's clean install reports healthy, not broken -------------------------------------
# doctor mixed what vstack installs with what the operator happens to have: the author's Claude
# plan, their ~/Projects layout, their optional plugins. On a fresh machine eight of those went
# red at once and no amount of re-installing could clear a single one, so the first thing a new
# user saw after a successful install was DRIFT ✖. What vstack ships still fails hard; the rest
# is now reported as a note.
if want doctor-stranger; then
  H="$ROOT/stranger"; mkdir -p "$H"
  HOME="$H" "$SRC/install.sh" >/dev/null 2>&1
  if [ ! -x "$H/.config/agents/bin/doctor" ]; then
    bad "doctor is green on a clean install" "install did not place bin/doctor"
  else
    out=$(HOME="$H" "$H/.config/agents/bin/doctor" 2>&1); rc=$?
    reds=$(printf '%s' "$out" | grep -c '✖' || true)
    if [ "$rc" -eq 0 ] && [ "${reds:-0}" -eq 0 ]; then
      ok "doctor is green on a clean install ($(printf '%s' "$out" | grep -c '·') note(s), 0 failures)"
    else
      bad "doctor is green on a clean install" \
          "exit $rc with $reds failure(s): $(printf '%s' "$out" | grep '✖' | sed 's/  */ /g' | tr '\n' ';')"
    fi
  fi
fi

echo
printf '%d passed, %d failed' "$PASS" "$FAIL"
[ "$SKIP" -gt 0 ] && printf ', %d skipped' "$SKIP"
printf '\n'
[ "$FAIL" -eq 0 ] && echo "MATRIX OK" || echo "MATRIX FAILED"
exit "$FAIL"
