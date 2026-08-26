#!/usr/bin/env bash
# overlay-ownership.sh — regression probe for overlay.sh's settings.json merge.
#
# CLAIM (defect 4): overlay.sh decides ownership of a target repo's hooks/skillOverrides by
# VOCABULARY (does this top-level key/event name happen to be one vstack also uses?) instead
# of by PROVENANCE (does this specific hook command point at a file vstack ships?). install.sh
# and uninstall.sh both compute $ourbasenames from the files vstack actually ships and match
# individual hook entries with `endswith("/hooks/" + $b)`, merging or removing only the entries
# that are actually vstack's. overlay.sh instead does `$dest * $ship` (jq deep-merge) and
# `.skillOverrides = ($ship.skillOverrides // {})` — for any event/key vstack also populates,
# the WHOLE array/object is replaced, foreign entries and all.
#
# This script is non-zero (defect reproduces) while that is true, and zero once overlay.sh
# merges by the same ownership rule install.sh/uninstall.sh use. It also asserts the positive
# direction: a STALE COPY of vstack's own hook — same basename vstack still ships, wrong/outdated
# args, as a fresh checkout of an old overlay commit would carry — must be resynced to exactly
# what vstack ships now, not left duplicated alongside the correct one. A version that "fixes"
# defect 4 by making overlay.sh a no-op on any collision would pass the first half of this probe
# and fail this half, because a no-op leaves the stale duplicate in place forever.
#
# Nothing here touches the real ~/.claude. Everything lives under a throwaway sandbox dir and
# a throwaway git repo inside it.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OVERLAY="$ROOT/overlay.sh"

[ -x "$OVERLAY" ] || { echo "FATAL: $OVERLAY missing or not executable" >&2; exit 2; }
command -v jq >/dev/null || { echo "FATAL: jq required" >&2; exit 2; }

SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/overlay-ownership.XXXXXX")
trap 'rm -rf "$SANDBOX"' EXIT
export HOME="$SANDBOX/home"
mkdir -p "$HOME"

DEST="$SANDBOX/target-repo"
mkdir -p "$DEST"
git -C "$DEST" init -q
git -C "$DEST" config user.email t@example.com
git -C "$DEST" config user.name "Overlay Repro"

fail=0
note() { printf '%s\n' "$1"; }
ok()   { printf 'PASS: %s\n' "$1"; }
bad()  { printf 'FAIL: %s\n' "$1"; fail=1; }

# --- discover, from vstack's own shipped settings.json, which hook events it populates -------
SHIP_EVENTS=$(jq -r '.hooks | keys[]' "$ROOT/claude/settings.json")
FIRST_SHIP_EVENT=$(printf '%s\n' "$SHIP_EVENTS" | head -1)

# An event vstack does NOT ship at all — used as a control: it must survive regardless of the
# defect, so if it does not, the fixture itself (not overlay.sh) is broken.
CONTROL_EVENT="Notification"
if printf '%s\n' "$SHIP_EVENTS" | grep -qxF "$CONTROL_EVENT"; then
  echo "FATAL: fixture assumption wrong — vstack now ships a $CONTROL_EVENT hook, pick another control event" >&2
  exit 2
fi

# basename of the first hook command vstack ships under FIRST_SHIP_EVENT — used to build a
# stale-but-recognisably-ours duplicate for the positive-direction fixture below.
FIRST_SHIP_BASENAME=$(jq -r --arg ev "$FIRST_SHIP_EVENT" \
  '.hooks[$ev][0].hooks[0].command | split("/") | last | rtrimstr("\"")' \
  "$ROOT/claude/settings.json")

# --- seed a foreign settings.json: a foreign hook on every event vstack ships, one on an event
# vstack does not ship, a foreign skillOverrides entry, a foreign permissions block, and one
# STALE COPY of a hook vstack DOES currently ship (same basename, wrong args — as a checkout of
# an old overlay commit would carry) mixed into the first event vstack ships -- this is the
# positive-direction fixture. ---------------------------------------------------------------
mkdir -p "$DEST/.claude"
python3 - "$DEST/.claude/settings.json" "$SHIP_EVENTS" "$CONTROL_EVENT" "$FIRST_SHIP_EVENT" "$FIRST_SHIP_BASENAME" <<'PY'
import json, sys
path, ship_events_raw, control_event, first_ship_event, first_ship_basename = sys.argv[1:6]
ship_events = [e for e in ship_events_raw.splitlines() if e]

hooks = {}
for ev in ship_events:
    entry = {"hooks": [{"type": "command", "command": "/repo/.claude/hooks/foreign-" + ev.lower() + ".sh"}]}
    if ev == first_ship_event:
        # a stale copy of vstack's OWN hook for this event: same basename vstack still ships
        # today, but with a marker argument no current vstack commit would ever write — as if
        # this repo was overlaid once, long ago, and never refreshed.
        stale = {"hooks": [{"type": "command",
                             "command": "\"$CLAUDE_PROJECT_DIR/.claude/hooks/" + first_ship_basename + "\"",
                             "statusMessage": "STALE-PRE-FIX-COPY-MARKER"}]}
        hooks[ev] = [entry, stale]
    else:
        hooks[ev] = [entry]

hooks[control_event] = [{"hooks": [{"type": "command", "command": "/repo/.claude/hooks/foreign-control.sh"}]}]

