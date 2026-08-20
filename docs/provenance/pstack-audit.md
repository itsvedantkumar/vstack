# pstack Skills — Fit & Benefit Audit for vk

Audited 2026-08-19. Source: `cursor/plugins` @ `195d9359`, `pstack/skills`, 44 skills.
Evidence: 6,334 claude-mem observations · 421 session transcripts (51 real sessions, 14 days) · 25,505 tool calls · 1,126 commits across 10 repos · full config inventory.

---

## Three findings that reframe the whole question

**1. 40 of 44 pstack skills carry `disable-model-invocation: true` — explicit invoke only.**
Only `how`, `setup-pstack`, `typescript-best-practices`, and `unslop` can self-trigger. Meanwhile your measured behavior: slash commands are **9.8% of prompts** (70 / 711), and your ~30 installed skills produced **14 `Skill` invocations in 14 days**. Your global CLAUDE.md says *"Skills auto-fire by their trigger — never wait for a slash command"* — pstack is built on the opposite assumption. **Adopting any of these as-is means they will not fire.** Flip the flag on anything you adopt, or it's dead weight.

**2. Your parallelism is partial — ~44% batched.** *(Corrected 2026-08-19; the original claim here was wrong.)* Grouping `Agent` tool_use blocks by `message.id` across all 421 transcripts gives fan-out 1×122, 2×55, 3×25, 4×9, 5×5, 6×2 — **96 of 218 dispatches (44%) were already batched**, max 6 agents in one message. The earlier "every single one is fan-out = 1" was an artifact of counting per assistant *event*: Claude Code emits one assistant event per *content block*, so a 3-agent batch looks like three 1-agent messages. Any future fan-out measurement must group by `message.id`.

The real gap is smaller but still real: 56% of dispatches are single-agent, and you asked for parallelism in 172 prompts across 33 of 47 sessions. `swarm`'s value is therefore **the explicit race rule and drain-to-one-table discipline**, not "teaching you to batch" — you already batch about half the time.

**3. You already built the verification gate and it has never fired.** `~/.claude/hooks/verify-gate.sh` is a Stop hook that blocks completion when `$PROJECT/.claude/verify.sh` fails. **0 of 10 project `.claude/` dirs contain `verify.sh`**, and the hook exits 0 when absent. Cost: 25 cases of "done" declared over a failing tool result, across 14 sessions.

---

## Scoring

**Fit** (0–5): how often your observed work hits the trigger.
**Benefit** (0–5): marginal value *after* subtracting existing coverage, weighted by observed friction.
Redundancy overrides total — a perfect-fit skill you already have in three places is a Skip.

---

## TIER 1 — ADOPT NOW

