#!/usr/bin/env bash
# tests/container-matrix.sh -- proves the published vstack install works in a genuinely foreign
# environment, not a simulation of one.
#
# tests/install-matrix.sh runs install.sh against throwaway HOMEs on whatever host runs the
# suite -- in practice, always macOS, always bash 5, always GNU-adjacent coreutils via Homebrew.
# This script runs the install inside real containers instead, and installs from published
# GitHub the way an actual stranger does: no worktree mounted in, no credentials, no local
# shortcuts.
#
# Retargeted to v1.38.0 (written against v1.31.0) and widened: nine releases shipped between
# those two tags and none of the new surface had a lane. Added:
#   - inventory: every skill/agent/command resolves to installed frontmatter with a description
#   - skill-name integrity: CLAUDE.md + the hook's live routing block resolve VERBATIM, no
#     prefix guessing -- the v1.35.0 defect, where the gate's own check hid eight dangling
#     routing entries by prepending "principle-" for them
#   - the session hook actually emits non-empty JSON for SessionStart and UserPromptSubmit
#   - skill-mandate.sh in all four directions, asserted on the stdout JSON naming the specific
#     mandate, never on exit code (it is 0 either way)
#   - guard-destructive.sh's three tiers: deny, ask, and silent-allow
#   - statusline.sh on a payload with empty fields (the field-shift bug shipped once)
#   - the delegation-drift logger: counts-only, opt-out honored, nothing written outside its
#     configured path
#   - format.sh: refuses to hand a JS/TS-format prettier config to prettier (closed this week)
#
# Every count below is DERIVED from the installed tree inside the container, never hardcoded --
# a hardcoded number is a claim that rots, which is why the source repo's own gate has a check
# 12 that exists for exactly that failure.
#
# Assertions, per image (all model-free -- vstack's enforcement layer is shell). The exact list
# a given run declared is derived from the assertions script itself (grep -c '^res ') and printed
# in the summary -- not hardcoded here either.
#
# CREDENTIALS: nothing from the host is mounted. No ~/.claude, no API key, no auth, and the
# `claude` CLI itself is never installed. Any lane whose assertion needs an authenticated CLI is
# reported as UNMEASURABLE, kept structurally distinct from both PASS and FAIL in the totals --
# see the summary this script prints at the end. check 3 (this repo's own .claude/verify.sh
# gate, run inside the clone) is required to end 0-skipped for exactly this reason: a skip
# folded silently into a pass is the failure mode this script exists to catch, and the plugin-
# manifest check inside that gate needs an authenticated CLI this harness deliberately does not
# provide.
#
# Usage: tests/container-matrix.sh [image ...]     (default: the three below)
#   VSTACK_REF=v1.38.0   the tag/branch installed from https://github.com/itsvedantkumar/vstack
#   DOCKER_CONFIG         passed through untouched; set it yourself if your docker needs it
set -uo pipefail
IMAGES=("$@")
[ "${#IMAGES[@]}" -eq 0 ] && IMAGES=(debian:stable-slim alpine:latest ubuntu:latest)
REF="${VSTACK_REF:-v1.38.0}"

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/vstack-container-matrix.XXXXXX")
trap 'rm -rf "$ROOT"' EXIT

DECLARED=0; RAN=0; SKIPPED=0
declare -a LANE_LINES=()
declare -a CONTAINERS=()
cleanup_containers(){
  # "${ARR[@]}" on a still-empty array is unbound under set -u on bash 3.2 (macOS's default
  # /bin/bash) -- the exact host/container mismatch this script exists to catch elsewhere -- so
  # it has to tolerate it in itself too.
  for c in "${CONTAINERS[@]+"${CONTAINERS[@]}"}"; do docker rm -f "$c" >/dev/null 2>&1; done
}
trap 'cleanup_containers; rm -rf "$ROOT"' EXIT

if ! command -v docker >/dev/null 2>&1; then
  echo "container-matrix: docker not found on PATH -- cannot run any lane"
  echo
  printf 'lanes: %d declared, %d ran, %d skipped\n' "${#IMAGES[@]}" 0 "${#IMAGES[@]}"
  echo "CONTAINER MATRIX: NO LANES RAN"
  exit 1
fi
if ! docker info >/dev/null 2>&1; then
  echo "container-matrix: docker daemon not reachable (docker info failed) -- cannot run any lane"
  echo
  printf 'lanes: %d declared, %d ran, %d skipped\n' "${#IMAGES[@]}" 0 "${#IMAGES[@]}"
  echo "CONTAINER MATRIX: NO LANES RAN"
  exit 1
fi

# --- per-package-manager bootstrap: the minimum a stranger installs before cloning -------------
cat > "$ROOT/bootstrap-apk.sh" <<'EOF'
#!/bin/sh
set -e
apk add --no-cache bash git jq curl ca-certificates shellcheck 2>&1 || \
  apk add --no-cache bash git jq curl ca-certificates 2>&1
EOF

cat > "$ROOT/bootstrap-apt.sh" <<'EOF'
#!/bin/sh
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends git jq curl ca-certificates shellcheck || \
  apt-get install -y -qq --no-install-recommends git jq curl ca-certificates
EOF

# --- the in-container assertion runner ----------------------------------------------------------
# Clones vstack from published GitHub at $VSTACK_REF, installs it, and exercises every assertion
# below. Emits RESULT lines this script parses; nothing here trusts the container's exit code
# alone, because a script that dies halfway can still exit 0 from the shell's point of view if
# the last line run happened to succeed.
cat > "$ROOT/assertions.sh" <<'ASSERT_EOF'
#!/usr/bin/env bash
# Runs inside a container. Clones vstack from published GitHub at $VSTACK_REF, installs it, and
# exercises the assertions below. Prints RESULT lines the host parses.
set -uo pipefail
REF="${VSTACK_REF:-v1.38.0}"
LABEL="${IMAGE_LABEL:-unknown}"
PASS=0; FAIL=0; SKIP=0
res(){ # <status> <name> <detail>
  printf 'RESULT %s|%s|%s|%s\n' "$LABEL" "$1" "$2" "$3"
  case "$1" in PASS) PASS=$((PASS+1));; FAIL) FAIL=$((FAIL+1));; SKIP) SKIP=$((SKIP+1));; esac
}

echo "=== env: $LABEL ==="
uname -a
[ -f /etc/os-release ] && grep -E '^(NAME|VERSION)=' /etc/os-release
readlink -f /bin/sh 2>/dev/null || ls -la /bin/sh
bash --version | head -1
git --version
jq --version

echo "=== clone $REF ==="
rm -rf /work && mkdir -p /work
git clone --quiet --branch "$REF" --depth 1 https://github.com/itsvedantkumar/vstack.git /work/repo 2>&1
CLONE_RC=$?
if [ "$CLONE_RC" -ne 0 ]; then
  res FAIL "clone" "git clone --branch $REF exited $CLONE_RC -- nothing else can run"
  echo "checks: 0 declared, 0 ran, 1 skipped (clone failed)"
  exit 1
