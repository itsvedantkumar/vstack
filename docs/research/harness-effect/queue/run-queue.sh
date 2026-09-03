#!/usr/bin/env bash
# Standing literature queue on the OpenCode Go lane. Drafts one report per topic in topics.tsv,
# gives every landed report an adversarial second reading, and when the queue is dry asks the
# model for six more topics drawn from the open questions in findings/. Runs until $STATE/STOP
# exists. Every job is confined to its own directory under $STATE; the only repo writes are
# copies into literature/ (report and verification), never README.md. `--index` prints the
# README rows for landed files the index does not name yet; `--status` prints the queue.
#
# Not scheduled anywhere: Vedant paused GLM on 2026-09-03 with the weekly quota nearly spent.
# Relaunch detached with:  python3 -c 'import subprocess;subprocess.Popen(["bash","docs/research/harness-effect/queue/run-queue.sh"],start_new_session=True)'
set -u
Q=$(cd "$(dirname "$0")" && pwd); L=$Q/../literature; F=$Q/../findings; RD=$Q/../README.md
STATE=${STATE:-$HOME/.local/state/glm-research}
JOBS=${JOBS:-4}
MODEL=${MODEL:-opencode-go/glm-5.3-flash}
VERIFY_MODEL=${VERIFY_MODEL:-$MODEL}
GEN_COOLDOWN=${GEN_COOLDOWN:-3600}
mkdir -p "$STATE"; touch "$STATE/topics.generated.tsv"

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$STATE/runner.log"; }
slots() { while [ "$(jobs -rp | wc -l | tr -d ' ')" -ge "$JOBS" ]; do sleep 30; done; }
running() { [ -f "$1/pid" ] && kill -0 "$(cat "$1/pid")" 2>/dev/null; }
tries() { cat "$1/tries" 2>/dev/null || echo 0; }

# A draft counts only when it has the shape the brief asked for: sections, sources, length.
accept_draft() {
  [ -s "$1" ] || return 1
  [ "$(wc -l < "$1" | tr -d ' ')" -ge 50 ] || return 1
  [ "$(/usr/bin/grep -c '^## ' "$1")" -ge 4 ] || return 1
  [ "$(/usr/bin/grep -c 'http' "$1")" -ge 8 ] || return 1
}
accept_verify() { [ -s "$1" ] && /usr/bin/grep -qiE '[0-9]+ verified, [0-9]+ misread' "$1"; }

run_job() { # dir model brief-file -> run.log, rc line
  ( cd "$1" && timeout "${JOB_TIMEOUT:-2400}" opencode run -m "$2" --auto --dir "$1" "$(cat "$3")" < /dev/null > run.log 2>&1; echo "rc=$?" >> run.log )
}

draft() { # slug topic seeds
  local d=$STATE/$1
  mkdir -p "$d"
  { cat "$Q/brief-draft.md"; printf '\nTOPIC: %s\n\nSEED SOURCES (verify each; add more):\n%s\n' "$2" "$3"; } > "$d/brief.md"
  rm -f "$d/report.md"
  (
    echo $BASHPID > "$d/pid"
    run_job "$d" "$MODEL" "$d/brief.md"
    if accept_draft "$d/report.md"; then
      cp "$d/report.md" "$L/$1.md"; log "landed $1 ($(wc -l < "$d/report.md" | tr -d ' ') lines)"
    else
      echo $(( $(tries "$d") + 1 )) > "$d/tries"; log "rejected $1 try $(tries "$d"): $(tail -1 "$d/run.log")"
    fi
    rm -f "$d/pid"
  ) &
}

verify() { # slug
  local d=$STATE/verify-$1
  mkdir -p "$d"; cp "$L/$1.md" "$d/report.md"; rm -f "$d/verification.md"
  (
    echo $BASHPID > "$d/pid"
    run_job "$d" "$VERIFY_MODEL" "$Q/brief-verify.md"
    if accept_verify "$d/verification.md"; then
      cp "$d/verification.md" "$L/$1.verification.md"
      log "verified $1: $(/usr/bin/grep -oiE '[0-9]+ verified, [0-9]+ misread[^.]*' "$d/verification.md" | head -1) [$VERIFY_MODEL]"
    else
      echo $(( $(tries "$d") + 1 )) > "$d/tries"; log "verify rejected $1 try $(tries "$d")"
    fi
    rm -f "$d/pid"
  ) &
}

