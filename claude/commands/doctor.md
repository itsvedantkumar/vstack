---
description: Health-check the agent setup (hooks, subagents, secrets, wrappers, Codex glue, role card)
---
1. Check whether `~/.config/agents/bin/doctor` exists and is executable.
2. If it exists: run `~/.config/agents/bin/doctor --mcp` and report any ✖ drift with the one-line fix.
3. If it does not exist, state plainly in one line that the doctor helper is not installed and that it ships with the vstack repo's install.sh (github.com/itsvedantkumar/vstack), then run the checks that don't require it and report a compact pass/fail list:
   a. List `~/.claude/hooks` and confirm each hook file is present and executable.
   b. Count the subagents in `~/.claude/agents`.
   c. Count the skills in `~/.claude/skills`.
   d. Run `gh auth status` and report whether it's authenticated.
   e. Check whether `ANTHROPIC_API_KEY` is set in the environment — it should NOT be set, since a set key bills API credits instead of using the subscription; flag it as a failure if present.
