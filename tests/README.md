# tests/

Two suites, with opposite constraints.

`gate-falsifiability.sh` runs offline in about 30 seconds and CI runs it on every push. It
proves `.claude/verify.sh` can actually fail.

`auto-trigger.sh` needs an authenticated CLI and spends real tokens, so it runs by hand. It
proves skills still fire on the situation.

## gate-falsifiability.sh

A check that cannot fail is indistinguishable from a check that is not there, and this repo has
shipped both. Check 11 read two of three hook lanes while its label claimed otherwise. Check 12
asserted only that a correct number appeared somewhere, so a wrong one shipped beside it. Three
checks were wrapped in a bare `if command -v jq` with no else and printed nothing at all on a
host without jq. Every one of those was green the whole time.

For each declared check the suite breaks exactly what that check watches, requires the gate to
go red naming it, restores the file byte for byte, and confirms the tree is unchanged at the
end. It compares against the working tree as it found it, not against HEAD, so it is safe to
run mid-change.

**Adding a check to `verify.sh` means adding a row here.** Check 16 of the gate fails otherwise.
A row is three things: the files it edits (`files_for`), the label the gate must print
(`label_for`), and the mutation (`break_it`).

Make the mutation surgical. One that trips four checks proves far less than one that trips the
intended check, and a mutation that lands somewhere unreachable proves nothing at all while
looking like it passed — appending `exit 3` to the end of `install.sh` did exactly that, because
the dry-run path exits before reaching it.

## What this proves

This setup's core property is that Claude Code skills fire on the situation
described in a prompt, without a slash command. That mechanism is the SKILLS
routing block in `claude/hooks/inject-session-context.sh` plus the
natural-language `description` field on each skill. It has already broken
silently once (0 of 4 test prompts fired a skill) with nothing to catch the
regression.

`auto-trigger.sh` is a black-box regression test for that property. It runs
`claude -p "<prompt>"` headlessly for 12 prompts that should each cause a
specific skill to auto-fire, inspects the `stream-json` transcript for
`Skill` tool_use blocks, and reports PASS/FAIL per case.

## team-gating.sh

Asks whether `/team` holds the bar or only says it does. `team-gating.sh` runs the command against
`tests/fixtures/team-fail/`, where `tests/fixtures/team-fail/slugify.py` is planted to fail three of
the five criteria in `tests/fixtures/team-fail/test_slugify.py` — plain stdlib, no pytest, so it runs
on every CI lane. `tests/fixtures/team-fail/README.md` explains why that fixture is the ground truth: whether a delegation was good is a judgement nobody
can score, whether the lead stopped when told the work was broken is a fact.

Costs model allowance. It opens with a control that refuses the run if the fixture passes its own
tests, because a fixture with nothing wrong in it makes every assertion below vacuous.

## evals/

`evals/run-pathways.sh` and `evals/swebench/run.sh` score this bundle against
other Claude Code setups and against unconfigured Claude Code. `evals/optimize.sh` drives the
change-one-thing-and-re-measure loop on top of `run-pathways.sh`; it scores against
`evals/holdout/` only through `--validate`, and never uses that set to decide whether to keep a
change. `evals/RESULTS.md` records every run, including the retracted one.

These cost real model calls and are not part of the gate.

## Run the tests

```bash
tests/auto-trigger.sh
```

The script requires `claude` on `PATH`, `jq`, and an authenticated session
(`claude auth status` reporting `loggedIn: true`). If any is missing, the
script prints `SKIP: ...` and exits 0. That is a valid, non-failing outcome,
not a bug in the test.

Each case runs in its own `mktemp -d` under `/tmp` (never this repo), so
nothing here pollutes the working tree the model sees. The test suite covers 28 cases:
readme-writing, typescript-review, swarm-audit, blast-radius-auth, feature-chain,
root-cause-guard, overnight-audit-trail, ui-iterate-styles, component-registry-combobox,
idempotent-cron, negative-arithmetic, and negative-factual.

## Why this cannot run in GitHub Actions

1. **Headless auth.** `claude -p` needs a logged-in session
   (`claude auth status`). CI runners have no browser or OAuth flow and no
   long-lived credential this test can use, so `claude auth status` will
   never report `loggedIn: true` there. The script detects this and skips
   rather than failing the build.
2. **It would bill tokens.** Every case makes real API calls, up to 3 turns
   each across 28 cases. Running this on every push or pull request in CI
   would spend real money on a check that mostly guards against
   skill-routing regressions. Those regressions are infrequent. Run the
   script by hand instead, or schedule it on a machine that already has an
   authenticated session: local dev, or a scheduled job outside CI.

Run it by hand after touching `inject-session-context.sh`, a skill's
`description` frontmatter, or the skill-routing logic.

## Add a case

Edit `tests/auto-trigger.sh`:

1. If the prompt needs a file to react to, such as code to review, add a
   `setup_<name>()` function that writes it into `$1`, the case's temp dir.
2. Add a `run_case "name" "prompt" "expected_regex" "setup_fn_or_empty"` call
   in the "Test cases" section near the bottom. `expected_regex` is an
   extended regex matched against the set of skills that fired. One match
   is enough, so use `a|b` to accept either of two acceptable skills.
3. Run the script and confirm the new case prints `PASS`.

Write prompts the way a person would actually phrase the ask. Do not name
the skill directly. The point is to prove routing works from natural
language, not from an exact keyword match.
