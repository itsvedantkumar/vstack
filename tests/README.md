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
hand-built transcripts straight into the hook and asserts on what the hook decided, with no gate
scaffolding in between. Run it by hand when touching the breadth-counting logic and you want to
see the hook's raw decision for a case, not just pass/fail:

```bash
tests/test-breadth-mandate.sh
```

The four cases it drives are one directory of same-extension fixtures, a real multi-directory
multi-extension change, the same change after an attributed `Task` call, and a wide
same-extension sweep. Check 27 of `.claude/verify.sh` (`skill mandate decides correctly`) covers
overlapping ground in cases h/i/j and is what the gate enforces on every run, but the two sets are
not the same. Check 27 has no delegation-suppression case at all, and its case `i` accepts any
block rather than requiring the block to name the breadth mandate, so an unrelated mandate firing
would satisfy it. This script asserts the specific `multi-directory work --` line.

This script is the harness that found the two shapes check 27 was missing before it had cases for
them: five fixture writes to one directory that the first version of the mandate counted as five
distinct things instead of one, and three dotfiles (`.editorconfig`, `.gitignore`, `.npmrc`)
across three directories that the second version read as three different file extensions.

It reads the hook's stdout JSON, not its exit code. That distinction is the whole reason the file
is trustworthy: the hook exits 0 whether it blocks or not, so an earlier version of this script
was structurally incapable of failing, and reported a pass over a block it never looked at. The
gate is still the source of truth; this is the fast way to reproduce a decision by hand.

## team-gating.sh

Asks whether `/team` holds the bar or only says it does. `team-gating.sh` runs the command against
`tests/fixtures/team-fail/`, where `tests/fixtures/team-fail/slugify.py` is planted to fail three of
the five criteria in `tests/fixtures/team-fail/test_slugify.py` — plain stdlib, no pytest, so it runs
on every CI lane. `tests/fixtures/team-fail/README.md` explains why that fixture is the ground truth: whether a delegation was good is a judgement nobody
can score, whether the lead stopped when told the work was broken is a fact.

Costs model allowance. It opens with a control that refuses the run if the fixture passes its own
tests, because a fixture with nothing wrong in it makes every assertion below vacuous.

## container-matrix.sh

`tests/container-matrix.sh` runs `install.sh`, `bin/doctor`, `.claude/verify.sh`, the mandate and
destructive-command hooks, `vstack trust`, `vstack update` and `uninstall.sh` inside real
`debian:stable-slim`, `alpine:latest` and `ubuntu:latest` containers. It clones from published
GitHub with no worktree mounted and no credentials, so it tests the artifact a stranger gets
rather than the tree it was written in.

That is the difference between this and `install-matrix.sh`. The matrix has a `bash-only` lane
because "only .zshrc/.zshenv were written" once shipped and broke every Debian, Ubuntu and Alpine
box, but its lanes simulate those environments on macOS. Real BusyBox coreutils, a real `ash` as
`/bin/sh`, a real GNU userland and a genuinely absent `jq` are what this suite adds. Its first run
found `bin/doctor` exiting 1 on a clean Alpine install, because the `date` fallback chain covers
BSD and GNU and BusyBox supports neither.

One assertion cannot be met here and the suite says so rather than lowering the bar: the gate
reports `1 skipped` in every lane, because `plugin manifests valid` needs an authenticated
`claude` CLI and no credentials are mounted. That is a structural limit of running without
credentials, not a passing result.

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
`dispatch-fleet.sh`'s schema=2 runlog header records the model, turn cap, tool fence and fixture
file every arm ran under, and refuses to append samples from a different invocation rather than
mix two arms into one k/n. That guard caught a real case: the 55-sample collision arm in
`/private/tmp/vstack-dispatch-pilot-col.jsonl` was produced by a local uncommitted edit to the
harness, so nothing in git could rebuild its instrument. The fence is committed now, but the
default has since gained `Explore` and `Task`, so resuming that specific arm needs its original
fence named explicitly:

