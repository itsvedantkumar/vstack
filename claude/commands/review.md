---
description: Run a thorough code review on the current changes
allowed-tools: Bash(git*), Read, Grep, Glob, Task
argument-hint: [optional path or PR number]
---

Review the current changes. $ARGUMENTS

Delegate to the `code-reviewer` subagent on the working diff (`git diff` plus staged). If a PR number is given, check it out first. Surface findings ranked by severity with file:line and fixes, then a SHIP / FIX FIRST / RETHINK verdict.

In a Conductor workspace (`CONDUCTOR_WORKSPACE_PATH` set), also post each finding as an inline `mcp__conductor__DiffComment` at its file:line so it shows in the Checks panel; do not post to GitHub unless asked.
