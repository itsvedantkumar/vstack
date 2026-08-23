---
name: push
description: Push with mandatory verification gate running.
---

Push to the current branch. **$ARGUMENTS**

The Stop hook runs automatically when an agent attempts to finish. If `.claude/verify.sh` exists and has been trusted (via `vstack trust`), the hook executes it. If verification fails, the push is blocked and the agent cannot claim the work is done.

1. **Check the working tree.** Run `git status` and abort if there are uncommitted changes or untracked files the push should carry.

2. **Run the verification gate.** Execute `bash ./.claude/verify.sh` and review the output. The gate runs syntax checks on all shell scripts, validation on JSON files, checks for hardcoded secrets and paths, verifies skills are loadable, confirms hook wiring, and runs the installer's dry run. Every check that fails must be fixed before pushing.

3. **Fix failures.** If any check fails, address the root cause. Common failures:
   - Shell syntax errors: run `bash -n <file>` to find the line
   - Secrets in git history: use `git log -p | grep -i 'key\|token\|secret'` to find and remove them, then force-push if necessary
   - Broken skill frontmatter: check the skill's SKILL.md for missing `name:` or `description:`
   - Broken references: verify all skills and agents referenced in prose actually exist on disk

4. **Trust the gate** (one-time per repo). If you see "skipped untrusted .claude/verify.sh", run `vstack trust` to record the script's hash in `~/.config/agents/verify-trust`.

5. **Retry the push.** Once the gate passes, push with `git push`. If you specified a target branch in $ARGUMENTS (e.g. `origin main`), use that; otherwise push to the current remote tracking branch.

The gate is idempotent — running verify.sh multiple times produces the same result. Block the push only on a non-zero exit code.
