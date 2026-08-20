# Harden vstack into a top-tier autonomous vibecoding system

## Context

The handoff asks for an audit-then-upgrade of the whole Claude Code + Conductor setup, with evidence for every claim, ending in a public-grade vstack repo. Phase 1 of that audit is **done** — findings below are verified against the tree, not asserted.

The headline result: **the gate is not measuring what it reports.** `.claude/verify.sh` says `VERIFIED` today while shipping a stale doc count and a plugin lane missing three of five hooks. Five of thirteen checks evaporate silently on a host without `jq`. The Stop-hook gate that is supposed to block on failure is inert on any machine where `jq` is not at `/usr/bin/jq`. So the first work is not new features — it is making the instrument honest, because nothing after it is provable until it is.

Second result: **token cost is not the problem.** Measured fixed surface is ~15.9 KB ≈ 3,964 tokens/session; the skill listing is 2,335 tokens against a 16,000-token budget (`skillListingBudgetFraction: 0.016`). No trimming campaign is warranted. The one real waste is 992 tokens of claude-mem descriptions that 38 lines of `skillOverrides` config claim to suppress and provably cannot.

### Workspace note

This Conductor workspace (`conductor-setup`, HEAD `3e8e6eb`) is **not** the canonical repo. Canonical is `~/Projects/vstack` (HEAD `6f2f757`, branch `main`). All work happens there. `conductor-setup` is a superseded predecessor and is itself a finding — see Phase 4.

---

## Verified findings (file:line)

### The gate false-passes

| # | Evidence | Defect |
|---|---|---|
| G1 | `.claude/verify.sh:118`, `:148`, `:187` | Checks 8, 9b, 11 are `if command -v jq` with **no else** — print nothing, vanish silently. On a jq-less host `VERIFIED` means 8 checks passed, not 13. |
| G2 | `.claude/verify.sh:189-192` | Check 11 claims "both lanes" but never reads `claude/hooks/hooks.json`. That lane wires **only** SessionStart + Stop; `UserPromptSubmit`, `PostToolUse`, `PostToolUseFailure` are missing **right now** and the gate is green. |
| G3 | `.claude/verify.sh:191` | `grep -q "$ev" install.sh` matches prose comments, and `PostToolUse` matches `PostToolUseFailure`. Proves a string exists, not that a hook is wired. |
| G4 | `.claude/verify.sh:202-209` | Check 12 counts skills + agents, never commands. `README.md:3-4` and `.claude-plugin/marketplace.json:15` say "15 commands"; tree has **14** (`orchestrate` removed in `eb22605`). Shipped green. Also asserts a right number appears *somewhere*, never that a wrong one does not. README's count is line-wrapped, so any grep needs whitespace normalization first. |
| G5 | `.claude/verify.sh:71`, `:78-80`, `:87-89` | Checks 4/5/6 are negative greps with `2>/dev/null` — any grep *error* yields empty hits → PASS. Check 5 scans the worktree, not `git ls-files`, and misses `api_key=`, `sk-proj-`, `xoxb-`, `AIza…`, `PRIVATE KEY` blocks. |
| G6 | `.claude/verify.sh:124` | Check 8 writes fixed `/tmp/vs-merge-{a,b}.json` — races across concurrent workspaces. The rest of the file uses `mktemp -d` correctly (`:149`). |
| G7 | `.claude/verify.sh:166-181` | Check 10 lacks the `n>0` empty-glob guard that check 3 has at `:65`. |

### The Stop-hook gate does not always block

| # | Evidence | Defect |
|---|---|---|
| S1 | `claude/hooks/verify-gate.sh:18`, `:22`, `:34` | Hardcodes `/usr/bin/jq`. Missing there → the `decision:"block"` JSON at `:34` is never emitted, so **a failing verify.sh does not block**. The gate is inert while appearing installed. |
| S2 | `verify-gate.sh:22` | `sid` falls back to `"nosess"` → one global counter file, so 3 failures anywhere latch the gate off machine-wide (`:28`). |
| S3 | `verify-gate.sh` (whole file) | No `set` line at all, unlike `.claude/verify.sh:7` and `bin/doctor:3`. |
| S4 | `install.sh:76-84` + `bin/vstack:66` | `update` = `git pull && install.sh`, and install re-trusts `verify.sh` unconditionally. Pull-then-auto-trust, no diff, no review. Worse: trust covers only `verify.sh`, but that script executes `install.sh --dry-run` (`:138`) and `overlay.sh` (`:153`), **neither hash-verified**. Trust boundary is one file; blast radius is the repo. |

