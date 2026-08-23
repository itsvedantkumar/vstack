#!/usr/bin/env bash
# tests/container-matrix.sh -- proves the published vstack install works in a genuinely foreign
# environment, not a simulation of one.
#
# tests/install-matrix.sh runs install.sh against throwaway HOMEs on whatever host runs the
# suite -- in practice, always macOS, always bash 5, always GNU-adjacent coreutils via Homebrew.
# It has six lanes including a "bash-only" one, added after a release only ever wrote
# .zshrc/.zshenv and broke every Debian/Ubuntu/Alpine box that shipped bash instead of zsh -- but
# even that lane runs the simulated shell on top of a real zsh/bash macOS host. It has never once
# run against a real BusyBox `sh`, a real bash 5 that is not Homebrew's, or a machine with no `jq`
# because nobody put one there. This script runs the install inside real containers instead of
# simulating them, and installs from published GitHub the way an actual stranger does: no
# worktree mounted in, no credentials, no local shortcuts.
#
# Assertions, per image (all model-free -- vstack's enforcement layer is shell):
#   1. install.sh exits 0, read on its own line, unpiped.
#   2. bin/doctor exits 0.
#   3. .claude/verify.sh (this repo's own gate, in the clone) ends VERIFIED with 0 skipped.
#   4. every hooks/*.sh the install placed is referenced under some event key in settings.json,
#      derived from the installed tree -- nothing here is a hardcoded list of hook names.
#   5. skill-mandate.sh blocks a Stop fed a violating fixture transcript, and stays silent on a
#      compliant one. Both directions.
#   6. guard-destructive.sh denies `rm -rf /` and an unqualified force-push to main, and allows
#      an ordinary command. Both directions.
#   7. `vstack trust` refuses without a TTY.
#   8. `vstack update` prints a full diff rather than a filtered allowlist, and refuses to apply
#      unattended.
#   9. install.sh run twice: the second run changes nothing (tree fingerprint, no duplicated
#      rc-file blocks).
#  10. uninstall.sh removes what it installed and restores what it replaced.
#
# Plus one investigative, non-required probe: whether `.claude/verify.sh` check 24 can pass or
# skip during the window a release is cut in -- reported separately from the 10 required
# assertions and never counted toward "declared".
#
# CREDENTIALS: nothing from the host is mounted. No ~/.claude, no API key, no auth. Any lane
# whose assertion needs the `claude` CLI authenticated is reported as unmeasured, not as a pass
# or a skip folded into the totals silently -- see the report this script prints at the end.
#
# Usage: tests/container-matrix.sh [image ...]     (default: the three below)
#   VSTACK_REF=v1.31.0   the tag/branch installed from https://github.com/itsvedantkumar/vstack
#   DOCKER_CONFIG         passed through untouched; set it yourself if your docker needs it
set -uo pipefail
IMAGES=("$@")
[ "${#IMAGES[@]}" -eq 0 ] && IMAGES=(debian:stable-slim alpine:latest ubuntu:latest)
REF="${VSTACK_REF:-v1.31.0}"

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/vstack-container-matrix.XXXXXX")
trap 'rm -rf "$ROOT"' EXIT

DECLARED=0; RAN=0; SKIPPED=0
declare -a LANE_LINES=()
declare -a CONTAINERS=()
cleanup_containers(){
  # "${ARR[@]}" on a still-empty array is unbound under set -u on bash 3.2 (macOS's default
  # /bin/bash), the exact host/container mismatch this script exists to catch elsewhere -- so it
  # has to tolerate it in itself too. The ${ARR[@]+"${ARR[@]}"} idiom expands to nothing at all
  # when the array is unset, instead of erroring.
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
# Alpine ships none of bash, git, jq or curl. Debian/Ubuntu ship bash but none of the rest.
# Installing the linter is best-effort: without it, check 29 of the repo's own gate degrades to
# a real skip, reported as such rather than hidden.
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

# --- the in-container assertion runner: clones from published GitHub and runs assertions 1-10 --
# plus the bonus check-24 probe. Emits RESULT lines this script parses; nothing here trusts the
# container's exit code alone, because a script that dies halfway can still exit 0 from the
# shell's point of view if the last line run happened to succeed.
cat > "$ROOT/assertions.sh" <<'ASSERT_EOF'
#!/usr/bin/env bash
# Runs inside a container. Clones vstack from published GitHub at $VSTACK_REF and exercises
# assertions 1-10 plus a bonus check-24 red-window probe. Prints RESULT lines the host parses.
set -uo pipefail
REF="${VSTACK_REF:-v1.31.0}"
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
  echo "checks: 0 declared, 0 ran, 10 skipped (clone failed)"
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
out=$(/work/repo/.claude/verify.sh 2>&1)
vrc=$?
acct=$(printf '%s\n' "$out" | grep -E '^checks: ' | tail -1)
tail_word=$(printf '%s\n' "$out" | tail -1)
skipped=$(printf '%s' "$acct" | grep -oE '[0-9]+ skipped' | grep -oE '^[0-9]+')
if [ "$tail_word" = "VERIFIED" ] && [ "${skipped:-1}" = 0 ]; then
  res PASS "3-verify-gate" "$acct / $tail_word"
else
  res FAIL "3-verify-gate" "$acct / $tail_word (exit=$vrc); skip reasons: $(printf '%s\n' "$out" | grep '^skip ' | tr '\n' ';')"
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

# --- 5. skill-mandate.sh blocks a violating transcript, passes a compliant one -----------------
MSH="$CDIR/hooks/skill-mandate.sh"
if [ -x "$MSH" ] && command -v jq >/dev/null 2>&1; then
  mkdir -p /tmp/mandate
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"/tmp/mandate/NOTES.md"}}]}}' > /tmp/mandate/violating.jsonl
  printf '%s\n%s\n' \
    '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"/tmp/mandate/NOTES.md"}}]}}' \
    '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"unslop"}}]}}' \
    > /tmp/mandate/compliant.jsonl
  bout=$(printf '{"transcript_path":"/tmp/mandate/violating.jsonl","session_id":"beth-block-%s","stop_hook_active":false}' "$LABEL" | TMPDIR=/tmp bash "$MSH" 2>/tmp/mandate.block.err)
  bdec=$(printf '%s' "$bout" | jq -r '.decision // "none"' 2>/dev/null)
  cout=$(printf '{"transcript_path":"/tmp/mandate/compliant.jsonl","session_id":"beth-ok-%s","stop_hook_active":false}' "$LABEL" | TMPDIR=/tmp bash "$MSH" 2>/tmp/mandate.ok.err)
  if [ "$bdec" = "block" ] && [ -z "$cout" ]; then
    res PASS "5-skill-mandate" "violating=block, compliant=silent(exit0)"
  else
    res FAIL "5-skill-mandate" "violating decision='$bdec' (want block), compliant output='$cout' (want empty)"
  fi
