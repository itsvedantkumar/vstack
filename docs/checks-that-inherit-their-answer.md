# Checks that inherit their answer

On 2026-08-22 three agents working this repo in parallel found six broken checks in one day. They
looked unrelated while we were finding them. They are one bug.

**A check inherited its verdict from state it did not control and did not assert.**

Every one printed `ok`. None of them was measuring the thing its label named. That is worse than a
missing check, because a missing check is visible in the census and a green one is an active claim
that something was verified.

## The fifteen

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

**The decision nothing downstream honoured.** The destructive guard returns `ask` for the commands
that destroy uncommitted work, and check 23 verifies it returns exactly that, thirty commands
across three tiers, both directions. Under `bypassPermissions` — the mode every unattended agent
runs in — an `ask` decision is auto-approved. Measured: `git clean -fd` ran unprompted and deleted
an untracked file with the guard live and returning `ask`; a `deny` for a force-push to main, in
the same session, blocked the whole tool call. Both halves were correct for months and the join
was never tested. The cost was not hypothetical: on the day this was found, a bare stash took four
agents' uncommitted files and a hard reset from another process wiped a fifth agent's work, and the
guard had answered `ask` for both. Inherited from: a permission mode the decider never read.

**The cap that was clearing by one byte.** Check 18 asserts the session hook's output stays under
4096 bytes. It measured 4095 in the operator's checkout and 4103 in a worktree of the same commit,
because the injected block embeds the absolute repository path twice and the branch name once. The
check was green on one machine, in one directory, on one branch. Anyone cloning to a longer path
got a red gate on a clean tree, and the falsifiability suite could not run at all — it correctly
refuses to mutate a tree that was not green first, which is the only reason this surfaced.
Note the check's own comment already knew the measurement was environment-dependent and applied a
tolerance to the README comparison beside it. The half that was reasoned about was right; the half
next to it inherited the operator's directory name.

**The control that inverted when its fix landed.** `tests/repro/formatter-config.sh` proved it was
not vacuous by reverting to `HEAD:claude/hooks/format.sh` and requiring the attack to reproduce.
The moment the fix was committed, HEAD became the fixed hook, the attack stopped reproducing, and
the repro reported the hole OPEN because its own control had gone green. A no-op detector that
reads `HEAD` measures the tree's history, not the fix, and every fix moves the thing it reads.
Inherited from: which commit happened to be checked out.

**The record that inherited the repository's contents.** `seed_owned_paths()` adopts a pre-1.46.0
install, one that predates ownership tracking, so `uninstall.sh` can later remove it. It decides
whether to run by counting recognisable vstack hook basenames **at the destination**, which is
correct. The five loops that follow then iterate the files the **repository ships** and call
`own()` on each unconditionally, which is true of every path in the tree regardless of what the
run put on disk. On a fingerprinted machine installed with `core`, `team`, or `ui`, the record
therefore claimed every agent, command, and skill in the repository. `uninstall.sh`'s skills loop
trusted that record on its own and `rm -rf`'d on a name match, so a user directory called
`brainstorming` was removed without its contents ever being compared. The comment above
`owns_path()` asserted the invariant the seeder breaks, in the present tense, as the reason the
loop is safe. No check caught it because check 45 and the profile round-trips all start from a
machine with no prior install, where the fingerprint reads zero and the seeder returns before its
first loop. Inherited from: what the repository contains, standing in for what the run installed.

**The tree-clean invariant that cannot see a directory.** Harnesses here plant a defect, measure,
restore, and then prove they restored it by comparing `git status --porcelain` before and after.
`tests/inventory-fixture.sh` did exactly that and reported `ok  git status --porcelain unchanged`
in the same run whose own control caught `.claude/verify.sh` returning four FAIL lines where it
had returned two. Both statements were true. **Git does not track empty directories**, so the
`mkdir -p claude/skills/vstack-fixture-skill` that `do_plant()` created and `do_unplant()` never
removed was invisible to porcelain and plainly visible to every consumer that globs the
filesystem. Each family's plant contaminated the next family's baseline, and
`tests/plugin-manifests.sh` was recorded as blind six times for failures the harness itself had
caused. Reproduced in isolation: against a clean worktree, `mkdir -p
claude/skills/vstack-fixture-skill` leaves `git status --porcelain` empty and takes
`plugin-manifests.sh` to `exit=1` with two FAIL lines. Note what caught it. Not the tree-unchanged
control, which is the check written for this exact purpose and which passed; the *positive
control* running an unrelated gate noticed the answer had moved. `tests/gate-falsifiability.sh`
carries the same porcelain-based invariant at :191 and :836 and is not known to be exposed, only
because its mutations happen to edit files that already exist, which is a property nothing in it
enforces. Inherited from: what git chooses to report, standing in for what is on disk.

