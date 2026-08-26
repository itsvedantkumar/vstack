# Worktree collision detection

## The empirical claim, verified

`git rev-parse --git-dir` is **per-worktree**. `git rev-parse --git-common-dir` and
`git worktree list` are **shared across every worktree of one repository**. Verified by creating
a linked worktree of this repo and comparing both from each side:

```
main git-dir:      .git
worktree git-dir:   /Users/you/Projects/vstack/.git/worktrees/wt1
main common-dir:    .git
worktree common-dir: /Users/you/Projects/vstack/.git   (identical, resolved absolute)
`git worktree list` — byte-identical output from both locations, including a THIRD, unrelated
  worktree (/private/tmp/vstack-falsify-19bd268) neither side was told about directly.
```

Anything keyed on `--git-dir` for cross-agent visibility is invisible to a peer working in a
different worktree of the same repo. Anything keyed on `--git-common-dir`, or discovered via
`git worktree list`, is not.

## Where this matters today

`tests/gate-falsifiability.sh`'s collision lock (`LOCK=` at line 87) and `.claude/verify.sh`'s two
reads of it (`_lk=` at line 26, the check-14b probe's `_gd=` at line 700) all currently build the
lock path from `git rev-parse --git-dir`. A falsifiability sweep running in a linked worktree
(e.g. `/tmp/vstack-falsify-19bd268`, referenced in this session's brief) writes a lock that
`.claude/verify.sh` running in the main checkout, or in any other worktree, will never see — the
one situation this lock exists for (a peer's gate run reading a plausible-looking wrong answer
while the sweep is mutating the tree) is exactly the situation it fails to prevent across a
worktree boundary.

**Proposed fix** (not applied — both files are outside this session's ownership): change all
three of

```
tests/gate-falsifiability.sh:87:  LOCK="$(git rev-parse --git-dir 2>/dev/null)/vstack-falsifiability.lock"
.claude/verify.sh:26:             _lk="$(git rev-parse --git-dir 2>/dev/null)/vstack-falsifiability.lock"
.claude/verify.sh:700:             _gd=$(git rev-parse --git-dir 2>/dev/null)
```

to `--git-common-dir`. All three must move together — a writer and a reader on different anchors
never agree, even within the same worktree. `tests/repro/lock-anchor.sh` asserts this both
directions (fails on today's three lines, passes on a corrected copy) and is ready to wire into
`.claude/verify.sh` once the three lines move; wiring it in before that would just make the gate
red for something outside this file's normal work.

## What else was already fixed, found while investigating this

The brief that opened this work described two more defects in `tests/gate-falsifiability.sh`: an
unconditional restore that could destroy a peer's concurrent edit, and no restore on SIGTERM. Both
are **already fixed** in the file as it stands now (`conflict_guard()` — refuses to overwrite a
file whose content no longer matches what this suite itself last wrote there — and
`trap cleanup EXIT INT TERM HUP`, not `EXIT` alone), landed by someone else in this checkout during
this session, after the brief was written and before this investigation reached the file. Nothing
here duplicates or touches that work.

## tests/lib-collision-guard.sh

A sourceable library for any test harness that mutates the shared checkout (not just this one) —
`tests/gate-falsifiability.sh`'s `conflict_guard`/`restore_all`/`trap cleanup EXIT INT TERM HUP`
independently solves the identical problem for its own use; this is the reusable form for a
harness that does not have one yet.

- `cg_save path` — record content + hash before the first mutation.
- `cg_checkpoint path` — call after every mutation; records what "this harness's own last write"
  looked like.
- `cg_restore path` — restore to the pre-`cg_save` content **only if** the file's current bytes
  still match the last `cg_checkpoint` (or `cg_save`, if no checkpoint followed). Otherwise refuse,
  leave the file untouched, name the file on stderr, and keep the harness's own backup at
  `path.cg-orig` for manual recovery. This is the "restore must refuse when the file has changed
  since it was saved" rule from this session's brief, as a reusable primitive.
- `cg_install_trap path...` — arms `EXIT INT TERM HUP` together (not `EXIT` alone) so a killed
  harness still restores.
- `cg_worktree_report` — names a live collision in ANY worktree of the current repo: which PID,
  which lock file, which worktree path it belongs to, and what to do (`ps -p <pid>`, wait). Reads
  `$(git rev-parse --git-common-dir)/vstack-*.lock` and
  `$(git rev-parse --git-common-dir)/worktrees/*/vstack-*.lock`, resolving each worktree's own
  path from git's own `worktrees/<name>/gitdir` plumbing file rather than reimplementing
  `git worktree list` parsing.

`tests/repro/worktree-collision.sh` proves all of the above in a fully sandboxed throwaway repo +
linked worktree (never touches this repo's real `.git`): a clean restore, a refused restore that
preserves a simulated peer's edit, a SIGTERM that still restores, a collision correctly named from
a *different* checkout than the one holding the lock, and no false positive once the lock's holder
is gone.

## Assertion to wire, if wanted

`tests/repro/lock-anchor.sh` is the standalone, both-directions proof for the `--git-dir` ->
`--git-common-dir` fix above. Exact assertion: for each of the three lines named, the line must
contain `--git-common-dir`, not bare `--git-dir`. Fails today (3/3, the real defect); passes on a
corrected copy (proven with an in-memory control case, not just grep-for-the-old-string). Wire it
into `.claude/verify.sh` *after* the three-line patch lands, or now for visibility — RICK's call.
