---
description: Run a thorough code review on the current changes
allowed-tools: Bash(git*), Read, Grep, Glob, Task
argument-hint: [optional path or PR number]
---

Review the current changes. $ARGUMENTS

Delegate to the `code-reviewer` subagent on the working diff (`git diff` plus staged). If a PR number is given, check it out first. Surface findings ranked by severity with file:line and fixes, then a SHIP / FIX FIRST / RETHINK verdict.
