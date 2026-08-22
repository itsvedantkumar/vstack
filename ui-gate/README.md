# ui-gate

An executable floor for interface work. It answers "do these known conditions hold", and nothing
else. It does not judge whether a design is good, and a green run is not evidence that it is.

That distinction is the whole reason this exists. There is no automated measure of visual quality
worth gating on: the research this was built from records aesthetic classifiers at 0.73 accuracy
and under 0.20 IoU, and a visual-aesthetics benchmark agreeing with humans 26.5% of the time
against a 68.9% human baseline. So the gate holds a floor with fixed thresholds, and taste stays
a human judgement.

## Running it

```bash
./ui-gate/ui-gate.sh /path/to/project    # the gate
./ui-gate/mutations.sh                   # proof each rule can fail
```

## The contract

`ui-gate.sh` prints `declared, ran, passed, failed, skipped` and fails unless
`ran + skipped == declared`. Every skip carries a rule ID and a reason.

The accounting is not decoration. A rule that throws mid-body, or sits inside a conditional with
no else, reports nothing at all, and a gate that cannot tell `passed` from `never ran` is the
exact defect this repository keeps finding in itself.

`mutations.sh` requires every blocking rule to have a mutation that makes it fail by name, applied
one at a time against a clean fixture. It reconciles its own rule list against the gate's declared
count and fails if they disagree, because the first version of that parse dropped `PERF-LAB` on a
trailing semicolon and audited eight of nine rules without noticing.

## Layout

`ui-gate.sh` declares the rule IDs and owns the accounting. It sources every file in
`ui-gate/rules/`: `rules/tokens.sh` holds the three enforced token rules, `rules/browser.sh` holds
the six that need a running browser and declares them as skips with their reasons. Adding a rule
means adding it to the declared list and to a file in that directory, and `mutations.sh` fails if
the two disagree.

## Rules

| ID | Holds | Status |
|---|---|---|
| `TOK-RAW-COLOR` | no `#hex`, `rgb()` or `hsl()` outside token sources | enforced |
| `TOK-ARBITRARY` | no arbitrary Tailwind values such as `mt-[13px]` | enforced |
| `TOK-TYPE-SCALE` | font sizes on 12/14/16/20/24/32/48 | enforced |
| `A11Y-AXE` | zero axe violations, WCAG 2.2 A and AA, per declared state | declared, needs a browser |
| `A11Y-KEYBOARD` | tab order, focus visibility, modal focus return | declared, needs a browser |
| `COV-STATES` | loading, empty, error, disabled, hover, focus-visible all exist | declared, needs a browser |
| `COV-VIEWPORT` | no horizontal overflow at 375, 768, 1440 | declared, needs a browser |
| `VIS-SNAPSHOT` | pinned screenshot diff, calibrated threshold | declared, needs a browser |
| `PERF-LAB` | LCP ≤ 2.5s, CLS ≤ 0.10, TBT ≤ 200ms, lab, median of 3 | declared, needs a browser |

Six of nine are declared and skipped. That is stated here, printed by the gate, and counted by the
mutation suite, because a family that is declared, skipped and quietly never implemented is how a
floor becomes a slogan. Each skip already carries the mutation it will need, taken from
[the specification](../docs/provenance/research-v1.7.0.md), so the falsifiability requirement is
written down before the rule exists rather than after.

## Why the thresholds are what they are

The type scale, the 4px spacing base and the contrast minimums match the standards `ui-engineer`
and `design-reviewer` build and review against, in `claude/agents/`. A gate that disagreed with the
agents would just generate work.
