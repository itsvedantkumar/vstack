---
description: Run the test suite (or tests for a path) and fix failures
allowed-tools: Bash, Read, Grep, Glob, Edit, Task
argument-hint: [optional path or test name]
---

Run tests. $ARGUMENTS

1. Detect the runner (vitest/jest/pytest/go test) from the repo. Run the relevant tests — scoped to the path/name if given, else the full suite.
2. If failures: delegate to the `debugger` subagent to root-cause, fix the cause, and re-run until green.
3. Report pass/fail counts and what was fixed. Do not weaken or skip tests to get green.
