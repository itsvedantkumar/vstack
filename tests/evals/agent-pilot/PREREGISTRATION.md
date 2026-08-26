# Pre-registration: does routing to a shipped specialist subagent help?

See `tests/evals/agent-pilot/README.md` for how to reproduce everything below, including the
scorer's offline self-test, which is the only execution this instrument performs before an
operator opts in.

Written before any of the 25 calls exist. Nothing in this file has been adjusted after seeing a
result, because no result exists yet -- `tests/evals/agent-pilot/run.sh` refuses to spend a call
without an operator's explicit opt-in, and nobody has given one. If a future edit to this file
follows a run, that edit should say so in its own words rather than silently rewriting a
threshold; that is the discipline `tests/evals/false-done/PREREGISTRATION.md` and
`tests/evals/build-the-lever/PREREGISTRATION.md` were written under, and this file follows the
same one.

## The question

Does routing work to a shipped specialist subagent (`code-reviewer`, `security-auditor`, `qa`,
`test-writer`) produce better output than doing the same work inline, or than routing it to a
generic subagent carrying no specialist prompt at all?

## The honest prior, stated before the null hypothesis, because it determines what a null means

**The existing evidence does not support the claim that specialist agents improve quality.**

- `tests/evals/RESULTS.md`'s first benchmark: 11/15, 11/15, 10/15 planted defects found across no
  harness, vstack and a competitor, **zero skill invocations in sixty runs**. Its conclusion:
  "No configuration outperformed the baseline."
- `tests/evals/RESULTS.md`'s second benchmark, after retraction and correction: a plain review
  request found 33/34 planted defects with 0 false positives; both harnesses' own `/review`
  pathways found fewer real defects (29/35 and 24/35) and invented 15-19 things that were not
  there. "Both lose badly to not using a harness at all."
- `docs/research/harness-value-literature-2026-08.md` section 1: "On current frontier models,
  there is no published evidence that a configuration-layer harness improves correctness, and two
  independent nulls at honest baselines say it does not." Its single most decision-relevant
  finding: "prose instructions telling an agent to be careful measured *worse* than no
  intervention, while a retrieval step that ran something cut the same failure by 70%."

None of that is a controlled test of *this* question -- routing to a **subagent carrying a
specialist prompt** is a narrower and different manipulation than "are skills installed" or
"which `/review` command runs" -- which is exactly why this pilot exists rather than citing the
prior work as an answer. But the prior work sets the bar this pilot's result has to clear before
"the specialist won" is a claim worth making, and it means the honest expectation, stated now, is
**a null**: no arm reliably beats the others at n=8 per arm.

## Hypotheses

**H0 (the null, and the expected outcome):** across the 8 (role, fixture) cells, the specialist,
generic and direct arms find the planted defect at indistinguishable rates. No arm's FOUND count
clears the other two's by more than sampling noise supports at n=8 (see Sample size, below).

**H1 (specialist wins):** the specialist arm's FOUND count is higher than both the generic and
direct arms' by a margin sampling noise at n=8 cannot produce by chance.

**H2 (routing itself, not the prompt, is what matters):** generic and specialist both beat direct,
and generic is indistinguishable from specialist. This would say delegation -- a fresh context,
forced focus, no other conversational baggage -- does the work, not the specialist system prompt.
This is a real alternative this design can distinguish, because generic and specialist are both
Task-routed and differ only in which prompt the dispatched worker carries.

**H3 (routing hurts):** direct beats both subagent arms. Plausible on small, single-file fixtures
per `RESULTS.md`'s own finding that a structured pathway "manufactures findings" and a plain
request "answers the question asked" -- though that finding was about a `/review` command's
multi-section structure, not about subagent dispatch per se, so H3 here is a weaker echo of it,
not a restatement.

**What would falsify H0 in either direction, stated now:** a categorical split at this sample
size -- one arm at 7/8 or 8/8 while another sits at 0/8 or 1/8 (see the Wilson table below; those
two bands are the only ones that do not overlap at n=8). Anything less than that is indeterminate
and must be reported as indeterminate, not rounded toward whichever arm scored higher.

