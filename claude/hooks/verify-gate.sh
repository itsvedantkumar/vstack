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
if ! grep -qxF "$h  $v" "$HOME/.config/agents/verify-trust" 2>/dev/null; then
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
tf="$HOME/.config/agents/verify-trust"
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
lock_acquired=0
i=0
while ! mkdir "$lock_dir" 2>/dev/null; do
  i=$((i + 1))
  if [ "$i" -ge 300 ]; then
    # stat -f (BSD/macOS) vs -c (GNU/Linux); `find -mmin` was tried first and dropped because
    # some `find` implementations (e.g. bfs) reject fractional minute arguments outright.
    lm=$(stat -f %m "$lock_dir" 2>/dev/null || stat -c %Y "$lock_dir" 2>/dev/null || echo 0)
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
# Latched open at the cap: the counter file stays put so an unfixable failure blocks at
# most 3 times per session, ever — not in repeating groups of 3. A later real pass below
# removes the file and re-arms the gate.
if [ "$cnt" -ge 3 ]; then
  exit 0
fi
out=$(cd "$d" && bash "$v" 2>&1); rc=$?
if [ "$rc" -ne 0 ]; then
  echo $((cnt+1)) > "$cnt_file"
  reason="Verification failed (.claude/verify.sh exit $rc, attempt $((cnt+1))/3). Fix these before finishing:
$out"
  if [ -n "$JQ" ]; then
    "$JQ" -cn --arg r "$reason" '{decision:"block",reason:$r}'
  else
    printf '{"decision":"block","reason":"%s"}\n' "$(esc "$reason")"
  fi
else
  rm -f "$cnt_file"
fi
exit 0
