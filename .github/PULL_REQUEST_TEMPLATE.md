## What was broken

<!-- The defect, not the change. If this is a feature, say what was not possible before. -->

## How you know

<!-- Paste the command and its real output. Not "tests pass" — the output. -->

```
```

## What now catches it

<!-- Which check fails if this regresses, and which mutation row proves that check can fail.
     "None" is a valid answer for docs-only changes. -->

## Gate

- [ ] `./.claude/verify.sh` ends VERIFIED with 0 skipped
- [ ] `./tests/gate-falsifiability.sh` ends FALSIFIABLE with the tree unchanged
- [ ] New checks have a mutation row, watched red before green
- [ ] Counts in README and manifests moved in the same commit if they changed
