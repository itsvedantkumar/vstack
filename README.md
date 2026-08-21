# vstack

**A Claude Code setup where the skills fire on their own** — and one that can show you they do,
rather than telling you.

[![verify](https://github.com/itsvedantkumar/vstack/actions/workflows/verify.yml/badge.svg)](https://github.com/itsvedantkumar/vstack/actions/workflows/verify.yml)
[![license](https://img.shields.io/badge/license-MIT%20%2B%20Apache--2.0-blue.svg)](LICENSE)
[![plugin](https://img.shields.io/badge/claude%20plugin-vstack-6f42c1.svg)](#start-here-the-skills-alone)
[![runs on](https://img.shields.io/badge/runs%20on-macOS%20%2B%20Linux-lightgrey.svg)](#what-runs-where)

> **This is for Claude Code and nothing else.** Not Cursor, not Codex, not Aider, not a local
> Llama or Qwen or DeepSeek, not an OpenAI or Gemini model behind a compatibility shim. Every
> piece of it is built on machinery only Claude Code has: skills that the model loads by reading
> their descriptions, the six hook event lanes, subagents, `skillOverrides`, `settings.json`,
> plugin marketplaces, and the `claude` CLI's own flags. There is no adapter layer and none is
> planned. If you are not running Claude Code, none of this does anything.
>
> **macOS and Linux.** Windows is not supported, and the reason is in [what runs where](#what-runs-where).

Ask for a README and the writing skills load. Hand it a TypeScript file and the type-safety
skill loads. Say "audit this three ways" and it fans out three subagents in one message. None of
that needs a slash command.

That claim is easy to make and most setups make it. Here it is measured: `tests/auto-trigger.sh`
runs 12 prompts against the real model and reports which attempt each one landed on, so the day
routing starts eroding shows up as a number rather than a feeling.

The same idea runs through the rest. Every one of the 33 checks in the verification gate has a
row in a suite that breaks what that check watches and requires the gate to go red naming it — a
check nobody has watched fail is indistinguishable from a check that always passes. The
installer is run into 22 throwaway home directories on Linux, macOS and Alpine on every
push, because the only way to know an installer works is to run it and look at the files.

**Two audits have been run against this repo by models other than the one that wrote it.** They
found real defects — an uninstall that deleted config it should have restored, a gate that was
installed and silently never ran, credentials exported into every shell. Those are fixed, each
with a test that fails without the fix. `CHANGELOG.md` says what they were. That history is the
honest version of "it works".

## Start here: the skills alone

If you want better Claude Code behaviour and nothing else, this is the whole thing. It adds
skills, subagents, commands and the routing hook, plus a Stop-hook gate that stays inert until
you trust a repo's own `.claude/verify.sh`. It does not touch your shell, your
credentials, your `~/.claude/settings.json`, or anything else on the machine.

```bash
claude plugin marketplace add itsvedantkumar/vstack
claude plugin install vstack@vstack
```

Ask Claude to write a README and watch `technical-writing` and `unslop` load without being
asked. If nothing about that appeals, stop here — you have lost thirty seconds and changed
nothing.

## The full workstation setup

Everything below installs one person's whole working environment: shell environment tuning, MCP
servers, CLI wrappers, a Conductor configuration, a destructive-command guard, and a Stop hook
that blocks an agent from claiming work is done while verification fails. It is genuinely
useful and it is genuinely opinionated. Read `## What this does not do` before running it.

**If the tools are already on the machine** — this installs the config alone:

```bash
git clone https://github.com/itsvedantkumar/vstack.git
cd vstack
./install.sh
```

**On a machine with nothing on it**, the bootstrap installs the tools first. Pin a release and
read the script before running it:

```bash
curl -fsSL https://raw.githubusercontent.com/itsvedantkumar/vstack/v1.8.0/bootstrap.sh -o bootstrap.sh
less bootstrap.sh                       # about 100 lines
VSTACK_REF=v1.8.0 bash bootstrap.sh     # installs that tag, not main
```

The unpinned one-liner is shorter and is what most people will paste:

```bash
curl -fsSL https://raw.githubusercontent.com/itsvedantkumar/vstack/main/bootstrap.sh | bash
```

It hands this repository — and Homebrew's, Bun's, uv's and Anthropic's installers, which it runs
next — immediate shell on your machine, at whatever state `main` happens to be in. `VSTACK_REF`
pins this repo to a tag you have read. It does nothing about the installers downstream. That is
the trade, stated plainly rather than left for you to work out.

On macOS it installs Homebrew, the CLI tools, Conductor and the Claude Code CLI. On Linux it
falls back to apt, dnf or apk and skips Conductor, which is a Mac app. Windows is not supported.
Every hook is a shell script, and the 600-mode check that protects `secrets.env` has no meaning
on a filesystem without POSIX permissions, so there is no honest way to make the claim. WSL is
Linux and the Linux lane covers it.

Nothing here schedules a job, phones home, or updates itself in the background. `vstack update`
shows you the incoming commits and the diff of every script the gate executes, and refuses to
proceed without a terminal.

## Three lanes, and which one reaches where

Config reaches a session by one of three routes. Most confusion about this setup is really
confusion about which lane something is in.

| Lane | Command | Lands in | Reaches |
|---|---|---|---|
| global | `./install.sh` | `~/.claude`, `~/.config/agents` | every local session on this machine |
| per-repo overlay | `./overlay.sh <repo>` | committed `.claude/` + `.conductor/` in that repo | Conductor workspaces and cloud sandboxes, which have no `~/.claude` |
| plugin marketplace | `claude plugin install vstack@vstack` | Claude Code's plugin cache | anyone, on any machine, without cloning |

The overlay lane is the one people miss. A cloud sandbox clones your repo and starts from
nothing — no home directory config of any kind. If the skills are not committed in that repo,
that session does not have them. `bin/doctor` fails when an active repo has no overlay, and it
finds those repos through their Conductor workspaces rather than a hardcoded list of paths.

The plugin lane is deliberately the narrowest. It ships the skills, subagents, commands, the
routing hook, and an opt-in Stop-hook verify gate that does nothing until a repo's
`.claude/verify.sh` is trusted — two hooks, not one. The token, delegation and autonomy rules in the other two lanes
are one person's operating policy and have no business arriving with a skill pack a stranger
installed.

### Remote Control and the phone

The lanes say where config lands; sessions differ in what they can read from there:

| Source | Local terminal | Conductor | Remote Control | Cloud session / routine (phone) |
|---|:--:|:--:|:--:|:--:|
| `~/.claude/**` (user scope) | ✅ | ✅ | ✅ runs on your Mac | ❌ sandbox has no `~/.claude` |
| `~/.zshenv` exports | ✅ | ✅ | ✅ | ❌ |
| `shell/claude-parity.zsh` wrapper | ✅ | n/a | ❌ never goes through your zsh | ❌ |
| committed `.claude/` overlay | ✅ | ✅ | ✅ | ✅ the only source a sandbox sees |

Two environment variables look like harmless telemetry switches and silently kill the Remote
Control column: `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` and `DISABLE_GROWTHBOOK` both gate
feature-flag evaluation, which Remote Control needs to register. With either set,
`claude doctor` reports "Remote Control rollout could not be verified" and phone dispatch
stops working. `bin/doctor` fails when the first is set.

Which settings keys may enter the overlay at all is decided in
[`claude/settings.project-keys`](claude/settings.project-keys), which records why each key
earns its place and names the ones deliberately kept in user scope. Hook commands in the
overlay use `$CLAUDE_PROJECT_DIR`-relative paths on purpose: an absolute `/Users/...` path
exits 127 on every hook event inside a sandbox.

## What you get

| Component | Count | Installs to |
|---|---|---|
| Skills | 26 | `~/.claude/skills/` |
| Subagents | 8 | `~/.claude/agents/` |
| Commands | 14 | `~/.claude/commands/` |
| Hooks | 6 | `~/.claude/hooks/` |
| CLI wrappers | 6 | `~/.config/agents/bin/` |
| MCP servers | 2 | merged into `~/.claude.json` |
| Global directives | `CLAUDE.md` | `~/.claude/CLAUDE.md` |

Counts regenerate with `find claude/skills -maxdepth 1 -mindepth 1 -type d | wc -l` and the
matching `ls` per directory.

## The skills

14 workflow skills, each triggered by a situation rather than a command.

| Skill | Fires when |
|---|---|
| `swarm` | work splits into independent parts, or approaches should be raced |
| `blast-radius` | you are shipping a risky change and want to know what it breaks |
| `interrogate` | code is going in that only one reviewer, or none, has seen |
| `create-verification-skill` | a repo has no scripted way to prove it works |
| `maintain-verification-skill` | that proof has drifted from the app |
| `show-me-your-work` | long or overnight work a human reviews after stepping away |
| `reflect` | you were corrected, or found a workflow worth keeping |
| `technical-writing` | writing docs, RFCs, READMEs, PR bodies, commit messages |
| `unslop` | any prose at all, to cut the AI tells |
| `typescript-best-practices` | reading, writing, or reviewing `.ts` or `.tsx` |
| `ui-iterate` | editing UI files when a dev server runs: screenshot, critique, fix before declaring done |
| `agent-browser` | screenshotting or driving a dev server when the shared Chrome is unavailable or contended |
| `impeccable` | building or polishing UI where visual quality matters: typography, motion, spacing, design modes |
| `component-registry` | about to hand-write a UI component in a React/Tailwind repo |

Eight principles load when the moment matches and apply a rule rather than run a procedure.

| Principle | Applies when |
|---|---|
| `prove-it-works` | before declaring anything done |
| `fix-root-causes` | debugging, or reaching for a `try`/`except` guard |
| `encode-lessons-in-structure` | the same correction lands twice |
| `type-system-discipline` | designing types or a function signature |
| `boundary-discipline` | wiring validation, error handling, or an adapter |
| `make-operations-idempotent` | writing cron jobs, retries, anything that can restart |
| `sequence-verifiable-units` | sweeps, migrations, stacked commits |
| `build-the-lever` | the same manual edit or check keeps repeating |

Four more cover the planning chain: `brainstorming`, `writing-plans`,
`test-driven-development`, and `executing-plans`.

## Why they fire

Installing a skill does not make it trigger. Three things have to be true at once, and the
third is invisible when it breaks:

1. The skill must not carry `disable-model-invocation`.
2. Its description must name a situation, because situations are what the model matches.
3. The description must survive the skill listing. Set `skillListingBudgetFraction` too low
   for the number of installed skills and Claude Code truncates descriptions, cutting exactly
   the trigger phrases that make matching work. Nothing errors. The skills just stop firing.

Even with all three right, something has to connect a situation to a skill.
`claude/hooks/inject-session-context.sh` carries that routing block and runs at every session
start.

`tests/auto-trigger.sh` proves it still works. It runs real prompts through the CLI and checks
which skills fired. Strip the routing block and cases fail, which is how you know the test is
worth having. [docs/how-skills-fire.md](docs/how-skills-fire.md) has the measurements.

### The ones that are not optional

Everything above is instruction, and an instruction is a probability. The routing lands on the
cases that measure it, and "lands on the cases that measure it" is a weaker claim than "always".

`claude/hooks/skill-mandate.sh` runs on `Stop` and makes two of them certain. It reads the
session transcript for what actually happened, which files were written and which skills were
invoked, and refuses to let the turn finish when a rule went unmet:

| You wrote | This must have run |
|---|---|
| `.md` or `.mdx` | `unslop` |
| `.ts` or `.tsx` | `typescript-best-practices` |

Two rules, not twenty, and the bar for adding a third is high: the situation has to be decidable
from a tool call rather than from judgement, and the skill has to be the right answer every
single time. A rule that is correct nine times in ten belongs in the routing block as guidance.
As a gate it would just teach you to switch the gate off.

It blocks at most twice per session and then latches open, it never fires while a `Stop` hook is
already running, and `VSTACK_NO_MANDATE=1` turns it off. Check 27 exercises all seven of those
behaviours in both directions, because a gate that always blocks passes any test that only
checks that it blocks.

## What this does that an unconfigured setup does not

Most setups in this space claim to make you better and none of them show it, because the claim
is usually about outcomes and outcomes depend far more on you and your problem than on any
config. So here is the narrower thing that can actually be checked — which mechanisms exist, and
what they decide when fired with identical input:

```
$ tests/compare-baseline.sh

scenario                             bare                vstack
agent claims done, tests fail        nothing intervenes  block
rm -rf / from an agent               runs                deny
git push --force origin main         runs                deny
git reset --hard, uncommitted work   runs                ask
rm -rf node_modules (routine)        runs                allow
untrusted repo's gate on Stop        no gate at all      did not run it
context spent per session (cost)     0 B                 ~3.6 KB full / ~2.1 KB plugin
```

Run it yourself; it takes a second and needs no API key. Each row asserts the decision it
expects, so it fails if a mechanism regresses, and it runs in CI on every push.

Two rows are there to keep the rest honest. `rm -rf node_modules` must be allowed, because a
guard that interrupts routine work gets switched off and a switched-off guard measures zero. And
the last row is a cost, not a benefit: this spends context on every session whether or not a
skill fires, and you should know the number before installing.

What it does not measure: whether the skills produce better work. That needs a live model and
human judgement. [`tests/auto-trigger.sh`](tests/auto-trigger.sh) measures whether they *fire*,
which is a smaller and more checkable claim, and nothing here measures quality. It also says
nothing about other setups — several have mechanisms this one does not.

## Verification that blocks completion

Put an executable `.claude/verify.sh` in a repo and the `verify-gate.sh` Stop hook runs it
before an agent may say the work is done. A non-zero exit blocks the claim and returns the
failure output as the reason. The gate stops after three blocks per session, so an overnight
run cannot loop forever.

This repo gates itself the same way:

```bash
./.claude/verify.sh
```

It checks shell syntax, JSON validity, skill frontmatter and description lengths, hardcoded
home paths, committed credentials, infrastructure identifiers, the settings merge program, and
a full `install.sh --dry-run`.

To add the same gate to another repo, ask Claude for verification there and the
`create-verification-skill` skill writes one that fits the stack.

## Day-to-day

```bash
vstack update            # fetch, review the incoming script diff, confirm, reinstall
vstack doctor            # health check
vstack doctor --drift    # has anything been edited in place?
vstack overlay <repo>    # commit the config into another repo
vstack verify            # run the gate
vstack uninstall --list  # show restorable backups
```

`doctor --drift` answers the question that costs you work: does the installed state still
match the repo it came from? Editing `~/.claude` directly works right up until the next
`install.sh` overwrites it.

`uninstall.sh` restores from those backups. It refuses to act without `--yes`, never touches
`secrets.env`, and never deletes a symlinked skill, because those belong to Claude Code and
its plugins.

## Where the config goes

```mermaid
flowchart LR
  R["vstack repo"]
  R -->|"install.sh"| H["~/.claude<br/>~/.config/agents"]
  R -->|"overlay.sh"| O[".claude/ committed<br/>in a target repo"]
  R -->|"plugin install"| P["Claude Code plugin"]
  H --> H1["local terminal<br/>Conductor<br/>Remote Control"]
  O --> O1["cloud sessions<br/>phone dispatch"]
  P --> P1["any machine<br/>skills only"]
```

A cloud session clones a repo into a sandbox with no access to your home directory, so a
committed `.claude/` directory is the only config it can read. That is what `overlay.sh` is
for. Run it in any repo you dispatch cloud work to.

**`CLAUDE_CONFIG_DIR` is honoured.** Set it and the install goes there instead of `~/.claude`,
including the hook paths written into `settings.json` and the `.claude.json` MCP entries. If
you keep separate profiles, or run in a container that puts config somewhere else, set it
before installing and everything follows.

**Shells.** The environment lane — the 1h prompt cache, tool concurrency, streaming, task
support — is written to `.zshenv` and, for bash users, to `.bashrc`. The `claude` wrapper is
zsh only: it is written in zsh and cannot be sourced by bash, so on a bash machine you get the
environment without the wrapper, and `install.sh` says so when it runs.

`tests/install-matrix.sh` runs the installer into throwaway HOMEs and asserts the resulting
tree: default, `CLAUDE_CONFIG_DIR`, a home path with a space, no `jq`, a bash user, a second run
for idempotency, both uninstall paths, and an install over a home that already holds the user's
own skills, agents, settings and MCP servers. Two more cases exercise the curl bootstrap and the
plugin marketplace against the published repo, and skip with a reason when offline. It runs on
Linux, macOS and Alpine in CI every push, and never touches your real home directory,
so it is safe to run on the machine you work on.

## Credentials

`install.sh` copies `secrets.env.example` to `~/.config/agents/secrets.env` with mode 600 when
that file does not exist, and leaves it alone when it does. Fill in the variables you use. The
MCP wrappers in `bin/` source it before they exec.

The example names the Anthropic key `ANTHROPIC_SDK_API_KEY` on purpose. Claude Code reads
`ANTHROPIC_API_KEY` and bills API credits against it instead of your subscription, so the
shell wrapper strips that name and `doctor` fails if it is set.

Two settings stay opt-in. `permissions.defaultMode=bypassPermissions` and
`skipDangerousModePermissionPrompt` stop Claude asking before it acts. Pass
`./install.sh --bypass-permissions` if you want them.

## Conductor

`.conductor/settings.toml` makes a Conductor workspace install this bundle as its setup step
and puts the verification gate behind a run button.

`./overlay.sh <repo>` writes the same file into your other repos, with a setup step that pulls
vstack in through `bootstrap.sh`. Cloud workspaces start from a bare Linux sandbox with no
`~/.claude`, so without it they get none of this. If the repo already has a
`.conductor/settings.toml`, `overlay.sh` leaves it alone and prints the lines to merge.

## Layout

```
claude/          settings, CLAUDE.md, statusline, hooks, agents, commands, skills
conductor/       user-level Conductor defaults
bin/             CLI wrappers installed to ~/.config/agents/bin
shell/           zsh wrapper and env snippet
mcp/             MCP server definitions merged into ~/.claude.json
tests/           the auto-trigger regression suite
install.sh       user-scope install, idempotent
overlay.sh       copies the config into a repo so cloud sessions get it
setup-machine.sh installs the tools a fresh machine lacks
bootstrap.sh     clone, setup-machine, and install in one line
```

## What this does not do

**Skill dispatch is a model decision, not a branch.** Routing raises the odds; it does not
guarantee them. `tests/auto-trigger.sh` allows three attempts per case for exactly this reason,
and `feature-chain` lands on the first attempt only about half the time. The suite prints which
attempt each case landed on, so erosion shows up before a case goes fully red. Treat a skill
firing as likely, not certain.

**`skillOverrides` cannot suppress a skill that comes from a plugin.** Claude Code resolves the
listing mode before it reads the setting for plugin-supplied skills. All 17 bundled overrides
here work; the plugin ones did not, which is why 38 of them were deleted. With `claude-mem`
enabled that costs about 992 tokens of listing every session, and there is no setting that
recovers it. [docs/how-skills-fire.md](docs/how-skills-fire.md) has the measurement.

**The Stop-hook gate is opt-in per repo, by content hash.** A freshly cloned repo's
`.claude/verify.sh` never runs until you run `vstack trust` there. That is deliberate — an
executable in someone else's repo running automatically on every Stop is a handout of code
execution — but it does mean the gate is inert until you arm it, and needs re-arming after you
edit it.

**`curl | bash` is a real trust decision, and pinning is the only mitigation offered.** The
one-liner runs whatever `main` holds at the moment you run it, then `setup-machine.sh` runs
Homebrew's, Bun's, uv's and Anthropic's installers, each fetched the same way. Nothing here is
digest-pinned or signature-verified, so a compromise of this account, of DNS or TLS in front of
any of those hosts, or of any chained installer becomes shell on your machine. `VSTACK_REF`
pins this repo to a tag you have read; it does nothing for the installers downstream. The
cloud-sandbox lane is pinned by default because a compromise there would reach every workspace
at once — `overlay.sh` writes a specific reviewed commit into `.conductor/settings.toml`.

**`vstack update --yes` skips the review.** An interactive update fetches, shows the incoming
commits and the full diff of every script the gate executes, and asks before merging and
re-recording trust hashes; without a terminal it refuses instead of assuming. The `--yes`
flag exists for automation, and anything automated enough to use it is back to trust-on-pull.

## What runs where

**macOS and Linux run in CI on every push. Windows is not supported.** The install matrix runs
on `ubuntu-latest`, `macos-latest` and an `alpine:latest` container, and Linux additionally
installs for real and fires the hooks. Alpine is there because BusyBox is not GNU and nothing
else in the workflow would catch a GNU-only flag.

Windows was dropped rather than left half-working. It had passed through Git Bash for three
commits, but `secrets.env` is protected by a 600-mode check, and a filesystem without POSIX
permission bits cannot enforce that. The lane could be made to go green; it could not be made
to be true. WSL is Linux and the Linux jobs cover that shape, though no job runs inside WSL
itself, so treat it as very likely rather than proven.

Two things are still macOS-only, and neither is the installer. Conductor is a Mac app, so the
`.conductor` lanes only mean something there. The `claude` shell wrapper is written in zsh and
bash cannot source it, so a bash user gets the environment without the wrapper and the
installer says so as it runs.

Nothing here installs a scheduled job on any platform: `install.sh` writes no launchd plist, no
systemd unit and no scheduled task. Scheduling is yours to arrange.

**The counts in this README are enforced, the prose is not.** `.claude/verify.sh` check 12
reads every number back and fails on a mismatch. Nothing checks whether a sentence is still
true.

## Docs

- [How skills fire](docs/how-skills-fire.md), and the measurements behind the routing block
- [Skill attribution](claude/skills/ATTRIBUTION.md), per-skill source and license
- [MCP servers](mcp/README.md), what ships globally and how to scope one to a project
- [The auto-trigger test](tests/README.md), how to run and extend it, and how the gate proves
  each of its own checks can fail
- [Why these skills](docs/provenance/pstack-audit.md), the fit-and-benefit audit of all 44 pstack
  skills that decided which 18 were worth porting
- [Provenance](docs/provenance/README.md), the design history this project was extracted from
- [Five open investigations](docs/provenance/research-v1.7.0.md), an outside research pass on
  skill reachability, false-success labelling, ablation design, evidence bundles and a UI floor
- [Changelog](CHANGELOG.md), with the measurements behind each release

## Credits

18 skills are ported from [pstack](https://github.com/cursor/plugins), 4 come from
[Superpowers](https://github.com/obra/superpowers), 1 from
[Impeccable](https://github.com/pbakaus/impeccable) by Paul Bakaus (Apache 2.0), 1 from
[agent-browser](https://github.com/vercel-labs/agent-browser) by Vercel Labs (Apache 2.0),
and 2 are original to this repo (`ui-iterate` and `component-registry`).
Porting adapted them to Claude Code: Cursor model names mapped to Anthropic ones, `Task` calls to
the `Agent` tool, and cloud-only parameters to local execution. Per-skill sources and licenses are
in [ATTRIBUTION.md](claude/skills/ATTRIBUTION.md).