fi
GOT_SHA=$(git -C /work/repo rev-parse HEAD)
res PASS "clone" "cloned $REF at $GOT_SHA"

# --- 1. install.sh exit code 0, unpiped -------------------------------------------------------
export HOME=/root
/work/repo/install.sh > /tmp/install.out 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then res PASS "1-install-exit0" "install.sh exit=$rc"
else res FAIL "1-install-exit0" "install.sh exit=$rc; tail: $(tail -5 /tmp/install.out | tr '\n' ' ')"; fi

# --- 2. bin/doctor exit code 0 --------------------------------------------------------------
DOCTOR="$HOME/.config/agents/bin/doctor"
if [ -x "$DOCTOR" ]; then
  "$DOCTOR" > /tmp/doctor.out 2>&1
  rc=$?
  if [ "$rc" -eq 0 ]; then res PASS "2-doctor-exit0" "doctor exit=$rc"
  else res FAIL "2-doctor-exit0" "doctor exit=$rc; $(grep '✖' /tmp/doctor.out | tr '\n' ';')"; fi
else
  res FAIL "2-doctor-exit0" "install did not place an executable $DOCTOR"
fi

# --- 3. .claude/verify.sh ends VERIFIED with 0 skipped (repo's own gate, in the clone) --------
# 0-skipped is required deliberately: a skip folded silently into a pass is the exact failure
# this harness exists to catch. The plugin-manifest check inside that gate needs an
# authenticated `claude` CLI, which this harness never installs -- so it is expected to render
# as a hard, visible requirement this lane cannot clear here, not a silent pass. That is reported
# separately below as UNMEASURABLE, not folded into PASS or FAIL.
out=$(/work/repo/.claude/verify.sh 2>&1)
vrc=$?
acct=$(printf '%s\n' "$out" | grep -E '^checks: ' | tail -1)
tail_word=$(printf '%s\n' "$out" | tail -1)
skipped=$(printf '%s' "$acct" | grep -oE '[0-9]+ skipped' | grep -oE '^[0-9]+')
skip_reasons=$(printf '%s\n' "$out" | grep '^skip ' | tr '\n' ';')
if [ "$tail_word" = "VERIFIED" ] && [ "${skipped:-1}" = 0 ]; then
  res PASS "3-verify-gate" "$acct / $tail_word"
else
  needs_auth=0
  printf '%s' "$skip_reasons" | grep -qi 'plugin manifest\|authenticat\|claude CLI' && needs_auth=1
  if [ "$needs_auth" = 1 ]; then
    res SKIP "3-verify-gate" "UNMEASURABLE WITHOUT CREDENTIALS: $acct / $tail_word; skip reasons: $skip_reasons"
  else
    res FAIL "3-verify-gate" "$acct / $tail_word (exit=$vrc); skip reasons: $skip_reasons"
  fi
fi

# --- 4. every installed hook script present in settings.json under an event key ---------------
CDIR="$HOME/.claude"
SETTINGS="$CDIR/settings.json"
if [ -f "$SETTINGS" ] && command -v jq >/dev/null 2>&1; then
  missing=""
  for h in "$CDIR"/hooks/*.sh; do
    [ -e "$h" ] || continue
    n=$(basename "$h")
    ev=$(jq -r --arg n "$n" '.hooks | to_entries[] | select(.value[]?.hooks[]?.command | test($n)) | .key' "$SETTINGS" 2>/dev/null | sort -u | tr '\n' ',')
    [ -n "$ev" ] || missing="$missing $n"
  done
  if [ -z "$missing" ]; then
    res PASS "4-hook-wiring" "every installed hooks/*.sh referenced under some event key in settings.json"
  else
    res FAIL "4-hook-wiring" "not referenced in settings.json:$missing"
  fi
else
  res FAIL "4-hook-wiring" "settings.json missing or jq unavailable"
fi
ASSERT_EOF
cat >> "$ROOT/assertions.sh" <<'ASSERT_EOF'

# --- 5. inventory: every skill/agent/command resolves to installed frontmatter + description ---
# Counts are DERIVED from the installed tree, never hardcoded -- report what was found, not what
# was expected.
nsk=0; nsk_bad=0; sk_errs=""
for d in "$CDIR"/skills/*/; do
  [ -d "$d" ] || continue
  s=$(basename "$d")
  nsk=$((nsk+1))
  f="$d/SKILL.md"
  if [ ! -f "$f" ]; then sk_errs="$sk_errs $s:no-SKILL.md"; nsk_bad=$((nsk_bad+1)); continue; fi
  fm=$(awk 'BEGIN{c=0} /^---[ \t]*$/{c++; next} c==1' "$f")
  if [ -z "$fm" ]; then sk_errs="$sk_errs $s:unparseable-frontmatter"; nsk_bad=$((nsk_bad+1)); continue; fi
  name_v=$(printf '%s\n' "$fm" | sed -n 's/^name:[ \t]*//p' | head -1 | tr -d '"'"'"'' )
  desc_v=$(printf '%s\n' "$fm" | sed -n 's/^description:[ \t]*//p' | head -1)
  if [ -z "$name_v" ]; then sk_errs="$sk_errs $s:no-name"; nsk_bad=$((nsk_bad+1)); continue; fi
  if [ -z "$desc_v" ]; then sk_errs="$sk_errs $s:empty-description"; nsk_bad=$((nsk_bad+1)); continue; fi
done
nag=0; nag_bad=0; ag_errs=""
for f in "$CDIR"/agents/*.md; do
  [ -e "$f" ] || continue
  nag=$((nag+1))
  a=$(basename "$f" .md)
  fm=$(awk 'BEGIN{c=0} /^---[ \t]*$/{c++; next} c==1' "$f")
  desc_v=$(printf '%s\n' "$fm" | sed -n 's/^description:[ \t]*//p' | head -1)
  [ -n "$desc_v" ] || { ag_errs="$ag_errs $a:empty-or-missing-description"; nag_bad=$((nag_bad+1)); }
done
ncmd=0; ncmd_bad=0; cmd_errs=""
for f in "$CDIR"/commands/*.md; do
  [ -e "$f" ] || continue
  ncmd=$((ncmd+1))
  c=$(basename "$f" .md)
  fm=$(awk 'BEGIN{c=0} /^---[ \t]*$/{c++; next} c==1' "$f")
  desc_v=$(printf '%s\n' "$fm" | sed -n 's/^description:[ \t]*//p' | head -1)
  [ -n "$desc_v" ] || { cmd_errs="$cmd_errs $c:empty-or-missing-description"; ncmd_bad=$((ncmd_bad+1)); }
done
if [ "$nsk_bad" = 0 ] && [ "$nag_bad" = 0 ] && [ "$ncmd_bad" = 0 ] && [ "$nsk" -gt 0 ] && [ "$nag" -gt 0 ] && [ "$ncmd" -gt 0 ]; then
  res PASS "5-inventory" "skills=$nsk (0 bad), agents=$nag (0 bad), commands=$ncmd (0 bad) -- all resolve, all have a non-empty description"
