# plate

Measured from perseus.computer, 2026-08-23. Painted plate, instrument panels, bitmap serif.

## Signature: a display face quantized to 32 units per em

Not a filter, not `image-rendering`, not canvas. The font outlines themselves are on a 32/em grid.
Verified by rendering `O` at 600px to an offscreen canvas and measuring left-edge run lengths:
every step is exactly `600/32 = 18.75px`, both axes. `filter: none`, `image-rendering: auto`.

**Step size = font-size / 32.** That single relation is the whole aesthetic:

| use | font-size | step | reads as |
|---|---|---|---|
| nav wordmark | 30px | 0.94px | clean serif |
| section h2 | 62.4px | 1.95px | slightly crunchy |
| hero h1 | 102.4px | **3.2px** | overt bitmap/CRT |
| footer wordmark | 123.84px | **3.87px** | fully pixel |

One face, no variants. Scale alone flips it between Renaissance book and 1980s terminal. Shipped
as TTF while every other font is woff2 — outline complexity defeats woff2 compression.

At 375 the h1 step drops to 1.45px and the effect nearly vanishes. **The signature is
desktop-only and degrades to a normal high-contrast serif rather than breaking.**

## Supporting moves in the same grammar

**ASCII mosaic canvas.** `<canvas aria-hidden>` at DPR2, painted once at mount and never
repainted — verified by patching `fillText`/`fillRect` and observing zero subsequent calls.
Autocorrelation gives a cell pitch of 5.85 × 11.8 device px, a ~379 × 132 grid, ~50k glyphs in a
mono face, drawn 2–4% above the `#0d0d0f` ground. An oil painting rendered as ASCII at
near-invisible contrast. Because it never animates, it is reduced-motion-safe by construction.

**Pixelated painting textures.** `image-rendering: pixelated` with
`filter: brightness(.54) saturate(.78)`, `opacity: .66`. At 375 the source scales up so the mosaic
blocks get ~4× larger — the texture is more legible on mobile, reading as a different artwork.

**Real paintings with credits**, each in a monospace 12px attribution line inside a fake terminal
titlebar.

## Type

Four families: a 32/em display serif, a variable sans for body and UI, a mono for numerics and
file paths, and a system mono (`SF Mono`) for anything meant to read as a terminal.

**Two ratio regimes, not one scale.** Display steps 1.21 / 1.64 / 1.28 (dramatic). UI steps
1.07–1.10 across 10/11/12/13/14/15/16/18 (near-continuous). The 22 → 30 → 48 gap is the
deliberate silence between them.

| px | line-height | tracking |
|---|---|---|
| 123.84 | 0.95 | −0.04em |
| 102.4 | **0.92** | −0.025em |
| 62.4 | 1.04 | −0.02em |
| 18 | 1.56 | 0 |
| 15 / 13 | **1.625** | 0 |
| 10 uppercase | 1.0 | **+0.16em** |

Prose measure 55–62ch. **Machine output is exempt and runs to 134ch on purpose** — it is meant to
read as output, not prose.

## Colour

13-step neutral ramp, all with R≈G and B +5–9: `#09090b` page, `#0d0d0f` surface, `#121213`,
`#151516`, `#17171a`, `#1e1e22`, `#42424a`, `#5a5a63`, `#74747d`, `#9a9aa3`, `#b7b6c0`, `#d6d5de`,
`#ecebf2` ink.

One accent at four stops: `#c2ceff` → `#a6b6ff` → `#879bff` → `#647fff`.

**The most-used colour on the page is `rgba(236,235,242,0.08)` — 1033 occurrences.** Ink at 8% as
every hairline and divider. There are no solid grey borders anywhere.

Grain: `feTurbulence fractalNoise baseFrequency 0.85 numOctaves 2 stitchTiles=stitch`, desaturated,
160×160 tile, **`opacity: .06` with `mix-blend-mode: overlay`** (footer uses `soft-light`).

Gradients are scrims and edge-lights, never decoration: a 112px top scrim, a 176px bottom scrim, a
**1px top edge-light** on every card (`linear-gradient(to right, transparent, rgba(255,255,255,.25), transparent)`),
and a 30%-height inner top glow at `rgba(255,255,255,.05)`. The primary button is
`linear-gradient(157deg,#fff,#eaf0ff 44%,#c2ceff)` — cold-white metal, not a colour.

Elevation `backdrop-filter: blur(56px) saturate(1.5)`; deepest shadow
`0 28px 80px rgba(0,0,0,.76)` — very large blur, high alpha, **zero spread**.

## Spacing

Base **2px**, not 4 or 8. Census over every element: multiples of 2 = 85.8%, of 4 = 59.2%, of 8 =
32.3%. Frequency: `8(225) 6(175) 12(162) 1(153) 4(111) 10(94) 16(77) 24(23)`. The volume of 6 and
10 is what breaks the 8-grid, plus 153 uses of 1px for hairlines.

**Gap ratio 1 : 1.5 : 3 : 5 : 16** — 6–8px inside a line, 12px between siblings, 24px between
groups, 40px between blocks, **128px between sections**. The 40 → 128 jump with nothing between is
the move: the page is either tight or completely open. No 64 or 80px tier does intermediate work.

Radii 8px (18×), 12px (11×), 10px (5×), 18, 22, 28, 9999. Panels 28, inner cards 12, chips 8.

Container `max-width: 1240px`, 64px inline padding at ≥lg. Prose capped 992px / 672px.

## Motion

Five curves assigned by intent, not taste:

| curve | role |
|---|---|
| `cubic-bezier(.4,0,.2,1)` | colour micro-transitions |
| `cubic-bezier(.25,1,.5,1)` | hover scale, transforms |
| `cubic-bezier(.16,1,.3,1)` | **entrances and reveals** |
| `cubic-bezier(.32,.72,0,1)` | nav open |

Hover and colour **130–200ms**. Entrance **420–760ms**. **Nothing between 300 and 420ms except the
nav.** Two transitions use different durations for opacity and transform on the same element
(420/560, 360/240) — opacity leads, transform trails.

Stagger via explicit `transition-delay`: 0/75/150ms and 0/80/100/160ms.

Caret blink is **1.06s `steps(1)`, deliberately not 1.0s**, so multiple carets drift out of phase.

Footer wordmark: two gradients clipped to text, a static vertical fade plus a 7.5s linear specular
sweep across 123.84px letterforms, `background-size: 240% 100%`.

Nav hides on scroll-down with `translateY(-135%)` — overshoot past its own height so the shadow
clears — over 360ms `cubic-bezier(.16,1,.3,1)`, behind a 140px gradient scrim on a transparent
68px bar.

**No scroll-linked transform, no parallax, no IntersectionObserver reveal.** The 700ms entrances
are mount-time.

## Structure

Hero `min-h:100svh` but **actual height 1.76× viewport** — the fold shows the painting and h1; the
comparison panes sit inside the same section, below the fold. The first scroll lands you still
inside the hero.

Layout is flex-dominant: 161 flex containers against 4 grids. The main grid is an explicit
`610px 610px` with 28px gap inside a 1240px shell, not `1fr 1fr`.

Hero content covers 19.4% of its box. Below the fold, density rises sharply — the page reads as
one enormous empty painted plate, then dense instrument panels.

At 375 the two-pane comparison becomes a single pane with a 52×28px pill toggle and three
dedicated keyframes. That is a different product decision, not a breakpoint.

## Dead code observed

`geistSans` is declared and never loads. `@keyframes perseus-art-pan` is defined and used by zero
elements. Do not carry either forward.
