# vstack

**A Claude Code configuration bundle whose every claim is checked by something that can fail.**

[![verify](https://github.com/itsvedantkumar/vstack/actions/workflows/verify.yml/badge.svg)](https://github.com/itsvedantkumar/vstack/actions/workflows/verify.yml)
[![release](https://img.shields.io/github/v/tag/itsvedantkumar/vstack?label=release&color=6f42c1)](https://github.com/itsvedantkumar/vstack/releases)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![plugin](https://img.shields.io/badge/claude%20plugin-vstack-6f42c1.svg)](#install)
[![runs on](https://img.shields.io/badge/runs%20on-macOS%20%2B%20Linux-lightgrey.svg)](#limits)

vstack installs skills, subagents, commands and hooks into Claude Code, and a gate that stops an
agent reporting a task done while the tests are red. It is for people who run agents unattended
and need to know afterwards which parts actually held.

The distinguishing property is not the count of anything. It is that **every check in this
repository has a mutation proving it can fail**, and the project has a written record of the
eighteen times a check here passed while measuring nothing.

## Repository layout

Two directory pairs differ only by a leading dot, and the difference is the whole mental model:

| path | what it is |
|---|---|
| `claude/` | the **shipped payload** — skills, subagents, commands, hooks, installed to `~/.claude/` |
| `.claude/verify.sh` | **this repository's own gate**, 46 checks; not shipped to anyone |
| `conductor/` | payload copied to `~/.conductor/` |
| `.conductor/` | this repository's own workspace config |
| `tests/` | the suites: the falsifiability harness, the install matrix, trigger and baseline tests |
| `ui-gate/` | a UI lint harness for **other people's** repos, driven by the `impeccable` skill |
| `bin/` | CLI wrappers installed to `~/.config/agents/bin/`, not this repo's executables |
| `docs/` | research, provenance and the failure-shape writeups |

The dotted one is always this repository holding itself to something. The undotted one is always
what you receive.

## Requirements

The [Claude Code CLI](https://claude.com/product/claude-code) on `PATH`, bash, and macOS or Linux.
`jq` and `git` are required by the gate; `./setup-machine.sh` installs them.

## Install

```bash
claude plugin marketplace add itsvedantkumar/vstack
claude plugin install vstack@vstack
```

That is the whole plugin lane: skills, subagents and commands, nothing else touched on the
machine. Remove it with `claude plugin uninstall vstack@vstack` — there is no `uninstall.sh` to
run, because there is no checkout.

For the hooks, the CLI wrappers and the shell lane, take the full install:

```bash
git clone https://github.com/itsvedantkumar/vstack ~/Projects/vstack
cd ~/Projects/vstack && ./install.sh
./bin/doctor            # confirm it landed
```

Pin a release rather than tracking `main`:

```bash
curl -fsSL https://raw.githubusercontent.com/itsvedantkumar/vstack/v1.45.1/bootstrap.sh -o bootstrap.sh
VSTACK_REF=v1.45.1 bash bootstrap.sh     # installs that tag, not main
```

The curl one-liner above always runs `./setup-machine.sh` first, which installs the tools this
repo's agents and gate expect — git, jq, ripgrep, fd, gh, node, bun, uv and the Claude Code CLI
itself. Pass `--skip-deps` to the one-liner to go straight to the config install; `./install.sh`
run directly never touches your tools unless you pass it `--with-deps`.

`setup-machine.sh` can also install three Claude Code plugins, and does not by default. Two are
third-party — `claude-mem` (persistent memory, `thedotmack/claude-mem`) and `frontend-design`
(Anthropic's own UI-review plugin) — added from their own marketplaces and updated on their own
schedule, not this repo's. The third, `typescript-lsp`, ships from the official
`anthropics/claude-plugins-official` marketplace. None of the three installs from the headline
command above. Opt in with `./setup-machine.sh --with-plugins`, or `VSTACK_PLUGINS=1` before the
bootstrap one-liner (bootstrap.sh forwards its arguments to `install.sh`, not to
`setup-machine.sh`, so the flag has no reach through it). If claude-mem is present — from this or
an earlier install — `setup-machine.sh` also flips claude-mem's own `UserPromptSubmit` hook from
sync to async in claude-mem's own `hooks.json`, so it stops blocking every prompt; that is the one
edit this repo makes to a file it does not ship, and it is disclosed in `setup-machine.sh`'s own
header. `./uninstall.sh --yes` undoes that specific edit. It never installs or removes claude-mem
itself.

Removing it restores what was there before: `./uninstall.sh --yes` puts every file it replaced
back byte for byte, unpicks the hook entries, MCP servers and policy keys it merged into
`settings.json` and `~/.claude.json`, and leaves anything you added alone.

**Confirm it worked:** inside Claude Code, run `/doctor`. It detects which of the two lanes
above actually landed and checks that one — skill, subagent and command counts for the plugin
lane; the full hook, wrapper and MCP breakdown for the full install — rather than printing a
generic "installed" with nothing behind it. This is also the fastest way to see the payload is
real: it names files on disk, not a slogan.

## What lands where

The two install lanes above put the payload in two different places, and the counts below only
mean what they say for the lane named above each table — mixing them up is exactly how `/doctor`
used to report a healthy plugin install as broken (`/doctor` now detects which lane landed and
checks the right one; see [Day to day](#day-to-day)).

**Full install** (`git clone` + `./install.sh`):

| Component | Count | Path |
|---|---|---|
| Skills | 28 | `~/.claude/skills/` |
| Subagents | 14 | `~/.claude/agents/` |
| Commands | 15 | `~/.claude/commands/` |
| Hooks | 7 | `~/.claude/hooks/` |
| CLI wrappers | 6 | `~/.config/agents/bin/` |
| MCP servers | 2 | merged into `~/.claude.json` |

`install.sh` merges rather than overwrites. It backs up every file it touches into
`~/.config/agents/backups/`, adds only the hook entries it owns, and leaves keys it does not
recognise alone. Check 21 fails if it deletes a key this repository never shipped.

**Plugin-marketplace install** (`claude plugin marketplace add` + `claude plugin install`):

| Component | Count | Path |
|---|---|---|
| Skills | 28 | `~/.claude/plugins/cache/vstack/vstack/<version>/skills/` |
| Subagents | 14 | `~/.claude/plugins/cache/vstack/vstack/<version>/agents/` |
| Commands | 15 | `~/.claude/plugins/cache/vstack/vstack/<version>/commands/` |
| Hooks | 0 (not this lane) | full install only |
| CLI wrappers | 0 (not this lane) | full install only |
| MCP servers | 0 — `claude/.claude-plugin/plugin.json` declares none | full install only |

`<version>` is whatever `claude plugin install` resolved and changes every release, so glob it —
`ls -dt ~/.claude/plugins/cache/vstack/vstack/*/ | head -1` — rather than pinning the number
above. This lane never runs `install.sh`: the skills, subagents and commands are real and fire
normally, but hooks, the CLI wrappers, the shell lane and MCP servers only land with the full
install. Take that lane if you want the Stop-hook gate, the destructive-command guard, or the
CLI wrappers under `~/.config/agents/bin/`.

## Day to day

| Command | What it does |
|---|---|
| `/ship` | verify, commit, push — refuses on a red gate |
| `/review` | full review of the current diff |
| `/team` | routes a goal through spec, plan, build, verify, review, ship, and writes a handoff log |
| `/doctor` | health-check the installed setup |
| `vstack update` | shows the incoming commits and refuses to run unattended |
| `vstack trust` | arms the Stop-hook gate in the current repository |

Skills are not slash commands. They fire on the situation from their description — writing prose
reaches for `unslop`, reviewing TypeScript reaches for `typescript-best-practices` — and
`tests/auto-trigger.sh` asserts that with 28 cases against the live model.

## Checks that can fail

The gate is 46 checks. `tests/gate-falsifiability.sh` breaks the repository once per check, at
least once and more where a check can fail in more than one way, requires the gate to go red
naming that check, restores the tree byte for byte, and fails if anything was left behind.
**Check 16 fails if any check has no mutation row**, so a check cannot be added without proof it
can fail.

```bash
./.claude/verify.sh                  # 46 checks
VSTACK_FALSIFY_ROWS=27 ./tests/gate-falsifiability.sh          # one row
git clone . /tmp/vstack-check && cd /tmp/vstack-check && ./tests/gate-falsifiability.sh
```

The full sweep runs the whole gate once per mutation, so it takes about twenty minutes on an
M-series Mac and there is no partial credit: a run that is interrupted has proven nothing about
the rows it never reached. Run it against a clone, as above. It mutates the working tree, and
editing that tree while it runs will be reported as an unrestored file at the end.

Run the falsifiability suite in a throwaway clone. It mutates real files.

This exists because checks lie. Eighteen in this repository have been caught passing while
measuring nothing — a comparison that ran before the commit it was judging, a linter whose
silence was read as success, an anchor a prose edit moved, a rule that reported OK with every
one of its own rules skipped. Each is in [CHANGELOG.md](CHANGELOG.md) with the command that
exposed it, and the shape behind all of them is in
[docs/checks-that-inherit-their-answer.md](docs/checks-that-inherit-their-answer.md).

A project that has never found one of these has not looked.

## What the hooks decide

| Situation | Unconfigured | vstack |
|---|---|---|
| Agent claims done, tests fail | nothing intervenes | blocked |
| `rm -rf /` from an agent | runs | denied |
| `git push --force origin main` | runs | denied |
| `git reset --hard`, uncommitted work | runs | asks |
| `rm -rf node_modules` | runs | allowed |
| Untrusted repository's gate on `Stop` | no gate at all | not executed |
| Context spent per session | 0 B | ~3.9 KB full / ~2.3 KB plugin |

The last row is the price, paid every session. Check 18 reads those figures back from this table
and fails if they drift from what the hook actually emits.

A gate you cannot turn off gets deleted by the first person it inconveniences, so the Stop-hook
gate is per repository and opt-in: `vstack trust` arms it, and an untrusted `.claude/verify.sh` is
never executed. `tests/compare-baseline.sh` produces the table above by firing the real hooks, and
every row carries the value it is supposed to produce.

## The team

Fourteen subagents, each with its own context window and its own tool allowlist, dispatched by the
Task tool. A reviewer with its own context cannot be talked out of a finding by the conversation
that produced the code.

Every agent carries a call sign and signs its reasoning with it, not only its final report. An
unattributed verdict cannot be challenged, and separate contexts are worth routing to only because
they can disagree. The lead is **RICK**. A Stop hook blocks a session that dispatched subagents and
then reported their work without naming any of them.

Instances are distinguished by a dimension code, so three reviewers reading the same diff at once
are `BIRDPERSON C-137`, `BIRDPERSON J-19`, `BIRDPERSON D-99` rather than three anonymous voices.

| call sign | agent | what it is for |
|---|---|---|
| **RICK** | *the lead* | routes the work and holds the bar; does none of it |
| **SUMMER** | `product-owner` | asks what this is actually for before anyone builds it |
| **ZEEP** | `planner` | builds the system the work will run inside |
| **MEESEEKS** | `worker` | spawned for one task, does it, ceases to exist |
| **MORTY** | `explorer` | sent to go and look, comes back with what it saw |
| **GLOOTIE** | `ui-engineer` | develops the app, whatever the advice on the arm says |
| **JAGUAR** | `test-writer` | precise, silent, and the job is done when it leaves |
| **BETH** | `qa` | a surgeon: verifies before anything gets closed up |
| **BIRDPERSON** | `code-reviewer` | grave, blunt, and never once tactful about a defect |
| **EVIL-MORTY** | `security-auditor` | thinks like the attacker because it is one |
| **NOOBNOOB** | `debugger` | the one who actually cleans up after everybody |
| **PICKLE-RICK** | `performance-engineer` | extreme optimisation under an absurd constraint |
| **SCARY-TERRY** | `design-reviewer` | judges how it looks, and you cannot hide from it |
| **POOPYBUTTHOLE** | `accessibility-auditor` | was always there; the room just never noticed |
| **UNITY** | `release-manager` | gets an entire population moving in sync, or nothing ships |

`/team` runs the whole roster on a goal — spec, plan, build, verify, review, fix, presentation,
ship — and writes a handoff log to `.audit/team-log.tsv`, one row per phase with the agent, its
verdict, the evidence, and what the lead decided. `vstack receipt` renders it. A log where every
decision is `proceed` is called out as decoration: it cannot tell a lead who held the bar from one
who had nothing to hold it against.

## Limits

No measured quality improvement is claimed. A head-to-head review benchmark run here returned a
null, and a survey of the published literature found no config-layer intervention with a measured
correctness gain on frontier models. The honest case for this is safety and reversibility, not
better code. See [docs/research/](docs/research/).

Supported: macOS, Linux, and WSL and Alpine as Linux. CI runs `ubuntu-latest`, `macos-latest` and
an `alpine:latest` container, and check 26 fails if the platforms named here are not the platforms
CI tested. Windows is not supported. That lane could be made to pass. It could not be made to be
true.

## Docs

- [How skills fire](docs/how-skills-fire.md) — the routing mechanism and what was measured
- [Checks that inherit their answer](docs/checks-that-inherit-their-answer.md) — the failure shape behind every fake green found here
- [What this actually does](docs/what-this-actually-does.md) — every claim sorted into measured, mechanism-only, and unproven, each dated and sourced
- [Do harnesses help?](docs/research/do-harnesses-help.md) — the null result, in full
- [Harness value: literature](docs/research/harness-value-literature-2026-08.md) — what anyone has actually measured
- [What we changed, and what we declined](docs/research/what-we-changed-2026-08-22.md)
- [Provenance](docs/provenance/README.md) — dated audit records, including [research-v1.7.0.md](docs/provenance/research-v1.7.0.md)
- [MCP servers](mcp/README.md) — what is wired and what it reaches
- [Tests](tests/README.md) — every suite and what it costs to run
- [CHANGELOG](CHANGELOG.md) · [CONTRIBUTING](CONTRIBUTING.md) · [SECURITY](SECURITY.md) · [CODE_OF_CONDUCT](CODE_OF_CONDUCT.md)

## Credits

Skills ported and adapted from [pstack](https://github.com/pstack-dev/pstack) and
[Superpowers](https://github.com/obra/superpowers), with attribution per skill in
[claude/skills/ATTRIBUTION.md](claude/skills/ATTRIBUTION.md). Licences for vendored work are in
[NOTICE](NOTICE) and alongside it.

MIT. See [LICENSE](LICENSE).
