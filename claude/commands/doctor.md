---
description: Health-check the agent setup (hooks, subagents, secrets, wrappers, role card)
---
vstack ships two install lanes, and each one puts the payload somewhere different. Detect which
lane actually landed before checking anything — do not assume the full-install layout.

1. **Full install.** Check whether `~/.config/agents/bin/doctor` exists and is executable.
   If it exists: run `~/.config/agents/bin/doctor --mcp` and report any ✖ drift with the
   one-line fix. Stop here.

2. **Plugin-marketplace install.** `~/.config/agents/bin/doctor` only ships via `install.sh`,
   so its absence means nothing yet — a `claude plugin install vstack@vstack` setup never
   creates it and is still a working install. Look for the plugin payload instead:
   a. Glob `~/.claude/plugins/cache/vstack/vstack/*/` — one directory per installed version.
      If more than one matches, use the most recently modified (`ls -dt`); do not hardcode a
      version number, since it changes every release. Call the winner `$PLUGIN_ROOT`.
   b. If `$PLUGIN_ROOT/skills` exists, the plugin lane is live. Report:
      - Count skills in `$PLUGIN_ROOT/skills` (directories), agents in `$PLUGIN_ROOT/agents`
        (`*.md`), commands in `$PLUGIN_ROOT/commands` (`*.md`).
      - State plainly that hooks, CLI wrappers, and MCP servers are **not part of this lane by
        design** — the plugin manifest declares no `mcpServers`, and hooks/wrappers/the shell
        lane only land via the full install (`git clone` + `./install.sh`). This is not a
        failure of the plugin install; do not report it as drift.
      - Run `gh auth status` and report whether it's authenticated.
      - Check whether `ANTHROPIC_API_KEY` is set in the environment — it should NOT be set,
        since a set key bills API credits instead of using the subscription; flag it as a
        failure if present.
   c. If `$PLUGIN_ROOT/skills` does not exist (the glob in 2a matched nothing), fall through to
      step 3.

3. **No install found.** Only reached if both `~/.config/agents/bin/doctor` is absent *and* no
   `~/.claude/plugins/cache/vstack/vstack/*/skills` directory exists. State plainly: no vstack
   install was found, and give both install commands from the README (the plugin lane —
   `claude plugin marketplace add itsvedantkumar/vstack` then `claude plugin install
   vstack@vstack` — and the full install — `git clone https://github.com/itsvedantkumar/vstack`
   then `./install.sh`). Do not run the checks below against paths that were never populated;
   an empty count from a directory that was never installed is not a health signal, it is noise.
