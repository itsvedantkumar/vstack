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

# -e, not -d: inside a git worktree .git is a file pointing at the real git dir. The -d test
# rejected every Conductor workspace, which is precisely where this needs to run — Conductor
# lays them out as workspaces/<project>/<workspace>, and each one is a worktree.
[ -e "$DEST/.git" ] || { echo "error: $DEST is not a git repo or worktree" >&2; exit 1; }
[ -f "$SRC/claude/settings.json" ] || { echo "error: run from the vstack repo" >&2; exit 1; }

mkdir -p "$DEST/.claude/hooks" "$DEST/.claude/agents" "$DEST/.claude/commands" "$DEST/.claude/skills"

# settings.json: ship the project-safe subset, merge it, don't clobber the repo's own keys.
#
# This used to copy the entire file, which put theme, tui, notification channels,
# forceLoginMethod and the plugin list into every repo it touched, and into the git history of
# anyone who cloned them. claude/settings.project-keys is the allowlist and says why each key
# earns its place.
#
# Keys vstack ships but no longer allows are deleted from the target, so a repo overlaid under
# the old behaviour gets cleaned instead of merely not accumulating more. Only keys this repo
# actually ships are eligible for deletion — a target's own unrelated settings are left alone.
KEYFILE="$SRC/claude/settings.project-keys"
[ -f "$KEYFILE" ] || { echo "error: missing $KEYFILE" >&2; exit 1; }
ALLOW=$(grep -vE '^[[:space:]]*#|^[[:space:]]*$' "$KEYFILE" | tr '\n' ' ')

