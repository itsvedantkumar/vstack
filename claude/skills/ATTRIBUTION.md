# Skill attribution

vstack ships 23 skills from three sources: 18 from pstack, 4 from Superpowers, and 1 original to this repo.

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

## What was removed, and why

| Skill | Removed because |
|---|---|
| `verification-before-completion` | `principle-prove-it-works` carries the same gate, wired to the `verify.sh` Stop hook, and includes the original skill's Iron Law and rationalization table. |
| `systematic-debugging` | `principle-fix-root-causes` carries the method. The `debugger` subagent handles dispatch. |
| `requesting-code-review` | `interrogate`, `blast-radius`, and the `code-reviewer` subagent cover the same ground. |
| `tokenmaxxing` | The SessionStart hook states these rules every session. Loading the skill again repeated them. |
| `vercel-deploy` | The `vercel` CLI does the same work with fewer tokens. |
| `spaceship`, `security-threat-model` | Not used. |

## Original (1)

`ui-iterate` — screenshot and critique cycle for UI files.

Source: this repo, MIT.

## Which skills are active

All 23. `skillOverrides` in `claude/settings.json` exists only to quiet skills that Claude
Code and its plugins install on their own. It never parks a skill from this repo.
