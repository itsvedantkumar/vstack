#!/usr/bin/env bash
# tests/inventory-fixture.sh — proves the CONSUMERS of claude/inventory.json's seven component
# families notice when the tree gains a member, the way tests/gate-falsifiability.sh proves the
# CHECKS in .claude/verify.sh can fail.
#
# Different subject, same shape. gate-falsifiability.sh breaks what a CHECK watches and requires
# the gate to go red naming that check. This breaks nothing -- it ADDS one minimal, valid member
# to each of the seven families claude/inventory.json documents (skills, agents,
# agent_references, commands, hooks, wrappers, mcp_servers) and requires every downstream
# consumer of that family -- the things that install it, count it, or report on it -- to notice.
# A consumer that stays green with the plant in place has not verified the family it claims to
# cover; it has verified that nothing changed, which is a different and much weaker claim.
#
# Per plant, every consumer here is run in the same invocation shape twice: once with no plant
# (the positive control -- everything must be green, or a "STALE" verdict later is meaningless
# because the harness could not tell a healthy tree from a broken one either) and once with the
# plant live. The assertion that makes this a test rather than a demo: a consumer that PASSES
# with the plant in place is the finding, printed as `STALE CONSUMER: <name> did not notice
# <family>/<plant>`. Some of those are structural and expected (bin/doctor --drift never reads
# mcp/servers.json; uninstall.sh never plans removing a merged MCP entry; README publishes no
# count for agent_references at all) -- printed anyway, because "expected" is not "invisible",
# and a reader deciding whether to trust a green run here needs the full matrix, not a filtered
# one.
#
# Concurrency, same discipline as gate-falsifiability.sh and for the same measured reason: three
# sessions have chased a verify.sh run that named a defect a harness had planted and not yet
# cleaned up. Acquire the shared lock, export VSTACK_FALSIFY=1 so a concurrent verify.sh refuses
# instead of reporting a false failure, and use tests/lib-collision-guard.sh's cg_save/
# cg_checkpoint/cg_restore rather than an unconditional save-and-restore -- a blind restore in
# this tree has already deleted two agents' uncommitted work.
#
# Usage: tests/inventory-fixture.sh [family ...]     (default: all seven)
# Runs by hand, not in CI: it installs the payload for real into scratch HOMEs, several times
# over (bin/doctor --drift's baseline, tests/install-matrix.sh's own internal installs,
# uninstall.sh --dry-run's pre-plant install), and calls the real `claude` CLI for
# tests/plugin-manifests.sh. Offline otherwise. Expect a few minutes.

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
SRC=$(pwd)
# shellcheck source=tests/lib-collision-guard.sh
. "$SRC/tests/lib-collision-guard.sh"

PASS=0; FAIL=0; STALE=0; UNKNOWN=0
ok(){   printf 'ok    %s\n' "$1"; PASS=$((PASS+1)); }
bad(){  printf 'FAIL  %s\n      %s\n' "$1" "${2:-}"; FAIL=$((FAIL+1)); }
noticed(){ printf '  notice  %-24s %s\n' "$1" "$2"; }
stale(){   printf '  STALE   %-24s %s\n' "$1" "$2"
  STALE_LINES="$STALE_LINES
STALE CONSUMER: $1 did not notice $3/$4 ($2)"
  STALE=$((STALE+1))
}
# A consumer that exited non-zero but never mentioned this family's plant is NOT the same claim
# as STALE ("ran clean, structurally could not have noticed") -- it may have failed for a real,
# unrelated reason, and folding the two together hides that reason behind a label that reads as
# reassuring. Found the hard way: do_unplant's own directory-leak bug (see its comment) made
# plugin-manifests.sh exit non-zero on every family after skills in one run, and the first cut of
# this predicate recorded all of them as STALE because none mentioned that run's own family name
# -- which was true and also not what "STALE" is supposed to claim. unknown() prints the
# consumer's own FAIL line(s) so the reader can attribute it instead of the harness guessing.
unknown(){ printf '  UNKNOWN %-24s %s\n' "$1" "$2"
  STALE_LINES="$STALE_LINES
UNKNOWN CONSUMER: $1 exited non-zero for $3/$4 without mentioning it -- attribute by hand ($2)"
  UNKNOWN=$((UNKNOWN+1))
}
skip_row(){ printf '  n/a     %-24s %s\n' "$1" "$2"; }
STALE_LINES=""

