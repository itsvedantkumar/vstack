# vstack

**Every claim below has a command next to it. That is the entire pitch.**

[![verify](https://github.com/itsvedantkumar/vstack/actions/workflows/verify.yml/badge.svg)](https://github.com/itsvedantkumar/vstack/actions/workflows/verify.yml)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![plugin](https://img.shields.io/badge/claude%20plugin-vstack-6f42c1.svg)](#install)
[![runs on](https://img.shields.io/badge/runs%20on-macOS%20%2B%20Linux-lightgrey.svg)](#what-runs-where)

> **Claude Code only.** Not Cursor, not Codex, not Aider, not a local Llama or Qwen or DeepSeek,
> not an OpenAI or Gemini model behind a compatibility shim. Built on machinery only Claude Code
> has: skills the model selects by reading their descriptions, the six hook event lanes,
> subagents, `skillOverrides`, `settings.json`, plugin marketplaces, and the CLI's own flags.
> There is no adapter layer and none is planned.

```bash
claude plugin marketplace add itsvedantkumar/vstack
claude plugin install vstack@vstack
```

## Why this exists

The closest comparable project is [gstack](https://github.com/garrytan/gstack). I read it before
writing this. Measured at commit `85fd9db`:

| | gstack | vstack |
|---|---|---|
| Tracked files | 1,359 | 195 |
| Its review skill, per invocation | 112 KB | delegated to a subagent |
| Checks proving the thing works | none found | 34 |
| Mutations proving those checks can fail | none found | 34 |
| Install environments under test | not published | 23 |
| Uninstall script | none | `./uninstall.sh --yes` |
| Specialists that are real subagents | 0 | 14 |

A skill count is not a quality metric. gstack has 53 of them and vstack has 28, and that
comparison tells you nothing, because neither number says whether any of them fire, whether the
review pathway runs, or whether uninstalling gets your machine back. Those are the questions, and
they are answerable by running something.

gstack's pitch is a virtual engineering team of named specialists. It is the right idea. It is
also, in the code, 53 Markdown files that instruct one conversation. vstack ships the team as 14
actual subagents, each with its own context window, tool allowlist and model, dispatched by the
Task tool. That is a different mechanism, not a different adjective: a reviewer with its own
context cannot be talked out of a finding by the conversation that produced the code.

**Reproduce the awkward one yourself:**

```bash
git clone --depth 1 https://github.com/garrytan/gstack /tmp/gstack
grep -c 'skills/gstack' /tmp/gstack/review/SKILL.md   # 85 absolute paths under your Claude config
```

Its review pathway shells out to 85 absolute paths under a global `skills/gstack/` directory. Its own
installer says `--local is deprecated, use global install`, and that flag rewrites those paths for
Kiro and no one else. Install it per-project and every one of those 85 is `command not found`,
silently, while the review still produces confident prose.

I know because I did exactly that, for months, and scored it. Every gstack number this repository
ever published came from an arm in that state. They are retracted and the retraction is in
[RESULTS.md](tests/evals/RESULTS.md), along with nine other defects in my own harness, seven of
which flattered vstack.

That is the actual difference. Not skill count. Whether the thing tells you when it is broken.

## The team

Fourteen subagents, each with its own context window, tool allowlist and model. `/team <goal>`
runs the whole loop and holds the bar between phases.

| Phase | Agent | Owns |
|---|---|---|
| Spec | `product-owner` | acceptance criteria, and what is explicitly out of scope |
| Plan | `planner` | architecture, before any code |
| Explore | `explorer` | locating code without burning the main context |
| Build | `ui-engineer` | interfaces, against the tokens already in the repo |
| Build | `worker` | mechanical edits, boilerplate, config |
| Build | `test-writer` | tests worth having |
| Verify | `qa` | exercising the real artifact against the criteria |
| Review | `code-reviewer` | correctness and maintainability |
| Review | `security-auditor` | auth, payments, input, IO, secrets |
| Review | `design-reviewer` | the running UI, at real breakpoints |
| Review | `accessibility-auditor` | WCAG 2.2 AA and keyboard operability |
| Review | `performance-engineer` | profiles, with before and after numbers |
| Debug | `debugger` | root cause, not a `try`/`except` |
| Ship | `release-manager` | version, changelog, tag, rollback |

The phase that matters is verify. `/team` will not let a feature reach `release-manager` until
`qa` has exercised the real thing against the acceptance criteria `product-owner` wrote. A green
unit test is a different claim and the command treats it as one.

Reviewers run in parallel because they read for different failures. Anything a phase could not
verify is carried into the final report rather than disappearing between phases.

## What "proven" means here

`.claude/verify.sh` runs 34 checks. `tests/gate-falsifiability.sh` breaks the repository once per
check, requires the gate to go red naming that check, restores the tree byte for byte, and fails
if anything was left behind. Check 16 fails if a check has no mutation row, so a check cannot be
added without proof it can fail.

This is not decoration. Five checks in this repository have been caught passing while measuring
nothing:

- Check 24 printed `ok` for a version whose tag did not exist, having compared zero files.
- Check 29 linted a hand-maintained file list that never included `bin/cloudflare-mcp`. Breaking
  that file left the gate green.
- Check 12 read a noun list its extractor did not share, so an invented count of shell scripts,
  bolded in the README, passed unchallenged.
- The falsifiability suite probed with `verify.sh | grep -q`, which returns 141 under
  `set -o pipefail` when grep exits early. That reads as "did not skip", so one row had been
  reporting success off the wrong branch.
- Two mutations stopped matching after a prose rewrite and reported the checks as unfalsifiable.
  The suite now distinguishes "this check is weak" from "this mutation landed nowhere".

Each is in [CHANGELOG.md](CHANGELOG.md) with the command that exposed it. A project that has never
found one of these has not looked.

## Install

Three lanes, all exercised on every commit across macOS, Ubuntu and Alpine by
[`tests/install-matrix.sh`](tests/install-matrix.sh).

**Skills only, through the plugin marketplace.** Adds skills, commands and agents. Touches nothing
else.

```bash
claude plugin marketplace add itsvedantkumar/vstack
claude plugin install vstack@vstack
```

**The full workstation, from a clone.**

```bash
git clone https://github.com/itsvedantkumar/vstack.git
cd vstack
./install.sh
```

**Pinned to a release, reading the script first.**

```bash
curl -fsSL https://raw.githubusercontent.com/itsvedantkumar/vstack/v1.13.0/bootstrap.sh -o bootstrap.sh
less bootstrap.sh                        # about 100 lines
VSTACK_REF=v1.13.0 bash bootstrap.sh     # installs that tag, not main
```

Check 24 fails if a version named in these docs is not a tag that exists. It was added after this
README shipped a pin to an untagged release and returned 404 to anyone who copy-pasted it.

**Removing it:**

```bash
./uninstall.sh --yes
```

Your `settings.json` keys, your `skillOverrides`, your MCP servers and your shell rc survive that,
byte-identical. One of the environment lanes seeds a scratch home with user-owned settings and
asserts both halves, with positive controls that fail if the thing being removed was never
installed in the first place.

## What lands where

| Component | Count | Path |
|---|---|---|
| Skills | 28 | `~/.claude/skills/` |
| Subagents | 14 | `~/.claude/agents/` |
| Commands | 15 | `~/.claude/commands/` |
| Hooks | 6 | `~/.claude/hooks/` |
| CLI wrappers | 6 | `~/.config/agents/bin/` |
| MCP servers | 2 | merged into `~/.claude.json` |

`install.sh` merges rather than overwrites. It backs up every file it touches into
`~/.config/agents/backups/`, adds only the hook entries it owns, and leaves keys it does not
recognise alone. Check 21 fails if it deletes a key this repository never shipped.

## Skills fire without being asked

A skill is selected by its description, so a description is a trigger and its length is a
functional constraint. Check 3 fails a description over 200 characters, because past that it is
truncated in the listing and the skill silently stops being selected. Two skills here were caught
that way at 238 and 261 characters.

`tests/auto-trigger.sh` runs 14 real prompts through the CLI and reports which attempt each landed
on. It is a measurement, not an assertion: dispatch is a model decision, so it retries up to three
times and records the hit rate. Two negative cases fail if a trivial prompt drags in a skill that
has no business firing.

Routing does not depend on the model remembering an instruction. The `Stop` hook refuses to end a
turn where prose was written and `unslop` never ran, or TypeScript was written and
`typescript-best-practices` never ran. `grill-me` fires from the `UserPromptSubmit` hook on the
first substantive prompt of a session and on any prompt long enough to be a plan.
`VSTACK_NO_MANDATE=1` and `VSTACK_NO_GRILL=1` turn those off, because a gate you cannot turn off
gets deleted by the first person it inconveniences.

Method and measurements: [docs/how-skills-fire.md](docs/how-skills-fire.md).

## The verification gate

The `Stop` hook runs a repository's own `.claude/verify.sh` before a turn can end, and blocks on
failure. It refuses to execute a gate it has not been shown: `~/.config/agents/verify-trust`
records the hash you approved, and a changed gate has to be approved again. Cloning a hostile
repository does not run that repository's code.

Locally:

```bash
./.claude/verify.sh               # 34 checks
./tests/gate-falsifiability.sh    # one mutation per check
./tests/install-matrix.sh         # 23 environment lanes
./tests/auto-trigger.sh           # 14 prompts through the real CLI
./tests/compare-baseline.sh       # what the hooks decide, vs no hooks
./bin/doctor && ./bin/doctor --drift
```

A skip is not a pass. The gate prints `N declared, N ran, N skipped` and fails if those do not add
up, because a check that throws mid-body used to leave no trace at all.

## What the hooks decide

`tests/compare-baseline.sh` fires the real hooks with identical input and records the decision,
rather than asking a model what it would do.

| Situation | Unconfigured | vstack |
|---|---|---|
| Agent claims done, tests fail | nothing intervenes | blocked |
| `rm -rf /` from an agent | runs | denied |
| `git push --force origin main` | runs | denied |
| `git reset --hard`, uncommitted work | runs | asks |
| `rm -rf node_modules` | runs | allowed |
| Untrusted repository's gate on `Stop` | no gate at all | not executed |
| Context spent per session | 0 B | about 3.6 KB |

The last row is the price, stated because you pay it every session.

## What this does not claim

It does not claim to make the model better at your codebase. There is no measured quality
improvement in this README because there is not yet one I trust, and
[RESULTS.md](tests/evals/RESULTS.md) is where I keep being wrong about that in public.

It does not manage secrets beyond a 600-mode file and wrappers that load it. It does not work
offline for the lanes that fetch. It is opinionated about model, effort and delegation, and those
opinions are one person's; the plugin lane exists so you can take the skills without them.

## Day to day

```bash
/ship            # verify, commit, push
/review          # code review of the current diff
/doctor          # health-check the installed setup
vstack update    # pull and reinstall, refusing a dirty checkout
doctor --drift   # compare what is installed against this repo
```

## What runs where

Supported: macOS, Linux, and WSL and Alpine as Linux. CI runs `ubuntu-latest`, `macos-latest` and
an `alpine:latest` container, and check 26 fails if the platforms named here are not the platforms
CI actually runs.

Windows is not supported. It passed through Git Bash for three commits and was dropped on purpose:
`secrets.env` is protected by a 600-mode check, and a filesystem without POSIX permission bits
cannot enforce it. That lane could be made to pass. It could not be made to be true.

## Documentation

- [docs/how-skills-fire.md](docs/how-skills-fire.md) — dispatch, the listing budget, the measurements
- [tests/evals/RESULTS.md](tests/evals/RESULTS.md) — every benchmark run, including the retracted one
- [tests/README.md](tests/README.md) — what each suite proves
- [mcp/README.md](mcp/README.md) — the two MCP servers
- [docs/provenance/](docs/provenance/README.md) — where the ported skills came from and what changed
- [docs/provenance/research-v1.7.0.md](docs/provenance/research-v1.7.0.md) — the outside review that specified the design-quality floor
- [claude/settings.project-keys](claude/settings.project-keys) — the keys the overlay may write
- [CONTRIBUTING.md](CONTRIBUTING.md) — the evidence bar, and how to add a check
- [SECURITY.md](SECURITY.md) — what this writes to your machine, and how to report a vulnerability
- [CHANGELOG.md](CHANGELOG.md) — every release, and every defect that produced one

## Credits

18 skills are ported from [pstack](https://github.com/cursor/plugins), 4 from
[Superpowers](https://github.com/obra/superpowers), 1 from
[Impeccable](https://github.com/pbakaus/impeccable), 2 from
[Vercel Labs](https://github.com/vercel-labs/agent-browser), and 1 from
[Matt Pocock](https://github.com/mattpocock/skills). The destructive-command guard adapts an idea
from [gstack](https://github.com/garrytan/gstack).
Per-skill provenance, licences and every deviation from upstream:
[claude/skills/ATTRIBUTION.md](claude/skills/ATTRIBUTION.md).

MIT. Ported skills keep their own licences; see [NOTICE](NOTICE).
