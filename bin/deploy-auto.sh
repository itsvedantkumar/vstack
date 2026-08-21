#!/usr/bin/env bash
# Autonomous deploy: verify -> deploy -> health-check -> notify. Detects Vercel / Cloudflare.
set -uo pipefail
# `cd || exit`, because without it a bad path left this running in the caller's directory and
# every step below — verify, detect, deploy — operated on whatever project the shell happened to
# be sitting in. A stale argument could deploy something nobody named.
d="${1:-$PWD}"; cd "$d" || { echo "deploy-auto: cannot enter $d" >&2; exit 1; }
notify(){ osascript -e "display notification \"$1\" with title \"Deploy\" sound name \"$2\"" >/dev/null 2>&1 || true; }
if [ -x .claude/verify.sh ]; then echo "▶ verify"; bash .claude/verify.sh || { echo "✖ verify failed — aborting"; notify "verify failed — aborted" Basso; exit 1; }; fi
url=""
if [ -d .vercel ] || [ -f vercel.json ]; then
  echo "▶ vercel deploy --prod"; url=$(vercel deploy --prod --yes 2>&1 | tee /dev/stderr | grep -oE 'https://[^ ]+' | tail -1)
elif [ -f wrangler.toml ]; then
  echo "▶ wrangler deploy"; out=$(npx wrangler deploy 2>&1); echo "$out"; url=$(echo "$out" | grep -oE 'https://[^ ]+' | tail -1)
else echo "✖ no vercel/cloudflare target"; exit 2; fi
[ -z "$url" ] && { echo "✖ deploy produced no URL"; notify "deploy failed — no URL" Basso; exit 1; }
echo "deployed: $url"
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "$url")
if [ "$code" -ge 200 ] && [ "$code" -lt 400 ]; then echo "✔ health $code — live"; notify "live $code · $url" Glass
else echo "✖ health $code — may be broken (consider: vercel rollback)"; notify "UNHEALTHY $code" Basso; exit 1; fi
