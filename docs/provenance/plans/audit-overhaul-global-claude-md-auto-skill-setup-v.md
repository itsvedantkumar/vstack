# Audit & overhaul: global CLAUDE.md + auto-skill setup (vstack)

## Context

Audit of the global Claude Code config found the setup is structurally sound (vstack → install.sh → ~/.claude, skills measurably auto-fire, verify gate armed) but carries real defects:

1. **Two always-loaded CLAUDE.md files contradict each other.** `~/.claude/CLAUDE.md` (vendored): "maximally concise, no preamble, end with **Next:**". `~/CLAUDE.md` (home dir, ancestor of every project, NOT vendored): "keep output short by being selective, not by compressing into fragments", "polish beyond the ask is welcome", plus a `/goal create/rb/status/verify/close` spec that contradicts the actual `commands/goal.md`. The agent hits this conflict every single turn.
2. **The SKILLS routing block is 100% hand-written prose** in `claude/hooks/inject-session-context.sh` (heredoc, lines 20–36). Nothing generates it from `skills/*/SKILL.md` frontmatter; it omits 4 skills (brainstorming, writing-plans, TDD, executing-plans); verify.sh never cross-checks it against the skills dir. It also mostly duplicates what the native skill listing already shows — the 22 frontmatter descriptions are already situation-triggers.
3. **The hook block claims "ACTIVE EVERY RESPONSE" but fires at SessionStart only** — injected once, decays out of attention in long sessions.
4. Assorted rot: 7 dead `skillOverrides` in live `~/.claude/settings.json` (kept alive forever because install.sh's jq deep-merge never deletes keys), `fastMode:true` + `effortLevel:high` + `opus-5[1m]` set together, verify-gate 3-block cap resets instead of latching (blocks in groups of 3 forever), verify.sh section numbering skips 3 and 7, `overlay.sh` never ships CLAUDE.md/statusline.sh to the cloud lane, stale install.sh comment, `~/.claude/.disabled/` junk, dead `settings.local.json`, half-removed cloudflare marketplace.
5. **Uncommitted work in vstack**: `bin/doctor` (modified), `bin/vstack`, `tests/auto-trigger.sh` (a headless regression test proving skills fire — becomes our go/no-go gate). Fresh bootstrap from GitHub misses these.

All edits happen in `~/Projects/vstack` (canonical source), then `./install.sh`. Never edit `~/.claude` directly.

## Design decisions

**A. One global CLAUDE.md.** Merge into vendored `claude/CLAUDE.md` (~12 lines, terse style wins — it's deliberate); delete `~/CLAUDE.md` (nothing in it survives on merit: duplicates, contradictions, and a /goal spec that doesn't match reality). Chain logic (`brainstorming → writing-plans → TDD → executing-plans → prove-it-works`) lives ONLY here — CLAUDE.md is in context every turn; hook text decays. Drop the `/loop` subcommand advertisement (documented nowhere). Add a `bin/doctor` check warning if `~/CLAUDE.md` reappears.

**B. Slim the SKILLS routing block to meta-rules only; don't generate it.** The per-skill lines duplicate the native skill listing (frontmatter descriptions are already situation-triggers, budget knobs guarantee they're listed). A generator would reproduce an existing machine's output. Keep ~3 lines: "skills fire on the SITUATION — call the Skill tool, don't reconstruct from memory, don't wait to be asked." Add a verify.sh check: every skill name referenced in CLAUDE.md/hook prose must exist as `claude/skills/<name>/` — zero maintenance, fails loudly on drift. Safety gate: `tests/auto-trigger.sh` before (baseline) and after; if firing regresses, restore the per-skill lines.

**C. Cadence hybrid.** Full block at SessionStart (header fixed to "SESSION BASELINE" — drop the false claim) + a 2-line digest (~40 tokens) on UserPromptSubmit from the same script (it already branches on `hook_event_name`): tokens/delegation/act-don't-ask. Fixes the decay without ~350 tokens/turn. Wire in both lanes: `claude/settings.json` AND install.sh's jq hook-rebuild. Do NOT attach notify.sh to UserPromptSubmit.

