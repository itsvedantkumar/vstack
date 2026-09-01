# How skills fire

A skill that is installed but never triggers looks identical to one that works. This page
records what actually makes the difference here, and the measurements behind each claim.

## Installing a skill does not make it fire

The first attempt at this setup installed 18 skills correctly and scored 0 out of 4 on a test
that asked for behaviour those skills cover. Nothing errored. The skills were present,
readable, and enabled.

Three conditions have to hold at once:

**The skill must not carry `disable-model-invocation`.** Upstream pstack sets it on 40 of its
44 skills, which makes them explicit-invoke only. Removing the flag makes a skill eligible.
Eligible is not the same as triggered.

**The description must name a situation.** The model matches situations, not capabilities. "Cut
AI tells from any text you write" gives it something to match against. "Writing quality tool"
does not.

**The description has to survive the skill listing.** `skillListingBudgetFraction` multiplied
by the context window sets the token budget for descriptions. Exceed it and Claude Code
truncates them, cutting the trigger phrases first because they sit at the end. At `0.006` this
repo's listing needed roughly 1,667 tokens against a 1,200 token budget, about 39 percent over.
Nothing reports this. The setting is now `0.016`.

## What the listing actually costs

Measured on a 1M context, so the budget is 16,000 tokens:

| Injected every session | Bytes | Tokens |
|---|---|---|
| skill listing, all sources | 9,340 | 2,335 |
| SessionStart hook block | 2,619 | 655 |
| subagent listing | 1,606 | 401 |
| `CLAUDE.md` | 1,230 | 308 |
| command listing | 1,062 | 265 |
| **total** | **15,857** | **3,964** |

The skill listing uses about 15 percent of its budget. It is not the constraint, and trimming
descriptions to save tokens would cost trigger accuracy for nothing. The per-prompt digest is
222 bytes, which over a hundred turns costs more than the session baseline does once.

## Overrides do not reach skills that come from a plugin

`skillOverrides` sets a skill to `off` or `name-only` to keep it out of the listing. It works
for bundled skills and has no effect on skills a plugin supplies: for those, Claude Code
resolves the listing mode before it reads the setting.

The split is visible in any session. Of the four bundled skills set to `off`, none appear. Of
the thirteen set to `name-only`, all thirteen appear as a bare name with no description. Skills
supplied by a plugin appear with their full description regardless of what any override says.

This was measured against `claude-mem`, which supplied 19 such skills — about 992 tokens,
roughly 42 percent of the listing. `claude/settings.json` carried 38 override entries trying to
suppress them, in both the `claude-mem:` and `claude-mem@thedotmack:` spellings. Neither works,
and having both is what made it look like a spelling problem rather than a ceiling. They are
deleted, and check 15 now fails any `skillOverrides` key containing `:` or `@`.

There is no setting that fixes this. The only lever is not installing the plugin. vstack removed
claude-mem in 1.46.0 for an unrelated and more decisive reason — it injected nothing — but the
ceiling is a property of the resolver, not of that plugin, and applies to the next one.

## Something has to route the situation

Those three conditions make a skill available. They do not connect "I am writing a README" to
`technical-writing`. `claude/hooks/inject-session-context.sh` carries a routing block that
does, and it runs at every session start.

The block is deliberately short and names only the mappings that frontmatter cannot carry on
its own.

## The measurement

`tests/auto-trigger.sh` runs real prompts through the CLI and reports which skills fired. A
version of the hook that dropped the routing table in favour of "the descriptions are the
triggers" was measured against the 28 auto-trigger cases the suite carried on 2026-08-23:

| Hook version | Result |
|---|---|
| Routing table present | 9 of 9 cases fire the expected skill |
| Routing table removed | 7 of 9, `technical-writing` and `typescript-best-practices` never fire |

Both runs used two attempts per case. The two that keep working without the table, `swarm` and
`blast-radius`, have descriptions with unusually distinctive trigger language. The two that
stop are the ones whose situations are common English that the model does not otherwise
connect to a skill.

That is why the table stays, and why it names those two lines explicitly.

## Skill dispatch is not deterministic

Choosing a skill is a model decision, so one sample proves little. An early version of the
test asserted on a single run per case and reported a failure for `blast-radius` that two
earlier runs had passed, with the mechanism fully intact.

The test now retries a miss up to twice, for 3 attempts total, controlled by `ATTEMPTS`. The property worth protecting is
that a situation routes to a skill, not that it does so on the first try. A skill that has
genuinely stopped firing misses every attempt.

## Running the test

```bash
./tests/auto-trigger.sh
```

It skips with exit 0 when the CLI is missing or unauthenticated, which is why GitHub Actions
cannot run it. See [tests/README.md](../tests/README.md) for how to add a case.
