# Finish the vstack goal: Phases 3–4, conductor-setup merge, handoff

## Context

A prior `/goal` session hardened vstack (Phases 1–2: 20 falsifiable gate checks, overlay leak fixed, doctor reach 5→27, routing 11/11) but ran out of budget before Phase 3 (research alternatives) and Phase 4 (public repo). The user wants absolutely everything finished, this conductor-setup repo's unique value merged into vstack, and a handoff prompt to re-initialize Conductor on vstack.

**Ground truth corrections from exploration (the transcript is stale):**
- Phase 4 is ~80% done in `~/Projects/vstack` (`27330ca "Ship 1.1.0"`): README (317 ln, Diátaxis, lanes table, honest limitations), Linux-container `install.sh` CI smoke job, `v1.1.0` tag pushed, CHANGELOG, LICENSE/ATTRIBUTION, issue templates. CI green (8/8 runs).
- The "5 repos carry no overlay" red check was produced by the pre-`55b6bbd` doctor (judged per-worktree). All 5 projects have the overlay at their main checkout; `bin/doctor` is now **ALL GREEN**. Do NOT run overlay.sh on them.
- `github.com/itsvedantkumar/conductor-setup` is **already archived** (private) — but its default branch `main` is near-empty, the 69-file branch `optimize-conductor-claude-setup` is unmerged, and there's no README pointer to vstack.
- vstack has **4 uncommitted files** (in-flight Phase 3/4 work): `.claude/verify.sh` (new check 19: `claude plugin validate --strict`), `tests/gate-falsifiability.sh` (registers 19), `claude/skills/agent-browser/SKILL.md` + `claude/skills/ui-iterate/SKILL.md` (agent-browser pixel-diff adoptions).
- `vstack update` (`bin/vstack:66`) still trusts-on-pull (U13, documented limitation at README:284-288). **Zero cron/launchd callers exist**, so the fix is now cheap.
- Installed-state drift: `~/.config/agents/bin/doctor` is stale (predates `55b6bbd`) — install.sh hasn't been re-run.
- `latestRelease: null` — the v1.1.0 tag has no GitHub Release object.

All work happens in `~/Projects/vstack` (canonical). This workspace's only irreplaceable content is **untracked** `.context/` research that dies when the conductor-setup project is deleted — salvage it first.

## Step 1 — Salvage conductor-setup's unique content into vstack (FIRST — untracked files don't survive project deletion)

Copy from `~/conductor/workspaces/conductor-setup/kabul` into vstack as **tracked** files under `docs/provenance/`:

