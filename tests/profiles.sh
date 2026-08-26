#!/usr/bin/env bash
# profiles.sh — regression test for install.sh's --profile=/VSTACK_PROFILE= support.
#
# Written after a real, reproduced defect: back() in install.sh recorded ownership (own())
# only AFTER an `[ -f "$1" ] || return 0` guard, so a brand-new install (nothing at the
# destination yet -- back() runs before the cp) never called own() for any hook, agent,
# command, wrapper, CLAUDE.md or statusline.sh. It was invisible on main because nothing
# consulted the ownership record for real removal decisions. The moment a profile installs at
# least one skill (whose loop calls own() directly, unconditionally), $OWNED_PATHS gets
# created containing ONLY that skill, and uninstall.sh's owns_path() -- which trusts a
# present file completely -- silently kept every hook/agent/command/wrapper/CLAUDE.md a --yes
# uninstall was supposed to remove, while still exiting 0. `core` alone "passed" only by
# accident: it installs no skills, so $OWNED_PATHS was never created at all, and
# owns_path()'s missing-file branch fell back to "assume everything" (the pre-1.46.0
# behaviour) and removed the lot anyway.
#
# That shape -- exit 0, plan looked right, yet the files never moved -- is exactly why this
# file asserts on-disk state (file counts, an ownership-record line count, an explicit
# leftover scan) and never on exit codes alone. A `check` here that only inspected `$?` would
# have passed against the live bug.
#
# Usage: bash tests/profiles.sh
set -uo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAIL=0
CHECK_N=0

say() { printf '%s\n' "$*"; }
hr()  { printf -- '---------------------------------------------------------------\n'; }

# check <name> <expected> <found-desc> <0-pass/1-fail>
check() {
  name="$1"; expected="$2"; found="$3"; status="$4"
  CHECK_N=$((CHECK_N + 1))
  if [ "$status" = 0 ]; then
    say "PASS  [$name]"
  else
    say "FAIL  [$name]"
    say "      expected: $expected"
    say "      found:    $found"
    FAIL=$((FAIL + 1))
  fi
}

# Named var, never the literal string "$HOME" -- this repo's own guard blocks `rm -rf "$HOME"`
# even with HOME reassigned, and a sandbox variable with its own name is the documented way
# round it. Each call replaces $HOME (exported) and leaves the previous sandbox on disk for
# the caller to clean up explicitly -- tests below always rm -rf their own $SBOX when done.
new_sandbox() {
  SBOX=$(mktemp -d) || { echo "cannot create sandbox" >&2; exit 1; }
  export HOME="$SBOX/home"
  mkdir -p "$HOME"
}

# Every managed path this repo can install, outside the sandbox's own bookkeeping (backups/,
# the ownership record itself, the repo pointer, secrets). Anything found here after a --yes
# uninstall is a leftover the uninstall was supposed to remove.
leftover_scan() {
  {
    find "$HOME/.claude" -type f 2>/dev/null
    find "$HOME/.config/agents" -type f 2>/dev/null \
      | grep -v -e '/secrets' -e '/vstack-repo' -e '/vstack-installed' -e '/verify-trust' -e '/backups/'
    find "$HOME/.conductor" -type f 2>/dev/null
  } | grep -v -e '/settings\.json$' -e '/backups/'
}

owned_lines() {
  wc -l < "$HOME/.config/agents/vstack-installed" 2>/dev/null | tr -d ' '
}

# The stable, deterministic slice of a fresh install: what install.sh actually decides based
# on PROFILE, with every source of per-run noise this repo is known to produce excluded by
# construction (not by diffing and hoping) -- mktemp/PID-suffixed .claude.json.tmp.*,
# epoch-ms-timestamped backups/*, gh's own random device-id under .local/state/gh/, and
# .config/agents/vstack-repo (which legitimately differs whenever $SRC differs, e.g. a
# worktree comparison against another checkout of the same commit).
payload_files() {
  find "$1/.claude/hooks" "$1/.claude/agents" "$1/.claude/commands" "$1/.claude/skills" \
       -type f 2>/dev/null
  [ -f "$1/.claude/CLAUDE.md" ] && printf '%s\n' "$1/.claude/CLAUDE.md"
  [ -f "$1/.claude/statusline.sh" ] && printf '%s\n' "$1/.claude/statusline.sh"
  [ -f "$1/.claude/settings.json" ] && printf '%s\n' "$1/.claude/settings.json"
}

