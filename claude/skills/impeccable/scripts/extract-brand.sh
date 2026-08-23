#!/usr/bin/env bash
# extract-brand.sh <url> [url...] — measure reference sites into a brand.json candidate.
#
# This replaces a corpus of frozen measurements. Four sites baked into a skill is a taste snapshot:
# it rots, it does not know the project, and it pushes every build toward whatever those four
# happened to do. The reusable asset is the measurement, not the measurements.
#
# What it reads is chosen because these are the properties that separated four expensive sites from
# a default build, and every one of them is a number a gate can enforce afterwards:
#
#   type scale        the sizes actually rendered, which is what TOK-TYPE-SCALE fails against
#   tracking curve    letter-spacing per size, in em, which is the property that survives resize
#   leading bands     line-height by size band; it inverts with size on every reference measured
#   measure           prose line length in ch
#   colour            ground, ink, the accent set, hairline alpha, and how many hues there are
#   spacing           the base unit inferred from a census, and the tight-to-open ratio
#   motion            transition durations and easing curves, grouped into bands
#   radius            the set in use
#
# Offline apart from loading the target. Uses agent-browser, which vstack already ships.
set -uo pipefail
command -v npx >/dev/null 2>&1 || { echo "needs npx" >&2; exit 2; }
npx --no-install agent-browser --version >/dev/null 2>&1 || { echo "needs agent-browser: npm i -g agent-browser" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "needs jq" >&2; exit 2; }
[ $# -ge 1 ] || { echo "usage: extract-brand.sh <url> [url...] > candidate.json" >&2; exit 2; }

ab() { npx --no-install agent-browser "$@" 2>/dev/null; }

# One page in, one JSON object out. Everything is read from getComputedStyle on elements that
# actually rendered, never from the stylesheet, because a rule that lost a specificity fight is not
# what the visitor saw.
PROBE='(() => {
  const els = [...document.querySelectorAll("*")].filter(e => {
    const r = e.getBoundingClientRect();
    return r.width > 0 && r.height > 0 && getComputedStyle(e).visibility !== "hidden";
  });
  const txt = els.filter(e => [...e.childNodes].some(n => n.nodeType === 3 && n.textContent.trim().length > 2));
  const num = v => parseFloat(v) || 0;
  const px  = v => Math.round(num(v) * 100) / 100;

  // type: size -> {tracking in em, leading ratio, weight, family, samples}
  const type = {};
  for (const e of txt) {
    const s = getComputedStyle(e), fs = px(s.fontSize);
    if (!fs) continue;
    const t = type[fs] ||= { em: [], lead: [], weight: {}, family: {}, n: 0 };
    t.n++;
    t.em.push(Math.round((s.letterSpacing === "normal" ? 0 : num(s.letterSpacing) / fs) * 1000) / 1000);
    t.lead.push(Math.round((num(s.lineHeight) / fs) * 100) / 100);
    t.weight[s.fontWeight] = (t.weight[s.fontWeight] || 0) + 1;
    t.family[s.fontFamily.split(",")[0].replace(/["]/g, "")] = 1;
  }
  const mode = a => a.sort((x, y) => a.filter(v => v === y).length - a.filter(v => v === x).length)[0];
  const scale = Object.keys(type).map(Number).sort((a, b) => a - b);

  // colour: count real hues, not declared tokens
  // Painted and read back, not parsed. getComputedStyle returns oklch() and color(srgb ...) on
  // modern sites; a regex over the digits turns oklch(0.98 0 0) into #010000, and canvas
  // fillStyle hands the same string straight back without converting it. Painting one pixel and
  // reading getImageData is the only path that resolves every notation the browser accepts.
  const _cx = document.createElement("canvas").getContext("2d", { willReadFrequently: true });
  _cx.canvas.width = _cx.canvas.height = 1;
  const _memo = new Map();
  const hex = c => {
    if (!c || c === "transparent" || c === "rgba(0, 0, 0, 0)") return null;
    if (_memo.has(c)) return _memo.get(c);
    _cx.clearRect(0, 0, 1, 1);
    _cx.fillStyle = "#000";
    _cx.fillStyle = c;
    _cx.fillRect(0, 0, 1, 1);
    const d = _cx.getImageData(0, 0, 1, 1).data;
    const out = d[3] === 0 ? null
      : "#" + [d[0], d[1], d[2]].map(n => n.toString(16).padStart(2, "0")).join("");
    _memo.set(c, out);
    return out;
  };

  const fg = {}, bg = {}, bd = {};
  for (const e of els) {
    const s = getComputedStyle(e);
    const fc = hex(s.color); if (txt.includes(e) && fc) fg[fc] = (fg[fc] || 0) + 1;
    const bc = hex(s.backgroundColor); if (bc) bg[bc] = (bg[bc] || 0) + 1;
    if (num(s.borderTopWidth) > 0) bd[s.borderTopColor] = (bd[s.borderTopColor] || 0) + 1;
  }
  const chroma = c => { const m = c.match(/^#(..)(..)(..)$/); if (!m) return 0;
    const [r,g,b] = m.slice(1).map(h => parseInt(h,16)); return Math.max(r,g,b) - Math.min(r,g,b); };

  // spacing census: what base unit is this actually on
  const vals = [];
  for (const e of els) { const s = getComputedStyle(e);
    for (const p of ["marginTop","marginBottom","paddingTop","paddingBottom","gap","rowGap","columnGap"]) {
      const v = Math.round(num(s[p])); if (v > 0 && v < 400) vals.push(v);
    } }
  const div = n => vals.length ? Math.round(vals.filter(v => v % n === 0).length / vals.length * 1000) / 10 : 0;
  const freq = {}; vals.forEach(v => freq[v] = (freq[v] || 0) + 1);

  // motion: durations and curves actually declared on rendered elements
  const dur = {}, ease = {};
  for (const e of els) { const s = getComputedStyle(e);
    s.transitionDuration.split(",").map(d => Math.round(num(d) * 1000)).filter(Boolean)
      .forEach(d => dur[d] = (dur[d] || 0) + 1);
    s.transitionTimingFunction.split(/,(?![^(]*[)])/).map(x => x.trim()).filter(x => x && x !== "all")
      .forEach(x => ease[x] = (ease[x] || 0) + 1); }

  const radius = {};
  for (const e of els) { const r = Math.round(num(getComputedStyle(e).borderRadius));
    if (r >= 0) radius[r] = (radius[r] || 0) + 1; }

  // measure in ch, per size, using the element own font
  const meas = {};
  for (const e of txt) { const s = getComputedStyle(e), fs = px(s.fontSize);
    const cv = document.createElement("canvas").getContext("2d");
    cv.font = `${s.fontWeight} ${fs}px ${s.fontFamily}`;
    const w = cv.measureText("0").width;
    if (w) (meas[fs] ||= []).push(Math.round(e.getBoundingClientRect().width / w)); }

  const top = (o, n) => Object.entries(o).sort((a,b) => b[1]-a[1]).slice(0, n);
  return {
    url: location.href, viewport: innerWidth + "x" + innerHeight,
    type: {
      scale,
      bands: Object.fromEntries(scale.map(s => [s, {
        em: mode(type[s].em), leading: mode(type[s].lead),
        weight: +top(type[s].weight,1)[0][0], family: Object.keys(type[s].family)[0], n: type[s].n }])),
      measureCh: Object.fromEntries(Object.entries(meas).map(([k,v]) => [k, mode(v)])),
    },
    color: {
      ink: top(fg,1)[0]?.[0], ground: top(bg,1)[0]?.[0],
      hues: [...new Set([...Object.keys(fg), ...Object.keys(bg)])].filter(c => chroma(c) > 18),
      foreground: top(fg,8), background: top(bg,8), borderTop: top(bd,4),
    },
    spacing: { divisibleBy2: div(2), divisibleBy4: div(4), divisibleBy8: div(8), top: top(freq,14) },
    motion: { durationsMs: top(dur,10), easing: top(ease,6) },
    radius: top(radius,6),
    density: { textNodes: txt.length, elements: els.length },
  };
})()'

echo "["
first=1
for url in "$@"; do
  [ $first -eq 1 ] || echo ","
  first=0
  ab set viewport 1440 900 >/dev/null
  ab open "$url" >/dev/null
  ab wait 1500 >/dev/null
  ab eval "$PROBE"
done
echo "]"
ab close --all >/dev/null 2>&1
