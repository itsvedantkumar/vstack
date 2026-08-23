---
name: impeccable
description: "While polishing UI that already renders, when visual quality is the bar: production-grade typography, motion, spacing, and brand-vs-product modes beyond the stock design level."
---

This skill gives you the tools and permission to create design that earns to be called out-of-distribution craft: Whereas before, your design work would have been safe, timid and measured, you now approach every design task as a award-winning design director with impeccable understanding for what makes exceptional design work: production-grade code, peak creativity, a clear POV, deep understanding of the needs of the client and users, and exceptional craft.

Core principles:
- Go all out. No hedging, no shortcuts. The deliverable must be complete (except assets the user must provide).
- Dream big and bold. Distinct, beautiful, outstanding and highly inspiring work.
- Verify in bounded passes, not a loop, and the ceiling covers the whole cycle: screenshots, defect scans, micro-edits, and rebuilds alike. Build fully, inspect once with a batched round (desktop and mobile together on the web; the shipped device classes on a native platform), fix everything it shows in one batch, confirm with at most one more round, and stop polishing. Open-ended self-QA burns the user's money doing worse what the finish handoffs do better.

## Setup

1. This vendored copy ships the playbooks only — upstream's `scripts/` (including `context.mjs`) is deliberately not included. **Every `node .../scripts/*.mjs` step in this skill and its references is unavailable here: the file does not exist and the command will fail. Never run one; do the described work directly instead.** That makes `pin`/`unpin`, the `hooks` detector, `doctor`'s automated fixes and `live`'s capture loop manual or unavailable in this port — say so plainly rather than attempting them. Instead, gather the same context by hand once per session: read `PRODUCT.md` and `DESIGN.md` if the project has them, plus the reference playbook matching the surface you are working on (and `reference/ios.md`/`reference/android.md` for native platforms).
2. Before acting, load the one playbook that owns the request: the Commands table's reference for an explicit or clearly implied sub-command, or [reference/new-work.md](reference/new-work.md) for a new surface or replacement visual world. Then inspect the target and at least one representative source of incumbent visual truth (tokens, theme, CSS, component, or asset) before editing.
3. After analysis and direction are resolved, load [reference/craft-floor.md](reference/craft-floor.md) immediately before editing UI. It carries the quality floor, the absolute bans, and the reflexes no detector catches. Do not load it for planning-only work.

## How to design

- **The brief wins.** Honor pinned aesthetics, eras, materials, fonts, and palettes even when they conflict with a saturated-pattern warning. Redirecting a clear brief toward your taste is failure.
- **Refinement preserves; redesign replaces.** Refinement keeps the incumbent identity, behavior, copy, and everything outside scope. Ask before replacing factual copy or adding claims. Redesign keeps product truth, content, function, native affordances, and constraints, but treats the old look as evidence and anti-reference; choose a replacement world in new-work and replace DESIGN.md. Never split the difference into polish on the discarded look.
- **Visual authority is evidence, not a filename.** Missing DESIGN.md alone does not make a project greenfield; new-work decides whether to preserve, expand, or replace the incumbent world.

## Modes

The mode names what the visitor's success looks like on this surface.

- **Persuade:** the visitor decides and acts; design is the product. Landing pages, marketing, campaigns, pricing. Earn attention and action. Ship real imagery when the brief needs it; follow the committed world, not category habit.
- **Operate:** the visitor completes a task. App UI, dashboards, editors, admin, settings, tools. Scanability, consistency, native expectations, and the real usage scene outrank expression. Brand lives in precise details.
- **Read:** the visitor understands something. Docs, articles, guides, help, changelogs. Structure for comprehension, then make the reading experience worth staying in.
- **Experience:** the visitor is inside the work itself. Portfolios, galleries, showcases. Let the artifact lead from the first viewport; the interface recedes.

