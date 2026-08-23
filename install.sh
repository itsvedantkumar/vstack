#!/usr/bin/env bash
# install.sh — install the whole vstack bundle onto this Mac.
#
# Idempotent: safe to re-run any number of times. Every file it overwrites is copied to a
# timestamped backup dir first, and it never touches secrets you already have.
#
# Lanes it materialises:
#   $CLAUDE_CONFIG_DIR, or ~/.claude   hooks, agents, commands, skills, settings
#   ~/.config/agents/bin/      CLI wrappers (deploy, headless runner, MCP shims, doctor)
#   ~/.config/agents/shell/    zsh parity wrapper + env snippet, wired into .zshrc/.zshenv
#   .claude.json               MCP server entries (merged, never clobbered)
#
# Usage:
#   ./install.sh                  install the config
#   ./install.sh --with-deps      install the tools first (fresh machine)
#   ./install.sh --bypass-permissions
#                                 stop asking before every tool call. Deliberately opt-in:
#                                 this repo is public, and nobody should get it by default.
#   ./install.sh --dry-run        print what would change, touch nothing
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Claude Code reads its user config from $CLAUDE_CONFIG_DIR when that is set, and from
# ~/.claude otherwise. vstack hardcoded ~/.claude, so anyone running with CLAUDE_CONFIG_DIR
# pointed elsewhere — VMs, containers, and anyone keeping separate profiles — got a complete,
# clean-looking install into a directory Claude Code never reads. It failed silently and
# looked like success, which is the worst way for an installer to be wrong.
#
# .claude.json follows the same rule: it sits inside the config dir when one is named, and
# beside it at ~/.claude.json when it is not.
CDIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then CJSON="$CDIR/.claude.json"; else CJSON="$HOME/.claude.json"; fi
# Second-resolution timestamps collide, and mkdir -p is happy to reuse the directory. Two
# installs in the same second therefore shared one backup, and the second run overwrote the
# first run's copies with files vstack had just installed — destroying the only record of what
# the user had before. Automation, retries and CI hit this easily. Claim the directory
# exclusively and step to a suffix when it is taken.
BK_BASE="$HOME/.config/agents/backups/install-$(date +%Y%m%d-%H%M%S)"
BK="$BK_BASE"
# Set only once `mkdir "$BK"` has actually succeeded below. BK itself is assigned unconditionally
# right above, so guarding abort_note on `[ "${BK:-}" = "" ]` never fired -- BK is never empty --
# and a run that died before the backup directory could even be created (HOME unwritable, disk
# full, no permission on ~/.config) still printed "every file this run touched was copied to $BK
# first" pointing at a path that was never made. This flag is the actual truth the message needs.
BK_CREATED=0
DRY=0
WITH_DEPS=0
BYPASS=0
for a in "$@"; do
  case "$a" in
    --bypass-permissions) BYPASS=1 ;;
    --with-deps)    WITH_DEPS=1 ;;
    --dry-run)      DRY=1 ;;
    -h|--help)      sed -n '2,18p' "$0"; exit 0 ;;
    *) echo "unknown flag: $a" >&2; exit 2 ;;
  esac
done

say(){ printf '%s\n' "$*"; }

# Every jq merge below was `jq -e . "$tmp" >/dev/null && cat "$tmp" > "$dest"`, followed
# unconditionally by say "merged ...". When jq produced nothing usable the && short-circuited,
# the destination kept its old contents, and the install still printed "merged" and exited 0 --
# so a settings merge that silently did not happen looked exactly like one that did. Failure has
# to be visible, name the backup, and survive to the exit code.
DEGRADED=0

# set -e means any failing command aborts mid-install. That is the right call -- continuing past
# a broken merge is how you get a half-configured machine -- but the bare abort printed a raw jq
# error and stopped, leaving the user staring at a partial install with no idea whether their
# own files had survived. They always had; nobody was ever told where.
abort_note(){
  st=$?
  [ "$st" = 0 ] && return 0
  [ "$BK_CREATED" = 1 ] || return 0
  [ "$DRY" = 1 ] && return 0
  printf '\ninstall aborted (exit %s). Nothing of yours was lost:\n' "$st"
  printf '  every file this run touched was copied to %s first\n' "$BK"
  printf '  restore with: %s/uninstall.sh\n' "$SRC"
  printf '  this installer is safe to re-run once the cause above is fixed\n'
}
trap abort_note EXIT

