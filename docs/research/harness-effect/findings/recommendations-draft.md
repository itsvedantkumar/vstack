# What the literature says vstack should change

Draft of 2026-09-03, written from the first six GLM-drafted literature files before their
verification pass ran. Every line below is provisional until the entry it cites carries
`VERIFIED` in the matching `literature/*.verification.md`. Nothing here is applied to the tree yet.

Each item names the vstack mechanism it touches, what it does today, what the sources say it
should do, and the measurement that would show the change worked. Items are ordered by how many
independent reports converged on them.

## 1. Retire the breadth trigger for fan-out; gate delegation on coupling

Status: applied in 1.68.0, see `plan-breadth-retirement.md`. Measurement pending.

Today: `skill-mandate.sh` forces a fan-out once a turn touches two directories or two extensions.
Our own measurement: the two runs where it fired cost 3.6 to 4.4 times bare Claude and up to six
times the wall time, on a three-file fix, for no correctness gain.
Sources: multi-agent-overhead entries 2, 6, 7 (delegation pays only when subtasks are independent
and verifiable; loss is exponential in cross-subtask coupling; coding has fewer parallelisable
tasks than research); model-routing entries 6, 9 (no router beats always-strongest on accuracy
across three SWE benchmarks; router gains indistinguishable from zero).
Change: replace the breadth count with a coupling pre-flight. Fan out read-only work
(investigation, localisation, review) freely; edits to overlapping files stay serial on the lead.
Measure: multi_module cost and wall time, vstack against bare, n of 10 each, expecting parity.

## 2. The Stop gate must consume an execution result, never a self-assessment

Today: `verify-gate.sh` does this but is off until `vstack trust` runs, so a fresh repo has no
executable gate. `goal-gate.sh` reads checkbox state in markdown, which is a self-report.
Sources: self-verification entries 1, 2, 11 (intrinsic self-judgment loses 3 to 25 points;
self-feedback on own code wrong in 32 of 80 cases); multi-agent-overhead entry 1 (verification
failures are over a third of observed failures); competitor-claims entry 22 (completion claims
inflate without fresh evidence).
Change: on Stop, when no trusted verify.sh exists, run the repository's own test command if one is
declared (package.json test, pytest, cargo test) in the working tree and block on its exit code;
keep goal-gate as a reminder, not a gate.
Measure: a fixture whose spec is contradictory; bare says DONE, gated arm says NOT DONE with the
failing output attached, n of 10.

## 3. Hand the agent a structured failure, and cap repair rounds at two

Today: verify-gate pastes verify.sh output and blocks up to three times, then keeps blocking on a
cached red.
Sources: self-verification entries 2, 5, 12 (repair works once the error is localised; gains land
in the first two rounds; more repair rounds below the baseline); competitor-claims entry 20
(an escalation channel cut reward hacking from 23.6% to 5.3%, no performance cost).
Change: the block message carries failing test name, expected versus actual, and the trace as
fields, not a log dump. After two red rounds the gate offers one structured exit: a defect report
against the tests or the environment, written to a file, which releases the Stop. Looping past
two is the design the literature has already falsified.
Measure: rounds to green and rate of test tampering on the contradictory-spec fixture.

## 4. Keep the instruction file short; nothing unconditional at session start

Today: CLAUDE.md is held to 8704 bytes and a per-prompt digest is injected on every turn.
Sources: model-routing entry 10 (unconditional skill injection lowers Pass@2 by 1.3 to 4.2
points and raises token cost 72% to 394%; anti-pattern rules are the only slice with a reliable
positive effect; example code hurts the strongest model); competitor-claims entries 13, 14, 16
(context files do not improve success and cost over 20% more; 62% of files leak lint rules;
roughly 150 to 200 followable instructions total); self-verification entry 1.
Change: cut CLAUDE.md to non-obvious invariants, the verification protocol and proscriptive
rules; move every style or formatting instruction into the format hook; drop the per-prompt
digest or make it conditional on the situation it addresses; run a length-matched irrelevant
control before any instruction file is kept.
Measure: mean_intdiv and multi_module cost and green rate with the digest on and off, n of 10.

## 5. Subagents get contracts, not the instruction file

Today: subagents inherit the project CLAUDE.md and the digest.
Sources: model-routing entry 12 (code-proximate contracts recover most of the gap on weak models
and add nothing on strong ones); competitor-claims entry 13 (the instruction budget is near the
frontier ceiling before a subagent starts); multi-agent-overhead entries 4, 7 (compact verified
handoffs beat context sharing; one change cut cost from $0.399 to $0.125).
Change: worker and explorer briefs carry the task, the file list and the acceptance check; the
lead's instruction file is not forwarded. A shared notes file typed FACT, FAIL, PATCH_SUMMARY is
the handoff, and the lead reads it before integrating.
Measure: tokens per subagent and lead integration turns, before and after.

## 6. Verify subagent output at admission

Today: the lead reads a subagent's prose report and acts on it.
Sources: multi-agent-overhead entries 7, 12; model-routing entry 6 (most reproduction claims from
a cheap tier are false before a verify-then-strip gate).
Change: a subagent that claims a test result has the lead re-run that test before its claim is
used; a subagent that claims a structural fact has it grepped.
Measure: false claims caught per hundred dispatches, from session logs.

## 7. Instrument per feature, then decide

Today: `dispatch-counter.sh` counts dispatches; nothing attributes cost or wall time to a hook,
a skill or a subagent.
Sources: multi-agent-overhead entries 5, 10, 11; competitor-claims entries 10, 22.
Change: a PostToolUse ledger of tokens, wall time and cost per dispatch and per skill load, and
a `bin/doctor` view of it. Every item above is adopted only if the ledger shows equal or better
correctness at equal or lower cost.
Measure: the ledger itself, compared against `runs/*.jsonl` totals for the same sessions.
