# How config reaches a session, measured

This doc records what a Claude Code session on this machine actually loads, established by experiment on 2026-09-01, not by reading docs. It also defines the coverage classes `bin/doctor` reports and the lane decisions behind them.

## The experiment

Setup: a scratch repo under `mktemp -d "${TMPDIR:-/tmp}/vstack-prec.XXXXXX"` with three planted markers, run against the real `~/.claude` with `claude -p --model claude-haiku-4-5`. An isolated `CLAUDE_CONFIG_DIR` was tried first and failed auth (`loggedIn: false`; Keychain and onboarding state do not follow the config dir), so the runs observe the real user scope. Each answer below names its artifact. Hook evidence is read from files hooks wrote and from the session transcript JSONL, not from model output. Memory-file evidence needs the model to echo markers, because the transcript never embeds CLAUDE.md contents; that is the one probe that runs through the model.

Scratch layout:

- root `CLAUDE.md` containing `PREC-ROOT-MEM`
- `.claude/CLAUDE.md` containing `PREC-PROJ-MEM`
- `.claude/settings.json` with a `UserPromptSubmit` hook that appends `project` to a log file
- a second repo adds `"disableAllHooks": true` to `.claude/settings.json`

### Q1: which memory files load?

All three. The marker-echo probe returned `PREC-ROOT-MEM, PREC-PROJ-MEM`, and a follow-up run confirmed the global file's opening phrase ("NEVER ASK. ACT.") is in context too. So a session loads `~/.claude/CLAUDE.md`, the repo root `CLAUDE.md`, and `.claude/CLAUDE.md` together, additively. No file replaces another. Which instruction wins on conflict is a prose question the model arbitrates; there is no mechanical override.

Consequence for vstack: `overlay.sh` deletes `.claude/CLAUDE.md` from targets (overlay.sh lines 112-115) because the file does load, and loading the policy text twice under two paths doubles its token cost without adding authority.

### Q2: do repo hooks shadow global hooks?

No. They merge. One prompt in the scratch repo produced both the project hook's `project` line in the log file and the global `inject-session-context.sh` digest (`OPERATING MODE ... SESSION BASELINE`) in the transcript. Every hook registered for an event runs, across user and project scope.

Consequence: the overlaid repos whose project `settings.json` lists fewer commands per event than `~/.claude/settings.json` (no `compat-canary.sh`, no `goal-gate.sh`, no `Agent|Task` matcher for `dispatch-counter.sh`) lose nothing. The global commands still run. Before this experiment that was an open question; a shadow answer would have meant every overlaid repo silently dropped dispatch counting.

### Q3: can a repo turn the global stack off?

Yes, completely. With `"disableAllHooks": true` in the scratch repo's `.claude/settings.json`, the project hook did not write its log line and the global digest vanished from the transcript. One committed line in any repo silences all nine global hooks, the verify gate included.

Consequence: "my session does not use vstack" has a one-line cause that no amount of global installation fixes. `bin/doctor` now flags any active repo whose `.claude/settings.json` or `.claude/settings.local.json` sets `disableAllHooks` (none did at the time of the audit).

### Q4: is the anti-delegation experiment paragraph cached here?

Yes. `~/.claude.json` holds three `clientDataCacheSlots` entries under `experimentKey: claude_code_opus5_efficiency_paragraph_experiment`, all scoped to `claude-opus-5` (the `claude-fable-5` and `claude-haiku-4-5` slots carry no paragraph). The cached text opens with "Do not call the AgentTool unless the user requested it" and "Do not use workflows or deep-research unless the user requested it". Conductor's managed settings pin `default = "opus-5"` (`conductor/settings.managed.toml`), so Conductor sessions run the one model that receives the paragraph. The key is absent from the 2026-08-10 backup of `.claude.json`, so enrollment happened after that date.

### Q5: does the global CLAUDE.md neutralize it?

Unknown, and not mechanically verifiable. The global file asserts "this file wins" over the cached paragraph; both are prose fed to the same model, and Q1 showed there is no mechanical precedence between prose sources. The honest statement is: claim unverified, behavior instrumented. The `PostToolUse` `Agent|Task` hook (`dispatch-counter.sh`) counts real dispatches per session, so whether opus-5 sessions delegate less than fable-5 sessions is a question the counter data can answer later. Do not cite the CLAUDE.md sentence as if it were a mechanism.

## Coverage classes

Three lanes carry vstack to a session, and they differ by what they can reach:

1. **Global (`~/.claude`)** reaches every local session in every repo and worktree, because hooks are wired by absolute path and memory loads from the user scope. `install.sh` owns this lane. Sufficient for all local work.
2. **Committed overlay (`.claude/` in the repo)** is the only lane that reaches a cloud sandbox, which has no `~/.claude`. `overlay.sh` owns it. It must be committed to matter: Conductor reads the repo-shared `.conductor/settings.toml` from the remote default branch, so an untracked overlay is invisible at workspace creation.
3. **Conductor setup script (`.conductor/settings.toml`)** curls `bootstrap.sh` at a pinned vstack SHA. Written once by `overlay.sh`; as of this change, re-running `overlay.sh` bumps a stale pin instead of keeping it forever.

`bin/doctor` ("project coverage" section) classifies every active repo (a commit in the last 45 days) into:

- **cloud-ready**: overlay artifacts complete (`.claude/hooks/policy.md` plus every hook in `claude/inventory.json`), `.conductor/settings.toml` present, pin equal to the vstack HEAD, `trust --yes` in the setup line.
- **half-covered**: `.conductor/settings.toml` without the overlay artifacts, or the artifacts without the toml. The old check called this covered; it is not, and that false green is why this doc exists.
- **stale**: artifacts complete but the pin is old or malformed, `trust --yes` is missing, or a Finder-duplicate `settings 2.toml` sits beside the real file.
- **local-only**: no overlay at all. Served fully by the global lane for local work; named by doctor so you run `overlay.sh` before dispatching that repo to a sandbox.
- **hooks-disabled**: `disableAllHooks` set repo-locally (Q3). Always a failure.

`local-only` is not a defect. The audit that motivated this work found 9 of 14 active repos local-only and all 9 fully functional, because the global lane covers them. The defect was doctor equating "has a `.conductor/settings.toml`" with "covered".

## Lane decisions

- `overlay.sh` stays one-target. An `--all` sweep would duplicate doctor's root list (two lists to drift apart) and would write into repos without an explicit ask, and every overlay still needs a human commit before it reaches a sandbox. Doctor names the exact repos and the exact command; that is the enumeration.
- No `conductor/` template change ships. The managed and user layers already work; the per-repo artifact is what drifts, and the fix is doctor forcing the commit.
- Gitignored files a workspace needs (for example an untracked `.claude/verify.sh`) can ride Conductor's copy lane via a `.worktreeinclude` file at the repo root. No repo uses it today; the generated `.conductor/settings.toml` mentions it.
