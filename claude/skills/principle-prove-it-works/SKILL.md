---
name: principle-prove-it-works
description: "Apply before declaring any task or fix done. Verify the real artifact — run it, read the actual value, inspect the diff — not a self-report, proxy, or 'it compiles.'"
---

# Prove It Works

Verify every task output by checking the real thing directly. Do not infer from proxies, self-reports, or "it compiles."

**Why:** Unverified work has unknown correctness. Indirect verification (file mtimes, output freshness, agent self-reports, cached screenshots) feels cheaper than direct observation. Acting on a wrong inference costs far more than checking the source.

**The Iron Law: no completion claims without fresh verification evidence.** If the proving command was not run in this message, the claim cannot be made — and the rule covers paraphrases, satisfaction ("Done!", "Perfect!"), and implications of success, not just the exact words.

**Pattern:** After completing any task, ask: "how do I prove this actually works?"

The gate, before any status claim: identify the command that proves it → run it fresh and complete → read the full output and exit code → only then state the claim, with the evidence. If the output contradicts the claim, state the actual status instead.

| Excuse | Reality |
|--------|---------|
| "Should work now" / "I'm confident" | Confidence ≠ evidence — run it |
| "Linter passed" | Linter ≠ compiler ≠ tests |
| "Agent said success" | Verify the artifact independently |
| "Partial check is enough" | Partial proves nothing |
| "Just this once" / "I'm tired" | No exceptions |

For regression tests, verify red-green: run the new test (pass) → revert the fix (test MUST fail) → restore (pass). A test never seen failing proves nothing.

Check the real thing, not a proxy:
- Check process liveness directly, not indirectly through derived state
- Read the actual value, not a cached or derived representation
- When verification fails, suspect the observation method before suspecting the system

Code and features:
1. Build it (necessary but not sufficient)
2. Run it and exercise the actual feature path
3. Check the full chain: does data flow from input to output?
4. For integrations, test the full communication path end-to-end

Delegation: trust artifacts, not self-reports.
When verifying delegated work, inspect the actual output artifact (git diff, file contents, runtime behavior), not the delegate's summary. Agents report what they intended, not always what happened.

## Script the check when you can

The strongest proof is a deterministic script that re-runs the same comparison, not a one-time eyeball. Write the script, run it, and keep its output as an artifact a reviewer can re-run instead of trusting your word. A script comparing the old and new compiled output catches what a glance misses.

Prose reminders get skipped under pressure. Put the check where it can't be: an executable `.claude/verify.sh` in the repo root is picked up automatically by the `verify-gate.sh` Stop hook, which runs it before the agent is allowed to finish and blocks with the failure output if it doesn't pass. Write or extend that script instead of re-promising to verify by hand.

Keep the artifact visible for the human. Commit it only for large or complex work where the trail has to be auditable later, like a big port or migration (the **show-me-your-work** skill). Most work just needs it visible, not committed.
