# Checks that inherit their answer

On 2026-08-22 three agents working this repo in parallel found six broken checks in one day. They
looked unrelated while we were finding them. They are one bug.

**A check inherited its verdict from state it did not control and did not assert.**

Every one printed `ok`. None of them was measuring the thing its label named. That is worse than a
missing check, because a missing check is visible in the census and a green one is an active claim
that something was verified.

## The six

**The anchor a prose edit moved.** Check 18 compares the README's published context cost against a
live probe of the session hook, guarded by `grep -qE '~[0-9.]+ KB full / ~[0-9.]+ KB plugin'` with
no `else`. Commit cc76ba8 rewrote the README and the phrasing changed. The comparison stopped
happening and the check went on printing `ok` for eleven commits. Inherited from: the wording of a
document the check does not own.

**The commit boundary that only closes too late.** Check 24 diffs `v$version..HEAD` for payload
drift. Run it on a dirty tree and your uncommitted work is not in `HEAD`, so it compares against
nothing and passes. Commit, and the identical tree goes red. The check becomes able to fail at the
exact moment it is too late to act on. Inherited from: whether the caller had committed yet.

**Silence read as success.** Check 29 treated a tool producing no output as a tool finding no
problems. A tool that is absent, misconfigured, or exiting early produces exactly the same silence.
Inherited from: whether a binary was installed.

**The validator that agreed with everything.** Check 19 delegates to `claude plugin validate`. On CI
it printed `ok` against a manifest the falsifiability suite had deliberately broken, because the
validator exited 0 there while the same version rejected the same manifest locally. Inherited from:
a third party's exit code, trusted without a control.

**The mutation something downstream undid.** Falsifiability row 34 planted a `.claude/CLAUDE.md`
five lines above the `rm -f` that exists to clear exactly that file. The planted defect was gone
before the check looked at it. Green row, zero evidence. Inherited from: an unrelated cleanup step
running between the mutation and the measurement.

**The verdict read out of the caller's environment.** Check 14b was written specifically to catch
fake greens, and was one. Its probe switched the harness-bypass path with
`env ${2:+VSTACK_FALSIFY=1}`, but the harness exports `VSTACK_FALSIFY=1` for every gate run it
makes, so the nested call inherited it no matter what the probe set. Its three assertions collapsed
into three copies of the same one. It passed by hand, because the hand running it had no
`VSTACK_FALSIFY` set, and failed the first time the harness ran it. Inherited from: an environment
variable the check neither set nor cleared.

## The test

Before believing any check, ask: **what in the environment could make this print `ok` without
measuring anything?** Then assert that thing.

In practice that is four questions.

**Does it read its subject from something it does not own?** Prose, a filename, an env var, a
version string. If yes, the absence of that subject must fail, not skip. `if guard; then compare;
fi` degrades to silence the moment the guard stops matching, and prose moves.

**Can it produce its verdict without the thing under test existing?** A tool that is missing, a diff
that is empty because nothing was committed, output that is silent because the binary was never
installed. Distinguish "measured and fine" from "could not measure" and report them differently.
Skips are counted here for exactly this reason.

**Does it delegate judgment?** Then it needs a control in both directions. A validator that accepts
everything and a validator that rejects everything are each indistinguishable from a healthy repo
unless you hand it a known-good and a known-bad and require the right answer on both.

**Does it pass when run by hand?** That is not evidence. Five of the six above passed by hand. Run
it the way the harness runs it, with the environment the harness has.

## Why this repo keeps finding it

Because it keeps looking. Every entry above was found by a falsifiability suite whose only job is to
break each check and confirm it notices, and the most instructive entry is the one where **the
suite's own row was the fake green**. A falsifiability harness cannot take its own rows on trust
either.

The generalisation is worth more than any individual fix: the fixes are six lines of shell, and the
shape will produce a seventh instance next month in a check nobody has written yet.

## Related

- The literature this repo surveyed on whether a harness helps at all is in
  [`research/harness-value-literature-2026-08.md`](research/harness-value-literature-2026-08.md).
  Its single most decision-relevant finding rhymes with this page: prose instructions telling an
  agent to be careful measured *worse* than no intervention, while a retrieval step that ran
  something cut the same failure by 70%. Exhortation and a check that cannot fail have the same
  defect, which is that neither is connected to the outcome it names.
- What that survey changed, and did not, is in
  [`research/what-we-changed-2026-08-22.md`](research/what-we-changed-2026-08-22.md).
- A guard can inherit its answer from the wrong scope rather than the wrong source. The
  falsifiability lock keyed on `git rev-parse --git-dir`, which returns a different path inside
  every linked worktree, so two sessions each held a lock neither could see and both believed
  they had the tree to themselves. Measured, with the resolution, in
  [`worktree-collision-detection.md`](worktree-collision-detection.md).
