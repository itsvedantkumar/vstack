---
name: swarm
description: "Use when work splits into independent parts or approaches should be raced — 'in parallel', 'at once', 'all of these', 'try N ways'. Fans out N agents in ONE batched message, returns one table."
---

# Swarm

Fan out N agents at once. They may cover separate slices, race the same brief, or mix both. The parent waits, aggregates, and returns one report.

## The one rule that makes this a swarm

**All N Agent calls go in a SINGLE assistant message as N separate tool uses. One message, N tool_use blocks.**

**If you emit one Agent call, wait for it, then emit the next, you have not swarmed — you have run a slow serial loop wearing a swarm's name.** That is the default failure mode and it is invisible from the outside: the transcript looks busy, the wall-clock cost is N times what it should be, and the race arms can no longer be compared because each one saw the previous one's result.

Concretely, the fan-out turn contains:

```
message: [Agent(brief 1), Agent(brief 2), Agent(brief 3), ... Agent(brief N)]
```

not

```
message: [Agent(brief 1)] → result → message: [Agent(brief 2)] → result → ...
```

Before you send the fan-out turn, count your tool uses. If the count is less than N, stop and rewrite the message. **N briefs, N tool uses, one message.** No exceptions for "let me just check the first one works" — sending a probe agent first and the rest after is the serial loop again.

## When a swarm is the wrong tool

A swarm is one model-driven fan-out: N independent briefs, one aggregation. When the shape is
a *pipeline* — items flowing through stages, loops that run until dry, verify passes gating
each stage, or more arms than you can aggregate in one turn — use the native **Workflow**
tool instead. It runs the orchestration deterministically (script-defined `pipeline()`/
`parallel()`, per-agent models and schemas) where a hand-rolled chain of Agent calls would
drift, serialize, or lose arms. Swarm for one burst; Workflow for a machine.

## Start

Open a todolist with one entry per phase before launching anything.

1. Frame
2. Fan out
3. Aggregate
4. Report

## Phase A: Frame

1. State the done predicate and the artifact or report the swarm must return.
2. **Choose the shape and declare the race rule out loud, in chat, before spawning anything.** Partition into slices, race N agents on identical briefs, or mix both. For a race or mixed shape, name the selection rule now — `first pass`, `rank all`, or `best-of`. Declaring it after results land is how you rationalize a favorite instead of picking a winner.
3. Set N from the user or derive it from the shape. Typical N is 3-8. Above ~10 the aggregation cost exceeds the parallelism win.
4. Pick the agent type and model per arm (see below). For a model race, name each arm's model up front.
5. **Decide who writes.** See "Writes are serial" — this is where a swarm corrupts a repo if you get it wrong.

## Writes are serial. Reads are parallel.

Never fan out two agents that write the same file. Concurrent edits to one file do not merge; the second write silently clobbers the first, and neither agent knows it happened.

- **Reads, searches, audits, reviews, "where is X", "does Y hold across the codebase"** — fan out freely with `subagent_type: "explorer"` (fast and cheap, returns conclusions) or `"Explore"` (broader sweep). Both are read-only by construction, so they cannot collide. This is the safest and most common swarm shape.
- **Writes** — either give each agent a disjoint file set, or give each agent its own writable output directory (`/tmp/swarm-<slug>/worker-<n>/`) or its own git worktree, then merge serially yourself in Phase C. If two arms must produce a competing version of the same file, that is a race: each arm writes to its own directory and you pick one.
- **Shared mutable state that is not a file** counts too: same branch, same dev server port, same database, same lockfile. Partition it or serialize it.

When in doubt, make the agents read-only and do the writing yourself in the parent. A swarm's value is the reading.

## Phase B: Fan out

Send all N `Agent` calls in one message (see the rule at the top). Per call:

- `subagent_type` — `"explorer"` or `"Explore"` for read-only work, `"general-purpose"` for anything that writes, or a specialist where it fits: `code-reviewer`, `security-auditor`, `test-writer`, `debugger`, `planner`, `worker`.
- `model` — `'haiku'` for mechanical sweeps, `'sonnet'` for the default worker, `'opus'` or `'fable'` for arms that need real reasoning. Omit to inherit. Check `~/.claude/CLAUDE.md` for a routing rule before defaulting.
- `run_in_background: true` — this is what lets them actually run concurrently. There is no cloud environment; every agent runs locally.
- `description` — 3-5 words, distinct per arm, so the drain is readable.

Every brief stands alone. The agent sees none of your conversation. Include the goal, the scope, its exact slice or race arm, how to verify, and what to report.

**Cap every brief's output.** Require a summary under ~200 words: verdict, evidence pointers as `file:line` or command output, nothing else. **Explicitly forbid pasting file contents back.** N agents each dumping files is how a swarm burns the parent's context and forces a compaction — the swarm then costs more than doing the work serially.

Reports use `PASS`, `ISSUES`, or `BLOCKED` with evidence.

If an agent drops out or errors, proceed with N-1 and note it in the table. Do not silently relaunch it as a serial straggler unless the slice is required for the done predicate.

## Phase C: Aggregate

Read the returned results. For coverage, every required slice needs a result. For a race, apply the selection rule you declared in Phase A — `first pass`, `rank all`, or `best-of`. Do not paste raw agent dumps.

If arms wrote to separate directories or worktrees, merge the winner in serially now, in the parent. One writer.

Keep a compact result table, one-line evidenced issues, and explicit gaps or dropouts.

## Phase D: Report

Return one consolidated in-chat report: the table, the issue one-liners, gaps or dropouts, and the race rule when one was used.

| # | arm | agent/model | verdict | evidence |
|---|-----|-------------|---------|----------|

## Composing

For a swarm long enough that a human reviews it after stepping away, route the decision trail through the **show-me-your-work** skill — one row per arm launched and per selection call. The parent owns the log; agents do not write to it concurrently.
