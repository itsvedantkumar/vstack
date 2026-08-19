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
Nothing reports this. The setting is now `0.012`.

## Something has to route the situation

Those three conditions make a skill available. They do not connect "I am writing a README" to
`technical-writing`. `claude/hooks/inject-session-context.sh` carries a routing block that
does, and it runs at every session start.

The block is deliberately short and names only the mappings that frontmatter cannot carry on
its own.

## The measurement

`tests/auto-trigger.sh` runs real prompts through the CLI and reports which skills fired. A
version of the hook that dropped the routing table in favour of "the descriptions are the
triggers" was measured against the same four cases:

| Hook version | Result |
|---|---|
| Routing table present | 4 of 4 cases fire the expected skill |
| Routing table removed | 2 of 4, `technical-writing` and `typescript-best-practices` never fire |

Both runs used two attempts per case. The two that keep working without the table, `swarm` and
`blast-radius`, have descriptions with unusually distinctive trigger language. The two that
stop are the ones whose situations are common English that the model does not otherwise
connect to a skill.

That is why the table stays, and why it names those two lines explicitly.

## Skill dispatch is not deterministic

Choosing a skill is a model decision, so one sample proves little. An early version of the
test asserted on a single run per case and reported a failure for `blast-radius` that two
earlier runs had passed, with the mechanism fully intact.

The test now retries a miss once, controlled by `ATTEMPTS`. The property worth protecting is
that a situation routes to a skill, not that it does so on the first try. A skill that has
genuinely stopped firing misses every attempt.

## Running the test

```bash
./tests/auto-trigger.sh
```

It skips with exit 0 when the CLI is missing or unauthenticated, which is why GitHub Actions
cannot run it. See [tests/README.md](../tests/README.md) for how to add a case.
