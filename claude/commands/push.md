---
name: push
description: Push with mandatory verification. No broken code.
---

# Push Command

## Usage

```bash
/push
/push origin main
```

## What Happens

1. Run typecheck
2. Run lint
3. Run tests
4. Run build
5. If ALL pass → push
6. If ANY fail → abort, show error

## Implementation

The pre-push hook runs automatically.

```bash
# Git hook setup (one-time)
git config core.hooksPath ~/.100xprompt/hooks
```

Or use script directly:

```bash
~/.100xprompt/hooks/pre-push.sh && git push
```

## Never Push Broken Code

If verification fails:
1. Hook blocks push
2. Shows which check failed
3. You fix
4. Retry push

No manual review needed. Tests catch everything.