# tree_fingerprint() (tests/lib-collision-guard.sh, sourced above), not bare `git status
# --porcelain`: porcelain cannot see an empty directory, and do_plant()'s own `mkdir -p` is
# exactly that shape. This is the file that bit on this once already (do_unplant's directory
# leak, fixed in abbf41a) -- the fingerprint is what turns "forgot to rmdir" into a loud failure
# here instead of a silently poisoned baseline for the next family.
PRE_STATUS=$(tree_fingerprint .)

# --- concurrency: acquire the same lock verify.sh checks, the same way gate-falsifiability.sh
# does. --git-common-dir, not --git-dir: the latter is per-worktree, so a lock written there is
# invisible to a peer session working a different worktree of the same repo.
LOCKFILE="$(git rev-parse --git-common-dir 2>/dev/null)/vstack-falsifiability.lock"
if [ -z "$LOCKFILE" ] || [ "$LOCKFILE" = "/vstack-falsifiability.lock" ]; then
  echo "ABORT: could not resolve --git-common-dir; refusing to run without a collision lock"
  exit 2
fi
if [ -f "$LOCKFILE" ] && kill -0 "$(head -1 "$LOCKFILE" 2>/dev/null)" 2>/dev/null; then
  _held_pid=$(head -1 "$LOCKFILE" 2>/dev/null)
  _held_cwd=$(sed -n 2p "$LOCKFILE" 2>/dev/null)
  echo "REFUSED: $LOCKFILE is held by pid $_held_pid, working ${_held_cwd:-an unrecorded path} -- another falsifiability run owns it right now."
  echo "         wait for it to finish."
  exit 2
fi
# Line 2 is this process's own cwd, read back by verify.sh's refusal message and by the REFUSED
# case above -- see tests/gate-falsifiability.sh's matching comment for why this beats naming
# "this working tree" unconditionally.
printf '%s\n%s\n' "$$" "$(pwd)" > "$LOCKFILE"
export VSTACK_FALSIFY=1
release_lock(){ [ -f "$LOCKFILE" ] && [ "$(head -1 "$LOCKFILE" 2>/dev/null)" = "$$" ] && rm -f "$LOCKFILE"; }

FAMILIES="skills agents agent_references commands hooks wrappers mcp_servers"
WANT="${*:-$FAMILIES}"
want_fam(){ case " $WANT " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

# --- per-family plant metadata ------------------------------------------------------------------
plant_path(){ case "$1" in
  skills)            printf 'claude/skills/vstack-fixture-skill/SKILL.md' ;;
  agents)            printf 'claude/agents/vstack-fixture-agent.md' ;;
  agent_references)  printf 'claude/agents/reference/VSTACK-FIXTURE.ref' ;;
  commands)          printf 'claude/commands/vstack-fixture-command.md' ;;
  hooks)             printf 'claude/hooks/vstack-fixture-hook.sh' ;;
  wrappers)          printf 'bin/vstack-fixture-wrapper' ;;
  mcp_servers)       printf 'mcp/servers.json' ;;
esac; }
# The token every consumer's output is grepped for. Distinct from plant_path's basename only for
# mcp_servers, whose plant is a key inside an existing file rather than a file of its own.
plant_name(){ case "$1" in
  skills)            printf 'vstack-fixture-skill' ;;
  agents)            printf 'vstack-fixture-agent' ;;
  agent_references)  printf 'VSTACK-FIXTURE.ref' ;;
  commands)          printf 'vstack-fixture-command' ;;
  hooks)             printf 'vstack-fixture-hook.sh' ;;
  wrappers)          printf 'vstack-fixture-wrapper' ;;
  mcp_servers)       printf 'vstack-fixture-server' ;;
esac; }
# Where install.sh/overlay.sh would place it, relative to $CDIR (or $HOME for wrappers).
installed_relpath(){ case "$1" in
  skills)            printf 'skills/vstack-fixture-skill' ;;
  agents)            printf 'agents/vstack-fixture-agent.md' ;;
  agent_references)  printf 'agents/reference/VSTACK-FIXTURE.ref' ;;
  commands)          printf 'commands/vstack-fixture-command.md' ;;
  hooks)             printf 'hooks/vstack-fixture-hook.sh' ;;
  wrappers)          printf 'vstack-fixture-wrapper' ;;   # under $HOME/.config/agents/bin/
  mcp_servers)       printf '' ;;                          # not a per-file install at all
