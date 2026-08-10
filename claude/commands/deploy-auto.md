---
description: Autonomous prod deploy — verify, deploy (Vercel/Cloudflare), health-check, notify
---
Run `~/.config/agents/bin/deploy-auto.sh "$PWD"` and report URL + health. If it aborts on verify or health-check, surface the failure and STOP — never force-deploy past a failed gate.
