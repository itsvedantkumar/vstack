# Reproductions

One script per confirmed defect. Each exits **1 while the defect is live** and **0 once it is
fixed**, so the fix has to be watched flipping it. They run the real `install.sh`, `uninstall.sh`,
`overlay.sh`, `bootstrap.sh` and hooks against a `mktemp -d` sandbox: `HOME`, `TMPDIR` and the
config dir are all reassigned, and none of them touch the operator's `~/.claude`.

These are not part of `.claude/verify.sh`. A repro answers "is this specific claim true today";
the gate answers "is the repo shippable", and it re-derives its own evidence. Keeping them apart
is deliberate: a repro that has been folded into the gate stops being a way to disagree with the
gate.

| Script | Defect | Status |
|---|---|---|
| `tests/repro/lifecycle.sh` | `uninstall.sh` could not return a machine to its pre-vstack state. Two causes: `install.sh` backed up its own payload so the next uninstall restored it, and `uninstall.sh` derived hook basenames from `claude/settings.json`, whose commands are quoted `$CLAUDE_PROJECT_DIR` strings, so both ownership branches were dead code. | fixed 1.46.0 |
| `tests/repro/overlay-ownership.sh` | `overlay.sh` deep-merges with `($dest * $ship)`, which replaces whole arrays. Every hook event vstack also populates loses the project's own entries, and `skillOverrides` is overwritten outright. | fixed 1.46.0 |
| `tests/repro/bootstrap-safety.sh` | `bootstrap.sh` checks `git status --porcelain` and nothing else, so a clean-but-ahead or diverged checkout is `reset --hard FETCH_HEAD` and the unpushed commit is dropped with no warning and no named ref. | fixed 1.46.0 |
| `tests/repro/stop-gate.sh` | The Stop gate stops blocking after 3 refusals and never re-arms for that session, even after a green run. The counter is a plain file at a path computable from the hook's own source, so one `echo 3 >` disables it on the first try. | fixed 1.46.0 |
| `tests/repro/trust-closure.sh` | `vstack trust` hashes `.claude/verify.sh` and the `*.sh` paths it names literally. The generated gate also runs `npm run typecheck`, `uv run pytest` and `cargo test`, none of which the hash covers. | fixed 1.46.0 |
| `tests/repro/formatter-config.sh` | `format.sh` fires on every `Edit`/`Write`/`MultiEdit`, and Prettier `require()`s any `.js` named in a static `.prettierrc.json` `plugins` array. Cloning a repo and editing one file ran that repo's JS, with the Stop gate's trust record never consulted. | fixed 1.46.0 |

| `tests/repro/compat-canary.sh` | Every hook parsed Claude Code's payload with `jq ... // empty` and no else branch, so a renamed field or an unrecognised `hook_event_name` degraded to the same silent exit 0 as nothing happening. No hook or `bin/doctor` checked the Claude version at all. | fixed 1.46.0 |
| `tests/repro/worktree-collision.sh` | Harness save/restore had no refusal on a changed file and the falsifiability lock is keyed on `git rev-parse --git-dir`, which differs per linked worktree, so two sessions each held a lock neither could see. | fixed 1.46.0 |
| `tests/repro/lock-anchor.sh` | The three remaining `--git-dir` lock anchors, red until they move to `--git-common-dir`. | open |

Run one directly. There are no arguments and no fixtures to prepare:

    bash tests/repro/lifecycle.sh; echo "rc=$?"
