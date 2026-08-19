# vstack

One repo that installs a complete Claude Code setup on a Mac: skills that fire on their own,
subagents, hooks, MCP servers, and deploy scripts.

Everything here used to live in three places at once: some in `~/.claude`, some in
`~/.config/agents`, and the parts that mattered most in nothing at all. Reinstalling meant
remembering. Now it is one clone and one command.

```bash
git clone https://github.com/itsvedantkumar/vstack.git
cd vstack
./install.sh
```

Run `./install.sh --dry-run` first if you want to see what it touches. It backs up every file
it overwrites to `~/.config/agents/backups/install-<timestamp>/`, and it never overwrites
`secrets.env`.

## A machine with nothing on it

One line takes a new Mac from empty to working. It installs Homebrew, the tools, the Claude
Code CLI, and then this config:

```bash
curl -fsSL https://raw.githubusercontent.com/itsvedantkumar/vstack/main/bootstrap.sh | bash
```

`bootstrap.sh` clones vstack to `~/.vstack`, runs `setup-machine.sh`, then runs `install.sh`.
Pass `--skip-deps` to install config only.

`setup-machine.sh` installs by tier, and checks each tool before installing it, so re-running
costs seconds:

| Tier | Tools | For |
|---|---|---|
| core | `git`, `jq`, `ripgrep`, `fd`, `gh`, `node`, `bun`, `uv` | agent tooling and this installer |
| claude | Claude Code CLI | the agent itself |
| deploy | `vercel`, `wrangler` | the autonomous deploy chain |
| plugins | claude-mem, frontend-design, typescript-lsp | memory layer and language tooling |
| security | `trivy`, `gitleaks`, `nmap`, `nuclei` | the `/security` command, add `--with-security` |

Only `git` and `jq` decide the exit code. A missing `nuclei` is not a broken machine.

Two things it cannot do for you. Xcode command line tools need a GUI prompt, so it tells you
to run `xcode-select --install` and continues. OWASP ZAP is a large Java app and is left to
you.

Check a machine without changing it:

```bash
./setup-machine.sh --check
```

## What lands where

| Component | Count | Installs to |
|---|---|---|
| Skills | 22 | `~/.claude/skills/` |
| Global directives | `CLAUDE.md` | `~/.claude/CLAUDE.md` |
| Plugins | 3 | installed and enabled by `setup-machine.sh` |
| Subagents | 7 | `~/.claude/agents/` |
| Slash commands | 15 | `~/.claude/commands/` |
| Hooks | 4 | `~/.claude/hooks/` |
| CLI wrappers | 8 | `~/.config/agents/bin/` |
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
syntax, JSON validity, skill frontmatter and description lengths, hardcoded home paths,
committed credentials, infrastructure identifiers, and a full `install.sh --dry-run`. To add the same gate to
another repo, ask Claude for verification in that repo and the `create-verification-skill`
skill writes one that fits its stack.

## Credentials

`install.sh` copies `secrets.env.example` to `~/.config/agents/secrets.env` with mode 600 when
that file does not exist, and leaves it alone when it does. Fill in the variables you use. The
MCP wrappers in `bin/` source it before they exec, and `.zshenv` sources it for your shell.

The example deliberately names the Anthropic key `ANTHROPIC_SDK_API_KEY`. Claude Code reads
`ANTHROPIC_API_KEY` and bills API credits against it instead of your subscription, so the
shell wrapper strips that name from the environment and `doctor` fails if it is set.


## Standing directives

`claude/CLAUDE.md` installs to `~/.claude/CLAUDE.md` and is read at the start of every
session. It is the shortest file here and the one that changes behaviour most: act instead of
asking, verify before claiming done, and chain the planning skills without being told to.

`install.sh` backs it up before overwriting, because on a machine that has been running a
while this is the file most likely to have been hand-edited.

## Day-to-day

```bash
vstack update            # pull the repo, reinstall
vstack doctor            # health check
vstack doctor --drift    # has anything been edited in place?
vstack overlay <repo>    # commit the config into another repo
vstack verify            # run the gate
vstack uninstall --list  # show restorable backups
```

`doctor` checks hooks, subagents, secrets file permissions, auth method, Conductor parity
keys, context caps, and Remote Control settings. Run it after any Claude Code update: plugin
updates have reverted config here before.

`doctor --drift` answers a different question: does the installed state still match the repo
it came from? Editing `~/.claude` directly works right up until the next `install.sh`
overwrites it, so drift means unsaved work is about to disappear. Fix it by copying the change
back into the repo, then reinstalling.

`uninstall.sh` restores from the backups `install.sh` has been writing all along. `--list`
shows the timestamps, `--dry-run` prints the plan, and it refuses to touch anything without
`--yes`. It never removes `secrets.env`, and it never deletes a skill that is a symlink,
because those belong to Claude Code and its plugins.

## Layout

```
claude/          settings, CLAUDE.md, statusline, hooks, agents, commands, skills
conductor/       user-level Conductor defaults (model, plan mode)
bin/             CLI wrappers installed to ~/.config/agents/bin
shell/           zsh wrapper and env snippet
mcp/             MCP server definitions merged into ~/.claude.json
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

## Install as a plugin

vstack is also a Claude Code marketplace, which is the fastest way to get the skills without
touching your machine config:

```bash
claude plugin marketplace add itsvedantkumar/vstack
claude plugin install vstack@vstack
```

As a plugin the session hook runs in `VSTACK_PROFILE=skills` mode: it injects the skill
routing block and nothing else. The token, delegation, and autonomy rules are one person's
operating policy, and a marketplace install has no business forcing them on you. `install.sh`
still applies the full block, because there you asked for it.

That delivers the 22 skills, 7 subagents, 15 commands, and the session hook that routes
situations to skills. It does not deliver the rest: user settings such as
`skillListingBudgetFraction`, the `bin/` wrappers, the shell lane, MCP servers, or
`secrets.env`. A plugin cannot write those. Use `install.sh` for the whole setup and the
plugin when you only want the skills.

Pick one or the other. Installing both runs the session hook twice and injects the operating
mode into every session two times over.

## Two lanes, and why both exist

`install.sh` writes to `~/.claude`. That covers the local terminal, Conductor, and Remote
Control sessions from your phone.

A cloud session is different. It clones the repo into a sandbox with no access to your home
directory, so a committed `.claude/` directory is the only config it can read. Run
`./overlay.sh /path/to/repo` in any repo you dispatch cloud work to.

## Credits

The 22 skills come from two places: 18 ported from [pstack](https://github.com/cursor/plugins)
and 4 from [Superpowers](https://github.com/obra/superpowers). Sources and licenses are
recorded in `claude/skills/ATTRIBUTION.md`.

Every skill here is one this setup actually uses. A skill that turned out to be redundant was
deleted rather than shipped disabled: if it is not worth loading, it is not worth carrying.