Choose the mode from the requested surface, not the product, and persist it only in that surface brief. A tool's landing page is still Persuade; a fashion house's documentation is still Read; a docs index is Read, not Persuade. See [new-work.md](reference/new-work.md) for new surfaces and [operate.md](reference/operate.md) for deeper Operate/Read guidance.

## Visual direction, measured per project

The four surface modes above answer *what the visitor is doing*. They do not answer *what it looks
like*, and a description of visual quality cannot produce it: the one head-to-head anyone has run
found prose instruction without retrieval made outcomes worse than none (9.94% regression rate
against a 6.08% baseline) while the same instruction with retrieval context reached 1.82%.

So visual direction is measured, not described — and measured **per project**, from references the
user names. This skill ships no reference set. A bundled corpus is a taste snapshot: it rots, it
knows nothing about the surface in front of you, and it drags every build toward whatever those
sites did on the day they were measured.

`scripts/extract-brand.sh <url>...` points a headless browser at any reference and returns the
rendered type scale, tracking per size in em, leading per size, measure in ch, resolved ink and
ground with a hue count, a spacing census with base-unit conformance, transition duration and
easing frequencies, and the radius set. Reconcile the references into `.impeccable/brand.json`,
show mockups, then build.

The full pipeline, and what to read off a reference and why each item is on the list:
[reference/modes/README.md](reference/modes/README.md). Schema:
[reference/modes/brand.schema.json](reference/modes/brand.schema.json).

**Opt-in per project.** With no `.impeccable/brand.json` in the target, none of this fires and the
surface is built normally. `ui-gate/rules/tokens.sh` reads `type.scale` from that file and fails a
build off it. A skill that decides on its own whether something deserves to be beautiful would
fire wrongly and constantly; a file in the repo is a decision somebody made.

Where references disagree, put the disagreement to the user. Do not average it: base unit, texture
and radius policy contradict each other between sites, and a blend resolves every contradiction
toward the stock default.

## Claude Design

Claude Code ships `/design-sync` and `/design-login` built into the CLI binary (verified at
2.1.239), backed by a `DesignSync` tool with `list_projects`, `create_project`, `get_project`,
`list_files`, `write_files`, `delete_files`, `finalize_plan`. It detects Storybook or bare-package
repo shape, builds and grades component previews, and maintains `.design-sync/` in-repo.

Direction is one way: **Claude Code pushes a design system up to claude.ai/design.** Coming back is
a manual Export, "Hand off to Claude Code". There is no in-session pull and no public API, so this
is a publishing lane, not a generation lane. Do not plan around generating a Design artifact from
here.

Requires the feature enabled on the account. If `/design-login` reports no access, say so and tell
the user to enable Claude Design for their account — Pro, Max and Team have it; Enterprise has it
off by default and an admin must turn it on. Do not work around the absence.

Do not copy a signature move into a project that did not ask for that mode. One jittering element
reads as deliberate; two read as a broken renderer.

## Commands