```bash
DISALLOWED_TOOLS="Write,Edit,MultiEdit,NotebookEdit,Bash,Agent,Workflow" \
MAX_TURNS=20 MODEL=sonnet FIXTURES=~/vstack-dispatch/fixtures.jsonl \
RUNLOG=/private/tmp/vstack-dispatch-pilot-col.jsonl ./tests/dispatch-fleet.sh col-11
```

Without that line, the arm was reproducible only for as long as its own runlog survived, since the
header was the sole record of what produced it.

`tests/evals/build-the-lever/run.sh` is a single-question harness rather than a scoring pathway: it
asks why `principle-build-the-lever` fires as rarely as it does, against the thresholds frozen
in `evals/build-the-lever/PREREGISTRATION.md` before the first sample was drawn. Every
hypothesis it registered was falsified; the standing answer it recorded is that the skill does
not fire because the model already does the thing.

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

## A harness change invalidates its own prior findings until the control re-runs

On 2026-08-23, five commits landed in `auto-trigger.sh` in one session -- the `Agent` tool
denied in `--disallowedTools`, a filesystem fence asserting nothing escapes a case's workdir,
the `error_max_turns`-vs-ran-to-completion split, and per-case `MAX_TURNS` overrides. Every one
of them touches the exact code path `auto-trigger.sh` exists to measure: what the model is
allowed to do and how long it gets to do it. Rate numbers gathered before those commits were
then compared against numbers gathered after, and a difference between them was reported as a
finding about skill dispatch. It was at least partly a finding about the harness.

The fix that day was a control: one case with a long, boring history of passing on attempt 1
(`root-cause-guard`), sampled n=10 independently alongside whatever was actually in question. It
came back 9/10, which is what made the other three numbers in that run readable as findings
rather than as "something in the last five commits broke everything." That control was run once,
after all five commits, not once per commit -- so it validates the harness as it stands now, not
each intermediate state it passed through, and comparisons against any number gathered before it
are not supported by it.

**The rule this earns:** after any change to `auto-trigger.sh` that touches tool availability,
turn budgets, retry logic, or anything else in the path between a prompt and a `Skill` tool_use,
re-run a stable control case at n well above 1 before trusting a rate number gathered against the
new state -- including a rate number from before the change, compared against one from after.
Skipping the control doesn't make the harness wrong; it makes the next finding unfalsifiable,
because a regression in the harness and a regression in dispatch produce the same printed output.

## team-start.sh

`tests/team-start.sh` measures, rather than asserts, the two properties `CLAUDE.md`'s NAME THE
AGENT policy and the delegation mandate only state in prose: does a session that plainly warrants
delegation issue an `Agent` tool_use, and does the assistant's own text name a roster call sign
when it does. Three positive fixtures that meet `skill-mandate.sh`'s own breadth threshold, one
negative — a one-line typo, `team.md`'s explicit "does not need the ceremony" case. n=5 per
fixture, raw k/5, no retry-to-first-hit, because a loop that stops at first success measures
whether it ever happened rather than how often.

**It refuses to spend a call when the installed `~/.claude/hooks` differ from this checkout**
(override with `VSTACK_ALLOW_HOOK_DRIFT=1`). Its own first run spent 9 samples against stale
hooks before that was caught, and they were discarded rather than folded in. Any harness that
probes the live CLI needs this preflight: a measurement of code you did not ship is a number
about a different program.

```bash
tests/team-start.sh
```

## compaction-effect.sh

Zero-model-call local parsing: does auto-compaction at the configured `autoCompactWindow`
correlate with worse behaviour in the turns right after it? Streams this machine's own
`~/.claude/projects/*/*.jsonl`, and around each `compact_boundary` compares tool_result
`is_error` rate, Read/Grep re-reads of files already touched, and near-duplicate user turns in a
fixed window before and after, split by auto- versus manual-trigger.

Correlational only, and the script says so in its own header: a session that reaches the trigger
is longer and harder than one that never does, so any spike is association rather than cause.
Thresholds are pre-registered in the header, written before real data was read.

```bash
tests/compaction-effect.sh
```

