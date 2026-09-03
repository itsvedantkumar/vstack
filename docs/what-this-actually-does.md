# What this actually does

**There is no evidence this configuration improves output quality on a frontier model.** Three
separate local benchmarks failed to show a gain. A review pathway scored 11/15, 11/15 and 10/15
across none, vstack and gstack, with zero skill invocations in sixty runs. A regression-aware
SWE-bench Lite scoring tied all four arms at zero. A false-completion pilot tied the baseline at
0/12 and vstack at 0/9 before the run was interrupted. `docs/research/` explains why. On
small, well-specified, single-file tasks a frontier model is already near ceiling, and a ceiling
leaves no headroom for a config layer to show up in.

`docs/research/fake-greens-2026-08.md` reports the whole evidence base as one document: what
was measured, what the numbers do not support, and the checks that passed while measuring
nothing, thirteen as of that document's date. The live catalogue is
`docs/checks-that-inherit-their-answer.md`, and it stands at eighteen. <!-- catalogue-count -->

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
| The gate declared 44 at v1.41.0 and every one ran green. | `./.claude/verify.sh` prints `checks: 44 declared, 44 ran, 0 skipped` and `VERIFIED`. | Run 2026-08-23 |
| On 2026-08-26 the gate declared 48 and was **red**: `48 declared, 47 ran, 1 skipped` and `VERIFICATION FAILED`, on `referenced install paths exist`, `inventory contract matches the tree` and `payload_digest`. All three are fixed. | `./.claude/verify.sh`, unpiped, on this branch | Run 2026-08-26 |
| As of 2026-08-27 both gates are green: `48 declared, 47 ran, 1 skipped` and `VERIFIED`, and falsifiability harness returned `60 declared, 59 passed, 0 failed, 1 skipped` with `FALSIFIABLE` (superseded by rows added in 1.46.0; tree now declares 73 rows, 70 mutation + 3 fixed, not re-run for this document). Run unpiped in an isolated worktree at the candidate commit, exit codes read on their own line. | `./.claude/verify.sh` and `./tests/gate-falsifiability.sh` | Run 2026-08-27 |
| The one remaining skip in both gates is check 24, and it is the designed state between a version bump and its tag, not a gap. The check's own source says so: it does not demand that HEAD be a release, only that the payload match the tag if one exists with the declared version. **Clearing it by tagging would fabricate the green** — a tag cut at HEAD makes the compared range empty by construction, so the check would report success having compared a commit to itself. The label was narrowed to say that instead. | `.claude/verify.sh` check 24, and its three branches exercised in a scratch clone | Verified 2026-08-27 |
| At v1.41.0, all 44 of the checks then declared had falsifiability rows. The tree now declares 66 checks and 113 falsifiability rows (113 mutation rows plus 3 fixed-mutation rows, 116 declared per run), all watched for red under mutation. `tests/gate-falsifiability.sh` breaks exactly what each check watches, requires the gate to name it, and restores the file byte for byte. Check 16 fails the gate if a check has no such row. | `tests/gate-falsifiability.sh`, `tests/README.md`, README.md "Checks that can fail" | v1.41.0 baseline as of 2026-08-23; current counts as of this write. Suite not re-run for this document; rows 40 and 44 verified by the scoped-row method only, see note below |
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
| `guard-destructive` Destructive-command guard (`claude/hooks/guard-destructive.sh`) | Denies `rm -rf /`, `rm -rf ~`, force-pushes to `main`, `master` or `HEAD:refs/heads/main`, and asks before `git reset --hard`, `terraform destroy`, wildcard staging outside the current workspace, and similar. Verified against 30 fixed commands (check 23, above) and against a stripped environment. | Whether it has intercepted a real destructive command in practice, or whether agents behave any differently with it installed than without. Unmeasured; decide by 2026-09-17. |
| `verify-gate` Stop-hook gate (`claude/hooks/verify-gate.sh`) | Blocks the agent's Stop event when the repository's `verify.sh` fails, in both jq-present and jq-absent conditions, and also blocks when a trusted script (for example `install.sh`) has changed since it was hashed and trusted. Tested end to end against a seeded failing gate (check 14). | Whether this changes completion accuracy or false-done rates downstream, beyond the small, interrupted false-completion pilot in category 1 (0/12 baseline, 0/9 vstack, both too small to trust). Unmeasured; decide by 2026-09-17. |
| `session-skill-routing` Skill routing on situation (`inject-session-context.sh` plus each skill's `description` frontmatter) | Connects a described situation ("writing prose" routes to `unslop`, "reviewing TypeScript" routes to `typescript-best-practices`) to a skill firing, for the cases exercised in category 1's ablation and hijack-fix numbers. | Whether the other roughly 19 of 28 `tests/auto-trigger.sh` cases, the ones outside the routing-table ablation subset and the eight principle-prefix fixes, dispatch reliably at all. See category 3. Unmeasured; decide by 2026-09-17. |
| `trust-hash-pinning` `vstack trust` hash-pinning | Requires a human to have hashed and trusted the exact bytes of every script the gate executes before the Stop hook will run it unattended (CHANGELOG.md, "1.30.0", fixed after `security-auditor` found the prior version armed unattended execution with no confirmation of its own). | How often this has stopped a hostile or accidental script substitution outside its own test fixtures. Unmeasured; decide by 2026-09-17. |
| `agent-naming` Agent-naming mandate (`claude/hooks/skill-mandate.sh:671-689`) | Blocks Stop when at least one `Task`/`Agent` dispatch happened in the session and no roster call sign appears in the assistant's text. | Whether the mandate changes attribution behaviour or output quality; no harness has run with and without it. Unmeasured; decide by 2026-09-17. |
| `swarm-first` Swarm-first mandate (`claude/hooks/skill-mandate.sh:693-710`) | Blocks Stop when a `Task`/`Agent` dispatch happened without a prior `Skill swarm` call in the same session. | Whether requiring `swarm` first changes fan-out quality or cost versus dispatching directly. Unmeasured; decide by 2026-09-17. |
| `serial-tail` Serial-dispatch-tail mandate (`claude/hooks/skill-mandate.sh:743-760`) | Blocks Stop when 3 or more Task/Agent dispatches were sent one message at a time since the last parallel batch (or session start). Threshold chosen against four real-session tail lengths (12, 25, 9, and a 2 that must not fire). | Whether catching a serial tail changes outcomes versus leaving it alone; no harness run yet. Unmeasured; decide by 2026-09-17. |
| `delegation-log-row` Delegation-drift log row (`claude/hooks/skill-mandate.sh:764-816`) | Appends one JSONL row per evaluated Stop recording dispatch/breadth/naming fields, unconditionally, whether or not a mandate blocked. Row-write mechanism itself proven by check 40 and falsifiability row 40 (`gate-falsifiability.sh:1086`). | Whether the logged fields correlate with anything downstream; check 40 proves the mechanism, not an effect. Unmeasured; decide by 2026-09-17. |
| `breadth-retired` Delegation-breadth mandate, retired (`claude/hooks/skill-mandate.sh:730-741`) | No longer blocks. Formerly forced fan-out on `dir_count >= 2 && ext_count >= 2 && fanout_batches == 0`; retired in 1.68.0 (commit `773f3d4`) after `tests/evals/showcase/runs/20260903-022953.55428.jsonl` showed it fired on 2 of 5 headless runs of the same fix at 3.6x-4.4x bare cost with no correctness gain, while the 3 silent runs matched bare cost. | Nothing outstanding; this row is the closed measurement, kept here rather than section 1 because it documents a mechanism (now inert) plus its own removal rationale. |
| `dispatch-counter` Dispatch counter and replay row (`claude/hooks/dispatch-counter.sh:360-403`) | Parses `tool_response` on every `Agent`/`Task` PostToolUse, sizes it, and appends a replay row. Mechanism proven by check 44 (`verify.sh:3027`). | Whether the counted/replayed data changes any downstream behaviour; check 44 proves the mechanism runs, not an effect. Unmeasured; decide by 2026-09-17. |
| `per-prompt-digest` Per-prompt digest and MANDATE line (`claude/hooks/inject-session-context.sh:91,159-178`) | Injects a small per-`UserPromptSubmit` reminder (GRILL / MANDATE lines) sized from Stop-hook-written counter files. | Effect beyond the routing-table ablation already cited above (9/9 vs 7/9, `docs/what-this-actually-does.md` row in section 1); that number is about the SessionStart routing table sharing this same script, not isolated to the per-prompt block. The FANOUT and MANDATE lines were rewritten in 1.68.0 and 1.69.0 after that ablation, so the ledger records it as unmeasured with decide-by 2026-09-17. |
| `goal-gate` Goal gate (`claude/hooks/goal-gate.sh`) | Blocks Stop on unchecked `## Rubric` boxes in `.goal/*/goal.md`, capped at 3 blocks then opens. | Whether the rubric-check requirement changes completion accuracy; the release path is still the agent ticking its own box, a self-report. Unmeasured; decide by 2026-09-17. |
| `format` Auto-format on write (`claude/hooks/format.sh`) | Runs on every `Edit`/`Write`/`MultiEdit` PostToolUse to reformat the touched file. | Whether auto-formatting changes review outcomes or downstream error rates. Unmeasured; decide by 2026-09-17. |

## 3. Unproven, and named as such

| Question | Status |
|---|---|
| Does delegation rate fall off across a session's own lifetime? | `tests/delegation-drift.sh` exists, is pre-registered (first-third vs. last-third breadth-eligible delegation rate, with explicit floors on eligible windows and contributing sessions), and states its own reverse-causality confound up front: late-session work may just be less delegable, independent of anything the model does differently. It reports `NOT EVALUATED` rather than a rate below its own floors, the expected, correct result on day one, not a bug. |
| Does auto-compaction correlate with worse behaviour in the turns after it? | `tests/compaction-effect.sh` is pre-registered the same way (is_error rate in a 15-tool-call window before and after a compaction boundary, with floors on boundary count and pooled calls) and states plainly that any result is correlational, not causal. A session long enough to hit auto-compaction is not a random draw from the same population as a short one. The one published result in this space, Governance Decay (arXiv 2606.22528), is from a different harness and does not transfer by citation alone. |
| Do the skills outside the measured subsets actually dispatch? | `tests/auto-trigger.sh` declares 30 cases. Category 1 above accounts for a 9-case routing-table ablation and 8 principle-prefix-naming fixes, whose re-run is "not yet authorised" per CHANGELOG.md, "1.35.0" (roughly 24 headless calls). The dispatch rate for the remaining cases is not separately recorded in this document's sources. |
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
2026-08-22, `docs/checks-that-inherit-their-answer.md` documented all six. It documents eighteen now; <!-- catalogue-count -->
the eleven added since are not restated here, because this section is dated and the catalogue is the
place that stays current:

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

This is the closest thing this repository has to a stress test of the "all checks falsifiable"
claim in category 1. It found the claim true only after finding six ways it had quietly stopped
being true. The catalogue has since reached eighteen, <!-- catalogue-count --> and by its own dating six of those were found across
2026-08-26 and 2026-08-27, so the rate that document predicted at roughly one a month is
understated by about an order of magnitude. The twelfth is the one worth reading: no check was
wrong, no mutation would have caught it, and the suite was green throughout. What failed was a
human reading a correct program's output the way people actually read output.

## What was expected here and not found

Sourcing for the container-matrix Alpine and `vstack update` defects (category 1) traces to the
CHANGELOG entry and the suite description in `tests/README.md`. The suite itself was not re-run
for this document, per the constraints under which it was written. That no longer applies to
`tests/gate-falsifiability.sh`. When this section was first written the suite could not be run at
all: it refuses to mutate a tree the gate did not pass first, and the gate was red, which is the
refusal working.

It was run on 2026-08-27, against `c37ce8c` in a detached worktree rather than the shared
checkout: **61 declared rows, 60 passed, 0 failed, 1 skipped, `FALSIFIABLE`**, followed by
`ok restore integrity: no concurrent edits during the run` and `ok tree unchanged by the run`. The
one skip is check 24, which names its reason (no tag to compare against). 58 of those rows carry a
mutation; the other 3 are fixed rows that assert the harness's own accounting. This run's row count (61) predates rows added in version 1.46.0; the tree now declares 73 rows (70 mutation + 3 fixed), and that count has not been re-run for this document. The row total
exceeds the 48 declared checks because several checks can fail in more than one way.

Read that as narrowly as it is written. Every row was watched going red under its own mutation and
green again after restore, on that commit. It is not a claim about any later commit, and it says
nothing about whether a check that goes red on cue is measuring the thing its label names.

## Who should and should not use this

**The value here is safety and reversibility, not output quality.** Nothing measured shows this
configuration makes a frontier model write better code, review more accurately, or resolve more
issues. Three separate benchmarks looked and found ties or nulls, mostly because the tasks tested
left no headroom to find anything. What is real and checkable is narrower: a destructive-command
guard that denies a fixed, tested set of catastrophic commands, a Stop-hook gate that blocks
completion when the repository's own gate is red, and a gate with a documented, if imperfect,
history of catching its own false greens. The check count moves too often to state here; read it
from a run.

If the goal is a frontier model that produces measurably better output, this will not deliver it
and nothing here claims otherwise. If the goal is bounding blast radius and getting an honest
signal when something is broken before an agent claims it is not, three pieces carry nearly the
whole case: the destructive-command guard, the Stop-hook gate, and `.claude/verify.sh` itself.
Someone who wants only that is better served by those three files than by the full skill and
subagent library, whose behavioural effect, beyond the specific, dated dispatch measurements in
category 1, remains open.
