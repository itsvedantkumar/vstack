#!/usr/bin/env bash
# overlay.sh — drop the portable Claude Code config into a target repo.
#
# WHY: a cloud session (claude.ai routines, `claude --cloud`, phone dispatch) runs in a
# sandbox that clones the repo and has NO access to your ~/.claude. The committed
# `.claude/` overlay is the ONLY config lane that reaches it. Run this in every repo you
# dispatch work to from your phone.
#
# Usage: ./overlay.sh [--check] [target-repo-dir]      (default: $PWD)
#   --check: report drift against a repo already overlaid, write nothing, exit 1 if stale
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --check may come before or after the dest arg (`overlay.sh --check repo` and the vstack
# dispatcher's `overlay <repo> --check` both need to work), so it is pulled out of the
# positional list rather than assumed to be $1. Every other positional arg — today there is
# only ever one — passes through untouched, which is what keeps a plain `./overlay.sh <repo>`
# byte-identical to before this flag existed.
CHECK=0
ARGS=()
for a in "$@"; do
  case "$a" in
    --check) CHECK=1 ;;
    *) ARGS+=("$a") ;;
  esac
done
DEST="${ARGS[0]:-$PWD}"

# -e, not -d: inside a git worktree .git is a file pointing at the real git dir. The -d test
# rejected every Conductor workspace, which is precisely where this needs to run — Conductor
# lays them out as workspaces/<project>/<workspace>, and each one is a worktree.
[ -e "$DEST/.git" ] || { echo "error: $DEST is not a git repo or worktree" >&2; exit 1; }
[ -f "$SRC/claude/settings.json" ] || { echo "error: run from the vstack repo" >&2; exit 1; }

