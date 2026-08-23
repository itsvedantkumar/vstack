# pixel

Measured from talk2hug.com, 2026-08-23. Deep field, one display size, analog jitter.

## Signature: four pre-baked SVG filters swapped by a steps() keyframe

No canvas, no WebGL, no JS. Four identical `feTurbulence` filters differing only in `seed`, cycled
by a CSS animation on exactly one element.

```html
<svg width="0" height="0"><filter id="jitter-0" x="-5%" y="-5%" width="110%" height="110%">
  <feTurbulence type="turbulence" baseFrequency="0.04" numOctaves="3" seed="3"/>
  <feDisplacementMap in="SourceGraphic" scale="3" xChannelSelector="R" yChannelSelector="G"/>
</filter></svg>  <!-- seeds 3, 10, 17, 24 -->
```
```css
@keyframes jitter { 0%,24.9%{filter:url(#jitter-0)} 25%,49.9%{filter:url(#jitter-1)}
                    50%,74.9%{filter:url(#jitter-2)} 75%,99.9%{filter:url(#jitter-3)} }
.jitter { animation: jitter .4s steps(1) infinite; will-change: filter }
@media (prefers-reduced-motion:reduce){ .jitter{ animation:none; filter:none; will-change:auto } }
```

Load-bearing numbers:
- **400ms / 4 steps = 100ms per frame = 10fps.** The traditional-animation "boil" rate. Smooth
  would read as a wobble filter; 10fps reads as hand-inked. Do not tween this.
- **Seeds spaced 7 apart** so consecutive noise fields are decorrelated.
- **`scale: 3` against 48px type ≈ 6% of cap height.** Analog, still legible.
- Applied to **one element only**. Two jittering elements reads as a broken renderer.

Reduced motion removes the filter, it does not freeze a frame.

## Grain is the same primitive

```css
background-image: url("data:image/svg+xml,<svg …><filter id='g'>
  <feTurbulence type='fractalNoise' baseFrequency='1.15' numOctaves='4' seed='9' stitchTiles='stitch'/>
  <feColorMatrix type='saturate' values='0'/>
  <feComponentTransfer><feFuncA type='gamma' amplitude='2.6' exponent='5' offset='-0.42'/></feComponentTransfer>
</filter>…</svg>");
mix-blend-mode: screen; opacity: .52; background-size: 22rem 22rem;
```
**`exponent: 5` is the number that matters** — it crushes the histogram so only the top few percent
survive as sparse specks. That is the starfield. `background-size` is fixed, so star size stays
constant across breakpoints; do not make it relative.

## Type

Two faces. A pixel/square face carries every structural voice (kicker, h1, stats, buttons,
footer eyebrow); a neutral sans carries running body only.

| role | px | line-height | tracking |
|---|---|---|---|
| h1 | 48 → 36 @375 | **0.95** | **−0.05em** |
| stat | 20.8 | 1.35 | 0 |
| body | 16 | **1.625** | 0 |
| eyebrow | 14 | 1.43 | **+0.24em**, uppercase |
| consent | 12 | 1.67 | 0 |

**There is no modular scale and that is the point.** Steps run 1.167, 1.143, 1.30, then **2.31**.
One display size, a flat utility band, and a hole where 24/32 would be. No h2, no h3.

Measure 32.6ch at 1440 — a `max-w-sm` (384px) column on a 1440 viewport, 28% of the width.

## Colour

Ground `#050505` neutral. Ink `#f7f4ec`, `hsl(44,39%,95%)`, 4.3% warm. Pure `#ffffff` reserved for
one line. Alpha ramp on the cream: .88 .78 .74 .68 .66 .60 .58 .54 .50 .46. Hairlines white
.06–.24.

Chroma lives in one blurred screen layer that never touches type:
```css
.glow{ filter:blur(12px); mix-blend-mode:screen; opacity:.42;
  background:radial-gradient(at 50% 34%,#b8deff33,#0000 46%),
             radial-gradient(at 50% 78%,#ffb87038,#0000 42%),
             radial-gradient(at 18% 62%,#ff806829,#0000 34%),
             radial-gradient(at 82% 62%,#ffaa7029,#0000 34%) }
```
Composited effect: top `#060909` (B−R +3), bottom `#0e0b07` (R−B +7). A ~10-point vertical
temperature gradient. Cool sky, warm horizon, neutral ground.

71.7% of pixels fall in the `#000` bucket. 89.8% in the four darkest.

## Spacing

Base **4px**, not 8 — 28 and 20 are both in use. Observed: 8 12 16 20 24 28 32 40 48 192.

Hero rhythm: `kicker →8 h1 →12 · h1 →28 label →8 stat →24 body →32 buttons →24 consent`.

Related:unrelated is **3.0:1** (8px label-to-stat against 24px stat-to-block). Section gap
`max(12rem, 21svh)` = 192px. Full range **8px to 192px = 24:1**.

## Structure

Hero `min-height:100dvh`, exactly 1.00 viewport. Content container `max-w-md` 448px, rendered 403px
after a `transform: scale(.9)` on the panel, with `translateY(clamp(-3rem,-5dvh,-1.5rem))` at
≥768px — measured −37.3px. **Content is drawn at 90% and lifted above optical centre.** Below
768px the lift goes to zero and it centres.

Buttons: grid `repeat(3,minmax(0,1fr))`, 12px gap, 96px tall, `border-radius: 0`,
`backdrop-filter: blur(14px)`, `background: rgba(10,10,10,.26)`, `border: 1px solid rgba(255,255,255,.24)`,
`box-shadow: inset 0 1px rgba(255,255,255,.1)`. Square corners plus an inset top highlight is the
entire glass treatment.

**Ink coverage 1.22% at 1440.** 98.8% empty field. At 375 it rises to 3.75% — 3.1× denser, and the
biggest perceptual difference between the breakpoints.

## Motion

Six declarations total. `filter` 400ms `steps(1)` infinite. Colour transitions 150ms
`cubic-bezier(.4,0,.2,1)`, 200ms and 250ms `ease`. **No scroll listener, no IntersectionObserver,
no parallax, nothing reveals.** `scroll-behavior: auto`.

## Known defect in the source, do not copy

The background video was not muxed with `+faststart` — `moov` sits in the last 0.05% of a 4.1MB
file, so the first frame is gated on the whole download. It never reached `readyState 1` in two
loads and froze the renderer for >45s. Every number above describes the CSS-only render, which is
also what a first-time visitor sees.

Contrast: the 12px consent line at 46% alpha measures **4.34:1** and fails AA. Do not reproduce.
