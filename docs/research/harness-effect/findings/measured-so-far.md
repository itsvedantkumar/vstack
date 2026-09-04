# What this repository has measured, as of 2026-09-03

Every number here has a harness and a raw-rows file behind it. Nothing here is a claim from a
README, ours or anyone else's.

## vstack against gstack, held-out checks

`tests/evals/showcase/RESULTS.md`, rows in `tests/evals/showcase/runs/`. Opus 5 and Haiku 4.5,
three arms, four fixtures, the agent never sees the check.

- Correctness: every valid run green in every arm (46 Opus, 10 Haiku).
- False completion: zero in every arm. The Stop gate vstack ships for this never had a case.
- Cost: within run-to-run noise when vstack does not delegate. On the two of five multi-file
  runs where its fan-out mandate fired, vstack cost 3.6 to 4.4 times the three runs where it
  stayed silent, and up to six times the wall time, for no correctness gain. gstack spawned no
  subagent in any run.
- Fixed overhead: vstack installs 28 skills and wires six hook events; gstack installs 54 skills
  and wires one.

### After the breadth mandate was retired (2026-09-03)

Paired rerun on the same three-file fixture, Opus 5, 10 samples per arm
(`tests/evals/showcase/runs/20260903-022953.55428.jsonl`): vstack spawned nothing on 10 of 10,
20 of 20 green. The 3.6 to 4.4x was the mandate, not the rest of the configuration.

### Gate experiments on GLM 5.3 Flash (2026-09-03)

Removed 2026-09-04: this section compared against a bare arm; the run files remain in
`tests/evals/showcase/runs/`.

### Second gate round (2026-09-03, afternoon)

Removed 2026-09-04: this section compared against a bare arm; the run files remain in
`tests/evals/showcase/runs/`.

## Review benchmark

`tests/evals/RESULTS.md`. Opus 5, three arms, four fixtures, five samples. Planted defects found
11 and 10 of 15 for vstack and gstack. No skill was invoked in any of the sixty runs under any
arm: a neutral prompt about a file reaches neither harness's front door.

## Intent versus behaviour, in the operator's own sessions

`../../../docs/research/do-harnesses-help.md` and the memory it cites. Three measured gaps between
what the configuration says and what sessions did, fixed 2026-08-19: the goal gate was not armed,
skills did not fire on situation, fan-out happened in under half of the eligible turns.

## What changed because of them

- 1.68.0 retires the breadth mandate (plan: `plan-breadth-retirement.md`). Acceptance is a
  re-run of the routing-cost table with vstack at cost parity and no forced spawns.

## What the numbers say together

On tasks small enough for one prompt, a frontier model gets the answer right, does not claim
`DONE` on a red tree, and pays more only when its fan-out mandate forces delegation it does not
need. The layer's measurable effects so far are all on the operator's side of the screen: whether
a gate is armed, whether a claim in the README can be shown false, whether an install can be
undone. The open question the literature folder exists to answer is where, if anywhere, a task
gets large enough or a model weak enough for the gate and the routing to start paying.