esac; }

do_plant(){ # family
  fam="$1"; p=$(plant_path "$fam")
  # cg_save writes its sidecar files (.cg-orig, .cg-orighash, .cg-lasthash) next to $p even
  # when $p does not exist yet -- that still requires $p's *directory* to exist. skills is
  # the one family whose plant directory (claude/skills/vstack-fixture-skill/) does not exist
  # until this harness creates it, so the mkdir has to happen before cg_save, not after --
  # found by running this for real: cg_save failed "No such file or directory" on all three
  # sidecars the first time this ran.
  mkdir -p "$(dirname "$p")"
  cg_save "$p"
  case "$fam" in
    skills)
      cat > "$p" <<'EOF'
---
name: vstack-fixture-skill
description: Fixture skill planted by tests/inventory-fixture.sh to prove the inventory consumers notice a new skill. Never install this for real; delete if found outside that harness's run window.
---

# vstack-fixture-skill

Planted by tests/inventory-fixture.sh.
EOF
      ;;
    agents)
      cat > "$p" <<'EOF'
---
name: vstack-fixture-agent
description: Fixture agent planted by tests/inventory-fixture.sh to prove the inventory consumers notice a new agent. Never dispatch this for real; delete if found outside that harness's run window.
tools: Read
model: sonnet
---

Planted by tests/inventory-fixture.sh.
EOF
      ;;
    agent_references)
      mkdir -p "$(dirname "$p")"
      printf 'Fixture reference file planted by tests/inventory-fixture.sh. Not real agent reference material -- delete if found outside that harness'"'"'s run window.\n' > "$p"
      ;;
    commands)
      cat > "$p" <<'EOF'
---
description: Fixture command planted by tests/inventory-fixture.sh to prove the inventory consumers notice a new command. Never run this for real.
---

Planted by tests/inventory-fixture.sh.
EOF
      ;;
    hooks)
      cat > "$p" <<'EOF'
#!/usr/bin/env bash
# Fixture hook planted by tests/inventory-fixture.sh to prove the inventory consumers notice a
# new hook script. Deliberately unwired -- not referenced in claude/hooks/hooks.json or
# install.sh's hook rebuild. Never install this for real; delete if found outside that harness's
# run window.
exit 0
EOF
      chmod 755 "$p"
      ;;
    wrappers)
      cat > "$p" <<'EOF'
#!/usr/bin/env bash
# Fixture wrapper planted by tests/inventory-fixture.sh to prove the inventory consumers notice a
# new CLI wrapper. Never install this for real; delete if found outside that harness's run window.
exit 0
EOF
      chmod 755 "$p"
      ;;
    mcp_servers)
      tmp="$p.fixture-tmp"
      jq --indent 2 '. + {"vstack-fixture-server": {"type":"stdio","command":"true","args":[]}}' "$p" > "$tmp" \
        && mv "$tmp" "$p"
      ;;
  esac
  cg_checkpoint "$p"
}
do_unplant(){ # family
  local pp
  pp=$(plant_path "$1")
  cg_restore "$pp"
  # cg_restore only ever un-writes the FILE do_plant wrote -- it has no opinion on the directory
  # do_plant's own `mkdir -p` created around it. git does not track empty directories, so a
  # directory left behind this way is invisible to `git status --porcelain` (the harness's own
  # final self-check passed with exactly this leak sitting in the tree) while still being a real,
  # on-disk directory that a filesystem-globbing consumer sees -- found by running this for real:
  # tests/plugin-manifests.sh's "every claude/skills/*/ directory carries a SKILL.md" check
  # failed on the orphaned claude/skills/vstack-fixture-skill/ after a full sweep reported clean.
  # `rmdir` only ever removes a directory that is actually empty, so this is safe to run
  # unconditionally for every family: claude/commands, claude/hooks, claude/agents/reference and
  # bin/ all have other files in them already and rmdir silently no-ops on all four.
  #
  # Why this matters beyond skills' own row: before this fix, one run of this file (log timestamp
  # 22:18, the run this repo's history calls "run #2") left the orphaned skills directory behind
  # after the skills family's own window closed, and every family iteration AFTER skills in that
  # same run shared this one live tree -- so plugin-manifests.sh's "every claude/skills/*/
  # directory carries a SKILL.md" check kept failing on that leftover for the rest of the run,
  # regardless of which family was actually under test at the time. Reproduced in isolation with
  # no other plant present: `mkdir -p claude/skills/vstack-fixture-skill && ./tests/
  # plugin-manifests.sh` fails the same two checks every time (`loader vs disk: > vstack-fixture-
  # skill`, `missing SKILL.md in: claude/skills/vstack-fixture-skill/`), confirming the six
  # exit=1s that run recorded for agents/agent_references/commands/hooks/wrappers/mcp_servers were
  # this leak, not those families' own plants -- their own FAIL text never named their own token,
  # which is exactly why the predicate at plugin-manifests.sh's call site (below) correctly did
  # not call it "noticed" for those families. It was mis-labeled STALE, not mis-labeled noticed;
  # see unknown() for why that distinction gets its own state now, and rmdir above for the fix
  # that makes the leak (and therefore the whole question) stop recurring.
  #
  # This `rmdir` is the fix for THIS family's specific leak; PRE_STATUS/POST_STATUS at the top
  # and bottom of this file now use tree_fingerprint() (tests/lib-collision-guard.sh), which
  # includes the empty-directory set, as the general backstop -- if a future family or a future
  # edit reintroduces a leaked empty directory anywhere in the tree, the final tree-unchanged
  # check fails loudly naming it, instead of the silent six-family poisoning this comment
  # documents happening once already.
  rmdir "$(dirname "$pp")" 2>/dev/null || true
}

