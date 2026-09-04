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
