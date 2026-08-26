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

# Plain, unsigned, world-editable-by-this-user text: a list of paths install.sh wrote, not a
# signed attestation. Written by install.sh (see its own comment above OWNED_PATHS there);
# read-only here. Absent entirely on a machine installed by vstack <= 1.45.1 and never
# reinstalled since -- owns_path() below treats that as "assume everything, the old way",
# which is what every uninstall.sh release before profiles existed already did.
OWNED_PATHS="$HOME/.config/agents/vstack-installed"
# A profile install (core/team/ui) only ever calls install.sh's own() for the subset it
# actually copied, so OWNED_PATHS is already profile-accurate by construction -- this uninstall
# does not need to know which profile was used, only whether a given candidate path is IN the
# record. No record at all (pre-1.46.1, or an install this old uninstall.sh has never seen
# write one) falls back to "yes", preserving the pre-profile behaviour of removing anything this
# checkout would install today.
owns_path(){ # <path>
  [ -f "$OWNED_PATHS" ] || return 0
  grep -qxF "$1" "$OWNED_PATHS" 2>/dev/null
}

# Claude Code reads its user config from $CLAUDE_CONFIG_DIR when set, ~/.claude otherwise.
# Mirrors install.sh: anything else and this operates on a directory the install never used.
CDIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then CJSON="$CDIR/.claude.json"; else CJSON="$HOME/.claude.json"; fi

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

# uninstall never had a backup helper — `back` is install.sh's, and calling it here was a
# command-not-found that silently skipped the copy before every edit this script makes.
# Anything modified below is copied next to the backup being restored from, so an uninstall is
# itself reversible.
UNDO="$BK/pre-uninstall"
back(){ [ -f "$1" ] || return 0; mkdir -p "$UNDO$(dirname "$1")"; cp "$1" "$UNDO$1" 2>/dev/null || true; }

# --- map a flat backup filename back to its real installed path ----------------------------
# Inverse of install.sh's back(): "${path#$HOME/}" then `tr / _`. claude.json is special-cased
# there too (copied without flattening), so it is special-cased here.
map_target() {
  name="$1"
  case "$name" in
    claude.json) printf '%s\n' "$CJSON" ;;
    skills_*)    printf '%s\n' "$CDIR/skills/${name#skills_}" ;;
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
  # files_abs/ holds anything install.sh backed up from outside $HOME — which is everything
  # under a CLAUDE_CONFIG_DIR pointed elsewhere. It records the full path, so it restores to
  # the exact path it came from rather than being reinterpreted as HOME-relative.
  #
  # This was missing, and the omission was worse than a no-op: the loop below treated files_abs
  # as a legacy flat name, mapped it under $HOME, and the removal pass then deleted the live
  # external file. An external-config uninstall destroyed the user's CLAUDE.md and left the only
  # copy in a tree they had no reason to look in.
  if [ -d "$BK/files_abs" ]; then
    find "$BK/files_abs" -type f | while IFS= read -r f; do
      printf '%s|%s\n' "$f" "${f#$BK/files_abs}"
    done
  fi
  for e in "$BK"/*; do
    [ -e "$e" ] || continue
    n=$(basename "$e")
    # pre-uninstall/ is this script's OWN safety backup (see `back()`/$UNDO above), written into
    # $BK by this exact run. Without this exclusion it fell through to the legacy-flat-name
    # branch below, map_target had no rule for it so it mapped to $HOME/pre-uninstall, and a
    # second `uninstall.sh --yes` against the same backup copied uninstall's own backup-of-a-
    # backup into the user's home as a permanent, ever-growing directory.
    case "$n" in files|files_abs|pre-uninstall) continue ;; esac
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
#
# owns_path gates this on the ownership record: a profile install (core, ui) that never copied a
# given skill directory never called install.sh's own() for it either, so it is not vstack's to
# remove here even though this checkout still ships it. Without this a `--profile=core` install
# (zero skills) followed by uninstall.sh would delete all 28 skill directories -- the "wrong set
# does not install, right set does" half of the profile promise, un-done on the way back out.
REMOVE_LIST=""
for d in "$SRC"/claude/skills/*/; do
  [ -d "$d" ] || continue
  s=$(basename "$d")
  [ -d "$BK/skills_$s" ] && continue
  tgt="$CDIR/skills/$s"
  owns_path "$tgt" || continue
  [ -L "$tgt" ] && continue
  [ -e "$tgt" ] || continue
  echo "remove   $tgt  (installed by vstack, not present in backup)"
  REMOVE_LIST="$REMOVE_LIST $s"
