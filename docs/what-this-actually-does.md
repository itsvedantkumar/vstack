# What this actually does

**There is no evidence this configuration improves output quality on a frontier model.** Three
separate local benchmarks failed to show a gain. A review pathway scored 11/15, 11/15 and 10/15
across none, vstack and gstack, with zero skill invocations in sixty runs. A regression-aware
SWE-bench Lite scoring tied all four arms at zero. A false-completion pilot tied the baseline at
0/12 and vstack at 0/9 before the run was interrupted. `docs/research/` explains why. On
small, well-specified, single-file tasks a frontier model is already near ceiling, and a ceiling
leaves no headroom for a config layer to show up in.

What this repository can show is narrower and checkable. Specific mechanisms do specific things,
each with the evidence that proves it and the date it was measured. That is what follows, in
three categories kept strictly apart: a number that exists, a mechanism that runs with no
measured effect, and a question still open.

Every row cites a check number, a test file, a commit-dated CHANGELOG entry, or a number with the
command that produced it. A row without one of those does not appear here.

## 1. Measured

A number exists, sourced, dated.

| Claim | Evidence | Source, date |
|---|---|---|
| The gate is 42 checks, all currently green. | `./.claude/verify.sh` prints `checks: 42 declared, 42 ran, 0 skipped` and `VERIFIED`, run against this tree at v1.38.0. | Run 2026-08-23 |
| Every one of those 42 checks has a falsifiability row that has been watched going red. `tests/gate-falsifiability.sh` breaks exactly what each check watches, requires the gate to name it, and restores the file byte for byte. Check 16 fails the gate if a check has no such row. | `tests/gate-falsifiability.sh`, `tests/README.md`, README.md "Checks that can fail" | Mechanism as of v1.38.0. Suite not re-run for this document, see note below |
| `principle-type-system-discipline` almost never fired: 1/10 at n=10. Rewriting its description around the literal nouns a user types ("a struct, enum, or type can hold an invalid combination of fields") moved it to 9/10, matching the control. The identical rewrite method applied to `principle-build-the-lever` did not move it. That skill scored 2/10 before and after, exactly at the pre-registered falsification floor, and the rewrite was reverted rather than shipped. | CHANGELOG.md, "1.38.0" | 2026-08-23 |
| `principle-prove-it-works` scored 0/10 on its own fixture prompt, because its trigger condition is about the assistant's own closing claim, not anything a skill matcher can see in the user's prompt. Replaced with a direct Stop-hook check (`prove-it-works`) rather than a rewritten description. | CHANGELOG.md, "1.37.0" | 2026-08-23 |
| The container matrix's first run against published GitHub tags found two shipped defects. `bin/doctor` exited 1 on a clean Alpine install because its 45-day-cutoff `date` fallback chain covered BSD and GNU but BusyBox understands neither `date -v-45d` nor `date -d '45 days ago'`. And `vstack update`, run by anyone following the README's own documented pin quickstart (`VSTACK_REF=vX.Y.Z bash bootstrap.sh`), reported "already up to date" forever regardless of how far behind `main` the pinned checkout had drifted, because the shallow clone's refspec never fetches `origin/main` and the comparison failed silently with stderr discarded. | CHANGELOG.md, "1.33.0", and `tests/container-matrix.sh` | 2026-08-23 |
| Eight routing entries, 8 of 28 skills and 28.6% of the library, named skills without the `principle-` prefix their directories actually carry (`fix-root-causes` instead of `principle-fix-root-causes`, and seven more), so a model told to invoke them could not resolve the name. The check meant to catch this, check 7, was more forgiving than the runtime: it tried both the bare and prefixed form, so it reported the broken prose as clean. Found by running `tests/auto-trigger.sh`, which nothing in CI runs. | CHANGELOG.md, "1.35.0" | 2026-08-23 |
| The delegation and agent-naming mandates in `skill-mandate.sh` counted only tool_use blocks named `Task`, the classic CLI's dispatch-tool name. This SDK build emits `Agent`. Measured against a real 15MB transcript: 70 `Agent` dispatches, 0 `Task` matches. The agent-naming mandate, gated on that same count being at least 1, was structurally unable to fire in any install since it shipped, despite call-sign naming being a standing, specific request. | CHANGELOG.md, "1.37.0" | 2026-08-23 |
| The three `bin/` CLI wrappers claimed success when nothing happened. `tests/bin-scripts.sh`, run for the first time against local stubs, found 17 failures across all three. | CHANGELOG.md, "1.32.0" | 2026-08-23 |
| The 300K context-compaction window setting binds on roughly one session in five. Scanning 120 real transcripts under `~/.claude/projects`, 20% exceeded 230K tokens (where the setting starts to matter) and 7% exceeded 680K (where the old, effectively-unset default would have). The two largest peaked at 999,445 and 997,674 tokens. | CHANGELOG.md, "1.34.0" | 2026-08-23 |
| A length-triggered nudge toward `grill-me` was outranking situation-matched skill routing. Run against the 28-case `tests/auto-trigger.sh` suite, it scored 19/28, with `grill-me` firing instead of the right skill in 9 of the failures. After the nudge was changed to yield when a more specific skill matches, the same suite scored 22/28 and the hijack count went to zero. One unrelated case flipped the other way in the same run, noted rather than hidden. | CHANGELOG.md, "1.34.0" | 2026-08-23 |
| With the routing table in `inject-session-context.sh` present, a 9-case ablation subset of `tests/auto-trigger.sh` fired the expected skill 9/9. With the table removed, 7/9. `technical-writing` and `typescript-best-practices` never fired without it. | `docs/how-skills-fire.md` | Dated within the v1.34.0-v1.35.0 window (2026-08-23). Exact run date not separately recorded in that file |
| The destructive-command guard decides correctly on a fixed set of 30 shell command strings across 3 tiers (deny, ask, allow), including under a stripped environment (`-u TMPDIR -u HOME -u USER -u LANG`) and malformed or empty input. | `.claude/verify.sh` check 23, run 2026-08-23, currently `ok` | 2026-08-23 |
| No configuration outperformed the unconfigured baseline on a planted-defect code review: 11/15 (none), 11/15 (vstack), 10/15 (gstack), across 4 fixtures times 5 samples times 3 arms, Claude Opus 5, zero false positives in any arm. The explanation is in the validity column, not the score. Zero `Skill` tool_use calls fired in any of the 60 runs, in any arm. The review path tested here is a subagent reached through the dispatch tool, not a skill, so this measured skills that were present and idle. | `tests/evals/RESULTS.md`, "Run of 2026-08-21", and CHANGELOG.md line 1622 | 2026-08-21 |

