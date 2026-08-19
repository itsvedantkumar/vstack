# Skill attribution

vstack ships 29 skills from four sources. Nothing here is original to vstack except the
porting work described below.

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

## From Superpowers (7)

`brainstorming`, `writing-plans`, `executing-plans`, `test-driven-development`,
`systematic-debugging`, `requesting-code-review`, `verification-before-completion`.

Source: [obra/superpowers](https://github.com/obra/superpowers), MIT.

`verification-before-completion`, `systematic-debugging`, and `requesting-code-review` are
disabled in `claude/settings.json`. Their methods are covered by `principle-prove-it-works`,
`principle-fix-root-causes`, and `interrogate` plus the `code-reviewer` subagent. They stay
in the repo so the originals are not lost, and cost nothing while disabled.

## Third-party (2)

- `security-threat-model` — Apache 2.0, license in the skill directory.
- `vercel-deploy` — MIT, Copyright (c) 2026 Vercel, license in the skill directory. Disabled:
  the `vercel` CLI covers it with fewer tokens.

## Written for this setup (2)

- `spaceship` — drives the Spaceship registrar REST API, paired with the `spaceship-mcp` wrapper in `bin/`.
- `tokenmaxxing` — disabled. The SessionStart hook in `claude/hooks/` now carries these rules,
  so loading them as a skill would say the same thing twice.

## Which skills are active

`claude/settings.json` holds the single source of truth in `skillOverrides`. A skill set to
`off` never loads. A skill set to `name-only` loads without its description, which keeps a
long description from spending listing budget. Everything else is active and can auto-trigger.
