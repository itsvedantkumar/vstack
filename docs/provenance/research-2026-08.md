# Phase 3 survey — alternatives research, 2026-08-20

Four parallel research agents surveyed the landscape since 2026-08-19 (skill packs and
marketplaces; vibecoding and design tooling; Conductor features; hook and gate patterns).
The bar for adoption: names a specific capability this setup lacks, verified real by reading
issues and code rather than README claims, worth its listing tokens, and requires no login.
Everything below is recorded — adoptions, deferrals, and rejections with reasons — so the
next survey starts from verdicts instead of re-litigating.

## Adopted

| What | From | Landed as |
|---|---|---|
| Component sourcing before hand-rolling UI | shadcn/ui registry protocol (MIT, active daily) | `component-registry` skill + routing line + auto-trigger case. The setup had strong post-hoc critique (screenshot, pixel-diff, axe-core) and nothing for where components come from. |
| Three-failed-fixes stop rule + anti-rationalization red flags | obra/superpowers `systematic-debugging` (MIT) | Two paragraphs in the `debugger` subagent. The skill itself was already adjudicated and removed (ATTRIBUTION: `principle-fix-root-causes` carries the method); this ports the one rule that wasn't carried. |
| Review findings land in Conductor's Checks panel | Conductor bundled skill + `mcp__conductor__DiffComment` (real, callable) | `interrogate` skill and `review` command now post inline diff comments when `CONDUCTOR_WORKSPACE_PATH` is set. |
| Open todos silently block Conductor's merge button | Conductor changelog 0.73.0/0.73.1 | One line in `claude/CLAUDE.md`: clear finished todos before stopping. |
| `scripts.archive`, `[environment_variables]`, `.worktreeinclude` | Conductor docs (stable) | Commented examples in the overlay's `.conductor/settings.toml` template, so downstream repos see the options. |

## Deferred, with the blocker named

- ~~`~/.conductor/settings.managed.toml`~~ **Adopted 2026-08-20** once the user made the
  plan-mode call: `conductor/settings.managed.toml` pins models/fastMode/plan-mode, install.sh
  always overwrites the installed copy, and `doctor --drift` compares it. Plan mode stays
  available per session; the global toggle is pinned false with the rationale in the file.
- **Claude Code native sandboxed Bash — adopted, then reverted the same hour, on live
  evidence.** The scratch-HOME evaluation looked adoptable: hooks run outside the Bash
  sandbox (Stop gate unaffected), workspace writes work, `$HOME`/`~/.claude` kernel-denied,
  `gh` carved out via `excludedCommands: ["gh *"]` (syntax proven; bare `"gh"` does not
  match subcommands). Enabling it live then showed the disqualifier the scratch test could
  not: the write boundary is the *session workspace*, and this setup's daily pattern is
  cross-repo writes from Conductor workspaces — editing vstack from any workspace, running
  `install.sh` from agent Bash (`~/.claude` deny is unliftable), `/tmp` logging. Every
  running session inherited the friction mid-flight. Re-evaluate if the sandbox ever gains
  a machine-level allowWrite for chosen repos, or if the cross-repo pattern changes.
- **Prompt-injection output scanning** (dwarvesf/claude-guardrails concept; scan fetched
  content for injected instructions). The repos surveyed are thin (32–262 stars, no
  false-positive data); the concept only enters vstack the way everything else did — rebuilt
  with a falsifiability proof. Not paid for yet by any observed incident.
- **vexscan pre-install plugin scanner** — right idea for the marketplace lane, 1-star
  maturity. Re-check in six months.
- **Conductor Stacks / `gh stack`** — real (changelog 0.80.0) but no stacked-PR workflow
  exists here to serve.

## Rejected

| Candidate | Why |
|---|---|
| anthropics/skills `skill-creator` | Already reaches this machine via the official plugin marketplace, deliberately `name-only` in `skillOverrides`. Vendoring would duplicate it. |
| anthropics/skills `mcp-builder`, `webapp-testing` | MCP authoring is rare enough that the claude-api reference covers it; webapp-testing is Playwright-shaped, and `agent-browser` was chosen specifically to avoid that dependency and its shared-Chrome contention. |
| anthropics docx/pdf/pptx/xlsx skills | Source-available, all rights reserved — cannot vendor. |
| anthropics `security-guidance` plugin | Real (100KB+ of hook code) but all-rights-reserved: installable via `/plugin install`, never vendorable. Left as a user decision because it adds a PreToolUse hook to every Edit/Write. |
| obra `requesting/receiving-code-review` | Already adjudicated in ATTRIBUTION's removed table: `interrogate` + `code-reviewer` cover it. |
| obra worktree/branch-lifecycle skills | Conductor owns the worktree lifecycle here. |
| wshobson/agents (92 plugins, 38.9K stars) | Its value is multi-harness portability; this setup deliberately dropped every runtime but Claude Code. |
| claude-mem replacement candidacy | The gap it fills is real but it now injects a paid-tier pitch into every session banner and its 992-token listing cost is already a documented ceiling. Existing `reflect` + MEMORY.md keep the continuity with more control. |
| awesome-list aggregators (rohitg00 toolkit) | Crowdsourced directories with no quality control on entries. |
| better-design, superdesign | Both need logins to external SaaS; superdesign's core repo also has no real license. |
| odiff, Playwright `toHaveScreenshot`, reg-suit, BackstopJS, Lost Pixel | Redundant with `agent-browser`'s native pixel-diff, or unmaintained (BackstopJS ~2 years stale; Lost Pixel archived into Figma 2026-04). |
| anthropics `frontend-design` | `impeccable` already states it goes beyond this bar. |
| karanb192 hook pack (pr-provenance-stamp, dead-rules-audit) | Overlaps `show-me-your-work`'s decision trail; every hook adds per-event latency and none of these earn it. |
| Single-use approval tokens (alexknowshtml) | 4 stars, no tests; the pattern is noted, the repo is not evidence. |
| Mutation-testing agent-written code (Stryker/PITest gate) | Real at Google/Meta scale; here it is per-repo test infrastructure, not setup config — belongs in a repo's own verify.sh when a repo earns it. |
| Making `interrogate` a mandatory Stop-hook pass | A model-decision gate is exactly the flaky-gate failure this repo documented: a gate that fails half the time gets ignored. Stays a routed skill. |
| Anthropic Compliance API | Enterprise-gated; local trails cover the need. |
| Conductor Cloud API / mobile app | Pro-gated and "coming soon"; the Remote Control lane was chosen over it for reasons recorded separately, and nothing in this window changes that. |
| Conductor Checkpoints | Zero-config, already on; nothing to adopt. |

## Sources

Surveys ran against: anthropics/skills, anthropics/claude-code plugins, obra/superpowers,
wshobson/agents, thedotmack/claude-mem, ui.shadcn.com/docs/registry, conductor.build docs and
changelog (0.73–0.80), dwarvesf/claude-guardrails, lasso-security/claude-hooks,
karanb192/claude-code-hooks, Check Point CVE-2025-59536 disclosure, and the Claude Code
sandboxing docs. Star counts, licenses, and last-push dates were read from the GitHub API on
2026-08-20.