## 2. Mechanism works, effect unmeasured

The thing does what it says. Nobody has shown it changes an outcome.

| Mechanism | What it verifiably does | What is not measured |
|---|---|---|
| Destructive-command guard (`claude/hooks/guard-destructive.sh`) | Denies `rm -rf /`, `rm -rf ~`, force-pushes to `main`, `master` or `HEAD:refs/heads/main`, and asks before `git reset --hard`, `terraform destroy`, wildcard staging outside the current workspace, and similar. Verified against 30 fixed commands (check 23, above) and against a stripped environment. | Whether it has intercepted a real destructive command in practice, or whether agents behave any differently with it installed than without. |
| Stop-hook gate (`claude/hooks/verify-gate.sh`) | Blocks the agent's Stop event when the repository's `verify.sh` fails, in both jq-present and jq-absent conditions, and also blocks when a trusted script (for example `install.sh`) has changed since it was hashed and trusted. Tested end to end against a seeded failing gate (check 14). | Whether this changes completion accuracy or false-done rates downstream, beyond the small, interrupted false-completion pilot in category 1 (0/12 baseline, 0/9 vstack, both too small to trust). |
| Skill routing on situation (`inject-session-context.sh` plus each skill's `description` frontmatter) | Connects a described situation ("writing prose" routes to `unslop`, "reviewing TypeScript" routes to `typescript-best-practices`) to a skill firing, for the cases exercised in category 1's ablation and hijack-fix numbers. | Whether the other roughly 19 of 28 `tests/auto-trigger.sh` cases, the ones outside the routing-table ablation subset and the eight principle-prefix fixes, dispatch reliably at all. See category 3. |
| `vstack trust` hash-pinning | Requires a human to have hashed and trusted the exact bytes of every script the gate executes before the Stop hook will run it unattended (CHANGELOG.md, "1.30.0", fixed after `security-auditor` found the prior version armed unattended execution with no confirmation of its own). | How often this has stopped a hostile or accidental script substitution outside its own test fixtures. |

## 3. Unproven, and named as such

| Question | Status |
|---|---|
| Does delegation rate fall off across a session's own lifetime? | `tests/delegation-drift.sh` exists, is pre-registered (first-third vs. last-third breadth-eligible delegation rate, with explicit floors on eligible windows and contributing sessions), and states its own reverse-causality confound up front: late-session work may just be less delegable, independent of anything the model does differently. It reports `NOT EVALUATED` rather than a rate below its own floors, the expected, correct result on day one, not a bug. |
| Does auto-compaction correlate with worse behaviour in the turns after it? | `tests/compaction-effect.sh` is pre-registered the same way (is_error rate in a 15-tool-call window before and after a compaction boundary, with floors on boundary count and pooled calls) and states plainly that any result is correlational, not causal. A session long enough to hit auto-compaction is not a random draw from the same population as a short one. The one published result in this space, Governance Decay (arXiv 2606.22528), is from a different harness and does not transfer by citation alone. |
| Do the skills outside the measured subsets actually dispatch? | `tests/auto-trigger.sh` declares 28 cases. Category 1 above accounts for a 9-case routing-table ablation and 8 principle-prefix-naming fixes, whose re-run is "not yet authorised" per CHANGELOG.md, "1.35.0" (roughly 24 headless calls). The dispatch rate for the remaining cases is not separately recorded in this document's sources. |
| Does any of this improve output quality on a frontier model? | Three independent local measurements found no gain and no loss large enough to trust: the review pathway (category 1), a regression-scored SWE-bench Lite pass that tied all four arms at 0 of 2 resolved once neighbour-breaking counted, and the false-completion pilot. `docs/research/do-harnesses-help.md` names the honest reading directly: these are ceiling effects on small, well-specified tasks, which read as "no difference" when the accurate statement is "this could not tell." `docs/research/harness-value-literature-2026-08.md`, surveying roughly 70 published sources, reaches the same split independently: no well-powered published result shows a config-layer gain on issue-resolution tasks with a frontier model, while the tail-behaviour literature (test-exploitation, cheating, out-of-scope destructive actions) shows some of the largest effect sizes in the field. |

### The failures, not smoothed over

Three `principle-*` skills fire at or near 0/10 and are named here rather than omitted.

- **`principle-prove-it-works`.** Scored 0/10 on its own fixture. Its trigger condition describes
  the assistant's own forthcoming speech act ("apply before declaring done"), not anything a
  skill matcher can see in the user's prompt. Worked around with a direct Stop-hook check instead
  of a skill fix (CHANGELOG.md, "1.37.0").
- **`principle-type-system-discipline`.** Scored 1/10 before a description rewrite, 9/10 after
  (CHANGELOG.md, "1.38.0").
- **`principle-build-the-lever`.** Scored 2/10, unmoved by the identical rewrite method that
  fixed the skill above, sitting exactly on the pre-registered falsification floor. The rewrite
  was reverted rather than shipped, and the failure is recorded rather than retried silently.

**Six checks were found in one day printing `ok` while measuring nothing they controlled.** On
2026-08-22, `docs/checks-that-inherit-their-answer.md` documented all six:

- An anchor a prose edit silently moved (check 18, blind for eleven commits).
- A commit-boundary check that only goes red once it is too late to fix before committing (check
  24 on a dirty tree).
- A linter whose silence was read as "no problems" instead of "did not run" (check 29).
- A third-party validator's exit code trusted without a control. It disagreed between CI and
  local (check 19).
- A planted defect erased by an unrelated cleanup step before the check ever looked at it
  (falsifiability row 34).
- A check whose own fake-green detector inherited an environment variable it neither set nor
  cleared (check 14b).

This is the closest thing this repository has to a stress test of the "42 checks, all
falsifiable" claim in category 1. It found the claim true only after finding six ways it had
quietly stopped being true.

## What was expected here and not found

Sourcing for the container-matrix Alpine and `vstack update` defects (category 1) traces to the
CHANGELOG entry and the suite description in `tests/README.md`. The suite itself was not re-run
for this document, per the constraints under which it was written. The same applies to
`tests/gate-falsifiability.sh`. Its own re-run, and a fresh confirmation that all 42
falsifiability rows still go red on cue, is asserted from `tests/README.md`'s description of the
mechanism and README.md's stated check-16 guarantee, not from executing it again today.

## Who should and should not use this

**The value here is safety and reversibility, not output quality.** Nothing measured shows this
configuration makes a frontier model write better code, review more accurately, or resolve more
issues. Three separate benchmarks looked and found ties or nulls, mostly because the tasks tested
left no headroom to find anything. What is real and checkable is narrower: a destructive-command
guard that denies a fixed, tested set of catastrophic commands, a Stop-hook gate that blocks
completion when the repository's own gate is red, and a gate of 42 checks with a documented, if
imperfect, history of catching its own false greens.

If the goal is a frontier model that produces measurably better output, this will not deliver it
and nothing here claims otherwise. If the goal is bounding blast radius and getting an honest
signal when something is broken before an agent claims it is not, three pieces carry nearly the
whole case: the destructive-command guard, the Stop-hook gate, and `.claude/verify.sh` itself.
Someone who wants only that is better served by those three files than by the full skill and
subagent library, whose behavioural effect, beyond the specific, dated dispatch measurements in
category 1, remains open.
