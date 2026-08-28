#!/usr/bin/env bash
# Stop hook. Opt-in: acts only if $CLAUDE_PROJECT_DIR/.claude/verify.sh exists & is executable.
# Runs it; if it fails, blocks the agent from finishing and feeds the failure back. Safe no-op otherwise.
# Caps at 3 blocks per session so an unfixable failure can't infinite-loop an overnight run.
set -uo pipefail

# jq was hardcoded to /usr/bin/jq here. That path exists on current macOS and on very few Linux
# hosts, and every jq call in this file failed silently without it — including the one that
# emits the block decision. The gate then looked installed and enforced nothing: a failing
# verify.sh produced no output and the agent finished anyway. Prefer the system binary, fall
# back to PATH, and keep blocking even when neither is there.
JQ=""
if [ -x /usr/bin/jq ]; then JQ=/usr/bin/jq
elif command -v jq >/dev/null 2>&1; then JQ=$(command -v jq); fi

# JSON string escaping for the no-jq path: escape backslash and quote, fold newlines, and drop
# the control bytes that would make the object unparseable.
esc(){ printf '%s' "$1" | tr -d '\000-\010\013\014\016-\037' \
       | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' \
       | awk 'BEGIN{ORS=""}{print (NR>1?"\\n":"") $0}'; }

input=$(cat 2>/dev/null || true)
d="${CLAUDE_PROJECT_DIR:-$PWD}"
v="$d/.claude/verify.sh"
[ -x "$v" ] || exit 0
# Trust gate: this hook fires in whatever repo is open, and a cloned repo's executable
# .claude/verify.sh is arbitrary code — running it silently on every Stop would hand any
# repository author code execution on this machine. Only run scripts the user explicitly
# trusted (`vstack trust`), keyed by content hash so an edited script needs re-trusting.
v=$(cd "$d/.claude" 2>/dev/null && pwd)/verify.sh
[ -f "$v" ] || exit 0
if command -v shasum >/dev/null 2>&1; then h=$(shasum -a 256 "$v" | cut -d' ' -f1)
else h=$(sha256sum "$v" 2>/dev/null | cut -d' ' -f1); fi
# ${HOME:-} rather than $HOME: this file runs under `set -u`, and with HOME absent a bare
# expansion aborts the hook on line 34 -- before it has allowed or blocked anything. The runtime
# gets a shell error and an exit code, not a decision. Defaulting to empty makes the lookup
# resolve to /.config/agents/verify-trust, which does not exist, so the answer is "untrusted":
# no trust store means nothing is trusted, which is the direction this gate must fail in.
if ! grep -qxF "$h  $v" "${HOME:-}/.config/agents/verify-trust" 2>/dev/null; then
  m="verify gate: skipped untrusted .claude/verify.sh (new or changed). Run 'vstack trust' in this repo to arm the Stop-hook gate."
  if [ -n "$JQ" ]; then "$JQ" -cn --arg m "$m" '{systemMessage:$m}'
  else printf '{"systemMessage":"%s"}\n' "$(esc "$m")"; fi
  exit 0
fi
# verify.sh is the entry point, not the whole blast radius: this repo's gate runs
# install.sh --dry-run and overlay.sh, and neither was covered. A verify.sh byte-identical to a
# trusted one would sail through while the scripts it calls had changed underneath. Every
# recorded file inside this repo has to still match, or nothing runs.
root=$(dirname "$(dirname "$v")")
tf="${HOME:-}/.config/agents/verify-trust"
while IFS= read -r line; do
  rh=${line%% *}; rp=${line#*  }
  case "$rp" in "$root"/*) ;; *) continue ;; esac
  [ "$rp" = "$v" ] || [ -f "$rp" ] || continue
  [ "$rp" = "$v" ] && continue
  if command -v shasum >/dev/null 2>&1; then ch=$(shasum -a 256 "$rp" | cut -d' ' -f1)
  else ch=$(sha256sum "$rp" 2>/dev/null | cut -d' ' -f1); fi
  if [ "$ch" != "$rh" ]; then
    m="verify gate: refused to run — ${rp##*/} changed since it was trusted, and .claude/verify.sh executes it. Review the change, then re-run 'vstack trust'."
    if [ -n "$JQ" ]; then "$JQ" -cn --arg m "$m" '{systemMessage:$m}'
    else printf '{"systemMessage":"%s"}\n' "$(esc "$m")"; fi
    exit 0
  fi
done < "$tf" 2>/dev/null

sid=""
[ -n "$JQ" ] && sid=$(printf '%s' "$input" | "$JQ" -r '.session_id // empty' 2>/dev/null)
# A missing session id must not collapse every session onto one shared counter file. It used to
# fall back to the literal "nosess", so three failures anywhere on the machine latched the gate
# off for every session at once. The parent pid is stable within a session and distinct across
# concurrent ones, which is all the counter needs.
[ -n "$sid" ] || sid="pid$PPID"
cnt_file="${TMPDIR:-/tmp}/verify-gate-block-$sid"
lock_dir="$cnt_file.lock"
# Stop hooks from the same session can fire concurrently (parallel sub-agents finishing at
# once), and read-cat-then-write-echo on cnt_file is a classic unlocked read-modify-write: ten
# racing invocations all read the same starting count, each computes its own +1, and the last
# write wins — the counter undercounts and the 3-block cap never engages, so every invocation
# blocks forever instead of latching open after 3. `mkdir` is atomic on every POSIX filesystem
# (exactly one caller sees it succeed), which makes it a lock GNU flock is not required for and
# stock macOS does not need coreutils to get. A lock older than 30s is assumed abandoned by a
# killed sibling rather than honored forever, so a crash can't wedge the gate shut.
# `stat -f` is "file status" on BSD/macOS and "FILESYSTEM status" on GNU coreutils and BusyBox,
# where it ignores %m, prints five lines about the mount, and exits 0 -- so the familiar
# `stat -f %m || stat -c %Y` never falls through on Linux and hands the caller a paragraph where
# it asked for an integer. Measured 2026-08-28 in alpine and postgres:16 containers. GNU first,
# because `stat -c` on macOS is a usage error (rc=1, empty output), which is the honest failure
# the `||` was written for. The digit guard is the part that matters: it rejects anything that is
# not a bare integer, whatever exited 0. verify.sh check 55 executes this function against a stub
# of each documented platform, and finds it by name -- keep the name.
mtime_of() { # <path> -> epoch seconds, or 0 when it cannot be read
  _m=$(stat -c %Y "$1" 2>/dev/null) || _m=""
  case "$_m" in ""|*[!0-9]*) _m=$(stat -f %m "$1" 2>/dev/null) ;; esac
  case "$_m" in ""|*[!0-9]*) _m=0 ;; esac
  printf '%s\n' "$_m"
}
lock_acquired=0
i=0
while ! mkdir "$lock_dir" 2>/dev/null; do
  i=$((i + 1))
  if [ "$i" -ge 300 ]; then
    # `find -mmin` was tried first and dropped because some `find` implementations (e.g. bfs)
    # reject fractional minute arguments outright.
    lm=$(mtime_of "$lock_dir")
    now=$(date +%s)
    if [ "$lm" -gt 0 ] && [ $((now - lm)) -ge 30 ]; then
      rm -rf "$lock_dir" 2>/dev/null
    fi
    i=0
  fi
  sleep 0.02 2>/dev/null || sleep 1