| # | Skill | F | B | Σ | Why |
|---|---|---|---|---|---|
| 1 | **create-verification-skill** | 5 | 5 | 10 | Generates the exact `verify.sh`-equivalent your inert Stop hook is waiting for. Interviews the repo, writes a verification skill + feature map, then *executes it once to prove it*. This is the missing keystone in machinery you already built. Port `.cursor/skills/` → `.claude/`. |
| 2 | **swarm** | 5 | 4 | 9 | Directly targets finding #2. Declares the race rule up front (first-pass / rank-all / best-of), fans out N workers, drains, returns one table. Ships as cloud-only (`environment: "cloud"`) — **port to local batched `Task` calls**. The discipline, not the runtime, is what you're missing. |
| 3 | **show-me-your-work** | 5 | 4 | 9 | TSV decision log (what/why/evidence/result) + a mandatory cross-model review pass. You run an 8:1 subagent-to-human-session ratio, 296 background Bash invocations, 3 scheduled tasks, and a launchd `~/OSS` factory that ships upstream PRs with **zero claude-mem observations**. All review is after-the-fact with no trail. |
| 4 | **principle-encode-lessons-in-structure** | 5 | 4 | 9 | "When you write the same instruction twice, encode it as a lint/check/script instead of more text." Your repeat counts: parallelize **172 prompts / 33 sessions**, verify **120 / 21**, don't-stop **48 / 11**, cost **84 / 14**. You've already hard-coded these into CLAUDE.md and they *still* recur — proving prose isn't the right encoding layer. |
| 5 | **blast-radius** | 4 | 4 | 8 | 5-level evidence ladder ("you said so" → "ran it"), forces one provable safety fact by running real code. Targets deploy-to-find-out: **22.2% of `vedant-to-gh` commits touch `.github/workflows`**, 5 bursts of ≥3 workflow commits <15 min apart, plus fabricated GitHub Action SHAs that needed a correction-to-the-correction. |
| 6 | **reflect** | 4 | 4 | 8 | 3 parallel transcript reviewers + synthesizer, routes findings to concrete skill edits. Transcript self-reflection is **NOT COVERED** in your setup (`skill-creator` is name-only). This is the delivery mechanism for #4. |
| 7 | **technical-writing** | 4 | 4 | 8 | **NOT COVERED**, and bigger than it looks: `.md` is your *most-edited file type* (205 edits vs 145 `.py`, 98 `.ts/.tsx`); vibemaxxing carries 152 tracked docs vs 30 app files; docs/spec is 16.2% of observations. You publish essays on vedant.to. Diátaxis + Google style + STE, zero subagents, zero prereqs. |
| 8 | **typescript-best-practices** | 4 | 4 | 8 | Language question resolved: raw LOC favors Python 4.6:1, but that 45k is throwaway CI-conformance harnesses and scrapers. **Every shipping surface is TS/React** (vedant.to, keystatic-passkeys, vibemaxxing web, both MCP servers), and first-party file count is near parity (146 TS vs 158 py). Your `typescript-lsp` plugin is diagnostics only — no idiom guidance. Already model-invocable on any `.ts/.tsx`. |
| 9 | **interrogate** | 4 | 4 | 8 | One reviewer per model family, same rubric, consensus + Act-on/Consider/Noted/Dismissed. Your review is a single Sonnet `code-reviewer`; `requesting-code-review` is demoted to name-only. Agent-authored auth code shipped a password oracle, a TOCTOU lockout race, a WebAuthn counter bypass, and VPN cache poisoning. 132 self-merged PRs with no second human. |

---

## TIER 2 — ADOPT WITH EDITS