if command -v jq >/dev/null; then
  [ -f "$DEST/.claude/settings.json" ] || echo '{}' > "$DEST/.claude/settings.json"
  # This used to delete every key vstack ships that is NOT on the project allowlist, on the
  # theory that it was cleaning up its own past overlays. It has no way to know that. Run against
  # a repository that independently set enabledPlugins, theme or forceLoginMethod — names vstack
  # happens to use at user scope — it deleted all three, because the deletion was keyed on
  # vstack's vocabulary rather than on provenance.
  #
  # It writes the allowlisted keys and leaves everything else alone now. Cleaning up an old
  # overlay has to be an explicit, separate act: provenance is not recoverable from the file, and
  # guessing at it costs someone their settings.
  clobbered=$(jq -rs '((.[0].hooks // {} | keys) - ((.[0].hooks // {} | keys) - (.[1].hooks // {} | keys))) | join(", ")' \
    "$DEST/.claude/settings.json" "$SRC/claude/settings.json")
  tmp=$(mktemp)
  jq -s --arg allow "$ALLOW" '
    ($allow | split(" ") | map(select(length > 0))) as $A
    | . as [$dest, $src]
    | ($src | with_entries(select(.key as $k | $A | index($k)))) as $ship
    | ($dest * $ship)
    | .skillOverrides = ($ship.skillOverrides // {})
  ' "$DEST/.claude/settings.json" "$SRC/claude/settings.json" > "$tmp"
  jq -e . "$tmp" >/dev/null && cat "$tmp" > "$DEST/.claude/settings.json"
  rm -f "$tmp"
  echo "merged  .claude/settings.json ($(printf '%s' "$ALLOW" | wc -w | tr -d ' ') project keys)"
  [ -n "$clobbered" ] && echo "        note: vstack's hook config replaced this repo's for: $clobbered"
else
  # No jq means no way to take a subset, and copying the whole file is what this change
  # exists to stop. Refuse rather than ship someone's preferences into their repo.
  echo "error: jq is required to build the project settings subset" >&2
  exit 1
fi

cp "$SRC"/claude/hooks/*.sh    "$DEST/.claude/hooks/"    && chmod 755 "$DEST"/.claude/hooks/*.sh
cp "$SRC"/claude/agents/*.md   "$DEST/.claude/agents/"
cp "$SRC"/claude/commands/*.md "$DEST/.claude/commands/"

# The policy document. It is NOT written as .claude/CLAUDE.md any more: that is a project-memory
# path, ~/.claude/CLAUDE.md holds the same bytes, and Claude Code loads both — the whole document
# twice, in every repo this had ever touched. No hook can dedupe that, because the client reads
# both files itself.
#
# It ships as .claude/hooks/policy.md instead, which nothing loads automatically, and the session
# hook reads it and speaks it only where it is the only voice: a sandbox, which has no ~/.claude.
# See the tail of claude/hooks/inject-session-context.sh.
cp "$SRC/claude/CLAUDE.md" "$DEST/.claude/hooks/policy.md"
# Converge, do not merely stop writing. Every repo overlaid before this change carries a
# .claude/CLAUDE.md that IS the duplication, and leaving it in place fixes nothing. Where it is
# tracked the removal shows up in git status for its owner to commit — which is the point, since
# an uncommitted deletion never reaches the sandbox that was reading it.
if [ -f "$DEST/.claude/CLAUDE.md" ]; then
  rm -f "$DEST/.claude/CLAUDE.md"
  echo "removed .claude/CLAUDE.md (superseded by .claude/hooks/policy.md — commit the deletion)"
fi
echo "wrote   .claude/hooks/policy.md"
cp "$SRC/claude/statusline.sh" "$DEST/.claude/statusline.sh" && chmod 755 "$DEST/.claude/statusline.sh"
echo "wrote   .claude/statusline.sh"
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

# The Stop hook and Conductor's verify button both point at .claude/verify.sh, and the overlay
# never shipped one. The hook no-ops safely on a missing file, but the button fails outright.
# Seed a template that runs whatever the repo already knows how to check. Never overwrite: a
# repo's real gate matters far more than this placeholder.
if [ -f "$DEST/.claude/verify.sh" ]; then
  echo "kept    .claude/verify.sh (already exists)"
else
  cp "$SRC/claude/verify.sh.tmpl" "$DEST/.claude/verify.sh"
  chmod 755 "$DEST/.claude/verify.sh"
  echo "wrote   .claude/verify.sh (template — write real checks, then 'vstack trust')"
fi

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
  # The pin was a hardcoded SHA that nobody bumped, so it drifted behind main and every new
  # sandbox bootstrapped an old vstack. Resolving HEAD keeps the security property — a sandbox
  # runs a specific reviewed commit, not whatever main happens to be — while pinning to the
  # commit actually being overlaid.
  PIN=$(git -C "$SRC" rev-parse HEAD)
  if ! git -C "$SRC" branch -r --contains "$PIN" 2>/dev/null | grep -q .; then
    echo "warning: $PIN is not on any remote branch yet — the sandbox setup will 404 until you push" >&2
  fi
  sed "s/__PIN__/$PIN/" > "$DEST/.conductor/settings.toml" <<'TOML'
"$schema" = "https://conductor.build/schemas/settings.repo.schema.json"

[scripts]
# Cloud workspaces start from a bare Linux sandbox with no ~/.claude, so pull vstack in.
# Pinned to a reviewed commit so a compromised repo/account cannot push code into every
# sandbox at once — bump the SHA deliberately when updating vstack.
#
# `vstack trust` arms this repo's .claude/verify.sh for the Stop-hook gate. Without it the
# gate installs and does nothing: verify-gate.sh refuses to execute a repo's verify.sh unless
# a machine-local trust entry matches its hash, and a fresh sandbox has no such entry. The
# gate was inert in the one lane that exists for cloud work — installed, wired, and silently
# skipping on every Stop.
#
# Arming it here rather than in verify-gate.sh keeps the local protection intact. Cloning an
# untrusted repo onto your laptop still runs nothing until you type `vstack trust` yourself.
# This line is different: it lives in a file you committed, in a disposable sandbox, for a
# repo you deliberately dispatched work to. That is the consent, and it is visible in the diff.
#
# --yes: `vstack trust` (5922ccf) added a TTY confirmation prompt, refusing to run unattended
# without it. This line always runs unattended -- there is no terminal in a sandbox bootstrap --
# so since 5922ccf it exited 1 ("no terminal to confirm on") on every cloud sandbox and never
# wrote the trust hash, leaving the Stop-hook gate permanently unarmed. The consent this comment
# already describes (a human committed this line, in a repo they chose to dispatch) is exactly
# what --yes is for; the prompt guards the case where nobody reviewed it, which does not apply
# to a line that shipped in a diff someone read.
#
# Add this repo's own install step (npm ci, uv sync, ...) to the end of this line.
setup = "curl -fsSL https://raw.githubusercontent.com/itsvedantkumar/vstack/__PIN__/bootstrap.sh | bash && \"$HOME/.config/agents/bin/vstack\" trust --yes"
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

# Runs before a workspace is archived or merged. Uncomment for repos whose workspaces start
# external resources (docker stacks, tunnels, background daemons) that need killing.
# [scripts.archive]
# command = "docker compose down --volumes"

# Per-repo env for every workspace session; [environment_variables.local] and .cloud split by
# surface. Cloud sandboxes also receive CONDUCTOR_API_TOKEN/CONDUCTOR_API_URL automatically.
# [environment_variables]
# EXAMPLE_FLAG = "1"

# Gitignored files a new local workspace needs (.env, certs) belong in a .worktreeinclude at
# the repo root — Conductor copies matches into every new worktree it creates.
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
