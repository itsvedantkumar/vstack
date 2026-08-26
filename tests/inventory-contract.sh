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
set -u
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

INV="claude/inventory.json"
FAIL=0
RAN=0

fail(){ printf 'FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2"; FAIL=1; RAN=$((RAN+1)); }
pass(){ printf 'ok    %s\n' "$1"; RAN=$((RAN+1)); }

command -v jq >/dev/null 2>&1 || { echo "FAIL  jq is required to validate $INV" >&2; exit 1; }
[ -f "$INV" ] || { echo "FAIL  $INV not found" >&2; exit 1; }
jq empty "$INV" >/dev/null 2>&1 || { echo "FAIL  $INV does not parse as JSON" >&2; exit 1; }

# --- contract_version: the hand-bumped SCHEMA version. An unknown value must fail loudly -- a
# validator that silently accepts a schema it does not understand is worse than no validator,
# because everything below reads fields whose meaning may have changed out from under it.
SUPPORTED_CONTRACT_VERSIONS=" 1 "
cv=$(jq -r '.contract_version' "$INV")
case "$SUPPORTED_CONTRACT_VERSIONS" in
  (*" $cv "*) pass "contract_version $cv recognised" ;;
  (*) fail "contract_version" "claude/inventory.json declares contract_version $cv, which this validator does not recognise (known:$SUPPORTED_CONTRACT_VERSIONS). The schema may have changed under it -- update tests/inventory-contract.sh before trusting anything else in this file, do not proceed past this line." ;;
esac

# --- payload digest: recompute the EXACT recipe the file documents (derived_at.digest_recipe),
# by eval'ing that string rather than a copy of it kept here, so the recipe this script runs and
# the recipe the file claims to be reporting can never drift apart from each other. A mismatch
# means the tree moved since this snapshot was taken and every derived field below needs
# re-checking -- the file calls this out itself (derived_at.staleness_is_the_signal): "the
# intended failure, not a maintenance chore".
#
# The recipe excludes claude/inventory.json's own path on purpose (derived_at.self_reference_note):
# the file lives inside claude/, which the recipe scans, so without the exclusion the digest could
# never match itself -- committing the file changes its own blob hash, which changes the digest
# it is trying to record, a fixed point editing the file cannot reach.
digest_cmd=$(jq -r '.derived_at.digest_recipe' "$INV")
computed_digest=$(eval "$digest_cmd" 2>/dev/null | awk '{print $1}')
stated_digest=$(jq -r '.derived_at.payload_digest' "$INV")
if [ "$computed_digest" = "$stated_digest" ]; then
  pass "payload_digest matches the tree ($computed_digest)"
else
  fail "payload_digest" "claude/inventory.json's derived_at.payload_digest is $stated_digest; the tree's is $computed_digest. The snapshot is stale."
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

check_list "components.skills.members"           ".components.skills.members"           "skills"
check_list "components.agents.members"           ".components.agents.members"           "agents"
check_list "components.agent_references.members" ".components.agent_references.members" "agent_references"
check_list "components.commands.members"         ".components.commands.members"         "commands"
check_list "components.hooks.members"            ".components.hooks.members"            "hooks"
check_list "components.wrappers.members"         ".components.wrappers.members"         "wrappers"
check_list "components.mcp_servers.members"      ".components.mcp_servers.members"      "mcp_servers"
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
  [ -n "$cmd" ] || continue
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
  echo "inventory-contract: $RAN checks, all clean"
  exit 0
else
  echo "inventory-contract: $RAN checks, FAILURES ABOVE"
  exit 1
fi