# shellcheck disable=SC2046  # intentional word-splitting: one plant path per positional arg, none contain spaces
cg_install_trap $(for f in $FAMILIES; do plant_path "$f"; echo; done)

# --- shared scratch installs, built once and reused across every family iteration --------------
SCRATCH_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/vstack-inventory-fixture.XXXXXX")
trap 'rm -rf "$SCRATCH_ROOT"' EXIT INT TERM HUP

echo "== positive control: every consumer, no plant =========================================="
BASE_HOME="$SCRATCH_ROOT/base"
mkdir -p "$BASE_HOME"
HOME="$BASE_HOME" ./install.sh >/tmp/inventory-fixture-base-install.log 2>&1
base_install_rc=$?
[ "$base_install_rc" -eq 0 ] && ok "positive control: install.sh into a clean scratch HOME" \
  || bad "positive control: install.sh into a clean scratch HOME" "exit=$base_install_rc; see /tmp/inventory-fixture-base-install.log"

base_drift_out=$(HOME="$BASE_HOME" ./bin/doctor --drift 2>&1); base_drift_rc=$?
BASE_COMPARED=$(printf '%s\n' "$base_drift_out" | grep -oE '[0-9]+ item\(s\) compared' | grep -oE '[0-9]+' | head -1)
[ "$base_drift_rc" -eq 0 ] && [ -n "$BASE_COMPARED" ] \
  && ok "positive control: bin/doctor --drift (no drift, $BASE_COMPARED items compared)" \
  || bad "positive control: bin/doctor --drift" "exit=$base_drift_rc$(printf '\n%s' "$base_drift_out" | tail -5)"

# payload_digest is a pre-existing, named, out-of-scope red: claude/inventory.json's
# derived_at.payload_digest goes stale on every commit anyone makes to this tree, and per this
# harness's own instructions it is recomputed LAST, after Step B lands, not by this file. A
# "positive control: all green" claim that silently swallowed *any* nonzero exit here would hide
# a real regression behind that known exception; one that hard-required exit=0 would be a false
# baseline failure on every run until the digest is recomputed. Assert the narrower, true claim
# instead: the only FAIL line(s) present are the ones payload_digest is already known to cause.
base_inv_out=$(./tests/inventory-contract.sh 2>&1); base_inv_rc=$?
base_inv_other_fails=$(printf '%s\n' "$base_inv_out" | grep '^FAIL' | grep -v payload_digest)
if [ -z "$base_inv_other_fails" ]; then
  ok "positive control: tests/inventory-contract.sh (clean except the known-stale payload_digest)"
else
  bad "positive control: tests/inventory-contract.sh" "unexpected FAIL(s) beyond payload_digest: $base_inv_other_fails"
fi

