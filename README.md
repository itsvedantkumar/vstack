# conductor-setup

Single source of truth for the Claude Code setup — local terminal, Conductor, Remote Control,
and cloud/phone dispatch.

## The three config lanes

Claude Code loads settings from `policy > flag > local > project > user`. Those sources do
**not** reach the same places, which is the whole reason this repo exists:

| Lane | Local terminal | Conductor | Remote Control | Cloud session / routine (phone) |
|---|:--:|:--:|:--:|:--:|
| `~/.claude/**` (user scope) | ✅ | ✅ | ✅ *(runs on your Mac)* | ❌ sandbox has no `~/.claude` |
| `~/.zshenv` exports | ✅ | ✅ | ✅ | ❌ |
| `shell/claude-parity.zsh` wrapper | ✅ | n/a | ❌ never goes through your zsh | ❌ |
| **committed `.claude/` overlay** | ✅ | ✅ | ✅ | ✅ **only lane that reaches cloud** |

So: `install.sh` for your machine, `overlay.sh` for every repo you dispatch work to.

## Usage

```bash
./install.sh                 # materialise user scope (~/.claude, ~/.config/agents, shell)
./overlay.sh ~/path/to/repo  # commit-able .claude/ overlay so cloud/phone runs match local
~/.config/agents/bin/doctor  # drift check (also runs nightly via doctor-cron.sh)
```

## What lives where, and why

**`claude/settings.json` — portable subset.** Model/effort/fastMode, the skill-listing caps,
`skillOverrides`, latency flags, and the allowlisted `env` block. Hook commands use
`$CLAUDE_PROJECT_DIR`-relative paths so they resolve inside a cloud sandbox; an absolute
`/Users/...` path there fails with exit 127 on every hook event.

**Deliberately NOT in the committed overlay** (user scope only): `forceLoginMethod`,
`remote.defaultEnvironmentId`, `remoteControlAtStartup`, `preferredNotifChannel`,
`statusLine` (no TTY in a sandbox), `enabledPlugins` (points at local marketplace caches),
and `permissions.defaultMode` (never put `bypassPermissions` in a repo others can clone).

**`shell/zshenv.snippet`** — env vars that are *not* in Claude Code's `settings.json` `env`
allowlist and therefore only work as real environment variables. Putting them in
`settings.json` is silently ignored.

> ⚠️ Do not set `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` or `DISABLE_GROWTHBOOK`. Both gate
> feature-flag evaluation, which **Remote Control requires** — `claude doctor` reports
> "Remote Control rollout could not be verified" and phone dispatch stops working.

**`shell/claude-parity.zsh`** — only the launch flags with no settings key (`--chrome`,
`--plugin-dir <conductor-skill>`, `--exclude-dynamic-system-prompt-sections`) plus stripping
`ANTHROPIC_API_KEY`/`ANTHROPIC_AUTH_TOKEN` so auth always resolves to the Max subscription.
Passthrough for `-p`, subcommands, and `--remote-control|--cloud|--bg`.

## Secrets

Never in this repo, never in `~/.zshrc`. They live in `~/.config/agents/secrets.env`
(mode 600, sourced from `~/.zshenv`). The key named `ANTHROPIC_API_KEY` must **not** exist in
any sourced file — `claude`, `codex`, and OpenCode all auto-consume that name and would bill
pay-per-token API credits instead of the subscription. Store it as `ANTHROPIC_SDK_API_KEY`
and opt in per-command.