else
  res FAIL "5-skill-mandate" "$MSH missing or not executable, or jq unavailable"
fi

# --- 6. guard-destructive.sh refuses rm -rf /, refuses force-push to main, silent otherwise ----
GSH="$CDIR/hooks/guard-destructive.sh"
if [ -x "$GSH" ] && command -v jq >/dev/null 2>&1; then
  d1=$(printf '%s' '{"tool_input":{"command":"rm -rf /"}}' | bash "$GSH" 2>/dev/null | jq -r '.hookSpecificOutput.permissionDecision // "none"')
  d2=$(printf '%s' '{"tool_input":{"command":"git push --force origin main"}}' | bash "$GSH" 2>/dev/null | jq -r '.hookSpecificOutput.permissionDecision // "none"')
  d3=$(printf '%s' '{"tool_input":{"command":"ls -la"}}' | bash "$GSH" 2>/dev/null | jq -r '.hookSpecificOutput.permissionDecision // "none"')
  if [ "$d1" = deny ] && [ "$d2" = deny ] && [ "$d3" = allow ]; then
    res PASS "6-guard-destructive" "rm-rf-root=deny force-push-main=deny ordinary=allow"
  else
    res FAIL "6-guard-destructive" "rm-rf-root=$d1(want deny) force-push-main=$d2(want deny) ordinary=$d3(want allow)"
  fi
else
  res FAIL "6-guard-destructive" "$GSH missing or not executable, or jq unavailable"
fi

# --- 7. vstack trust refuses without a TTY ------------------------------------------------------
VBIN="$HOME/.config/agents/bin/vstack"
if [ -x "$VBIN" ]; then
  out=$(VSTACK_DIR=/work/repo "$VBIN" trust /work/repo < /dev/null 2>&1); rc=$?
  if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -qiE 'terminal|--yes'; then
    res PASS "7-trust-no-tty" "exit=$rc, refused citing no terminal"
  else
    res FAIL "7-trust-no-tty" "exit=$rc, output: $(printf '%s' "$out" | tr '\n' ' ' | cut -c1-200)"
  fi
else
  res FAIL "7-trust-no-tty" "$VBIN missing"
fi

# --- 8. vstack update prints a full diff, not a filtered allowlist -----------------------------
if [ -x "$VBIN" ]; then
  rm -rf /work/old && git clone --quiet --branch v1.30.0 --depth 1 https://github.com/itsvedantkumar/vstack.git /work/old 2>&1
  if [ -d /work/old/.git ]; then
    nongate=$(git -C /work/old diff --name-only v1.30.0..origin/main -- . ':!install.sh' ':!overlay.sh' ':!uninstall.sh' ':!bootstrap.sh' ':!.claude/verify.sh' 2>/dev/null | head -1)
    out=$(VSTACK_DIR=/work/old "$VBIN" update < /dev/null 2>&1); rc=$?
    got_diff_header=$(printf '%s' "$out" | grep -c 'full diff,')
    got_nongate=0
    [ -n "$nongate" ] && printf '%s' "$out" | grep -qF "$nongate" && got_nongate=1
    if [ "$rc" -ne 0 ] && [ "$got_diff_header" -ge 1 ] && { [ -z "$nongate" ] || [ "$got_nongate" -eq 1 ]; }; then
      res PASS "8-update-full-diff" "printed 'full diff' header; includes non-gate file '$nongate'; refused unattended (exit=$rc)"
    else
      shortcut=""
      printf '%s' "$out" | grep -qi 'already up to date' && shortcut=" -- took the already-up-to-date shortcut: the shallow/single-ref clone from --branch v1.30.0 has no origin/main tracking ref, so the ahead-check silently reads as nothing new and update reinstalls the SAME pinned commit without ever diffing or asking"
      res FAIL "8-update-full-diff" "exit=$rc header_seen=$got_diff_header nongate='$nongate' nongate_seen=$got_nongate$shortcut; tail: $(printf '%s' "$out" | head -1)"
    fi
  else
    res FAIL "8-update-full-diff" "could not clone v1.30.0 as the stale checkout to update from"
  fi