| # | Skill | F | B | Σ | Why |
|---|---|---|---|---|---|
| 10 | principle-build-the-lever | 4 | 4 | 8 | "Build the tool that proves it, not the manual pass." Fits the CI thrash and your 6,123 inline `python3` heredocs — throwaway work that never becomes a rerunnable artifact. |
| 11 | principle-sequence-verifiable-units | 4 | 4 | 8 | Small units each ending verifiable. Targets fix-of-the-fix: **22.6% / 22.7%** fix-prefixed commits in the two shipping repos; 9.5% land <2h after touching the same files. |
| 12 | principle-prove-it-works | 5 | 3 | 8 | Verify against the real artifact, not a proxy. Perfect fit — but CLAUDE.md already says this and it still failed 25 times. Prose is the wrong layer; #1 is the actual fix. Adopt as reinforcement only. |
| 13 | maintain-verification-skill | 3 | 4 | 7 | Keeps #1 honest over time. **Strictly conditional** — worthless until create-verification-skill has shipped a verify skill. |
| 14 | principle-make-operations-idempotent | 4 | 3 | 7 | Converge regardless of partial prior runs. Your launchd OSS factory, 3 scheduled tasks, and sessions that hard-stop on API limits mid-run ("resume six killed planning workstreams") are exactly this shape. |
| 15 | principle-fix-root-causes | 4 | 3 | 7 | **112 broad `except Exception`** at HEAD in TextVed, 23 with same-line `# noqa: BLE001`, 309 total suppression lines. Your `debugger` agent covers this well already — hence B3 not B5. |
| 16 | unslop | 4 | 3 | 7 | Always-on, 31 AI-tell patterns. Your CLAUDE.mds govern *response* style, not prose Claude writes *into files* — a real gap given 205 `.md` edits and a published essay site. Bonus: your two CLAUDE.mds currently conflict on fragment-style. |
| 17 | architect | 4 | 2 | 6 | Type/signature sketch before code. Heavily covered: `brainstorming` + `writing-plans` at full, `planner` agent, 47% plan-mode usage. Take the sketch-first mechanic, skip the skill. |
| 18 | principle-guard-the-context-window | 5 | 1 | 6 | Highest-fit principle by evidence — **4 sessions at 905k–913k tokens**, 63 above 180k, only 5 compactions corpus-wide, 14.2% of Reads are same-session re-reads. But your SessionStart TOKENS block already says this verbatim. Same "already told, still recurs" trap as #12. |
| 19 | figure-it-out | 3 | 3 | 6 | Bespoke playbook + hypothesis loop + TSV trail for large migrations. Fits vibemaxxing's multi-phase planning; overkill for daily work. |
| 20 | how | 3 | 3 | 6 | Model-invocable, 2–4 parallel explorers + explainer. Your `explorer` agent is a *locator* returning `path:line`, not an explainer — genuine PARTIAL gap. Discounted because you're solo on your own code. |
| 21 | arena | 3 | 3 | 6 | N candidates + cross-family judge, graft the winners. Real value for greenfield UI/architecture calls; expensive (N+1 subagents) and needs worktrees. |
| 22 | recall | 3 | 3 | 6 | Reconstructs context from transcripts + git + gh. You have claude-mem but disabled 17 of its skills; retrieval is manual. Partial dep on `why`, which is crippled for you (see #41). |
| 23 | automate-me | 3 | 3 | 6 | Mines transcripts → personal `-mode` skill. Preference→rule capture is **NOT COVERED**. Discounted because you've already hand-built this by hand, well. |
| 24 | principle-type-system-discipline | 4 | 2 | 6 | Parent of #8; make illegal states unrepresentable, parse at boundaries. Adopt bundled with typescript-best-practices, not standalone. |
| 25 | principle-boundary-discipline | 3 | 3 | 6 | Guards at CLI/config/network/external-API edges. Two MCP servers + Keystatic auth + passkeys = a lot of boundary surface. |
| 26 | setup-pstack | — | — | — | **Infrastructure, conditional.** Writes `~/.cursor/rules/pstack-models.mdc` with Cursor-only slugs. Needed only if you adopt fan-out skills, and needs full translation to Claude Code model IDs. |

---

## TIER 3 — MARGINAL

| # | Skill | F | B | Σ | Note |
|---|---|---|---|---|---|
| 27 | principle-separate-before-serializing-shared-state | 3 | 2 | 5 | Your hook + `/orchestrate` already say "serialize edits to shared files". |
| 28 | principle-laziness-protocol | 3 | 2 | 5 | Bias to deletion. Median diff is already small (73 lines). |
| 29 | principle-minimize-reader-load | 3 | 2 | 5 | Solo dev; you are the only reader. |
| 30 | principle-subtract-before-you-add | 3 | 2 | 5 | Generic good hygiene, no specific friction evidence. |
| 31 | principle-foundational-thinking | 3 | 2 | 5 | Overlaps `planner` + `brainstorming`. |
| 32 | principle-model-the-domain | 3 | 2 | 5 | Some fit (vibemaxxing state machines); no measured pain. |
| 33 | principle-experience-first | 3 | 2 | 5 | Fits lexifocus/vedant.to product work; overlaps `frontend-design` plugin. |
| 34 | tdd | 3 | 1 | 4 | Your `test-driven-development` skill is at FULL priority + `test-writer` agent + `/test`. pstack's version is deliberately *narrower* (has an escape hatch). Strict downgrade. |
| 35 | principle-exhaust-the-design-space | 2 | 2 | 4 | Only meaningful if you adopt `arena`. |
| 36 | no-comments | 2 | 2 | 4 | Zero evidence you've ever given a comment-style directive (0 matches in 711 prompts). The adjacent real problem is *suppression* (`noqa`/`type: ignore`), which `fix-root-causes` handles better. |
| 37 | teach | 2 | 2 | 4 | Depends on `how` + `why`; `why` is crippled for you. Solo dev — nobody to teach. |
| 38 | principle-outcome-oriented-execution | 2 | 2 | 4 | For planned rewrites with phase boundaries; you're mostly greenfield. |
| 39 | principle-redesign-from-first-principles | 2 | 2 | 4 | Same. |
| 40 | poteto-mode | 2 | 2 | 4 | The hub — 140 lines + **~180KB of playbooks/scripts**, plus Graphite, bun, `poteto-agent`, and cursor-team-kit. It's a complete competing operating style, and you already have a strongly-defined one across 2 CLAUDE.mds, 4 hooks, 7 agents, 16 commands. Adopting it means replacing your system, not extending it. |

---

## TIER 4 — SKIP

| # | Skill | F | B | Reason |
|---|---|---|---|---|
| 41 | **principle-never-block-on-the-human** | 5 | 0 | Highest fit in the entire set, **zero** marginal value. You already encode it in three places: `NEVER ASK. ACT.` (global CLAUDE.md), `<default_to_action>` (project), `AUTONOMY: act without asking` (SessionStart hook) — plus `defaultMode: "bypassPermissions"`. Pure duplication. |
| 42 | why | 2 | 1 | Needs up to 6 MCPs for full coverage (Linear, Notion, Slack, Datadog, Sentry, Databricks). You have none. Solo dev, no issue tracker, no incident history — the evidence categories it queries are empty. Its 229-line body + 53KB of references would buy you `git log`. |
| 43 | principle-migrate-callers-then-delete-legacy-apis | 1 | 1 | Assumes an existing internal API with many callers. Greenfield solo repos, 30 active days of history. |
| 44 | bro | 1 | 1 | 7-line novelty. You already run `/caveman` (7 uses) and a maximally-concise output directive. |

---

## Adoption sequence

1. **`create-verification-skill`** on `vedant-to-gh` first (your only production app, 22.6% fix-rate). Activates the dormant `verify-gate.sh`. Highest single ROI in this audit.
2. **Port `swarm`'s batching discipline** into `/orchestrate` — the command's text is already right; the behavior is missing. Then verify fan-out >1 actually appears in transcripts.
3. **`show-me-your-work`** on the `~/OSS` launchd factory — currently shipping upstream PRs entirely unobserved.
4. **`typescript-best-practices` + `principle-type-system-discipline`** as a pair, model-invocable on `.ts/.tsx`.
5. **`technical-writing` + `unslop`** — cheapest wins in the set. Pure prose, no subagents, no prereqs, and they cover a real gap.
6. Then `blast-radius`, `interrogate`, `reflect`.

**Do not** bulk-install. The standing tax is ~2.7k tokens for all 44 frontmatter descriptions, and you run a `skillListingBudgetFraction` of 0.0025 — a deliberately tight skill-listing budget that 44 new descriptions would blow through.

## Porting cost (applies to everything above)

pstack is Cursor-native. Every adopted skill needs: model slugs translated (`claude-opus-5-thinking-xhigh` → `claude-opus-5`), Task params translated (`readonly`, `environment: "cloud"`, `subagent_type: generalPurpose` → your agent roster), paths remapped (`.cursor/skills` → `.claude/skills`, `~/.cursor/rules` → CLAUDE.md), and `disable-model-invocation` flipped to false or the skill will never fire for you.

## What I could not see

- **Two other machines were not audited** (not reachable from this one). GitHub served as a proxy and showed no cross-machine evidence — all 951 human commits carry one timezone; the only web-editor commits number 5. If those machines carry materially different work, this ranking does not reflect it.
- **The `~/OSS` factory is a blind spot in your own memory**, not just this audit: 4 repos and 2 live upstream PRs (pypa/pip, sphinx-doc/sphinx) created Aug 18–19 with zero claude-mem observations, because launchd runs it outside instrumented sessions.
- claude-mem covers Aug 5–19 only; git history extends to Apr 24.
- [one credential-hygiene bullet redacted from the public copy]