### doctor reports pass on total failure

| # | Evidence | Defect |
|---|---|---|
| D1 | `bin/doctor:161`, `:168`, `:172` | `cutoff=$(date … \|\| date …)`; if both fail, `cutoff=""` → every repo skipped → `uncovered=""` → `ok "active repos overlaid"`. **Complete failure reports as a pass.** |
| D2 | `bin/doctor:166`, `:163` | `[ -d "$r/.git" ]` makes git worktrees invisible (`.git` is a file); `~/conductor/workspaces` is never scanned. "Coverage" means coverage of two hardcoded directories. |
| D3 | `bin/doctor:63-87` | `--drift` never compares `claude/CLAUDE.md`, `statusline.sh`, `shell/claude-parity.zsh`, or `settings.json` — and `install.sh:95-96` itself calls CLAUDE.md "the file most likely to have been hand-edited". |
| D4 | `bin/doctor:50` | `diff -rq … 2>/dev/null \| wc -l` — if diff errors, `n=0` → reported clean. Fail-open. |
| D5 | `bin/doctor:34-37` vs `bin/vstack:58-62` | Copy-pasted resolvers that disagree: doctor exits **0** on unresolvable repo, vstack exits **1**. |
| D6 | `bin/doctor:124`, `:120` | `[ "$n" -ge 6 ]` subagents while the tree ships 8; hook name list hardcodes 3 of 4. |

### Token and autonomy (measured)

- Fixed per-session surface **15,857 B ≈ 3,964 tokens**: skill listing 2,335 / SessionStart hook 655 / agents 401 / CLAUDE.md 308 / commands 265. Budget at 1M ctx is 16,000 tokens. **Under by 6.8×.**
- **19 `claude-mem:*` skills = 992 tokens = 42% of the skill listing, and `skillOverrides` cannot suppress them.** Root cause read out of the shipped CLI binary (`~/.local/share/claude/versions/<version>`): the listing resolver short-circuits `if(e.type!=="prompt" || e.source==="plugin") return "on"` **before** `skillOverrides` is read. Confirmed three ways: (a) the binary short-circuit; (b) a perfect live split — all 4 bundled `"off"` entries are absent from the listing and all 13 bundled `"name-only"` entries appear as bare names, while all 19 plugin entries appear in full; (c) `claude/settings.json:25-62` already ships *both* candidate spellings and both are inert. **All 38 lines are dead config.**
- `UserPromptSubmit` digest is 222 B/prompt ≈ 5,550 tokens over 100 turns — more than the session baseline, and ungated.
- 4 agent descriptions exceed the 200-char cap (explorer 250, worker 250, design-reviewer 210, planner 210); check 3 caps skills only.
- `conductor/settings.toml:10` `default_plan_mode = true` blocks every session on human plan approval — while `~/.claude/settings.json` sets `bypassPermissions` precisely to stop approving things.
- `overlay.sh:85` pins bootstrap to hardcoded SHA `ecb6992e`, already drifted from HEAD.
- `overlay.sh:35` copies `claude/settings.json` wholesale, shipping `theme`, `tui`, notification prefs, `forceLoginMethod`, `enabledPlugins` and the 57-entry `skillOverrides` map into every repo a stranger clones.
- `overlay.sh:89` wires a Stop hook to `./.claude/verify.sh` but **never ships a verify.sh** — overlaid repos get an armed gate with no gate script.
- `claude/settings.json:137-140` enables `claude-mem@thedotmack` but the repo never declares that marketplace, so a fresh machine cannot resolve it.
- `install.sh:157` comments that "retired top-level keys are `del()`ed explicitly below"; the only `del()` is `del(.hooks)` at `:173`. The promised cleanup does not exist.
- Corrected audit claim: notify hooks **are** reproducible from the repo (`install.sh:160` + wire sites `:179`, `:187`, `:190-192`). What is missing is a check keeping them wired.

### Tests

Assertion mechanism is **sound** — `tests/auto-trigger.sh:66-74` parses `stream-json` for `Skill` tool_use and anchors the match at `:127`. Weaknesses are in what is accepted: `:229` allows `technical-writing|unslop` while unslop's own description is "must always apply" (near-tautological); `:247` and `:253` use wide ORs; `ATTEMPTS=3` hides hit-rate decay because only pass/fail is recorded; 9 of 25 skills covered; no negative controls; three preflight paths `exit 0` so CI is permanently green-by-skip. `tests/README.md:41` says "4 cases" — there are 9.

