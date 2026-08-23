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
`claude -p "<prompt>"` headlessly for 28 prompts that should each cause a
specific skill to auto-fire, inspects the `stream-json` transcript for
`Skill` tool_use blocks, and reports PASS/FAIL per case.

## dispatch-static.sh

`dispatch-static.sh` runs in CI on every push and makes zero model calls. It proves the fixtures
`auto-trigger.sh` depends on are internally consistent: every skill name a case expects resolves to
a real `claude/skills/*/SKILL.md`, every `setup_*` function a case references is actually defined,
every fixture those functions write parses under its own language's parser, and the case count this
file claims matches the number of cases in the suite.

It does not prove a skill fires. It would stay green the day dispatch broke entirely, because an
intact fixture list and a live `Skill` tool call are two different facts. Only `auto-trigger.sh`
measures the second one, and that cannot run in CI here by deliberate decision: it needs an
`ANTHROPIC_API_KEY` secret and spends model allowance per run. See the section below.

## test-breadth-mandate.sh

A standalone reproduction script for the delegation mandate in `skill-mandate.sh`: it feeds four
hand-built transcripts straight into the hook and prints what the hook decided, with no gate
scaffolding in between. Run it by hand when touching the breadth-counting logic and you want to
see the hook's raw stdout/exit code for a case, not just pass/fail:

```bash
tests/test-breadth-mandate.sh
```

The four cases it drives -- one directory of same-extension fixtures, a real multi-directory
multi-extension change, the same change after a `Task` call, and a wide same-extension sweep --
are also codified as cases h/i/j inside check 27 of `.claude/verify.sh` (`skill mandate decides
correctly`), which is what the gate actually enforces on every run. This script is the harness
that found the two shapes check 27 was missing before it had cases for them: five fixture writes
to one directory that the first version of the mandate counted as five distinct things instead of
one, and three dotfiles (`.editorconfig`, `.gitignore`, `.npmrc`) across three directories that
the second version read as three different file extensions. Kept here as the fast, no-gate way to
reproduce a mandate decision by hand; the gate is the source of truth.

## team-gating.sh

Asks whether `/team` holds the bar or only says it does. `team-gating.sh` runs the command against
`tests/fixtures/team-fail/`, where `tests/fixtures/team-fail/slugify.py` is planted to fail three of
the five criteria in `tests/fixtures/team-fail/test_slugify.py` — plain stdlib, no pytest, so it runs
on every CI lane. `tests/fixtures/team-fail/README.md` explains why that fixture is the ground truth: whether a delegation was good is a judgement nobody
can score, whether the lead stopped when told the work was broken is a fact.

Costs model allowance. It opens with a control that refuses the run if the fixture passes its own
tests, because a fixture with nothing wrong in it makes every assertion below vacuous.

## bin-scripts.sh

`bin/claude-bg.sh`, `bin/claude-task.sh` and `bin/deploy-auto.sh` install to every user's
`~/.config/agents/bin/` via `install.sh`'s wholesale copy of `bin/*`, whether or not anyone has
ever run them. Checks 1 and 29 of the gate already run `bash -n` and `shellcheck -S warning` over
all three, so their syntax was covered; nothing exercised their behaviour. `bin-scripts.sh` does,
entirely offline: every `claude`/`vercel`/`wrangler`/`curl` it invokes is a local stub, so it costs
zero model calls and never reaches the network.

It covers, for each script: `bash -n` and `shellcheck` (at default severity, stricter than the
gate's `-S warning`, which is how it catches an info-level finding the gate does not), argument
handling (no args, `--help`, a bogus flag, too many args), running from an unrelated cwd, and
running under a `cron`/`launchd`-shaped environment (`env -i`, a bare `PATH`, stdin from
`/dev/null`). `bin/claude-task.sh` gets three more cases specific to it: a missing task
directory, a task directory with no `SKILL.md`, and an unwritable log directory — the unattended
path the README markets safety around, and the one nobody had run and looked at. A positive
control (two synthetically broken scripts) proves the `bash -n`/`shellcheck` checks above can
actually go red before trusting either to report clean.

Usage: `tests/bin-scripts.sh [case-name ...]` (default: all).

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

## Why auto-trigger.sh cannot run in GitHub Actions

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

The owner of this repository was asked in August 2026 whether to add an `ANTHROPIC_API_KEY` secret
and run this nightly, and declined. That is a standing decision, not an oversight. The consequence
is recorded here rather than papered over: **skill dispatch is unmeasured on CI, and has been since
this repository existed.** `dispatch-static.sh` recovers the free part of it and says in its own
header that it is not a substitute.

## Before you edit: this checkout may not be yours alone

Several Claude sessions edit `~/Projects/vstack` directly, because changes belong in the canonical
repo rather than in a per-workspace worktree. That makes concurrent writes to one checkout normal
here, not exceptional.

On 2026-08-23 two sessions were in this tree at once. One ran `git add -A` and pushed a commit
whose message described a documentation change while the diff also carried three of the other
session's uncommitted security fixes. They shipped unversioned and unchangelogged, and the next
release had to document the mislabeled history in its own tag. The committing session had checked
`git status` and found it clean, minutes earlier.

Two things came out of it, and only one of them is a mechanism.

The mechanism: the destructive guard asks before `git add -A`, `git add .`, `git add --all`,
`git commit -a`, `git commit -am` and `git commit --all`, when `CONDUCTOR_WORKSPACE_PATH` is set
and the working directory sits outside it. Check 23 asserts both directions.

What the mechanism does not do, stated plainly so nobody reads the guard as a solution: it narrows
the window and nothing in this repo closes it. Two sessions editing the same file still interleave,
the guard says nothing about it, and a session outside Conductor gets no prompt at all. The
protection that actually worked that day was manual. One session announced which files it held over
SendMessage, and the other declined to start an agent in the same region until it was told the
file was free. Later the same day one of them moved its agent into an isolated git worktree
instead, which removes the question rather than negotiating it.

So: announce the paths you are taking, stage explicit paths rather than wildcards, re-read
`git status` immediately before committing rather than at the start, and prefer a separate worktree
over a hand-held lock when the work is more than a few minutes.

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