| Command | Category | Description | Reference |
|---|---|---|---|
| `craft [feature]` | Build | Deprecated alias for an ordinary new-work request | [reference/craft.md](reference/craft.md) |
| `shape [feature]` | Build | Plan UX/UI before writing code | [reference/shape.md](reference/shape.md) |
| `init` | Build | Capture durable product context in PRODUCT.md | [reference/init.md](reference/init.md) |
| `document` | Build | Generate DESIGN.md from existing project code | [reference/document.md](reference/document.md) |
| `extract [target]` | Build | Pull reusable tokens and components into design system | [reference/extract.md](reference/extract.md) |
| `critique [target]` | Evaluate | UX design review with heuristic scoring | [reference/critique.md](reference/critique.md) |
| `audit [target]` | Evaluate | Technical quality checks (a11y, perf, responsive) | [reference/audit.md](reference/audit.md) · native: [reference/audit.native.md](reference/audit.native.md) |
| `polish [target]` | Refine | Final quality pass before shipping | [reference/polish.md](reference/polish.md) |
| `bolder [target]` | Refine | Amplify safe or bland designs | [reference/bolder.md](reference/bolder.md) |
| `quieter [target]` | Refine | Tone down aggressive or overstimulating designs | [reference/quieter.md](reference/quieter.md) |
| `distill [target]` | Refine | Strip to essence, remove complexity | [reference/distill.md](reference/distill.md) |
| `harden [target]` | Refine | Production-ready: errors, i18n, edge cases | [reference/harden.md](reference/harden.md) |
| `onboard [target]` | Refine | Design first-run flows, empty states, activation | [reference/onboard.md](reference/onboard.md) |
| `animate [target]` | Enhance | Add purposeful animations and motion | [reference/animate.md](reference/animate.md) |
| `colorize [target]` | Enhance | Add strategic color to monochromatic UIs | [reference/colorize.md](reference/colorize.md) |
| `typeset [target]` | Enhance | Improve typography hierarchy and fonts | [reference/typeset.md](reference/typeset.md) |
| `layout [target]` | Enhance | Fix spacing, rhythm, and visual hierarchy | [reference/layout.md](reference/layout.md) |
| `delight [target]` | Enhance | Add personality and memorable touches | [reference/delight.md](reference/delight.md) |
| `overdrive [target]` | Enhance | Push past conventional limits | [reference/overdrive.md](reference/overdrive.md) |
| `clarify [target]` | Fix | Improve UX copy, labels, and error messages | [reference/clarify.md](reference/clarify.md) |
| `adapt [target]` | Fix | Adapt for different devices and screen sizes | [reference/adapt.md](reference/adapt.md) · native: [reference/adapt.native.md](reference/adapt.native.md) |
| `optimize [target]` | Fix | Diagnose and fix UI performance | [reference/optimize.md](reference/optimize.md) |
| `live` | Iterate | Visual variant mode: pick elements in the browser, generate alternatives | [reference/live.md](reference/live.md) |

Routing:

- **No argument:** read [routing.md](reference/routing.md) and present its context-aware menu; never auto-run a command.
- **Explicit or clearly implied command:** load its reference (native variant on native platforms) and follow it. Ask once if two commands fit.
- **Otherwise:** treat the request as general design work. Missing PRODUCT.md routes a new surface or replacement world through init, then new-work; a narrow refinement of existing code proceeds on the incumbent implementation as context.mjs directs, offering init afterward rather than blocking on it.
- `teach` aliases `init`. `craft` is a deprecated alias for ordinary new-work and adds nothing. `shape` owns task discovery, then enters new-work only for visual-world and surface-concept decisions.

After init writes PRODUCT.md, resume without rerunning `context.mjs`; init loads the native platform reference itself when the platform it recorded is `ios`, `android`, or `adaptive`.

**Pin / Unpin:** upstream does this with `scripts/pin.mjs`, which this port does not vendor. Tell the user the shortcut cannot be created here and point them at upstream if they want it.

**Hooks:** `/impeccable hooks <on|off|status|ignore-rule|ignore-file|ignore-value|reset>` manages the design detector hook for this project (auto-runs the detector after UI file edits and surfaces findings). Load [reference/hooks.md](reference/hooks.md) when the user invokes it with any argument.

**Doctor:** `/impeccable doctor` reports and repairs drift between this project's Impeccable artifacts (PRODUCT.md, DESIGN.md and its sidecar, config, surface briefs, the hook) and what this version reads. Load [reference/doctor.md](reference/doctor.md) when the user invokes it, or when they ask what is out of date, stale, or needs refreshing. A `CONTEXT_STALE` directive in Setup's output is the cheap subset of the same report; act on it there per its own instructions rather than running doctor unasked.

**Never repair drift as a side effect of a design task.** A `CONTEXT_STALE` finding is reported, not acted on, unless the user asks. The one exception is a finding marked `auto`, which the next write to that file performs anyway.