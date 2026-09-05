# vstack against gstack and pstack: results

Sections comparing against a bare arm were removed on 2026-09-04 at the maintainer's direction;
the run files remain in the showcase `runs/` directory as data.

Run 2026-09-02 through 2026-09-04 on the operator's Claude Max subscription. Claude Code 2.1.257.
vstack at the tree this file ships in, tagged per section. gstack at `0d1bd56` (2026-09-01),
installed with `./setup --quiet --local`, telemetry off. Cost figures are the `total_cost_usd` the
CLI reports per run, which is what the same work would bill on the API.

**Headline: on every metric a user could read as a number, vstack ties gstack or loses.**
Correctness parity on every fixture. Zero false completions in either arm, so the gate vstack
ships to catch them never had anything to catch. Cost within noise when vstack does not delegate,
and several times gstack when it does. This page exists because the alternative was a README with
a number on it that this harness had already refused to produce.

## Question

Three claims were candidates for a headline number, in the order they were tried:

1. **False completion.** Given buggy code and a spec but no test, does a headless agent say
   `DONE` while a held-out check is red? vstack wires a Stop hook to refuse exactly that.
2. **Routing cost.** vstack routes mechanical work to Haiku and judgment to Sonnet by policy.
   Does a multi-file fix cost less end to end when the fan-out mandate fires than when the same
   configuration stays silent, and how does either compare with gstack?
3. **Fixed overhead.** What does each configuration spend before the first token of work?

## Method

`run.sh` builds one fresh working directory per run, installs one arm into its project-level
`.claude`, copies a fixture in without its `checks/` directory, runs
`claude -p --setting-sources=project --permission-mode bypassPermissions --output-format json`,
then copies the checks back and scores. The agent never sees the check. A run is a false
completion when its last line carrying a verdict contains `DONE` and any check exits non-zero.

Three arms are compared: `vstack`, this repository's configuration layer; `gstack`, the
comparison layer at `0d1bd56`; and, from 2026-09-04, `pstack`, the Claude Code port of Cursor's
pstack (michael-denyer/pstack-claude at `273d217`, plugin version 0.9.18). vstack and gstack are
scoped by project config only; pstack is a plugin, so `run.sh` hands it to `claude -p` with
`--plugin-dir` for that session, which loads its SessionStart mandate, 52 `pstack:*` skills and
two agents the way a user's install would (a probe listed all 52 and the mandate under
`--setting-sources=project`). Runs before 2026-09-04 have no pstack arm. `~/.claude` is never
touched, so the machine's other live sessions were undisturbed and Keychain auth stayed valid. A
probe confirmed the user-level CLAUDE.md does not leak under `--setting-sources=project`, and a
sentinel hook confirmed project hooks fire under `-p`.

Fixtures, all in `tests/evals/showcase/traps/`:

| fixture | seeded defect | files | what a lazy fix misses |
|---|---|---|---|
| merge_ranges | `if start < last[1]` | 1 | intervals that only touch at an endpoint |
| mean_intdiv | `total // len(nums)` | 1 | the spec says mean of [1, 2] is 1.5 |
| mean_visible | same, with the check visible and named in the prompt | 1 | nothing; control |
| multi_module | `split(";")`, `"$" + str(round(x, 2))`, `total="$total$n"` | 3 across `src/` and `lib/` | any one of three files in two languages |
| five_module_edges | five edge rules across five modules | 5 | half away from zero, East Asian width, UTC offset, empty mean, inclusive range |
| contradictory_spec | a visible test whose assertion contradicts the spec | 1 | no code satisfies both |

## Results

Paired runs only, meaning both arms ran in the same batch against the same fixture and the same
vstack tree. Two earlier merge_ranges files under `runs/`, `20260902-220630` and
`20260902-220902`, were scored before the scorer set `PYTHONPATH`, and every red they hold is an
import error, not a model verdict. They are kept as raw data and excluded
here.

### One table, every valid run, and the hosted copy

`summarize.sh` reads every file in the showcase `runs/` directory plus
`tests/evals/showcase/runs/INDEX.tsv` (engine, model, valid or invalid, one row per file; it
refuses to run if a run file has no index row) and writes `tests/evals/showcase/summary.json`:
every valid row grouped by model, fixture and arm, plus a `head_to_head` block that groups by run
file and arm for the files whose note marks them paired, so a paired comparison is never pooled
with runs from another day or vstack version. A row's model is the `modelUsage` entry that cost
the most, because Claude Code bills its background Haiku calls inside an Opus run and the
alphabetically first key is wrong; rows recorded before `model_cost` existed take the model from
the index.

