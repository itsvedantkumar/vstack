# vstack

One repo that installs a complete Claude Code setup on a Mac: skills that fire on their own,
subagents, hooks, MCP servers, deploy scripts, and scheduled routines.

Everything here used to live in four places at once. Some of it sat in `~/.claude`, some in
`~/.config/agents`, some only in a cloud routine, and the parts that mattered most were the
parts nothing tracked. Reinstalling meant remembering. Now it is one clone and one command.

```bash
git clone https://github.com/itsvedantkumar/vstack.git
cd vstack
./install.sh
```

Run `./install.sh --dry-run` first if you want to see what it touches. It backs up every file
it overwrites to `~/.config/agents/backups/install-<timestamp>/`, and it never overwrites
`secrets.env`.

On a machine with nothing set up yet, including a Linux sandbox, one line does the clone and
the install:

```bash
curl -fsSL https://raw.githubusercontent.com/itsvedantkumar/vstack/main/bootstrap.sh | bash
```

## What lands where

| Component | Count | Installs to |
|---|---|---|
| Skills | 29 (24 active, 5 off) | `~/.claude/skills/` |
| Subagents | 7 | `~/.claude/agents/` |
| Slash commands | 15 | `~/.claude/commands/` |
| Hooks | 4 | `~/.claude/hooks/` |
| CLI wrappers | 8 | `~/.config/agents/bin/` |
| Scheduled routines | 3 | `~/.claude/scheduled-tasks/` |
| launchd timers | 3 | `~/Library/LaunchAgents/` (only with `--with-launchd`) |
| MCP servers | 2 | merged into `~/.claude.json` |

Regenerate these counts with `find claude/skills -maxdepth 1 -mindepth 1 -type d | wc -l` and
the matching `ls` for each directory.

## The part that took the longest to get right

Installing a skill does not make it fire. That distinction cost a week of thinking the setup
worked when it did not.

A skill needs three things to trigger on its own. It must not carry
`disable-model-invocation`. Its description must describe a situation, not a capability,
because the model matches situations. And the description has to survive the skill listing:
if `skillListingBudgetFraction` is too small for the number of installed skills, Claude Code
truncates descriptions, and it truncates exactly the trigger phrases that make matching work.
That last one is invisible. Nothing errors. The skills just quietly stop firing.

Even with all three right, nothing connects a situation to a skill unless something says so.
`claude/hooks/inject-session-context.sh` carries a routing block that maps situations to
skills, and it runs on every session start. That block is the reason the skills in this repo
fire without being asked for.

## Verification is a script, not a promise

`.claude/verify.sh` in a repo is run by the `verify-gate.sh` Stop hook. When it exits
non-zero, the agent is blocked from claiming the work is done, and the failure output comes
back as the reason. Three blocks per session, then it stops, so an overnight run cannot loop
forever.

This repo gates itself with the same mechanism. Run `./.claude/verify.sh` and it checks shell
syntax, JSON validity, plist validity, skill frontmatter and description lengths, hardcoded
home paths, committed credentials, and a full `install.sh --dry-run`. To add the same gate to
another repo, ask Claude for verification in that repo and the `create-verification-skill`
skill writes one that fits its stack.

## Credentials

`install.sh` copies `secrets.env.example` to `~/.config/agents/secrets.env` with mode 600 when
that file does not exist, and leaves it alone when it does. Fill in the variables you use. The
MCP wrappers in `bin/` source it before they exec, and `.zshenv` sources it for your shell.

The example deliberately names the Anthropic key `ANTHROPIC_SDK_API_KEY`. Claude Code reads
`ANTHROPIC_API_KEY` and bills API credits against it instead of your subscription, so the
shell wrapper strips that name from the environment and `doctor` fails if it is set.

## Scheduling

The three routines under `claude/scheduled-tasks/` are prompts. Scheduling them is a separate
choice, and there are two lanes:

- **Cloud routines** at [claude.ai/code/routines](https://claude.ai/code/routines) run whether
  or not the Mac is awake. This is the better default.
- **launchd timers** run locally. Install them with `./install.sh --with-launchd`.

Pick one lane. Running both doubles every job.

The three routines are templates, not live jobs. They carry `<owner>/<repo>` and
`prj_YOUR_PROJECT_ID` placeholders, and each file opens with the list of values to replace.
`./.claude/verify.sh` fails if a real Vercel, environment, or trigger ID lands in the repo.

## Health check

```bash
~/.config/agents/bin/doctor
```

`doctor` checks hooks, subagents, secrets file permissions, auth method, Conductor parity
keys, context caps, and Remote Control settings. It exits non-zero on drift. Run it after any
Claude Code update: plugin updates have reverted config here before.

## Layout

```
claude/          settings, hooks, agents, commands, skills, scheduled-tasks
bin/             CLI wrappers installed to ~/.config/agents/bin
shell/           zsh wrapper and env snippet
mcp/             MCP server definitions merged into ~/.claude.json
launchd/         plist templates, __HOME__ substituted at install time
install.sh       user-scope install, idempotent
overlay.sh       copies the config into a repo so cloud sessions get it
```

## Conductor

`.conductor/settings.toml` makes a Conductor workspace install this bundle as its setup step,
and puts the verification gate behind a run button. Creating a workspace on vstack installs
vstack.

For your other repos, `./overlay.sh /path/to/repo` writes a `.conductor/settings.toml` whose
setup step pulls vstack in through `bootstrap.sh`. That matters for cloud workspaces: they
start from a bare Linux sandbox with no `~/.claude`, so without a setup step they get none of
this. If the repo already has a `.conductor/settings.toml`, `overlay.sh` leaves it alone and
prints the lines to merge yourself.

Cloud sandboxes often ship without `jq`. The installer no longer treats that as fatal: it
installs skills, hooks, agents, and commands, then skips only the two merge steps that need
`jq` and says so.

## Two lanes, and why both exist

`install.sh` writes to `~/.claude`. That covers the local terminal, Conductor, and Remote
Control sessions from your phone.

A cloud session is different. It clones the repo into a sandbox with no access to your home
directory, so a committed `.claude/` directory is the only config it can read. Run
`./overlay.sh /path/to/repo` in any repo you dispatch cloud work to.

## Credits

The 29 skills come from four places: 18 ported from [pstack](https://github.com/cursor/plugins),
7 from [Superpowers](https://github.com/obra/superpowers), 2 third-party (Apache 2.0 and MIT),
and 2 written for this setup. Per-skill sources, licenses, and the reason each disabled skill
is disabled are in `claude/skills/ATTRIBUTION.md`.

Five skills ship disabled through `skillOverrides` in `claude/settings.json`. They are kept
rather than deleted because the originals live nowhere else, and a disabled skill costs no
context. That file is the one place that decides what is active.
