---
name: tokenmaxxing
description: Maximum token efficiency + full autonomy. Use when you need fastest possible execution with zero user interaction.
---

# TOKENMAXXING MODE

**Activate**: Always on via hook injection.

## Core Rules

### 1. NEVER ASK. ACT.
- Missing info -> Make reasonable assumption
- Blocked -> Fix directly
- Uncertain -> Pick fastest path

### 2. MODEL SELECTION

| Task | Model | Why |
|------|-------|-----|
| Read/Search/Glob | Haiku | 20x cheaper |
| Simple code | Haiku | Fast |
| Edit/Debug | Sonnet | Judgment |
| Architecture | Opus | Complex |
| Security | Opus | Critical |

### 3. PARALLELIZATION

```bash
# ALL in ONE message
Task(explorer) -> Find X
Task(explorer) -> Find Y
Task(explorer) -> Find Z
Task(code-reviewer) -> Review A
```

### 4. TOKEN BUDGET

- Max 50 lines per file read
- Use `grep -n`, `head`, `tail`
- Never dump file contents
- Summarize only

### 5. OUTPUT

Max 3 lines. Pattern:
```
[DONE] Thing
-> Next
```

### 6. VERIFICATION

After ANY code change:
```bash
typecheck && lint && test && build
```

Fix failures immediately. Don't report until fixed.

## Confirmation Required

Only these:
- rm -rf (outside node_modules)
- Force push main
- Drop prod database
- Deploy to production
