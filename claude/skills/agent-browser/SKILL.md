---
name: agent-browser
description: "Use when you need to screenshot or drive a dev server and the shared Chrome is unavailable or contended — e.g. parallel Conductor workspaces: headless per-workspace browser via npx agent-browser."
---

# agent-browser — headless per-workspace browser

Browser automation CLI from Vercel Labs. Native Rust binary driving Chrome/Chromium over
CDP — no Playwright, no shared Chrome window. Each `--session` gets its own browser
instance, cookies, and history, so parallel Conductor workspaces never fight over tabs.

Needs node/npx. Run every command through `npx agent-browser ...` (or `agent-browser` if
installed globally with `npm i -g agent-browser`). First use on a machine may need
`npx agent-browser install` to download Chrome for Testing; existing Chrome, Brave,
Playwright, and Puppeteer installs are detected automatically.

## Isolate the workspace first

```bash
SESSION="$(npx agent-browser session id --scope worktree --prefix dev-loop)"
# Then pass --session "$SESSION" on every call, or export AGENT_BROWSER_SESSION="$SESSION"
```

The browser persists via a background daemon, so chaining commands with `&&` is safe.

## The ui-iterate loop

Screenshot the affected route at all three widths, then critique the images:

```bash
URL="http://localhost:${CONDUCTOR_PORT:-3000}/route-you-changed"

npx agent-browser --session "$SESSION" open "$URL"
npx agent-browser --session "$SESSION" wait --load networkidle

npx agent-browser --session "$SESSION" set viewport 375 812   # phone
npx agent-browser --session "$SESSION" screenshot /tmp/ui-375.png

npx agent-browser --session "$SESSION" set viewport 768 1024  # tablet
npx agent-browser --session "$SESSION" screenshot /tmp/ui-768.png

npx agent-browser --session "$SESSION" set viewport 1440 900  # desktop
npx agent-browser --session "$SESSION" screenshot /tmp/ui-1440.png
```

Read each PNG with the Read tool and critique it (hierarchy, spacing, states) per the
ui-iterate skill. Add `--full` to `screenshot` for the full page instead of the viewport.

## Interact via accessibility-tree refs

`snapshot` prints the accessibility tree with stable `@eN` element refs — more reliable
than CSS selectors for driving state (hover, open menus, filled forms) before a shot:

```bash
npx agent-browser --session "$SESSION" snapshot -i        # interactive elements only, with refs
npx agent-browser --session "$SESSION" click @e2          # click by ref
npx agent-browser --session "$SESSION" fill @e3 "test@example.com"  # clear + fill by ref
npx agent-browser --session "$SESSION" snapshot -i        # re-snapshot after the page changes
```

Refs go stale on navigation or DOM changes — always re-run `snapshot` before reusing them.
If a click fails because another element covers the target (consent banner, modal), dismiss
the reported covering element and take a fresh snapshot before retrying.

## Done? Close it

```bash
npx agent-browser --session "$SESSION" close
```

More commands (`wait --text`, `hover`, `press`, `scroll`, `diff screenshot`, auth/state):
`npx agent-browser --help`, or `npx agent-browser skills get core` for the full workflow
guide served by the installed CLI. `skills get dogfood` is an adversarial exploratory-QA pass,
which complements a design review of a surface you already know about.

## Which browser tool, and when

Two browser lanes exist here and they must not fight over the same Chrome.

**claude-in-chrome** drives your real, logged-in browser. Use it when the session needs your
cookies, an authenticated app, or you want to watch what happens.

**agent-browser** runs its own headless Chrome. Use it whenever the shared browser would be
contended or is unavailable: parallel Conductor workspaces, background runs, anything
unattended. Always pass `--session <workspace>` and `--pin-tab`, which is what keeps two
workspaces from adopting each other's tabs.

Requires Node 24 or newer. On an older Node the CLI still runs but npm prints an engine
warning; if a command behaves strangely, check the Node version before debugging further.

## Accessibility, without hand-rolling it

```bash
npx agent-browser --session "$SESSION" a11y --tags wcag2a,wcag2aa
```

Runs axe-core in-page, offline and CSP-safe, scoped by selector and aware of iframes. Prefer it
to writing WCAG checks by hand in a review.
