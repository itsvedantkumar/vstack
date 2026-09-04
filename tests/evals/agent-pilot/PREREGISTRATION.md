# Pre-registration: does routing to a shipped specialist subagent help?

See `tests/evals/agent-pilot/README.md` for how to reproduce everything below, including the
scorer's offline self-test, which is the only execution this instrument performs before an
operator opts in.

Written before any of the 27 calls exist. Nothing in this file has been adjusted after seeing a
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

  Note 2026-09-04: comparisons against the none arm are no longer reported; see the maintainer's
  rule in tests/evals/showcase/RESULTS.md.
- The canary is never pooled into the 24-cell comparison. It exists to validate the harness, not
  to add a ninth data point to any arm.

## The canary, and why it is the most important 3 of the 27 calls

Twenty-four scored cells look exactly like real data whether or not the harness actually worked --
a wrong `subagent_type`, a fixture that never reached the model, a capture pipe that silently
dropped output, or a `detect_all` regex that cannot match anything would each still produce 24
rows of FOUND/NOT_FOUND that read as a result. The canary is designed so a broken harness produces
a **visibly wrong** canary result instead, cheaply, before the other 24 are spent.

**The fixture:** `canary/canary.py`, a `requests.put(..., verify=False)` call inside a plausible
`upload()` helper -- disabled TLS certificate verification, a man-in-the-middle risk on every call.
This is deliberately the single most obvious, least model-dependent defect this pilot could plant:
a hard defect would make a NOT_FOUND result ambiguous between "the harness is broken" and "the
model missed a genuinely hard case"; an obvious one removes that ambiguity. **Any arm that is
actually reading the file and saying anything about it will name disabled certificate
verification.** That is exactly why the canary is not one of the 8 scored fixtures -- it is not
testing whether a specialist beats a generic subagent, it is testing whether the pipe between "a
file exists" and "a verdict gets recorded" works at all.

**Why not the hardcoded-secret version this canary originally shipped as (changed 2026-08-26):**
the first draft planted an `AWS_SECRET_ACCESS_KEY` assignment holding AWS's own documented public
example access key ID -- the string starting `AKIA` that AWS's own docs use as a placeholder
everywhere, not a real credential -- chosen for exactly the same "obvious and model-independent"
reason. It collided with this repository's own gate: `.claude/verify.sh` check 5 (no committed
secrets) matches that `AKIA`-prefixed shape on any tracked file, with no awareness that the string
is a fixture rather than a leak, and turned the gate red on this branch (this paragraph itself
does not spell the example key out contiguously, on purpose, so that describing the fix does not
retrigger the same check). The fix was **not** a
path-scoped exemption for `canary/canary.py` -- an exemption to the secret scanner is a permanent
narrowing of a real security claim traded for one fixture's convenience, and it is also exactly the
shape an attacker benefits from having present. The fix was to change the fixture. `verify=False`
is chosen because it is equally unmistakable to any arm that reads the file, equally
model-independent, and contains nothing shaped like a key, token, or password -- it cannot trip
check 5's `AKIA[0-9A-Z]{16}` pattern or its generic `(KEY|TOKEN|SECRET|PASSWORD)[A-Za-z_]*=[A-Za-z0-9_/+-]{20,}`
alternative, confirmed by replaying both patterns against this fixture and against every other file
in `tests/evals/agent-pilot/` before committing. **If a future editor is tempted to make this
canary "more realistic" by swapping in something credential-shaped again, don't -- that is the
exact change that broke the gate the first time, and the TLS-verification version is not a
downgrade in how obvious or how model-independent it is, only in how much it resembles a secret.**

**The arms: all three, not one.** The original design ran the canary only through `security-auditor`
specialist, on the reasoning that it exercises the most machinery -- a sandboxed `PILOT_HOME`, a
copied `claude/agents/security-auditor.md`, a forced `Task` dispatch naming that `subagent_type` --
so a pass there is stronger evidence than a pass through the direct arm, which has no delegation
step to get wrong. That reasoning is still true, but it proves too little: the specialist arm's
`Task` dispatch names `subagent_type=security-auditor` and installs an agent file; the generic
arm's `Task` dispatch names `subagent_type=general-purpose` and installs nothing. These are
different code paths inside `run_cell()` and a different resolution inside the CLI, and a green
specialist canary says nothing about whether the generic arm's dispatch resolves at all, or
whether the direct arm's simpler no-delegation path (the one carrying the least apparatus, and by
that same logic the least likely to be the one that's broken) actually delivers the fixture either.
**Minimum coverage that answers "is the harness wired correctly" for all three arms this pilot
compares is one canary call per arm -- three calls, not one.** That is the deviation from the
original 25-call brief this file now runs: 24 scored + 3 canary = 27. `ground-truth.json`'s
`.canary` entry no longer pins a single `arm`; `run.sh`'s `enumerate_canary_cells()` loops the same
fixture across `direct`, `generic`, and `specialist`, producing `canary-direct`, `canary-generic`,
`canary-specialist`.

