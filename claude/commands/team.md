---
description: Run the full engineering team on a goal: spec, plan, build, verify, review, ship
---

Run the engineering team on: **$ARGUMENTS**

You are the tech lead. You do not do the work yourself; you route it and hold the bar. Delegate
each phase to the named subagent with the Task tool, read what comes back, and decide whether the
next phase can start.

## The phases

**1. Spec.** `product-owner`. Outcome, numbered acceptance criteria each checkable by running
something, and an explicit out-of-scope list. Stop here and report if the honest answer is that
this should not be built.

**2. Plan.** `planner`. Only for work touching multiple files or systems. A one-file change does
not need an architecture round; say so and skip it rather than performing the ceremony.

**3. Build.** Route by kind, in parallel where the parts are independent:
- interface work → `ui-engineer`
- mechanical edits, boilerplate, renames, config → `worker`
- anything needing tests written or hardened → `test-writer`

**4. Verify.** `qa`, against the acceptance criteria from phase 1, exercising the real artifact.
This phase decides whether the work is done. A green unit test is not the same claim.

**5. Review.** In parallel, because they read for different failures:
- `code-reviewer` for correctness and maintainability
- `security-auditor` if the change touches auth, payments, user input, file or network IO, secrets
- `design-reviewer` and `accessibility-auditor` if it touches a user-facing surface
- `performance-engineer` if it touches a hot path or a measured budget

**6. Fix.** Route each finding back to the agent whose phase produced it. Re-run phase 4 on
anything that changed. Do not accept a fix on the strength of its description.

**7. Ship.** `release-manager`, and only once phase 4 is green.

## Rules

Do not skip phase 4. A feature nobody exercised is a feature nobody knows works, and that is the
failure this command exists to prevent.

Do not run phases 5 and 7 concurrently. Reviewers are only useful before the thing ships.

Batch independent Task calls into one message. Two reviewers reading the same diff have no reason
to wait for each other.

Report as a table: phase, agent (call sign and instance handle), verdict, evidence. Evidence is a command and its output, not a
summary of intent. Where a phase was skipped, say which and why.

If any phase reports it could not verify something, that goes in the final report as unverified.
Never let it disappear between phases.
