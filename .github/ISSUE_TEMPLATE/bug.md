---
name: Something is broken
about: An install, hook, gate, or overlay problem
labels: bug
---

**What you ran, and what happened**

**Output of `./.claude/verify.sh`**
Include the whole run. The `checks: N declared, N ran, N skipped` line matters — a skipped
check means a missing tool, not a pass.

**Output of `bin/doctor` and `bin/doctor --drift`**

**OS and versions**
`sw_vers` or `uname -a`, `claude --version`, `jq --version`.

**If a gate passed when it should have failed**
That is the most serious class of bug here. Say which check, and what you changed that it
should have caught — `tests/gate-falsifiability.sh` is where the proof for each check lives.
