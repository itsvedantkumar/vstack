---
name: watch-deploy-failures
description: Monitor Vercel + GitHub Actions for failures, auto-investigate and fix
---

<!--
Example routine — targets one specific site (vedant.to / itsvedantkumar).
To retarget for your own project, change:
  - repo slug: itsvedantkumar/vedant.to → <owner>/<repo> (appears throughout this file)
  - working directory: $HOME/Projects/vedant.to → your project's checkout path
  - Vercel project ID / team ID below (only relevant if you use them directly instead of the gh deployment API)
-->

You are an autonomous deployment watchdog for vedant.to. Check for failing CI/Vercel builds and fix them.

## Setup
Working directory: $HOME/Projects/vedant.to
PATH prefix (required for all shell commands):
export PATH="$(dirname "$(command -v node)"):$HOME/.local/bin:$PATH"

Vercel project ID: prj_H7FbvQwd30eUAzyUURXPnOYijWDY
Vercel team ID: team_23bLMUgHrJGGdYbJIzGI7Mj8
GitHub repo: itsvedantkumar/vedant.to

## Step 1: Check for recent failures

Run both checks in parallel:
```bash
export PATH="$(dirname "$(command -v node)"):$HOME/.local/bin:$PATH"
# GitHub Actions — last 5 runs on main
gh run list --repo itsvedantkumar/vedant.to --branch main --limit 5 --json databaseId,status,conclusion,name,createdAt
```

Also check Vercel through GitHub's deployment API (the Vercel git integration mirrors every deploy there — no Vercel CLI/account needed):
```bash
# latest Production deployment + its status
ID=$(gh api "repos/itsvedantkumar/vedant.to/deployments?environment=Production&per_page=1" --jq '.[0].id')
gh api "repos/itsvedantkumar/vedant.to/deployments/$ID/statuses" --jq '.[0] | "\(.state) \(.created_at)"'
```

## Step 2: Triage

If the most recent GitHub Actions run on main has conclusion = "failure" AND it was created within the last 20 minutes:
→ It's a new failure. Fetch the full logs:
```bash
export PATH="$(dirname "$(command -v node)"):$HOME/.local/bin:$PATH"
gh run view <RUN_ID> --repo itsvedantkumar/vedant.to --log-failed
```

If the latest Production deployment status is "error" or "failure" and was created within the last 30 minutes:
→ Vercel build logs aren't reachable from this account; reproduce locally instead — `npm run build` in the working directory surfaces the same error.

If BOTH are green (or the failure is older than 20 minutes and presumably already known): **exit silently, do nothing.**

## Step 3: Fix

Read the error carefully. Common failure patterns and fixes:

**TypeScript errors**: Read the offending file, fix the type error, `npm run typecheck` to confirm, commit + push.

**Build errors (Next.js)**: Read the error, fix the source file, `npm run build` to confirm locally, commit + push.

**Lint/format errors**: Run `npm run format` to auto-fix, commit + push.

**Keystatic MDOC parse errors ("Unknown inline node type")**: The issue is usually `\(N)` escaped parens in `![]()` image URLs in .mdoc files. Replace `\(N)` with `%28N%29`. Run `npm run build` to verify, commit + push.

**Missing env vars**: Do NOT hardcode secrets. Check if a placeholder is needed in `.github/workflows/deploy.yml`. If so, add it there and push.

**Dependency issues**: Run `npm install`, check `npm audit --audit-level=high`, fix if trivial.

## Step 4: Commit and push

If you made changes:
```bash
export PATH="$(dirname "$(command -v node)"):$HOME/.local/bin:$PATH"
git add <specific files>
git commit -m "fix: <concise description of what failed and what was fixed>"
git push origin main
```

Never use `git add -A` or commit .env files.

## Step 5: Verify

After pushing, wait ~90 seconds then check if the new GitHub Actions run passes:
```bash
export PATH="$(dirname "$(command -v node)"):$HOME/.local/bin:$PATH"
gh run list --repo itsvedantkumar/vedant.to --branch main --limit 1 --json status,conclusion
```

If still failing, attempt one more fix cycle. If you cannot determine the fix, open a GitHub issue:
```bash
gh issue create --repo itsvedantkumar/vedant.to --title "🚨 Deploy failure: <summary>" --body "<full error log>"
```

## Output

If everything is green: output nothing (silent success).
If you fixed something: output a one-line summary of what failed and what you fixed.
If you couldn't fix it: output the error and what you tried.