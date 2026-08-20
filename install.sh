#!/usr/bin/env bash
# install.sh — install the whole vstack bundle onto this Mac.
#
# Idempotent: safe to re-run any number of times. Every file it overwrites is copied to a
# timestamped backup dir first, and it never touches secrets you already have.
#
# Lanes it materialises:
#   ~/.claude/                 hooks, agents, commands, skills, settings
#   ~/.config/agents/bin/      CLI wrappers (deploy, headless runner, MCP shims, doctor)
#   ~/.config/agents/shell/    zsh parity wrapper + env snippet, wired into .zshrc/.zshenv
#   ~/.claude.json             MCP server entries (merged, never clobbered)
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
BK="$HOME/.config/agents/backups/install-$(date +%Y%m%d-%H%M%S)"
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
  mkdir -p "$BK" "$HOME/.claude/hooks" "$HOME/.claude/agents" "$HOME/.claude/commands" \
           "$HOME/.claude/skills" \
           "$HOME/.config/agents/bin" "$HOME/.config/agents/shell"
  chmod 700 "$HOME/.config/agents/backups"
fi
# Backups preserve the real path under files/ — the old flat `tr / _` names were a lossy
# encoding that misparsed any future filename containing an underscore on restore.
back(){ [ "$DRY" = 1 ] && return 0; [ -f "$1" ] || return 0
  rel="${1#$HOME/}"
  mkdir -p "$BK/files/$(dirname "$rel")"
  cp "$1" "$BK/files/$rel"
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
for f in "$SRC"/claude/hooks/*.sh;    do back "$HOME/.claude/hooks/$(basename "$f")"; run cp "$f" "$HOME/.claude/hooks/"; done
for f in "$SRC"/claude/agents/*.md;   do back "$HOME/.claude/agents/$(basename "$f")";   run cp "$f" "$HOME/.claude/agents/";   done
for f in "$SRC"/claude/commands/*.md; do back "$HOME/.claude/commands/$(basename "$f")"; run cp "$f" "$HOME/.claude/commands/"; done
[ "$DRY" = 0 ] && chmod 755 "$HOME"/.claude/hooks/*.sh
say "installed  hooks, agents, commands"

# --- global directives + statusline ---------------------------------------------------------
# CLAUDE.md is the standing instruction file every session reads. It is backed up first: it is
# the file most likely to have been hand-edited on a machine that has been running a while.
back "$HOME/.claude/CLAUDE.md"
run cp "$SRC/claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
back "$HOME/.claude/statusline.sh"
run cp "$SRC/claude/statusline.sh" "$HOME/.claude/statusline.sh"
[ "$DRY" = 0 ] && chmod 755 "$HOME/.claude/statusline.sh"
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
  [ -d "$HOME/.claude/skills/$s" ] && cp -R "$HOME/.claude/skills/$s" "$BK/skills_$s"
  rm -rf "${HOME:?}/.claude/skills/$s"
  # NB: strip the trailing slash. BSD/macOS `cp -R src/ dest/` copies src CONTENTS into dest,
  # not src itself, which would scatter SKILL.md and references/ across the skills root.
  cp -R "${d%/}" "$HOME/.claude/skills/"
done
# The licence and the attribution travel with the skills. Shipping LICENSE.pstack alone left
# the installed tree claiming one origin for skills that actually come from four.
for meta in LICENSE.pstack ATTRIBUTION.md; do
  [ -f "$SRC/claude/skills/$meta" ] && run cp "$SRC/claude/skills/$meta" "$HOME/.claude/skills/"
done
[ "$DRY" = 0 ] && find "$HOME/.claude/skills" -name "*.sh" -exec chmod 755 {} + 2>/dev/null
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
# claude/settings.json itself once shipped and no longer does. Across all 11 revisions of that
# file the union of its top-level keys is 27, and 27 are shipped today: this repo has never
# retired one.
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
US="$HOME/.claude/settings.json"; back "$US"
[ -f "$US" ] || { [ "$DRY" = 0 ] && echo '{}' > "$US"; }
if [ "$DRY" = 0 ] && [ "$HAVE_JQ" = 0 ]; then
  # No jq: never hand-merge JSON. Write the portable settings only when there is nothing
  # to lose, otherwise leave the existing file untouched.
  if [ ! -s "$US" ] || [ "$(cat "$US")" = "{}" ]; then
    cp "$SRC/claude/settings.json" "$US"
    say "wrote      ~/.claude/settings.json (no jq — hook paths stay relative)"
  else
    say "skipped    settings merge (no jq — existing settings left untouched)"
  fi
elif [ "$DRY" = 0 ]; then
  tmp=$(mktemp)
  jq -s --arg h "$HOME/.claude/hooks" --argjson retired "$RETIRED" '
    ((.[1] | del(.hooks)) as $portable
      | (.[0] * $portable)
      | .skillOverrides = ($portable.skillOverrides // {})
      | delpaths([$retired[] | [.]]))
    | .hooks = {
        SessionStart: [
          { hooks: [ {type:"command", command:($h+"/inject-session-context.sh"), statusMessage:"context"} ] } ],
        UserPromptSubmit: [
          { hooks: [ {type:"command", command:($h+"/inject-session-context.sh")} ] } ],
        PostToolUse: [
          { matcher:"Edit|Write|MultiEdit",
            hooks: [ {type:"command", command:($h+"/format.sh"), statusMessage:"format"} ] } ],
        Stop: [
          { hooks: [ {type:"command", command:($h+"/verify-gate.sh")} ] } ],
        PostToolUseFailure: [
          { matcher:"*", hooks: [ {type:"command", command:($h+"/failure-diagnose.sh")} ] } ]
      }
    | .statusLine = {type:"command", command:(($h|rtrimstr("/hooks")) + "/statusline.sh"), padding:0, refreshInterval:3}
  ' "$US" "$SRC/claude/settings.json" > "$tmp"
  jq -e . "$tmp" >/dev/null && cat "$tmp" > "$US"; rm -f "$tmp"
  if [ "$BYPASS" = 1 ]; then
    tmp=$(mktemp)
    jq '.permissions.defaultMode = "bypassPermissions" | .skipDangerousModePermissionPrompt = true' "$US" > "$tmp"
    jq -e . "$tmp" >/dev/null && cat "$tmp" > "$US"; rm -f "$tmp"
    say "merged     ~/.claude/settings.json (+ bypassPermissions)"
  else
    say "merged     ~/.claude/settings.json"
  fi
fi

# --- MCP servers ---------------------------------------------------------------------------
# Merged into the GLOBAL mcpServers map. Ours win on key collision; anything else you have
# configured is preserved. Project-scoped servers stay yours to add (see mcp/README).
CJ="$HOME/.claude.json"
if [ "$HAVE_JQ" = 0 ]; then
  say "skipped    MCP merge (no jq)"
elif [ -f "$CJ" ] && [ "$DRY" = 0 ]; then
  cp "$CJ" "$BK/claude.json"
  tmp=$(mktemp)
  sed "s|__HOME__|$HOME|g" "$SRC/mcp/servers.json" > "$tmp.servers"
  jq -s '.[0] as $cur | .[1] as $new | $cur | .mcpServers = (($cur.mcpServers // {}) * $new)' \
     "$CJ" "$tmp.servers" > "$tmp"
  jq -e . "$tmp" >/dev/null && cat "$tmp" > "$CJ"
  rm -f "$tmp" "$tmp.servers"
  say "merged     MCP servers into ~/.claude.json"
else
  say "skipped    MCP merge (no ~/.claude.json yet — run claude once, then re-run this)"
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
if [ "$DRY" = 0 ] && ! grep -q 'agents/secrets.env' "$HOME/.zshenv" 2>/dev/null; then
  printf '\n[ -f "$HOME/.config/agents/secrets.env" ] && set -a && . "$HOME/.config/agents/secrets.env" && set +a\n' >> "$HOME/.zshenv"
fi
say "installed  shell lane (.zshrc, .zshenv)"

# --- verify ----------------------------------------------------------------------------------
say ""
if [ "$DRY" = 1 ]; then
  say "dry run complete — nothing was changed."
  exit 0
fi
say "backup: $BK"
say ""
if [ -x "$HOME/.config/agents/bin/doctor" ]; then
  "$HOME/.config/agents/bin/doctor" || {
    say ""
    say "doctor reports drift above. Most causes are one-time setup steps it cannot do for you:"
    say "  - fill in ~/.config/agents/secrets.env"
    say "  - exec zsh -l   (to pick up the shell lane)"
    exit 0
  }
fi
say "run: exec zsh -l"