generate() {
  local d=$STATE/generate; mkdir -p "$d"; rm -f "$d/new-topics.tsv"
  for f in "$F"/*.md; do cp "$f" "$d/findings-$(basename "$f")"; done
  all_slugs > "$d/done.txt"
  date +%s > "$d/last"
  (
    echo $BASHPID > "$d/pid"
    run_job "$d" "$MODEL" "$Q/brief-generate.md"
    n=0
    while IFS=$'\t' read -r slug topic seeds; do
      [ -n "$slug" ] && [ -n "$topic" ] && [ -n "$seeds" ] || continue
      case $slug in *[!a-z0-9-]*) continue;; esac
      all_slugs | /usr/bin/grep -qx "$slug" && continue
      printf '%s\t%s\t%s\n' "$slug" "$topic" "$seeds" >> "$STATE/topics.generated.tsv"; n=$((n+1))
    done < "$d/new-topics.tsv" 2>/dev/null
    log "generated $n new topics"
    rm -f "$d/pid"
  ) &
}

all_slugs() { cat "$Q/topics.tsv" "$STATE/topics.generated.tsv" | /usr/bin/grep -v '^#' | cut -f1; }

status() {
  printf '%-40s %s\n' slug state
  while IFS=$'\t' read -r slug topic seeds; do
    [ -n "$slug" ] || continue
    if [ -s "$L/$slug.verification.md" ]; then s=verified
    elif running "$STATE/verify-$slug"; then s=verifying
    elif [ -s "$L/$slug.md" ]; then s=landed
    elif running "$STATE/$slug"; then s=drafting
    elif [ "$(tries "$STATE/$slug")" -ge 3 ]; then s=failed
    else s=queued; fi
    printf '%-40s %s\n' "$slug" "$s"
  done < <(cat "$Q/topics.tsv" "$STATE/topics.generated.tsv" | /usr/bin/grep -v '^#')
}

index() { # README rows for landed files the index does not reference
  for r in "$L"/*.md; do
    case $r in *.verification.md) continue;; esac
    n=$(basename "$r" .md)
    /usr/bin/grep -q "literature/$n.md" "$RD" && continue
    v="$L/$n.verification.md"; c=unverified
    [ -s "$v" ] && c=$(/usr/bin/grep -oiE '[0-9]+ verified, [0-9]+ misread' "$v" | head -1)
    printf '| [`literature/%s.md`](literature/%s.md) | %s | GLM 5.3 Flash | %s |\n' "$n" "$n" "$(head -1 "$r" | sed 's/^#* *//')" "$c"
  done
}

case ${1:-} in
  --status) status; exit 0;;
  --index) index; exit 0;;
esac

log "runner start pid=$$ jobs=$JOBS model=$MODEL verify=$VERIFY_MODEL"
while [ ! -e "$STATE/STOP" ]; do
  busy=0
  while IFS=$'\t' read -r slug topic seeds; do
    [ -n "$slug" ] && [ -n "$topic" ] || continue
    [ -e "$STATE/STOP" ] && break
    if [ ! -s "$L/$slug.md" ] && ! running "$STATE/$slug" && [ "$(tries "$STATE/$slug")" -lt 3 ]; then
      slots; draft "$slug" "$topic" "$seeds"; busy=1
    elif [ -s "$L/$slug.md" ] && [ ! -s "$L/$slug.verification.md" ] && ! running "$STATE/verify-$slug" && [ "$(tries "$STATE/verify-$slug")" -lt 3 ]; then
      slots; verify "$slug"; busy=1
    fi
  done < <(cat "$Q/topics.tsv" "$STATE/topics.generated.tsv" | /usr/bin/grep -v '^#')
  if [ "$busy" -eq 0 ] && [ "$(jobs -rp | wc -l | tr -d ' ')" -eq 0 ] && ! running "$STATE/generate" \
     && [ $(( $(date +%s) - $(cat "$STATE/generate/last" 2>/dev/null || echo 0) )) -ge "$GEN_COOLDOWN" ]; then
    generate
  fi
  sleep 60
done
wait
log "runner stop (STOP present)"