**Expected verdict: FOUND, on all three.**

**What each other verdict means, on any of the three arms, stated in advance so nobody improvises
an explanation after seeing one:**

- **NOT_FOUND** -- the call ran, produced real output, and never named the vulnerability. On a
  defect this obvious, that is not a competence result, it is the strongest available signal that
  something in that arm's harness plumbing is broken: for `specialist`, the wrong `subagent_type`
  was dispatched or the copied agent file didn't land; for `generic`, the `Task` dispatch to
  `general-purpose` didn't happen or didn't receive the fixture; for `direct`, the fixture was never
  actually delivered into the working directory the model saw, or the tool grant blocked reading
  it. It can also mean `detect_all`'s patterns are broken and cannot match true-positive text
  either -- check that first, since it is the one explanation common to all three arms failing
  together. **Do not read the 24 scored rows for an arm whose canary is not FOUND; diagnose that
  arm's harness first.**
- **NOT_RUN** -- the call never completed: authentication failing under the reassigned
  `PILOT_HOME` (see "Precondition" below -- this is no longer a hypothetical for this pilot, it is
  a confirmed failure mode this file's `AGENT_PILOT_AUTH_MODE` gate exists to make the operator
  choose about explicitly), a `subagent_type` rejected by the CLI (a typo, a stale agent file), or
  the per-call timeout being too short for a nested subagent dispatch.
- **NOT_CAPTURED** -- the call finished but the capture pipeline lost the output. Look at the
  redirection in `run_cell()`, not at the model.

A non-FOUND canary on any one arm is not "one bad data point to discard" -- it invalidates
interpretation of that arm's 8 scored rows (2 fixtures x 4 roles) until the specific cause is found
and fixed, because the same per-arm plumbing produced all of them. A non-FOUND canary on all three
arms simultaneously usually means the shared cause (`detect_all`, the fixture file, or
authentication), not three independent failures.

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
3. **Resolved, not just flagged (2026-08-26): a reassigned `HOME` does not authenticate on this
   machine.** See "Precondition" below for the full evidence and the two accepted responses
   (`AGENT_PILOT_AUTH_MODE=api-key` or `=keychain-symlink`). What remains an open risk, not fully
   closed: `keychain-symlink` mode has been verified to make `claude auth status` report
   `loggedIn: true`, but has not been exercised through an actual `claude -p` call under this
   pilot's exact flag set (`--model`, `--max-turns`, `--allowedTools`, `--output-format=stream-json`)
   without spending one -- that first real confirmation is exactly what `--canary-only` is for.
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
8. **Fixed, not just flagged (2026-08-26): `run.sh`'s `role_tools()` reads each role's tool list
   at run time from `claude/agents/<role>.md`'s own `tools:` frontmatter line** -- there is no
   longer a hand-copied table to go stale. `check_design_matches_ground_truth()` calls
   `role_tools()` for every role before printing a plan and refuses to run if any agent file is
   missing or its `tools:` line does not parse, so a broken source is caught before a call is
   spent rather than producing a silently wrong tool grant. What this does not solve, because
   nothing can from outside the CLI: the generic arm's actual toolset (item 1, above) is still
   whatever `general-purpose` defaults to, not something this file derives or pins.

## Precondition: authentication under a reassigned `HOME`, resolved before any call

Established without spending a model call, using only `security find-generic-password`
(reads metadata -- service name, account -- never the secret) and the CLI's own
`claude auth status` subcommand (checks login state, makes no model call):

- Under the real `$HOME`: `claude auth status` reports `loggedIn: true`.
- Under `env HOME=$(mktemp -d) claude auth status`: `loggedIn: false, authMethod: "none"`.

**A reassigned `HOME` does not authenticate on this machine.** Root cause: this machine's Claude
Code credential is stored in the macOS login Keychain under service name
`"Claude Code-credentials"`, and Keychain Services resolves the default keychain search list via
`$HOME/Library/Keychains/`, confirmed HOME-dependent by a direct `security find-generic-password`
probe under both HOME values. This is a second, independent failure from the one this repository's
own memory already records for `CLAUDE_CONFIG_DIR` isolation (pointing that at a fresh directory
makes the CLI report "not logged in" because `~/.claude.json`'s account metadata is missing,
before the CLI ever consults the keychain) -- a bare `HOME` reassignment fails here for a second,
independent reason on top of that first one, and copying `.claude.json` alone does not fix it.

