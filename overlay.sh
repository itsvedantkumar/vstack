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
[ -f "$SRC/claude/settings.json" ] || { echo "error: run from the conductor-setup repo" >&2; exit 1; }

mkdir -p "$DEST/.claude/hooks" "$DEST/.claude/agents" "$DEST/.claude/commands" "$DEST/.claude/skills"

# settings.json: merge, don't clobber — a repo may already have project settings.
if [ -f "$DEST/.claude/settings.json" ] && command -v jq >/dev/null; then
  tmp=$(mktemp)
  jq -s '.[0] * .[1]' "$DEST/.claude/settings.json" "$SRC/claude/settings.json" > "$tmp"
  jq -e . "$tmp" >/dev/null && cat "$tmp" > "$DEST/.claude/settings.json"
  rm -f "$tmp"
  echo "merged  .claude/settings.json"
else
  cp "$SRC/claude/settings.json" "$DEST/.claude/settings.json"
  echo "wrote   .claude/settings.json"
fi

cp "$SRC"/claude/hooks/*.sh    "$DEST/.claude/hooks/"    && chmod 755 "$DEST"/.claude/hooks/*.sh
cp "$SRC"/claude/agents/*.md   "$DEST/.claude/agents/"
cp "$SRC"/claude/commands/*.md "$DEST/.claude/commands/"

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

# .context/ is agent scratch space; keep it out of the repo without touching .gitignore.
ex="$(git -C "$DEST" rev-parse --git-common-dir)/info/exclude"
grep -qxF '.context/' "$ex" 2>/dev/null || { echo '.context/' >> "$ex"; echo "excluded .context/"; }

echo
echo "Verify the cloud lane (simulates a sandbox with no ~/.claude):"
echo "  cd $DEST && claude --setting-sources=project,local -p 'which agents do you have?'"
