# Taste, per project

There is no bundled set of reference sites here, and there was briefly: four measured sites baked
into this skill. They were removed. A frozen corpus is a taste snapshot — it rots, it knows nothing
about the project in front of you, and it pushes every build toward whatever those four sites
happened to do in August 2026. Shipping somebody else's answer is the same defect as shipping a
count nobody re-derives.

What ships instead is the measurement.
[`scripts/extract-brand.sh`](../../scripts/extract-brand.sh) points a headless browser at any URL
and returns the properties that separate an expensive build from a default one, as numbers a gate
can enforce afterwards.

## The pipeline

**1. Requirements before references.** What is the surface, who is it for, what must it do. The
four surface modes in SKILL.md — Persuade, Operate, Read, Experience — answer this and constrain
everything downstream. A dashboard does not get a landing page's typography no matter which
references the user liked. Do not proceed to step 2 with an unanswered brief.

**2. The user names the references.** Two to five URLs they want this to feel like. Ask for them;
do not supply them. If the user has no references, ask for adjacent products they admire, or for
an existing surface of their own to stay consistent with. **Never substitute a default set.**

**3. Measure.**

    ./scripts/extract-brand.sh <url> <url> ... > .impeccable/candidate.json

Returns per URL: the rendered type scale, tracking per size in em, leading per size, measure in ch,
resolved ink/ground/hue count and the full colour frequency table, a spacing census with base-unit
conformance, transition durations and easing frequencies, and the radius set.

**4. Reconcile into one brand.json.** Where the references agree, take the agreement. Where they
disagree, the disagreement is a decision to put to the user, not an average — base unit, texture
and radius policy in particular contradict each other between sites, and a blend resolves every
contradiction toward the stock default. Write the result to `.impeccable/brand.json` against
[brand.schema.json](brand.schema.json).

**5. Show before building.** Produce static mockups of the key screens at 1440 and 375 and put them
in front of the user. Screenshot them with `agent-browser screenshot` so what is reviewed is what
renders, not a description of it. Get an explicit yes on the visual direction before any component
is written. A wireframe approved in prose is not approved.

**6. Hand off to Claude Design for wireframing** where the project wants it — see the Claude
Design section in SKILL.md. That lane pushes a design system up with `/design-sync`; it does not
generate back into the session.

**7. Build against the tokens, with the gate armed.** `ui-gate/rules/tokens.sh` reads
`type.scale` from `.impeccable/brand.json` and fails a build that drifts off it. `ui-iterate`
re-shoots at 375/768/1440. Without a `brand.json` none of this fires and the surface is built
normally.

## What to read off a reference, and why each one

Every item is here because it is measurable, it survives into a gate, and it differed between
expensive builds and default ones.

| property | why it is on the list |
|---|---|
| type scale | the sizes actually rendered; `TOK-TYPE-SCALE` fails against exactly this |
| tracking per size, in `em` | the property that survives a fluid resize unchanged; `px` tracking does not |
| leading per size | it inverts with size on expensive builds and is flat on default ones |
| measure in ch | short measure is one of the cheapest signals of care |
| ink, ground, hue count | pure black on pure white, and more than two hues, both read as default |
| hairline treatment | whether borders are a solid grey or ink at low alpha |
| spacing base unit | inferred from a census of what rendered, not from a config file |
| tight-to-open ratio | the ratio between intra-group and inter-section spacing carries more than any value |
| duration bands | expensive builds cluster short and long with a gap; default ones sit at 300ms |
| easing frequency | one house curve doing most of the work is a signal; five curves evenly used is not |
| radius set | a declared set, so anything off it is drift |

## Two things to check on any reference before copying it

Measure contrast on the smallest text. Measure `prefers-reduced-motion` coverage against the
motion actually present. Reference sites ship accessibility defects — a 12px line at 4.34:1 and a
scroll-driven hero uncovered by any reduced-motion rule were both found in sites worth learning
from otherwise. Take the craft, not the defect.