done

# Same rule, applied to everything else this repo copies in. It only ever ran for skills, so
# uninstalling a fresh install left 14 agents, 15 commands, 8 hooks and 6 wrappers sitting in
# ~/.claude with nothing to say where they came from: the backup held no prior version to
# restore over them, and only skills had a branch that removed what the backup lacked.
#
# settings.json and .claude.json are deliberately not in this list. install.sh MERGES those
# rather than copying them, so there is no version of them that belongs solely to vstack —
# deleting either would take the user's own configuration with it. If the backup holds a prior
# copy, the restore pass above already put it back, and for .claude.json it always does:
# install.sh backs the file up before merging, and creates it as `{}` first where it is absent,
# so there is always a prior copy to come back to. The uninstall-clean matrix case asserts that
# end to end -- vstack's mcpServers entries gone, the user's own still registered -- with a
# positive control that the entries were there to begin with.
#
# A file only qualifies if it is still byte-identical to the copy vstack installed. Once it
# differs, somebody edited it, and their edit is not this script's to throw away — CLAUDE.md is
# the obvious case, since it accumulates a machine's own notes and there may be no backup
# holding those. Changed files are kept and named, so the plan says what it is leaving and why
# rather than deleting quietly.
FILE_REMOVE_LIST=""
KEPT_EDITED=""
plan_file_removal() { # <installed-path> <repo-source-or-empty>
  tgt="$1"; src="${2:-}"
  [ -e "$tgt" ] || return 0
  [ -L "$tgt" ] && return 0
  # Same profile gate as the skills loop above: not in the ownership record means this exact
  # install run never claimed it, so it is not this uninstall's to remove -- a hook, agent,
  # command or wrapper a profile-limited install deliberately left uncopied stays exactly as
  # uncopied as it was, rather than being reported "removed" for a copy that was never made.
  owns_path "$tgt" || return 0
  # Backup lookup follows the same split install.sh used when writing: HOME-relative under
  # files/, full path under files_abs/. Checking only the first meant an external config file
  # never looked backed up, so it was classified as removable and deleted.
  case "$tgt" in
    "$HOME"/*) [ -e "$BK/files/${tgt#"$HOME"/}" ] && return 0 ;;
    *)         [ -e "$BK/files_abs$tgt" ] && return 0 ;;
  esac
  if [ -n "$src" ] && [ -e "$src" ] && ! cmp -s "$src" "$tgt"; then
    KEPT_EDITED="$KEPT_EDITED$tgt
"
    return 0
  fi
  echo "remove   $tgt  (installed by vstack, not present in backup)"
  # Newline-delimited, not space-delimited. These hold absolute paths, and a home directory
  # with a space in it split every one of them into fragments that matched nothing — so an
  # uninstall under such a home removed the skills and left every hook, command, agent and
  # wrapper in place while printing "restore complete".
  FILE_REMOVE_LIST="$FILE_REMOVE_LIST$tgt
"
}
for f in "$SRC"/claude/hooks/*.sh;    do [ -e "$f" ] && plan_file_removal "$CDIR/hooks/$(basename "$f")" "$f"; done
for f in "$SRC"/claude/agents/*.md;   do [ -e "$f" ] && plan_file_removal "$CDIR/agents/$(basename "$f")" "$f"; done
for f in "$SRC"/claude/agents/reference/*.ref; do [ -e "$f" ] && plan_file_removal "$CDIR/agents/reference/$(basename "$f")" "$f"; done
for f in "$SRC"/claude/commands/*.md; do [ -e "$f" ] && plan_file_removal "$CDIR/commands/$(basename "$f")" "$f"; done
for f in "$SRC"/bin/*;                do [ -e "$f" ] && plan_file_removal "$HOME/.config/agents/bin/$(basename "$f")" "$f"; done
plan_file_removal "$CDIR/CLAUDE.md"                    "$SRC/claude/CLAUDE.md"
plan_file_removal "$CDIR/statusline.sh"                "$SRC/claude/statusline.sh"
# Conductor. install.sh writes settings.toml where none exists and rewrites settings.managed.toml
# every time, and this script had no reference to conductor at all -- so an uninstall left both in
# place permanently. The managed file is the one that pins models, fast mode and plan mode, which
# means a removed vstack went on setting a machine's policy. The same three rules apply as to
# everything else here: a backup wins, an edited file is kept and named, and only a file still
# byte-identical to what vstack shipped is removed.
plan_file_removal "$HOME/.conductor/settings.toml"         "$SRC/conductor/settings.toml"
plan_file_removal "$HOME/.conductor/settings.managed.toml" "$SRC/conductor/settings.managed.toml"
plan_file_removal "$CDIR/skills/LICENSE.pstack"        "$SRC/claude/skills/LICENSE.pstack"
plan_file_removal "$CDIR/skills/ATTRIBUTION.md"        "$SRC/claude/skills/ATTRIBUTION.md"
plan_file_removal "$HOME/.config/agents/shell/claude-parity.zsh" "$SRC/shell/claude-parity.zsh"
if [ -n "$KEPT_EDITED" ]; then
  echo "keeping  files you have edited since install (not removing, no backup holds your version):"
  printf '%s' "$KEPT_EDITED" | while IFS= read -r k; do [ -n "$k" ] && echo "         $k"; done
fi

if [ "$PLAN_EMPTY" = 1 ] && [ -z "$REMOVE_LIST" ] && [ -z "$FILE_REMOVE_LIST" ]; then
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
[ -d "$CDIR/hooks" ] && chmod 755 "$CDIR"/hooks/*.sh 2>/dev/null
[ -d "$HOME/.config/agents/bin" ] && chmod 755 "$HOME"/.config/agents/bin/* 2>/dev/null
[ -d "$CDIR/skills" ] && find "$CDIR/skills" -name "*.sh" -exec chmod 755 {} + 2>/dev/null

for s in $REMOVE_LIST; do
  tgt="$CDIR/skills/$s"
  [ -L "$tgt" ] && continue
  [ -e "$tgt" ] && rm -rf "$tgt"
done
printf '%s' "$FILE_REMOVE_LIST" | while IFS= read -r tgt; do
  [ -n "$tgt" ] || continue
  [ -L "$tgt" ] && continue
  [ -e "$tgt" ] && rm -f "$tgt"
done

# --- settings.json: unpick vstack's own entries, leave everything else ------------------------
#
# Not deleting the file — install.sh merges into it, so it holds the user's configuration too.
# But leaving it entirely alone was worse than either extreme: a fresh install followed by a
# fresh uninstall left six hook commands pointing at scripts that had just been deleted, plus
# vstack's model policy and all seventeen skillOverrides still in force. The result was not a
# removed tool, it was a broken one, and later Claude sessions can error on the dead hooks.
#
# Ownership is decided by what this repo ships, never by where a file happens to sit. A hook is
# vstack's when its command ends in one of the hook filenames vstack installs; the directory is
# shared with the user and proves nothing. A skillOverride whose value still
# matches what vstack shipped is vstack's; one the user has since changed is theirs and stays. A
# top-level key is removed only if it still equals what this repo ships — edit it and it is
# yours. That is conservative in the right direction: the failure mode is leaving something
# behind, not deleting something somebody wanted.
if command -v jq >/dev/null 2>&1 && [ -f "$CDIR/settings.json" ] && [ -f "$SRC/claude/settings.json" ]; then
  utmp=$(mktemp)
  # The names vstack installs, taken from the scripts install.sh copies (install.sh:162) and the
  # statusline it writes (install.sh:410). Deriving them from claude/settings.json instead was a
  # reader pointed at a source the writer never uses: the template spells its commands
  # "$CLAUDE_PROJECT_DIR/.claude/hooks/x.sh" -- embedded quotes, for project scope -- so every
  # basename split out of it carried a trailing quote and matched no installed path. Both
  # ownership branches below were dead for three releases and the printed line still claimed
  # the cleanup had happened.
  ubase=$(for _f in "$SRC"/claude/hooks/*.sh; do [ -e "$_f" ] && basename "$_f"; done | jq -R . | jq -s .)
  usl=$(basename "$SRC/claude/statusline.sh")
  if [ "$ubase" = "[]" ]; then
    echo "warn     $CDIR/settings.json left alone (no hook scripts under $SRC/claude/hooks — ownership unknowable)" >&2
  elif jq -s --arg h "$CDIR/hooks" --argjson ourbase "$ubase" --arg shipsl "$usl" '
      . as [$live, $ship]
      | ($live.hooks // {}) as $lh
      | $live
      # Hook entries that run one of vstack'"'"'s own hook scripts, matched by filename.
      #
      # Directory prefix was the first attempt and it deleted the user'"'"'s own hooks. Anyone who
      # keeps personal scripts in ~/.claude/hooks -- the conventional location, which vstack also
      # installs into -- had every entry pointing at them stripped, while the scripts themselves
      # stayed on disk. The printed line still said "vstack hooks ... removed", so the tool
      # reported a narrow cleanup while doing a broad one.
      #
      # Ownership is a filename, not a parent directory, and the filenames come from disk
      # ($ourbase/$shipsl above) rather than from any JSON either side happens to spell.
      | .hooks = ( $lh
          | with_entries(.value |= map(select(
              [.hooks[]?.command]
              | map(. as $c | $ourbase | any(. as $b | $c | endswith("/hooks/" + $b)))
              | any | not )))
          | with_entries(select(.value | length > 0)) )
      | if (.hooks | length) == 0 then del(.hooks) else . end
      # skillOverrides vstack set and the user has not changed since.
      | .skillOverrides = ( (.skillOverrides // {})
          | with_entries(select(
              (.key as $k | ($ship.skillOverrides // {}) | has($k)) and
              (.value == ($ship.skillOverrides // {})[.key]) | not )) )
      | if (.skillOverrides | length) == 0 then del(.skillOverrides) else . end
      # statusLine points at a file vstack installed and has just removed.
      | if $shipsl != "" and ((((.statusLine.command? // "") | split("/") | last)) == $shipsl)
        then del(.statusLine) else . end
      # Top-level policy keys, removed only where the live value still equals what vstack ships.
      | reduce ($ship | keys_unsorted[]) as $k (.;
          if $k == "hooks" or $k == "skillOverrides" then .
          elif has($k) and (.[$k] == $ship[$k]) then del(.[$k])
          else . end)
    ' "$CDIR/settings.json" "$SRC/claude/settings.json" > "$utmp" && jq -e . "$utmp" >/dev/null 2>&1; then
    back "$CDIR/settings.json"
    cat "$utmp" > "$CDIR/settings.json"
    echo "cleaned  $CDIR/settings.json (vstack hooks, overrides and unedited policy keys removed)"
  fi
  rm -f "$utmp"
fi

# --- mcp servers: unpick vstack's own entries from ~/.claude.json, leave everything else -------
#
# install.sh merges cloudflare-mcp and context7 into the GLOBAL mcpServers map and never removes
# either, so leaving this file alone -- the way settings.json used to be left alone -- broke the
# same promise the same way: a removed vstack left two mcpServers entries behind, one of them
# (cloudflare-mcp) pointing at a wrapper the bin/ removal pass above had just deleted. Claude Code
# then tries to spawn a stdio command that no longer exists on every session.
#
# Ownership follows the install-time backup of this exact file, the same signal the file-removal
# pass above uses ("present in the backup" = "was here before vstack touched it"): a key vstack
# ships is removed only if THIS backup's claude.json did not already have it, and only if the
# live value still equals what vstack currently ships -- a value the user has since edited is
# kept and named, never silently overwritten or deleted, same as an edited settings.json key
# above. A key that predates the install (your own context7, say) is never touched: install.sh's
# merge may already have folded some of vstack's fields into it on key collision, but its
# existence in the backup is what says it was yours first.
if command -v jq >/dev/null 2>&1 && [ -f "$CJSON" ] && [ -f "$SRC/mcp/servers.json" ]; then
  mship=$(mktemp); morig=$(mktemp)
  sed "s|__HOME__|$HOME|g" "$SRC/mcp/servers.json" > "$mship"
  if [ -f "$BK/claude.json" ]; then cat "$BK/claude.json" > "$morig"; else printf '{}\n' > "$morig"; fi
  MCP_REMOVE=""
  while IFS=$'\t' read -r mstatus mkey; do
    [ -n "$mkey" ] || continue
    case "$mstatus" in
      remove)
        MCP_REMOVE="$MCP_REMOVE $mkey"
        echo "remove   mcpServers.$mkey in $CJSON  (installed by vstack, not present in backup)" ;;
      kept-preexisting)
        echo "keeping  mcpServers.$mkey in $CJSON  (present before vstack installed it)" ;;
      kept-edited)
        echo "keeping  mcpServers.$mkey in $CJSON  (edited since install, not vstack's alone to remove)" ;;
    esac
  done < <(jq -s -r '
      . as [$live, $ship, $orig]
      | $ship as $shipm
      | ($orig.mcpServers // {}) as $origm
      | ($live.mcpServers // {}) as $livem
      | ($shipm | keys_unsorted[]) as $k
      | select($livem | has($k))
      | if ($origm | has($k)) then "kept-preexisting\t\($k)"
        elif ($livem[$k] == $shipm[$k]) then "remove\t\($k)"
        else "kept-edited\t\($k)"
        end
    ' "$CJSON" "$mship" "$morig" 2>/dev/null)
  if [ -n "$MCP_REMOVE" ]; then
    back "$CJSON"
    mtmp=$(mktemp)
    # shellcheck disable=SC2086  # $MCP_REMOVE is a space-separated list of our own key names
    # (never containing spaces) and has to word-split here to become one -R value per line.
    mkeys=$(printf '%s\n' $MCP_REMOVE | jq -R . | jq -s .)
    if jq --argjson keys "$mkeys" '
        .mcpServers = ((.mcpServers // {}) | with_entries(select(([.key] | inside($keys)) | not)))
        | if ((.mcpServers // {}) | length) == 0 then del(.mcpServers) else . end
      ' "$CJSON" > "$mtmp" && jq -e . "$mtmp" >/dev/null 2>&1; then
      cat "$mtmp" > "$CJSON"
      echo "cleaned  $CJSON (vstack mcpServers entries removed:$MCP_REMOVE)"
    fi
    rm -f "$mtmp"
  fi
  rm -f "$mship" "$morig"
fi

# --- the ownership record -----------------------------------------------------------------------
# install.sh appends every path it owns here so the NEXT install can tell its own previous
# payload from the user's files. It is plain, unsigned, world-editable-by-this-user text -- a
# list of paths install.sh wrote, not a signed attestation that those paths are still what it
# wrote. Once vstack is removed the record is a liability: a user who later writes their own
# ~/.claude/hooks/format.sh would have it silently claimed by a reinstall.
if [ -f "$OWNED_PATHS" ]; then
  rm -f "$OWNED_PATHS"
  echo "removed  $OWNED_PATHS  (ownership record; a fresh install starts with no ownership claims)"
fi

# --- claude-mem hooks.json: undo the async edit older vstack versions made ---------------------
#
# vstack up to 1.45.1 flipped claude-mem's own hooks.json from sync to async and left the prior
# contents beside it as hooks.json.vstack-orig. 1.46.0 removed that edit entirely -- claude-mem
# was measured injecting nothing, so there was no work to keep off the critical path. This block
# stays because a machine that ran an older vstack still carries the sidecar, and a version that
# stopped making an edit is not a version that gets to stop undoing it. It is a no-op on any
# machine that never had claude-mem installed.
if command -v jq >/dev/null 2>&1 && [ -d "$CDIR/plugins/cache/thedotmack/claude-mem" ]; then
  for cm_orig in "$CDIR"/plugins/cache/thedotmack/claude-mem/*/hooks/hooks.json.vstack-orig; do
    [ -f "$cm_orig" ] || continue
    cm_f="${cm_orig%.vstack-orig}"
    if [ -f "$cm_f" ] && jq -e '[.hooks.UserPromptSubmit[]?.hooks[]?.async] | all' "$cm_f" >/dev/null 2>&1; then
      cat "$cm_orig" > "$cm_f"
      echo "restored $cm_f  (claude-mem's own hooks.json, vstack's async edit undone)"
    else
      echo "keeping  $cm_f  (changed since vstack edited it, not vstack's to overwrite)"
    fi
    rm -f "$cm_orig"
  done
fi

# The trust store is vstack'"'"'s alone: it exists so the Stop hook will execute a repo'"'"'s gate.
if [ -f "$HOME/.config/agents/verify-trust" ]; then
  rm -f "$HOME/.config/agents/verify-trust"
  echo "removed  $HOME/.config/agents/verify-trust"
fi

# Shell blocks vstack wrote, matched by their own sentinels so a hand-edited rc is left alone.
for rc in .zshrc .zshenv .bashrc .profile; do
  [ -f "$HOME/$rc" ] || continue
  grep -q 'claude-parity' "$HOME/$rc" 2>/dev/null || continue
  back "$HOME/$rc"
  stmp=$(mktemp)
  # The env block is removed first and by its own sentinels. Running the plain-block
  # expression first consumed the line "# >>> claude-parity env >>>" — which also contains
  # ">>> claude-parity" — and then ran on to the wrong terminator, so .zshrc came out clean
  # while .zshenv kept its block. The earlier attempt at this fix also carried a stray '>' in
  # the pattern, which matched nothing at all.
  sed -e '/>>> claude-parity env >>>/,/<<< claude-parity env <<</d' \
      -e '/>>> claude-parity >>>/,/<<< claude-parity <<</d' \
      -e '/claude-parity\.zsh/d' \
    "$HOME/$rc" > "$stmp" && cat "$stmp" > "$HOME/$rc"
  rm -f "$stmp"
  echo "cleaned  ~/$rc (claude-parity block removed)"
done

echo "restore complete."
