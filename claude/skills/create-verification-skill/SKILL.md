---
name: create-verification-skill
description: "Nothing exists yet: this repo has no scripted proof its UI, CLI or service works. Generates the executable .claude/verify.sh gate, a verify-<app> skill, and a feature map."
---

# Create a verification skill

Every serious project needs a scripted way to drive the real app and prove behavior: launch it, exercise a feature the way a user would, and capture evidence. This skill generates two coupled artifacts:

1. **`.claude/verify.sh`** — a fast, always-on gate wired to the `Stop` hook. It runs automatically every time an agent tries to finish in this repo and blocks it if the repo is broken. This is the piece that turns "I verified it" from a claim into a mechanism.
2. **`.claude/skills/verify-<app>/`** — the deep, human-and-agent-readable skill that drives the real app, plus a feature map.

`verify.sh` is the cheap gate that runs constantly; the skill is the expensive drive you invoke deliberately. Both, or neither is worth much: a gate with no drive only proves the code compiles, and a drive nothing invokes never runs.

You write the output for the next agent, not for a human: it will be read cold, mid-task, by an agent that has never seen the app.

## 1. Interview the repo, not the user

Answer these from the codebase and only ask the user what you cannot observe. **Fan this out — send all of these as multiple `Agent` tool calls in a single message** so they run concurrently, not one after another:

- **Surface:** what does a user actually touch? A web UI, a CLI/TUI, a desktop app, an API, a library? A repo can have several; pick the primary one and note the rest.
- **Run:** how does the app start locally? Prefer the repo's own documented dev command (package scripts, Makefile, README quickstart). Note ports, env vars, seed data, auth.
- **Check:** what already exists as a fast, non-interactive correctness check? `typecheck`, `lint`, `test`, `build` scripts in `package.json`; `cargo check`; `go vet`; `pytest`; a `Makefile` target. Record the exact invocation and whether it currently passes on a clean tree.
- **Drive:** how can an agent interact with the app programmatically? Existing harnesses first — Playwright/Cypress specs, expect scripts, PTY helpers, curl-able endpoints, a debug port. Only then a generic recipe: Playwright or the `claude-in-chrome` MCP for web and Electron, a tmux/PTY harness for CLI/TUI, plain `curl` for services.
- **Observe:** what evidence can be captured? Screenshots, terminal transcripts, response bodies, logs, exit codes, DB state.
- **Isolate:** can two instances run side by side (ports, data dirs, profiles)? If not, say so in the generated skill: refusing to double-drive a shared instance beats corrupting the user's session.

Use `subagent_type: "explorer"` for the read-only mapping questions and `"general-purpose"` for anything that must run a command. If the checkout doesn't build or start as-is, fix that first (or report it precisely) before generating; a skill written against a broken base teaches wrong steps. When an irrelevant missing asset blocks startup (a static dir the API never serves, a sample config), the generated skill may create it, clearly marked as verification scaffolding, and remove it in cleanup.

## 2. Generate `.claude/verify.sh` — the always-on gate

This is the highest-value artifact. A `Stop` hook at `~/.claude/hooks/verify-gate.sh` already exists and looks for exactly this path. It is a silent no-op unless the file is present **and executable**, so a `verify.sh` you forget to `chmod +x` is a `verify.sh` that does nothing.

**The contract, verbatim, and the constraints it forces:**

| Hook behavior | What `verify.sh` must therefore do |
|---|---|
| Runs `bash .claude/verify.sh` with cwd already set to the project root | Never `cd`. Use paths relative to the repo root. |
| Exit `0` lets the agent stop; non-zero **blocks** it | Exit non-zero if and only if a human would call the repo broken. |
| Combined stdout+stderr is fed back to the agent as the block reason | Print only what's needed to fix it. Truncate tool output; no full logs. |
| Fires on *every* stop, capped at 3 blocks per session | Stay fast (target under 90s) and deterministic. |
| No human is attached | Never read stdin, never prompt, never open an editor or a browser. |
| The agent will run it again immediately after fixing | Be idempotent and read-only: no fixtures left behind, no ports left bound. |

