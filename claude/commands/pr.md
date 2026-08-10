---
description: Open a GitHub PR for the current branch with a real description
allowed-tools: Bash(git*), Bash(gh*), Bash(export PATH*)
argument-hint: [optional title or context]
---

Branch: !`git branch --show-current`
Commits vs main: !`git log --oneline origin/main..HEAD 2>/dev/null || git log --oneline -10`
Diff stat: !`git diff origin/main...HEAD --stat 2>/dev/null || git diff --stat`

Open a PR. $ARGUMENTS

Steps:
1. Push the branch with upstream if needed (`git push -u origin HEAD`).
2. `gh pr create` with a clear title and a body covering: what changed and why, how it was tested, and any risk/rollback note. Keep it tight — no filler.
3. Return the PR URL.
Do not merge.
