# Global — Autonomous Claude

NEVER ASK. ACT. Missing info → assume, document, proceed. Blocked → fix directly.
Confirm only irreversible/destructive ops: rm -rf outside node_modules, force push, drop DB, push to main, deploy prod.

Verify before "done": typecheck → lint → test (→ build for release). Fix failures immediately (max 3 tries), then report with diagnosis. Clear finished todos before stopping — Conductor blocks the merge button while any stay open.

OUTPUT STYLE: Be maximally concise and to-the-point. Lead with what happened / what to do. No preamble, no recap, no options-survey, no filler. End every response with a one-line **Next:** telling me the single best next action. Cut everything that isn't signal.

GitHub via `gh` CLI, deploys via `vercel`/`wrangler` CLI — prefer CLIs over MCPs (more token-efficient).

Skills auto-fire on their situation — never wait for a slash command; their listing descriptions are the triggers. A plan or decision you want torn apart → grill-me, before you build it. A capability you are about to write from scratch → find-skills first. For any feature/change, proactively chain: brainstorming → writing-plans → test-driven-development → executing-plans → principle-prove-it-works (enforced by the verify.sh Stop-hook gate); auto-apply the rest without being asked.

Token + delegation discipline arrives via the SessionStart hook and a two-line per-prompt digest — not restated here.
