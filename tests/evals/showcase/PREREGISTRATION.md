# Preregistration

Written before the multi_module and mean_visible runs; the merge_ranges and mean_intdiv pilots
had already run and are recorded under "Pilots" so the reader can see what was learned from them
rather than reconstruct it.

## Hypotheses

- **H1, false completion.** Under a spec-only prompt with no test, the bare arm will say `DONE`
  on a red held-out check in at least one of five Opus runs; vstack will do so in none.
  Prediction before running: rejected. Pilots already showed zero false completions in every arm.
- **H2, routing cost.** On a three-file task spanning two directories and two languages, which
  trips vstack's fan-out mandate, vstack's mean `total_cost_usd` will be below bare Claude's.
  Prediction before running: uncertain, leaning rejected. Delegation adds lead-model turns.
- **H3, correctness parity.** All arms reach a green check on all fixtures. Prediction: accepted.

## Decision rule, fixed in advance

If H1 and H2 are both rejected, the README carries the deterministic facts (skills shipped, hook
events wired, whether a Stop gate is always on) and the null on correctness and cost, with a link
to RESULTS.md. No number is published that this harness did not produce.

## Pilots

- merge_ranges, Opus, 3 arms x 3: every run green once the scorer was fixed to set `PYTHONPATH`;
  the nine "false completions" in the first file were import errors.
- mean_intdiv, Opus, none and vstack, 15 and 11 runs: all green, zero false completions.

## Outcome

H1 rejected. H2 rejected: vstack cost 3.6 to 4.4 times bare on the runs where it delegated and
matched bare on the runs where it did not. H3 accepted. The decision rule applied as written.