base_verify_out=$(HOME="$(mktemp -d)" bash .claude/verify.sh 2>&1)
base_verify_fails=$(printf '%s\n' "$base_verify_out" | grep -c '^FAIL')
# The SET of FAIL labels, not just how many -- a count that matches before and after can still
# hide one label leaving and a different one arriving in its place, which is exactly what
# happened here: a count-only positive control read "unchanged" over a real regression (an
# orphaned empty directory do_unplant left behind -- see do_unplant's own comment) because the
# stale-digest FAIL happened to be replaced by two different FAILs at the same total. sort makes
# `comm` below meaningful; the post-run comparison names precisely what was added and removed.
base_verify_labels=$(printf '%s\n' "$base_verify_out" | grep '^FAIL' | sort)
base_verify_other_fails=$(printf '%s\n' "$base_verify_out" | grep '^FAIL' | grep -v 'payload_digest\|inventory contract matches the tree')
if [ -z "$base_verify_other_fails" ]; then
  ok "positive control: .claude/verify.sh ($base_verify_fails FAIL line(s), all attributable to the known-stale payload_digest)"
else
  bad "positive control: .claude/verify.sh" "unexpected FAIL(s) beyond payload_digest: $base_verify_other_fails"
fi

echo
echo "== per-family plant x consumer matrix ===================================================="

