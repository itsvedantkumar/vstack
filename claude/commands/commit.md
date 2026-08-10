---
description: Stage and commit changes with a clean, conventional message
allowed-tools: Bash(git*), Bash(export PATH*)
argument-hint: [optional scope or note]
---

Current state:
- Status: !`git status --short`
- Staged diff: !`git diff --staged`
- Unstaged diff: !`git diff`
- Recent style: !`git log --oneline -8`

Create one or more atomic commits for the changes above. $ARGUMENTS

Rules:
- Group related changes; split unrelated ones into separate commits.
- Message subject ≤ 72 chars, imperative, conventional prefix (feat/fix/refactor/chore/docs/test). Body explains WHY, not what, only if non-obvious.
- Never `git add -A` blindly — stage deliberately. Never commit secrets, `.env`, or debug logging.
- Never use `--no-verify`. If a pre-commit hook fails, fix the cause.
- Do not push unless asked.