- `.context/pstack-audit.md` → `docs/provenance/pstack-audit.md` — the 44-skill Fit/Benefit scoring (6,334 observations) that justifies the 18 vendored skills.
- `.context/plans/*.md` (9 files, ~1,500 ln) → `docs/provenance/plans/` — includes the harden-vstack plan (G1–G7 defects), the two bare-metal Conductor-parity analyses, and the 3 phone/Remote-Control dispatch plans (only record of that lane's design).
- `.goal/conductor-e2e-audit/goal.md` → `docs/provenance/conductor-e2e-audit.md` — R1–R8 rubric + 3 open residuals.
- Diff kabul `README.md` against vstack README; port any missing rows: the `ANTHROPIC_API_KEY`→`ANTHROPIC_SDK_API_KEY` billing rule, `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`/`DISABLE_GROWTHBOOK` breaking Remote Control, the "deliberately NOT overlaid" key list.
- **Skip** `claude/commands/orchestrate.md` — vstack removed it deliberately (`eb22605`; swarm skill covers it).
- verify.sh check 12 enforces documented counts — confirm new docs don't introduce unregistered count claims.

Commit in vstack; verify.sh must stay green.

## Step 2 — Commit vstack's in-flight work

- Commit the 4 dirty files (check 19 + falsifiability registration; agent-browser/ui-iterate skill upgrades). Run `.claude/verify.sh` + `tests/gate-falsifiability.sh` first; fix if red.
- Add CHANGELOG entries for the agent-browser adoption + check 19. No new skill was vendored, so no auto-trigger case is owed.

## Step 3 — Phase 3: research alternatives (parallel web agents)

Per the plan in `docs/provenance/plans/harden-vstack-*.md`:
- Fan out parallel WebSearch research agents across 4 areas: (a) Claude Code skill packs / plugin marketplaces, (b) vibecoding & design tooling (component registries, visual regression, screenshot loops, design-review agents), (c) Conductor features, (d) hook/gate patterns.
- Adoption bar per candidate: names a specific capability vstack lacks; verified real by reading issues/code, not README claims (ruflo lesson); worth the tokens; no login required.
- Adopt only by vendoring with license + attribution (ATTRIBUTION.md conventions), description ≤200 chars and situation-formed, **one new `tests/auto-trigger.sh` case per vendored skill**, verify.sh green.
- Write the survey outcome — adoptions AND rejections with reasons — to `docs/provenance/research-2026-08.md`, so Phase 3 is auditable even if zero candidates clear the bar (likely: the window since 2026-08-19 is a day; the agent-browser adoptions in Step 2 are already Phase 3 output).

## Step 4 — Phase 4: close the remaining gaps

1. **`vstack update` trust-on-pull (U13)** — now cheap (zero cron callers): make `update` show the incoming diff for trusted scripts and require confirmation, with `--yes` to skip; then update the README limitation paragraph (it currently documents trust-on-pull as open) and any check-12-enforced claims.
2. **GitHub Release** — if Phase 3 landed adoptions: bump to v1.2.0 (changelog, tag, `gh release create`); otherwise `gh release create v1.1.0` from the existing tag + CHANGELOG.
3. **Marketplace stranger-install** — check 19 (committed in Step 2) mechanises `claude plugin validate --strict`; additionally smoke it once from a fresh temp clone.
4. **conductor-setup archive pointer** — `gh repo unarchive itsvedantkumar/conductor-setup --yes` → merge `optimize-conductor-claude-setup` into `main` (preserves the 69 tracked files on the default branch) → replace README top with a pointer: "Superseded by github.com/itsvedantkumar/vstack; research salvaged to vstack docs/provenance/" → push → `gh repo archive --yes`.
5. **Installed-state drift** — re-run `~/Projects/vstack/install.sh` so `~/.config/agents/bin/doctor` matches `55b6bbd`; `bin/doctor --drift` must come back clean.
6. **Repo hygiene** — delete the untracked Finder-duplicate junk found during exploration: 18 `"SKILL 2.md"` files in `~/Desktop/vedant.to-gh/vedant-to-gh/.claude/skills/`, `".gitkeep 2"` in `~/Desktop/odyssey/odyssey`. (Explicitly NOT running overlay.sh on the 5 repos — stale finding.)

## Step 5 — Final verification (all must pass before "done")

From `~/Projects/vstack`:
- `./.claude/verify.sh` → VERIFIED (21 checks incl. 19)
- `./tests/gate-falsifiability.sh` → all checks proven falsifiable, 0 failed
- `./tests/auto-trigger.sh` → 11/11 + one case per newly vendored skill
- `./bin/doctor` all green and `./bin/doctor --drift` no drift
- Push main; CI (verify + install-linux jobs) green on GitHub
- `gh release view` shows the release; `gh repo view itsvedantkumar/conductor-setup` shows archived + updated pushedAt
- Fresh-clone smoke: clone vstack to a temp dir, `./install.sh --dry-run` exit 0

## Step 6 — Handoff prompt (final deliverable to user)

Produce a copy-paste prompt for the user containing:
1. Conductor UI steps: delete the `conductor-setup` project (safe — all unique content now tracked in vstack `docs/provenance/`), add `~/Projects/vstack` (github.com/itsvedantkumar/vstack) as a new project.
2. An initialization prompt for the first vstack workspace session: repo role (canonical setup source; edit here, run install.sh, never edit ~/.claude), the verification entry points (verify.sh / doctor / tests), and current open residuals.
3. Update auto-memory: `vstack-is-canonical.md` gains the provenance-docs note; record that conductor-setup is merged + archived.

## Key files

- vstack: `bin/vstack` (update cmd), `install.sh:73-84` (trust block), `.claude/verify.sh`, `tests/gate-falsifiability.sh`, `tests/auto-trigger.sh`, `README.md:284-288`, `CHANGELOG.md`, `claude/skills/ATTRIBUTION.md`, new `docs/provenance/`
- kabul workspace (read-only source): `.context/pstack-audit.md`, `.context/plans/`, `.goal/conductor-e2e-audit/goal.md`, `README.md`

## Risks / notes

- Unarchive→push→re-archive on conductor-setup is outward-facing but explicitly authorized ("commit and do whatever you want"); repo is private.
- The `update` confirmation must not break `bin/vstack`'s other subcommands or the CI install job (CI calls install.sh directly, not update — safe).
- claude-mem's 992-token listing cost stays as-is (upstream ceiling, user already told).
