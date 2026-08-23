# scrollfield

Measured from lighthousehq.com, 2026-08-23. Scroll-bound reveals, page-wide colour field, no
motion library.

## Signature: reveals bound to scroll position, not to a clock

No GSAP, no Framer Motion, no Lenis, no ScrollTrigger, no IntersectionObserver stagger. 15 rules
use native `animation-timeline`.

```css
.hero-bg--video > video {
  animation-name: hero-video-scroll;
  animation-timeline: scroll(root);
  animation-range: 0px 900px;
  animation-timing-function: linear;
  animation-fill-mode: both;
}
@keyframes hero-video-scroll {
  0%   { filter: brightness(1) saturate(1);      transform: translateZ(0) scale(1.04) }
  100% { filter: brightness(.55) saturate(.2);   transform: translate3d(0,120px,0) scale(1.02) }
}
```

Over the first 900px the hero video drains to near-greyscale, dims 45%, drifts 120px and un-zooms,
while a black wash deepens 30% → 56% on the same timeline. Scroll back and the colour returns.

**Stagger is encoded as range offsets, not delays:**

```css
animation-range: entry  4% cover 24%;
animation-range: entry  5% cover 27%;
animation-range: entry  6% cover 28%;
animation-range: entry 10% cover 32%;
animation-range: entry 15% cover 37%;
```
```css
@keyframes appear-settle {   /* 1.25s cubic-bezier(.16,1,.3,1) */
  0%   { opacity:.001; transform: translate(var(--appear-x,0),var(--appear-y,0)) scale(var(--appear-scale,1)); filter: blur(8px) }
  100% { opacity:1;    transform: translate(0,0) scale(1); filter: blur(0) }
}
```

Because each element binds to **its own** viewport position, elements mid-transition coexist at
different opacities and blur amounts while scrolling — buttons fully resolved beside a paragraph
still at ~15% opacity and blurred. **A timer-based IntersectionObserver stagger cannot produce
that state.** It is the whole effect.

Guarded by `@supports (animation-timeline: view())` with `.reveal { animation: none }` fallback.

## Page-wide colour field

```css
.page-color-field { position: fixed; inset: 0; z-index: 0; pointer-events: none;
  background-color: var(--page-background-color, var(--bg));
  transition: background-color .76s cubic-bezier(.16,1,.3,1) }
```

One `aria-hidden` div behind everything. JS sets `--page-background-color` / `--page-ink-color` per
active section and the whole page cross-fades palette in 760ms. **Every section is
`background: transparent` — nothing paints its own background.** Five named palettes:
`wheat, dark-brown, warm-slate, limestone-blue, patina`. Observed `#201E1D`, `#1E2A2F`, and a sage
light theme with ink `rgb(221,221,213)`.

## Type

Four families: a neutral sans, a serif **italic only**, a mono, and a second mono reserved for
numerals.

**The lockup switches family mid-headline** — line 1 serif italic, line 2 sans, identical size and
line-height, 0px gap, marked up as `<p>` + `<h1>`.

**No constant ratio.** 20 sizes, per-step ratios 1.05 to 1.60. The rule is tier separation:

| relation | ratio |
|---|---|
| display : body | **4.44×** (80 : 18) |
| section head : body | 2.78× (50 : 18) |
| body : meta | 1.64× (18 : 11) |

The 22–31px band carries only proper nouns and codes, never running text, so 50 → 18 is
essentially unbridged.

**Tracking is the inverse of the usual convention.** `normal` on everything ≥13px **including 80px
display** — zero negative tracking on large type, leaning on the typefaces instead of optical
correction. Positive tracking only opens small mono caps: +0.01em at 12px, +0.04em at 11px.
One exception, a 19px footer heading at −0.01em.

**Line-height is three flat values, not a curve:** 1.10 for everything ≥20px, 1.20 for 15–18px,
1.40–1.50 for long-form 10–16px.

**Measure 32–37ch typical, 49ch max** — roughly half the conventional 65–75ch. With 1.20 leading,
that is a large part of the expensive read.

Display type is `clamp()` on vw; body type is fixed px and does not scale at all.

## Colour

**19 custom properties, 3 of them hues:** `#181818` ground, `#fff` ink, `#ffb44f` accent.
Everything else is white-at-alpha.

**The accent appears exactly once as text on the entire homepage.** Borders are one value,
`white/.22`, on 61 of the 65 elements that carry one.

Body copy `white/.58` = **6.63:1**. All text clears AA.

**No grain, no noise.** 292,468 characters of CSS grepped: zero hits for `noise`, `grain`,
`fractalNoise`, `feTurbulence`. All texture is real video and WebGL fog.

Depth comes from **31 `backdrop-filter` declarations** — `blur(18px) saturate(1.35)`, `blur(10px)`,
`blur(6px)` — plus element filters `brightness(.42) saturate(.78) contrast(1.04)` on card video.
Only 3 `mix-blend-mode` uses. Two `background-image` values on the whole page, both hairlines faked
as gradients.

## Spacing

**Base 2px. There is no 4pt or 8pt grid** — of 610 measured values, 79.3% divide by 2 but only
**13.4% by 8**. Frequency: `22×68, 12×68, 14×56, 10×55, 7×49, 18×43, 20×42`. The presence of 7, 11,
25, 31 shows hand-tuning, not generation.

**Hierarchy 0 : 16 : 38 : 84 → ratios 0 : 1 : 2.4 : 5.2 : 10.** The two-line headline sits at
literally **0px gap**, then jumps 2.4× to the next group. Absolute values matter less than the rule
that the smallest meaningful step is 16 and every escalation is ≥2×.

Section padding is **asymmetric and never equal**: 72–90px top, 64–84px bottom.

Container 1280px with **80px gutters drawn as visible vertical hairlines** — the frame is the
layout, made literal. Grid for layout, flex only for the accordion.

**Mean text ink 11.5% per section; 88% is not text.** Densest section 19.3%.

## Motion

**One house curve.** Of 260 transition declarations, `cubic-bezier(.16,1,.3,1)` carries **125
(48%)**. `ease` is reserved for opacity and background micro-states. `linear` appears only on
scroll-linked timelines.

**Durations are bimodal with nothing in the middle:** micro 120–180ms (73 uses at 180ms), macro
520–760ms (76 uses at 760ms). Nothing meaningful at 300ms.

`font-size, line-height` transitions at 520ms expo-out — the accordion headings grow rather than
swap. Numbers roll on a 2.2s digit-strip settle.

`html { scroll-behavior: smooth }` and no scroll-jacking library.

## Defect in the source, do not copy

**`prefers-reduced-motion` coverage is partial.** Six targeted blocks exist, and they do not cover
the hero scroll desaturation, any `appear-settle` reveal (blur plus translate), the 1.15s logo
crossfade, the 2.2s number roll, the colour-field transitions, or the 60fps WebGL scene with a
mouse-reactive trail left enabled on touch. There is no global reset. A reduced-motion user gets
nearly the full experience.

If you take this mode, gate the scroll timelines the way `editorial` gates its marquee: define
them only inside `@media (prefers-reduced-motion: no-preference)` so they never start.
