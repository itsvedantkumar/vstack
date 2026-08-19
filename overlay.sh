#!/usr/bin/env bash
# overlay.sh — drop the portable Claude Code config into a target repo.
#
# WHY: a cloud session (claude.ai routines, `claude --cloud`, phone dispatch) runs in a
# sandbox that clones the repo and has NO access to your ~/.claude. The committed
# `.claude/` overlay is the ONLY config lane that reaches it. Run this in every repo you
# dispatch work to from your phone.
#
# Usage: ./overlay.sh [target-repo-dir]      (default: $PWD)
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${1:-$PWD}"

[ -d "$DEST/.git" ] || { echo "error: $DEST is not a git repo" >&2; exit 1; }
[ -f "$SRC/claude/settings.json" ] || { echo "error: run from the vstack repo" >&2; exit 1; }

mkdir -p "$DEST/.claude/hooks" "$DEST/.claude/agents" "$DEST/.claude/commands" "$DEST/.claude/skills"

# settings.json: merge, don't clobber — a repo may already have project settings.
# skillOverrides is replaced wholesale (same reason as install.sh: dead overrides for
# removed skills must not linger), and hook events both sides define are won by vstack —
# say so instead of doing it silently.
if [ -f "$DEST/.claude/settings.json" ] && command -v jq >/dev/null; then
  clobbered=$(jq -rs '((.[0].hooks // {} | keys) - ((.[0].hooks // {} | keys) - (.[1].hooks // {} | keys))) | join(", ")' \
    "$DEST/.claude/settings.json" "$SRC/claude/settings.json")
  tmp=$(mktemp)
  jq -s '. as [$dest, $src] | ($dest * $src) | .skillOverrides = ($src.skillOverrides // {})' \
    "$DEST/.claude/settings.json" "$SRC/claude/settings.json" > "$tmp"
  jq -e . "$tmp" >/dev/null && cat "$tmp" > "$DEST/.claude/settings.json"
  rm -f "$tmp"
  echo "merged  .claude/settings.json"
  [ -n "$clobbered" ] && echo "        note: vstack's hook config replaced this repo's for: $clobbered"
else
  cp "$SRC/claude/settings.json" "$DEST/.claude/settings.json"
  echo "wrote   .claude/settings.json"
fi

cp "$SRC"/claude/hooks/*.sh    "$DEST/.claude/hooks/"    && chmod 755 "$DEST"/.claude/hooks/*.sh
cp "$SRC"/claude/agents/*.md   "$DEST/.claude/agents/"
cp "$SRC"/claude/commands/*.md "$DEST/.claude/commands/"

# Global directives + statusline: a cloud sandbox has no ~/.claude, so the project copy is
# the only lane these reach it by. .claude/CLAUDE.md is a recognized project-memory path.
cp "$SRC/claude/CLAUDE.md" "$DEST/.claude/CLAUDE.md"
cp "$SRC/claude/statusline.sh" "$DEST/.claude/statusline.sh" && chmod 755 "$DEST/.claude/statusline.sh"
echo "wrote   .claude/CLAUDE.md + .claude/statusline.sh"
if command -v jq >/dev/null; then
  tmp=$(mktemp)
  jq '.statusLine = {type:"command", command:"\"$CLAUDE_PROJECT_DIR/.claude/statusline.sh\"", padding:0, refreshInterval:3}' \
    "$DEST/.claude/settings.json" > "$tmp" && jq -e . "$tmp" >/dev/null && cat "$tmp" > "$DEST/.claude/settings.json"
  rm -f "$tmp"
fi

# skills carry references/ and scripts/ subtrees — replace each whole, don't merge.
for d in "$SRC"/claude/skills/*/; do
  s=$(basename "$d")
  rm -rf "$DEST/.claude/skills/$s"
  # strip trailing slash — BSD `cp -R src/ dest/` copies contents, not the dir itself
  cp -R "${d%/}" "$DEST/.claude/skills/"
done
find "$DEST/.claude/skills" -name "*.sh" -exec chmod 755 {} + 2>/dev/null || true
echo "wrote   .claude/{hooks,agents,commands,skills}"

[ -f "$DEST/CLAUDE.md" ] || { cp "$SRC/CLAUDE.md.tmpl" "$DEST/CLAUDE.md"; echo "wrote   CLAUDE.md (template — edit it)"; }

# Conductor: give the repo a verify button and, for cloud workspaces, a way to pull vstack
# into the sandbox. Never overwrite an existing file — a repo's own setup script matters more
# than this one, so print the lines to merge by hand instead.
mkdir -p "$DEST/.conductor"
if [ -f "$DEST/.conductor/settings.toml" ]; then
  echo "kept    .conductor/settings.toml (already exists)"
  echo "        to run the verify gate from Conductor, add:"
  echo "          [scripts.run.verify]"
  echo "          command = \"./.claude/verify.sh\""
else
  cat > "$DEST/.conductor/settings.toml" <<'TOML'
"$schema" = "https://conductor.build/schemas/settings.repo.schema.json"

[scripts]
# Cloud workspaces start from a bare Linux sandbox with no ~/.claude, so pull vstack in.
# Pinned to a reviewed commit so a compromised repo/account cannot push code into every
# sandbox at once — bump the SHA deliberately when updating vstack.
# Add this repo's own install step (npm ci, uv sync, ...) to the end of this line.
setup = "curl -fsSL https://raw.githubusercontent.com/itsvedantkumar/vstack/ecb6992e848599bc1b6eaa648ab4c6cfa85ae8f0/bootstrap.sh | bash"
run_mode = "concurrent"

[scripts.run.verify]
command = "./.claude/verify.sh"
icon = "shield-check"

# Live preview for the ui-iterate / design-review loop. Each local workspace gets ten ports
# starting at $CONDUCTOR_PORT. Adjust the command to the repo's dev runner (vite needs
# `npm run dev -- --port $CONDUCTOR_PORT`); delete this block for repos with no frontend.
[scripts.run.dev]
available_in = [ "local" ]
command = "PORT=$CONDUCTOR_PORT npm run dev"
default = true
icon = "play"
TOML
  echo "wrote   .conductor/settings.toml"
fi

# .context/ is agent scratch space; keep it out of the repo without touching .gitignore.
# --git-common-dir can answer with a path relative to DEST — anchor it, or the exclude
# lands in whatever repo the CALLER happens to be standing in.
common=$(git -C "$DEST" rev-parse --git-common-dir)
case "$common" in /*) ;; *) common="$DEST/$common" ;; esac
ex="$common/info/exclude"
mkdir -p "${ex%/*}"
grep -qxF '.context/' "$ex" 2>/dev/null || { echo '.context/' >> "$ex"; echo "excluded .context/"; }

echo
echo "Verify the cloud lane (simulates a sandbox with no ~/.claude):"
echo "  cd $DEST && claude --setting-sources=project,local -p 'which agents do you have?'"