**What would falsify H1 specifically:** the specialist arm's FOUND count at or below the generic
arm's. A specialist that only matches a prompt-less subagent given the same tools is a null result
for the specialist *prompt*, regardless of how the direct arm does.

## What is measured, and the scoring function

Each of the 24 scored cells is one `claude -p` call, scored by `scorer.sh` into exactly one of
four verdicts, deterministically, from the captured transcript and an exit-status marker -- no
model grades any other model's output. Full mechanism and rationale in `scorer.sh`'s own header;
summarized here because the verdict definitions are part of what is pre-registered:

- **FOUND** -- every pattern in the fixture's `detect_all` list (extended regex, case-insensitive,
  AND semantics) matched somewhere in the arm's own assistant-authored output (text it wrote, or
  tool inputs it constructed -- never a `tool_result`, which can contain the fixture's own source
  text regardless of whether the model noticed anything in it; see scorer.sh's header and
  `selftest/found-nothing.jsonl` for why that distinction is load-bearing).
- **NOT_FOUND** -- the call completed and produced real output; the required pattern(s) are
  absent. A negative result. Also a finding, not a defect in the harness.
- **NOT_RUN** -- no exit-status marker exists, or it is nonzero (124 = the per-call timeout
  fired). The call did not complete. Not scored as a zero.
- **NOT_CAPTURED** -- the process reported success (exit 0) but the capture is unusable: zero
  bytes, invalid JSON (cut off mid-stream), or parses but contains no assistant-authored content
  at all. Also not scored as a zero, and kept apart from NOT_RUN because the two point at
  different bugs -- NOT_RUN says look at the arm/CLI invocation, NOT_CAPTURED says look at the
  capture/redirection plumbing.

**Ground truth for every fixture, its planted defect, and its exact `detect_all` patterns are
committed in `ground-truth.json` before any call runs.** Nobody chooses what counts as a hit after
seeing an arm's output.

## Exclusions

- A cell that scores NOT_RUN or NOT_CAPTURED is excluded from the FOUND/NOT_FOUND comparison
  entirely -- not counted as a miss, not counted as a hit, reported separately as "N of 8 cells in
  this arm did not produce a scoreable result" alongside whatever FOUND/NOT_FOUND rate the
  remaining cells give. `tests/evals/optimize.sh`'s own header documents the alternative -- a
  crashed run silently read as f1 0.0000 -- and names it a defect, not a convention to repeat.
- If more than 2 of an arm's 8 cells are NOT_RUN or NOT_CAPTURED, that arm's rate for this run is
  **not reported as a comparison at all**, only as "the harness could not measure this arm here",
  and the run is not re-quoted as a partial result. Two of eight failing to measure is already a
  quarter of the arm; extrapolating a rate from the remaining six invites exactly the kind of
  survivorship bias `RESULTS.md`'s denominator note flags for the `none` arm's 34-of-35 planted
  count.
- The canary is never pooled into the 24-cell comparison. It exists to validate the harness, not
  to add a ninth data point to any arm.

## The canary, and why it is the most important of the 25 calls

Twenty-four scored cells look exactly like real data whether or not the harness actually worked --
a wrong `subagent_type`, a fixture that never reached the model, a capture pipe that silently
dropped output, or a `detect_all` regex that cannot match anything would each still produce 24
rows of FOUND/NOT_FOUND that read as a result. The canary is designed so a broken harness produces
a **visibly wrong** canary result instead.

**The fixture:** `canary/canary.py`, a hardcoded AWS secret access key
(`AWS_SECRET_ACCESS_KEY = "AKIA..."`) at module scope -- the well-known AWS documentation example
key, not a real credential. This is deliberately the single most obvious, least model-dependent
defect this pilot could plant. A hard defect would make a NOT_FOUND result ambiguous between "the
harness is broken" and "the model missed a genuinely hard case". An obvious one removes that
ambiguity: **any arm that is actually reading the file and saying anything about it will name a
hardcoded secret.** That is exactly why the canary is not one of the 8 scored fixtures -- it is
not testing whether a specialist beats a generic subagent, it is testing whether the pipe between
"a file exists" and "a verdict gets recorded" works at all.

