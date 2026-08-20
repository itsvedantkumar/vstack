---
description: Scaffold founder-grade Claude Code + Conductor config into the current repo (idempotent)
---
Overlay vstack into this repo, then tailor what the overlay leaves generic.

1. Find the vstack checkout: read `~/.config/agents/vstack-repo`, which `install.sh` writes with
   the path. If that file is missing, vstack was never installed on this machine — say so and
   stop rather than guessing a path.
2. Run `"$(cat ~/.config/agents/vstack-repo)/overlay.sh" "$PWD"`. It is idempotent: it merges the
   allowlisted project keys into `.claude/settings.json`, copies hooks, agents, commands and
   skills, seeds `.claude/verify.sh` from the template only when absent, writes
   `.conductor/settings.toml` pinned to the overlaid commit, and excludes `.context/`. It never
   overwrites a file the repo already owns.
3. Detect the stack and fill in what the overlay writes as placeholders. Read the lockfile or
   manifest — `pnpm-lock.yaml`, `yarn.lock`, `bun.lockb`, `package-lock.json`, `pyproject.toml`,
   `requirements.txt`, `go.mod`, `Cargo.toml` — and derive the install, dev, test, lint and build
   commands from it.
   - In `.conductor/settings.toml`, replace the `[scripts.run.dev]` command with this repo's real
     dev runner bound to `$CONDUCTOR_PORT` (Vite needs `npm run dev -- --port $CONDUCTOR_PORT`).
     Delete that block for a repo with no frontend. Append this repo's install step to `setup`.
   - In `.claude/verify.sh`, keep only the branches that match this stack.
   - Reference only scripts that actually exist. A `package.json` without a `lint` script must not
     get a `lint` line, or the verify gate blocks every Stop on a command that cannot run.
4. Write a `CLAUDE.md` at the repo root if none exists: what the project is, the stack, the real
   commands, and the conventions a new agent would otherwise get wrong. Keep it short — it loads
   into every session in this repo. Never overwrite an existing one; show what you would add and
   let the human merge it.
5. Report what changed, then show the resulting `CLAUDE.md` and `.conductor/settings.toml` and
   point out every `# TODO` placeholder still to fill.

The gate stays inert until it is armed: `.claude/verify.sh` does not run on Stop until someone
runs `vstack trust` in this repo, by content hash. Tell the human that, and tell them it needs
re-arming after they edit the file.