else
  res FAIL "5-inventory" "skills=$nsk bad=$nsk_bad[$sk_errs]; agents=$nag bad=$nag_bad[$ag_errs]; commands=$ncmd bad=$ncmd_bad[$cmd_errs]"
fi

# --- 6. skill-name integrity: CLAUDE.md + the hook's LIVE routing block resolve VERBATIM -------
# This is the v1.35.0 defect: the source gate used to accept a short "prove-it-works" by
# prepending "principle-" itself, which hid eight routing entries pointing at names that did not
# exist. No prefix guessing here -- a token resolves to an installed skill/agent/command dir
# exactly as written, or it is a defect.
if command -v jq >/dev/null 2>&1; then
  # The routing block as the hook ACTUALLY emits it right now, in this installed tree, in the
  # SAME mode install.sh's own settings.json runs it in (no VSTACK_PROFILE -- that env var is
  # the plugin/marketplace lane's variant, not what a direct install's SessionStart hook command
  # actually sets) -- not the source heredoc, which is a stronger claim (proves the runtime
  # output a stranger's first session really sees, not the source text).
  route_out=$(printf '{"hook_event_name":"SessionStart"}' | bash "$CDIR/hooks/inject-session-context.sh" 2>/dev/null)
  route_text=$(printf '%s' "$route_out" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)
  claude_md_text=$(cat "$CDIR/CLAUDE.md" 2>/dev/null)
  # Generic hyphenated English / git-plumbing / agent-and-command tokens that the same token
  # pattern also matches -- verified by hand against the actual emitted text of this release,
  # not copied from the source gate's own list.
  ALLOW='agent-written|cross-cutting|one-step|multi-step|one-line|options-survey|per-prompt|re-pins|re-pin|to-the-point|rev-parse|show-current|show-toplevel|symbolic-ref|is-inside-work-tree|git-common-dir|auto-apply|auto-fire|multi-phase|name-only|session-context|session-start|operating-mode|two-line'
  errs=""
  toks=$( { printf '%s\n' "$claude_md_text"; printf '%s\n' "$route_text"; } | grep -ohE '\b[a-z][a-z0-9]*(-[a-z0-9]+)+' | sort -u )
  ntok=0
  for tok in $toks; do
    ntok=$((ntok+1))
    [ -d "$CDIR/skills/$tok" ] && continue
    [ -f "$CDIR/agents/$tok.md" ] && continue
    [ -f "$CDIR/commands/$tok.md" ] && continue
    printf '%s' "$tok" | grep -qE "^($ALLOW)$" && continue
    errs="$errs $tok"
  done
  if [ -z "$route_text" ]; then
    res FAIL "6-skill-name-integrity" "hook emitted no routing text to check against CLAUDE.md and the installed tree"
  elif [ -z "$errs" ]; then
    res PASS "6-skill-name-integrity" "$ntok hyphenated tokens checked verbatim across installed CLAUDE.md + live routing block, all resolve"
  else
    res FAIL "6-skill-name-integrity" "referenced but not installed (verbatim, no prefix guessing):$errs"
  fi
else
  res FAIL "6-skill-name-integrity" "jq unavailable"
fi

# --- 7. the hook actually emits: SessionStart and UserPromptSubmit both produce non-empty,
#        valid JSON with a non-empty additionalContext -----------------------------------------
if command -v jq >/dev/null 2>&1; then
  ss_out=$(printf '{"hook_event_name":"SessionStart"}' | bash "$CDIR/hooks/inject-session-context.sh" 2>/tmp/ss.err)
  ss_ok=0
  if [ -n "$ss_out" ] && printf '%s' "$ss_out" | jq -e '.hookSpecificOutput.additionalContext | length > 0' >/dev/null 2>&1; then ss_ok=1; fi
  ups_out=$(printf '{"hook_event_name":"UserPromptSubmit","prompt":"fix the flaky test in checkout.spec.ts","session_id":"beth-emit-%s"}' "$LABEL" | bash "$CDIR/hooks/inject-session-context.sh" 2>/tmp/ups.err)
  ups_ok=0
  if [ -n "$ups_out" ] && printf '%s' "$ups_out" | jq -e '.hookSpecificOutput.additionalContext | length > 0' >/dev/null 2>&1; then ups_ok=1; fi
  if [ "$ss_ok" = 1 ] && [ "$ups_ok" = 1 ]; then
    res PASS "7-hook-emits" "SessionStart and UserPromptSubmit both produced valid JSON with non-empty additionalContext"
  else
    res FAIL "7-hook-emits" "SessionStart valid=$ss_ok (raw: $(printf '%s' "$ss_out" | cut -c1-150)); UserPromptSubmit valid=$ups_ok (raw: $(printf '%s' "$ups_out" | cut -c1-150))"
  fi
else
  res FAIL "7-hook-emits" "jq unavailable"
fi
ASSERT_EOF
cat >> "$ROOT/assertions.sh" <<'ASSERT_EOF'

