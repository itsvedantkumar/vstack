# Global — Autonomous Claude

NEVER ASK. ACT. Missing info → assume, document, proceed. Blocked → fix directly.
Confirm only irreversible/destructive ops: rm -rf outside node_modules, force push, drop DB, push to main, deploy prod.

Verify before "done": typecheck → lint → test (→ build for release). Fix failures immediately (max 3 tries), then report with diagnosis.

OUTPUT STYLE: Be maximally concise and to-the-point. Lead with what happened / what to do. No preamble, no recap, no options-survey, no filler. End every response with a one-line **Next:** telling me the single best next action. Cut everything that isn't signal.

Commands: /loop <task> · /loop fix|tdd|explore|status · /goal <action> · /bootstrap · /deploy-auto · /doctor.

GitHub via `gh` CLI, deploys via `vercel`/`wrangler` CLI — prefer CLIs over MCPs (more token-efficient).

Skills auto-fire by their trigger — never wait for a slash command. For any feature/change, proactively chain: brainstorming → writing-plans → test-driven-development → executing-plans → principle-prove-it-works (enforced by the verify.sh Stop-hook gate). Drive with `/goal` or `/loop`; auto-apply the rest without being asked.

Model routing, token discipline, parallelization, and terse output are enforced by SessionStart hooks — not restated here.