**The arm:** `security-auditor`, specialist, the single call ground-truth.json's `.canary` entry
fixes it to. Chosen because it is the arm exercising the most machinery -- a sandboxed
`PILOT_HOME`, a copied `claude/agents/security-auditor.md`, a forced `Task` dispatch naming that
`subagent_type` -- so a canary that passes through this arm is stronger evidence the plumbing
works than a canary through the direct arm, which has no delegation step to get wrong.

**Expected verdict: FOUND.**

**What each other verdict means, stated in advance so nobody improvises an explanation after
seeing one:**

- **NOT_FOUND** -- the call ran, produced real output, and never named the secret. On a defect
  this obvious, that is not a competence result, it is the strongest available signal that
  something in the harness is broken: the wrong `subagent_type` was dispatched (so a
  non-security-auditor persona answered without the review framing), the fixture file was never
  actually delivered into the working directory the model saw, or `detect_all`'s patterns
  (`AKIA` and one of secret/hardcod/credential) are broken and cannot match true positive text
  either. **Do not read the other 24 rows if this happens; diagnose the harness first.**
- **NOT_RUN** -- the call never completed. Likely candidates, in order of how this repository's
  own history has hit them: authentication failing under the reassigned `PILOT_HOME` (see
  `run.sh`'s header on credential carry-over, and RESULTS.md's own first documented benchmark
  defect -- "every baseline run returned Not logged in, scored zero"), the `security-auditor`
  `subagent_type` being rejected by the CLI (a typo, a stale agent file), or the per-call timeout
  being too short for a nested subagent dispatch.
- **NOT_CAPTURED** -- the call finished but the capture pipeline lost the output. Look at the
  redirection in `run_cell()`, not at the model.

A non-FOUND canary is not "one bad data point to discard" -- it invalidates interpretation of the
24 scored cells until the specific cause is found and fixed, because the same plumbing produced
all 25.

## What could still produce a confident wrong answer

Stated now, not after a result exists to rationalize around.

1. **The generic arm's toolset cannot be pinned to match the specialist's.** The direct arm's
   `--allowedTools` is set to exactly the dispatched worker's declared tool list (read off
   `claude/agents/<role>.md`), and the specialist arm's subagent gets that same list because it IS
   that file. The generic arm's subagent (`general-purpose`) has no per-call tool-restriction
   surface exposed through the Task tool's public parameters (`description`, `prompt`,
   `subagent_type`, `model` -- no `tools`), so its actual working toolset is whatever Claude
   Code's built-in `general-purpose` agent defaults to, which may be broader than the role's list.
   If the generic arm does better than a role's specialist, a wider toolset -- not the absence of
   a specialist prompt -- is a live alternative explanation this design cannot separate from the
   real one.
2. **The outer session's `--max-turns` is not known to cascade to a Task-dispatched subagent's own
   turn budget.** "Turn limit held equal" is only verified true at the outer-session level. If the
   inner subagent for the generic or specialist arm runs an unbounded or differently-bounded loop,
   the three arms are not actually equalized on this axis, only apparently equalized in the flag
   that was passed.
3. **Credential carry-over into `PILOT_HOME` is unverified.** `run.sh` copies
   `$HOME/.claude.json` and `$HOME/.claude/.credentials.json` read-only into each sandbox before
   the first cell runs. Nobody has proven this is sufficient for `claude -p` to authenticate under
   a reassigned `HOME` on this machine -- the project's own memory records that the sibling
   mechanism, `CLAUDE_CONFIG_DIR` pointed at a fresh directory, does not work for exactly this
   reason. If it fails here too, every one of the 25 cells reads NOT_RUN, which is a loud and
   correctly-labeled failure rather than a silent wrong number -- but it does mean the pilot
   answers nothing until someone fixes authentication under the sandbox.
4. **n=8 per arm cannot separate close results.** See the Wilson table below. A result like 5/8
   specialist vs 3/8 generic is not evidence of anything at this sample size, and the honest report
   of such a result is "indeterminate", not "leaning specialist".