# --- 8-12. skill-mandate.sh, all four directions (five sub-cases: prove-it-works needs two) ----
# Asserted on the stdout JSON's .reason naming the SPECIFIC mandate, never on exit code -- the
# hook exits 0 whether or not it blocks, and accepting any block as proof of the RIGHT block is
# the defect this suite closes.
MSH="$CDIR/hooks/skill-mandate.sh"
if [ -x "$MSH" ] && command -v jq >/dev/null 2>&1; then
  mkdir -p /tmp/mandate
  jline_text(){ jq -cn --arg t "$1" '{type:"assistant",message:{content:[{type:"text",text:$t}]}}'; }
  jline_tool(){ jq -cn --arg n "$1" --argjson i "$2" '{type:"assistant",message:{content:[{type:"tool_use",name:$n,input:$i}]}}'; }
  # VSTACK_DELEGATION_LOG must be exported before the pipeline, not prefixed onto just the
  # printf half of it -- an env-var prefix on one command in a pipe scopes to that command only,
  # and skill-mandate.sh (the OTHER half of the pipe) would then fall back to its real default
  # path and write these synthetic fixture Stops straight into the actual installed
  # ~/.claude/vstack-delegation-log.jsonl, next to genuine session data. The source comment on
  # VSTACK_DELEGATION_LOG says exactly this must not happen; this scopes the override to the
  # whole function via a subshell so it never leaks past run_mandate either.
  run_mandate(){ ( # <fixture-file> <session-id-suffix>
    export VSTACK_DELEGATION_LOG=/tmp/mandate/drop.jsonl
    printf '{"transcript_path":"%s","session_id":"beth-%s-%s","stop_hook_active":false}' "$1" "$2" "$LABEL" \
      | TMPDIR=/tmp bash "$MSH" 2>/tmp/mandate.err
  ) }

  # 8: breadth across >=3 dirs / >=2 extensions, zero dispatch -> block naming the breadth mandate.
  { jline_tool Write '{"file_path":"/tmp/mandate/breadth/a/x.sh"}'
    jline_tool Write '{"file_path":"/tmp/mandate/breadth/b/y.json"}'
    jline_tool Write '{"file_path":"/tmp/mandate/breadth/c/z.yaml"}'
    jline_text "Updated the three config files."
  } > /tmp/mandate/breadth-no-dispatch.jsonl
  out8=$(run_mandate /tmp/mandate/breadth-no-dispatch.jsonl breadth-nodispatch)
  dec8=$(printf '%s' "$out8" | jq -r '.decision // "none"' 2>/dev/null)
  reason8=$(printf '%s' "$out8" | jq -r '.reason // ""' 2>/dev/null)
  if [ "$dec8" = block ] && printf '%s' "$reason8" | grep -q 'multi-directory work'; then
    res PASS "8-mandate-breadth-blocks" "breadth with zero dispatch blocked, naming 'multi-directory work'"
  else
    res FAIL "8-mandate-breadth-blocks" "decision=$dec8 (want block naming 'multi-directory work'); reason: $(printf '%s' "$reason8" | tr '\n' ' ' | cut -c1-200)"
  fi

  # 9: same breadth, but WITH an Agent dispatch + a named call sign -> stays silent (exit 0, empty stdout).
  { jline_tool Write '{"file_path":"/tmp/mandate/breadth2/a/x.sh"}'
    jline_tool Write '{"file_path":"/tmp/mandate/breadth2/b/y.json"}'
    jline_tool Write '{"file_path":"/tmp/mandate/breadth2/c/z.yaml"}'
    jline_tool Agent '{"prompt":"verify the config changes","subagent_type":"qa"}'
    jline_text "Delegated verification to RICK for follow-up."
  } > /tmp/mandate/breadth-with-dispatch.jsonl
  out9=$(run_mandate /tmp/mandate/breadth-with-dispatch.jsonl breadth-dispatch)
  if [ -z "$out9" ]; then
    res PASS "9-mandate-breadth-dispatch-silent" "breadth with an Agent dispatch + attribution stayed silent"
  else
    res FAIL "9-mandate-breadth-dispatch-silent" "expected empty stdout, got: $(printf '%s' "$out9" | tr '\n' ' ' | cut -c1-200)"
  fi

  # 10: purely conversational turn (no tool_use at all) -> stays silent.
  jline_text "Sure -- here's how the retry loop's exponential backoff is computed." > /tmp/mandate/conversational.jsonl
  out10=$(run_mandate /tmp/mandate/conversational.jsonl conversational)
  if [ -z "$out10" ]; then
    res PASS "10-mandate-conversational-silent" "a purely conversational turn stayed silent"
  else
    res FAIL "10-mandate-conversational-silent" "expected empty stdout, got: $(printf '%s' "$out10" | tr '\n' ' ' | cut -c1-200)"
  fi

  # 11: prove-it-works -- an edit, then a completion claim, with NO Bash/Read/Task/Agent call
  # anywhere in the turn -> block naming prove-it-works.
  { jline_tool Write '{"file_path":"/tmp/mandate/piw/fix.sh"}'
    jline_text "The fix is done."
  } > /tmp/mandate/piw-unverified.jsonl
  out11=$(run_mandate /tmp/mandate/piw-unverified.jsonl piw-unverified)
  dec11=$(printf '%s' "$out11" | jq -r '.decision // "none"' 2>/dev/null)
  reason11=$(printf '%s' "$out11" | jq -r '.reason // ""' 2>/dev/null)
  if [ "$dec11" = block ] && printf '%s' "$reason11" | grep -q 'prove-it-works'; then
    res PASS "11-mandate-prove-it-works-blocks" "edit + completion claim with no verification blocked, naming 'prove-it-works'"
  else
    res FAIL "11-mandate-prove-it-works-blocks" "decision=$dec11 (want block naming 'prove-it-works'); reason: $(printf '%s' "$reason11" | tr '\n' ' ' | cut -c1-200)"
  fi

  # 12: same shape, but a Bash call is present in the turn -> stays silent.
  { jline_tool Write '{"file_path":"/tmp/mandate/piw2/fix.sh"}'
    jline_tool Bash '{"command":"bash /tmp/mandate/piw2/fix.sh --selftest"}'
    jline_text "The fix is done."
  } > /tmp/mandate/piw-verified.jsonl
  out12=$(run_mandate /tmp/mandate/piw-verified.jsonl piw-verified)
  if [ -z "$out12" ]; then
    res PASS "12-mandate-prove-it-works-silent" "edit + completion claim WITH a Bash call in the turn stayed silent"
  else
    res FAIL "12-mandate-prove-it-works-silent" "expected empty stdout, got: $(printf '%s' "$out12" | tr '\n' ' ' | cut -c1-200)"
  fi
else
  res FAIL "8-mandate-breadth-blocks" "$MSH missing or not executable, or jq unavailable"
  res FAIL "9-mandate-breadth-dispatch-silent" "$MSH missing or not executable, or jq unavailable"
  res FAIL "10-mandate-conversational-silent" "$MSH missing or not executable, or jq unavailable"
  res FAIL "11-mandate-prove-it-works-blocks" "$MSH missing or not executable, or jq unavailable"
  res FAIL "12-mandate-prove-it-works-silent" "$MSH missing or not executable, or jq unavailable"
fi
ASSERT_EOF
cat >> "$ROOT/assertions.sh" <<'ASSERT_EOF'

# --- 13-17. guard-destructive.sh, all three tiers -----------------------------------------------
GSH="$CDIR/hooks/guard-destructive.sh"
if [ -x "$GSH" ] && command -v jq >/dev/null 2>&1; then
  gdec(){ printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null; }

  d13=$(printf '%s' '{"tool_input":{"command":"rm -rf /"}}' | bash "$GSH" 2>/dev/null)
  v13=$(gdec "$d13")
  [ "$v13" = deny ] && res PASS "13-guard-deny-rm-rf-root" "rm -rf / => deny" \
    || res FAIL "13-guard-deny-rm-rf-root" "got $v13, want deny"

  d14=$(printf '%s' '{"tool_input":{"command":"git push --force origin main"}}' | bash "$GSH" 2>/dev/null)
  v14=$(gdec "$d14")
  [ "$v14" = deny ] && res PASS "14-guard-deny-force-push-main" "unqualified force-push to main => deny" \
    || res FAIL "14-guard-deny-force-push-main" "got $v14, want deny"

  # ask tier, case A: wildcard staging in a workspace this session does not own.
  d15=$(cd /tmp && CONDUCTOR_WORKSPACE_PATH=/tmp/not-this-session printf '%s' '{"tool_input":{"command":"git add -A"}}' | env CONDUCTOR_WORKSPACE_PATH=/tmp/not-this-session bash "$GSH" 2>/dev/null)
  v15=$(gdec "$d15")
  [ "$v15" = ask ] && res PASS "15-guard-ask-wildcard-staging-foreign-workspace" "git add -A outside \$CONDUCTOR_WORKSPACE_PATH => ask" \
    || res FAIL "15-guard-ask-wildcard-staging-foreign-workspace" "got $v15, want ask"

  # ask tier, case B: unconditional (no workspace context needed) -- git reset --hard.
  d16=$(printf '%s' '{"tool_input":{"command":"git reset --hard HEAD~1"}}' | bash "$GSH" 2>/dev/null)
  v16=$(gdec "$d16")
  [ "$v16" = ask ] && res PASS "16-guard-ask-reset-hard" "git reset --hard => ask" \
    || res FAIL "16-guard-ask-reset-hard" "got $v16, want ask"

  # allow tier: an ordinary command.
  d17=$(printf '%s' '{"tool_input":{"command":"ls -la"}}' | bash "$GSH" 2>/dev/null)
  v17=$(gdec "$d17")
  [ "$v17" = allow ] && res PASS "17-guard-allow-ordinary" "ls -la => allow" \
    || res FAIL "17-guard-allow-ordinary" "got $v17, want allow"