---

## Approach

**Gate-first, except for the instrument itself.** You cannot gate-first while the gate silently vanishes, so Phase 0 fixes `verify.sh` and `verify-gate.sh` outright. After that, every unit writes its check, **runs it red**, then lands the fix, and the commit message records the red output. That is the handoff's "add a gate check for any bug class that shipped green", made repeatable.

The durable form is `tests/gate-falsifiability.sh` (U3): promote the one-off falsifiability step already in `.github/workflows/verify.yml:24-39` into a table of `check-id | mutation | expected failing check`. Every new check must register a row. Without it, a future refactor neuters check 11 again and nothing notices — which is exactly how today's state arose.

---

## Phase 0 — make the instrument honest (fix-first)

**U1 — `.claude/verify.sh` cannot silently skip.** Add check 0: `jq`/`git` absent → `bad`, not `skip` (jq is core tier per `README.md:56`). Give checks 8/9b/11 `else bad` branches. Convert check 8's fixed `/tmp` paths to `mktemp -d`. Add `n>0` guards to check 10. Print a trailing `checks run: N/N`.
*Proof:* `PATH= ./.claude/verify.sh` must exit non-zero.
*Risk:* a jq-less cloud sandbox now blocks at Stop instead of passing. Intended — that is the bug.

**U2 — `verify-gate.sh` actually blocks.** Add `set -uo pipefail`. Resolve `JQ=$(command -v jq)`; when unresolvable, emit the block JSON via `printf` rather than not blocking. Replace the `"nosess"` global-counter fallback.
*Proof:* **new check 23** runs the hook against a deliberately failing verify.sh, with and without jq on PATH, and asserts `decision:"block"` in both.

**U3 — `tests/gate-falsifiability.sh`.** Table-driven; seeded with the existing skill-description mutation; wired into CI, replacing the inline step. Rule added to `tests/README.md`: no new check merges without a row.
*Proof:* **check 24** asserts every `--- N.` header in verify.sh has a row. Keep the workflow's trailing `git diff --exit-code` so a mutation that fails to restore is caught.

U1 → U2 → U3 in order. U4–U9 are independent and parallelizable after U3.

## Phase 1 — bug classes, gate-first

**U4 — hook wiring, three lanes (rewrite check 11).** Inspect `claude/settings.json`, `claude/hooks/hooks.json`, and install.sh's rebuild program — extracting the jq program the way check 8 already does at `:119`, and anchoring on `^\s*<Event>: \[` instead of a bare substring grep. Assert the notify command stays wired to all 5 events. Then add the 3 missing events to `hooks.json` using the `${CLAUDE_PLUGIN_ROOT}` style at `:10`, `:22`, preserving `VSTACK_PROFILE=skills` on SessionStart only.
*Red first:* must report 3 missing plugin-lane events.
*Risk:* the plugin lane now runs `format.sh` and `failure-diagnose.sh` for plugin-only installs. Verify both no-op safely without `$CLAUDE_PROJECT_DIR`.

**U5 — counts (rewrite check 12).** One `derive()` emitting skills/agents/commands/hooks/mcp from the tree. Bidirectional assertion: scan each doc for every `<N> <noun>` pair and fail if any claimed N differs — a wrong number fails even when the right one also appears. Normalize whitespace (`tr '\n' ' ' | tr -s '[:space:]' ' '`) so README's wrapped count is visible. Assert ATTRIBUTION's `18+4+1+1+1` sums to derived skills. Files covered: `README.md`, `.claude-plugin/marketplace.json`, `claude/.claude-plugin/plugin.json`, `claude/skills/ATTRIBUTION.md`, `claude/CLAUDE.md`, `docs/how-skills-fire.md`, `tests/README.md`. Historical prose (`docs/how-skills-fire.md:8`, `:15`) exempted by an explicit `file:line` allowlist so each exemption is a visible diff. Fix 15 → 14 commands in README and marketplace.json; fix `tests/README.md:41`.

**U6 — manifest version sync (check 13).** `marketplace.json:13` must equal `plugin.json:3`. Green on arrival; the falsifiability row proves it bites.

**U7 — secret/path scans (checks 4/5/6 → 22).** Iterate `git ls-files`, not the worktree. Capture grep's exit status: 0 = hits, 1 = clean, **≥2 = error → bad**. Extend patterns with `api_key=`, `sk-proj-`, `xoxb-`, `AIza[0-9A-Za-z_-]{35}`, `-----BEGIN [A-Z ]*PRIVATE KEY-----`.
*Risk:* new patterns may trip on `secrets.env.example` — it assigns nothing (`:77`), verify it stays clean.