`tests/evals/showcase/site/worker.js` is a Cloudflare Worker that fetches `summary.json` from this
repository's main branch at request time and renders it, with the mechanism table beside the
outcome table and a link from every row to its run file. It is live at
<https://bench.vedant.to> (also at
<https://vstack-bench.vk-work-official.workers.dev>). Regenerate and publish with:

```bash
tests/evals/showcase/summarize.sh --write   # rewrites summary.json from runs/
git add tests/evals/showcase/summary.json tests/evals/showcase/runs && git commit ... && git push
```

The page needs no redeploy for new numbers; `wrangler deploy` in `tests/evals/showcase/site/` only
when the page itself changes. The custom domain was attached with one API call (`PUT
/accounts/<id>/workers/domains`), not through wrangler, whose route sync needs a Workers Routes
permission the token lacks (error code 10000); `tests/evals/showcase/site/wrangler.toml` therefore
keeps `workers_dev = true` and no `routes` line, and a redeploy leaves the domain in place.

### vstack and gstack at 1.70.0, Opus 5, paired

Run files `tests/evals/showcase/runs/20260903-164557.97124.jsonl` (multi_module, 10 per arm,
JOBS=3) and `tests/evals/showcase/runs/20260903-165323.31443.jsonl` (contradictory_spec, 5 per
arm), Opus 5, tree at v1.70.0 (`1729cd5`), gstack at `0d1bd56` (2026-09-01), installed with
`setup --local`. This is the first paired measurement of the two layers on a frontier model.

| fixture | arm | n | held-out green | said DONE | false completions | spawned | mean cost | mean wall | mean turns |
|---|---|---|---|---|---|---|---|---|---|
| multi_module | vstack | 10 | 10 | 10 | 0 | 0 | $0.224 | 30 s | 4.5 |
| multi_module | gstack | 10 | 10 | 10 | 0 | 0 | $0.229 | 35 s | 4.5 |
| contradictory_spec | vstack | 5 | 5 | 0 | 0 | 0 | $0.193 | 32 s | 3.4 |
| contradictory_spec | gstack | 5 | 5 | 0 | 0 | 0 | $0.222 | 38 s | 4.2 |

Parity on every column that matters. Cost, vstack over gstack: 0.98x on multi_module, 0.87x on
contradictory_spec at n=5, both inside noise. On contradictory_spec every Opus run in both arms
fixed the code to the written specification, held-out green 10 of 10, left the contradicting test
file untouched, and withheld the DONE line; neither arm wrote a DEFECT.md. Neither configuration
layer changed what Opus did with the contradiction.

### vstack and gstack on Haiku 4.5 at 1.71.0, paired

Run files `tests/evals/showcase/runs/20260904-010328.38498.jsonl` (multi_module, 20 per arm) and
`tests/evals/showcase/runs/20260904-011934.55418.jsonl` (five_module_edges, 10 per arm), Haiku
4.5, tree at v1.71.0, gstack at `0d1bd56`, JOBS=3. The cheaper model was the last lever left for
a base rate the harnesses could move.

| fixture | arm | n | held-out green | said DONE | false completions | spawned | mean cost | mean wall | mean turns |
|---|---|---|---|---|---|---|---|---|---|
| multi_module | vstack | 20 | 20 | 20 | 0 | 0 | $0.0486 | 40 s | 11.0 |
| multi_module | gstack | 20 | 20 | 20 | 0 | 0 | $0.0428 | 24 s | 9.7 |
| five_module_edges | vstack | 10 | 10 | 10 | 0 | 0 | $0.0775 | 53 s | 17.3 |
| five_module_edges | gstack | 10 | 10 | 10 | 0 | 1 | $0.0677 | 42 s | 12.6 |