done
lock_acquired=1
trap '[ "$lock_acquired" = 1 ] && rmdir "$lock_dir" 2>/dev/null' EXIT

cnt=$(cat "$cnt_file" 2>/dev/null || echo 0)
case "$cnt" in ''|*[!0-9]*) cnt=0 ;; esac
# B-12: the old cap at cnt>=3 short-circuited with a bare `exit 0` BEFORE verify.sh ran, and the
# only reset was the success branch below — which that same short-circuit made unreachable once
# tripped. A red gate blocked its first 3 Stops, then went silently open for the rest of the
# session no matter how long it stayed red, and a self-planted counter file (same path, computed
# from public constants in this script) reached that state with zero real failures behind it.
# Fixed by decoupling "how often we pay for another verify.sh run" from "what we tell the agent":
# past the cap we still emit decision:block every time, we just reuse the last real result
# instead of re-running verify.sh, and only for as long as that result is fresh. This can no
# longer be used to reach silence — silence only ever comes from verify.sh itself passing when it
# is actually invoked, which is the outcome the gate exists to allow.
ts_file="$cnt_file.ts"
out_file="$cnt_file.out"
last_ts=$(cat "$ts_file" 2>/dev/null || echo 0)
case "$last_ts" in ''|*[!0-9]*) last_ts=0 ;; esac
now=$(date +%s 2>/dev/null || echo 0)
# VSTACK_VERIFY_RESET_SECS, same idiom as VSTACK_DELEGATE_RESET_SECS in skill-mandate.sh: a
# window, not a permanent latch. Below the cap we always re-run for real (cnt<3 below is false
# whenever last_ts is stale or absent, e.g. a self-planted file with no .ts sibling), so this
# only throttles re-checks once a failure has already repeated 3 times in this session.
VERIFY_RESET_SECS="${VSTACK_VERIFY_RESET_SECS:-300}"
recheck_due=1
if [ "$cnt" -ge 3 ] && [ "$last_ts" -gt 0 ] && [ "$now" -gt 0 ] \
   && [ $((now - last_ts)) -lt "$VERIFY_RESET_SECS" ]; then
  recheck_due=0
fi

if [ "$recheck_due" -eq 1 ]; then
  out=$(cd "$d" && bash "$v" 2>&1); rc=$?
  [ "$now" -gt 0 ] && printf '%s' "$now" > "$ts_file" 2>/dev/null
  if [ "$rc" -ne 0 ]; then
    cnt=$((cnt + 1))
    printf '%s' "$cnt" > "$cnt_file"
    printf '%s' "$out" > "$out_file" 2>/dev/null
    reason="Verification failed (.claude/verify.sh exit $rc, attempt $cnt). Fix these before finishing:
$out"
    if [ -n "$JQ" ]; then
      "$JQ" -cn --arg r "$reason" '{decision:"block",reason:$r}'
    else
      printf '{"decision":"block","reason":"%s"}\n' "$(esc "$reason")"
    fi
  else
    rm -f "$cnt_file" "$ts_file" "$out_file"
  fi
else
  # Capped and still within the window: block on the last confirmed-red result without paying
  # for another verify.sh run. Bounds the cost of an unfixable failure the way the 3-block cap
  # always intended to, without ever answering with silence for a gate that is, as far as this
  # hook has actually checked, still red.
  age=$((now - last_ts))
  cached=$(cat "$out_file" 2>/dev/null || echo "(no cached output)")
  reason="Verification is still failing (.claude/verify.sh last confirmed red ${age}s ago, attempt $cnt+). This gate re-runs verify.sh at most once per ${VERIFY_RESET_SECS}s once a failure has repeated 3 times, but it keeps blocking every Stop while red — it does not go silent. Last known failure:
$cached"
  if [ -n "$JQ" ]; then
    "$JQ" -cn --arg r "$reason" '{decision:"block",reason:$r}'
  else
    printf '{"decision":"block","reason":"%s"}\n' "$(esc "$reason")"
  fi
fi
exit 0