## Steps (each ends verified)

1. **Commit pending work**: `bin/doctor`, `bin/vstack`, `tests/`. Verify: `.claude/verify.sh` → VERIFIED, push, `git log origin/main..HEAD` empty.
2. **verify.sh hygiene**: renumber sections contiguously; add referenced-skills existence check (decision B). Run `tests/auto-trigger.sh` once to record pre-change baseline. Commit.
3. **verify-gate latch fix** (`claude/hooks/verify-gate.sh:12-15`): at cap, exit 0 WITHOUT deleting the counter file (latch open); delete only on the success path (re-arms after a real pass). Verify by shell simulation: failing verify.sh × 5 stops → exactly 3 blocks then silence. Commit.
4. **Settings cleanup + merge semantics root-cause fix** (`claude/settings.json`, `install.sh:140-159`): drop `fastMode:true`; make jq merge authoritative for `skillOverrides` (`.skillOverrides = ($portable.skillOverrides // {})` — purges the 7 dead entries) and `del(.fastMode)`; fix stale comment (install.sh:123-125). Verify: verify.sh section 8b, `./install.sh --dry-run`, real install, `jq '.skillOverrides|keys' ~/.claude/settings.json` clean. Commit.
5. **Hook overhaul** (`claude/hooks/inject-session-context.sh`, `claude/settings.json`, `install.sh`): slim SKILLS heredoc per B; fix header; UserPromptSubmit branch emits 2-line digest (no git work — must stay fast); add UserPromptSubmit hook entry in both lanes. Verify: `bash -n`, pipe both event JSONs through the script, verify.sh, install, **`tests/auto-trigger.sh` go/no-go vs step-2 baseline** (regression ⇒ restore per-skill lines). Commit.
6. **CLAUDE.md consolidation** (`claude/CLAUDE.md` rewrite per A; `claude/commands/goal.md`: replace "stuck >3 min → ask" with "document blocker, continue, flag in report"; `bin/doctor` reappearance check; then `rm ~/CLAUDE.md`). Verify: verify.sh (skill-reference check now guards the chain line), install, `diff ~/.claude/CLAUDE.md claude/CLAUDE.md` empty, smoke `claude -p` shows no contradiction. Commit.
7. **overlay.sh cloud-lane parity**: copy `CLAUDE.md` + `statusline.sh` into target repo's `.claude/`. Verify: overlay into a scratch `git init` dir, assert files present, `claude --setting-sources=project,local -p` smoke. Commit.
8. **Live-home cleanup + fresh-clone proof**: tar+remove `~/.claude/.disabled/`, remove dead `~/.claude/settings.local.json`, purge half-removed cloudflare marketplace entry; `git clone` vstack to /tmp, `./install.sh --dry-run` completes; final interactive smoke (SessionStart block once, per-prompt digest, one natural-language skill trigger fires).

## Risk flags
- **Don't touch the `env` block** in `claude/settings.json` or `.zshenv`/MCP wiring — 2 env vars there can break Remote Control (memory: claude-config-lanes).
- Step 5 is the only behaviorally risky unit — isolated, baselined, explicit revert path.
- install.sh backs up every overwritten file to `~/.config/agents/backups/install-<ts>/`; all real installs reversible.

## Critical files
- `~/Projects/vstack/claude/hooks/inject-session-context.sh`
- `~/Projects/vstack/claude/CLAUDE.md` (+ delete `~/CLAUDE.md`)
- `~/Projects/vstack/install.sh`
- `~/Projects/vstack/.claude/verify.sh`
- `~/Projects/vstack/claude/settings.json`
- `~/Projects/vstack/claude/hooks/verify-gate.sh`, `overlay.sh`, `claude/commands/goal.md`, `bin/doctor`