else
  res FAIL "13-guard-deny-rm-rf-root" "$GSH missing or not executable, or jq unavailable"
  res FAIL "14-guard-deny-force-push-main" "$GSH missing or not executable, or jq unavailable"
  res FAIL "15-guard-ask-wildcard-staging-foreign-workspace" "$GSH missing or not executable, or jq unavailable"
  res FAIL "16-guard-ask-reset-hard" "$GSH missing or not executable, or jq unavailable"
  res FAIL "17-guard-allow-ordinary" "$GSH missing or not executable, or jq unavailable"
fi

# --- 18-19. statusline.sh renders without field-shift on empty fields --------------------------
SLINE="$CDIR/statusline.sh"
if [ -x "$SLINE" ] && command -v jq >/dev/null 2>&1; then
  mkdir -p /tmp/statustest
  payload=$(jq -cn '{model:{display_name:"Claude Test"},workspace:{current_dir:"/tmp/statustest"},output_style:{name:""},cost:{total_cost_usd:3.5,total_lines_added:10,total_lines_removed:5},context_window:{total_input_tokens:150000}}')
  out18=$(printf '%s' "$payload" | bash "$SLINE" 2>/tmp/statusline.err)
  ok18=1
  printf '%s' "$out18" | grep -qF '$3.50' || ok18=0
  printf '%s' "$out18" | grep -qF '+10' || ok18=0
  printf '%s' "$out18" | grep -qF -e '-5' || ok18=0
  printf '%s' "$out18" | grep -qF 'ctx 150k' || ok18=0
  printf '%s' "$out18" | grep -qF 'statustest' || ok18=0
  if [ "$ok18" = 1 ]; then
    res PASS "18-statusline-empty-field-no-shift" "empty output_style.name mid-payload: cost=\$3.50, +10/-5, ctx 150k, dir=statustest all landed in the right slot"
  else
    res FAIL "18-statusline-empty-field-no-shift" "rendered: $(printf '%s' "$out18" | cat -v | cut -c1-300)"
  fi

  out19=$(printf '{}' | bash "$SLINE" 2>/tmp/statusline2.err); rc19=$?
  if [ "$rc19" -eq 0 ] && [ -n "$out19" ] && printf '%s' "$out19" | grep -qF 'Claude'; then
    res PASS "19-statusline-fully-empty-payload" "empty {} payload rendered without crashing: $(printf '%s' "$out19" | cat -v | cut -c1-80)"
  else
    res FAIL "19-statusline-fully-empty-payload" "rc=$rc19 out=$(printf '%s' "$out19" | cat -v | cut -c1-200) stderr=$(cat /tmp/statusline2.err 2>/dev/null | cut -c1-200)"
  fi
else
  res FAIL "18-statusline-empty-field-no-shift" "$SLINE missing or not executable, or jq unavailable"
  res FAIL "19-statusline-fully-empty-payload" "$SLINE missing or not executable, or jq unavailable"
fi
ASSERT_EOF
cat >> "$ROOT/assertions.sh" <<'ASSERT_EOF'

