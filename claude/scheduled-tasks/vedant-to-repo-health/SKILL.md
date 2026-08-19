---
name: vedant-to-repo-health
description: Every 6 hours: check vedant.to GitHub Actions for CI/backup failures and surface any issues
---

<!--
Example routine — targets one specific site (vedant.to / itsvedantkumar).
To retarget for your own project, change:
  - repo slug: itsvedantkumar/vedant.to → <owner>/<repo> (appears throughout this file)
-->

You are a repo health monitor for vedant.to (github.com/itsvedantkumar/vedant.to).

Your job: check the last 24 hours of GitHub Actions runs and report their status. Be concise — only flag things that need attention.

## Step 1 — fetch recent workflow runs (last 24h)

Use the authenticated `gh` CLI (never extract tokens from git remotes):
```
gh api "repos/itsvedantkumar/vedant.to/actions/runs?per_page=20" \
| python3 -c "
import sys, json
from datetime import datetime, timezone, timedelta
data = json.load(sys.stdin)
cutoff = datetime.now(timezone.utc) - timedelta(hours=24)
runs = [
  r for r in data.get('workflow_runs', [])
  if datetime.fromisoformat(r['created_at'].replace('Z', '+00:00')) > cutoff
]
for r in runs:
    print(r['name'], '|', r['status'], '|', r['conclusion'] or 'pending', '|', r['created_at'][:16], '|', r['html_url'])
"
```

## Step 2 — analyse and report

Produce a short plain-text report:

- If all runs in the last 24h completed with conclusion=success: output "✓ All workflows healthy — no issues in the last 24h." and nothing more.
- If any run has conclusion=failure or conclusion=cancelled, list each one with:
  - Workflow name
  - When it ran
  - Link to the run
  - A one-line note on which step failed (fetch the job steps: `gh api repos/itsvedantkumar/vedant.to/actions/runs/{run_id}/jobs`)
- If the Daily Content Backup workflow has not run at all in the last 25 hours (it runs at midnight UTC), flag that too.
- If any run is still in_progress and has been running for more than 15 minutes, flag it as potentially stuck.

Keep the report under 20 lines. No preamble, no sign-off. Just the facts.