doc = {
    "hooks": hooks,
    "skillOverrides": {"my-private-skill": "off", "another-foreign-one": "name-only"},
    "permissions": {"allow": ["Bash(ls:*)"]},
}
with open(path, "w") as f:
    json.dump(doc, f, indent=2)
PY

git -C "$DEST" add -A
git -C "$DEST" commit -q -m "seed foreign .claude/settings.json"

BEFORE="$SANDBOX/before.json"
cp "$DEST/.claude/settings.json" "$BEFORE"

# --- run it -------------------------------------------------------------------------------
note "--- overlay.sh run 1 ---"
"$OVERLAY" "$DEST"
run1_rc=$?
note "overlay.sh exit code (run 1): $run1_rc"
[ "$run1_rc" -eq 0 ] || { echo "FATAL: overlay.sh itself failed" >&2; exit 2; }

AFTER="$DEST/.claude/settings.json"
jq -e . "$AFTER" >/dev/null || { echo "FATAL: overlay.sh left invalid JSON" >&2; exit 2; }

# --- assertion 1: foreign hooks on events vstack also ships must SURVIVE ------------------
while IFS= read -r ev; do
  [ -n "$ev" ] || continue
  marker="foreign-$(printf '%s' "$ev" | tr '[:upper:]' '[:lower:]').sh"
  if jq -e --arg m "$marker" '[.hooks[$ARGS.named.ev][]?.hooks[]?.command // empty] | any(test($m))' \
        --arg ev "$ev" "$AFTER" >/dev/null 2>&1; then
    ok "foreign $ev hook survived overlay"
  else
    bad "foreign $ev hook was destroyed by overlay (colliding event, wholesale array replace)"
  fi
done <<EOF
$SHIP_EVENTS
EOF

# --- assertion 2: foreign hook on a NON-colliding event must survive (sanity control) -----
if jq -e --arg ev "$CONTROL_EVENT" '[.hooks[$ev][]?.hooks[]?.command // empty] | any(test("foreign-control"))' \
      "$AFTER" >/dev/null 2>&1; then
  ok "control: foreign $CONTROL_EVENT hook survived (non-colliding event, as expected either way)"
else
  bad "control: foreign $CONTROL_EVENT hook vanished — fixture or overlay.sh broken outside the claimed defect"
fi

# --- assertion 3: foreign skillOverrides entries must SURVIVE -----------------------------
if jq -e '(.skillOverrides["my-private-skill"] == "off") and (.skillOverrides["another-foreign-one"] == "name-only")' \
      "$AFTER" >/dev/null 2>&1; then
  ok "foreign skillOverrides entries survived overlay"
else
  bad "foreign skillOverrides entries were wiped by overlay (skillOverrides = ship's set, not a merge)"
fi

# --- assertion 4: foreign permissions key must survive (not on vstack's allowlist) ---------
if jq -e '.permissions.allow == ["Bash(ls:*)"]' "$AFTER" >/dev/null 2>&1; then
  ok "foreign permissions key survived overlay"
else
  bad "foreign permissions key was altered — vstack does not even ship this key, should be untouched"
fi

# --- assertion 5 (positive direction): the STALE COPY of vstack's own hook must be resynced,
# i.e. the marker from the pre-fix copy must be GONE and there must be exactly one entry for
# that basename left (no duplicate lingering alongside the refreshed one). ------------------
if jq -e '[.hooks[$ev][]?.hooks[]?.statusMessage // empty] | any(. == "STALE-PRE-FIX-COPY-MARKER")' \
      --arg ev "$FIRST_SHIP_EVENT" "$AFTER" >/dev/null 2>&1; then
  bad "stale vstack-owned hook copy (marker STALE-PRE-FIX-COPY-MARKER) survived — vstack's own entries must resync to what it currently ships, not accumulate stale duplicates"
else
  ok "stale vstack-owned hook copy was correctly resynced/removed"
fi
dupe_count=$(jq --arg ev "$FIRST_SHIP_EVENT" --arg b "$FIRST_SHIP_BASENAME" \
  '[.hooks[$ev][]?.hooks[]?.command // empty | select(test("/hooks/" + $b + "\"?$"))] | length' \
  "$AFTER" 2>/dev/null || echo "?")
note "entries for $FIRST_SHIP_BASENAME under $FIRST_SHIP_EVENT after overlay: $dupe_count"
if [ "$dupe_count" = "1" ]; then
  ok "exactly one $FIRST_SHIP_BASENAME entry after overlay (no duplicate)"
else
  bad "expected exactly one $FIRST_SHIP_BASENAME entry after overlay, found $dupe_count"
fi

# --- idempotency: run again, diff byte-for-byte -------------------------------------------
note "--- overlay.sh run 2 (idempotency) ---"
cp "$AFTER" "$SANDBOX/after-run1.json"
"$OVERLAY" "$DEST" >/dev/null
run2_rc=$?
note "overlay.sh exit code (run 2): $run2_rc"
if diff -q "$SANDBOX/after-run1.json" "$AFTER" >/dev/null 2>&1; then
  ok "idempotent: settings.json byte-identical after a second run"
else
  note "NOTE: settings.json changed on second run (not fatal to this probe, but worth knowing):"
  diff "$SANDBOX/after-run1.json" "$AFTER" || true
fi

echo
if [ "$fail" -eq 0 ]; then
  echo "RESULT: overlay.sh preserves foreign config and still removes its own retired entries (fixed)"
else
  echo "RESULT: overlay.sh destroys foreign config it does not own (defect 4 reproduced)"
fi
exit "$fail"