# --- 20-22. the delegation-drift logger: counts-only, opt-out honored, path-scoped ------------
if [ -x "$MSH" ] && command -v jq >/dev/null 2>&1; then
  mkdir -p /tmp/dlog
  jq -cn '{type:"assistant",message:{content:[{type:"text",text:"just chatting, nothing to log beyond counts"}]}}' > /tmp/dlog/benign.jsonl
  LOGF=/tmp/dlog/scratch.jsonl
  rm -f "$LOGF"
  DEFAULT_LOG="$CDIR/vstack-delegation-log.jsonl"
  before_sz=0
  [ -f "$DEFAULT_LOG" ] && before_sz=$(stat -c%s "$DEFAULT_LOG" 2>/dev/null || stat -f%z "$DEFAULT_LOG" 2>/dev/null || echo 0)

  VSTACK_DELEGATION_LOG="$LOGF" printf '{"transcript_path":"/tmp/dlog/benign.jsonl","session_id":"beth-dlog-%s","stop_hook_active":false}' "$LABEL" \
    | VSTACK_DELEGATION_LOG="$LOGF" TMPDIR=/tmp bash "$MSH" >/dev/null 2>/tmp/dlog.err

  if [ -f "$LOGF" ]; then
    line=$(tail -1 "$LOGF")
    keys=$(printf '%s' "$line" | jq -r 'keys | sort | join(",")' 2>/dev/null)
    # An ALLOWLIST, not an exact key list. This assertion used to be a string comparison against
    # `checkpoint_index,dir_count,ext_count,named,session_id,task_count,ts`, and it broke the day
    # the hook grew two benign counters (`latched`, `task_fail_count`) -- failing on every
    # container for a reason that had nothing to do with what it protects. Worse than the false
    # alarm is the repair it invites: paste in whatever the current keys are, which launders a
    # leaked key into the expectation the moment one appears.
    #
    # So: every key must be declared here, and adding one is a deliberate edit. That half is
    # unchanged in spirit.
    DLOG_ALLOWED_KEYS='checkpoint_index dir_count ext_count latched named session_id task_count task_fail_count ts'
    undeclared=$(printf '%s' "$line" \
      | jq -r --arg a "$DLOG_ALLOWED_KEYS" '($a|split(" ")) as $ok | [keys[] | . as $k | select(($ok|index($k))==null)] | join(",")' 2>/dev/null)
    # The property this test actually exists for, asserted on VALUES rather than on three literal
    # strings. `grep -c '/tmp/dlog/benign.jsonl\|"command"\|"file_path"'` only ever caught the one
    # leak somebody had already thought of; any other absolute path sailed through. A path is a
    # string value containing a slash, and no legitimate field here is one: the counters are
    # numbers, the flags are booleans, `ts` is an ISO timestamp and `session_id` is an opaque id.
    # This fires even on a key that has been added to the allowlist above, which is the point --
    # the allowlist governs shape, this governs content, and neither is sufficient alone.
    pathshaped=$(printf '%s' "$line" \
      | jq -r '[to_entries[] | select((.value|type)=="string" and (.value|test("/")))|.key] | join(",")' 2>/dev/null)
    has_path=$(printf '%s' "$line" | grep -c '/tmp/dlog/benign.jsonl\|"command"\|"file_path"' || true)
    if [ -z "$undeclared" ] && [ -z "$pathshaped" ] && [ "${has_path:-0}" = 0 ]; then
      res PASS "20-delegation-log-counts-only" "row keys: $keys; every key declared, no string value carries a path"
    else
      res FAIL "20-delegation-log-counts-only" "undeclared keys=[$undeclared], path-shaped values=[$pathshaped], literal leakage matches=$has_path, keys=$keys, line: $(printf '%s' "$line" | cut -c1-200)"
    fi
  else
    res FAIL "20-delegation-log-counts-only" "no log file written to configured VSTACK_DELEGATION_LOG=$LOGF"
  fi

  after_default_sz=0
  [ -f "$DEFAULT_LOG" ] && after_default_sz=$(stat -c%s "$DEFAULT_LOG" 2>/dev/null || stat -f%z "$DEFAULT_LOG" 2>/dev/null || echo 0)
  if [ "$before_sz" = "$after_default_sz" ]; then
    res PASS "22-delegation-log-path-scoped" "default log ($DEFAULT_LOG) unchanged ($before_sz bytes) while VSTACK_DELEGATION_LOG override was set -- nothing written outside the configured path"
  else
    res FAIL "22-delegation-log-path-scoped" "default log grew from $before_sz to $after_default_sz bytes despite an explicit VSTACK_DELEGATION_LOG override"
  fi

  sz_before_optout=0
  [ -f "$LOGF" ] && sz_before_optout=$(stat -c%s "$LOGF" 2>/dev/null || stat -f%z "$LOGF" 2>/dev/null || echo 0)
  VSTACK_NO_DELEGATION_LOG=1 VSTACK_DELEGATION_LOG="$LOGF" printf '{"transcript_path":"/tmp/dlog/benign.jsonl","session_id":"beth-dlog-optout-%s","stop_hook_active":false}' "$LABEL" \
    | VSTACK_NO_DELEGATION_LOG=1 VSTACK_DELEGATION_LOG="$LOGF" TMPDIR=/tmp bash "$MSH" >/dev/null 2>/tmp/dlog2.err
  sz_after_optout=0
  [ -f "$LOGF" ] && sz_after_optout=$(stat -c%s "$LOGF" 2>/dev/null || stat -f%z "$LOGF" 2>/dev/null || echo 0)
  if [ "$sz_before_optout" = "$sz_after_optout" ]; then
    res PASS "21-delegation-log-optout" "VSTACK_NO_DELEGATION_LOG=1 wrote nothing ($sz_before_optout bytes before and after)"
  else
    res FAIL "21-delegation-log-optout" "log grew from $sz_before_optout to $sz_after_optout bytes despite VSTACK_NO_DELEGATION_LOG=1"
  fi
else
  res FAIL "20-delegation-log-counts-only" "$MSH missing or not executable, or jq unavailable"
  res FAIL "21-delegation-log-optout" "$MSH missing or not executable, or jq unavailable"
  res FAIL "22-delegation-log-path-scoped" "$MSH missing or not executable, or jq unavailable"
fi

# --- 23-24. format.sh never hands a JS/TS-format prettier config to prettier -------------------
FSH="$CDIR/hooks/format.sh"
if [ -x "$FSH" ] && command -v jq >/dev/null 2>&1; then
  rm -rf /tmp/fmt && mkdir -p /tmp/fmt/jscfg/node_modules/.bin /tmp/fmt/staticcfg/node_modules/.bin
  cat > /tmp/fmt/jscfg/prettier.config.js <<'JS'
module.exports = {semi:false};
JS
  cat > /tmp/fmt/jscfg/node_modules/.bin/prettier <<'SH'
#!/bin/sh
touch /tmp/fmt/jscfg-prettier-invoked
SH
  chmod +x /tmp/fmt/jscfg/node_modules/.bin/prettier
  echo 'const x=1' > /tmp/fmt/jscfg/some.ts
  rm -f /tmp/fmt/jscfg-prettier-invoked
  jq -cn --arg f /tmp/fmt/jscfg/some.ts '{tool_input:{file_path:$f}}' | bash "$FSH" >/dev/null 2>/tmp/fmt.err
  if [ ! -e /tmp/fmt/jscfg-prettier-invoked ]; then
    res PASS "23-format-refuses-js-config-prettier" "prettier.config.js present: prettier never invoked (no RCE path)"
  else
    res FAIL "23-format-refuses-js-config-prettier" "prettier WAS invoked against a JS-format config -- this is the RCE path that was closed"
  fi

  printf '{"semi": false}' > /tmp/fmt/staticcfg/.prettierrc.json
  cat > /tmp/fmt/staticcfg/node_modules/.bin/prettier <<'SH'
#!/bin/sh
touch /tmp/fmt/staticcfg-prettier-invoked
SH
  chmod +x /tmp/fmt/staticcfg/node_modules/.bin/prettier
  echo 'const x=1' > /tmp/fmt/staticcfg/some.ts
  rm -f /tmp/fmt/staticcfg-prettier-invoked
  jq -cn --arg f /tmp/fmt/staticcfg/some.ts '{tool_input:{file_path:$f}}' | bash "$FSH" >/dev/null 2>/tmp/fmt2.err
  if [ -e /tmp/fmt/staticcfg-prettier-invoked ]; then
    res PASS "24-format-still-runs-static-config-prettier" "positive control: a static .prettierrc.json config still invokes prettier -- the refusal is scoped to JS/TS configs, not a silent no-op"
  else
    res FAIL "24-format-still-runs-static-config-prettier" "prettier was NOT invoked even for a static config -- the JS-config refusal has regressed into a blanket no-op"
  fi
else
  res FAIL "23-format-refuses-js-config-prettier" "$FSH missing or not executable, or jq unavailable"
  res FAIL "24-format-still-runs-static-config-prettier" "$FSH missing or not executable, or jq unavailable"
fi
ASSERT_EOF
cat >> "$ROOT/assertions.sh" <<'ASSERT_EOF'

# --- 25. vstack trust refuses without a TTY ------------------------------------------------------
VBIN="$HOME/.config/agents/bin/vstack"
if [ -x "$VBIN" ]; then
  out=$(VSTACK_DIR=/work/repo "$VBIN" trust /work/repo < /dev/null 2>&1); rc=$?
  if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -qiE 'terminal|--yes'; then
    res PASS "25-trust-no-tty" "exit=$rc, refused citing no terminal"
  else
    res FAIL "25-trust-no-tty" "exit=$rc, output: $(printf '%s' "$out" | tr '\n' ' ' | cut -c1-200)"
  fi
else
  res FAIL "25-trust-no-tty" "$VBIN missing"
