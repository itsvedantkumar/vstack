# Skill attribution

vstack ships 22 skills from two sources. Nothing here is original to vstack except the porting
work described below.

Every skill in this repo is one the setup actually uses. Skills that turned out to be
redundant were deleted, not shipped disabled: a skill not worth loading is not worth carrying,
and a disabled skill is one more thing to read past.

## Ported from pstack (18)

`blast-radius`, `create-verification-skill`, `interrogate`, `maintain-verification-skill`,
`reflect`, `show-me-your-work`, `swarm`, `technical-writing`, `typescript-best-practices`,
`unslop`, and the eight `principle-*` skills.

Source: [cursor/plugins](https://github.com/cursor/plugins) at commit
`195d9359bdc2890f83745df69927528ad4538406`. License in `LICENSE.pstack`.

These were written for Cursor and rewritten for Claude Code: Cursor model names mapped to
Anthropic ones, `Task` calls to the `Agent` tool, cloud-only parameters to local execution,
and `.cursor/` paths to `.claude/`. Where a skill assumed reviewers from different vendors,
the Claude Code version says plainly that every reviewer is an Anthropic model and uses
different review lenses instead of pretending the reviewers are independent.

## From Superpowers (4)

`brainstorming`, `writing-plans`, `executing-plans`, `test-driven-development` — the planning
and implementation chain.

Source: [obra/superpowers](https://github.com/obra/superpowers), MIT.

## What was removed, and why

| Skill | Removed because |
|---|---|
| `verification-before-completion` | `principle-prove-it-works` carries the same gate and is wired to the `verify.sh` Stop hook. Its Iron Law and rationalization table were merged in. |
| `systematic-debugging` | `principle-fix-root-causes` carries the method; the `debugger` subagent handles dispatch. |
| `requesting-code-review` | Covered by `interrogate`, `blast-radius`, and the `code-reviewer` subagent. |
| `tokenmaxxing` | The SessionStart hook states these rules on every session. Loading them again said the same thing twice. |
| `vercel-deploy` | The `vercel` CLI does the same work with fewer tokens. |
| `spaceship`, `security-threat-model` | Not used. |

## Which skills are active

All 22. `skillOverrides` in `claude/settings.json` still exists, but only to quiet skills that
Claude Code and its plugins install on their own, never to park a skill from this repo.
