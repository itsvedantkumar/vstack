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
Our own measurement: the two runs where it fired cost 3.6 to 4.4 times the three runs where it
stayed silent, and up to six times the wall time, on a three-file fix, for no correctness gain.
Sources: multi-agent-overhead entries 2, 6, 7 (delegation pays only when subtasks are independent
and verifiable; loss is exponential in cross-subtask coupling; coding has fewer parallelisable
tasks than research); model-routing entries 6, 9 (no router beats always-strongest on accuracy
across three SWE benchmarks; router gains indistinguishable from zero).
Change: replace the breadth count with a coupling pre-flight. Fan out read-only work
(investigation, localisation, review) freely; edits to overlapping files stay serial on the lead.
Measure: multi_module cost and wall time, vstack against gstack, n of 10 each, expecting parity.

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
Measure: a fixture whose spec is contradictory; the gated arm says NOT DONE with the failing
output attached, n of 10.

Declined for this tree on 2026-09-03. The fallback of running an untrusted package.json test script at Stop time reopens the hole 1.30.0 and 1.46.0 closed. README.md lines 349 to 356 name scripts.test as arbitrary code at Stop time, tests/compare-baseline.sh lines 118 to 127 pin untrusted did not run it, and check 61 in .claude/verify.sh hashes manifests for that reason. The cloud lane already arms trust in overlay.sh line 389. The goal-gate downgrade to a reminder is declined too: it blocks on the absence of a claim and its cap already opens, and the benchmark has zero events to tell the two apart. The verify-gate already consumes an exit code and never a self-assessment (claude/hooks/verify-gate.sh lines 145 to 157).

## 3. Hand the agent a structured failure, and cap repair rounds at two

Today: verify-gate pastes verify.sh output and blocks up to three times, then keeps blocking on a
cached red.
Sources: self-verification entries 2, 12 (repair works once the error is localised; gains land in
the first two rounds); competitor-claims entry 20 (an escalation channel cut reward hacking from
23.6% to 5.3%, no performance cost). Self-verification entry 5 is marked MISREAD in the verification
file.
Change: the failure is built as fields: exit status, attempt of cap, the failing lines, and the
last forty lines of trace. The agent gets two repair rounds. Past the cap, the gate offers one
structured exit: a defect report against the tests or the environment, written to a file, which
releases the Stop. The plan is in plan-next-mechanisms.md.
Measure: rounds to green and rate of test tampering on the contradictory-spec fixture.

## 4. Keep the instruction file short; nothing unconditional at session start

Today: CLAUDE.md is 4332 bytes and a per-prompt digest is injected on every turn. No check in
.claude/verify.sh caps the file size.
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

The SessionStart skills routing table in claude/hooks/inject-session-context.sh (lines 201 to
230) is unconditional and stays, because it is what made skills fire.

## 5. Subagents get contracts, not the instruction file

Today (corrected 2026-09-03): subagents do not receive the digest. It is UserPromptSubmit output
(claude/settings.json lines 84 to 93) and that event does not fire inside an Agent call. Whether
subagents load the project or user CLAUDE.md at all is unmeasured here (docs/config-precedence.md
line 18 probes the main session only).
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
Sources: multi-agent-overhead entries 5, 11; competitor-claims entry 22. Competitor-claims entry
10 is marked MISREAD in literature/competitor-claims.verification.md line 16.
Change: a PostToolUse ledger of tokens, wall time and cost per dispatch and per skill load, and
a `bin/doctor` view of it. Every item above is adopted only if the ledger shows equal or better
correctness at equal or lower cost.
Measure: the ledger itself, compared against `runs/*.jsonl` totals for the same sessions.