**U8 — agent description cap (check 14).** Extend check 3's cap to `claude/agents/*.md`; trim explorer/worker/design-reviewer/planner to ≤200.
*Risk:* this is the one unit with no automated proof — trim filler, never trigger vocabulary, and read the before/after.

**U9 — skillOverrides cleanup (check 15).** Delete `claude/settings.json:25-62` (all 38 plugin-namespaced entries — provably inert, and "remove, don't disable" is settled policy). Check 15: no `skillOverrides` key contains `:` or `@`; every remaining key names a real `claude/skills/*` dir or a known-bundled name. Record the `wGe()` short-circuit and its evidence in `docs/how-skills-fire.md` so the 992 tokens are documented as an upstream limitation, not a config bug.
*Do not* delete `~/.claude/plugins/cache/` entries — `bin/doctor:151-155` documents that claude-mem auto-updates and reverts local edits. `bin/doctor:149` asserts `skillOverrides|length>0`, still true with 19 real entries.

**U10 — settings partition (check 16).** Add `claude/settings.project-keys`. Add `extraKnownMarketplaces` to the repo (fixes the unresolvable `enabledPlugins` marketplace). Record chosen install flags to `~/.config/agents/install-flags` and replay them in `bin/vstack:66`, so `--bypass-permissions` stops being operator memory. Check 16: every top-level key in `claude/settings.json` is classified project-safe / user-only / generated — nothing unclassified.
Keep out of the repo: `permissions.defaultMode`, `skipDangerousModePermissionPrompt` (public repo; `install.sh:16-18` states the opt-in deliberately) and `remote.defaultEnvironmentId` (check 6 correctly bans that ID shape).
*Risk:* the portable file wins every key it ships (`install.sh:172-175`), so a locally-added marketplace would be clobbered. Merge that key additively or state the clobber in the `:151-157` comment.