**The refusal that ends without a verdict.** `.claude/verify.sh` refuses to run while another
process holds the falsifiability lock: it prints `REFUSED`, explains why, and exits 2. Correct on
every count, and it still produced a false green on 2026-08-27. The refusal's last line was "Wait
for it to finish", so the output ended with no verdict at all. Read the way people actually read
gate output -- tail the last lines, count the `FAIL` lines -- a refusal is indistinguishable from a
clean run: zero failures, no complaint. That reading went into a commit message as "Gate: 48
declared, 47 ran, 1 skipped, VERIFIED", in a commit whose subject was about labels overstating what
they assert, written by the person who had spent the day fixing exactly this. The exit code was
right the whole time; nothing read it. The fix is a `NOT RUN` terminator in the position a real run
puts `VERIFIED`, and an assertion on the refusal's LAST line, not just its first (row 14c). Note
what this one costs to find: no check was wrong, no mutation would have caught it, and the
falsifiability suite was green throughout. What failed was the human protocol around a correct
program. **A discipline that has to be remembered is not a control**, and this catalogue now has
two entries -- this and the empty-directory one -- where the defect was in how a true statement
was read rather than in whether it was true.

**The backup directory that exists and is empty.** `install.sh` ends a successful run with
`backup: /Users/you/.config/agents/backups/install-20260827-051816`, and `abort_note` promises that
"every file this run touched was copied there first". Both statements were true about the
directory and false about its contents. `back()` calls `own "$1"`, which appends the path to the
ownership record, and then asks that record whether an *earlier* install claimed the path. It had:
two lines up, in this run. The guard matched every path on every call and `back()` returned before
its `cp`. No file was ever backed up, on any machine, from the moment the ordering changed. What
makes it belong here rather than in a changelog is the reporting: the directory is real, the path
is real, the announcement is accurate, and the only thing missing is the thing the announcement is
for. `.claude/verify.sh` was `48 declared, 48 ran, 0 skipped, VERIFIED` throughout, which is not a
gate defect -- install lanes belong to `tests/install-matrix.sh` by a stated division -- and the
matrix did go red, on all three platforms, within fifteen minutes of the push. It was read
fourteen hours later. The check worked; nobody read the remote. Pinned by
[`../tests/repro/backup-self-claim.sh`](../tests/repro/backup-self-claim.sh), which asserts the
copy's *bytes*, because a directory containing a post-overwrite copy is the same lie one level
down.

**The check that graded a different copy of the thing than the one it set up.** Check 49 stubs
`gh`, computes this checkout's `HEAD`, and asks `bin/doctor` whether the CI verdict it reports
belongs to that commit. `resolve_vstack_repo()` prefers `~/.config/agents/vstack-repo` -- wherever
`install.sh` last ran from -- over the location of `bin/doctor` itself, so doctor answered about the
installed tree while the harness had stubbed the tree under test. The two agreed for exactly as long
as they were the same directory. Running the check from an isolated clone separated them and three
of five cases went red, including both positive controls. Inherited from: which checkout the
operator happened to have installed. Fixed by pinning `VSTACK_DIR` to the tree under test.

**The published figure compared against a machine-dependent measurement.** Check 18's cap lane was
fixed once already for exactly this: the session hook splices `$root`, `$branch` and `$base` into
the block it measures, so a raw byte count is partly a measurement of the operator's directory name.
The fix normalized `$root` and `$branch` out and explicitly left `$base` in, on the stated grounds
that the remote's default branch "does not vary with this checkout." It varies with the remote,
which is no less environmental, and it is spliced three times. Meanwhile the published-figure lane
was never converted at all and went on comparing the README against the raw count. The result: the
check passed at 4077 B on the author's directory on `main` (3.9 KB, inside a 0.15 KB tolerance) and
failed at 4163 B in a clone three characters longer whose `origin/HEAD` named a 24-character branch
(4.1 KB). A green that was a property of where it ran. Inherited from: the checkout path, the branch
name, and the remote's default branch. Fixed by subtracting all three and publishing the invariant
count, which is 3990 B in every checkout tested. Row 18d splices `$base` a fourth time so the
correction can never again fall behind what the hook adds.

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

**Does it pass when run by hand?** That is not evidence. Five of the nine above passed by hand. Run
it the way the harness runs it, with the environment the harness has.

## Why this repo keeps finding it

Because it keeps looking. Every entry above was found by a falsifiability suite whose only job is to
break each check and confirm it notices, and the most instructive entry is the one where **the
suite's own row was the fake green**. A falsifiability harness cannot take its own rows on trust
either.

The generalisation is worth more than any individual fix: the fixes are six lines of shell, and the
shape will produce a seventh instance next month in a check nobody has written yet.

It produced five, in two days, five weeks early. Four of the last five were found on 2026-08-26, in
an audit looking for something else, and the fifth on 2026-08-27 by committing it. The sixth
that day was found by a remote CI job that had been red for fourteen hours. One of them had been inert since the guard was
written, and the last of the four was found by a positive control rather than by the check written
for that exact purpose, which passed. Reread this page before trusting a check you did not watch
fail.

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