# --check stops here, before anything below that writes. It walks the exact same file lists
# overlay would copy — unconditional copies, seed_tmpl targets, the conductor pin — but only
# ever reads, so a repo can be checked in CI or a cron without risking the write path neither
# of those callers reviewed.
if [ "$CHECK" -eq 1 ]; then
  STALE=0
  OWNED=0
  MISSING=0

  # <label> <src file> <dest file> — the "always overwritten" half of overlay: hooks, agents,
  # commands, skills' loose files, policy.md, statusline.sh, security-scan.sh. A repo where
  # these differ from $SRC has been overlaid at an older commit and silently kept running it;
  # cmp -s is the same byte comparison seed_tmpl already uses below to decide "kept" vs "wrote".
  check_unconditional() {
    local label="$1" s="$2" d="$3"
    if [ ! -f "$d" ]; then
      echo "missing  $label (not present — overlay would write it)"
      MISSING=$((MISSING + 1))
    elif ! cmp -s "$s" "$d"; then
      echo "stale    $label (differs from $s — overlay would refresh it)"
      STALE=$((STALE + 1))
    fi
  }

  for f in "$SRC"/claude/hooks/*.sh; do
    [ -e "$f" ] || continue
    b=$(basename "$f")
    check_unconditional ".claude/hooks/$b" "$f" "$DEST/.claude/hooks/$b"
  done
  for f in "$SRC"/claude/agents/*.md; do
    [ -e "$f" ] || continue
    b=$(basename "$f")
    check_unconditional ".claude/agents/$b" "$f" "$DEST/.claude/agents/$b"
  done
  for f in "$SRC"/claude/agents/reference/*.ref; do
    [ -e "$f" ] || continue
    b=$(basename "$f")
    check_unconditional ".claude/agents/reference/$b" "$f" "$DEST/.claude/agents/reference/$b"
  done
  for f in "$SRC"/claude/commands/*.md; do
    [ -e "$f" ] || continue
    b=$(basename "$f")
    check_unconditional ".claude/commands/$b" "$f" "$DEST/.claude/commands/$b"
  done
  check_unconditional ".claude/hooks/policy.md" "$SRC/claude/CLAUDE.md" "$DEST/.claude/hooks/policy.md"
  check_unconditional ".claude/statusline.sh" "$SRC/claude/statusline.sh" "$DEST/.claude/statusline.sh"
  check_unconditional ".claude/security-scan.sh" "$SRC/claude/security-scan.sh" "$DEST/.claude/security-scan.sh"
  check_unconditional ".claude/whitebox-audit.sh" "$SRC/claude/whitebox-audit.sh" "$DEST/.claude/whitebox-audit.sh"

  # Skills carry references/ and scripts/ subtrees and overlay replaces each whole (rm -rf then
  # cp -R), so a single-file cmp is not enough — diff -rq walks the tree the same way the write
  # path does.
  for d in "$SRC"/claude/skills/*/; do
    [ -d "$d" ] || continue
    s=$(basename "$d")
    if [ ! -d "$DEST/.claude/skills/$s" ]; then
      echo "missing  .claude/skills/$s (not present — overlay would write it)"
      MISSING=$((MISSING + 1))
    elif ! diff -rq "${d%/}" "$DEST/.claude/skills/$s" >/dev/null 2>&1; then
      echo "stale    .claude/skills/$s (differs from $SRC/claude/skills/$s — overlay would refresh it)"
      STALE=$((STALE + 1))
    fi
  done

  # <label> <src tmpl> <dest file> — seed_tmpl's targets. These are seeded once and never
  # overwritten, so a difference here is not staleness, it is the repo's own edit: report it as
  # repo-owned and leave it out of the exit-code gate.
  check_seeded() {
    local label="$1" s="$2" d="$3"
    if [ ! -f "$d" ]; then
      echo "absent   $label (never seeded — overlay would write it)"
      MISSING=$((MISSING + 1))
    elif ! cmp -s "$s" "$d"; then
      echo "differs (repo-owned) $label — diff it against $s if you want"
      OWNED=$((OWNED + 1))
    fi
  }
  check_seeded ".github/workflows/security.yml" "$SRC/claude/security.yml.tmpl" "$DEST/.github/workflows/security.yml"
  check_seeded ".github/dependabot.yml" "$SRC/claude/dependabot.yml.tmpl" "$DEST/.github/dependabot.yml"
  # Same seed-once contract as the two above, easy to miss because their write-path calls
  # (~:260 for CLAUDE.md, ~:266-278 for verify.sh) aren't seed_tmpl itself — CLAUDE.md.tmpl is
  # a plain `[ -f ] || cp`, and verify.sh's write branch adds a chmod and a "kept + hint" path
  # instead of seed_tmpl's "kept (differs from template)" — but the seeded-once semantics are
  # identical: never overwritten, so absent here is real missing-file drift, not a repo-owned
  # diff, since content drift from either template is expected and deliberate.
  check_seeded "CLAUDE.md" "$SRC/CLAUDE.md.tmpl" "$DEST/CLAUDE.md"
  check_seeded ".claude/verify.sh" "$SRC/claude/verify.sh.tmpl" "$DEST/.claude/verify.sh"

  # Legacy migration: overlay's write path (~:230-232) deletes a tracked .claude/CLAUDE.md the
  # moment it finds one, because its existence IS the duplication policy.md was written to
  # replace. --check has no write path, so it reports instead of removing — a repo still
  # carrying this file has not run overlay since the migration and is drifted exactly like a
  # stale copy, so it counts toward the same exit-code gate.
  if [ -f "$DEST/.claude/CLAUDE.md" ]; then
    echo "legacy   .claude/CLAUDE.md (overlay would remove it)"
    STALE=$((STALE + 1))
  fi

  # Conductor pin: same substring overlay itself rewrites, read instead of written. Compared
  # against $SRC's own current HEAD, not a fetched origin/main — that is the commit overlay
  # would pin to if run right now, on whatever branch $SRC happens to be checked out to, which
  # is exactly what "stale" needs to mean here.
  if [ -f "$DEST/.conductor/settings.toml" ]; then
    curpin=$(grep -oE '/vstack/[0-9a-f]{40}/bootstrap\.sh' "$DEST/.conductor/settings.toml" 2>/dev/null | head -1 || true)
    curpin=${curpin#/vstack/}; curpin=${curpin%/bootstrap.sh}
    if [ -n "$curpin" ]; then
      mainsha=$(git -C "$SRC" rev-parse HEAD)
      echo "pin $curpin vs main $mainsha"
      [ "$curpin" = "$mainsha" ] || STALE=$((STALE + 1))
    fi
  else
    echo "missing  .conductor/settings.toml (not present — overlay would write it)"
    MISSING=$((MISSING + 1))
  fi

  echo "overlay --check: $STALE stale, $OWNED repo-owned diffs, $MISSING missing"
  if [ "$STALE" -eq 0 ] && [ "$MISSING" -eq 0 ]; then
    exit 0
  else
    exit 1
  fi
fi

mkdir -p "$DEST/.claude/hooks" "$DEST/.claude/agents" "$DEST/.claude/agents/reference" "$DEST/.claude/commands" "$DEST/.claude/skills"

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
  #
  # hooks and skillOverrides are merged by OWNERSHIP, not by vocabulary. `$dest * $ship` (jq deep
  # merge) replaces the whole array for any event key both sides populate, and
  # `.skillOverrides = $ship.skillOverrides` is an unconditional overwrite — either one destroys
  # a target repo's own hook on SessionStart/PreToolUse/etc. or its own skillOverrides entries
  # the moment vstack also touches that key. install.sh/uninstall.sh already solved this: decide
  # ownership by what a hook COMMAND points at (a path ending in .../hooks/<file vstack ships>),
  # not by whether the event NAME collides.
  #
  # Basenames are derived from $ours here, which is $ship.hooks itself — overlay ships hooks
  # verbatim from claude/settings.json (project scope, `"$CLAUDE_PROJECT_DIR/.claude/hooks/x.sh"`,
  # quoted), unlike install.sh's inline-built absolute unquoted user-scope paths. That trailing
  # `"` matters: split("/")|last on a quoted command yields `x.sh"` with the quote still attached,
  # so both the basename and the command under test are trimmed of a trailing `"` before
  # comparing, or nothing ever matches and every ownership branch is silently dead code — the
  # same mistake that left uninstall.sh's ownership checks inert for three releases.
  tmp=$(mktemp)
  jq -s --arg allow "$ALLOW" '
    ($allow | split(" ") | map(select(length > 0))) as $A
    | . as [$dest, $src]
    | ($src | with_entries(select(.key as $k | $A | index($k)))) as $ship
    | ($ship.hooks // {}) as $ours
    | ([$ours | .. | .command? // empty] | map(rtrimstr("\"") | split("/") | last) | unique) as $ourbasenames
    | (($dest.hooks // {})
        | with_entries(.value |= map(select(
            [.hooks[]?.command // empty]
            | map(. as $cmd | ($ourbasenames | any(. as $b | ($cmd | rtrimstr("\"")) | endswith("/hooks/" + $b))))
            | any | not )))
        | with_entries(select(.value | length > 0))) as $theirs
    | ($dest * $ship)
    | .hooks = (reduce ($ours | to_entries[]) as $e
                 ($theirs; .[$e.key] = (($theirs[$e.key] // []) + $e.value)))
    | .skillOverrides = (($dest.skillOverrides // {}) + ($ship.skillOverrides // {}))
  ' "$DEST/.claude/settings.json" "$SRC/claude/settings.json" > "$tmp"
  jq -e . "$tmp" >/dev/null && cat "$tmp" > "$DEST/.claude/settings.json"
  rm -f "$tmp"
  echo "merged  .claude/settings.json ($(printf '%s' "$ALLOW" | wc -w | tr -d ' ') project keys)"
else
  # No jq means no way to take a subset, and copying the whole file is what this change
  # exists to stop. Refuse rather than ship someone's preferences into their repo.
  echo "error: jq is required to build the project settings subset" >&2
  exit 1
fi

cp "$SRC"/claude/hooks/*.sh    "$DEST/.claude/hooks/"    && chmod 755 "$DEST"/.claude/hooks/*.sh
cp "$SRC"/claude/agents/*.md   "$DEST/.claude/agents/"
# *.ref, not *.md -- see install.sh: the agent walker recurses and loads every .md it finds.
cp "$SRC"/claude/agents/reference/*.ref "$DEST/.claude/agents/reference/" 2>/dev/null || true
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
# Overwritten every time, unlike the two CI templates below: this is vstack's own script, called
# by vstack's own verify.sh template, and a stale copy of it in a target repo is a scanner lane
# that silently runs last release's rules. Nothing in a target repo is expected to edit it --
# that is what .gitleaks.toml and the workflow file are for.
cp "$SRC/claude/security-scan.sh" "$DEST/.claude/security-scan.sh" && chmod 755 "$DEST/.claude/security-scan.sh"
echo "wrote   .claude/security-scan.sh"
# The deep lane, same reasoning. It is NOT wired into verify.sh: it takes minutes, and a gate that
# takes minutes is a gate people disable. The whitebox-pentest skill drives it on demand.
cp "$SRC/claude/whitebox-audit.sh" "$DEST/.claude/whitebox-audit.sh" && chmod 755 "$DEST/.claude/whitebox-audit.sh"
echo "wrote   .claude/whitebox-audit.sh"
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
  # A repo that already has a real gate keeps it -- and then has .claude/security-scan.sh sitting
  # next to a gate that never calls it, which is indistinguishable from not shipping the scanner
  # at all. Overwriting someone's gate to wire it in costs more than it buys, so say the one line
  # they need and let them place it. Only the template (claude/verify.sh.tmpl) calls it already.
  if ! grep -q security-scan.sh "$DEST/.claude/verify.sh"; then
    echo "hint    .claude/verify.sh does not call .claude/security-scan.sh — add: bash .claude/security-scan.sh || FAIL=1"
  fi
else
  cp "$SRC/claude/verify.sh.tmpl" "$DEST/.claude/verify.sh"
  chmod 755 "$DEST/.claude/verify.sh"
  echo "wrote   .claude/verify.sh (template — write real checks, then 'vstack trust')"
fi

# The CI half of the same lane. The local scan above catches a secret before it is committed; only
# a workflow catches one pushed from a machine that never ran the overlay, and only dependabot
# tracks the vulnerability that lands in a dependency next week.
#
# Seeded once and never overwritten: a repo's own security workflow and update policy outrank a
# template. "kept" alone could not tell a deliberate local edit from a copy that had drifted
# behind the template nobody re-read, so it says which -- and names the file to diff against,
# because a report that a file differs without saying from what is not actionable.
seed_tmpl(){ # <src path relative to vstack> <dest path relative to the target repo>
  _st_src="$SRC/$1"; _st_dst="$DEST/$2"
  [ -f "$_st_src" ] || { echo "error: missing $_st_src" >&2; return 1; }
  mkdir -p "$(dirname "$_st_dst")"
  if [ -f "$_st_dst" ]; then
    if cmp -s "$_st_src" "$_st_dst"; then
      echo "kept    $2 (matches template)"
    else
      echo "kept    $2 (differs from template — diff it against $_st_src)"
    fi
  else
    cp "$_st_src" "$_st_dst"
    echo "wrote   $2 (template — tune it for this repo)"
  fi
}
seed_tmpl claude/security.yml.tmpl .github/workflows/security.yml
seed_tmpl claude/dependabot.yml.tmpl .github/dependabot.yml

# Conductor: give the repo a verify button and, for cloud workspaces, a way to pull vstack
# into the sandbox. Never overwrite an existing file — a repo's own setup script matters more
# than this one, so print the lines to merge by hand instead.
mkdir -p "$DEST/.conductor"
# The pin was a hardcoded SHA that nobody bumped, so it drifted behind main and every new
# sandbox bootstrapped an old vstack. Resolving HEAD keeps the security property — a sandbox
# runs a specific reviewed commit, not whatever main happens to be — while pinning to the
# commit actually being overlaid.
PIN=$(git -C "$SRC" rev-parse HEAD)
if ! git -C "$SRC" branch -r --contains "$PIN" 2>/dev/null | grep -q .; then
  echo "warning: $PIN is not on any remote branch yet — the sandbox setup will 404 until you push" >&2
fi
if [ -f "$DEST/.conductor/settings.toml" ]; then
  # "Written only when absent" made every existing pin permanent: five real repos carried four
  # different vstack SHAs, all behind HEAD. Rewrite exactly the /vstack/<sha>/bootstrap.sh
  # substring and nothing else. A file with no such substring has an operator-owned setup line;
  # leave it byte-identical and say what is missing instead.
  curpin=$(grep -oE '/vstack/[0-9a-f]{40}/bootstrap\.sh' "$DEST/.conductor/settings.toml" 2>/dev/null | head -1)
  curpin=${curpin#/vstack/}; curpin=${curpin%/bootstrap.sh}
  if [ -n "$curpin" ] && [ "$curpin" != "$PIN" ]; then
    tomltmp=$(mktemp)
    sed "s|/vstack/$curpin/bootstrap\.sh|/vstack/$PIN/bootstrap.sh|g" \
      "$DEST/.conductor/settings.toml" > "$tomltmp" && cat "$tomltmp" > "$DEST/.conductor/settings.toml"
    rm -f "$tomltmp"
    echo "bumped  .conductor/settings.toml pin $curpin -> $PIN (commit it)"
  else
    echo "kept    .conductor/settings.toml (already exists)"
  fi
  grep -q 'trust --yes' "$DEST/.conductor/settings.toml" 2>/dev/null \
    || echo "        note: setup line has no \"vstack trust --yes\" — the Stop-hook gate stays unarmed in cloud sandboxes"
  grep -q '\[scripts.run.verify\]' "$DEST/.conductor/settings.toml" 2>/dev/null || {
    echo "        to run the verify gate from Conductor, add:"
    echo "          [scripts.run.verify]"
    echo "          command = \"./.claude/verify.sh\""
  }
else
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
