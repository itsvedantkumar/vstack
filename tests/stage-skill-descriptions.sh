#!/usr/bin/env bash
# tests/stage-skill-descriptions.sh
#
# Copies the repo's SKILL.md description line for named skills into ~/.claude/skills, and puts
# it back afterwards.
#
# WHY THIS HAS TO EXIST
#
# tests/auto-trigger.sh runs the CLI in a scratch workdir, so the descriptions that reach the
# matcher are the INSTALLED ones under ~/.claude/skills. Measured 2026-09-01: a project-local
# .claude/skills/<name>/SKILL.md is loaded and listed, but a user-level skill of the same name
# WINS -- asked to quote its own listing for `swarm`, the model returned the installed text and
# reported no duplicate. So a description edited in a checkout is invisible to the harness, and
# an after-arm measured without installing would measure the before-arm's bytes and call it a
# result.
#
# Running install.sh instead is not an option here: it installs the whole tree, including
# whatever hook edits another session has in flight.
#
# WHY THE RESTORE REFUSES
#
# A save/restore harness in this repo once deleted two agents' uncommitted work by restoring
# over a change it did not make. --restore therefore refuses any file whose content differs from
# what --stage wrote, and says so, rather than overwriting a foreign edit. The snapshot records
# a checksum per file, not just the bytes.
#
# --stage likewise refuses to start if the installed copy differs from the repo copy at HEAD,
# because that means someone else is mid-edit and staging would silently take their change with
# it into a measurement.
#
# Usage:
#   tests/stage-skill-descriptions.sh --stage   swarm writing-plans
#   tests/stage-skill-descriptions.sh --status
#   tests/stage-skill-descriptions.sh --restore
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILLS_SRC="$REPO_ROOT/claude/skills"
SKILLS_DST="$HOME/.claude/skills"
STATE_DIR="${TMPDIR:-/tmp}/vstack-skill-stage"

if command -v shasum >/dev/null 2>&1; then SUM=shasum
elif command -v sha256sum >/dev/null 2>&1; then SUM=sha256sum
else echo "need shasum or sha256sum" >&2; exit 2; fi

sumof() { "$SUM" < "$1" | awk '{print $1}'; }

desc_of() {
  awk 'NR==1 { if ($0 != "---") exit; infm=1; next }
       infm && $0 == "---" { exit }
       infm && /^description:[[:space:]]/ { print; exit }' "$1"
}

do_stage() {
  local name src dst staged=0
  [ "$#" -gt 0 ] || { echo "--stage needs at least one skill name" >&2; exit 2; }
  mkdir -p "$STATE_DIR"
  if [ -e "$STATE_DIR/manifest" ]; then
    echo "REFUSING: $STATE_DIR/manifest already exists -- a previous stage was never restored." >&2
    echo "          Run --restore (or --status) first." >&2
    exit 2
  fi

  # Pre-flight every skill before touching any of them: a half-applied stage is worse than none.
  for name in "$@"; do
    src="$SKILLS_SRC/$name/SKILL.md"; dst="$SKILLS_DST/$name/SKILL.md"
    [ -f "$src" ] || { echo "REFUSING: no repo skill at $src" >&2; exit 2; }
    [ -f "$dst" ] || { echo "REFUSING: no installed skill at $dst" >&2; exit 2; }
    if ! git -C "$REPO_ROOT" show "HEAD:claude/skills/$name/SKILL.md" 2>/dev/null \
         | diff -q - "$dst" >/dev/null 2>&1; then
      echo "REFUSING: installed $name differs from repo HEAD. Someone else is mid-edit, or an" >&2
      echo "          earlier stage leaked. Staging would carry their change into the arm." >&2
      exit 2
    fi
  done

  : > "$STATE_DIR/manifest"
  for name in "$@"; do
    src="$SKILLS_SRC/$name/SKILL.md"; dst="$SKILLS_DST/$name/SKILL.md"
    cp "$dst" "$STATE_DIR/$name.orig"
    cp "$src" "$dst"
    printf '%s\t%s\t%s\n' "$name" "$dst" "$(sumof "$dst")" >> "$STATE_DIR/manifest"
    staged=$((staged + 1))
    printf 'staged %-28s %s\n' "$name" "$(desc_of "$dst" | cut -c1-72)..."
  done
  echo "staged $staged skill(s). Installed digest is now: $(installed_digest)"
  echo "Run --restore when the arm is finished."
}

installed_digest() {
  grep -h '^description:' "$SKILLS_DST"/*/SKILL.md 2>/dev/null | "$SUM" | cut -c1-12
}

do_restore() {
  local name dst want have rc=0 n=0
  [ -f "$STATE_DIR/manifest" ] || { echo "nothing staged (no $STATE_DIR/manifest)"; exit 0; }
  while IFS=$'\t' read -r name dst want; do
    [ -n "$name" ] || continue
    have="$(sumof "$dst")"
    if [ "$have" != "$want" ]; then
      echo "REFUSING $name: $dst changed since it was staged." >&2
      echo "          staged=$want now=$have -- restoring would destroy a foreign edit." >&2
      echo "          Original is preserved at $STATE_DIR/$name.orig" >&2
      rc=1
      continue
    fi
    cp "$STATE_DIR/$name.orig" "$dst"
    n=$((n + 1))
    printf 'restored %-28s\n' "$name"
  done < "$STATE_DIR/manifest"
  if [ "$rc" -eq 0 ]; then
    rm -rf "$STATE_DIR"
    echo "restored $n skill(s), state cleared. Installed digest: $(installed_digest)"
  else
    echo "restored $n skill(s); state KEPT because at least one refused." >&2
  fi
  return "$rc"
}

do_status() {
  echo "installed digest: $(installed_digest)"
  if [ -f "$STATE_DIR/manifest" ]; then
    echo "STAGED (not yet restored):"
    cut -f1 "$STATE_DIR/manifest" | sed 's/^/  /'
  else
    echo "nothing staged"
  fi
}

case "${1:---status}" in
  --stage)   shift; do_stage "$@" ;;
  --restore) do_restore ;;
  --status)  do_status ;;
  *) echo "usage: $0 --stage NAME... | --restore | --status" >&2; exit 2 ;;
esac
