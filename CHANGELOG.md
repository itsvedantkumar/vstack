# Changelog

Versions follow [semver](https://semver.org). The version lives in two manifests,
`.claude-plugin/marketplace.json` and `claude/.claude-plugin/plugin.json`, and check 13 of
`.claude/verify.sh` fails when they disagree.

## 1.1.0 — 2026-08-20

An audit of the verification machinery, prompted by a simple question: does the gate that says
VERIFIED actually check anything? It largely did not. Every defect below has the same shape — a
check that reported success without having run — and each fix ships with the mutation that
proves the check now bites.

### The gate was not measuring what it reported

- Three checks were wrapped in a bare `if command -v jq` with no `else`. On a host without jq
  they printed nothing at all, so `VERIFIED` meant 8 of 13 checks had run. Added a toolchain
  preflight that fails rather than skips, `else` branches everywhere, and a
  declared/ran/skipped tally that fails when the three do not add up.
- Check 11 was labelled "both lanes" and read two of three. It never opened
  `claude/hooks/hooks.json`. Its user-lane test was `grep -q "$ev" install.sh`, which matches
  prose and lets `PostToolUse` match the `PostToolUseFailure` line — deleting the whole
  `PostToolUse` block still passed. Now reads all three lanes and anchors on the object key.
- Check 12 asserted a correct number appeared *somewhere*, for two nouns in two files. It
  could not see a wrong number beside a right one, so "15 commands" shipped against a tree of
  14. Now derives 7 counts from the tree and reads every claim back, in prose and table form,
  whitespace-normalised.
- Checks 4–6 were negative greps with `2>/dev/null`, so a grep that *errored* produced empty
  output and passed. They also scanned ignored files, which had the gate red over a `.context/`
  scratch note. Now scan `git ls-files` and read grep's exit status.

### The Stop gate did not always stop anything

- `verify-gate.sh` called `/usr/bin/jq` by absolute path — a macOS path. Everywhere else the
  block decision was never emitted, so a failing `verify.sh` let the agent finish while the
  gate looked installed. Same bug in `inject-session-context.sh` was worse: it emitted **zero
  bytes** off macOS, meaning skill routing was entirely dead on Linux.
- Trust covered `.claude/verify.sh` alone, while that script executes `install.sh` and
  `overlay.sh`. A byte-identical `verify.sh` passed with swapped scripts underneath. `vstack
  trust` now records the repo-root scripts and the gate re-checks all of them.
- The per-session block counter fell back to a literal `"nosess"`, putting every such session
  on one shared file — three failures anywhere latched the gate off machine-wide.

### doctor reported passes for things it never looked at

- The coverage check returned a tick when its cutoff date failed to compute and nothing was
  scanned at all.
- `[ -d "$r/.git" ]` is false inside a git worktree, so every Conductor workspace was invisible
  to a check whose job is finding uncovered repos. `overlay.sh` had the identical bug and
  refused to run in a worktree — the one place the cloud lane most needs it.
- `--drift` never compared `claude/CLAUDE.md`, the file `install.sh` itself calls most likely
  to have been hand-edited.
- `check_item` ignored `diff`'s exit status, so an unreadable directory read as clean.

### Config that looked like a control and was not

- Deleted 38 `skillOverrides` entries covering 19 `claude-mem` skills in two spellings. Claude
  Code resolves listing mode before reading the setting for plugin-supplied skills, so none of
  them ever had any effect. Check 15 now rejects any key containing `:` or `@`.
- `overlay.sh` copied all 27 settings keys into every repo it touched, including theme,
  notification channel, login method and plugin list — into the git history of anyone who
  cloned them. Now ships 10, listed in `claude/settings.project-keys`, and strips the rest from
  repos overlaid under the old behaviour.
- The Conductor setup pin was a hardcoded SHA that had drifted behind main, so new sandboxes
  bootstrapped an old vstack. Resolves HEAD at overlay time.

### Added

- `tests/gate-falsifiability.sh` — one row per check, breaking exactly what it watches and
  requiring the gate to go red naming it. Check 16 fails when a check has no row.
- CI now installs for real on Linux and fires the hooks, because the worst bug here was
  Linux-only and invisible on the machine it was written on.
- Two negative controls in `tests/auto-trigger.sh`, which previously could not detect a skill
  that fires on everything, plus a hit-rate table so erosion shows before a case goes red.
- Check 18 bounds what the session hook injects: 305 bytes per prompt, 3,446 at session start.
- `claude/verify.sh.tmpl`, seeded into overlaid repos that have no gate of their own.

### Changed

- `default_plan_mode` is now `false`. Installing `bypassPermissions` to stop approving tool
  calls and then blocking every session on approving a plan is the same interruption moved one
  level up.
- `tests/auto-trigger.sh` preflight exits 2 locally instead of 0. A run that tested nothing
  read exactly like a pass.
- `readme-writing` no longer accepts `unslop`, whose own description is "Must always apply" and
  which therefore made the case unable to fail.

### Measured

| | before | after |
|---|---|---|
| gate checks | 13, 3 of them silent without jq | 20, all falsifiable |
| doctor scan reach | 5 repos | 27 repos and worktrees |
| settings keys the overlay ships | 27 | 10 |
| routing suite | 9 cases, no negative controls | 11 cases, 11 passing |
| session token surface | unmeasured | 15,857 bytes, ~3,964 tokens |

## 1.0.0

First public release: 25 skills, 8 subagents, 14 commands, the SessionStart routing hook, the
Stop-hook verify gate, and the three install lanes.