A working technical fix exists and was verified the same way (`claude auth status` -> `loggedIn:
true` under the reassigned `HOME`): symlink `$PILOT_HOME/Library/Keychains` to the real
`$HOME/Library/Keychains`, read-only, created only inside the throwaway sandbox, never writing to
or copying the real `Keychains` directory itself.

**This fix is not this file's default**, because it is not free: every one of the four roles this
pilot dispatches (code-reviewer, security-auditor, qa, test-writer) carries `Bash` in its declared
tool list, so a symlinked `Keychains` directory hands every dispatched subagent -- including the
unaudited built-in `general-purpose` agent used by the generic arm -- filesystem access to the
operator's **entire** real login keychain, not just the one Claude Code entry. That is a larger and
qualitatively different risk than "the pilot cannot authenticate," and it is exactly the class of
exposure the brief that authorized this instrument exists to keep out of a sandbox built to
"never touch the operator's real `~/.claude`."

`run.sh` resolves the tension in the file, not at run time, by requiring the operator to name the
mode explicitly via `AGENT_PILOT_AUTH_MODE` (no default; refuses to run without it, for either
`--go` or `--canary-only`):

- **`api-key`** (recommended): requires `ANTHROPIC_API_KEY` already set in the invoking shell.
  Nothing is copied or symlinked into `PILOT_HOME` at all -- the emptiest, safest sandbox this
  design can produce, and the one that keeps the "never touch real `~/.claude`" property intact
  with no caveat. Its cost is not technical: it moves spend from the operator's unbilled Max-plan
  OAuth session to pay-per-token API billing, which is a separate authorization this file does not
  grant on its own (this operator's standing policy is that costed spend needs an explicit ask).
- **`keychain-symlink`**: accepts the full-keychain-exposure risk above, knowingly. `run.sh` prints
  an explicit warning naming that exposure every time a cell activates under this mode; it is not
  silent, and it is not the thing that happens by default when a sandbox merely reassigns `HOME`.

Neither the `save/restore` pattern of `tests/evals/run-pathways.sh`/`tests/evals/false-done/run.sh`
nor a `tests/lib-collision-guard.sh`-style restore-that-refuses-on-foreign-change was adopted here,
because neither is needed: this instrument never writes to the real `$HOME/.claude` in the first
place (see `run.sh`'s "SANDBOXING" header), so there is nothing on that path to restore. The
tension RICK's review raised -- that the recorded workaround for this class of problem elsewhere in
this repository is "patch and restore the real `~/.claude/settings.json`," which is in direct
tension with sandbox discipline -- does not apply to this file's design, because this file solves
authentication without ever touching the real config directory at all, under either
`AGENT_PILOT_AUTH_MODE`.

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

27 `claude -p` calls total (24 scored + 3 canary, one per arm -- see "The canary" above for why the
count grew from the original 25-call brief), `--model sonnet`, serial. `run.sh --canary-only` spends
only the 3 canary calls and is the recommended first run.

- **Tokens:** not measured, because nothing has run. Estimated from this repository's own prior
  harness runs (`RESULTS.md`'s review-pathway benchmark) and from the fixture sizes here (8-20
  lines of source per fixture, task prompts under 100 words): roughly 10k-20k tokens per direct or
  generic-subagent cell, higher for specialist cells carrying a full agent system prompt and for
  test-writer cells whose output includes generated file content. Estimated total: **10k-15k
  tokens** for `--canary-only` (3 calls), **270k-540k tokens** for the full 27-call `--go` run. This
  is a stated estimate, not a measurement, and should be labeled as such in any report that cites
  it.
- **Wall-clock:** direct-arm cells are a single agent loop; generic and specialist cells nest a
  `Task`-dispatched agent loop inside the outer session, which is the slower half. Estimated
  45-150 seconds per cell, serial execution (no parallelism in `run.sh`): roughly **3-8 minutes**
  for `--canary-only`, **20-65 minutes** for the full `--go` run.
- **Runner refuses without opt-in, three separate ways.** `run.sh` requires an action flag
  (`--go` or `--canary-only`), the matching literal `AGENT_PILOT_CONFIRM` string
  (`"RUN THE 27 CALLS"` or `"RUN THE CANARY"` respectively -- deliberately different strings so
  approving one cannot be mistaken for approving the other), and `AGENT_PILOT_AUTH_MODE` set to
  `api-key` or `keychain-symlink` (see "Precondition" above) before any of the above is spent. The
  default invocation, or any invocation missing one of the three, prints this same plan and exits
  without calling anything.
