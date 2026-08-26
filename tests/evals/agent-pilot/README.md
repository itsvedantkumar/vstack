# agent-pilot -- a 27-call pilot on specialist-subagent routing

**This instrument has not been run.** No model call has been made under this directory. See
`tests/evals/agent-pilot/PREREGISTRATION.md` for the question, the null, the scoring function, the
exclusions, the canary, the cost estimate, and -- most importantly -- what could still produce a
confident wrong answer, all written before any call exists.

## What this is

Does routing work to a shipped specialist subagent (`code-reviewer`, `security-auditor`, `qa`,
`test-writer`) produce better output than doing it inline, or than routing it to a generic
subagent with no specialist prompt? Three arms, four roles, two fixtures per role:
4 x 2 x 3 = 24 scored calls, plus one canary fixture run on all three arms (a single-arm canary
does not prove the other two arms' distinct dispatch mechanisms work -- see `PREREGISTRATION.md`,
"The canary") = 3 more calls, 27 total. Full design in `PREREGISTRATION.md`.

This is a **pilot**, not a benchmark this repository is claiming an answer from. At n=8 per arm it
can only separate a categorical effect from noise (see the Wilson-interval table in
`PREREGISTRATION.md`); read the "Sample size, honestly" section before drawing any conclusion from
a number this produces.

## Reproduce the only thing that has actually run: the scorer's offline self-test

Zero model calls. Proves the four-verdict scorer against four hand-made transcripts.

```
bash tests/evals/agent-pilot/scorer.sh selftest
```

Expected: `PASS -- all four verdicts reproduced from hand-made transcripts.`, exit 0. It exercises:

- `tests/evals/agent-pilot/selftest/found-everything.jsonl` -> `FOUND`
- `tests/evals/agent-pilot/selftest/found-nothing.jsonl` -> `NOT_FOUND` (the adversarial case: a
  `tool_result` in this transcript contains both required tokens verbatim because it IS the
  fixture's source text, echoed back by a `Read` call; the assistant's own text denies finding
  anything. `NOT_FOUND` is only correct here because the scorer's haystack is
  assistant-authored content only, never `tool_result` -- see `scorer.sh`'s header.)
- `tests/evals/agent-pilot/selftest/truncated.jsonl` -> `NOT_CAPTURED` (valid exit status, but the
  JSON is cut off mid-stream -- a non-parsing capture, not an empty one)
- `tests/evals/agent-pilot/selftest/empty.jsonl` -> `NOT_RUN` (no exit-status marker was ever
  written for this case, simulating a call that never finished)

## See the plan without spending anything

```
bash tests/evals/agent-pilot/run.sh
```

Prints the full 27-cell matrix (role, fixture, arm, cell id), the cost estimate, and exits 0
without calling a model. This is also what happens if you pass `--go` or `--canary-only` without
the matching confirmation environment variable or the auth-mode variable -- the refusal is the
default, not a special case.

## Check the harness cheaply first: `--canary-only` (3 calls)

```
AGENT_PILOT_AUTH_MODE=api-key AGENT_PILOT_CONFIRM="RUN THE CANARY" \
  bash tests/evals/agent-pilot/run.sh --canary-only
```

Runs only the canary fixture, once per arm (`canary-direct`, `canary-generic`,
`canary-specialist`). Answers "is the harness wired correctly" for roughly a tenth of the full
run's tokens before spending the other 24 calls. All three rows should read `FOUND`; if any does
not, `PREREGISTRATION.md`'s "The canary" section says what each other verdict means for that arm,
and says explicitly: do not run `--go` until the cause is found.

`AGENT_PILOT_AUTH_MODE` is required for either mode below and has no default -- see
`PREREGISTRATION.md`'s "Precondition" section for why (a reassigned `HOME` does not authenticate
on this machine, confirmed via `claude auth status`, no model call spent establishing that):

- `api-key` -- requires `ANTHROPIC_API_KEY` already set in your shell; nothing is copied into the
  sandbox. Recommended. Moves billing to the API, not your Max-plan session -- a separate spend
  decision from the token cost above.
- `keychain-symlink` -- read-only-symlinks your real login Keychain into the sandbox so OAuth
  login carries over. Every arm here has `Bash`, including the unaudited built-in generic
  subagent, so this exposes your entire keychain, not just Claude Code's entry, to every arm for
  the run's duration. `run.sh` prints this warning again at the moment it activates.

## Running the actual 27 calls (NOT authorized by this deliverable; documented for the operator)

