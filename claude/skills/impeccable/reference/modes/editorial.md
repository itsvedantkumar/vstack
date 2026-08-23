# editorial

Measured from forgeresidency.com, 2026-08-23. Pinned painting, poster typography, no texture.

## Signature: a sticky zero-copy hero the page scrolls over, not past

```html
<div class="sticky top-0 z-0 h-[100svh] overflow-hidden">
  <div class="absolute inset-x-0 -top-[3svh] -bottom-[10svh]
              sm:-top-[4svh] sm:-bottom-[13svh]" style="transform: scale(1.02)">
    <img class="object-cover object-[center_46%] sm:object-center" sizes="100vw">
  </div>
  <!-- 224px scrims top and bottom: linear-gradient(rgba(0,0,0,.65), transparent) -->
</div>
<div class="relative z-10 bg-[#060708]">  <!-- opaque curtain, everything else -->
```

Proven static: `img.getBoundingClientRect().top` = **−47px at scrollY 0, 200, 400, 600, 800**. The
image never moves. **No parallax JS, no canvas, no WebGL, no video.** The effect is one painting,
overscanned to 1.17× viewport height with `scale(1.02)`, and an opaque curtain sliding over it.

**Zero copy on the hero.** No h1, no tagline. Wordmark, nav, and a floating stats bar. The top 87%
is image.

`svh` not `vh` — no mobile URL-bar jump.

## Supporting moves

**Ghost numerals bleeding out of containers.** A 400px numeral at `rgba(255,255,255,0.045)` and a
144px one at `0.025`, behind live content, clipped by `overflow-hidden`. This is what reads as
editorial poster.

**Nav that shrinks its own container.** `max-width: 80rem → 64rem` plus `padding-block: .75rem →
.5rem` over **620ms `cubic-bezier(.22,1,.36,1)`**, with hide-on-scroll-down at `translateY(-95.4px)`.

**Cursor spotlight on rows.** `background: radial-gradient(280px circle at <x>px <y>px,
rgba(10,11,12,.1), rgba(10,11,12,.025) 42%, transparent 72%)` on a `pointer-events-none absolute
inset-0` layer, `opacity: 0` at rest.

**Count-up numerals** on `tabular-nums`, IntersectionObserver-triggered, ease-out over ~1.2–1.6s.
Constant not extractable from the minified bundle; treat as approximate.

## Type

Four webfonts, but **the serif editorial voice is not a webfont** — long-form body uses a system
stack (`"Iowan Old Style", "Palatino Linotype", Palatino, serif`). Zero bytes.

**19 distinct `clamp(min, Nvw, max)` definitions and no shared ratio.** Measured adjacent steps
give 1.79, 1.56, 1.43, 1.01, 1.22, 1.14, 1.02 — bespoke per block. Do not reverse-engineer a
scale; copy the bands.

| band | px @1440 | @375 | tracking | line-height |
|---|---|---|---|---|
| ghost numeral | 400 / 224 / 144 | 256 / 112 / 88 | −0.12 / −0.10 / −0.08em | 1.0 / 0.68 / 1.0 |
| display | 100 | 49.6 | −0.060 → −0.068em | **0.88** |
| stat numeral | 70–82 | 33.6–43.2 | −0.065 → −0.070em | 1.0 |
| section head | 46–58 | 24.8–34.4 | −0.050 → −0.055em | 0.92–0.98 |
| lede | 22–25 | 22–25.6 | 0 → −0.025em | **1.5** |
| body | 16–18 | 16–18 | **0** | **1.55–1.75** |
| eyebrow | 10–11 | **9–10** | **+0.15 → +0.22em** | 1.5, uppercase |

Curve: **−0.12em at 400px, crossing 0 at ~20px, +0.22em at 11px.**

**`font-weight: 400` for every display and body element.** 500/600 appear only on the wordmark and
two buttons. **All display copy is lowercase with a terminal period**: "results so far.",
"cohorts.", "four chapters."

