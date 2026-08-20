# Skill attribution

vstack ships 26 skills from five sources: 18 from pstack, 4 from Superpowers, 1 from Impeccable, 1 from Vercel Labs, and 2 original to this repo.

Every skill in this repo is active. Skills that became redundant were deleted, not disabled.

## Ported from pstack (18)

`blast-radius`, `create-verification-skill`, `interrogate`, `maintain-verification-skill`,
`reflect`, `show-me-your-work`, `swarm`, `technical-writing`, `typescript-best-practices`,
`unslop`, and the eight `principle-*` skills.

Source: [cursor/plugins](https://github.com/cursor/plugins) at commit
`195d9359bdc2890f83745df69927528ad4538406`. License in `LICENSE.pstack`.

pstack wrote these skills for Cursor. The port maps Cursor model names to Anthropic ones,
changes `Task` calls to `Agent` tool calls, swaps cloud-only parameters for local execution,
and rewrites `.cursor/` paths as `.claude/`. Where a skill assumed reviewers from different
vendors, the Claude Code version states that every reviewer is an Anthropic model using a
different review lens.

## From Superpowers (4)

`brainstorming`, `writing-plans`, `executing-plans`, and `test-driven-development` form the
planning and implementation chain.

Source: [obra/superpowers](https://github.com/obra/superpowers), MIT.

## Also adapted from Superpowers: a subagent rule, not a skill

`claude/agents/debugger.md` carries a three-failed-fixes stop rule and
anti-rationalization red flags adapted from obra/superpowers systematic-debugging
(MIT). This lives in a subagent, not a skill, so it does not add to the skill count
above and does not change the "2 original" arithmetic in the first line of this file.

## From Impeccable (1)

`impeccable` — design-director quality bar for frontend work: typography, motion, spacing,
color, and brand-vs-product design modes, with per-command reference playbooks.

Source: [pbakaus/impeccable](https://github.com/pbakaus/impeccable), Apache 2.0.
Author: Paul Bakaus. Its `reference/ios.md` and `reference/android.md` derive from ehmo's
[platform-design-skills](https://github.com/ehmo/platform-design-skills), MIT.

The port vendors only the skill (SKILL.md + reference files), not the repo's 23 slash
commands, subagents, or helper scripts. The frontmatter is trimmed to vstack's
`name` + `description` convention; the body is upstream's, so its mentions of
`scripts/*.mjs` helpers and `impeccable-*` subagents refer to pieces that are not vendored —
the `reference/degraded/` playbooks cover the subagent roles inline.

## From Vercel Labs (1)

`agent-browser` — headless per-workspace browser automation: open, viewport, screenshot,
accessibility-tree snapshots with `@eN` refs, click/fill by ref. Backs the ui-iterate loop
when the shared Chrome is unavailable or contended (parallel Conductor workspaces).

Source: [vercel-labs/agent-browser](https://github.com/vercel-labs/agent-browser),
Apache 2.0. Author: Vercel Labs. Vendored from v0.34.0.

Upstream's skill is a discovery stub that defers all usage to `agent-browser skills get core`
at runtime. The vendored version instead inlines the command sequences verified against
upstream's README (Quick Start, Commands, Sessions), trims the frontmatter to vstack's
`name` + quoted situation description, and drops upstream's `allowed-tools` and
`hidden: true` keys. Only SKILL.md is vendored — no upstream code ships in this repo.

## What was removed, and why

| Skill | Removed because |
|---|---|
| `verification-before-completion` | `principle-prove-it-works` carries the same gate, wired to the `verify.sh` Stop hook, and includes the original skill's Iron Law and rationalization table. |
| `systematic-debugging` | `principle-fix-root-causes` carries the method. The `debugger` subagent handles dispatch. |
| `requesting-code-review` | `interrogate`, `blast-radius`, and the `code-reviewer` subagent cover the same ground. |
| `tokenmaxxing` | The SessionStart hook states these rules every session. Loading the skill again repeated them. |
| `vercel-deploy` | The `vercel` CLI does the same work with fewer tokens. |
| `spaceship`, `security-threat-model` | Not used. |

## Original (2)

`ui-iterate` — screenshot and critique cycle for UI files.

`component-registry` — pull vetted primitives from shadcn-compatible registries before
hand-writing UI components. Original text; the registry protocol it teaches is
[ui.shadcn.com/docs/registry](https://ui.shadcn.com/docs/registry) (MIT).

Source: this repo, MIT.

## Which skills are active

All 26. `skillOverrides` in `claude/settings.json` exists only to quiet skills that Claude
Code and its plugins install on their own. It never parks a skill from this repo.