**U11 — overlay split (checks 17/18/19).** Build the shipped settings from `settings.project-keys` via jq. Ship: `hooks`, `statusLine`, `env`, the two skillListing knobs, cleaned `skillOverrides`, `enableWorkflows`, and the parity trio `model`/`effortLevel`/`fastMode` (cloud sandboxes need them; `bin/doctor:143` asserts them). Never ship: UI/notification prefs, `forceLoginMethod`, `autoUpdatesChannel`, `cleanupPeriodDays`, `fileCheckpointingEnabled`, `remoteControlAtStartup`, `enabledPlugins`, `extraKnownMarketplaces`. Add `verify.sh.tmpl` written only when absent (runs the repo's own test/lint if present, else exits 0 with a replace-me banner) — do not copy vstack's own, it asserts `claude/skills/`. Replace the `:85` hardcoded SHA with `git -C "$SRC" rev-parse HEAD`, preserving the pin-to-a-reviewed-commit property without the drift.
*Risk — highest in the plan:* the merge at `:28` is `$dest * $src`, which **preserves** personal keys already committed in overlaid repos. The next run must `del()` the denylist explicitly, and check 17 must seed the temp repo *with* a personal key to prove removal.

**U12 — `bin/doctor` (check 21).** Add CLAUDE.md / statusline.sh / claude-parity.zsh to `--drift`, plus a key-*subset* settings comparison (the installed file legitimately has more keys). Capture diff's rc at `:50` (≥2 = error). Empty `cutoff` at `:161` → `bad`. `[ -d "$r/.git" ]` → `[ -e ]` and add `~/conductor/workspaces` to the scan roots. Derive the subagent floor and hook list from the repo. Make `:34-37` exit 1 to match `bin/vstack`. Extract the duplicated resolver into one sourced file under `bin/` (both copies must find it; `install.sh:131-135` copies all of `bin/*`). Add the `~/.conductor/settings.toml` `[models]` comparison U15 needs.

**U13 — trust model.** Extend the trust record to cover `install.sh` and `overlay.sh`, since `verify.sh:138`/`:153` execute them. Change `vstack update` to diff the three scripts against their trusted hashes and refuse when changed unless `--yes`, reporting the diff rather than silently re-trusting.
*Autonomy trade-off, stated deliberately:* this is the one place the plan **adds** a stop. `--yes` must be plumbed through `bin/vstack` and every cron/launchd caller (check `bootstrap.sh` and the `schedule` skill) before it lands, and doctor must surface "untrusted change pending" so an unattended run reports instead of hanging.
*Proof:* **check 25** — every script verify.sh invokes is trust-covered, and the gate rejects a modified `install.sh`.

**U14 — tests.** Narrow `:229` to `technical-writing` and tighten `:247`/`:253`. Record per-case hit rate across attempts so decay is visible before it becomes failure. Add 2–3 negative controls (prompts where no skill may fire). Make the three preflight `exit 0` paths exit 0 only under `CI=true`, else exit 2 — a local skip currently reads identically to a pass.
*Risk:* tightening may fail a real, acceptable routing outcome. Run the suite before and after and compare rates. This unit needs live evidence, not reasoning.

**U15 — autonomy.** `conductor/settings.toml:10` → `default_plan_mode = false`. This is a genuine conflict, not a nit: installing `bypassPermissions` to stop approving tool calls and then blocking every session on plan approval is contradictory, and this repo's whole thesis (measured in `docs/how-skills-fire.md`) is that `brainstorming`/`writing-plans` fire *conditionally* on the situations that warrant them. The safety net is the Stop-hook gate plus per-workspace worktree isolation. Add **check 20**: digest ≤256 B, session baseline ≤2 KB, so the per-prompt cost cannot grow silently. Document the measured token surface.
*Rollout caveat:* `install.sh:106` writes `~/.conductor/settings.toml` only when absent, so existing machines keep `true` until doctor's new drift report prompts action. Say so in the commit message.

Ordering: U1→U2→U3 first. U12 after U1, before U15. U11 after U10. U13 after U11.

## Phase 2 — prove it

Run and record output for each: `.claude/verify.sh` (VERIFIED), `bin/doctor` + `--drift` (ALL GREEN, no drift), `tests/gate-falsifiability.sh`, `tests/auto-trigger.sh` (background, ~15 min typical / 54 min worst case at `ATTEMPTS=3` × 9 × 120 s), `install.sh --dry-run` from a **fresh GitHub clone in /tmp**, `uninstall.sh --dry-run`, `overlay.sh` into a seeded scratch repo, and one live cloud-lane smoke — `claude --setting-sources=project,local -p …` in an overlaid scratch repo, where a reply ending in `Next:` proves the OUTPUT STYLE directives loaded.

## Phase 3 — research alternatives (parallel web agents)

Survey since 2026-08-19: Claude Code skill packs and plugin marketplaces, vibecoding/design tooling (component registries, visual regression, screenshot loops, design-review agents), Conductor features, hook/gate patterns. For each candidate answer three questions: what specific capability does this setup lack, is it *real* (read issues and code, not README claims — the ruflo lesson), is it worth the tokens. Adopt only by vendoring with license + attribution, description ≤200 chars and situation-formed, verify.sh green, **plus a new `auto-trigger.sh` case per skill vendored**. Skip anything requiring a login.

## Phase 4 — public repo

Only after 1–3 land. README on Diátaxis lines: quickstart ≤3 commands, a concept map of the three lanes, honest limitations (including the plugin-skill suppression finding). CI extended with a Linux-container `install.sh` smoke. Semver tag + changelog, with `marketplace.json`/`plugin.json` kept in sync by check 13. Verify the marketplace lane is installable by a stranger (`/plugin marketplace add`). Issue templates only if they earn their weight. LICENSE/ATTRIBUTION complete. Every new documented count registered with check 12.

Also resolve the duplicate-repo finding: `github.com/itsvedantkumar/conductor-setup` is a superseded predecessor of vstack still carrying 69 tracked files. Under "remove, don't disable", archive it with a README pointer to vstack rather than leaving two plausible sources of truth.

All prose written in this phase (README, changelog, PR bodies, commit messages) goes through `unslop` and `technical-writing`.

## Definition of done

Every unit committed separately with its proof in the message (the red output, then the green). CI green. `vstack test` 9/9 or better with the new cases and negative controls. `doctor` ALL GREEN, no drift. Final report: what changed, what was measured before and after, what was rejected and why, and the short list of human-only items. Memory files under `~/.claude/projects/<project-slug>/memory/` updated in place — `setup-intent-behavior-gaps.md` and `factory-audit-2026-08.md` are the ones this work invalidates.

## Human-only items (deferred to the final report, not blocking)

- Whether `default_plan_mode = false` propagates to existing machines (`install.sh:106` writes only when absent).
- The 992 claude-mem listing tokens are an upstream CLI limitation; the only lever is disabling the plugin, which would break memory capture — out of scope per settled decisions.
- Any Phase 3 candidate requiring a login or paid signup.