Measure capped at 448px / 512px — **42ch at 16px, 58ch at 18px, 38ch at 25px serif.** Under 60
everywhere.

Display halves at 375 (100 → 49.6px, exactly 0.50×) while tracking stays byte-identical in `em`.
That is why the mobile type does not read loose.

## Colour

| role | hex |
|---|---|
| ink / page | `#060708` |
| paper | `#ffffff` |
| **accent, the only hue** | `#16a85a` |
| ink on accent | `#061008` |
| muted | `#8a9099` dark / `#6b7280` light |

**Real hue count: 2.** Everything else is alpha steps of white and black.

**No grain, no noise, no film overlay, no blend modes anywhere.** Four gradients total, all
functional scrims. This is the mode that proves texture is optional.

**Zero elevation shadows.** One `shadow-2xl shadow-black/20` on the stats bar and nothing else.
Depth comes from `ring-1 ring-white/10` hairlines and `backdrop-blur(12px)`.

**Radius is binary: 551 elements at 0px, 14 at 9999px. Nothing between.**

Contrast: white on `#060708` = 20.16:1. `#6b7280` on white = **4.83:1**, passing AA only just —
tighten if you copy it.

## Spacing

Base **4px**. Census of 477 values: 83% multiples of 4, 53% of 8, 99% of 2. Non-4 values (6, 10,
14, 44, 3) are Tailwind half-steps.

Frequency: `16(70) 24(48) 32(48) 20(47) 12(44) 6(40) 40(31) 8(28) 28(26) 10(21) 4(18)` — then a
gap — `56(8) 112(5) 128(4)`.

**Section padding 112–128px against 16px intra-group. Ratio 7:1.** Sub-blocks 56–80px.

Container `max-width: 1280px`, gutters 24px → 40px. At 1440 the first text pixel lands at
**x = 131px**.

109 flex containers against 31 grids. One 6-column explicit grid (`42px 379.9 422.1 72 90 38`) for
table rows.

**Text ink coverage 12–27% per section → 73–88% empty.** The two accent-colour sections run 27%
and 48% — the only dense moments, deliberate loud beats between quiet ones.

## Motion

| property | duration | easing | n |
|---|---|---|---|
| colors | **150ms** | `cubic-bezier(.4,0,.2,1)` | 33 |
| all | 300ms | `cubic-bezier(.4,0,.2,1)` | 19 |
| opacity + transform | **500ms** | `cubic-bezier(.4,0,.2,1)` | 12 |
| transform | **700ms** | `cubic-bezier(0,0,.2,1)` | 8 |
| nav shell | **620ms** | `cubic-bezier(.22,1,.36,1)` | 1 |

**Stagger step 45ms** (0/45/90/135) on 500ms transforms.

**One `@keyframes` on the entire page** — a partner marquee, 46s linear infinite, 34.3 px/s, 38s
at mobile.

Reveals are IntersectionObserver with **`rootMargin: "240px 0px"`** — they fire 240px before
entry, so nothing is ever caught mid-animation. Pre-reveal state is inline
`opacity:0; transform:translateY(Npx)` with N ∈ {3,14,16,18,20,22,24,28}. The 3px variant appears
10× as a near-imperceptible settle on list rows.

Fixed scroll-progress bar: `h-px origin-left`, `transform: scaleX(progress)`, `z-[100]`.

**Reduced motion is structural.** The marquee is defined *only* inside
`@media (prefers-reduced-motion: no-preference)`, so it never starts rather than starting and
being clamped. Copy that pattern.

## Breakpoint behaviour worth copying

The nav **loses its links entirely and gains no hamburger** — mobile nav is wordmark plus one
pill. The hero image **re-crops** (`object-[center_46%]` → `sm:object-center`) rather than
letterboxing. Cohort rows swap to a **separately authored** compact block, not a rearranged one.
Smallest type drops to 9px, below the desktop floor.
