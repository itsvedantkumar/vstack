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
