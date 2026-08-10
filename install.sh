#!/usr/bin/env bash
# install.sh — materialise the user-scope lane (~/.claude, ~/.config/agents) from this repo.
# Idempotent. Backs up anything it overwrites.
#
# Lanes (see README):
#   user-scope   -> this script            : local terminal + Conductor + Remote Control
#   repo overlay -> ./overlay.sh <repo>    : ALSO reaches cloud sessions / phone dispatch
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BK="$HOME/.config/agents/backups/install-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BK" "$HOME/.claude/hooks" "$HOME/.claude/agents" "$HOME/.claude/commands" \
         "$HOME/.config/agents/shell"
chmod 700 "$HOME/.config/agents/backups"

back(){ [ -f "$1" ] && cp "$1" "$BK/$(echo "${1#$HOME/}" | tr / _)"; }

# --- hooks / agents / commands ---
for f in "$SRC"/claude/hooks/*.sh;    do back "$HOME/.claude/hooks/$(basename "$f")";    cp "$f" "$HOME/.claude/hooks/";    done
for f in "$SRC"/claude/agents/*.md;   do cp "$f" "$HOME/.claude/agents/";   done
for f in "$SRC"/claude/commands/*.md; do cp "$f" "$HOME/.claude/commands/"; done
chmod 755 "$HOME"/.claude/hooks/*.sh

# --- settings: merge the portable subset INTO existing user settings, then re-point hook
#     paths to absolute (user scope has no $CLAUDE_PROJECT_DIR). Never clobbers user-only
#     keys such as forceLoginMethod / remote / statusLine / enabledPlugins / permissions.
US="$HOME/.claude/settings.json"; back "$US"
[ -f "$US" ] || echo '{}' > "$US"
NOTIFY='[ -n "$SUPERSET_HOME_DIR" ] && [ -x "$SUPERSET_HOME_DIR/hooks/notify.sh" ] && SUPERSET_AGENT_ID=claude "$SUPERSET_HOME_DIR/hooks/notify.sh" || true'
tmp=$(mktemp)
jq -s --arg h "$HOME/.claude/hooks" --arg n "$NOTIFY" '
  # merge the portable subset (minus hooks — those need absolute paths at user scope)
  ((.[1] | del(.hooks)) as $portable | .[0] * $portable)
  # then rebuild hooks with absolute paths, preserving the Superset notifier on every event
  | .hooks = {
      SessionStart: [
        { hooks: [ {type:"command", command:($h+"/inject-session-context.sh"), statusMessage:"context"} ] },
        { hooks: [ {type:"command", command:$n} ] } ],
      PostToolUse: [
        { matcher:"Edit|Write|MultiEdit",
          hooks: [ {type:"command", command:($h+"/format.sh"), statusMessage:"format"} ] } ],
      Stop: [
        { hooks: [ {type:"command", command:($h+"/verify-gate.sh")} ] },
        { hooks: [ {type:"command", command:$n} ] } ],
      PostToolUseFailure: [
        { matcher:"*", hooks: [ {type:"command", command:($h+"/failure-diagnose.sh")} ] },
        { matcher:"*", hooks: [ {type:"command", command:$n} ] } ],
      SessionEnd:        [ { hooks: [ {type:"command", command:$n} ] } ],
      PermissionRequest: [ { matcher:"*", hooks: [ {type:"command", command:$n} ] } ]
    }
' "$US" "$SRC/claude/settings.json" > "$tmp"
jq -e . "$tmp" >/dev/null && cat "$tmp" > "$US"; rm -f "$tmp"

# --- shell lane ---
cp "$SRC/shell/claude-parity.zsh" "$HOME/.config/agents/shell/"
back "$HOME/.zshrc"
if ! grep -q '>>> claude-parity >>>' "$HOME/.zshrc" 2>/dev/null; then
  printf '\n# >>> claude-parity >>>\n[ -f "$HOME/.config/agents/shell/claude-parity.zsh" ] && . "$HOME/.config/agents/shell/claude-parity.zsh"\n# <<< claude-parity <<<\n' >> "$HOME/.zshrc"
fi
back "$HOME/.zshenv"
if ! grep -q '>>> claude-parity env >>>' "$HOME/.zshenv" 2>/dev/null; then
  cat "$SRC/shell/zshenv.snippet" >> "$HOME/.zshenv"
fi

echo "installed. backup: $BK"
echo "run: exec zsh -l && ~/.config/agents/bin/doctor"