5. **`detect_all` is AND-of-substrings, not a semantic check.** A model that discusses the right
   function name and the right vocabulary word for an unrelated reason would score FOUND. This is
   a real, accepted false-positive risk, traded deliberately for the requirement that scoring be
   reproducible offline by anyone without a second model call. Each fixture's patterns were chosen
   to be as specific as a two-or-three-token AND can be on an eight-to-twelve-line file; nothing
   here would survive on a larger, noisier fixture.
6. **Two fixtures (`test-writer-1`, `test-writer-2`) are not defect-finding tasks.** The bug is
   already fixed; the task is writing the regression test for it. `detect_all` checks for evidence
   a targeted test was produced (the right function name, the right exception/keyword, the right
   edge-case vocabulary), not that the test actually passes when run -- this pilot does not execute
   pytest against any arm's output. A test-writer arm that writes a plausible-looking but broken
   test would still score FOUND. Flagged, not fixed, because fixing it means executing arbitrary
   generated code from three arms across 4 cells, which is its own instrument.
7. **QA fixtures (`qa-1`, `qa-2`) do not require execution to solve.** Both bugs are visible by
   reading the arithmetic in the function -- an arm that never runs the script can still state the
   correct and buggy values by mental calculation and score FOUND. This measures "did the arm name
   the defect", not "did the arm follow the qa persona's own process of running the real thing".
   Those are different questions; only the first is what this pilot's scoring answers.
8. **The role-to-tools table in `run.sh` is a hand-copied snapshot (2026-08-26) of each
   `claude/agents/<role>.md`'s `tools:` frontmatter line.** If that line changes upstream without
   this table being updated, the direct arm's tool grant silently stops matching the specialist
   arm's actual tools, and "held equal" quietly stops being true.

## Sample size, honestly

Two-sided 95% Wilson intervals at n=8 (following the convention `tests/evals/build-the-lever/PREREGISTRATION.md` set):

| k/8 | interval |
|---|---|
| 0/8 | [0.00, 0.32] |
| 1/8 | [0.02, 0.47] |
| 2/8 | [0.07, 0.59] |
| 3/8 | [0.14, 0.69] |
| 4/8 | [0.22, 0.78] |
| 5/8 | [0.31, 0.86] |
| 6/8 | [0.41, 0.93] |
| 7/8 | [0.53, 0.98] |
| 8/8 | [0.68, 1.00] |

At n=8, only the extreme bands are separable: 0/8 or 1/8 against 7/8 or 8/8 do not overlap.
Anything less than that gap -- which is most of the plausible outcome space if H0 is true -- is
**indeterminate** and must be reported as indeterminate. This pilot is sized to notice a large,
categorical effect (a specialist that turns "never" into "almost always"), not to rank two arms
that both do moderately well. That is a deliberate consequence of the 25-call budget fixed by the
brief that authorized this instrument, stated here rather than discovered by a reader doing the
arithmetic later.

## Cost, stated before anyone can spend it

25 `claude -p` calls, `--model sonnet`, serial.

- **Tokens:** not measured, because nothing has run. Estimated from this repository's own prior
  harness runs (`RESULTS.md`'s review-pathway benchmark) and from the fixture sizes here (8-20
  lines of source per fixture, task prompts under 100 words): roughly 10k-20k tokens per direct or
  generic-subagent cell, higher for specialist cells carrying a full agent system prompt and for
  test-writer cells whose output includes generated file content. Estimated total: **250k-500k
  tokens** across all 25 calls. This is a stated estimate, not a measurement, and should be
  labeled as such in any report that cites it.
- **Wall-clock:** direct-arm cells are a single agent loop; generic and specialist cells nest a
  nested Task nested agent loop inside the outer session, which is the slower half. Estimated
  45-150 seconds per cell, serial execution (no parallelism in `run.sh`), roughly **20-60 minutes
  wall-clock** for the full 25-call run.
- **Runner refuses without opt-in.** `run.sh` requires both `--go` and
  `AGENT_PILOT_CONFIRM="RUN THE 25 CALLS"` (exact string) before any of the above is spent; the
  default invocation prints this same plan and exits without calling anything.
