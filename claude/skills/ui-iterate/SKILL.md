---
name: ui-iterate
description: "Use after editing any UI file (.tsx/.jsx/.css/.vue/html) when a dev server runs: screenshot 375/768/1440px, self-critique hierarchy, spacing, states, fix and re-shoot before claiming done."
---

# ui-iterate — look at what you built before calling it done

UI edited blind is UI shipped broken. Code that compiles says nothing about what renders.
This loop forces the screenshot-critique-fix cycle that separates polished frontends from
plausible ones. Run it after every meaningful UI change, before declaring the task done.

## The loop

1. **Find the live page.** Locate the dev server: check for a running process on common ports
   (3000, 5173, 4321, 8080), `$CONDUCTOR_PORT`, or the `dev` script in package.json (start it
   if the repo has one and nothing is running). Identify the route your change affects.

2. **Screenshot three widths.** Using the browser tools (claude-in-chrome; `resize_window`
   then `computer` screenshot), capture the affected page at:
   - 375px — phone
   - 768px — tablet
   - 1440px — desktop
   If browser tools are unavailable, use a headless fallback (`npx playwright screenshot` or
   agent-browser) — never skip the looking step because the preferred tool is missing.

3. **Critique what you see.** Judge the screenshots, not the code, against:
   - **Hierarchy** — is the most important element visually dominant? Does the eye land where
     the page's job says it should?
   - **Spacing** — consistent scale (4/8px grid), no cramped clusters or orphaned gaps,
     breathing room around groups.
   - **Typography** — clear size/weight contrast between levels; line length 45–75ch; no
     near-identical sizes competing.
   - **Contrast & accessibility** — text meets WCAG AA against its actual background;
     interactive elements look interactive.
   - **States** — hover, focus, empty, loading, error, long-content overflow. Trigger the ones
     your change touches and screenshot them.
   - **Responsive integrity** — nothing clipped, wrapped awkwardly, or overlapping at any of
     the three widths.

4. **Fix the worst thing, re-shoot.** One issue at a time, most severe first. Re-screenshot
   the affected width after each fix. Repeat until step 3 finds no majors.

5. **Measure the change, do not eyeball it.** Comparing two screenshots by looking at them
   misses exactly the regressions that matter: the 4px shift on a width you were not focused
   on. Keep the pre-change capture as a baseline and diff against it:

   ```bash
   npx agent-browser diff screenshot --baseline .context/ui-evidence/before-1440.png \
     --threshold 0.02 -o .context/ui-evidence/diff-1440.png
   ```

   It reports a mismatch percentage and writes a PNG with the changed pixels highlighted. Run
   it on the widths you did *not* intend to change — a non-zero mismatch there is an unintended
   regression, and that is the whole point. `diff snapshot` compares the accessibility tree
   instead, which is less flaky than pixels for structural changes.

   Two things make pixel diffs trustworthy rather than noisy: a fixed viewport
   (`agent-browser set viewport 1440 900`) and waiting for the network to settle
   (`agent-browser wait --load networkidle`) before every capture. Without both, you are
   diffing animation frames.

6. **Show the evidence.** The final message includes what the screenshots showed, the mismatch
   percentages, and what changed because of them. For gated repos, save the final captures to
   `.context/ui-evidence/` so verify.sh or a reviewer can see the loop actually ran.

## When NOT to use

Pure logic/data changes with no rendered surface, or repos with no runnable frontend. Do not
fake the loop with code-reading — if nothing can render, say so plainly instead.