else
  res FAIL "8-update-full-diff" "$VBIN missing"
fi

# --- 9. idempotency: second install.sh run is clean --------------------------------------------
export HOME=/root2; mkdir -p "$HOME"
/work/repo/install.sh > /tmp/idem1.out 2>&1
if command -v sha256sum >/dev/null 2>&1; then SUM=sha256sum; else SUM=shasum; fi
fp(){ find "$1" -type f | sort | xargs $SUM 2>/dev/null | $SUM; }
a=$(fp "$HOME/.claude")
/work/repo/install.sh > /tmp/idem2.out 2>&1; rc=$?
b=$(fp "$HOME/.claude")
zdup=$(grep -c '>>> claude-parity >>>' "$HOME/.zshrc" 2>/dev/null); zdup=${zdup:-0}
if [ "$rc" -eq 0 ] && [ "$a" = "$b" ] && [ "${zdup:-0}" = 1 ]; then
  res PASS "9-idempotent" "second run exit=$rc, tree fingerprint unchanged, .zshrc block not duplicated"
else
  res FAIL "9-idempotent" "second run exit=$rc, fingerprint changed=$([ "$a" = "$b" ] && echo no || echo YES), zshrc-block-count=$zdup"
fi
export HOME=/root

# --- 10. uninstall removes what it installed, restores what it replaced ------------------------
export HOME=/root3; mkdir -p "$HOME/.claude/commands"
echo "MY OWN REVIEW" > "$HOME/.claude/commands/review.md"
/work/repo/install.sh > /tmp/uninst-install.out 2>&1
/work/repo/uninstall.sh --yes > /tmp/uninst.out 2>&1; rc=$?
e=""
[ -e "$HOME/.claude/hooks/verify-gate.sh" ] && e="$e; hooks survived"
grep -q 'MY OWN REVIEW' "$HOME/.claude/commands/review.md" 2>/dev/null || e="$e; user's review.md not restored"
if [ "$rc" -eq 0 ] && [ -z "$e" ]; then
  res PASS "10-uninstall" "uninstall exit=$rc, vstack files removed, user's own file restored"
else
  res FAIL "10-uninstall" "uninstall exit=$rc$e"
fi
export HOME=/root

# --- bonus: check 24 cannot pass or skip during a release (the pins-loop red window) -----------
# Reproduced against a throwaway clone: bump the manifest version and add a matching README pin
# without creating the tag, and show check 24 hard-fails rather than skipping -- the state every
# release passes through between "bump the version" and "push the tag".
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
echo "container totals: $PASS passed, $FAIL failed, $SKIP skipped (of the 10 required assertions + clone + bonus)"
ASSERT_EOF

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
  overall_pass=$((overall_pass+lane_pass)); overall_fail=$((overall_fail+lane_fail)); overall_skip=$((overall_skip+lane_skip))
  RAN=$((RAN+1))

  if [ "$lane_fail" -eq 0 ] && [ "$lane_pass" -ge 10 ]; then
    LANE_LINES+=("ok    $IMAGE (${lane_pass} passed, ${lane_skip} skipped)")
  else
    matrix_ok=0
    LANE_LINES+=("FAIL  $IMAGE (${lane_pass} passed, ${lane_fail} failed, ${lane_skip} skipped -- see the RESULT lines above)")
  fi
done

cleanup_containers

echo
echo "============================================================"
echo "container-matrix summary"
echo "============================================================"
for l in "${LANE_LINES[@]+"${LANE_LINES[@]}"}"; do printf '%s\n' "$l"; done
echo
printf 'assertion totals across all lanes that ran: %d passed, %d failed, %d skipped\n' \
  "$overall_pass" "$overall_fail" "$overall_skip"
echo
printf 'lanes: %d declared, %d ran, %d skipped\n' "$DECLARED" "$RAN" "$SKIPPED"
echo
echo "NOTE: any RESULT line naming 'claude CLI not installed' or similar is unmeasured, not a"
echo "pass -- this harness mounts no credentials on purpose and does not install the claude CLI,"
echo "so lanes that need an authenticated session cannot be exercised here. See the report."

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
