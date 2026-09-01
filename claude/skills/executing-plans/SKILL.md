---
name: executing-plans
description: "A written plan or numbered task list already exists and the ask is to carry it out: work the tasks in order, verify each, pause at the review checkpoint between phases."
---

> **Ported here, and some of what it names is not.** This skill comes from upstream, where it
> sits beside sibling skills this port does not vendor. Any `superpowers:<name>` or
> `elements-of-style:<name>` reference below that does not match a skill you actually have is
> **not available here** — do not try to invoke it. Where one is named as a required step, do
> the work it describes directly instead, or use the closest skill that is installed. Run
> `ls ~/.claude/skills` to see what you have.

# Executing Plans

## Overview

Load plan, review critically, execute all tasks, report when complete.

**Announce at start:** "I'm using the executing-plans skill to implement this plan."

**Note:** Tell your human partner that plan execution works much better with access to subagents. The quality of its work will be significantly higher if run on a platform with subagent support (such as Claude Code). If subagents are available, dispatch each task to a fresh subagent via the Agent tool instead of executing tasks inline in this session.

## The Process

### Step 1: Load and Review Plan
1. Read plan file
2. Review critically - identify any questions or concerns about the plan
3. If concerns: Raise them with your human partner before starting
4. If no concerns: Create TodoWrite and proceed

### Step 2: Execute Tasks

For each task:
1. Mark as in_progress
2. Follow each step exactly (plan has bite-sized steps)
3. Run verifications as specified
4. Mark as completed

### Step 3: Complete Development

After all tasks complete and verified:
- Verify the implementation: run typecheck, lint, and all tests
- Commit changes to the branch with descriptive messages
- Open a pull request or merge per your repository's convention

## When to Stop and Ask for Help

**STOP executing immediately when:**
- Hit a blocker (missing dependency, test fails, instruction unclear)
- Plan has critical gaps preventing starting
- You don't understand an instruction
- Verification fails repeatedly

**Ask for clarification rather than guessing.**

## When to Revisit Earlier Steps

**Return to Review (Step 1) when:**
- Partner updates the plan based on your feedback
- Fundamental approach needs rethinking

**Don't force through blockers** - stop and ask.

## Remember
- Review plan critically first
- Follow plan steps exactly
- Don't skip verifications
- Reference skills when plan says to
- Stop when blocked, don't guess
- Never start implementation on main/master branch without explicit user consent

## Integration

**Around this skill:**
- **writing-plans** (a real skill here) creates the plan this one executes.
- Isolated workspace: under Conductor each workspace is already a worktree. Outside it, `git worktree add`.
- Finishing: verify with typecheck, lint and tests, commit, then merge or open a PR per the repo's convention.

Only the first is a skill you can invoke. The other two are things you do, named here so the
sequence is legible.
