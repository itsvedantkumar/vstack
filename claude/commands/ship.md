---
description: Verify, commit, and push — the full ship gate
allowed-tools: Bash, Read, Grep, Glob, Task
argument-hint: [optional commit note]
---

Ship the current work. $ARGUMENTS

Gate (stop and report at the first failure):
1. Detect the project's checks from package.json/Makefile/etc. Run, in order: typecheck, lint, tests, build. Actually run them — do not assume.
2. If anything fails, fix the root cause and re-run. Do not proceed with red.
3. Once green: stage deliberately, commit atomically (conventional message, why-not-what), and `git push`.
4. Report: what shipped, what the checks confirmed, and the pushed commit/branch.

Never `--no-verify`, never force-push a shared branch, never weaken a test to make it pass.
