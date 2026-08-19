#!/usr/bin/env bash
# uninstall.sh — restore ~/.claude and ~/.config/agents from an install.sh backup.
#
# install.sh copies every file it overwrites into
# ~/.config/agents/backups/install-<timestamp>/ — real paths under files/, plus legacy
# top-level entries from older installs (flat `tr / _` names, `skills_<name>/`,
# `claude.json`). Nothing restores those backups automatically — this does. It also removes
# the ~/.config/agents/vstack-repo pointer install.sh writes.
#
# Usage:
#   ./uninstall.sh --list                 show available backup timestamps, newest first
#   ./uninstall.sh [--from <timestamp>]   print the restore plan for the newest (or named)
#                                          backup; nothing changes without --yes
#   ./uninstall.sh --yes [--from <ts>]    actually restore
#   ./uninstall.sh --dry-run [--from ts]  print the plan and exit; never requires --yes
set -uo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BKROOT="$HOME/.config/agents/backups"
SECRETS="$HOME/.config/agents/secrets.env"

usage() {
  sed -n '2,16p' "$0"
}

MODE=restore
FROM=""
DRY=0
YES=0
while [ $# -gt 0 ]; do
  case "$1" in
    --list) MODE=list; shift ;;
    --from)
      [ $# -ge 2 ] || { echo "uninstall.sh: --from requires a timestamp" >&2; exit 2; }
      FROM="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    --yes) YES=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "uninstall.sh: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

list_timestamps() {
  [ -d "$BKROOT" ] || return 0
  for d in "$BKROOT"/install-*/; do
    [ -d "$d" ] || continue
    b=$(basename "$d")
    printf '%s\n' "${b#install-}"
  done | sort -r
}

if [ "$MODE" = list ]; then
  TS=$(list_timestamps)
  if [ -z "$TS" ]; then
    echo "no install backups found in $BKROOT"
    exit 0
  fi
  echo "available backups (newest first):"
  printf '%s\n' "$TS" | while IFS= read -r t; do echo "  $t"; done
  exit 0
fi

# --- resolve which backup to restore -------------------------------------------------------
if [ -n "$FROM" ]; then
  case "$FROM" in
    install-*) BK="$BKROOT/$FROM" ;;
    *)         BK="$BKROOT/install-$FROM" ;;
  esac
  [ -d "$BK" ] || { echo "uninstall.sh: no backup found for '$FROM' (try --list)" >&2; exit 1; }
else
  latest=$(list_timestamps | head -1)
  [ -n "$latest" ] || { echo "uninstall.sh: no install backups found in $BKROOT — nothing to restore" >&2; exit 1; }
  BK="$BKROOT/install-$latest"
fi

echo "restoring from: $BK"

# --- map a flat backup filename back to its real installed path ----------------------------
# Inverse of install.sh's back(): "${path#$HOME/}" then `tr / _`. claude.json is special-cased
# there too (copied without flattening), so it is special-cased here.
map_target() {
  name="$1"
  case "$name" in
    claude.json) printf '%s\n' "$HOME/.claude.json" ;;
    skills_*)    printf '%s\n' "$HOME/.claude/skills/${name#skills_}" ;;
    *)           printf '%s\n' "$HOME/$(printf '%s' "$name" | tr '_' '/')" ;;
  esac
}

# --- enumerate restore pairs (src|target), covering both backup formats --------------------
restore_pairs() {
  if [ -d "$BK/files" ]; then
    find "$BK/files" -type f | while IFS= read -r f; do
      printf '%s|%s\n' "$f" "$HOME/${f#$BK/files/}"
    done
  fi
  for e in "$BK"/*; do
    [ -e "$e" ] || continue
    n=$(basename "$e")
    [ "$n" = "files" ] && continue
    printf '%s|%s\n' "$e" "$(map_target "$n")"
  done
}

# --- build the restore plan -----------------------------------------------------------------
PLAN_EMPTY=1
while IFS='|' read -r src tgt; do
  [ -n "$src" ] || continue
  [ "$tgt" = "$SECRETS" ] && continue   # never touch secrets.env, even hypothetically
  echo "restore  $tgt  (from ${src#$BK/})"
  PLAN_EMPTY=0
done < <(restore_pairs)
[ -f "$HOME/.config/agents/vstack-repo" ] && echo "remove   $HOME/.config/agents/vstack-repo  (install.sh pointer)"

# skills this repo installs that the backup does not contain existed before install → vstack
# added them, so an uninstall should remove them. Never touch a symlink (builtin/plugin skill).
REMOVE_LIST=""
for d in "$SRC"/claude/skills/*/; do
  [ -d "$d" ] || continue
  s=$(basename "$d")
  [ -d "$BK/skills_$s" ] && continue
  tgt="$HOME/.claude/skills/$s"
  [ -L "$tgt" ] && continue
  [ -e "$tgt" ] || continue
  echo "remove   $tgt  (installed by vstack, not present in backup)"
  REMOVE_LIST="$REMOVE_LIST $s"
done

if [ "$PLAN_EMPTY" = 1 ] && [ -z "$REMOVE_LIST" ]; then
  echo "(backup is empty — nothing to restore)"
fi

if [ "$DRY" = 1 ]; then
  echo
  echo "dry run — nothing changed."
  exit 0
fi

if [ "$YES" != 1 ]; then
  echo
  echo "pass --yes to actually restore (this overwrites the files listed above)."
  exit 1
fi

# --- execute ---------------------------------------------------------------------------------
while IFS='|' read -r src tgt; do
  [ -n "$src" ] || continue
  [ "$tgt" = "$SECRETS" ] && continue
  mkdir -p "$(dirname "$tgt")"
  if [ -d "$src" ]; then
    rm -rf "$tgt"
    cp -R "$src" "$tgt"
  else
    cp -p "$src" "$tgt" 2>/dev/null || cp "$src" "$tgt"
  fi
done < <(restore_pairs)
rm -f "$HOME/.config/agents/vstack-repo"

# install.sh chmods hooks/bin/skill-scripts 755 after copying; match that here so restored
# files stay executable.
[ -d "$HOME/.claude/hooks" ] && chmod 755 "$HOME"/.claude/hooks/*.sh 2>/dev/null
[ -d "$HOME/.config/agents/bin" ] && chmod 755 "$HOME"/.config/agents/bin/* 2>/dev/null
[ -d "$HOME/.claude/skills" ] && find "$HOME/.claude/skills" -name "*.sh" -exec chmod 755 {} + 2>/dev/null

for s in $REMOVE_LIST; do
  tgt="$HOME/.claude/skills/$s"
  [ -L "$tgt" ] && continue
  [ -e "$tgt" ] && rm -rf "$tgt"
done

echo "restore complete."
