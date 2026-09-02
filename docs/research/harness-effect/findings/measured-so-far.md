# What this repository has measured, as of 2026-09-03

Every number here has a harness and a raw-rows file behind it. Nothing here is a claim from a
README, ours or anyone else's.

## vstack against gstack and bare Claude, held-out checks

`tests/evals/showcase/RESULTS.md`, rows in `tests/evals/showcase/runs/`. Opus 5 and Haiku 4.5,
three arms, four fixtures, the agent never sees the check.

- Correctness: every valid run green in every arm (46 Opus, 10 Haiku).
- False completion: zero in every arm. The Stop gate vstack ships for this never had a case.
- Cost: within run-to-run noise when vstack does not delegate. 3.6 to 4.4 times bare Claude on
  the two of five multi-file runs where its fan-out mandate fired, and up to six times the wall
  time. Neither bare Claude nor gstack spawned a subagent in any run.
- Fixed overhead: vstack installs 28 skills and wires six hook events; gstack installs 54 skills
  and wires one; bare Claude none.
- Bare GLM 5.3 Flash through OpenCode, same fixtures: 73 of 75 green; 2 of 40 three-file runs
  said `DONE` over a red held-out check, the first non-zero false-completion count. Too few for
  a rate; enough to place the phenomenon on the cheap-model side.

### After the breadth mandate was retired (2026-09-03)

Paired rerun on the same three-file fixture, Opus 5, 10 samples per arm
(`tests/evals/showcase/runs/20260903-022953.55428.jsonl`): vstack spawned nothing on 10 of 10,
20 of 20 green, vstack $0.245 against bare $0.275 per run, 39 s against 43 s. The 3.6 to 4.4x was
the mandate, not the rest of the configuration.

### Gate experiments on GLM 5.3 Flash (2026-09-03)

The only false completions so far were bare GLM on the test-less three-file fixture, so the gate
question was put to GLM through a harness-side driver loop (OpenCode has no blocking Stop hook;
see `opencode-stop-gate-feasibility.md`). Two arms beyond bare: `gate` runs the fixture's visible
`verify.sh` after the agent stops and feeds a red result back, cap 3; `oracle` does the same with
the held-out check itself as the verifier, reporting only which check failed, the ceiling for any
gate.

- Fixture with visible tests (`multi_module_tested`, `runs/20260903-023828.96398.jsonl`), 20 per
  arm: bare 20 of 20 green, gate 20 of 20 green, zero gate rounds fed back. Given a runnable test,
  GLM runs it unprompted and the gate has nothing to catch.
- Test-less fixture (`multi_module`, `runs/20260903-030932.25374.jsonl`), bare against oracle,
  150 per arm: bare 149 of 150 green, 0 false completions (the one red run printed no verdict line: one turn, 296 s, a stalled session);
  oracle 150 of 150 green, 0 rounds fed back. Bare GLM on this fixture now stands at 2 false
  completions in 200 runs across all batches (both in the first batch of ten). At that base rate
  the oracle arm never had a red first pass in 150 tries, so the driver loop was exercised on a
  live run zero times; its red path is proven only by the harness self-test (`oracle_verify` on
  the untouched buggy tree reports three failing checks). The gate question stays open for lack
  of events, not for lack of a gate.

## Review benchmark

`tests/evals/RESULTS.md`. Opus 5, three arms, four fixtures, five samples. Planted defects found
11, 11 and 10 of 15 for bare, vstack and gstack. No skill was invoked in any of the sixty runs
under any arm: a neutral prompt about a file reaches neither harness's front door.

## Intent versus behaviour, in the operator's own sessions

`../../../docs/research/do-harnesses-help.md` and the memory it cites. Three measured gaps between
what the configuration says and what sessions did, fixed 2026-08-19: the goal gate was not armed,
skills did not fire on situation, fan-out happened in under half of the eligible turns.

## What changed because of them

- 1.68.0 retires the breadth mandate (plan: `plan-breadth-retirement.md`). Acceptance is a
  re-run of the routing-cost table with vstack at cost parity and no forced spawns.

## What the numbers say together

On tasks small enough for one prompt, a frontier model gets the answer right with or without the
layer, does not claim `DONE` on a red tree, and pays more when told to delegate. The layer's
measurable effects so far are all on the operator's side of the screen: whether a gate is armed,
whether a claim in the README can be shown false, whether an install can be undone. The open
question the literature folder exists to answer is where, if anywhere, a task gets large enough
or a model weak enough for the gate and the routing to start paying.
