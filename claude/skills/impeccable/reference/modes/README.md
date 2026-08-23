# Measured modes

Three reference sites, measured rather than described: computed styles read from a live browser,
pixel histograms, autocorrelation on canvas output. Adjectives were excluded on purpose. The one
head-to-head anyone has run on config-layer interventions found prose instruction without
retrieval made outcomes worse than no instruction (9.94% regression rate against a 6.08%
baseline) while the same instruction with retrieval context cut it to 1.82%. A mode file carries
numbers for that reason.

Sources: talk2hug.com, perseus.computer, forgeresidency.com, lighthousehq.com, measured 2026-08-23.

## What every one of them does

These held across all three. Treat a violation as a defect, not a choice.

**Weight carries no hierarchy.** `font-weight: 400` for every display and body element. Forge uses
500/600 on exactly two buttons and the wordmark. Hierarchy comes from size and tracking.

**Tracking is a monotonic function of size, locked in `em`.** Negative on display, zero in the
middle, positive on small uppercase. Measured curves:

| site | at display | crossover | at eyebrow |
|---|---|---|---|
| forge | −0.12em @ 400px | 0 @ ~20px | +0.22em @ 11px |
| perseus | −0.04em @ 124px | 0 @ 15–18px | +0.16em @ 10px |
| hug | −0.05em @ 48px | 0 @ 16px | +0.24em @ 14px |

Locked in `em` so the ratio survives a fluid resize untouched. Forge's mobile display is exactly
0.50× desktop with byte-identical tracking; that is why it does not read loose.

**Line-height inverts with size.** Display 0.88–0.95. Mid 1.35–1.5. Body 1.5–1.75. No exceptions
in any of the three.

**One accent hue, or none.** Perseus `#647fff`. Forge `#16a85a`. Hug has no type accent at all and
reserves pure `#ffffff` for a single line of stats. Everything else is a neutral ramp plus alpha.

**Ink is never pure white on a dark ground.** Hug `#f7f4ec` (4.3% warm). Perseus `#ecebf2` (cool).
Ground is never pure black: `#050505`, `#09090b`, `#060708`.

**Tight groups inside enormous silence.** The ratio is the signature, not any single value:
forge 7:1 (16px intra, 112–128px section), perseus 16:1 (1:1.5:3:5:16), hug 24:1 (8px to 192px).

**Measure under 60ch.** Forge 42–58ch. Perseus 55–62ch for prose. Hug 32.6ch. Machine output is
exempt and runs long on purpose (perseus terminal transcript at 134ch).

**Emptiness is the product.** Text ink coverage: hug 1.22% of hero pixels, forge 12–27% per
section, perseus ~20% of hero. Nothing here is dense.

**Motion has two bands and a hole.** Hover and colour 130–200ms. Entrance 420–760ms. Nothing
between 300 and 420ms in any of the three. Stagger steps are small and explicit: 45ms (forge),
75/80ms (perseus).

**prefers-reduced-motion is honoured structurally, not gestured at.** Hug removes the filter
entirely rather than freezing a distorted frame. Forge defines its marquee only inside
`@media (prefers-reduced-motion: no-preference)` so it never starts. Copy that, not a blanket
duration clamp.

## Where they diverge, and what that makes them

| | pixel | plate | editorial | scrollfield |
|---|---|---|---|---|
| reference | talk2hug | perseus | forge | lighthouse |
| base unit | 4px | **2px** | 4px | **2px** (8pt conformance 13%) |
| grain | feTurbulence `screen` .52 | feTurbulence `overlay` .06 | **none** | **none** |
| radius | 0 | 8 / 12 / 28 | **0 or 9999 only** | — |
| elevation | `blur(14px)` | `blur(56px)`, shadow `0 28px 80px/.76` | **zero shadows**, `ring-1` | 31× `backdrop-filter` |
| display tracking | −0.05em | −0.04em | −0.12em | **`normal`, even at 80px** |
| motion | CSS filter swap | mount-time entrances | IntersectionObserver | **`animation-timeline`, no library** |
| signature | `pixel.md` | `plate.md` | `editorial.md` | `scrollfield.md` |

`scrollfield` is the one exception to the tracking invariant above: it leaves display type at
`normal` and uses tracking only to open small mono caps. If you take that mode, take it whole.

Pick one. Averaging them produces the stock look with extra steps: the base unit, the grain and
the radius policy contradict each other directly, and a blend resolves each contradiction toward
the default.