**Read the sample size before the verdict.** Of 3,134 transcripts on this machine, only **8**
contain a compaction event, because `autoCompactWindow` was set on 2026-08-23 and the corpus
mostly predates it. The auto-trigger arm has 2 qualifying boundaries and reports NOT EVALUATED
rather than a rate. The manual arm shows no signal at n=6, which is not evidence of no effect —
it is too little data to detect anything short of a large one. Re-run this once the corpus has
grown; the script needs no changes to become useful, only time.

## Shell traps this repo has actually hit

Each of these cost someone real time here. They are recorded because the next person will write
the same line.

**macOS ships bash 3.2.57.** No `mapfile`, no associative arrays. A `case` nested inside a `while`
nested inside `$(...)` fails to parse outright with `syntax error near unexpected token ';;'` —
reproduced standalone in four lines while refactoring the gate. Use `[[ ]]` glob tests instead.
Run `bash -n` immediately after any edit rather than waiting for the gate.

**BSD `sort` has no `-V`.** Version comparison has to be hand-rolled, because a string sort puts
`1.9.0` above `1.10.0`. Check 39 does this.

**`while read x < file; do gh ...; done` shares stdin with the loop body.** Any command inside the
loop that probes fd0 eats the list. `gh release create` hung for five minutes this way. Redirect
the list to a spare descriptor: `done 3< file` with `read x <&3`, so the body's stdin stays free.

**`status` is a read-only special variable in zsh.** It already holds the last command's exit code,
so `status=$?` aborts the script with `read-only variable: status` rather than failing cleanly at
the point of use. Use `rc=$?`.

**Redirections apply left to right.** `: > "$log" 2>/dev/null` does not suppress the failure of
`> "$log"` — the `2>/dev/null` is set up after the redirect that fails. Write
`: 2>/dev/null > "$log"`.

**`cd "-x"` parses as an option, not a path.** Without `--`, a bad argument produces
`cd: invalid option` on stderr ahead of your own error message. Use `cd -- "$d"`.

**`cmd | grep -q` returns 141 under `set -o pipefail`.** `grep -q` exits on first match and SIGPIPEs
the writer. This has inverted three checks in this repo. Use `grep -q ... <<<"$var"`.

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

## plugin-manifests.sh

`plugin-manifests.sh` needs an authenticated CLI but spends no tokens and makes no model call. It
proves the CLI accepts `.claude-plugin/marketplace.json` and `claude/.claude-plugin/plugin.json`,
with a positive control in both directions, and that every skill, command, agent and `hooks.json`
script reference resolves to a file on disk. This is the check `container-matrix.sh` can never
run, because a throwaway container never installs `claude` — that lane reports
`UNMEASURABLE WITHOUT CREDENTIALS` and stays that way on purpose rather than being folded into a
pass.

It covers one thing `verify.sh` check 19 does not: `claude plugin validate` reads only the two
manifest files, so a skill directory whose frontmatter the loader silently drops passes it. This
harness cross-references `claude plugin details`'s live component inventory against the tree and
fails on that.

Known gap: `hooks.json` names three of the six scripts under `claude/hooks/` directly. The other
three are invoked from inside those, so renaming one of them is not caught here.

## dispatch-fleet.sh

`dispatch-fleet.sh` measures the 54-fixture set in `~/vstack-dispatch/` — recall, precision,
`AMBIGUOUS`/`CHAIN` splits and paraphrase delta, each scored separately. It is broader than
`auto-trigger.sh` and answers a different question: not "does this one situation still route
there" but "does a library of 28 skills compete with itself." Samples are non-retrying. Real
calls sit behind a confirmation gate; the file header carries the sample definition and the
exit-code contract.

Do not read a blended number off it. Recall and precision are reported apart on purpose, and the
`AMBIGUOUS` cases are distributions rather than pass/fail — a 50/50 split and a 100/0 split are
different findings and both matter.

## Reproductions

`repro/` holds one script per confirmed defect, each red until its fix lands. See
`tests/repro/README.md` for the current table.
