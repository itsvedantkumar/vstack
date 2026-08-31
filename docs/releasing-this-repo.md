# Releasing this repository

Three harnesses disagree about a release candidate between the moment its version is bumped and
the moment its tag exists. None of them is wrong. They ask different questions, and the answers
genuinely differ in that window: a version is declared, and nothing a stranger can fetch carries
it yet.

This page exists because that ordering has been re-derived from scratch at three consecutive
releases, each time by running something and reading why it was red.

## What each harness does before the tag exists

| harness | pre-tag behaviour | why |
|---|---|---|
| `.claude/verify.sh` check 24 | **skip**, with the reason named | there is no tagged payload to compare the declared version against, so the check says so rather than inventing a verdict |
| `tests/gate-falsifiability.sh` | **refuses to start** on a red gate; its own row 24 skips when the clone has no tags | a suite that mutates the tree cannot tell its own damage from damage that was already there |
| `tests/falsify-parallel.sh` | **refuses to start** on a dirty tree | it clones, so it would test HEAD; a verdict about a different tree than the one you are looking at is not evidence |
| `tests/install-matrix.sh`, `doctor-stranger` lane | **hard fail** | `bin/doctor` asks origin whether the declared tag is fetchable. Pre-tag it is not, and an install URL built from it really does 404. That is true, so it fails |

The install matrix being red here is not a bug to route around. It is the same measurement that
caught four consecutive releases shipping a README URL that 404'd while check 24 was green,
because check 24 can only see this machine and `git ls-remote` can see origin.

## The order that works

`push.followTags` is true globally on the maintainer's machine, so every push in this repository
is explicit about tags or it publishes one by accident.

1. Bump the version in `claude/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` and
   `claude/inventory.json`. Check 13 fails if any of the three disagree.
2. Open the CHANGELOG section. Keep bare `<number> <noun>` phrasing out of it unless the number
   really is a repository total; check 12 reads those as claims about the tree.
3. Advance the README's pin (the `curl` URL and `VSTACK_REF`) to the version being released.
   Check 24 requires the pin to name a tag that exists, so this lands in the same commit as the
   tag, not before it and not after.
4. Recompute the payload digest with `./tests/inventory-contract.sh --print-digest` and write it
   into `claude/inventory.json`. Do not hand-type the recipe; that is a second implementation.
5. Commit.
6. Create the annotated tag **locally**: `git tag -a vX.Y.Z -F - HEAD`.
7. Clone to a scratch directory, check out that commit, and run all three suites there. Never in
   the shared checkout: the falsifiability harness refuses to run while another process is
   mutating a tree that shares its git directory, and it is right to.
8. Push both refs in one atomic operation:

   ```
   git push --no-follow-tags --atomic origin HEAD:refs/heads/main refs/tags/vX.Y.Z
   ```

## What to expect from CI

`resolve` waits for the required checks to decide before publishing, bounded by
`REQUIRE_CHECKS_WAIT_SECONDS` in `.github/workflows/release.yml`. That ceiling has been below the
job it waits for twice, because `verify` grows by roughly a runner minute for every falsifiability
row added and the number was justified against a measurement that then went stale.

Check 58 of `.claude/verify.sh` now derives the floor from the row count in
`tests/gate-falsifiability.sh` and `FALSIFY_SHARDS` in `.github/workflows/verify.yml`, and fails
when the ceiling is under twice that floor, so adding rows or removing shards goes red at commit
time rather than at release time. The check derives a floor, not a measurement: if you want the
real durations, read the whole run and not the job named `verify`, which has been a 4-second join
over the shards since v1.55.0. The query is in the comment beside the value.

The per-row cost that floor is built on lives in `claude/inventory.json` under
`verification.required[falsifiability].cost_model`, with the run id it came from and the check
count it was taken at. Check 58 scales it by the gate's current size, so adding checks moves the
floor on its own; re-derive the recorded numbers when you re-derive the ceiling, and update
`checks_at_measurement` in the same edit or the scaling silently compares against the wrong base.

When `resolve` times out it exits 2 and the caller withholds publication **without deleting the
tag**. The tag survives, nothing is published, and a re-dispatch of the release workflow finishes
the job once the required checks are green. A red verdict deletes; an undecided one does not.
