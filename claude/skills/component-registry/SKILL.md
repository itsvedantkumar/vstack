---
name: component-registry
description: Use before hand-writing any UI component in a React/Tailwind repo - pull a vetted, accessible primitive from a shadcn-compatible registry (npx shadcn add); hand-roll only what no registry has.
---

# Component registry

The setup has strong tooling for judging UI after it exists — screenshots, pixel-diff,
axe-core, design review. It had nothing for where a component comes from, so every combobox,
date picker, and dialog was hand-written from scratch and then critiqued into shape. Registry
components have already survived that critique: accessibility, keyboard handling, focus traps,
and edge states are solved before you start.

## Protocol

1. **Check the project speaks the protocol.** A `components.json` at the repo root means the
   shadcn CLI is wired; note its `style`, `tailwind.css`, and `aliases`. No `components.json`
   in a React + Tailwind repo? `npx shadcn@latest init` is cheap and non-destructive — ask
   nothing, run it, commit it with the component.
2. **Search before you write.** `npx shadcn@latest search <term>` queries the configured
   registries; `npx shadcn@latest view <item>` prints the source so you can judge it before
   adding. Anything `registry.json`-conformant works as a source, not just ui.shadcn.com —
   a URL or `@namespace/name` both resolve.
3. **Add, then adapt.** `npx shadcn@latest add <item>` vendors the source into the repo —
   it is yours to edit, not a dependency. Restyle it to the product; do not fork its
   accessibility wiring (aria attributes, focus management, keyboard handlers) without a
   reason you can state.
4. **Hand-roll only the gap.** If no registry has the primitive, write it — composed from
   registry primitives where possible — and say so in the commit message, because that is
   the signal a future session should re-check the registries.

## When this does not apply

- Not a React repo, or styling is not utility-class based: the protocol is React-shaped;
  skip it rather than force it.
- Truly bespoke, brand-defining pieces (hero animations, one-off marketing layouts): the
  `impeccable` skill owns those; registries would fight it.
- The repo already has its own design system package: its components outrank any registry.

After adding, the normal loop applies: `ui-iterate` to verify it renders right at every
breakpoint, `impeccable` if the surface is brand-critical.