commit_json(){ # <tmp> <dest> <what>
  if jq -e . "$1" >/dev/null 2>&1; then
    cat "$1" > "$2"; rm -f "$1"; return 0
  fi
  rm -f "$1"
  DEGRADED=1
  say "FAILED     $3 was NOT written -- the merge produced invalid JSON"
  say "           $2 is unchanged; your copy from before this run is in $BK"
  return 1
}
run(){ if [ "$DRY" = 1 ]; then say "would: $*"; else "$@"; fi; }

[ -f "$SRC/claude/settings.json" ] || { echo "error: run this from the vstack repo" >&2; exit 1; }

# --with-deps installs the tools first. Kept opt-in here because a normal re-install should
# not reach for a package manager; bootstrap.sh turns it on for fresh machines.
if [ "$WITH_DEPS" = 1 ] && [ -x "$SRC/setup-machine.sh" ]; then
  if [ "$DRY" = 1 ]; then "$SRC/setup-machine.sh" --dry-run; else "$SRC/setup-machine.sh"; fi
  echo
fi

# jq drives the two merge steps (settings, MCP). Linux cloud sandboxes often lack it, and
# skills plus hooks are still worth installing there, so degrade instead of aborting.
HAVE_JQ=1
command -v jq >/dev/null || { HAVE_JQ=0; echo "warn: jq not found — settings and MCP merge will be skipped (brew install jq / apt install jq)" >&2; }

if [ "$DRY" = 0 ]; then
  # Claim the backup directory exclusively. `mkdir -p` is happy to reuse one, and the timestamp
  # only has second resolution, so two installs in the same second shared a directory and the
  # second overwrote the first's copies with files vstack had just installed — destroying the
  # only record of what the user had before. Automation and retries hit this easily.
  mkdir -p "$(dirname "$BK_BASE")"
  bn=1
  until mkdir "$BK" 2>/dev/null; do
    BK="$BK_BASE-$bn"
    bn=$((bn+1))
    [ "$bn" -gt 500 ] && { echo "error: cannot create a backup dir under $(dirname "$BK_BASE")" >&2; exit 1; }
  done
  BK_CREATED=1
  mkdir -p "$CDIR/hooks" "$CDIR/agents" "$CDIR/commands" \
           "$CDIR/skills" \
           "$HOME/.config/agents/bin" "$HOME/.config/agents/shell"
  chmod 700 "$HOME/.config/agents/backups"
