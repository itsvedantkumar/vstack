---
description: Decompose a complex task and run it via parallel subagents
allowed-tools: Task, Read, Grep, Glob, Bash, Edit, Write, TodoWrite
argument-hint: <the goal>
---

Goal: $ARGUMENTS

Run this as an orchestrator, optimizing for speed and token cost:

1. **Decompose** the goal into the smallest set of independent units. State them in one tight list.
2. **Fan out** the independent units NOW — launch them in a single batch of parallel `Task` calls. Use `explorer` (Haiku) for any locate/map/search work, and the specialist subagents (`planner`, `code-reviewer`, `security-auditor`, `debugger`, `test-writer`) for judgment work. Each subagent returns a compact summary, not raw dumps.
3. **Synthesize** the returned summaries into the plan/answer. Keep only conclusions in the main thread.
4. **Execute** the dependent work serially (edits to shared files happen here, one at a time), then verify (build/tests).

Do not read large files or crawl the repo yourself if a subagent can. Do not parallelize writes to the same files. Report the outcome, not the play-by-play.
