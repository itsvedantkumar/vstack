---
name: goal
description: Execute a goal with mandatory verification at every step. Only stops when fully verified.
---

# /goal — Autonomous Goal Execution

Use when you have a multi-step task that needs rigorous verification.

## Protocol

1. **Plan** — Break goal into atomic steps (1 file change max per step). Define verification criteria upfront.
2. **Execute** — One step at a time. After each: `typecheck && lint && test && build`. Fix on fail, max 3 retries.
3. **Verify completion** — Final: full verification + `trivy fs --scanners secret --quiet .` + `npm audit --audit-level=high` + check `git diff` for unintended changes.
4. **Report** — Only say "done" with evidence from this session.

## Rules
- Max 1 file per step
- Never skip verification
- Never report without evidence
- If stuck >3 min, report and ask
