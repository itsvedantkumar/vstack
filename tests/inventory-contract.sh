#!/usr/bin/env bash
# inventory-contract.sh — regenerate every derived field in claude/inventory.json straight from
# the tree and diff against what the file claims.
#
# claude/inventory.json documents itself as a CHECK-TIME ORACLE ONLY: nothing shipped reads it at
# runtime, install.sh keeps deriving what it does from the filesystem the same way it always did.
# The only reason this file earns its place is that something independent regenerates the same
# lists and diffs -- if install.sh ever read this file instead of deriving, "does the inventory
# match what installs?" would answer itself. This script is the independent half.
#
# Not yet wired into .claude/verify.sh or CI (see tests/README.md). Run by hand:
#   tests/inventory-contract.sh
#
# `--write` (alias `--repoint`) is the ONLY supported way to re-point derived_at.head and
# derived_at.payload_digest at HEAD after a payload commit. It refuses on a dirty payload tree,
# reuses payload_digest_compute() below rather than a second implementation, writes the file with
# jq (stable key order, same 2-space indent already on disk), re-validates, and on a clean result
# prints the commit command to run:
#   tests/inventory-contract.sh --write
set -u
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

INV="claude/inventory.json"
FAIL=0
RAN=0

fail(){ printf 'FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2"; FAIL=1; RAN=$((RAN+1)); }
pass(){ printf 'ok    %s\n' "$1"; RAN=$((RAN+1)); }
# A skip is a named result, never folded into RAN. Counting a skip as a check that ran is how a
# suite reports coverage it does not have; the footer prints both numbers so the two cannot be
# confused by a reader who only sees the last line.
SKIPPED=0
skipc(){ printf 'skip  %s (%s)\n' "$1" "$2"; SKIPPED=$((SKIPPED+1)); }

PAYLOAD_PATHS='claude/ mcp/ bin/ shell/ conductor/ install.sh uninstall.sh overlay.sh bootstrap.sh setup-machine.sh :(exclude)claude/inventory.json'

# macOS ships `shasum` and no `sha256sum`; BusyBox and most slim Linux images ship `sha256sum`
# and no `shasum`. This file used bare `shasum` and produced an EMPTY digest on Alpine -- the
# comparison then read "the tree's is ." and the contract failed for a reason that had nothing
# to do with the tree. A missing tool must refuse, not return the empty string: an empty digest
# compared against an empty expectation would have passed while measuring nothing at all, and
# that shape is the entire subject of docs/checks-that-inherit-their-answer.md.
sha256_of(){ # reads stdin -> hex digest, or dies naming what is missing
  if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 | cut -d' ' -f1
  else
    echo "inventory-contract: neither sha256sum nor shasum is on PATH; refusing to emit an empty digest" >&2
    exit 3
  fi
}

payload_digest_compute(){
  # -c -o --exclude-standard: tracked entries AND untracked-but-not-ignored files, so a new hook
  # dropped into claude/hooks/ counts as payload movement. A tracked file deleted from the working
  # tree still appears in the -c list and hashes as `absent`, which is how a deletion registers.
  # NUL-delimited throughout: no quoting, no filename that can split a field.
  #
  # --exclude-standard means .gitignore'd files inside the payload directories are NOT hashed.
  # That is deliberate: a stray .DS_Store or *.log would otherwise make the digest differ on every
  # developer's machine. The cost is real and stated here rather than left to be discovered --
  # install.sh copies directories, so an ignored file sitting in one does reach the installed tree
  # without this digest ever seeing it.
  # shellcheck disable=SC2086
  git ls-files -z -co --exclude-standard -- $PAYLOAD_PATHS \
    | LC_ALL=C sort -z -u \
    | while IFS= read -r -d '' f; do
        if [ -L "$f" ]; then
          printf 'symlink %s -> %s\n' "$f" "$(readlink "$f")"
        elif [ -f "$f" ]; then
          printf '%s %s %s\n' "$(sha256_of < "$f")" \
                               "$([ -x "$f" ] && printf 'x' || printf -- '-')" "$f"
        elif [ -d "$f" ]; then
          # A path that is a directory in a file listing is a gitlink (submodule). There are none
          # here today; without this arm a future one would hash as `absent` forever and every
          # bump inside it would be invisible. The recorded commit is the content.
          printf 'gitlink %s %s\n' "$(git ls-files -s -- "$f" | awk '{print $2}')" "$f"
        else
          printf 'absent - %s\n' "$f"
        fi
      done \
    | sha256_of
}

# `tests/inventory-contract.sh --print-digest` is the ONLY supported way to recompute the value
# that goes into the file. Anyone typing the recipe by hand into a shell is running a second
# implementation, which is how the old one drifted from what it claimed to measure.
if [ "${1:-}" = "--print-digest" ]; then payload_digest_compute; exit 0; fi

command -v jq >/dev/null 2>&1 || { echo "FAIL  jq is required to validate $INV" >&2; exit 1; }
[ -f "$INV" ] || { echo "FAIL  $INV not found" >&2; exit 1; }
jq empty "$INV" >/dev/null 2>&1 || { echo "FAIL  $INV does not parse as JSON" >&2; exit 1; }

# --- --write / --repoint ---------------------------------------------------------------------
# The two-step dance every stale-inventory failure below actually asks for: recompute
# payload_digest with the one blessed implementation (payload_digest_compute(), never a hand-typed
# recipe), set derived_at.head to the commit that recipe just ran against, write both fields back
# with jq so key order and indent survive untouched, then re-run the validation this same script
# does on every other invocation so `--write` cannot itself ship a stale file.
#
# Refuses on a dirty payload tree rather than repointing at a HEAD the digest was not actually
# computed from: derived_at.head names the commit payload_digest describes, and a payload file
# with uncommitted changes means HEAD is not that commit yet -- committing first is the only way
# to make the claim true, not something this flag can paper over.
# `needs_repoint` mirrors the contract's own definition of stale for these two fields ONLY well
# enough to answer "is there anything to fix" -- it is not a second implementation of the digest
# (payload_digest_compute() is still the only place that runs) and it does not replace the real
# checks below, which still run afterward and print the authoritative pass/fail lines. Without
# this, --write would rewrite derived_at.head to current HEAD on every call, even one made right
# after an unrelated non-payload commit where the file already validates clean -- which is not a
# fix, it is churn, and it breaks the "second --write on a clean tree changes nothing" contract.
needs_repoint(){
  [ "$(payload_digest_compute)" != "$(jq -r '.derived_at.payload_digest' "$INV")" ] && return 0
  h=$(jq -r '.derived_at.head // empty' "$INV")
  [ -z "$h" ] && return 0
  printf '%s' "$h" | grep -qE '^[0-9a-f]{40}$' || return 0
  # Absent from a shallow checkout: the real check below SKIPs rather than fails this case, so
  # --write must not force a rewrite it cannot justify either.
  git cat-file -e "$h^{commit}" 2>/dev/null || return 1
  git merge-base --is-ancestor "$h" HEAD 2>/dev/null || return 0
  # shellcheck disable=SC2086
  [ -n "$(git diff --name-only "$h" HEAD -- $PAYLOAD_PATHS 2>/dev/null)" ] && return 0
  return 1
}

WRITE_MODE=0
WROTE=0
if [ "${1:-}" = "--write" ] || [ "${1:-}" = "--repoint" ]; then
  WRITE_MODE=1
  # shellcheck disable=SC2086
  dirty=$(git status --porcelain -- $PAYLOAD_PATHS)
  if [ -n "$dirty" ]; then
    echo "FAIL  inventory-contract --write: the payload has uncommitted changes:" >&2
    printf '%s\n' "$dirty" >&2
    echo "commit the payload first, the head must name a commit" >&2
    exit 2
  fi
  if needs_repoint; then
    write_head=$(git rev-parse HEAD)
    write_digest=$(payload_digest_compute)
    write_tmp=$(mktemp "${INV}.XXXXXX") || { echo "FAIL  inventory-contract --write: mktemp failed" >&2; exit 1; }
    if ! jq --arg h "$write_head" --arg d "$write_digest" \
          '.derived_at.head = $h | .derived_at.payload_digest = $d' \
          "$INV" > "$write_tmp"; then
      echo "FAIL  inventory-contract --write: jq failed to write $INV" >&2
      rm -f "$write_tmp"
      exit 1
    fi
    mv "$write_tmp" "$INV"
    WROTE=1
    echo "inventory-contract --write: derived_at.head -> $write_head, derived_at.payload_digest -> $write_digest"
  else
    echo "inventory-contract --write: derived_at.head and derived_at.payload_digest already satisfy the contract; nothing to do"
  fi
  echo
fi

# --- contract_version: the hand-bumped SCHEMA version. An unknown value must fail loudly -- a
# validator that silently accepts a schema it does not understand is worse than no validator,
# because everything below reads fields whose meaning may have changed out from under it.
SUPPORTED_CONTRACT_VERSIONS=" 1 "
cv=$(jq -r '.contract_version' "$INV")
case "$SUPPORTED_CONTRACT_VERSIONS" in
  (*" $cv "*) pass "contract_version $cv recognised" ;;
  (*) fail "contract_version" "claude/inventory.json declares contract_version $cv, which this validator does not recognise (known:$SUPPORTED_CONTRACT_VERSIONS). The schema may have changed under it -- update tests/inventory-contract.sh before trusting anything else in this file, do not proceed past this line." ;;
esac

# --- payload digest -----------------------------------------------------------------------------
# This block used to `eval` the recipe string out of claude/inventory.json, on the stated reasoning
# that "the recipe this script runs and the recipe the file claims can never drift apart". That is
# the defect, not the safeguard: it made the artifact its own oracle. Editing digest_recipe and
# payload_digest together passed the check while measuring nothing, and eval'ing a string out of
# the file under test is arbitrary code execution from the artifact. The recipe now lives here, in
# the independent half, and the file merely names where it lives.
#
# The old recipe was also content-blind. It hashed `git ls-files -s` (INDEX blob ids) plus
# `git status --porcelain` (status letters and paths, never bytes), so two different unstaged
# edits to the same file produced the same digest, and so did two different untracked payload
# files at the same path. Both confirmed by running it. This one hashes the working-tree bytes.
#
# claude/inventory.json's own path is excluded on purpose (derived_at.self_reference_note): the
# file lives inside claude/, which this scans, so without the exclusion the digest could never
# match itself -- writing the file changes its own bytes, which changes the digest it is trying to
# record, a fixed point editing the file cannot reach.

computed_digest=$(payload_digest_compute)
stated_digest=$(jq -r '.derived_at.payload_digest' "$INV")
if [ "$computed_digest" = "$stated_digest" ]; then
  pass "payload_digest matches the tree ($computed_digest)"
else
  fail "payload_digest" "claude/inventory.json's derived_at.payload_digest is $stated_digest; the tree's is $computed_digest. The snapshot is stale. run: tests/inventory-contract.sh --write"
fi

# The file no longer carries an executable recipe, so nothing here can be tricked into running
# it. What it carries instead is a pointer, and a pointer nobody checks is how prose goes stale:
# derived_at.digest_recipe_source must name a function this script actually defines.
recipe_src=$(jq -r '.derived_at.digest_recipe_source // empty' "$INV")
if [ -z "$recipe_src" ]; then
  fail "digest_recipe_source" "claude/inventory.json does not say where payload_digest's recipe lives; a digest with no named implementation cannot be reproduced"
elif jq -e '.derived_at | has("digest_recipe")' "$INV" >/dev/null 2>&1; then
  fail "digest_recipe_source" "claude/inventory.json still carries an executable derived_at.digest_recipe. That field was the oracle supplying its own recipe; it must not come back"
else
  _rs_file=${recipe_src%%:*}
  _rs_fn=${recipe_src#*:}
  _rs_fn=${_rs_fn%%(*}
  if [ ! -f "$_rs_file" ]; then
    fail "digest_recipe_source" "digest_recipe_source names $_rs_file, which does not exist"
  elif ! grep -q "^${_rs_fn}()" "$_rs_file"; then
    fail "digest_recipe_source" "digest_recipe_source names $_rs_fn in $_rs_file, but no such function is defined there"
  else
    pass "digest_recipe_source names a live implementation ($recipe_src)"
  fi
fi

# --- derived_at.head names a real commit this checkout can see, and one HEAD descends from -----
#
# Until 2026-08-27 nothing validated this field at all: `grep -rn 'derived_at.head' tests/ .claude/`
# returned nothing, so it was a recorded claim with no check behind it -- the shape this whole
# repository exists to find, sitting in the file that describes the repository.
#
# It deliberately does NOT assert equality with HEAD. The field names the commit payload_digest
# was computed FROM, and any commit that writes the field invalidates equality on the spot: the
# same fixed point derived_at.self_reference_note works through for the digest itself. Ancestor-of
# HEAD is the strongest assertion that is true by construction -- it still catches a fabricated
# hash, a commit from an unrelated branch, and a value that was never updated across a rebase.
stated_head=$(jq -r '.derived_at.head // empty' "$INV")
if [ -z "$stated_head" ]; then
  fail "derived_at.head" "claude/inventory.json has no derived_at.head; there is no provenance for payload_digest"
elif ! printf '%s' "$stated_head" | grep -qE '^[0-9a-f]{40}$'; then
  fail "derived_at.head" "derived_at.head is '$stated_head', which is not a 40-character commit hash"
elif ! git cat-file -e "$stated_head^{commit}" 2>/dev/null; then
  # Absent, not wrong. A shallow clone has no history to check against, and calling that a pass
  # would be the tagless-checkout defect check 24 already learned once.
  skipc "derived_at.head" "$stated_head is not present in this checkout (shallow clone?), so its ancestry cannot be checked"
elif git merge-base --is-ancestor "$stated_head" HEAD 2>/dev/null; then
  # Ancestry is necessary and not sufficient. head claims the digest above was computed FROM that
  # commit, so if any payload file changed between it and HEAD, the claim is false however
  # ancestral the commit is: recomputing the digest at head would give a different answer. That
  # shipped here on 2026-08-31 -- head named a commit taken BEFORE the payload edit whose bytes
  # the recorded digest describes, and the ancestry test passed it without complaint.
  #
  # This does not recompute the digest at that commit, and cannot: the recipe hashes
  # untracked-but-not-ignored files too, which do not exist in a commit. It asserts the weaker
  # thing that is actually checkable, and which is false in exactly the case above.
  _hd_moved=$(git diff --name-only "$stated_head" HEAD -- $PAYLOAD_PATHS 2>/dev/null)
  if [ -n "$_hd_moved" ]; then
    fail "derived_at.head" "derived_at.head is $(printf '%.12s' "$stated_head") and is an ancestor of HEAD, but payload has changed since it: $(printf '%s' "$_hd_moved" | tr '\n' ' ') -- so payload_digest was not computed from that commit, whatever this field says. Re-point head at the commit whose payload the digest describes. run: tests/inventory-contract.sh --write"
  else
    pass "derived_at.head is an ancestor of HEAD with no payload change since ($(printf '%.12s' "$stated_head"), $(git rev-list --count "$stated_head..HEAD" 2>/dev/null) commit(s) ago)"
  fi
else
  fail "derived_at.head" "derived_at.head is $stated_head, which exists but is NOT an ancestor of HEAD -- the snapshot was taken on a commit this branch does not descend from"
fi

# --- every list: regenerate with the exact command the file's own regeneration.derivations
# block names for it, and diff against the declared member list. Neither side is hand-written:
# the LEFT side runs a command the file states about itself, the RIGHT side is read back from
# the file. Agreement is the only thing that makes either trustworthy.
check_list(){ # label, jq path to the declared array, regeneration.derivations key
  label="$1"; target="$2"; key="$3"
  cmd=$(jq -r --arg k "$key" '.regeneration.derivations[$k] // empty' "$INV")
  if [ -z "$cmd" ]; then
    fail "$label" "claude/inventory.json's regeneration.derivations has no entry named '$key' -- nothing to regenerate against"
    return
  fi
  # sort -u, not sort: every one of these is a SET of names (skill/agent/hook basenames, CI
  # runner labels, settings keys...). ci_runners in particular derives from one grep line per
  # CI job, and two jobs sharing a runner label is not a second, distinct member.
  regen=$(eval "$cmd" 2>/dev/null | sort -u)
  declared=$(jq -r "${target}[]" "$INV" 2>/dev/null | sort -u)
  if [ "$regen" = "$declared" ]; then
    n=$(printf '%s\n' "$regen" | grep -c .)
    pass "$label ($n entries, tree and contract agree)"
    return
  fi
  added=$(comm -23 <(printf '%s\n' "$regen") <(printf '%s\n' "$declared") 2>/dev/null)
  missing=$(comm -13 <(printf '%s\n' "$regen") <(printf '%s\n' "$declared") 2>/dev/null)
  msg="$label: the tree and claude/inventory.json disagree."
  [ -n "$added" ]   && msg="$msg
  on the tree, not in the contract: $(printf '%s' "$added" | tr '\n' ' ')"
  [ -n "$missing" ] && msg="$msg
  in the contract, not on the tree: $(printf '%s' "$missing" | tr '\n' ' ')"
  fail "$label" "$msg"
}

# Driven from `.components | keys[]`, not a hand-maintained list of family names: a family added
# to .components with no matching call here was the defect (see
# docs/checks-that-inherit-their-answer.md) -- a new key in .components must be checked BY
# CONSTRUCTION, not by remembering to also register it in a second, parallel list. check_list
# itself already fails loudly when regeneration.derivations has no entry for the key; looping
# keys[] is what makes it get called at all.
#
# The exclusion is derived, not hand-listed: a component family with no `.members` array (were
# one ever added) is skipped with a named, counted skip -- never a silent `continue` -- because a
# hand-list of "families with no members" is the same defect one layer up.
for _c in $(jq -r '.components | keys[]' "$INV"); do
  if jq -e --arg c "$_c" '.components[$c] | has("members")' "$INV" >/dev/null 2>&1; then
    check_list "components.$_c.members" ".components.$_c.members" "$_c"
  else
    skipc "components.$_c.members" "components.$_c has no .members array to diff against the tree"
  fi
done

check_list "ownership.settings.shipped_keys"     ".ownership.settings.shipped_keys"     "settings_keys"
check_list "ownership.settings.project_scope_keys" ".ownership.settings.project_scope_keys" "project_keys"
check_list "ownership.skill_overrides.keys"      ".ownership.skill_overrides.keys"      "skill_overrides"
check_list "verification.gate.check_ids"         ".verification.gate.check_ids"         "checks"
check_list "platforms.ci_runners"                ".platforms.ci_runners"                "ci_runners"

# falsifiability_rows has no declared member array (tests/gate-falsifiability.sh's CHECKS= line
# is one space-separated string) -- compare the regenerated row COUNT against
# verification.required[id=falsifiability].rows instead.
fr_cmd=$(jq -r '.regeneration.derivations.falsifiability_rows // empty' "$INV")
if [ -n "$fr_cmd" ]; then
  fr_regen_count=$(eval "$fr_cmd" 2>/dev/null | wc -w | tr -d ' ')
  fr_declared_count=$(jq -r '.verification.required[] | select(.id=="falsifiability") | .rows' "$INV")
  if [ "$fr_regen_count" = "$fr_declared_count" ]; then
    pass "falsifiability rows ($fr_regen_count, tree and contract agree)"
  else
    fail "falsifiability rows" "tests/gate-falsifiability.sh's CHECKS= line has $fr_regen_count row ids; claude/inventory.json's verification.required[falsifiability].rows says $fr_declared_count"
  fi
fi

# declared_checks is a count paired with check_ids, a list -- they must not drift from each
# other even before either is compared to the tree.
dc=$(jq -r '.verification.gate.declared_checks' "$INV")
ci=$(jq -r '.verification.gate.check_ids | length' "$INV")
if [ "$dc" = "$ci" ]; then
  pass "declared_checks ($dc) matches check_ids length"
else
  fail "declared_checks vs check_ids" "verification.gate.declared_checks says $dc but check_ids lists $ci entries -- the contract disagrees with itself before it even reaches the tree"
fi

# --- floors: every components.* count must not have fallen below the floor the file states for
# it. This is independent of the diff above -- a floor violation where the CONTRACT was also
# hand-edited down to match would pass the diff and still be a real regression against the
# claim floor_reason names.
for comp in $(jq -r '.components | keys[]' "$INV"); do
  floor=$(jq -r --arg c "$comp" '.components[$c].floor' "$INV")
  cmd=$(jq -r --arg c "$comp" '.regeneration.derivations[$c] // empty' "$INV")
  # A floor that cannot be checked is not a floor: a components.* family with no matching
  # regeneration.derivations entry used to fall through this `continue` with no fail, no skip,
  # and no printed line at all -- the family's stated floor was never compared against the tree.
  if [ -z "$cmd" ]; then
    fail "floor: components.$comp" "claude/inventory.json's regeneration.derivations has no entry named '$comp' -- the stated floor of $floor cannot be checked against the tree"
    continue
  fi
  cnt=$(eval "$cmd" 2>/dev/null | grep -c .)
  if [ "$cnt" -ge "$floor" ] 2>/dev/null; then
    pass "floor: components.$comp ($cnt >= floor $floor)"
  else
    reason=$(jq -r --arg c "$comp" '.components[$c].floor_reason' "$INV")
    fail "floor: components.$comp" "the tree has $cnt, below the stated floor of $floor.
  $reason"
  fi
done

# --- degenerate contract: members must not be empty, and members' own length must agree with
# the count the file declares for it -- both read straight from the file, no tree involved. A
# contract that shipped $count right and $members wrong (or vice versa) is corrupt regardless of
# what the tree says.
for comp in $(jq -r '.components | keys[]' "$INV"); do
  mlen=$(jq -r --arg c "$comp" '.components[$c].members | length' "$INV")
  dcount=$(jq -r --arg c "$comp" '.components[$c].count' "$INV")
  if [ "$mlen" -eq 0 ]; then
    fail "degenerate: components.$comp.members" "components.$comp.members is empty -- a contract with no members and a nonzero count is not a claim, it is a placeholder"
    continue
  fi
  if [ "$mlen" != "$dcount" ]; then
    fail "degenerate: components.$comp.members" "components.$comp.members has $mlen entries but components.$comp.count says $dcount"
    continue
  fi
  pass "degenerate check: components.$comp ($mlen members, count $dcount agree)"
done

echo
if [ "$FAIL" -eq 0 ]; then
  if [ "$SKIPPED" -gt 0 ]; then
    echo "inventory-contract: $RAN checks, $SKIPPED skipped, all clean"
  else
    echo "inventory-contract: $RAN checks, all clean"
  fi
  if [ "$WRITE_MODE" -eq 1 ] && [ "$WROTE" -eq 1 ]; then
    echo
    echo "commit: git commit -am \"Re-point inventory at $(git rev-parse --short HEAD)\""
  fi
  exit 0
else
  echo "inventory-contract: $RAN checks, $SKIPPED skipped, FAILURES ABOVE"
  if [ "$WRITE_MODE" -eq 1 ] && [ "$WROTE" -eq 1 ]; then
    echo "--write updated derived_at.head/payload_digest but validation still fails on the above -- not printing a commit command over a file that is not clean" >&2
  fi
  exit 1
fi
