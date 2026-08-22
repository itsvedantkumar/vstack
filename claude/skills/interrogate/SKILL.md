---
name: interrogate
description: "After the thing exists: parallel reviewers over a diff one person or nobody has read, especially auth, payments or agent-written code. Fires on tear this apart."
---

# Interrogate

Spawn several parallel reviewers over the same diff, same intent, same rubric. Deduplicate their findings, then deliver a single bucketed verdict.

**The deliverable is a verdict, not a patch. Do NOT auto-apply changes.**

## Read this before you trust consensus

The original method assumed reviewers from different vendors — different training data, different blind spots — so agreement across models was strong independent evidence.

**That premise does not hold here. Claude Code is Anthropic-only. Every reviewer is a Claude model.** They share pretraining lineage, post-training, and safety tuning, so their blind spots are correlated. Two Claude models agreeing is weaker evidence than two vendors agreeing, and — more dangerously — *four Claude models missing the same thing tells you almost nothing about whether it's there.*

Two consequences, and they are load-bearing:

1. **Manufacture the diversity in the prompt, not the model picker.** Each reviewer gets a different rubric emphasis (its lens) so the reviewers are actually looking at different things. Model choice varies reasoning depth and cost; the lens is what varies coverage. If you collapse all reviewers onto the same lens, you are paying 4x for roughly one review.
2. **Silence is not clearance.** "No reviewer flagged the auth path" does not mean the auth path is clean. Report unanimous silence on a high-risk lens as an open question in the verdict, never as an all-clear.

Do not describe this setup to the user as equivalent to multi-vendor review.

## Step 1, Determine scope

Identify what to review from context:

- If the user points at specific files or a diff, use that
- If on a feature branch, run `git diff main...HEAD` (or the appropriate base branch) for the full changeset
- If the user's message references recent work, gather the relevant files

Package the diff (or file contents) plus any surrounding context files the reviewers need to understand the code.

## Step 2, State the intent

Before spawning reviewers, state the intent explicitly. What is this code trying to accomplish? Derive it from the user's message, commit messages, the PR description if one exists, and the code itself.

Write one clear paragraph. Reviewers challenge whether the work achieves the intent well, not whether the intent itself is correct. If the intent is genuinely ambiguous, pick the most plausible reading, state the assumption in the verdict, and proceed.

## Step 3, Spawn reviewers

**Spawn every reviewer in ONE message as multiple Agent tool calls.** Four calls, one assistant turn. Do not spawn one, wait, spawn the next — sequential fan-out is the single most common failure of this skill and it costs you the wall-clock benefit of the whole method while producing an identical verdict. If you catch yourself writing a second message containing a second Agent call, you have already broken the skill.

Set `run_in_background: false` on all of them so the batch runs concurrently and every result is in hand before synthesis.

| Reviewer | `subagent_type` | `model` | Lens (rubric emphasis to stress in the prompt) |
|---|---|---|---|
| A | `code-reviewer` | `opus` | Correctness, concurrency, state, error paths |
| B | `security-auditor` | `sonnet` | Security, authn/authz, trust boundaries, TOCTOU, abuse |
| C | `code-reviewer` | `fable` | Structural integrity, complexity budget, code-judo simplifications |
| D | `code-reviewer` | `haiku` | Verification: tests, invariants, what would catch a regression |

Model slugs behind those overrides: `opus` → `claude-opus-5`, `fable` → `claude-fable-5`, `sonnet` → `claude-sonnet-5`, `haiku` → `claude-haiku-4-5`. Use the short override strings in the tool call.

`code-reviewer` and `security-auditor` have Read, Grep, Glob, Bash only, so reviewers are structurally read-only — they cannot edit the branch even if a finding tempts them. If a lens has no matching agent type, use `subagent_type: "general-purpose"` with `model:` set and forbid writes in the prompt body.

Scale the roster to the job: drop D on a pure refactor with no behavior change; drop B when nothing touches input, auth, secrets, or IO. Never drop below two lenses — one reviewer is what you already have.

Read `references/reviewer-prompt.md` and fill in the template for each reviewer with:

1. The stated intent
2. The diff or file contents
3. The review rubric from `references/rubric.md`
4. The code-quality lens from `references/code-quality-review.md`
5. That reviewer's assigned lens from the table, in the `{LENS}` slot

Everything except `{LENS}` is identical across reviewers. The lens is the only deliberate divergence, so it has to carry the weight.

## Step 4, Synthesize

As results come back, build a unified picture:

1. **Parse all findings** from the reviewers.
2. **Identify consensus.** Findings raised by 2+ reviewers get a confidence bump — but a smaller one than the original method assumed, and smaller still when the agreeing reviewers shared a lens. Two reviewers on the *same* lens agreeing is close to no information. Two reviewers on *different* lenses converging on one line of code is the strongest signal available here.
3. **Identify lone-reviewer findings.** Worth reading. A finding raised only by the lens that owns that territory (security-auditor on an auth bug) is not weak evidence — it is the expected shape of a correct finding.
4. **Deduplicate.** Different reviewers describe the same issue differently. Merge them and note which reviewers raised it.
5. **Note disagreements.** One reviewer flagging what another explicitly cleared is useful context for the verdict.
6. **Note the gaps.** Which lens returned nothing? Say so explicitly. Correlated blind spots show up as suspicious unanimity, not as errors.

## Step 5, Lead judgment

You are the lead reviewer, a pragmatic senior engineer, not a neutral aggregator.

Read `references/lead-judgment.md` for the full framework. Reviewers see a slice of the codebase; you have the full context — the goal, the constraints, what was already tried and rejected. Use it aggressively.

Categorize every finding:

- **Act on.** Real issues affecting correctness, security, or maintainability given the actual goals. These would block a real PR.
- **Consider.** Legitimate, but you're not sure the fix outweighs its cost right now. Worth the user's attention.
- **Noted.** Technically valid, not actionable. Context-dependent, premature, or low-impact at this stage.
- **Dismissed.** Wrong, nitpicky, or missing context. Brief explanation why.

For each finding include: which reviewer(s) and lens(es) raised it, the category, and a one-line rationale.

## Output format

### Intent
> [The stated intent paragraph from Step 2]

### Reviewers
- Reviewer [label]: [model], [lens], [N findings] — one bullet each

### Act on
[Findings to address. For each: description, which reviewers raised it, why it matters.]

### Consider
[Findings worth thinking about. For each: description, reviewers, tradeoff.]

### Noted
[Valid but low-priority. Brief list.]

### Dismissed
[Rejected findings with rationale, so the user can override your judgment where they disagree.]

### Agreement map and blind spots
Where reviewers converged, where they diverged, and what the pattern means. Then, explicitly: which lenses came back empty, and whether that is a clean bill of health or an untested area. Close with a one-line reminder that all reviewers were Anthropic models and share blind spots, so this verdict bounds *known* risk, not total risk.

## Where the verdict lands

In a Conductor workspace (`CONDUCTOR_WORKSPACE_PATH` is set), also post each Act-on and
Consider finding as an inline `mcp__conductor__DiffComment` at its file:line — that puts the
verdict in the Checks panel next to the diff, where the merge decision happens. Do not post
to GitHub unless asked.

## After the verdict

Stop. The user decides what to fix. If they ask you to apply findings, treat that as a normal change — plan it, make it, verify it. Re-running `interrogate` on your own fixes is legitimate and often catches a bad patch.