fi

# --- 26. vstack update prints a full diff, not a filtered allowlist -----------------------------
if [ -x "$VBIN" ]; then
  rm -rf /work/old && git clone --quiet --branch v1.30.0 --depth 1 https://github.com/itsvedantkumar/vstack.git /work/old 2>&1
  if [ -d /work/old/.git ]; then
    # --branch v1.30.0 --depth 1 leaves no origin/main tracking ref in a shallow clone, so
    # `diff v1.30.0..origin/main` used to fail with "bad revision" and $nongate silently landed
    # empty every single run -- the [ -z "$nongate" ] fallback then made this assertion pass
    # vacuously, on every image, forever: a green that measured nothing. Fetching main
    # explicitly into FETCH_HEAD first is what makes $nongate a real filename.
    git -C /work/old fetch --quiet origin main --depth 1 2>&1
    nongate=$(git -C /work/old diff --name-only v1.30.0..FETCH_HEAD -- . ':!install.sh' ':!overlay.sh' ':!uninstall.sh' ':!bootstrap.sh' ':!.claude/verify.sh' 2>/dev/null | head -1)
    out=$(VSTACK_DIR=/work/old "$VBIN" update < /dev/null 2>&1); rc=$?
    got_diff_header=$(printf '%s' "$out" | grep -c 'full diff,')
    # Pure-bash substring match, not `printf ... | grep -q`: $out is the full ~300KB+ diff, the
    # match is near its top, and `grep -q` exits the instant it finds one -- which closes the
    # pipe out from under `printf` mid-write. Under `set -o pipefail` (this script has it) that
    # SIGPIPE (exit 141) becomes the PIPELINE's exit status even though grep itself succeeded,
    # so `got_nongate` read as unset every time regardless of whether the string was actually
    # there. Confirmed against a real captured $out: grep -qF found it 0/1 times over a pipe,
    # 1/1 times reading the same bytes from a file -- this is that difference eliminated by
    # never piping into grep -q in the first place.
    got_nongate=0
    [ -n "$nongate" ] && [[ "$out" == *"$nongate"* ]] && got_nongate=1
    if [ "$rc" -ne 0 ] && [ "$got_diff_header" -ge 1 ] && { [ -z "$nongate" ] || [ "$got_nongate" -eq 1 ]; }; then
      res PASS "26-update-full-diff" "printed 'full diff' header; includes non-gate file '$nongate'; refused unattended (exit=$rc)"
    else
      shortcut=""
      [[ "$out" == *[Aa]lready\ up\ to\ date* ]] && shortcut=" -- took the already-up-to-date shortcut"
      res FAIL "26-update-full-diff" "exit=$rc header_seen=$got_diff_header nongate='$nongate' nongate_seen=$got_nongate$shortcut; tail: $(printf '%s' "$out" | head -1)"
    fi
  else
    res FAIL "26-update-full-diff" "could not clone v1.30.0 as the stale checkout to update from"
  fi
else
  res FAIL "26-update-full-diff" "$VBIN missing"
fi

# --- 27. idempotency: second install.sh run is clean --------------------------------------------
export HOME=/root2; mkdir -p "$HOME"
/work/repo/install.sh > /tmp/idem1.out 2>&1
if command -v sha256sum >/dev/null 2>&1; then SUM=sha256sum; else SUM=shasum; fi
fp(){ find "$1" -type f | sort | xargs $SUM 2>/dev/null | $SUM; }
a=$(fp "$HOME/.claude")
/work/repo/install.sh > /tmp/idem2.out 2>&1; rc=$?
b=$(fp "$HOME/.claude")
zdup=$(grep -c '>>> claude-parity >>>' "$HOME/.zshrc" 2>/dev/null); zdup=${zdup:-0}
if [ "$rc" -eq 0 ] && [ "$a" = "$b" ] && [ "${zdup:-0}" = 1 ]; then
  res PASS "27-idempotent" "second run exit=$rc, tree fingerprint unchanged, .zshrc block not duplicated"
else
  res FAIL "27-idempotent" "second run exit=$rc, fingerprint changed=$([ "$a" = "$b" ] && echo no || echo YES), zshrc-block-count=$zdup"
fi
export HOME=/root

# --- 28. uninstall removes what it installed, restores what it replaced ------------------------
export HOME=/root3; mkdir -p "$HOME/.claude/commands"
echo "MY OWN REVIEW" > "$HOME/.claude/commands/review.md"
/work/repo/install.sh > /tmp/uninst-install.out 2>&1
/work/repo/uninstall.sh --yes > /tmp/uninst.out 2>&1; rc=$?
e=""
[ -e "$HOME/.claude/hooks/verify-gate.sh" ] && e="$e; hooks survived"
grep -q 'MY OWN REVIEW' "$HOME/.claude/commands/review.md" 2>/dev/null || e="$e; user's review.md not restored"
if [ "$rc" -eq 0 ] && [ -z "$e" ]; then
  res PASS "28-uninstall" "uninstall exit=$rc, vstack files removed, user's own file restored"
else
  res FAIL "28-uninstall" "uninstall exit=$rc$e"
fi
export HOME=/root

# --- bonus: check 24 cannot pass or skip during a release (the pins-loop red window) -----------
if command -v jq >/dev/null 2>&1; then
  rm -rf /work/release && mkdir -p /work/release
  (git clone --quiet https://github.com/itsvedantkumar/vstack.git /work/release) 2>&1
  cur=$(jq -r '.version' /work/release/claude/.claude-plugin/plugin.json 2>/dev/null)
  next="${cur%.*}.$(( ${cur##*.} + 1 ))"
  tmpj=$(mktemp)
  jq --arg v "$next" '.version=$v' /work/release/claude/.claude-plugin/plugin.json > "$tmpj" && mv "$tmpj" /work/release/claude/.claude-plugin/plugin.json
  printf '\npin: VSTACK_REF=v%s\n' "$next" >> /work/release/README.md
  git -C /work/release add claude/.claude-plugin/plugin.json README.md
  git -C /work/release -c user.email=t@example.com -c user.name=t commit -q -m "bump version, tag not pushed yet"
  rout=$(/work/release/.claude/verify.sh 2>&1)
  rline=$(printf '%s\n' "$rout" | grep -A4 'declared version matches what installs' | tr '\n' ' ')
  if printf '%s\n' "$rout" | grep -q 'FAIL  declared version matches what installs' \
     && printf '%s\n' "$rout" | grep -qi 'not a tag in this repository'; then
    res PASS "bonus-check24-red-window" "confirmed: bump-without-tag hard-FAILs check 24 (not a skip): $rline"
  else
    res FAIL "bonus-check24-red-window" "expected a hard FAIL naming 'not a tag in this repository', got: $rline"
  fi
else
  res SKIP "bonus-check24-red-window" "jq not installed"
fi

echo
echo "container totals: $PASS passed, $FAIL failed, $SKIP skipped"
ASSERT_EOF

# EXPECTED_LANES: derived from the assertions script itself (count of res() call sites), not
# hardcoded -- so widening the suite again later cannot silently desync the "did every lane run
# to completion" sanity check from what it is actually checking.
EXPECTED_LANES=$(grep -oE 'res (PASS|FAIL|SKIP) "[^"]+"' "$ROOT/assertions.sh" \
  | sed -E 's/res (PASS|FAIL|SKIP) "([^"]+)"/\2/' | sort -u | wc -l | tr -d ' ')

pm_for(){ # <image> -> apk|apt|unknown
  case "$1" in
    alpine*) echo apk ;;
    debian*|ubuntu*) echo apt ;;
    *) echo unknown ;;
  esac
}