**The failure mode to design against:** a check that fails for a reason the agent cannot fix (a dev server that isn't running, a network flake, a missing global tool) burns all three blocks and then the gate silently stops mattering for the rest of the session. So: **a check whose prerequisite is absent must SKIP, not FAIL.**

Write the file, then `chmod +x .claude/verify.sh`. Use this shape, keeping the header comment intact and replacing the checks with the real ones you found in the Interview:

```bash
#!/usr/bin/env bash
# .claude/verify.sh — contract with the Stop hook (~/.claude/hooks/verify-gate.sh)
#
#   The hook runs this file with cwd = project root every time the agent tries to finish.
#     exit 0   -> the agent may stop.
#     exit !=0 -> the agent is BLOCKED and this script's stdout+stderr is handed back
#                 to it verbatim as the reason to fix. Capped at 3 blocks per session.
#
#   Therefore this file MUST:
#     - never cd (the hook already runs it from the project root)
#     - never read stdin, prompt, or require anything interactive
#     - be safe to run repeatedly and concurrently: read-only, no leftover state
#     - stay fast (target < 90s) — it runs on every single turn-end
#     - print only what the agent needs in order to fix it, not full tool logs
#     - SKIP (not fail) any check whose prerequisite is missing; an unfixable
#       failure just burns the 3-block budget and disables the gate for the session
#
#   Deep behavioral verification lives in .claude/skills/verify-<app>/, not here.

set -uo pipefail   # deliberately NOT -e: report every failing check, not just the first
FAILED=0
TAIL="${VERIFY_TAIL:-25}"

run() {  # run <label> <command...>
  local label="$1"; shift
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "skip $label ($1 not installed)"
    return 0
  fi
  local out rc
  out=$("$@" 2>&1); rc=$?
  if [ "$rc" -ne 0 ]; then
    FAILED=1
    echo "FAIL $label (exit $rc)"
    printf '%s\n' "$out" | tail -n "$TAIL"
    echo
  else
    echo "ok   $label"
  fi
}

has_script() { [ -f package.json ] && node -e "process.exit(require('./package.json').scripts?.['$1']?0:1)" 2>/dev/null; }

RAN=0
run_if() { # <label> <cmd...>  -- counts what actually executed
  RAN=$((RAN+1)); run "$@"
}

# --- Static gate: replace with the exact checks found in this repo ------------
# This template is npm-shaped. In a Go, Rust, Python or Makefile repo every has_script is false,
# every line prints "skip", and the script exits 0 having verified nothing -- a gate that cannot
# fail is not a gate. Replace these three lines with the repo's real commands (go vet ./... &&
# go test ./..., cargo clippy, pytest, make check). The RAN counter below is the backstop: it
# refuses to report success until at least one check has actually run.
has_script typecheck && run_if typecheck npm run --silent typecheck || echo "skip typecheck (no script)"
has_script lint      && run_if lint      npm run --silent lint      || echo "skip lint (no script)"
has_script test      && run_if test      npm run --silent test      || echo "skip test (no script)"

# --- Optional smoke: only if the app is ALREADY up. Never start a server here;
# --- the hook has no way to reap it and a stray process poisons the next run.
if curl -fsS -m 2 http://127.0.0.1:3000/api/health >/dev/null 2>&1; then
  run smoke bash .claude/verify-smoke.sh
else
  echo "skip smoke (nothing serving :3000)"
fi

if [ "$RAN" -eq 0 ]; then
  echo "Blocked by .claude/verify.sh: every check skipped, so nothing was verified."
  echo "This gate is still the npm-shaped template. Point it at this repo's real commands."
  exit 1
fi

if [ "$FAILED" -ne 0 ]; then
  echo "Blocked by .claude/verify.sh. Fix the FAIL lines above."
  echo "For behavior (not just compilation), drive the feature with the verify-<app> skill."
  exit 1
fi
exit 0
```

Rules for what goes in:

- **Only checks you personally ran and saw pass on a clean tree.** A gate that is red on arrival teaches the agent that red is normal, and it will start working around it.
- **No check that needs a server the agent didn't start**, no check that needs the network, no check that needs credentials. Those belong in the skill's live drive.
- If the repo has no fast checks at all, say so out loud rather than shipping a `verify.sh` that skips everything. **An all-skip gate is indistinguishable from no gate** — it exits 0 forever. Either add the missing script or tell the user what's missing and why the gate is currently thin.
- Prove it by hand both ways before you hand it over: run it on a clean tree (must exit 0), then introduce one deliberate breakage (a type error), re-run, confirm it exits non-zero and the message alone is enough to locate the fault, and revert.

## 3. Generate the verification skill

Write `.claude/skills/verify-<app>/SKILL.md` with YAML frontmatter (`name: verify-<app>` and a `description` that names the app, the surface, and the situation you'd reach for it in — without frontmatter the skill never registers; a description that only lists slash forms never fires) and these sections, each grounded in what the interview actually found (no placeholders left):

- **Launch:** the exact command that starts the app for verification, and how to tell it's ready (a log line, a port answering, a prompt). Include teardown. For a short-lived CLI or TUI there is no server to keep alive: launch means build the binary (or install deps) once, then start each drive in its own isolated PTY or tmux session.
- **Doctor:** one read-only check that answers "is this instance worth driving?" — process up, right version/build, port owned by us, auth valid. An agent runs this first whenever anything looks off.
- **Drive:** the harness recipe with real selectors/commands from this repo, not examples. Prefer stable handles (ARIA labels, data attributes, prompt strings, route paths) over coordinates and tab order.
- **Evidence:** what to capture for a proof and where it goes. State the proof standards: exercise the real user path, not internal setters or test-only endpoints; capture the action and the resulting state, not just the final screen; verify side effects (files written, rows inserted, messages sent) alongside what's visible; mocks only where a production boundary already isolates the external system. When the safe path is a dry-run or test mode, verify what it actually skips by observing (files, network, git refs) rather than trusting its name: some dry-runs still touch the network or open a browser.
- **Cleanup:** how to tear down instances the run created. Never kill by process name; kill what you started. Cleanup removes instances and scratch state, never the evidence: proof artifacts survive the teardown, in a location the skill names.
- **Helpers:** any script the skill ships is executable and its invocation is shown in the skill body. A helper the reader has to reverse-engineer is not a helper.
- **Relationship to the gate:** one line naming which checks `.claude/verify.sh` already covers, so a live drive doesn't waste a run re-proving the typechecker.

## 4. Seed the feature map

Create `.claude/skills/verify-<app>/features/README.md` plus one file per user-facing feature you can identify (aim for the top 3-5 to start, from routes, commands, menus, or docs). Follow the shape in [`references/feature-map-example/`](references/feature-map-example/), with a README index and one file per feature. Each file answers, from the user's point of view: what the feature is, how to reach it, how to drive it with the harness, and what observable end state proves it works. The four H2s are `Sub-features`, `How to get to it (user POV)`, `Driving it with <harness>`, and `Gotchas`. The map is the repo's maintained verification source; a proof that drives one convenient entry point is incomplete when the map lists others.

## 5. Prove the deliverables before handing them over

Run the generated skill's own instructions end to end once: launch, doctor, drive ONE mapped feature (one is enough; the map exists so later runs can cover the rest), capture evidence, clean up. After cleanup, confirm the evidence still exists at the named location — a cleanup that eats the proof fails this step. Fix what fails, and run the generated cleanup after every failed iteration too, so broken attempts don't strand processes and ports.

Then confirm the gate is actually armed:

```
test -x .claude/verify.sh && bash .claude/verify.sh; echo "exit=$?"
```

`test -x` failing means the hook will silently ignore your work. A generated skill that was never executed is a draft, not a deliverable; an unarmed `verify.sh` is not a deliverable at all.

## 6. Hand off the maintenance loop

Tell the user that `maintain-verification-skill` keeps both the feature map and `verify.sh` honest as the app changes, and that it is worth running after any release or any week of heavy feature churn. Suggest a cadence only if they ask.