fi
# Backups preserve the real path under files/ — the old flat `tr / _` names were a lossy
# encoding that misparsed any future filename containing an underscore on restore.
back(){ [ "$DRY" = 1 ] && return 0; [ -f "$1" ] || return 0
  # Paths under $HOME are stored HOME-relative so uninstall can map them back. A config dir
  # moved outside $HOME by CLAUDE_CONFIG_DIR has no such relative form, so it is stored under
  # files_abs/ with its full path and restored to exactly where it came from.
  case "$1" in
    "$HOME"/*) rel="${1#$HOME/}"; dest="$BK/files/$rel" ;;
    *)         dest="$BK/files_abs${1}" ;;
  esac
  mkdir -p "$(dirname "$dest")"
  cp "$1" "$dest"
  return 0
}

# Record where this install came from so doctor --drift and `vstack` can find the repo even
# when it is cloned somewhere other than ~/.vstack and $VSTACK_DIR is unset.
[ "$DRY" = 0 ] && printf '%s\n' "$SRC" > "$HOME/.config/agents/vstack-repo"

# Trust this repo's own verify.sh for the Stop-hook gate: running install.sh IS the explicit
# consent. Other repos' gates stay off until the user runs `vstack trust` there — the gate
# executes repo-controlled code, so a bare clone must never arm it by itself.
if [ "$DRY" = 0 ] && [ -f "$SRC/.claude/verify.sh" ]; then
  tv="$(cd "$SRC/.claude" && pwd)/verify.sh"
  if command -v shasum >/dev/null 2>&1; then th=$(shasum -a 256 "$tv" | cut -d' ' -f1)
  else th=$(sha256sum "$tv" | cut -d' ' -f1); fi
  tf="$HOME/.config/agents/verify-trust"
  ttmp=$(mktemp); grep -vF "  $tv" "$tf" 2>/dev/null > "$ttmp" || true
  printf '%s  %s\n' "$th" "$tv" >> "$ttmp"; mv "$ttmp" "$tf"
  say "trusted    $SRC/.claude/verify.sh (verify gate)"
fi

# --- hooks / agents / commands ------------------------------------------------------------
for f in "$SRC"/claude/hooks/*.sh;    do back "$CDIR/hooks/$(basename "$f")"; run cp "$f" "$CDIR/hooks/"; done
for f in "$SRC"/claude/agents/*.md;   do back "$CDIR/agents/$(basename "$f")";   run cp "$f" "$CDIR/agents/";   done
for f in "$SRC"/claude/commands/*.md; do back "$CDIR/commands/$(basename "$f")"; run cp "$f" "$CDIR/commands/"; done
[ "$DRY" = 0 ] && chmod 755 "$CDIR"/hooks/*.sh
say "installed  hooks, agents, commands"

# --- global directives + statusline ---------------------------------------------------------
# CLAUDE.md is the standing instruction file every session reads. It is backed up first: it is
# the file most likely to have been hand-edited on a machine that has been running a while.
back "$CDIR/CLAUDE.md"
run cp "$SRC/claude/CLAUDE.md" "$CDIR/CLAUDE.md"
back "$CDIR/statusline.sh"
run cp "$SRC/claude/statusline.sh" "$CDIR/statusline.sh"
[ "$DRY" = 0 ] && chmod 755 "$CDIR/statusline.sh"
say "installed  CLAUDE.md, statusline.sh"

# --- conductor user settings ------------------------------------------------------------------
# Conductor reads model and workflow defaults from here. Only written when absent: these are
# per-person preferences, and clobbering them would change how every workspace launches.
if [ ! -f "$HOME/.conductor/settings.toml" ]; then
  [ "$DRY" = 0 ] && { mkdir -p "$HOME/.conductor"; cp "$SRC/conductor/settings.toml" "$HOME/.conductor/settings.toml"; }
  say "installed  ~/.conductor/settings.toml"
else
  say "kept       existing ~/.conductor/settings.toml"
fi

# The managed layer is different: it exists to pin model/fastMode/plan-mode above the Settings
# UI, so it is ALWAYS overwritten — a managed file that install leaves alone is just a second
# preferences file. The pins and their rationale live in conductor/settings.managed.toml.
if [ -f "$SRC/conductor/settings.managed.toml" ]; then
  # Backed up first. This file is always overwritten by design — a managed layer that install
  # leaves alone is just a second preferences file — but overwriting without a backup is how
  # someone already using Conductor managed settings loses machine-wide policy on first install,
  # with nothing to restore from. It is the only file this installer replaced unconditionally
  # and unrecoverably.
  back "$HOME/.conductor/settings.managed.toml"
  [ "$DRY" = 0 ] && { mkdir -p "$HOME/.conductor"; cp "$SRC/conductor/settings.managed.toml" "$HOME/.conductor/settings.managed.toml"; }
  say "pinned     ~/.conductor/settings.managed.toml (models, fast mode, plan mode)"
fi

# --- skills -------------------------------------------------------------------------------
# Whole-dir replace per skill: they carry references/ and scripts/ subtrees, so a file-by-file
# copy would leave stale files behind after an upstream removal. Only touches skills this repo
# owns; never deletes skills you wrote yourself.
for d in "$SRC"/claude/skills/*/; do
  s=$(basename "$d")
  [ "$DRY" = 1 ] && { say "would: install skill $s"; continue; }
  [ -d "$CDIR/skills/$s" ] && cp -R "$CDIR/skills/$s" "$BK/skills_$s"
  rm -rf "${CDIR:?}/skills/$s"
  # NB: strip the trailing slash. BSD/macOS `cp -R src/ dest/` copies src CONTENTS into dest,
  # not src itself, which would scatter SKILL.md and references/ across the skills root.
  cp -R "${d%/}" "$CDIR/skills/"
done
# The licence and the attribution travel with the skills. Shipping LICENSE.pstack alone left
# the installed tree claiming one origin for skills that actually come from four.
for meta in LICENSE.pstack ATTRIBUTION.md; do
  [ -f "$SRC/claude/skills/$meta" ] && run cp "$SRC/claude/skills/$meta" "$CDIR/skills/"
done
[ "$DRY" = 0 ] && find "$CDIR/skills" -name "*.sh" -exec chmod 755 {} + 2>/dev/null
say "installed  skills ($(find "$SRC"/claude/skills -maxdepth 1 -mindepth 1 -type d | wc -l | tr -d ' '))"

# --- agent bin ----------------------------------------------------------------------------
for f in "$SRC"/bin/*; do
  b=$(basename "$f")
  back "$HOME/.config/agents/bin/$b"
  run cp "$f" "$HOME/.config/agents/bin/$b"
done
[ "$DRY" = 0 ] && chmod 755 "$HOME"/.config/agents/bin/*
say "installed  bin wrappers"

# --- secrets scaffold ---------------------------------------------------------------------
# Never overwrite real secrets. Only create the file (from the example) when it is absent.
SE="$HOME/.config/agents/secrets.env"
if [ ! -f "$SE" ]; then
  run cp "$SRC/secrets.env.example" "$SE"
  [ "$DRY" = 0 ] && chmod 600 "$SE"
  say "created    secrets.env from example — fill it in"
else
  [ "$DRY" = 0 ] && chmod 600 "$SE"
  say "kept       existing secrets.env (chmod 600)"
fi

# --- settings ------------------------------------------------------------------------------
# Merge the portable subset INTO existing user settings, then rebuild hooks with absolute
# paths (user scope has no $CLAUDE_PROJECT_DIR). The portable file is authoritative for
# every key it ships — including enabledPlugins and skillOverrides, which is replaced
# wholesale so overrides for deleted skills don't linger in the live file forever. Keys the
# portable file never mentions (forceLoginMethod / remote / permissions) survive untouched.
#
# RETIRED is the part that used to be a lie: the comment here claimed retired keys were
# del()ed "explicitly below" and no such code was ever written, so a key this repo dropped
# would sit in the live file forever. A merge that cannot delete is an accumulator.
#
# It is EMPTY, and that is the correct value today. This list may only ever name a key that
# claude/settings.json itself once shipped and no longer does. Across every revision of that
# file the union of its top-level keys equals the count shipped today: this repo has never
# retired one. Check the two numbers against each other rather than against a number written
# here — the previous wording hardcoded 27, and was stale at 28 before anyone noticed.
#
# Read that before adding anything here. The first draft of this list was invented from
# plausible-sounding names — "sandbox", "enabledMcpjsonServers", "autoCompactEnabled" — none
# of which this repo has ever shipped. They are Claude Code's own settings. Shipping that list
# would have silently stripped a user's native Bash sandboxing on every install of a public
# repo: a security feature, deleted without a word, on someone else's machine. Deleting a key
# vstack does not own is not cleanup, it is vandalism with a changelog.
#
# To add one: confirm with
#   for s in $(git log --all --format=%H -- claude/settings.json); do
#     git show "${s}:claude/settings.json" | jq -r 'keys[]'; done | sort -u
# that the key appears there and not in the current file. Check 21 enforces exactly that.
RETIRED='[]'
US="$CDIR/settings.json"; back "$US"
[ -f "$US" ] || { [ "$DRY" = 0 ] && echo '{}' > "$US"; }

# A settings.json that does not parse is not a merge problem, it is a broken file. It happens:
# a crash or a full disk mid-write, or a hand edit that dropped a brace. Until now the merge
# just failed — jq printed a raw parse error, the file stayed corrupt, install.sh exited with
# jq's status, and the user was left with everything else installed and a settings file Claude
# Code cannot read at all. Nothing said which of those things had happened.
#
# The backup was already taken above, so the honest move is to say so loudly and start from a
# known-good file. Keeping an unparseable one helps nobody: Claude Code cannot read it either.
if [ "$DRY" = 0 ] && [ "$HAVE_JQ" = 1 ] && [ -s "$US" ]; then
  if ! jq -e . "$US" >/dev/null 2>&1; then
    say "WARNING    $US did not parse as JSON and has been replaced."
    say "           your copy is safe at $BK/files/${US#"$HOME"/}"
    say "           re-apply anything you need from it by hand."
    echo '{}' > "$US"
  fi
fi
if [ "$DRY" = 0 ] && [ "$HAVE_JQ" = 0 ]; then
  # No jq: never hand-merge JSON. Write the portable settings only when there is nothing
  # to lose, otherwise leave the existing file untouched.
  if [ ! -s "$US" ] || [ "$(cat "$US")" = "{}" ]; then
    # Rewrite the hook paths on the way in. The shipped file addresses hooks as
    # $CLAUDE_PROJECT_DIR/.claude/hooks/... because that is correct for the overlay lane, where
    # the hooks live in the repo. At user scope there is no project dir, so copying the file
    # verbatim produced an install that reported success and wired every hook to a path that
    # does not exist — exit 127 on every session start, every stop, every tool failure. The
    # gate, the routing and the formatter were all inert, on exactly the jq-less sandboxes this
    # branch exists to support.
    #
    # It is a textual substitution rather than a JSON edit, which is the only honest option
    # without jq, and it is safe here because the target is a file this repo controls.
    sed "s|\$CLAUDE_PROJECT_DIR/.claude/hooks|$CDIR/hooks|g" \
      "$SRC/claude/settings.json" > "$US"
    say "wrote      $US (no jq — hook paths rewritten to $CDIR/hooks; no statusline, no MCP merge)"
  else
    say "skipped    settings merge (no jq — existing settings left untouched)"
  fi
elif [ "$DRY" = 0 ]; then
  tmp=$(mktemp)
  # Hooks and skillOverrides are merged by ownership, not replaced wholesale.
  #
  # Replacing them was silent destruction. A user with a Notification hook, a PreToolUse policy
  # or security hook, or a skillOverride for a skill of their own lost every one of them on
  # install — no prompt, no mention in the output, just a backup they had no reason to know they
  # needed. The wholesale replace existed to stop overrides for deleted skills lingering
  # forever, which is a real problem, but the cure removed configuration this repo does not own.
  #
  # Ownership is decided by what a hook command points at: anything under this install's hooks
  # directory is ours to rebuild, and anything else is theirs to keep. Legacy notifier entries
  # are dropped by name, since the integration they served is gone.
  #
  # skillOverrides merge with ours winning on collision. A stale entry naming a skill nobody
  # ships is inert — Claude Code ignores it — and losing a user's override is not.
  jq -s --arg h "$CDIR/hooks" --argjson retired "$RETIRED" '
    ((.[1] | del(.hooks)) as $portable
      | (.[0].hooks // {}) as $userhooks
      | (.[0].skillOverrides // {}) as $userso
      | {
          SessionStart: [
            { hooks: [ {type:"command", command:($h+"/inject-session-context.sh"), statusMessage:"context"} ] } ],
          UserPromptSubmit: [
            { hooks: [ {type:"command", command:($h+"/inject-session-context.sh")} ] } ],
          PreToolUse: [
            { matcher:"Bash",
              hooks: [ {type:"command", command:($h+"/guard-destructive.sh"), statusMessage:"guard"} ] } ],
          PostToolUse: [
            { matcher:"Edit|Write|MultiEdit",
              hooks: [ {type:"command", command:($h+"/format.sh"), statusMessage:"format"} ] } ],
          Stop: [
            { hooks: [ {type:"command", command:($h+"/verify-gate.sh")},
                       {type:"command", command:($h+"/skill-mandate.sh")} ] } ],
          PostToolUseFailure: [
            { matcher:"*", hooks: [ {type:"command", command:($h+"/failure-diagnose.sh")} ] } ]
        } as $ours
      # Basenames of every command $ours ships (inject-session-context.sh, guard-destructive.sh,
      # ...), derived from $ours itself rather than duplicated, so this list can never drift out
      # of sync with the hooks actually installed above.
      | ([$ours | .. | .command? // empty] | map(split("/") | last) | unique) as $ourbasenames
      | ($userhooks
          | with_entries(.value |= map(select(
              [.hooks[]?.command]
              # Matched by shape (a path ending in .../hooks/<one of our filenames>), not by
              # startswith($h) against the CURRENT $CDIR/hooks. startswith tied ownership to
              # THIS machine HOME at merge time, so a settings.json copied from a different HOME
              # (a new machine, a restored backup, a renamed account) had its own vstack entries
              # treated as user-authored forever, because they no longer started with $h -- doctor
              # stayed green while every reinstall appended a duplicate SessionStart entry
              # pointing at a path that no longer exists. A path is ours if its immediate parent
              # directory is literally named "hooks" and its filename is one $ours installs; that
              # survives a HOME move without also claiming a same-named script a user keeps in
              # some unrelated hooks directory of their own, since that script is never one of
              # ours by name.
              | map(
                  . as $cmd
                  | ($cmd | test("SUPERSET_HOME_DIR"))
                  or ($ourbasenames | any(. as $b | $cmd | endswith("/hooks/" + $b)))
                )
              | any | not )))
          | with_entries(select(.value | length > 0))) as $theirs
      | (.[0] * $portable)
      | .skillOverrides = ($userso + ($portable.skillOverrides // {}))
      | del(.enabledPlugins["claude-mem@thedotmack"]?)
      | delpaths([$retired[] | [.]])
      | .hooks = (reduce ($ours | to_entries[]) as $e
                   ($theirs; .[$e.key] = (($theirs[$e.key] // []) + $e.value)))
      | .statusLine = {type:"command", command:(($h|rtrimstr("/hooks")) + "/statusline.sh"), padding:0, refreshInterval:3})
  ' "$US" "$SRC/claude/settings.json" > "$tmp"
  # shellcheck disable=SC2088  # the third argument is a label printed to the operator
  if commit_json "$tmp" "$US" "~/.claude/settings.json"; then
    if [ "$BYPASS" = 1 ]; then
      tmp=$(mktemp)
      jq '.permissions.defaultMode = "bypassPermissions" | .skipDangerousModePermissionPrompt = true' "$US" > "$tmp"
      commit_json "$tmp" "$US" "~/.claude/settings.json (bypassPermissions)" \
        && say "merged     ~/.claude/settings.json (+ bypassPermissions)"
    else
      say "merged     ~/.claude/settings.json"
    fi
  fi
fi

# --- MCP servers ---------------------------------------------------------------------------
# Merged into the GLOBAL mcpServers map. Ours win on key collision; anything else you have
# configured is preserved. Project-scoped servers stay yours to add (see mcp/README).
CJ="$CJSON"
if [ "$HAVE_JQ" = 0 ]; then
  say "skipped    MCP merge (no jq)"
elif [ "$DRY" = 0 ]; then
  # The file is created when absent rather than skipped.
  #
  # This branch used to require $CJSON to already exist, which is never true on a machine that
  # has not run Claude Code yet -- exactly the machine running this installer. The result was
  # that a first install printed "run claude once, then re-run this" and every stranger who
  # followed the README once, as instructed, ended up without a single MCP server. The README
  # says these ship. They did not. bin/doctor now checks the same thing from the other side.
  if [ -f "$CJ" ]; then cp "$CJ" "$BK/claude.json"; else printf '{}\n' > "$CJ"; fi
  tmp=$(mktemp)
  sed "s|__HOME__|$HOME|g" "$SRC/mcp/servers.json" > "$tmp.servers"
  jq -s '.[0] as $cur | .[1] as $new | $cur | .mcpServers = (($cur.mcpServers // {}) * $new)' \
     "$CJ" "$tmp.servers" > "$tmp"
  commit_json "$tmp" "$CJ" "MCP servers in $CJSON" \
    && say "merged     MCP servers into $CJSON"
  rm -f "$tmp" "$tmp.servers"
else
  say "skipped    MCP merge (dry run)"
fi

# --- shell lane ----------------------------------------------------------------------------
run cp "$SRC/shell/claude-parity.zsh" "$HOME/.config/agents/shell/"
back "$HOME/.zshrc"
if [ "$DRY" = 0 ] && ! grep -q '>>> claude-parity >>>' "$HOME/.zshrc" 2>/dev/null; then
  printf '\n# >>> claude-parity >>>\n[ -f "$HOME/.config/agents/shell/claude-parity.zsh" ] && . "$HOME/.config/agents/shell/claude-parity.zsh"\n# <<< claude-parity <<<\n' >> "$HOME/.zshrc"
fi
back "$HOME/.zshenv"
if [ "$DRY" = 0 ] && ! grep -q '>>> claude-parity env >>>' "$HOME/.zshenv" 2>/dev/null; then
  cat "$SRC/shell/zshenv.snippet" >> "$HOME/.zshenv"
fi
# Credentials are NOT exported into your shells, and any earlier line that did is removed.
#
# Leaving it behind would mean the fix only reached new machines while every existing install
# kept leaking. vstack wrote that line, so vstack takes it out — matched exactly, backed up
# first, and only ever the form this installer produced. A line you wrote yourself that happens
# to mention secrets.env is not touched.
if [ "$DRY" = 0 ]; then
  for rc in .zshenv .zshrc .bashrc .profile; do
    [ -f "$HOME/$rc" ] || continue
    grep -q 'set -a && \. "$HOME/.config/agents/secrets.env" && set +a' "$HOME/$rc" 2>/dev/null || continue
    back "$HOME/$rc"
    tmp=$(mktemp)
    grep -vF '[ -f "$HOME/.config/agents/secrets.env" ] && set -a && . "$HOME/.config/agents/secrets.env" && set +a' "$HOME/$rc" > "$tmp" && cat "$tmp" > "$HOME/$rc"
    rm -f "$tmp"
    say "removed    credential export from ~/$rc (wrappers load their own; backup in $BK)"
  done
fi

# Credentials are NOT exported into your shells.
#
# This used to source secrets.env with `set -a` into .zshenv, and then — when the bash lane was
# added — into .bashrc and .profile too, which widened it rather than fixing it. The effect was
# that filling in a Cloudflare token handed it to every child process of every shell: every
# script in every repo you cd into, every package postinstall, every tool you try once.
#
# Nothing needed it. Every wrapper in bin/ already loads secrets.env itself (see
# bin/cloudflare-mcp), which is the correct scope: the process that needs the credential reads
# it, and nothing else sees it. The parity block above stays, because those are CLAUDE_* tuning
# variables, not secrets.

# bash gets the same environment. The wrapper does not travel — claude-parity.zsh is written
# in zsh (whence -p, print -r, local -a) and cannot be sourced by bash — but the env snippet
# and the secrets line are plain POSIX exports, and they are the part that actually changes
# behaviour: the 1h prompt cache, tool concurrency, streaming, task support.
#
# Only zsh users got any of it, which meant a default Debian, Ubuntu or Alpine box — every
# cloud VM and nearly every container — installed cleanly and then ran with none of it. Both
# rc files are written when both shells are present, because a machine can have both.
SHELL_LANES=".zshrc, .zshenv"
if [ "$DRY" = 0 ]; then
  for rc in .bashrc .profile; do
    # .profile only when there is no .bashrc: writing both double-exports on login shells.
    [ "$rc" = .profile ] && [ -f "$HOME/.bashrc" ] && continue
    [ "$rc" = .bashrc ] || [ -f "$HOME/$rc" ] || [ -n "${BASH_VERSION:-}" ] || continue
    back "$HOME/$rc"
    if ! grep -q '>>> claude-parity env >>>' "$HOME/$rc" 2>/dev/null; then
      cat "$SRC/shell/zshenv.snippet" >> "$HOME/$rc"
      SHELL_LANES="$SHELL_LANES, $rc"
    fi
  done
  case "${SHELL:-}" in
    *zsh) ;;
    *) say "note       the claude wrapper is zsh-only; \$SHELL is ${SHELL:-unset}, so you get the env lane without it" ;;
  esac
fi
say "installed  shell lane ($SHELL_LANES)"

# --- verify ----------------------------------------------------------------------------------
say ""
if [ "$DRY" = 1 ]; then
  say "dry run complete — nothing was changed."
  exit 0
fi
say "backup: $BK"
say ""
if [ -x "$HOME/.config/agents/bin/doctor" ]; then
  if ! "$HOME/.config/agents/bin/doctor"; then
    say ""
    say "doctor reports drift above. Most causes are one-time setup steps it cannot do for you:"
    say "  - fill in ~/.config/agents/secrets.env"
    say "  - exec zsh -l   (to pick up the shell lane)"
  fi
fi
if [ "$DEGRADED" = 1 ]; then
  say ""
  say "install finished with failures above. Nothing was lost -- the originals are in $BK --"
  say "but the setup is incomplete. Fix the cause and re-run; this is safe to run twice."
  exit 1
fi
say "run: exec zsh -l"
