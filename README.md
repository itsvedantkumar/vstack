# vstack

A Claude Code configuration whose claims are executable. Every behaviour it advertises has a
check, and every check has a mutation that proves the check can fail.

[![verify](https://github.com/itsvedantkumar/vstack/actions/workflows/verify.yml/badge.svg)](https://github.com/itsvedantkumar/vstack/actions/workflows/verify.yml)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![plugin](https://img.shields.io/badge/claude%20plugin-vstack-6f42c1.svg)](#install)
[![runs on](https://img.shields.io/badge/runs%20on-macOS%20%2B%20Linux-lightgrey.svg)](#what-runs-where)

> **Claude Code only.** Not Cursor, not Codex, not Aider, not a local Llama or Qwen or DeepSeek,
> not an OpenAI or Gemini model behind a compatibility shim. It is built on machinery only Claude
> Code has: skills the model selects by reading their descriptions, the six hook event lanes,
> subagents, `skillOverrides`, `settings.json`, plugin marketplaces, and the CLI's own flags.
> There is no adapter layer and none is planned.

```bash
claude plugin marketplace add itsvedantkumar/vstack
claude plugin install vstack@vstack
```

## How this differs from gstack

[gstack](https://github.com/garrytan/gstack) is the closest comparable project and the obvious
thing to measure against. It is larger and broader: a skill count of 53 against this repo's 28, eight host
agents against one, a TypeScript test suite, and fourteen CI workflows. If you want a virtual
engineering team of named specialists across several agents, it is the better fit and it is
genuinely good.

vstack is a different shape. Four differences are checkable rather than asserted.

**It configures the machine, not just the prompt.** gstack ships skills and commands. vstack also
ships six hooks across the `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`,
`PostToolUseFailure` and `Stop` lanes, a `settings.json` merge that preserves keys it does not
own, two MCP servers, a statusline, shell parity files, and Conductor configuration. Routing
happens in the hooks, so it does not depend on the model remembering an instruction.

**Its gate is falsifiable.** `.claude/verify.sh` runs 34 checks.
`tests/gate-falsifiability.sh` breaks the repository once per check and requires the gate to go
red naming that check, then restores the tree byte for byte and fails if anything was left
behind. Check 16 fails if any check has no mutation row, so a check cannot be added without one.
A check nobody has watched fail is indistinguishable from a check that always passes, and this
repository has shipped five of those; each one is recorded in [CHANGELOG.md](CHANGELOG.md) with
the command that exposed it.

**Uninstalling restores what was there.** `./uninstall.sh --yes` removes vstack's hook entries,
its `skillOverrides`, the trust store, the shell blocks and the Conductor files, and leaves every
key, override and MCP server you owned byte-identical. One of the environment cases in
`tests/install-matrix.sh` seeds a scratch home with user-owned settings and asserts both halves,
with positive controls that fail if the thing being removed was never installed.

**It publishes its own broken measurements.** [tests/evals/RESULTS.md](tests/evals/RESULTS.md)
carries ten benchmark defects found in this repository's own harness, seven of which flattered
vstack, plus one published run that was retracted after a reader refused to believe it. There is
no vstack-versus-gstack number in this README because the only one ever produced here came from a
gstack arm whose helper scripts did not exist on the machine that ran it.

What gstack does better: breadth of skills, multi-agent support, and a conventional unit-test
suite. Pick on which of those you need.

## Install

Three lanes. All of them are exercised on every commit by
[`tests/install-matrix.sh`](tests/install-matrix.sh) across macOS, Ubuntu and Alpine.

**Skills only, through the plugin marketplace.** Adds the skills, commands and agents. Touches
nothing else on your machine.

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
curl -fsSL https://raw.githubusercontent.com/itsvedantkumar/vstack/v1.12.1/bootstrap.sh -o bootstrap.sh
less bootstrap.sh                        # about 100 lines
VSTACK_REF=v1.12.1 bash bootstrap.sh     # installs that tag, not main
```

Check 24 fails if a version named in these docs is not a tag that exists, because a pinned
quickstart that returns 404 is worse than no quickstart. That check was added after this README
shipped a pin to an untagged release.

Removing it:

```bash
./uninstall.sh --yes
```

## What lands where

| Component | Count | Path |
|---|---|---|
| Skills | 28 | `~/.claude/skills/` |
| Subagents | 8 | `~/.claude/agents/` |
| Commands | 14 | `~/.claude/commands/` |
| Hooks | 6 | `~/.claude/hooks/` |
| CLI wrappers | 6 | `~/.config/agents/bin/` |
| MCP servers | 2 | merged into `~/.claude.json` |

`install.sh` merges rather than overwrites. It backs up every file it touches into
`~/.config/agents/backups/`, adds only the hook entries it owns, and leaves keys it does not
recognise alone. Check 21 fails if it deletes a key this repository never shipped.

## Skills fire without being asked

A skill is selected by its description, so a description is a trigger and its length is a
functional constraint. Check 3 fails a skill whose description exceeds the 200-character listing
cap, because past that it is truncated and the skill silently stops being selected.

`tests/auto-trigger.sh` runs 14 real prompts through the CLI and reports which attempt each one
landed on. It is a measurement, not an assertion: dispatch is a model decision, so the suite
retries up to three times and records the hit rate. The two negative cases fail if a trivial
prompt pulls in a skill that has no business firing.

Two rules do not rely on dispatch at all. The `Stop` hook refuses to end a turn where prose was
written and `unslop` never ran, or TypeScript was written and `typescript-best-practices` never
ran. `VSTACK_NO_MANDATE=1` turns that off, because a gate you cannot turn off gets deleted by the
first person it inconveniences.

`grill-me` fires from the `UserPromptSubmit` hook on the first substantive prompt of a session
and on any prompt long enough to be a plan. `VSTACK_NO_GRILL=1` turns it off and
`VSTACK_GRILL_CHARS` moves the threshold. Check 32 tests both directions and the byte budget.

Full method and the measurements behind it: [docs/how-skills-fire.md](docs/how-skills-fire.md).

## The verification gate

The `Stop` hook runs a repository's own `.claude/verify.sh` before a turn can end, and blocks on
failure. It refuses to execute a gate it has not been shown, so cloning a hostile repository does
not run that repository's code: the trust store at `~/.config/agents/verify-trust` records the
hash you approved, and a changed gate has to be approved again.

For this repository, the gate is what the badge above reports. Locally:

```bash
./.claude/verify.sh               # 34 checks
./tests/gate-falsifiability.sh    # one mutation per check
./tests/install-matrix.sh         # 23 environment lanes
./tests/auto-trigger.sh           # 14 prompts through the real CLI
./tests/compare-baseline.sh       # what the hooks decide, vs no hooks
./bin/doctor && ./bin/doctor --drift
```

A skip is not a pass. The gate prints `N declared, N ran, N skipped` and fails if those do not
add up, because a check that throws mid-body used to leave no trace at all.

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

The last row is the cost, stated because it is paid every session. None of this measures whether
the output is better. `tests/evals/` is where that question is attempted, and
[RESULTS.md](tests/evals/RESULTS.md) is honest about how often the attempt has been wrong.

## Day to day

```bash
/ship            # verify, commit, push
/review          # code review of the current diff
/doctor          # health-check the installed setup
vstack update    # pull and reinstall, refusing a dirty checkout
doctor --drift   # compare what is installed against this repo
```

## What runs where

Supported: macOS, Linux, and WSL and Alpine as Linux. CI runs `ubuntu-latest`, `macos-latest` and an
`alpine:latest` container, and check 26 fails if the platforms named here are not the platforms CI
actually runs.

Windows is not supported. It passed through Git Bash for three commits and was dropped on
purpose: `secrets.env` is protected by a 600-mode check, and a filesystem without POSIX
permission bits cannot enforce it. That lane could be made to pass. It could not be made to be
true.

## What this does not do

It does not make the model better at your codebase, and nothing here claims a quality improvement
that has been measured. It does not manage secrets beyond a 600-mode file and wrappers that load
it. It does not work offline for the lanes that fetch. It is opinionated about model, effort and
delegation, and those opinions are one person's; the plugin lane exists so you can take the
skills without them.

## Documentation

- [docs/how-skills-fire.md](docs/how-skills-fire.md) — dispatch, the listing budget, and the measurements
- [tests/evals/RESULTS.md](tests/evals/RESULTS.md) — every benchmark run, including the retracted one
- [tests/README.md](tests/README.md) — what each suite proves
- [mcp/README.md](mcp/README.md) — the two MCP servers
- [docs/provenance/](docs/provenance/README.md) — where the ported skills came from and what changed
- [docs/provenance/research-v1.7.0.md](docs/provenance/research-v1.7.0.md) — the outside review that specified the design-quality floor
- [claude/settings.project-keys](claude/settings.project-keys) — the keys the overlay is allowed to write
- [CHANGELOG.md](CHANGELOG.md) — every release, and every defect that produced one
- [CONTRIBUTING.md](CONTRIBUTING.md) — the evidence bar, and how to add a check
- [SECURITY.md](SECURITY.md) — what this writes to your machine, and how to report a vulnerability

## Credits

18 skills are ported from [pstack](https://github.com/cursor/plugins), 4 from
[Superpowers](https://github.com/obra/superpowers), 1 from
[Impeccable](https://github.com/pbakaus/impeccable), 2 from
[Vercel Labs](https://github.com/vercel-labs/agent-browser), and 1 from
[Matt Pocock](https://github.com/mattpocock/skills). The destructive-command guard adapts an idea
from [gstack](https://github.com/garrytan/gstack). Per-skill provenance, licences and every
deviation from upstream: [claude/skills/ATTRIBUTION.md](claude/skills/ATTRIBUTION.md).

MIT. Ported skills keep their own licences; see [NOTICE](NOTICE).