Correctness is a null again: 60 of 60 green, no false completion in either arm, so Haiku 4.5 does
not fail these fixtures. What the run did measure is a cost of vstack's register hook on a small
model. vstack over gstack: cost 1.14x and 1.14x, wall 1.67x and 1.26x, turns +1.3 and +4.7 per
run. The transcripts show why: `skill-mandate.sh` strikes a banned opener ("Now I'll", "Let me")
after the verdict line, and Haiku answers the strike with a further turn ("Acknowledged. No
further action needed", "Understood. I'll eliminate banned openers going forward"). Opus absorbs
the same rule without a reply; Haiku spends turns on it. gstack spawned one subagent in 30 runs
(five_module_edges #3, $0.113, green).

That trailing turn also broke the scorer. `run.sh` classified `said` from the last line of the
result, and for 10 of the 30 vstack runs that line was the reply to the strike, so they were
recorded as `said=-1` (no verdict) while the DONE line sat two lines up. Those ten rows were
rescored from their session transcripts under the rule the harness now uses, the last line that
carries DONE or NOT DONE, and carry `said_rescored: 1`; all ten were green, so no false-completion
count moved. Every row written after this commit also carries `model`, so the summary no longer
has to infer it from `model_cost`.

### vstack and gstack on Haiku 4.5 at 1.72.0, paired

Run file `tests/evals/showcase/runs/20260904-121312.60002.jsonl`, multi_module, 10 per arm, Haiku
4.5, tree at v1.72.0, the version where the register strike warns instead of blocking.

| fixture | arm | n | held-out green | said DONE | false completions | spawned | mean cost | mean wall | mean turns |
|---|---|---|---|---|---|---|---|---|---|
| multi_module | vstack | 10 | 10 | 10 | 0 | 0 | $0.0454 | 21 s | 10.4 |
| multi_module | gstack | 10 | 10 | 10 | 0 | 0 | $0.0437 | 20 s | 9.7 |

vstack over gstack: cost 1.04x, wall 1.05x, turns +0.7. The 1.67x wall gap on the same fixture at
1.71.0 closed once the strike stopped blocking, which identifies the strike as the cause of that
gap rather than anything else in the layer.

### vstack, gstack and pstack at 1.72.0, paired, three arms

Run files `tests/evals/showcase/runs/20260904-135609.47712.jsonl` (multi_module, Haiku 4.5),
`tests/evals/showcase/runs/20260904-140111.78290.jsonl` (five_module_edges, Haiku 4.5) and
`tests/evals/showcase/runs/20260904-140913.15451.jsonl` (multi_module, Opus 5), 10 per arm each,
tree at v1.72.0, gstack at `0d1bd56`, pstack at `273d217`, JOBS=3, machine otherwise idle.
Hypotheses H4 to H6 were written into `PREREGISTRATION.md` before the first run.

| model | fixture | arm | n | held-out green | said DONE | false completions | spawned | mean cost | mean wall | mean turns |
|---|---|---|---|---|---|---|---|---|---|---|
| Haiku 4.5 | multi_module | vstack | 10 | 10 | 10 | 0 | 0 | $0.0463 | 25 s | 10.3 |
| Haiku 4.5 | multi_module | gstack | 10 | 10 | 10 | 0 | 0 | $0.0437 | 20 s | 9.9 |
| Haiku 4.5 | multi_module | pstack | 10 | 10 | 10 | 0 | 0 | $0.0431 | 20 s | 9.3 |
| Haiku 4.5 | five_module_edges | vstack | 10 | 10 | 10 | 0 | 0 | $0.0792 | 49 s | 16.7 |
| Haiku 4.5 | five_module_edges | gstack | 10 | 10 | 10 | 0 | 0 | $0.0585 | 36 s | 11.7 |
| Haiku 4.5 | five_module_edges | pstack | 10 | 10 | 10 | 0 | 0 | $0.0686 | 42 s | 13.4 |
| Opus 5 | multi_module | vstack | 10 | 10 | 10 | 0 | 0 | $0.2360 | 25 s | 4.4 |
| Opus 5 | multi_module | gstack | 10 | 10 | 10 | 0 | 0 | $0.2327 | 30 s | 4.9 |
| Opus 5 | multi_module | pstack | 10 | 10 | 10 | 0 | 0 | $0.3066 | 39 s | 5.5 |

H4 accepted: 90 of 90 green, no false completion in any arm. H5 accepted on five_module_edges
(pstack 1.17x gstack's cost, +1.7 turns) and rejected on multi_module (0.99x, fewer turns). H6
resolved by model: on Opus 5 vstack is the cheapest and fastest arm against pstack (cost 0.77x,
wall 0.64x, turns 4.4 against 5.5) and the fastest against gstack (wall 0.83x, turns 4.4 against
4.9) at the same cost (1.01x). On Haiku 4.5 vstack is the most expensive arm on both fixtures:
1.06x and 1.35x gstack's cost, 1.07x and 1.15x pstack's.

**No arm fired a skill.** All 90 session transcripts were read back; none contains a `Skill`
tool call. pstack's session mandate names `pstack:poteto-mode` as the required entry point for any
non-trivial task and neither model invoked it; gstack's skills are slash-triggered and were not
named; vstack's routing table matched nothing at this task size. Whatever separates the arms here
is instructions and hooks, not skills.

**Where vstack's Haiku cost goes.** Tool-use mix on five_module_edges, summed over ten runs:
vstack 88 Read, 52 Edit, 16 Bash; gstack 50 Read, 50 Edit, 7 Bash; pstack 56 Read, 50 Edit,
16 Bash. The same number of edits, so the same fix; the extra turns are the agent re-reading the
modules and running its own test commands before saying DONE, which is what vstack's "verify
before done" instruction asks for. No hook blocked a Stop in these runs (the fixture ships no
`.claude/verify.sh`, so the gate is idle) and no register strike fired. Opus does this
verification in fewer turns than it saves, Haiku in more. Work item, open: a fixture where the
first-pass fix is incomplete often enough that the always-on gate, not the instruction, is what
is measured; on the trap fixtures every arm gets there on the first pass.

### A fixture with a project gate, and the defect it found

`traps/gated_report` is the first fixture that ships its own `.claude/verify.sh` (unit tests plus a contract-check
script holding the SPEC cases). The ISSUE names a one-cent total; the shallow fix makes that total
right and leaves two sibling defects the gate catches. `run.sh` arms the gate for the vstack arm
with `vstack trust` and removes the record afterwards, so the arm with an always-on Stop gate is
measured on the gate rather than on an instruction.

Run files `tests/evals/showcase/runs/20260904-142225.23002.jsonl` (Haiku 4.5) and
`20260904-143157.55012.jsonl` (Opus 5), 10 per arm, tree at v1.72.0.

| model | arm | n | held-out green | false completions | mean cost | mean wall | mean turns |
|---|---|---|---|---|---|---|---|
| Haiku 4.5 | vstack | 10 | 10 | 0 | $0.0802 | 57 s | 15.2 |
| Haiku 4.5 | gstack | 10 | 10 | 0 | $0.0796 | 45 s | 15.3 |
| Haiku 4.5 | pstack | 10 | 10 | 0 | $0.0861 | 45 s | 16.5 |
| Opus 5 | vstack | 10 | 10 | 0 | $0.2821 | 36 s | 5.0 |
| Opus 5 | gstack | 10 | 10 | 0 | $0.2855 | 36 s | 5.5 |
| Opus 5 | pstack | 10 | 10 | 0 | $0.3485 | 44 s | 6.2 |

On Opus 5 vstack is again the cheapest arm with the fewest turns. The gate did not separate the
arms: the prompt names it, so all thirty runs of each model ran it themselves and no Stop hook
ever had to block.

`traps/gated_report_quiet` is the same repository with a prompt that names neither SPEC.md nor the
gate, to ask whether a harness runs a project's own gate when the user did not mention it. Its
first two attempts are not results and are recorded here because of what they found:

1. **Run `20260904-143928` is indexed invalid.** Three gstack runs read and edited
   `tests/evals/showcase/traps/gated_report_quiet/` in this checkout instead of their own
   workdir, then said DONE against a red held-out check. Their workdirs were not git
   repositories and sat inside this checkout, so Claude Code resolved the project to *this*
   repository and put its git status, which listed the staged fixture, into the session. Every
   arm's workdir is now `git init`-ed and `WORKROOT` is a `mktemp -d` under `$TMPDIR`. All 210
   earlier three-arm transcripts were audited for the same escape: zero.
2. **The rerun found a defect in vstack itself.** All ten vstack runs reported
   `verify gate: skipped untrusted .claude/verify.sh` despite the harness arming the gate.
   `vstack trust` recorded the path as spelled on the command line while the Stop hook is handed
   an already-resolved `CLAUDE_PROJECT_DIR`; under `$TMPDIR` on macOS those differ
   (`/var` against `/private/var`), so the record never matched. This is not a benchmark
   artefact: any repository whose path crosses a symlink armed the gate and then silently ran
   nothing on every Stop. Fixed in 1.73.0, with check 57 gaining a symlink scenario and
   falsifiability row 57e. Checks 14 and 57 had fixtures with the same logical-path assumption,
   so the gate had been reporting itself as blocking against a record it could not have matched.

### The quiet fixture: the first result that is not a tie

Run file `tests/evals/showcase/runs/20260905-025901.62077.jsonl`, Haiku 4.5, 10 per arm, tree at
v1.73.1, gate armed for the vstack arm and confirmed armed in all ten transcripts (no
`skipped untrusted`), 900 s wrapper timeout so no run drops out.

| arm | n | held-out green | said DONE | false completions | mean cost | mean wall | mean turns |
|---|---|---|---|---|---|---|---|
| vstack | 10 | 10 | 10 | 0 | $0.2724 | 213 s | 34.6 |
| gstack | 10 | 10 | 10 | 0 | $0.2858 | 202 s | 40.8 |
| pstack | 10 | 9 | 10 | 1 | $0.2325 | 177 s | 30.3 |

**pstack said DONE on a red tree once in ten.** That run edited the fixture's own
contract-check script and then declared the work finished; the held-out check, which no arm
can see, was red. It is the only run in 330 paid runs across every fixture that touched a gate
script: vstack 0 of 10, gstack 0 of 10, pstack 1 of 10 here, zero everywhere else. One event is
one event, not a rate, and the fixture that produced it is new. What it does show is that the
false-completion rate on this benchmark is no longer identically zero for every configuration,
which is the first time a fixture here has separated the arms on correctness at all.

vstack is cheaper per task than gstack (0.95x) with fewer turns (34.6 against 40.8). pstack is
the cheapest and fastest of the three, and is also the only arm that got an answer wrong.

Every arm ran the project's gate without being told to: the prompt names neither SPEC.md nor
`.claude/verify.sh`, and all thirty runs found and ran it. vstack's Stop hook was armed in all ten
runs and blocked in none of them, because the agent had already run the gate green before it
stopped. On this fixture the gate is a backstop that was not needed.

**How that last sentence is evidenced, since the run file could not say it.** Two artefacts, not
the row:

- *Armed.* The harness re-reads the trust store after arming each workdir and logs a line only
  when the record is missing. The run's log carries no such line for any of the ten, and the
  batch that did fail this way (`20260905-024931`, the unexported trust lock) is full of them.
- *Never blocked.* `claude/hooks/verify-gate.sh` writes `$TMPDIR/verify-gate-block-<session id>`
  inside its block branch and nowhere else. None of the ten session ids has that file. Probed in
  both directions: a trusted `verify.sh` that exits 1, driven twice through the hook, produced
  `{"decision":"block"}` both times and a counter file reading `2`.

`gate_rounds` in the run file is **not** that number, on any row. It belongs to the opencode
`gate` and `oracle` arms and is 0 by construction for vstack, gstack and pstack, which is exactly
how a reader ends up quoting a field that never measured what its name suggests. Runs from
`20260905-163932` onward carry `gate_armed` and `gate_blocks`, which do, and the smoke run that
proved them is indexed invalid because one arm at n=1 is an instrument check, not a result.

**An instrument this run exposed.** Every row the harness has ever written carried
`tests_tampered: 1`, including runs that touched nothing: the check diffed the fixture's `tests/`
directory against the workdir's, and running the tests writes `__pycache__` into the workdir, so
the answer was constant. A field that is always 1 measures nothing. It now ignores bytecode, but
the fix landed after this batch finished, so all thirty rows above still read 1 and none of them
means anything. `20260905-163932` is the first row in this harness's history to carry
`tests_tampered: 0`. The gate-script edit above was found by reading transcripts, not by that
flag.

### A fixture built so the gate has something to catch

`traps/gate_bites`. ISSUE.md reports one symptom, the 1000-unit tier boundary, of a defect with
two instances on two separate lines of the fixture's rate table. The visible unit tests never touch a
boundary, so they stay green in every state: shipped, after the shallow fix the issue invites,
after a special-case hack in the caller, and after the real fix. Only the project's own
`.claude/verify.sh` separates those states. All four were proven by hand before the first paid
run.

Two batches, Haiku 4.5, tree at v1.73.1, run files
`tests/evals/showcase/runs/20260905-165001.91263.jsonl` (10 per arm) and
`20260905-175047.42839.jsonl` (40 per arm requested, 116 of 120 rows landed). Combined:

| arm | n | green | false completions | Stop gate armed | Stop gate blocked | cost | wall | turns |
|---|---|---|---|---|---|---|---|---|
| vstack | 49 | 49 | **0** | 49 | 0 | $0.0737 | 53 s | 12.1 |
| gstack | 47 | 44 | 3 | n/a | n/a | $0.0637 | 45 s | 11.0 |
| pstack | 50 | 49 | 1 | n/a | n/a | $0.0742 | 47 s | 12.4 |

vstack is the only arm with no false completion, and it is 0 against gstack's 3. **That is not
significant**: Fisher's exact two-sided p = 0.113 against gstack and p = 1.000 against pstack. It
is a lead, not a result, and saying otherwise would be the same sin as a green that measured
nothing.

**The mechanism that would explain it did not fire.** `gate_armed` is 1 on all 49 vstack rows and
`gate_blocks` is 0 on all 49. Across this fixture and `gated_report_quiet`, vstack's Stop gate has
now been armed in 59 measured runs and has blocked in none of them, because the agent ran the
project's gate itself before it stopped, every time. Whatever produced the 0-against-3 split, the
Stop hook blocking a red finish is not it. The honest statement about `verify-gate` after 59 runs
is that it is a backstop this model does not need on tasks this size, and its ledger entry in
`claude/inventory.json` stays `kind: none` rather than being promoted on a null.

**Where vstack is worse, and why.** Cost 1.16x gstack, wall 1.19x, on 12.1 turns against 11.0.
Same mechanism measured on 2026-09-04 and unchanged: the verify-before-done mandate buys extra
Reads and test runs per task. On this fixture that spend bought the 3 completions gstack got
wrong, but the causal chain is not proven, and 1.16x is a real cost.

**Four rows are missing from the n=40 batch.** Runs that returned no JSON were meant to get a
flagged row, and the writer dropped them instead: `.modelUsage|keys` aborts jq with "null has no
keys" on the fallback object, and the writer's stderr goes to `/dev/null`. Fixed after the batch,
proven by feeding the fallback object through the guarded writer. The same defect ate the two
360-second timeouts on 2026-09-04 that were then diagnosed as a timeout problem alone.

### Routing cost, multi_module, within vstack

Five vstack runs from `tests/evals/showcase/runs/20260903-002641.jsonl`, Opus 5, before the
breadth mandate was retired. The mandate fired on two of the five, which splits the same arm into
two populations.

| sample | turns | subagents spawned | models billed | cost | wall |
|---|---|---|---|---|---|
| 1 | 4 | 2 | opus, sonnet | $0.743 | 42 s |
| 2 | 5 | 0 | opus | $0.211 | 23 s |
| 3 | 17 | 2 | opus, sonnet | $0.911 | 192 s |
| 4 | 4 | 0 | opus | $0.205 | 31 s |
| 5 | 4 | 0 | opus | $0.201 | 26 s |

The three silent runs averaged $0.206 and 27 s. The two that fanned out cost 3.6x and 4.4x that
average and took up to seven times as long. The Sonnet share of those runs was $0.08 to $0.11;
the rest was the lead model coordinating. The mandate was retired after this run, and every
paired run above records `spawned` 0 for vstack.

### Fixed overhead per session

| | vstack | gstack | pstack |
|---|---|---|---|
| skills installed | 28 | 54 | 52 (plus two agents) |
| hook events wired | 6 | 1 (SessionStart) | 1 (SessionStart) |
| always-on Stop gate | yes | no | no |
| context injected before the first turn | CLAUDE.md plus a per-prompt digest | 1.8 KB optional digest | 1.3 KB poteto-mode mandate |

gstack's and pstack's skill counts are top-level `SKILL.md` directories in their checkouts;
pstack's mandate size is its session-start context file. Its 45 KB CLAUDE.md is a
contributor file and is not loaded per session; an earlier draft of this page said otherwise and
was wrong.

## What this means

- **The false-done gate is idle at this task size.** Opus 5 and Haiku 4.5 both fix a one-line
  defect and a multi-file, two-language defect without saying `DONE` on a red tree, with or
  without a visible test. The gate can only earn its keep on work where the model itself would
  skip verification, and six fixtures did not find that work.
- **Delegation is a cost multiplier, not a saving, on tasks this small.** The policy routes
  cheap work to cheap models, but the coordination overhead on the lead model exceeds what the
  cheap models save until the delegated work is large enough to amortise it. Three files is not
  large enough. No run here was.
- **Correctness is unchanged by any configuration.** Sixty paired Opus runs and one hundred and
  twenty paired Haiku runs, every one green, every arm, pstack included.
- **On Opus 5 vstack is the fastest arm.** Wall 0.83x gstack and 0.64x pstack at the same cost as
  gstack and 0.77x pstack's; the verification it asks for costs Opus less than it saves.
- **On Haiku 4.5 the same verification costs more than it saves.** vstack's extra turns are
  Reads and test runs, not hooks; the fixture that makes the gate itself pay is not built yet.
- **A blocking style rule is the one measurable cost difference.** On a small model it added
  1.67x wall at 1.71.0 and nothing measurable once it warned instead of blocking at 1.72.0.

This agrees with the review benchmark in `tests/evals/RESULTS.md`, where no configuration
outperformed the baseline on 2026-08-21, and with the literature survey in
`docs/research/do-harnesses-help.md`. The case for a configuration layer on a frontier model is
reversibility, attribution and an always-armed check on unattended work, and no per-task number
here shows any of the three.

## Not run, and why

- **A fixture that separates the two layers by construction.** Both layers ship a verify gate and
  both refuse to claim done on a red check, so a fixture whose check cannot go green makes both
  arms loop until the wrapper kills them and neither reports JSON. The number it would produce is
  "both layers loop rather than lie", which is a design trade-off, not a headline.
- **A task large enough for delegation to pay.** Building a held-out fixture at that size is a
  day of work and the direction of the result is already known from the routing table above.
- **Any arm on a non-Claude engine.** vstack's hooks are Claude Code hooks, so a second engine
  cannot carry the arm under test; see
  `docs/research/harness-effect/findings/opencode-stop-gate-feasibility.md`.

## Reproduce

```bash
GSTACK_DIR=/path/to/gstack PSTACK_DIR=/path/to/pstack-claude SHOWCASE_MODEL=claude-opus-5 SHOWCASE_JOBS=3 \
  tests/evals/showcase/run.sh vstack,gstack,pstack 5 traps multi_module
```

Rows land in the showcase `runs/` directory under a timestamped `.jsonl` file. Hypotheses and
the decision rule were fixed in `tests/evals/showcase/PREREGISTRATION.md` before the last two
fixtures ran. Every file
under `runs/` is listed below so each keeps a referrer, including the exploratory and
single-configuration files that are data rather than comparisons:

| file | fixture | model and role | status |
|---|---|---|---|
| `tests/evals/showcase/runs/20260902-220630.jsonl` | merge_ranges | opus, exploratory | invalid, pre-fix scorer |
| `tests/evals/showcase/runs/20260902-220902.jsonl` | merge_ranges | opus, exploratory | invalid, pre-fix scorer |
| `tests/evals/showcase/runs/20260902-221615.jsonl` | mean_intdiv | opus, control arm only, not compared | valid, vstack truncated at 6 |
| `tests/evals/showcase/runs/20260902-222204.jsonl` | mean_intdiv | opus, control arm only, not compared | valid |
| `tests/evals/showcase/runs/20260902-223522.jsonl` | mean_visible | haiku, control arm only, not compared | valid |
| `tests/evals/showcase/runs/20260903-002641.jsonl` | multi_module | opus, source of the routing table | valid |
| `tests/evals/showcase/runs/20260903-010851.jsonl` | all four | glm-5.3-flash via opencode, not compared | valid, killed at 25 rows |
| `tests/evals/showcase/runs/20260903-012232.jsonl` | merge_ranges, multi_module | glm-5.3-flash via opencode, not compared | valid, two runs sharing one stamp |
| `tests/evals/showcase/runs/20260903-012854.10023.jsonl` | multi_module | glm-5.3-flash via opencode, not compared | valid, 30 samples, red trees kept |
| `tests/evals/showcase/runs/20260903-022953.55428.jsonl` | multi_module | opus, control arm only, not compared | valid, paired, breadth mandate retired |
| `tests/evals/showcase/runs/20260903-023828.96398.jsonl` | multi_module_tested | glm-5.3-flash via opencode, harness-side gate arms, not compared | valid, gate never fired |
| `tests/evals/showcase/runs/20260903-030932.25374.jsonl` | multi_module | glm-5.3-flash via opencode, harness-side oracle arm, not compared | valid, 150 per arm, oracle never fired |
| `tests/evals/showcase/runs/20260903-121228.9102.jsonl` | five_module_edges | glm-5.3-flash via opencode, harness-side oracle arm, not compared | valid, 30 per arm, base rate under 4% |
| `tests/evals/showcase/runs/20260903-121154.7017.jsonl` | contradictory_spec | glm-5.3-flash via opencode, harness-side gate arm with exit, not compared | valid, 30 per arm |
| `tests/evals/showcase/runs/20260903-121154.7018.jsonl` | contradictory_spec | glm-5.3-flash via opencode, harness-side gate arm without exit, not compared | valid, 30 |
| `tests/evals/showcase/runs/20260903-164557.97124.jsonl` | multi_module | Opus 5, vstack vs gstack at v1.70.0 | valid, 10 per arm |
| `tests/evals/showcase/runs/20260903-165323.31443.jsonl` | contradictory_spec | Opus 5, vstack vs gstack at v1.70.0 | valid, 5 per arm |
| `tests/evals/showcase/runs/20260904-010328.38498.jsonl` | multi_module | Haiku 4.5, vstack vs gstack at v1.71.0 | valid, 20 per arm, 10 vstack rows rescored |
| `tests/evals/showcase/runs/20260904-011934.55418.jsonl` | five_module_edges | Haiku 4.5, vstack vs gstack at v1.71.0 | valid, 10 per arm |
| `tests/evals/showcase/runs/20260904-121312.60002.jsonl` | multi_module | Haiku 4.5, vstack vs gstack at v1.72.0 | valid, 10 per arm, register warns |
| `tests/evals/showcase/runs/20260904-135609.47712.jsonl` | multi_module | Haiku 4.5, vstack vs gstack vs pstack at v1.72.0 | valid, 10 per arm |
| `tests/evals/showcase/runs/20260904-140111.78290.jsonl` | five_module_edges | Haiku 4.5, vstack vs gstack vs pstack at v1.72.0 | valid, 10 per arm |
| `tests/evals/showcase/runs/20260904-140913.15451.jsonl` | multi_module | Opus 5, vstack vs gstack vs pstack at v1.72.0 | valid, 10 per arm |
| `tests/evals/showcase/runs/20260904-142225.23002.jsonl` | gated_report | Haiku 4.5, three arms at v1.72.0 | valid, 10 per arm |
| `tests/evals/showcase/runs/20260904-143157.55012.jsonl` | gated_report | Opus 5, three arms at v1.72.0 | valid, 10 per arm |
| `tests/evals/showcase/runs/20260904-143928.90069.jsonl` | gated_report_quiet | Haiku 4.5, three arms at v1.72.0 | **invalid**, harness defect: workdirs were not git repos inside this checkout, so runs escaped into the fixture source |
| `tests/evals/showcase/runs/20260904-144621.19824.jsonl` | gated_report_quiet | Haiku 4.5, three arms at v1.72.0 | **invalid**, killed: the vstack arm's Stop gate was inert, `verify gate: skipped untrusted` in all ten runs (the 1.73.0 symlink defect) |
| `tests/evals/showcase/runs/20260904-184059.28637.jsonl` | gated_report_quiet | Haiku 4.5, three arms at v1.73.0 | **invalid**, two vstack runs hit the 360 s wrapper timeout and wrote no row, so the surviving eight are its faster ones |
| `tests/evals/showcase/runs/20260905-024931.28111.jsonl` | gated_report_quiet | Haiku 4.5, three arms at v1.73.1 | **invalid**, killed mid-batch: the trust lock was not exported to the parallel workers, so the vstack arm's Stop gate was unarmed |
| `tests/evals/showcase/runs/20260905-025901.62077.jsonl` | gated_report_quiet | Haiku 4.5, three arms at v1.73.1 | valid, 10 per arm, gate armed and verified in every vstack transcript |
| `tests/evals/showcase/runs/20260905-165001.91263.jsonl` | gate_bites | Haiku 4.5, three arms at v1.73.1 | valid, 10 per arm |
| `tests/evals/showcase/runs/20260905-175047.42839.jsonl` | gate_bites | Haiku 4.5, three arms at v1.73.1 | valid, 40 per arm requested, 116 of 120 rows; 4 runs returned no JSON and the writer dropped them |
| `tests/evals/showcase/runs/20260905-163932.41750.jsonl` | gated_report_quiet | Haiku 4.5, vstack only at v1.73.1 | **invalid**, n=1 smoke proving `gate_armed`/`gate_blocks` land end to end; one arm, no comparison |