for fam in $FAMILIES; do
  want_fam "$fam" || continue
  p=$(plant_path "$fam")
  name=$(plant_name "$fam")
  rel=$(installed_relpath "$fam")
  echo
  echo "--- $fam (plant: $p, token: $name) ---"

  do_plant "$fam"

  # 1. tests/inventory-contract.sh -- regenerates components.$fam.members from the tree and
  #    diffs against claude/inventory.json's declared list.
  inv_out=$(./tests/inventory-contract.sh 2>&1); inv_rc=$?
  if [ "$inv_rc" -ne 0 ] && printf '%s\n' "$inv_out" | grep -q "on the tree, not in the contract:.*$name"; then
    noticed "inventory-contract.sh" "components.$fam.members: on the tree, not in the contract: ... $name ..."
  else
    stale "inventory-contract.sh" "exit=$inv_rc, no 'on the tree, not in the contract' line naming $name" "$fam" "$name"
  fi

  # verify.sh, once, sliced into checks 48 / 12 / 11 / 31.
  verify_out=$(HOME="$(mktemp -d)" bash .claude/verify.sh 2>&1)
  blk(){ # label [boundary_regex] -> the FAIL/ok line and its detail, up to the boundary.
    # Default boundary is the next top-level check's own ok/FAIL/skip line. Check 48
    # ("inventory contract matches the tree") embeds tests/inventory-contract.sh's *entire*
    # stdout verbatim, which itself contains lines like "ok    contract_version..." and
    # "FAIL  payload_digest" that match that same default pattern -- using it there truncates
    # the block after its first line and hides everything the embedded sub-report actually
    # says. Pass that check's own fixed footer line as the boundary instead.
    local boundary="${2:-^(FAIL|ok|skip)  }"
    printf '%s\n' "$verify_out" | awk -v l="$1" -v b="$boundary" '
      $0 ~ "^(FAIL|ok)  *"l {p=1; print; next}
      p && $0 ~ b {exit}
      p {print}'
  }

  # 2. check 48 -- wraps tests/inventory-contract.sh's own output verbatim, so it fails whenever
  #    row 1 above does, naming the same tree-vs-contract line.
  b48=$(blk 'inventory contract matches the tree' '^inventory-contract: ')
  if printf '%s' "$b48" | grep -q '^FAIL' && printf '%s' "$b48" | grep -q "$name"; then
    noticed "verify.sh check 48" "inventory contract matches the tree: names $name"
  else
    stale "verify.sh check 48" "$(printf '%s' "$b48" | head -1)" "$fam" "$name"
  fi

  # 3. check 12 -- doc counts match tree (lane-aware as of 4307663). Only fires for families
  #    README actually publishes a count for; agent_references has no README row at all, which
  #    is a structural, permanent STALE for this family and this consumer, not a bug in either.
  b12=$(blk 'doc counts match tree')
  if [ "$fam" = agent_references ]; then
    skip_row "verify.sh check 12" "README publishes no 'agent reference(s)' count -- structurally out of scope"
  elif printf '%s' "$b12" | grep -q '^FAIL'; then
    noticed "verify.sh check 12" "doc counts match tree: went red on the family's own count"
  else
    stale "verify.sh check 12" "stayed ok ($(printf '%s' "$b12" | head -1))" "$fam" "$name"
  fi

  # 4. check 11 -- hook wiring. In scope only for the hooks family (an unwired hook script);
  #    every other family is legitimately outside this check's subject.
  b11=$(blk 'hook wiring')
  if [ "$fam" = hooks ]; then
    if printf '%s' "$b11" | grep -q '^FAIL' && printf '%s' "$b11" | grep -q "$name"; then
      noticed "verify.sh check 11" "hook wiring: names $name as unwired in the USER lane"
    else
      stale "verify.sh check 11" "$(printf '%s' "$b11" | head -1)" "$fam" "$name"
    fi
  else
    skip_row "verify.sh check 11" "hook wiring is not this family's subject"
  fi

  # 5. check 31 -- every shipped file has a referrer. In scope for hooks and wrappers (their
  #    paths are not excluded); skills/agents/commands/agent_references are excluded by path
  #    convention (loaded by directory), and mcp_servers plants an existing file, not a new path.
  b31=$(blk 'every shipped file has a referrer')
  case "$fam" in
    hooks|wrappers)
      if printf '%s' "$b31" | grep -q '^FAIL' && printf '%s' "$b31" | grep -q "$p"; then
        noticed "verify.sh check 31" "every shipped file has a referrer: names $p"
      else
        # In scope by path, but the check iterates `git ls-files`, not the filesystem -- an
        # untracked plant of ANY family is invisible to it regardless of path convention. Say
        # that mechanism, not just the passing headline, so this doesn't read as "check 31
        # inspected this file and judged it fine."
        stale "verify.sh check 31" "$(printf '%s' "$b31" | head -1) -- untracked, so git ls-files never lists it" "$fam" "$name"
      fi
      ;;
    *)
      skip_row "verify.sh check 31" "excluded by path convention or not a new path"
      ;;
  esac

  # 6. bin/doctor --drift, against the BASE_HOME install taken before any plant existed.
  drift_out=$(HOME="$BASE_HOME" ./bin/doctor --drift 2>&1); drift_rc=$?
  drift_compared=$(printf '%s\n' "$drift_out" | grep -oE '[0-9]+ item\(s\) compared' | grep -oE '[0-9]+' | head -1)
  if [ "$fam" = mcp_servers ]; then
    if [ "$drift_rc" -eq 0 ] && [ "$drift_compared" = "$BASE_COMPARED" ]; then
      stale "bin/doctor --drift" "exit=0, compared=$drift_compared (identical to the no-plant baseline of $BASE_COMPARED) -- run_drift() never reads mcp/servers.json" "$fam" "$name"
    else
      unknown "bin/doctor --drift" "exit=$drift_rc compared=$drift_compared -- does not match the STALE prediction for mcp_servers, attribute by hand" "$fam" "$name"
    fi
  else
    # A drift-found run prints only the missing/differs lines plus "DRIFT (word)", no
    # item(s)-compared count at all (that phrase is emitted only on the no-drift path) --
    # so the notice here is the missing line itself, not a count comparison.
    if [ "$drift_rc" -ne 0 ] && printf '%s\n' "$drift_out" | grep -q "missing.*$rel"; then
      noticed "bin/doctor --drift" "$(printf '%s\n' "$drift_out" | grep "missing.*$rel" | head -1) (baseline was $BASE_COMPARED item(s) compared, no drift)"
    else
      stale "bin/doctor --drift" "exit=$drift_rc, no 'missing $rel' line ($(printf '%s' "$drift_out" | tail -2 | tr '\n' ' '))" "$fam" "$name"
    fi
  fi

  # 7. tests/install-matrix.sh default -- installs from THIS tree into a throwaway HOME and
  #    asserts counts it also derives from THIS tree in the same call, so a family that grows
  #    correctly on both sides of that comparison can never produce a mismatch. Run for real
  #    rather than assumed, because that is exactly the kind of claim this file exists to check
  #    empirically rather than take on trust.
  im_out=$(./tests/install-matrix.sh default 2>&1); im_rc=$?
  if [ "$im_rc" -ne 0 ] && printf '%s\n' "$im_out" | grep -qi "$name"; then
    noticed "install-matrix.sh default" "$(printf '%s\n' "$im_out" | grep -i "$name" | head -1)"
  elif [ "$im_rc" -eq 0 ]; then
    stale "install-matrix.sh default" "exit=0, ok -- counts are derived from this same tree on both sides of every comparison" "$fam" "$name"
  else
    unknown "install-matrix.sh default" "exit=$im_rc, FAIL line(s): $(printf '%s\n' "$im_out" | grep -i 'FAIL' | tr '\n' ';')" "$fam" "$name"
  fi

  # 8. tests/plugin-manifests.sh -- checks 3-4 diff `claude plugin details`'s loader inventory
  #    against a filesystem glob, both pointed at THIS tree (:156 opens with `--plugin-dir
  #    "$REPO/claude"`, :161-169 globs the same claude/). That is not the same shape as row 7:
  #    row 7's counts are a completeness assertion undermined by reading both sides off one
  #    glob; checks 3-4 are a CONSISTENCY assertion -- do the loader and the disk agree? -- for
  #    which reading both sides off the same tree is the design, not a gap. A plant this harness
  #    adds is valid to both readers (a real SKILL.md, a real agent file, ...), so it is present
  #    on both sides identically and cannot produce a diff, structurally, the same way an
  #    untracked file cannot appear in `git ls-files` for check 31 below: the check is doing its
  #    job and finding no disagreement, not failing to notice growth it was never asked to count.
  #    Does not check hooks/wrappers/mcp_servers/agent_references counts at all -- only whether
  #    wired hooks.json references resolve, which an unwired plant never touches.
  if command -v claude >/dev/null 2>&1; then
    pm_out=$(./tests/plugin-manifests.sh 2>&1); pm_rc=$?
    if [ "$pm_rc" -ne 0 ] && printf '%s\n' "$pm_out" | grep -q "$name"; then
      noticed "plugin-manifests.sh" "$(printf '%s\n' "$pm_out" | grep "$name" | head -1)"
    elif [ "$pm_rc" -eq 0 ]; then
      stale "plugin-manifests.sh" "exit=0 -- checks 3-4 measure loader/disk AGREEMENT, not completeness; a plant valid to both readers matches on both sides by construction and can never produce a diff (not a coverage gap -- same category as check 31's untracked-plant blindness below)" "$fam" "$name"
    else
      unknown "plugin-manifests.sh" "exit=$pm_rc, FAIL line(s): $(printf '%s\n' "$pm_out" | grep '^FAIL' | tr '\n' ';')" "$fam" "$name"
    fi
  else
    skip_row "plugin-manifests.sh" "claude CLI not installed"
  fi

  # 9. overlay.sh into a scratch dest -- not a verifier, a copier. The finding here is presence,
  #    not a printed verdict: does the plant land where profiles.overlay.ships says it should
  #    (or correctly NOT land, for wrappers/mcp_servers, which that lane never ships)?
  ov_dest="$SCRATCH_ROOT/overlay-$fam"
  mkdir -p "$ov_dest" && git -C "$ov_dest" init -q 2>/dev/null
  ov_out=$(./overlay.sh "$ov_dest" 2>&1); ov_rc=$?
  ov_diag="rc=$ov_rc"; [ "$ov_rc" -ne 0 ] && ov_diag="$ov_diag output=$ov_out"
  ships_overlay=$(jq -r --arg f "$fam" '.profiles.overlay.ships | index($f) != null' claude/inventory.json 2>/dev/null)
  case "$fam" in
    mcp_servers) ov_target="" ;;                          # overlay never merges MCP servers
    *)           ov_target="$ov_dest/.claude/$rel" ;;
  esac
  if [ "$ships_overlay" = "true" ]; then
    if [ -n "$ov_target" ] && [ -e "$ov_target" ]; then
      noticed "overlay.sh" "$ov_target present (ships: $fam)"
    else
      bad "overlay.sh should have shipped $fam but did not" "target=$ov_target $ov_diag"
    fi
  else
    if [ -z "$ov_target" ] || [ ! -e "$ov_target" ]; then
      noticed "overlay.sh" "correctly absent -- profiles.overlay.does_not_ship names $fam"
    else
      bad "overlay.sh shipped $fam, which profiles.overlay.does_not_ship names" "target=$ov_target $ov_diag"
    fi
  fi

  # 10. uninstall.sh --dry-run -- requires an install that actually contains the plant (its plan
  #     only names a path that is both owned AND present at the installed destination), so this
  #     installs fresh into its own scratch HOME with the plant live, then asks for the plan.
  un_home="$SCRATCH_ROOT/uninst-$fam"
  mkdir -p "$un_home"
  HOME="$un_home" ./install.sh >/dev/null 2>&1
  un_out=$(HOME="$un_home" ./uninstall.sh --dry-run 2>&1)
  un_cdir="$un_home/.claude"
  case "$fam" in
    wrappers) un_installed="$un_home/.config/agents/bin/$name" ;;
    *)        un_installed="$un_cdir/$rel" ;;
  esac
  if [ "$fam" = mcp_servers ]; then
    if ! printf '%s\n' "$un_out" | grep -q "$name"; then
      stale "uninstall.sh --dry-run" "plan never mentions $name -- settings.json/.claude.json merges are deliberately outside plan_file_removal's scope" "$fam" "$name"
    else
      noticed "uninstall.sh --dry-run" "unexpectedly present -- re-check the STALE prediction for mcp_servers"
    fi
  else
    if [ -e "$un_installed" ] && printf '%s\n' "$un_out" | grep -q "remove.*$un_installed"; then
      noticed "uninstall.sh --dry-run" "plan: remove $un_installed"
    else
      stale "uninstall.sh --dry-run" "installed=$([ -e "$un_installed" ] && echo yes || echo no), plan does not name $un_installed" "$fam" "$name"
    fi
  fi
  rm -rf "$un_home"

  do_unplant "$fam"