```
AGENT_PILOT_AUTH_MODE=api-key AGENT_PILOT_CONFIRM="RUN THE 27 CALLS" \
  bash tests/evals/agent-pilot/run.sh --go
```

The action flag, the exact `AGENT_PILOT_CONFIRM` value for that flag, and `AGENT_PILOT_AUTH_MODE`
are all required -- three separate gates, none defaulted. Read
`tests/evals/agent-pilot/PREREGISTRATION.md`'s cost section and "what could still produce a
confident wrong answer" section first.

Raw per-cell rows land in a `runs.tsv` under a fresh `mktemp -d` (`RUNLOG` env var overrides the
path), opened through `tests/evals/lib/runlog.sh` so a second invocation appends rather than
truncates. **Score the three `canary-*` rows first.** If any of their verdicts is not `FOUND`,
`PREREGISTRATION.md`'s "The canary" section explains what each other verdict means for that arm
and says explicitly: do not interpret that arm's 8 scored rows until the cause is found.

## Files in this directory

| path | what it is |
|---|---|
| `tests/evals/agent-pilot/PREREGISTRATION.md` | hypotheses, null, scoring function, exclusions, the canary, cost, and the pilot's own known weak points -- written before any call |
| `tests/evals/agent-pilot/README.md` | this file |
| `tests/evals/agent-pilot/ground-truth.json` | the 8 fixtures' tasks and `detect_all` patterns, plus the canary entry -- committed before any call |
| `tests/evals/agent-pilot/run.sh` | the runner. Refuses to spend a call without an action flag (`--go`/`--canary-only`), the matching `AGENT_PILOT_CONFIRM` string, and `AGENT_PILOT_AUTH_MODE` all set |
| `tests/evals/agent-pilot/scorer.sh` | the deterministic, offline, four-verdict scorer. No model grades another model's output here |
| `tests/evals/agent-pilot/fixtures/code-reviewer-1.py` | pagination off-by-one (floor division drops the last partial page) |
| `tests/evals/agent-pilot/fixtures/code-reviewer-2.py` | file handle leaked on the error path in `load_config()` |
| `tests/evals/agent-pilot/fixtures/security-auditor-1.py` | SQL injection via `%`-formatting into a query string in `find_user()` |
| `tests/evals/agent-pilot/fixtures/security-auditor-2.py` | command injection via `subprocess.run(..., shell=True)` in `convert_image()` |
| `tests/evals/agent-pilot/fixtures/qa-1.py` | Fahrenheit-to-Celsius CLI: floor division silently violates its own stated acceptance criterion |
| `tests/evals/agent-pilot/fixtures/qa-2.py` | discount CLI: percent-off never divided by 100, wildly wrong output |
| `tests/evals/agent-pilot/fixtures/test-writer-1.py` | `safe_divide()`, a just-fixed bug needing a regression test for the zero-denominator case |
| `tests/evals/agent-pilot/fixtures/test-writer-2.py` | `parse_csv_row()`, a just-fixed bug needing a regression test for a quoted comma |
| `tests/evals/agent-pilot/canary/canary.py` | the canary fixture: `requests.put(..., verify=False)`, disabled TLS verification -- chosen for being least model-dependent while containing nothing shaped like a credential (see `PREREGISTRATION.md`, "The canary", for why the earlier hardcoded-AWS-key version was replaced) |
| `tests/evals/agent-pilot/selftest/found-everything.jsonl` | hand-made transcript proving the `FOUND` verdict |
| `tests/evals/agent-pilot/selftest/found-nothing.jsonl` | hand-made transcript proving `NOT_FOUND`, including the tool_result adversarial case |
| `tests/evals/agent-pilot/selftest/truncated.jsonl` | hand-made transcript proving `NOT_CAPTURED` |
| `tests/evals/agent-pilot/selftest/empty.jsonl` | hand-made transcript proving `NOT_RUN` |

## What this pilot deliberately does not measure

- Whether vstack's skill library fires during any of these calls. Every arm's project directory
  contains only the fixture file, no `.claude/` overlay at all -- this isolates the
  specialist-subagent-prompt question from the skill-firing question `tests/evals/run-pathways.sh`
  already measured (and found null: zero skill invocations in sixty runs, `RESULTS.md`).
- Whether a test-writer arm's generated test actually passes when run, or whether a qa arm
  actually executed the fixture rather than reasoning about it statically. Both are named as
  explicit limitations in `PREREGISTRATION.md` (items 6 and 7), not silently assumed away.
- Any ranking between two arms that both do moderately well. n=8 per arm does not support it; see
  `PREREGISTRATION.md`'s Wilson-interval table.
