---
description: Autonomous prod deploy — verify, deploy (Vercel/Cloudflare), health-check, notify
---
1. Check whether `~/.config/agents/bin/deploy-auto.sh` exists and is executable.
2. If it exists: run `~/.config/agents/bin/deploy-auto.sh "$PWD"` and report URL + health. If it aborts on verify or health-check, surface the failure and STOP — never force-deploy past a failed gate.
3. If it does not exist, state plainly in one line that the deploy-auto helper is not installed and that it ships with the vstack repo's install.sh (github.com/itsvedantkumar/vstack), then do the deploy inline:
   a. If `.claude/verify.sh` exists and is executable, run it. If verification fails, STOP and report the failure — do not deploy.
   b. Detect the deploy target: if `vercel.json` or a `.vercel` directory is present, run `vercel deploy --prod`; if `wrangler.toml` or `wrangler.jsonc` is present, run `npx wrangler deploy`.
   c. Take the resulting deploy URL and health-check it with `curl -o /dev/null -s -w "%{http_code}"`, then report the status code alongside the URL.