done

echo
echo "== positive control, again: every consumer, plant removed ================================"
./tests/inventory-contract.sh >/dev/null 2>&1; post_inv_rc=$?
[ "$post_inv_rc" -eq "$base_inv_rc" ] && ok "positive control (post): tests/inventory-contract.sh matches the pre-run result" \
  || bad "positive control (post): tests/inventory-contract.sh" "exit=$post_inv_rc, was $base_inv_rc"

post_verify_out=$(HOME="$(mktemp -d)" bash .claude/verify.sh 2>&1)
post_verify_fails=$(printf '%s\n' "$post_verify_out" | grep -c '^FAIL')
post_verify_labels=$(printf '%s\n' "$post_verify_out" | grep '^FAIL' | sort)
# comm needs sorted input on both sides (both are, via `sort` above) -- -13 is lines only in
# the post set (added), -23 is lines only in the base set (removed). A count match with a
# non-empty added/removed set here is precisely the bug this replaced: two different labels
# swapping in for each other at an unchanged total.
verify_added=$(comm -13 <(printf '%s\n' "$base_verify_labels") <(printf '%s\n' "$post_verify_labels"))
verify_removed=$(comm -23 <(printf '%s\n' "$base_verify_labels") <(printf '%s\n' "$post_verify_labels"))
if [ -z "$verify_added" ] && [ -z "$verify_removed" ]; then
  ok "positive control (post): .claude/verify.sh FAIL set matches the pre-run result ($post_verify_fails FAIL line(s))"
else
  bad "positive control (post): .claude/verify.sh" \
    "$(printf 'FAIL set changed (%s -> %s).\n      added:   %s\n      removed: %s' \
       "$base_verify_fails" "$post_verify_fails" "${verify_added:-(none)}" "${verify_removed:-(none)}")"
fi

echo
if [ -n "$STALE_LINES" ]; then
  echo "== STALE CONSUMER / UNKNOWN findings ======================================================"
  printf '%s\n' "$STALE_LINES" | grep -v '^$'
fi

echo
echo "== tree unchanged =========================================================================="
POST_STATUS=$(tree_fingerprint .)
if [ "$PRE_STATUS" = "$POST_STATUS" ]; then
  ok "tree unchanged from before this run (porcelain + empty directories)"
else
  bad "tree changed" "$(diff <(printf '%s' "$PRE_STATUS") <(printf '%s' "$POST_STATUS"))"
fi

echo
printf 'inventory-fixture: %d ok, %d FAIL, %d STALE CONSUMER finding(s), %d UNKNOWN finding(s)\n' "$PASS" "$FAIL" "$STALE" "$UNKNOWN"
release_lock
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