hr
say "=== per-profile membership + ownership-record + round-trip ==="
hr

# profile  hooks_ok(count) agent_canary_present agent_canary_absent skill_count claude_md owned_lines
run_profile_case() {
  P="$1"; EXPECT_HOOKS="$2"; EXPECT_AGENTS="$3"; EXPECT_COMMANDS="$4"; EXPECT_SKILLS="$5"
  EXPECT_CLAUDE_MD="$6"; EXPECT_OWNED_LINES="$7"
  say ""
  say "--- profile=$P ---"
  new_sandbox
  install_out=$(HOME="$HOME" VSTACK_PROFILE="$P" "$SRC/install.sh" 2>&1)
  ic=$?
  check "$P: install exits 0" "0" "$ic" "$([ "$ic" = 0 ] && echo 0 || echo 1)"
  [ "$ic" = 0 ] || say "      install.sh output: $install_out"

  nh=$(ls "$HOME/.claude/hooks" 2>/dev/null | wc -l | tr -d ' ')
  check "$P: hook count" "$EXPECT_HOOKS" "$nh" "$([ "$nh" = "$EXPECT_HOOKS" ] && echo 0 || echo 1)"

  na=$(find "$HOME/.claude/agents" -mindepth 1 -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')
  check "$P: agent count" "$EXPECT_AGENTS" "$na" "$([ "$na" = "$EXPECT_AGENTS" ] && echo 0 || echo 1)"

  nc=$(ls "$HOME/.claude/commands" 2>/dev/null | wc -l | tr -d ' ')
  check "$P: command count" "$EXPECT_COMMANDS" "$nc" "$([ "$nc" = "$EXPECT_COMMANDS" ] && echo 0 || echo 1)"

  ns=$(find "$HOME/.claude/skills" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
  check "$P: skill count" "$EXPECT_SKILLS" "$ns" "$([ "$ns" = "$EXPECT_SKILLS" ] && echo 0 || echo 1)"

  if [ "$EXPECT_CLAUDE_MD" = yes ]; then
    check "$P: CLAUDE.md present" "present" "$([ -f "$HOME/.claude/CLAUDE.md" ] && echo present || echo absent)" \
      "$([ -f "$HOME/.claude/CLAUDE.md" ] && echo 0 || echo 1)"
  else
    check "$P: CLAUDE.md absent" "absent" "$([ -f "$HOME/.claude/CLAUDE.md" ] && echo present || echo absent)" \
      "$([ -f "$HOME/.claude/CLAUDE.md" ] && echo 1 || echo 0)"
  fi

  ol=$(owned_lines)
  check "$P: ownership record line count" "$EXPECT_OWNED_LINES" "$ol" "$([ "$ol" = "$EXPECT_OWNED_LINES" ] && echo 0 || echo 1)"

  # Round trip: uninstall --yes must leave zero leftovers, judged by presence on disk, not by
  # exit code -- the live bug this file guards against exited 0 while every file survived.
  uninstall_out=$(HOME="$HOME" bash "$SRC/uninstall.sh" --yes 2>&1)
  uc=$?
  left=$(leftover_scan)
  nleft=$(printf '%s\n' "$left" | grep -c .)
  check "$P: uninstall exits 0" "0" "$uc" "$([ "$uc" = 0 ] && echo 0 || echo 1)"
  [ "$uc" = 0 ] || say "      uninstall.sh output: $uninstall_out"
  check "$P: zero leftover files after uninstall" "0 files" "$nleft file(s): $left" "$([ "$nleft" = 0 ] && echo 0 || echo 1)"
  check "$P: ownership record removed" "gone" "$([ -f "$HOME/.config/agents/vstack-installed" ] && echo present || echo gone)" \
    "$([ -f "$HOME/.config/agents/vstack-installed" ] && echo 1 || echo 0)"

  rm -rf "$SBOX"
}

# Measured directly against this tree by re-running install.sh in a throwaway sandbox and
# counting; not read out of install.sh's own PROFILE_* variables, so this cannot pass just
# because the installer and this test share one wrong assumption.
run_profile_case core         5  0  11 0  no  30
run_profile_case team         7 14  15 1  no  54
run_profile_case ui           5  3  11 4  no  39
run_profile_case opinionated  8 14  15 28 yes 83

hr
say "=== right set installs, wrong set does not (canary files) ==="
hr

new_sandbox
HOME="$HOME" VSTACK_PROFILE=core "$SRC/install.sh" >/dev/null 2>&1
check "core: has verify-gate.sh (safety hook)" "present" "$([ -f "$HOME/.claude/hooks/verify-gate.sh" ] && echo present || echo absent)" \
  "$([ -f "$HOME/.claude/hooks/verify-gate.sh" ] && echo 0 || echo 1)"
check "core: lacks dispatch-counter.sh (team-only hook)" "absent" "$([ -f "$HOME/.claude/hooks/dispatch-counter.sh" ] && echo present || echo absent)" \
  "$([ -f "$HOME/.claude/hooks/dispatch-counter.sh" ] && echo 1 || echo 0)"
check "core: lacks agents/qa.md (no roster)" "absent" "$([ -f "$HOME/.claude/agents/qa.md" ] && echo present || echo absent)" \
  "$([ -f "$HOME/.claude/agents/qa.md" ] && echo 1 || echo 0)"
check "core: lacks commands/team.md (no /team)" "absent" "$([ -f "$HOME/.claude/commands/team.md" ] && echo present || echo absent)" \
  "$([ -f "$HOME/.claude/commands/team.md" ] && echo 1 || echo 0)"
check "core: lacks swarm skill" "absent" "$([ -d "$HOME/.claude/skills/swarm" ] && echo present || echo absent)" \
  "$([ -d "$HOME/.claude/skills/swarm" ] && echo 1 || echo 0)"
rm -rf "$SBOX"

new_sandbox
HOME="$HOME" VSTACK_PROFILE=team "$SRC/install.sh" >/dev/null 2>&1
check "team: has dispatch-counter.sh (team-only hook)" "present" "$([ -f "$HOME/.claude/hooks/dispatch-counter.sh" ] && echo present || echo absent)" \
  "$([ -f "$HOME/.claude/hooks/dispatch-counter.sh" ] && echo 0 || echo 1)"
check "team: has agents/qa.md (roster)" "present" "$([ -f "$HOME/.claude/agents/qa.md" ] && echo present || echo absent)" \
  "$([ -f "$HOME/.claude/agents/qa.md" ] && echo 0 || echo 1)"
check "team: has commands/team.md (/team)" "present" "$([ -f "$HOME/.claude/commands/team.md" ] && echo present || echo absent)" \
  "$([ -f "$HOME/.claude/commands/team.md" ] && echo 0 || echo 1)"
check "team: lacks CLAUDE.md (routing policy is opinionated-only)" "absent" \
  "$([ -f "$HOME/.claude/CLAUDE.md" ] && echo present || echo absent)" \
  "$([ -f "$HOME/.claude/CLAUDE.md" ] && echo 1 || echo 0)"
rm -rf "$SBOX"

new_sandbox
HOME="$HOME" VSTACK_PROFILE=ui "$SRC/install.sh" >/dev/null 2>&1
check "ui: has agents/ui-engineer.md" "present" "$([ -f "$HOME/.claude/agents/ui-engineer.md" ] && echo present || echo absent)" \
  "$([ -f "$HOME/.claude/agents/ui-engineer.md" ] && echo 0 || echo 1)"
check "ui: has component-registry skill" "present" "$([ -d "$HOME/.claude/skills/component-registry" ] && echo present || echo absent)" \
  "$([ -d "$HOME/.claude/skills/component-registry" ] && echo 0 || echo 1)"
check "ui: lacks dispatch-counter.sh (team-only hook)" "absent" \
  "$([ -f "$HOME/.claude/hooks/dispatch-counter.sh" ] && echo present || echo absent)" \
  "$([ -f "$HOME/.claude/hooks/dispatch-counter.sh" ] && echo 1 || echo 0)"
check "ui: lacks commands/team.md (no /team)" "absent" \
  "$([ -f "$HOME/.claude/commands/team.md" ] && echo present || echo absent)" \
  "$([ -f "$HOME/.claude/commands/team.md" ] && echo 1 || echo 0)"
rm -rf "$SBOX"

hr
say "=== compat fallback: no ownership record => uninstall assumes everything is vstack's ==="
hr
say "(this is the exact case that made a bare 'core' install pass by accident before the fix"
say " to back() -- pinned here explicitly so nobody mistakes it for the general mechanism, or"
say " removes it thinking it's dead code once every profile records ownership correctly.)"

new_sandbox
HOME="$HOME" VSTACK_PROFILE=opinionated "$SRC/install.sh" >/dev/null 2>&1
before_hooks=$(ls "$HOME/.claude/hooks" 2>/dev/null | wc -l | tr -d ' ')
check "compat: opinionated install actually landed hooks" "greater than 0" "$before_hooks" \
  "$([ "$before_hooks" -gt 0 ] && echo 0 || echo 1)"
rm -f "$HOME/.config/agents/vstack-installed"   # simulate a pre-1.46.0 machine: no record at all
compat_uout=$(HOME="$HOME" bash "$SRC/uninstall.sh" --yes 2>&1)
uc=$?
left=$(leftover_scan)
nleft=$(printf '%s\n' "$left" | grep -c .)
check "compat: uninstall exits 0 with no ownership record present" "0" "$uc" "$([ "$uc" = 0 ] && echo 0 || echo 1)"
[ "$uc" = 0 ] || say "      uninstall.sh output: $compat_uout"
check "compat: zero leftovers with no ownership record (assume-everything fallback)" "0 files" \
  "$nleft file(s): $left" "$([ "$nleft" = 0 ] && echo 0 || echo 1)"
rm -rf "$SBOX"

hr
say "=== migration seeding x non-default profile: a name collision must not delete a directory ==="
hr
say "(the untested join a real adversarial review found: seed_owned_paths()'s fingerprint loop"
say " tested the destination but its five seeding loops tested only whether the REPO ships a"
say " path, which is always true -- so a --profile=core install on a machine with >= 3 of"
say " vstack's own hook basenames sitting in ~/.claude/hooks (satisfied by every pre-1.46.0"
say " machine, which kept no ownership record at all) claimed every agent, command, reference"
say " file and skill in the repository, none of which core actually put on disk. A user"
say " directory later created under a colliding skill name -- ordinary names like"
say " \"brainstorming\" are exactly what someone would pick unprompted -- then had its owns_path()"
say " check pass on nothing but that name match, and the skills-removal loop rm -rfd it: no"
say " content comparison guarded a directory the way plan_file_removal already guards a file.)"

new_sandbox
mkdir -p "$HOME/.claude/hooks"
# The exact fingerprint seed_owned_paths() looks for: >= 3 of vstack's own hook basenames
# already sitting at the destination, with no ownership record present -- what every genuine
# pre-1.46.0 machine looks like the first time it meets a version that writes one.
cp "$SRC/claude/hooks/compat-canary.sh" "$SRC/claude/hooks/failure-diagnose.sh" \
   "$SRC/claude/hooks/format.sh" "$HOME/.claude/hooks/"
install_out=$(HOME="$HOME" VSTACK_PROFILE=core "$SRC/install.sh" 2>&1)
ic=$?
check "migration+core: install exits 0" "0" "$ic" "$([ "$ic" = 0 ] && echo 0 || echo 1)"
[ "$ic" = 0 ] || say "      install.sh output: $install_out"

check "migration+core: seeder did not over-claim (agents dir has no vstack agent files)" \
  "0 agent files" \
  "$(find "$HOME/.claude/agents" -mindepth 1 -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ') agent files" \
  "$([ -z "$(find "$HOME/.claude/agents" -mindepth 1 -maxdepth 1 -type f 2>/dev/null)" ] && echo 0 || echo 1)"
check "migration+core: seeder did not over-claim (no skill directories)" "0 skill dirs" \
  "$(find "$HOME/.claude/skills" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ') skill dirs" \
  "$([ -z "$(find "$HOME/.claude/skills" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)" ] && echo 0 || echo 1)"
# Directly on the record, not just on-disk state -- the over-claim bug pollutes OWNED_PATHS
# without copying any file, so a check that only looks at the filesystem cannot see it: the
# seeder called own() for every agent/command/skill the repo ships, whether or not this core
# install actually put it at $CDIR. A record entry for something core never installs is the
# defect itself, independent of whether uninstall.sh separately catches the consequence below.
# grep -c prints a count of 0 and still exits 1 on no match -- a `|| echo 0` fallback after it
# double-prints ("0" from grep, then "0" from the fallback, since the nonzero exit trips ||
# regardless of what grep already wrote), so the count is read from stdout alone, unguarded.
claim_count=$(grep -c "agents/qa.md\|commands/team.md\|skills/swarm" "$HOME/.config/agents/vstack-installed" 2>/dev/null)
claim_count=${claim_count:-0}
check "migration+core: ownership record does not claim agents/commands/skills core never installed" \
  "no agents/qa.md, no commands/team.md, no skills/swarm in the record" \
  "$claim_count matching line(s)" "$([ "$claim_count" = 0 ] && echo 0 || echo 1)"

# Plant a user's own directory under a name this repo also uses for a skill, with content that
# does not match what vstack would install (the exact repro).
mkdir -p "$HOME/.claude/skills/brainstorming"
printf 'my own private notes\n' > "$HOME/.claude/skills/brainstorming/notes.md"

uninstall_out=$(HOME="$HOME" bash "$SRC/uninstall.sh" --yes 2>&1)
uc=$?
check "migration+core: uninstall exits 0" "0" "$uc" "$([ "$uc" = 0 ] && echo 0 || echo 1)"
check "migration+core: the colliding user directory survives" "directory + file both present" \
  "$([ -f "$HOME/.claude/skills/brainstorming/notes.md" ] && echo present || echo GONE)" \
  "$([ -f "$HOME/.claude/skills/brainstorming/notes.md" ] && echo 0 || echo 1)"
check "migration+core: the colliding directory's content is untouched" "my own private notes" \
  "$(cat "$HOME/.claude/skills/brainstorming/notes.md" 2>/dev/null || echo MISSING)" \
  "$([ "$(cat "$HOME/.claude/skills/brainstorming/notes.md" 2>/dev/null)" = "my own private notes" ] && echo 0 || echo 1)"
rm -rf "$SBOX"

hr
say "=== a genuinely-owned skill whose content changed after install must not be rm -rf'd ==="
hr
say "(defense in depth, independent of the migration-seeding case above: even a correctly-"
say " seeded/recorded ownership entry must not be trusted alone once content has diverged --"
say " the record says a path was OURS at install time, not that it still is now. Directories"
say " get the same byte-for-byte discipline plan_file_removal() already gives single files.)"

new_sandbox
HOME="$HOME" VSTACK_PROFILE=opinionated "$SRC/install.sh" >/dev/null 2>&1
grep -qxF "$HOME/.claude/skills/brainstorming" "$HOME/.config/agents/vstack-installed" \
  && seeded_ok=0 || seeded_ok=1
check "content-divergence: brainstorming is genuinely recorded as ours before the edit" "recorded" \
  "$([ "$seeded_ok" = 0 ] && echo recorded || echo "not recorded")" "$seeded_ok"

# The user repurposes vstack's own directory in place -- the same shape as editing a file
# plan_file_removal already protects, just on a directory uninstall.sh has to walk instead.
rm -rf "$HOME/.claude/skills/brainstorming"
mkdir -p "$HOME/.claude/skills/brainstorming"
printf 'repurposed after install, not vstack content anymore\n' > "$HOME/.claude/skills/brainstorming/SKILL.md"

uninstall_out=$(HOME="$HOME" bash "$SRC/uninstall.sh" --yes 2>&1)
uc=$?
check "content-divergence: uninstall exits 0" "0" "$uc" "$([ "$uc" = 0 ] && echo 0 || echo 1)"
check "content-divergence: the edited directory survives uninstall" "directory present, edited content intact" \
  "$([ -f "$HOME/.claude/skills/brainstorming/SKILL.md" ] && cat "$HOME/.claude/skills/brainstorming/SKILL.md" || echo GONE)" \
  "$([ -f "$HOME/.claude/skills/brainstorming/SKILL.md" ] && grep -qxF "repurposed after install, not vstack content anymore" "$HOME/.claude/skills/brainstorming/SKILL.md" && echo 0 || echo 1)"
rm -rf "$SBOX"

hr
say "=== --dry-run changes nothing, per profile ==="
hr
for P in core team ui opinionated; do
  new_sandbox
  before=$(find "$HOME" -type f 2>/dev/null | sort)
  HOME="$HOME" VSTACK_PROFILE="$P" "$SRC/install.sh" --dry-run >/dev/null 2>&1
  dc=$?
  after=$(find "$HOME" -type f 2>/dev/null | sort)
  check "$P --dry-run: exits 0" "0" "$dc" "$([ "$dc" = 0 ] && echo 0 || echo 1)"
  check "$P --dry-run: filesystem unchanged" "identical file list" \
    "$([ "$before" = "$after" ] && echo identical || echo changed)" \
    "$([ "$before" = "$after" ] && echo 0 || echo 1)"
  rm -rf "$SBOX"
done

hr
say "=== profile validation: bad values rejected, not silently accepted ==="
hr
new_sandbox
HOME="$HOME" "$SRC/install.sh" --profile=bogus >/dev/null 2>&1
bc=$?
check "unknown profile exits 2" "2" "$bc" "$([ "$bc" = 2 ] && echo 0 || echo 1)"
rm -rf "$SBOX"

new_sandbox
skmsg=$(HOME="$HOME" VSTACK_PROFILE=skills "$SRC/install.sh" 2>&1)
skc=$?
check "VSTACK_PROFILE=skills exits 2 (hook-runtime value, not an install profile)" "2" "$skc" \
  "$([ "$skc" = 2 ] && echo 0 || echo 1)"
check "VSTACK_PROFILE=skills error names the hook-runtime origin" "mentions hooks.json/inject-session-context.sh" \
  "$skmsg" "$(printf '%s' "$skmsg" | grep -q "hooks.json" && echo 0 || echo 1)"
rm -rf "$SBOX"

new_sandbox
HOME="$HOME" "$SRC/install.sh" --profile=core --profile=team >/dev/null 2>&1
last_wins=$?
# Last flag on the command line wins (plain left-to-right case-statement overwrite); this pins
# that as intentional, not asserts a specific choice between the two -- either flag value must
# still be a valid profile, so exit 0 is what "not silently broken" looks like here.
check "repeated --profile flags: last one wins, still installs cleanly" "exit 0" "$last_wins" \
  "$([ "$last_wins" = 0 ] && echo 0 || echo 1)"
rm -rf "$SBOX"

hr
say "=== opinionated is the default: byte-identical to a bare, no-argument install ==="
hr
new_sandbox; SBOX_A="$SBOX"; HOME_A="$HOME"
HOME="$HOME_A" "$SRC/install.sh" >/dev/null 2>&1

new_sandbox; SBOX_B="$SBOX"; HOME_B="$HOME"
HOME="$HOME_B" "$SRC/install.sh" --profile=opinionated >/dev/null 2>&1

# Compare the stable payload only (see payload_files()'s own comment for exactly what that
# excludes and why) -- relative paths first, then byte content after stripping each sandbox's
# own $HOME prefix out of every file (vstack-repo excluded entirely instead: it legitimately
# holds $SRC verbatim, and $SRC is the same live checkout for both runs here, so it is
# deterministic and does not need normalising).
list_a=$(payload_files "$HOME_A" | sed "s#^$HOME_A/##" | sort)
list_b=$(payload_files "$HOME_B" | sed "s#^$HOME_B/##" | sort)
check "no-arg vs --profile=opinionated: identical payload file lists" "same set" \
  "$([ "$list_a" = "$list_b" ] && echo same || echo "different: $(diff <(printf '%s\n' "$list_a") <(printf '%s\n' "$list_b"))")" \
  "$([ "$list_a" = "$list_b" ] && echo 0 || echo 1)"

content_diff=0
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  fa="$HOME_A/$rel"; fb="$HOME_B/$rel"
  [ -f "$fa" ] && [ -f "$fb" ] || { content_diff=1; say "      only on one side: $rel"; continue; }
  na=$(sed "s#$HOME_A#@HOME@#g" "$fa" 2>/dev/null)
  nb=$(sed "s#$HOME_B#@HOME@#g" "$fb" 2>/dev/null)
  if [ "$na" != "$nb" ]; then
    content_diff=1
    say "      byte diff after HOME-normalisation: $rel"
  fi
done <<EOF
$(printf '%s\n%s\n' "$list_a" "$list_b" | sort -u)
EOF
check "no-arg vs --profile=opinionated: byte-identical payload content (HOME-normalised)" "no diffs" \
  "$([ "$content_diff" = 0 ] && echo none || echo "see byte diff lines above")" "$content_diff"
rm -rf "$SBOX_A" "$SBOX_B"

hr
say "=== opinionated matches the last commit's install.sh (profiles add no default drift) ==="
hr
WT=$(mktemp -d)
if git -C "$SRC" worktree add --detach "$WT" HEAD -q 2>/tmp/profiles-worktree-err; then
  new_sandbox; SBOX_C="$SBOX"; HOME_C="$HOME"
  HOME="$HOME_C" "$WT/install.sh" >/dev/null 2>&1
  wc_ic=$?
  check "HEAD's install.sh (no args) runs clean in an isolated worktree" "exit 0" "$wc_ic" \
    "$([ "$wc_ic" = 0 ] && echo 0 || echo 1)"

  new_sandbox; SBOX_D="$SBOX"; HOME_D="$HOME"
  HOME="$HOME_D" "$SRC/install.sh" >/dev/null 2>&1

  # Scoped to the stable payload set (payload_files()) for the same reason as the no-arg-vs-
  # flag comparison above, PLUS one more: HEAD, in this shared, uncommitted checkout, predates
  # two fixes this branch already needed independent of profiles -- compat-canary.sh's
  # SessionStart wiring (landed in a concurrent commit whose install.sh-side wiring is part of
  # THIS uncommitted work) and back()'s ownership-recording fix (this file's whole reason to
  # exist). Both change hooks/settings.json and vstack-installed content on purpose. Comparing
  # settings.json against HEAD would fail on the compat-canary entry alone, a real, wanted
  # change with nothing to do with profiles -- so this check only claims what the brief asked
  # for: that HEAD's install.sh (no profile support at all) and this checkout's install.sh
  # --profile=opinionated agree on which files land, restricted to hooks/agents/commands/
  # skills/CLAUDE.md -- the part profile filtering actually touches.
  list_c=$(find "$HOME_C/.claude/hooks" "$HOME_C/.claude/agents" "$HOME_C/.claude/commands" \
                "$HOME_C/.claude/skills" -type f 2>/dev/null | sed "s#^$HOME_C/##" | sort)
  list_d=$(find "$HOME_D/.claude/hooks" "$HOME_D/.claude/agents" "$HOME_D/.claude/commands" \
                "$HOME_D/.claude/skills" -type f 2>/dev/null | sed "s#^$HOME_D/##" | sort)
  # compat-canary.sh is expected on the working-tree side only (HEAD's install.sh does not
  # wire it yet -- that wiring is part of this same uncommitted change) -- excluded from the
  # "profiles add no drift" claim by name, not silently swallowed into a generic mismatch.
  list_c_f=$(printf '%s\n' "$list_c" | grep -v '/hooks/compat-canary\.sh$')
  list_d_f=$(printf '%s\n' "$list_d" | grep -v '/hooks/compat-canary\.sh$')
  check "working-tree default vs HEAD's install.sh: identical hook/agent/command/skill file lists (compat-canary.sh excluded, see above)" \
    "same set" \
    "$([ "$list_c_f" = "$list_d_f" ] && echo same || echo "different: $(diff <(printf '%s\n' "$list_c_f") <(printf '%s\n' "$list_d_f"))")" \
    "$([ "$list_c_f" = "$list_d_f" ] && echo 0 || echo 1)"

  # Content, not just existence, can legitimately differ from HEAD for a reason that has
  # nothing to do with profiles: another agent's own uncommitted, in-flight edit to a hook,
  # agent, command or skill this checkout is shared with (this repo's tests/README.md
  # documents multiple agents editing this tree concurrently; ownership is per-file, not
  # per-checkout). Computed fresh each run, by basename, from the actual source tree's own
  # diff against HEAD -- not a hardcoded list that bit-rots the moment that other lane commits
  # or a different file goes dirty next.
  dirty_src_basenames=$(git -C "$SRC" diff --name-only HEAD -- claude/hooks claude/agents \
    claude/commands claude/skills 2>/dev/null | xargs -n1 basename 2>/dev/null | sort -u)

  payload_diff=0
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    bn=$(basename "$rel")
    if printf '%s\n' "$dirty_src_basenames" | grep -qxF "$bn"; then
      say "      skipped (unrelated concurrent edit in this checkout, not a profiles change): $rel"
      continue
    fi
    fc="$HOME_C/$rel"; fd="$HOME_D/$rel"
    [ -f "$fc" ] && [ -f "$fd" ] || continue
    nc_=$(sed "s#$HOME_C#@HOME@#g" "$fc" 2>/dev/null)
    nd_=$(sed "s#$HOME_D#@HOME@#g" "$fd" 2>/dev/null)
    if [ "$nc_" != "$nd_" ]; then
      payload_diff=1
      say "      byte diff after HOME-normalisation: $rel"
    fi
  done <<EOF2
$(printf '%s\n%s\n' "$list_c_f" "$list_d_f" | sort -u)
EOF2
  check "working-tree default vs HEAD's install.sh: payload byte-identical (HOME-normalised, files with an unrelated in-flight edit excluded)" \
    "no diffs" "$([ "$payload_diff" = 0 ] && echo none || echo "see byte diff lines above")" "$payload_diff"
  rm -rf "$SBOX_C" "$SBOX_D"
  git -C "$SRC" worktree remove "$WT" --force 2>/dev/null
else
  say "SKIP  [HEAD-comparison worktree] could not create worktree: $(cat /tmp/profiles-worktree-err 2>/dev/null)"
fi
rm -rf "$WT" 2>/dev/null

hr
say "checks run: $CHECK_N   failed: $FAIL"
if [ "$FAIL" -gt 0 ]; then
  say "RESULT: FAIL -- install.sh profile support and/or its uninstall join has a defect"
else
  say "RESULT: PASS -- every profile installs, uninstalls and round-trips as declared"
fi
exit "$FAIL"
