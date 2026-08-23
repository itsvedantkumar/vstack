---
name: deploy
description: Deploy to production (Vercel, Cloudflare, Railway, Fly) with verification.
---

Deploy to production. **$ARGUMENTS**

Deployment is handled by the `deploy-auto` command, which auto-detects your deployment platform (Vercel, Cloudflare Workers, Railway, or Fly.io) and runs the full verification gate before deploying.

1. **Check that the project is deployable.** The deploy-auto helper lives at `~/.config/agents/bin/deploy-auto.sh` (installed by vstack's `install.sh`) or is inlined below if not present.

2. **Run deploy-auto.sh** with the project directory:
   ```bash
   ~/.config/agents/bin/deploy-auto.sh "$PWD"
   ```
   The script will:
   a. Run `.claude/verify.sh` if it exists. If verification fails, stop and report the failure.
   b. Auto-detect the deployment target: if `vercel.json` or `.vercel/` exists, use Vercel; if `wrangler.toml` or `wrangler.jsonc` exists, use Cloudflare Workers.
   c. Run the deploy command for that platform.
   d. Health-check the resulting URL (HTTP status code).
   e. Report the deployment URL and health status.

3. **If deploy-auto.sh is not found,** run verification and auto-detect inline:
   ```bash
   bash ./.claude/verify.sh && \
   if [ -f vercel.json ] || [ -d .vercel ]; then
     vercel deploy --prod
   elif [ -f wrangler.toml ] || [ -f wrangler.jsonc ]; then
     npx wrangler deploy
   else
     echo "No deployment config found (vercel.json, .vercel/, wrangler.toml, or wrangler.jsonc)"
     exit 1
   fi
   ```

See `deploy-auto.md` for the full details.