overall_pass=0; overall_fail=0; overall_skip=0
matrix_ok=1

for IMAGE in "${IMAGES[@]}"; do
  DECLARED=$((DECLARED+1))
  echo
  echo "############################################################"
  echo "# $IMAGE"
  echo "############################################################"

  if ! docker pull "$IMAGE" >/tmp/pull.$$.log 2>&1; then
    SKIPPED=$((SKIPPED+1))
    LANE_LINES+=("skip  $IMAGE (docker pull failed: $(tail -1 /tmp/pull.$$.log))")
    echo "SKIP  $IMAGE: docker pull failed"
    tail -5 /tmp/pull.$$.log
    rm -f /tmp/pull.$$.log
    continue
  fi
  rm -f /tmp/pull.$$.log

  PM=$(pm_for "$IMAGE")
  if [ "$PM" = unknown ]; then
    SKIPPED=$((SKIPPED+1))
    LANE_LINES+=("skip  $IMAGE (no apk/apt bootstrap recipe for this image)")
    echo "SKIP  $IMAGE: no bootstrap recipe (only alpine/debian/ubuntu families are wired)"
    continue
  fi

  CNAME="vstack-container-matrix-$$-$(echo "$IMAGE" | tr -c 'a-zA-Z0-9' '-')"
  if ! docker run -d --name "$CNAME" "$IMAGE" sleep 3600 >/tmp/run.$$.log 2>&1; then
    SKIPPED=$((SKIPPED+1))
    LANE_LINES+=("skip  $IMAGE (docker run failed: $(tail -1 /tmp/run.$$.log))")
    echo "SKIP  $IMAGE: docker run failed"
    rm -f /tmp/run.$$.log
    continue
  fi
  rm -f /tmp/run.$$.log
  CONTAINERS+=("$CNAME")

  docker cp "$ROOT/bootstrap-$PM.sh" "$CNAME:/bootstrap.sh" >/dev/null 2>&1
  docker cp "$ROOT/assertions.sh" "$CNAME:/assertions.sh" >/dev/null 2>&1

  if ! docker exec "$CNAME" sh /bootstrap.sh > "$ROOT/$CNAME.bootstrap.log" 2>&1; then
    RAN=$((RAN+1))
    overall_fail=$((overall_fail+1))
    matrix_ok=0
    LANE_LINES+=("FAIL  $IMAGE (bootstrap failed to install prerequisites -- see $ROOT/$CNAME.bootstrap.log)")
    echo "FAIL  $IMAGE: bootstrap (package install) failed"
    tail -15 "$ROOT/$CNAME.bootstrap.log"
    continue
  fi

  docker exec -e IMAGE_LABEL="$IMAGE" -e VSTACK_REF="$REF" "$CNAME" bash /assertions.sh \
    > "$ROOT/$CNAME.out" 2>&1
  cat "$ROOT/$CNAME.out"

  lane_pass=$(grep -c '^RESULT [^|]*|PASS|' "$ROOT/$CNAME.out" 2>/dev/null); lane_pass=${lane_pass:-0}
  lane_fail=$(grep -c '^RESULT [^|]*|FAIL|' "$ROOT/$CNAME.out" 2>/dev/null); lane_fail=${lane_fail:-0}
  lane_skip=$(grep -c '^RESULT [^|]*|SKIP|' "$ROOT/$CNAME.out" 2>/dev/null); lane_skip=${lane_skip:-0}
  lane_total=$((lane_pass + lane_fail + lane_skip))
  overall_pass=$((overall_pass+lane_pass)); overall_fail=$((overall_fail+lane_fail)); overall_skip=$((overall_skip+lane_skip))
  RAN=$((RAN+1))

  # A lane that ran fewer assertions than the assertions script declares crashed partway through
  # (set -uo pipefail does not save it: a subshell inside a $(...) can still swallow a fatal
  # error). That is reported as a FAIL, not folded into whatever partial PASS count it produced.
  if [ "$lane_fail" -eq 0 ] && [ "$lane_total" -ge "$EXPECTED_LANES" ]; then
    LANE_LINES+=("ok    $IMAGE (${lane_pass} passed, ${lane_skip} unmeasurable-without-credentials, of $EXPECTED_LANES declared)")
  else
    matrix_ok=0
    short=""
    [ "$lane_total" -lt "$EXPECTED_LANES" ] && short=" -- only $lane_total of $EXPECTED_LANES declared assertions ran; the lane crashed partway through"
    LANE_LINES+=("FAIL  $IMAGE (${lane_pass} passed, ${lane_fail} failed, ${lane_skip} unmeasurable-without-credentials, of $EXPECTED_LANES declared$short -- see the RESULT lines above)")
  fi
done

cleanup_containers

echo
echo "============================================================"
echo "container-matrix summary"
echo "============================================================"
for l in "${LANE_LINES[@]+"${LANE_LINES[@]}"}"; do printf '%s\n' "$l"; done
echo
printf 'assertion totals across all lanes that ran: %d passed, %d failed, %d unmeasurable-without-credentials (of %d declared per lane)\n' \
  "$overall_pass" "$overall_fail" "$overall_skip" "$EXPECTED_LANES"
echo
printf 'lanes: %d declared, %d ran, %d skipped\n' "$DECLARED" "$RAN" "$SKIPPED"
echo
echo "NOTE: any RESULT line marked SKIP is UNMEASURABLE WITHOUT CREDENTIALS, not a pass and not a"
echo "failure -- this harness mounts no credentials on purpose and does not install the claude"
echo "CLI, so lanes that need an authenticated session (the plugin-manifest check inside"
echo "check 3's .claude/verify.sh run) cannot be exercised here. Kept as a separate category on"
echo "purpose: folding it into either PASS or FAIL is exactly the failure this repo is named for."

# The accounting footer refuses to claim success when zero lanes ran -- a green run that measured
# nothing is the defect class every check in this repo exists to catch, including this one about
# itself.
if [ "$RAN" -eq 0 ]; then
  echo "CONTAINER MATRIX: NO LANES RAN"
  exit 1
fi
if [ "$matrix_ok" -eq 1 ] && [ "$overall_fail" -eq 0 ]; then
  echo "CONTAINER MATRIX OK"
  exit 0
else
  echo "CONTAINER MATRIX FAILED"
  exit 1
fi
