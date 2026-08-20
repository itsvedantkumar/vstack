# Goal: End-to-end conductor setup audit

Created: 2026-08-19 · Status: **complete** (2 documented residuals) · Branch: optimize-conductor-claude-setup

## Objective

Audit the entire conductor setup end-to-end — config lanes, hooks, skills, agents, commands,
connectors (MCP servers), and the autonomous-deploy chain. Everything must demonstrably work,
with no bloat or redundant skills, and the per-session token overhead justified.

## Rubric (all must pass with session evidence before close)

- [x] R1 — Lanes in sync: diff -rq repo↔deployed zero diffs; LICENSE.pstack debris removed from ~/.claude/skills; install.sh re-run propagated all edits (backup install-20260819-141923)
- [x] R2 — All 4 hooks bash -n clean + executed on realistic stdin: inject emits SKILLS block; verify-gate allow/block/allow on 3 cases; format + failure-diagnose exit 0 valid JSON
- [x] R3 — 35 skills checked: all 18 pstack ports fully clean; 0 disable-model-invocation; all scripts executable + bash -n; only issues were 9 overlong descriptions on pre-existing skills (4 disabled, 4 name-only → moot, 1 = VBC, now off)
- [x] R4 — Redundancy map: VBC merged into principle-prove-it-works (Iron Law + rationalization table ported, VBC off); systematic-debugging + requesting-code-review off (covered by principle-fix-root-causes/debugger and interrogate/code-reviewer); unslop/technical-writing and type-system pairs verified orthogonal; all 8 principles verified to add method beyond hook routing; ~/.claude/CLAUDE.md chain re-pointed to prove-it-works
- [x] R5 — Connectors: cloudflare-mcp, context7, namecheap OK; [one MCP-wiring finding redacted from the public copy: an MCP server was orphaned and has been re-wired]; claude-mem repaired (npx claude-mem repair → doctor 5/5 green); claude-in-chrome extension-based (no file config, working at runtime)
- [x] R6 — skillListingBudgetFraction 0.006→0.012 (both lanes): active listing needs ~1,611 tokens post-prune, budget now 2,400 — no truncation, ~33% headroom
- [x] R7 — gh authed; wrangler installed + authed [credential presence detail redacted from the public copy]; vercel installed (login = residual); verify gate ARMED on a project repo (.claude/verify.sh: typecheck+26 tests, falsifiability proven 0→1→0); scheduled routines: PRIMARY lane is claude.ai cloud routines (user's 2026-08-10 decision) [trigger ids redacted from the public copy]; local fallback repaired — repo-health SKILL.md rewritten gh-based (PAT-scraping removed) and live-tested via claude-task.sh (exit 0, real report in 30s); launchd plists built, validated, then parked [path redacted from the public copy] to avoid duplicating cloud runs
- [x] R8 — Re-verified: all .sh bash -n clean, both settings jq-valid, trivy secret scan clean, git status shows only intended files, launchctl list shows both jobs

## Residuals (documented, need user action)

1. `vercel login` (or VERCEL_TOKEN in secrets.env) — unblocks vercel deploys and the watch-deploy-failures routine's Vercel half.
2. 1-min check at https://claude.ai/code/routines that the cloud triggers are still active (their runs leave no local trace; local audit can't see them). If they're gone, re-arm locally: `launchctl bootstrap gui/$(id -u) <path redacted from the public copy>/<plist>`.
3. [redacted from the public copy: a local credential-hygiene note; it lives in the private session record]
