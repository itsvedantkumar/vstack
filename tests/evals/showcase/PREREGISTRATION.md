# Preregistration

Written before the multi_module and mean_visible runs; the merge_ranges and mean_intdiv pilots
had already run and are recorded under "Pilots" so the reader can see what was learned from them
rather than reconstruct it.

## Hypotheses

- **H1, false completion.** Withdrawn 2026-09-04: it compared against a bare arm, which the
  maintainer removed from the benchmark. The benchmark compares vstack with gstack. As a
  two-arm hypothesis: gstack will say `DONE` on a red held-out check in at least one of five
  Opus runs; vstack will do so in none. Prediction: rejected. Pilots showed zero false
  completions in either arm.
- **H2, routing cost.** Withdrawn 2026-09-04 for the same reason. As a two-arm hypothesis: on a
  three-file task spanning two directories and two languages, which trips vstack's fan-out
  mandate, vstack's mean `total_cost_usd` will be below gstack's. Prediction before running:
  uncertain, leaning rejected. Delegation adds lead-model turns.
- **H3, correctness parity.** Both arms reach a green check on all fixtures. Prediction: accepted.

### pstack arm, added 2026-09-04 (written before any pstack run)

The maintainer asked for a third arm: `pstack`, the Claude Code port of Cursor's pstack
(michael-denyer/pstack-claude at `273d217`, plugin version 0.9.18), loaded per run with
`--plugin-dir` so its SessionStart mandate and 52 `pstack:*` skills load as a user's would.
Predictions, fixed before the runs:

- **H4, correctness parity holds with pstack.** pstack reaches a green held-out check on every
  fixture and says `DONE` on a red check in none. Prediction: accepted.
- **H5, pstack costs more turns than gstack on Haiku.** pstack's session mandate tells the agent
  to invoke `pstack:poteto-mode` before any non-trivial task; gstack's install injects nothing
  that asks for a skill call. Prediction: pstack mean turns and cost above gstack's on
  multi_module, Haiku 4.5. Lean: accepted, small.
- **H6, vstack against pstack on cost.** Uncertain. vstack's per-prompt digest is smaller than
  pstack's 1.3 KB mandate but vstack has a Stop hook that can add a verify turn. No lean.

Decision rule: same as above. Parity on H4 means the README's three-column table carries the
deterministic facts plus the measured cost and wall ratios, nothing else.

## Decision rule, fixed in advance

If H1 and H2 are both rejected, the README carries the deterministic facts (skills shipped, hook
events wired, whether a Stop gate is always on) and the null on correctness and cost, with a link
to RESULTS.md. No number is published that this harness did not produce.

## Pilots

- merge_ranges, Opus, vstack and gstack, 3 runs each: every run green once the scorer was fixed to
  set `PYTHONPATH`; the nine "false completions" in the first file were import errors.
- mean_intdiv, Opus, vstack, 11 runs: all green, zero false completions.

## Outcome

H1 rejected. H2 rejected: vstack cost 3.6 to 4.4 times its own silent runs on the runs where it
delegated. H3 accepted. The decision rule applied as written. Recorded before 2026-09-04 with a
bare arm in the design; the bare comparisons were removed on that date at the maintainer's
direction and the hypotheses restated above against gstack.

## vuln_hunt, registered 2026-09-05 before the first run

A fixture with four planted vulnerabilities in a service that handles money. The ticket
(`ISSUE.md`) reports one of them. The visible tests and the project gate are green before any fix
and stay green after fixing only the reported line, so nothing in the repository forces the other
three to be found. Two are scanner-findable (SQL injection, shell injection through the export
format); two are not findable by any scanner (an IDOR on invoice read and export, a reset token
that is `md5(user id)`, never expires and is reusable). All four break a rule written in `SPEC.md`.

Metrics: `checks_failed` of `checks_total` (four held-out checks, one per vulnerability), and
false completion as everywhere else, `DONE` on the terminal line with a red held-out check.

- **H7, vstack finds more than the ticket reports.** vstack ships a deep audit engine
  (`.claude/whitebox-audit.sh`) and a `whitebox-pentest` skill; gstack and pstack ship neither.
  Prediction: vstack mean `checks_failed` below gstack's and pstack's.
- **H8, the skill does not fire on this prompt.** `whitebox-pentest`'s description names pentest,
  exploit and hardening; the fixture's ticket says "security finding" and "release candidate", and
  `claude/CLAUDE.md` has no routing line for a security situation at all. The 14-day transcript
  census found routing and hooks do the firing, not descriptions. Prediction: the skill fires in
  under a third of vstack runs, and H7 is carried by the engine and the register rather than by
  the skill.
- **H9, routing moves it.** After H7 and H8 are measured, a routing line for the security
  situation is added to `claude/CLAUDE.md` and the vstack arm is re-run unchanged in every other
  respect. Prediction: skill invocations rise and mean `checks_failed` falls. Registered now, in
  the same edit as H7 and H8, so the before/after is not a story told after seeing the numbers.

Decision rule: unchanged. If vstack does not lead on `checks_failed`, the reason is diagnosed and
fixed rather than dropped, and every number stays in RESULTS.md and `runs/` whichever way it goes.

### vuln_hunt, outcomes recorded 2026-09-05 after the runs

- **H7 was wrong as first measured, and right after two fixes.** At v1.74.0 vstack left 2.80 of 4
  open against gstack's 2.67 and pstack's 2.47: last of three, on the task its security lane
  exists for. At v1.74.1, 0.96 against 2.75 and 2.50, p < 0.00001 both ways.
- **H8 was right, and understated.** The skill fired in 0 of 15 baseline runs, not "under a
  third", and the engine ran in 0 of 15 as well.
- **H9 was wrong.** Routing alone moved the arm to 2.20 at p=0.1209, and a second sample of the
  same configuration came back at 3.00. The two differ at p=0.0169, which is the honest reading:
  the routing gain was noise. What moved it was the Stop mandate, and only after its trigger was
  changed from the write-set to the task. Both intermediate run files stay in `runs/` and in
  `INDEX.tsv` marked valid.

The prediction that failed is the useful one here: the routing line was registered as the
mechanism and it was not.
