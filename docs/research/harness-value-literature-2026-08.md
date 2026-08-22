# Does a coding-agent harness beat the unconfigured agent? What the literature says, August 2026

Written 2026-08-22. True when written, not maintained.

What this changed about vstack, and the changes it explicitly did not license, are recorded
separately in [what-we-changed-2026-08-22.md](what-we-changed-2026-08-22.md).

This is a record of **other people's** published evidence. This project's own measurements live in
`tests/evals/RESULTS.md` and are summarised, quarantined, in section 6 below. The two are kept
apart on purpose: the failure this document exists to avoid is letting what we measured, what
others claim, and what merely sounds obvious blur into one voice.

Method: eight parallel research lanes, ~120 findings over roughly 70 distinct sources, then two
adversarial verification passes, one checking citation integrity and one hunting for claims
presented as measurements. The verifiers killed two findings outright for fabricated or inverted
numbers and forced rewrites on about thirty more. Everything below is written from evidence
fields, not from the lanes' own claim fields, because the claim fields routinely outran them.

---

## 1. The direct answer

**On current frontier models, there is no published evidence that a configuration-layer harness
improves correctness, and two independent nulls at honest baselines say it does not.** (A third
config-layer null exists and is excluded from that count: it never states its baseline, so it
cannot be distinguished from a floor or ceiling artifact. See 3.4.) The
measured effects of the config layer are elsewhere: on cost, usually upward; on *which* problems
get solved rather than how many; and on behavioural integrity, where prompt-level text produces
some of the largest effects in the entire literature.

Confidence: **medium-high** for the correctness null on issue-resolution tasks. **Low** for
anything outside that task shape, because nobody has measured it.

Three distinctions carry the whole answer, and collapsing any of them produces a wrong conclusion.

**Architectural scaffolding is not configuration.** The literature's word "scaffold" spans a full
agent loop, with retry policy, context compression, checkpointing and tool schemas, down to a
markdown file. Architectural scaffolding demonstrably matters: harness choice at fixed model moves
SWE-bench-style pass@1 by 12.5 to 27.4 points, comparable to the 29.4 points from changing the
model (Claw-SWE-Bench, arXiv 2606.12344, n=350 tasks, 5 harnesses x 2 models, page-fetched,
self_eval unclear, layer architectural, baseline 38.6-63.1%, cost $71.50-$1,399.10 per run).
That number gets quoted as though it licenses a skills-and-hooks layer. It does not. The same
paper states it does not ablate skills, subagents or hooks, and its own diagnostic shows most of
the low-end spread is patch-application plumbing: a bare patch adapter scores 19.1% against 73.4%
for a full adapter on the identical model. That is broken pipes being fixed, not reasoning being
supported.

**Correctness is not the only outcome.** Config-layer text moves cheating rates, out-of-scope
destructive actions and regression rates by very large margins while leaving pass rates flat.
Section 4 is the strongest part of the case for a harness and it is almost entirely about
behaviour rather than capability.

**A null at ceiling is not a null.** Every finding below carries its baseline, because a
"no difference" result is uninformative unless you know there was room to differ. The corpus
contains real instances: a pentest comparison whose top arm sits at 92.3%, a config ablation
sitting in a 74.4-76.0% band against a corpus maximum of 79.2%, and SWE-bench Verified itself at a
reported 80.9% before retirement. This project published three of its own and called them nulls.

---

## 2. Q1. Does the scaffold separate from the base model, and has the gap narrowed?

### 2.1 The leaderboards deliberately stopped measuring it

The two most-cited coding leaderboards now hold the harness fixed by design. SWE-bench Verified's
default view is "Bash Only", described on the site as "every model in the same mini-SWE-agent
environment", and since 2025-11-18 the board accepts only academic and open-research submissions,
explicitly excluding commercial harnesses (Augment Code, Solver AI, Honeycomb.sh named as no
longer eligible). Scale's SEAL SWE-bench Pro board converged independently on the same choice, its
top entries footnoted "run with mini-swe-agent harness".

*Confidence: high. Source: [SWE-bench experiments README](https://github.com/SWE-bench/experiments/blob/main/README.md)
plus [swebench.com](https://www.swebench.com/) and [Scale SEAL](https://labs.scale.com/leaderboard/swe_bench_pro_public).
self_eval unclear, layer architectural, baseline n/a, cost not reported.*

This is a methodology finding, not a score, and it is the single most important structural fact in
this report. The venues everyone cites answer "which model" and by construction cannot answer
"which harness". A harness question asked of a SWE-bench leaderboard has no answer available.

Worse for our purposes: the locked-harness view has **no entries for any model released after
2026-02-12**. Six months of frontier releases, zero locked-harness data. The one clean
scaffold-versus-minimal time series available stops exactly where the current-generation question
begins, because OpenAI retired the benchmark for saturation and contamination in February 2026.

*Confidence: high for the leaderboard gap, which was verified directly against the embedded JSON.
Medium for the retirement rationale: OpenAI's post returns HTTP 403 to both WebFetch and curl with
a browser user agent, so the reasons (top score moving only 74.9% to 80.9% over six months; an
audit finding 59.4% of 138 hard tasks had flawed test design; GPT-5.2 solving 31 "nearly
impossible" tasks) rest on a single secondary blog nobody in this sweep could corroborate. Cite
as reported, not verified.*

### 2.2 Has the gap narrowed? Probably, but the honest series is not monotonic

Pairing every model present on both swebench.com views gives a best-scaffold-minus-locked-minimal
gap. Taking the maximum over submissions produces a clean monotonic narrowing, from +17 to +39
points for 2024 models down to +2.4 to +3.4 points for late-2025 frontier models. That series is
inflated: "best" is a max over k submissions, and k is 7 for GPT-4o and Claude 4 Sonnet against 1
or 2 for Sonnet 4.5, Gemini 3 Pro and Opus 4.5. Max-selection bias does most of the work.

Using the median instead, the honest series is:

| Model | Locked mini-SWE-agent | Median-based gap |
|---|---|---|
| GPT-4o | 21.6% | +5.4 |
| Claude 4 Sonnet | 64.9% | +6.3 |
| GPT-5 | 65.0% | +6.8 |
| Claude Sonnet 4.5 | 71.4% | +3.4 |
| Claude Opus 4.5 | 76.8% | +2.4 |

It rises across three generations before falling. The two most recent frontier models do show the
smallest gaps, and that is the real signal, but "narrows monotonically with model generation" is
not what the data says. GLM 4.6 (September 2025) is a further counterexample at +12.8, so whatever
is happening is specific to frontier closed models rather than to calendar time.

*Confidence: medium. This is derived arithmetic over leaderboard rows, not a published comparison.
Source: [swebench.com](https://www.swebench.com/) embedded leaderboard JSON, accessed 2026-08-22.
self_eval unclear, layer architectural, baselines in the table, cost reported for only 44 of 180
Verified entries.*

One confound nobody has addressed: if late-2025 frontier models memorised SWE-bench Verified
solutions, which is OpenAI's stated reason for retiring it, then a minimal harness closing the gap
to elaborate ones is exactly what contamination would produce. Retrieval needs no scaffold. No
published work separates the capability explanation from the contamination explanation.

### 2.3 The cleanest evidence: matched pairs on Terminal-Bench

Terminal-Bench 2.1 is the only public board where a benchmark team ran and verified the runs,
published cost per entry, and carries both a vendor product harness and its own reference harness
on the identical model at matched reasoning effort. That is the closest thing to a controlled
product-versus-minimal comparison in existence.

| Model, effort | Product harness | Reference (Terminus 2) | Delta | Cost ratio |
|---|---|---|---|---|
| GPT-5.5 xhigh | Codex 83.1% ±1.1 | 78.0% ±1.2 | +5.1 | 4.2x ($2,059 vs $494) |
| Opus 4.7 max | Claude Code 68.9% ±1.4 | 66.1% ±1.4 | +2.8 | ~1x |
| Gemini 3 Pro high | Gemini CLI 65.8% ±1.4 | 73.9% ±1.3 | **-8.1** | ~1.1x |
| Gemini 3.1 Pro high | Gemini CLI 65.8% ±1.7 | 65.6% ±1.7 | +0.2 | not reported |

The Opus 4.7 delta of 2.8 points sits inside roughly twice the combined confidence interval. On
the same board the deliberately minimal mini-SWE-agent reaches 76.2% ±1.2 for $198.05, eighth of
seventeen, above Claude Code with Sonnet 5 at 74.6%.

*Confidence: medium-high, with one caveat. The two Gemini rows carry an identical point estimate
for different model generations under the same harness, which looks like a row duplication in
extraction, and the -8.1 result depends on the first of them. Source:
[Terminal-Bench 2.1](https://www.tbench.ai/leaderboard/terminal-bench/2.1). self_eval no, layer
architectural, baseline Terminus 2 at 65.6-78.0%, cost published per entry.*

On the earlier 2.0 board, Anthropic's own Claude Code submission scored **below** the benchmark's
reference harness on every Claude model tested, by 0.8 to 5.7 points, and below the minimal
mini-SWE-agent on two of them. A vendor scoring its own product below a third party's reference is
the opposite of the usual bias direction, which makes it worth more than most vendor numbers.

*Confidence: high. Source: [Terminal-Bench 2.0](https://www.tbench.ai/leaderboard/terminal-bench/2.0),
142 entries. self_eval yes (Anthropic submitted the Claude Code rows), layer architectural,
baseline Terminus 2, cost not reported on this board.*

Note that harness *spread* at fixed model widens rather than narrows on this board: Opus 4.1 spans
3.2 points over 4 harnesses, Opus 4.5 spans 11.4 over 8, Opus 4.6 spans 18.4 over 9, Gemini 3.1
Pro spans 20.8. That contradicts the narrowing in 2.2, and both readings are confounded, the
spread by k growing with submissions and the narrowing by max-selection. Neither should be
load-bearing. One lane in this sweep read this same board as *shrinking* by counting only 2 of the
9 Opus 4.6 entries; the verifier caught it and the finding was dropped.

### 2.4 The one component ablation points away from the config layer

Automated harness evolution lifted Terminal-Bench 2 pass@1 from 69.7% to 77.0%, above the
human-designed Codex CLI at 71.9%, and its ablations "localize the gain to tools, middleware, and
long-term memory rather than the system prompt, suggesting factual harness structure transfers
while prose-level strategy does not".

That sentence is the closest thing in the literature to a direct verdict on our question, and it
says the prose layer is where the gain is not.

*Confidence: low-medium, and deliberately downgraded. Source:
[arXiv 2604.25850](https://arxiv.org/abs/2604.25850). verified=abstract-fetched, so the ablation
table was never seen, only the authors' own one-sentence gloss. self_eval no, though the team's
rank-1 leaderboard entry is self-submitted and is not independent corroboration. layer both,
baseline 69.7%, cost 12% fewer tokens than seed on transfer.*

---

## 3. Q4 and the config layer proper. Does configuration substitute for capability?

This section covers the evidence closest to the actual artifact: skills, instruction files,
gates. Read it before section 2's architectural numbers tempt anyone into a transfer.

### 3.1 The strongest positive result, and why it is an upper bound

SkillsBench mounts expert-curated Agent Skills on 87 containerised tasks across 8 domains with
deterministic pytest verifiers, paired design, same task and container, only Skill access
differing. Task-macro pass rate rises from 33.9% to 50.5%, +16.6 points, averaged over 18
model-harness configurations. All 18 improved, range +4.1 to +25.7. Claude Code with Opus 4.7 goes
43.0% to 61.2%.

*Confidence: high for the numbers, low for their transferability. Source:
[arXiv 2602.12670](https://arxiv.org/abs/2602.12670) v4, page-fetched, PDF extracted locally.
layer config. baseline 33.9% fleet, 43.0% for Claude Code + Opus 4.7, far from ceiling. cost:
Claude Code + Opus 4.7 goes 4.33M to 6.43M tokens, $5.21 to $6.74, +29% for +18.2 points; the
direction is not uniform, OpenHands + Opus 4.7 got both cheaper and better.*

Two caveats belong in the claim, not the footnotes, and both are the authors' own. First, during
task filtering "tasks with no measurable separation between conditions are rejected as
low-signal". **The benchmark is constructed to contain tasks where skills matter.** +16.6 points is
an upper bound on a skill-favourable distribution, not an effect estimate for arbitrary work.
Second, there is no length-matched or irrelevant-text control, so the gain may partly be context
volume rather than procedural structure.

On provenance: SkillsBench is led by BenchFlow, correspondence to xiangyi@benchflow.ai, a
commercial benchmarking company whose product is this benchmark, across 36 listed affiliations
including Berkeley, Stanford, CMU, Princeton and Oxford, with Dawn Song as senior author. No
Anthropic affiliation appears; Anthropic is thanked for model access alongside nine other labs.
So it is not a vendor evaluating its own product, but it is not conflict-free either. One lane in
this sweep affirmatively asserted the absence of a commercial conflict; that was wrong and the
verifier caught it.

### 3.2 What SkillsBench says when you read past the headline

The internals are more useful to us than the headline, and they cut against the way most harnesses
are built.

**More configuration is worse.** Tasks paired with 4 or more skills gained +10.1 points against
+19.0 for 2-3 skills and +18.0 for a single skill. By documentation length: compact +19.0,
standard +21.5, detailed +14.5, "comprehensive" **+0.7**, statistically indistinguishable from
doing nothing. The comprehensive bucket is only N=5 tasks so that specific figure is fragile, but
the decline from standard through detailed to comprehensive holds across 65 tasks. The authors
attribute it to "excess content creates overhead or conflicting guidance".

*Confidence: high. Source: SkillsBench Appendix F.1 (Table 8, N=23/43/21) and F.2 (Table 9,
N=22/22/38/5). layer config, baselines 32.2-39.3% per bucket, cost not reported per bucket.*

**Software engineering is the second-weakest of eight domains.** +11.6 points, against +28.8 for
natural science and +24.1 for media. Only mathematics and OR was lower at +9.7. Thirteen of 87
tasks showed negative deltas, worst -7.4. The authors' explanation is that domains whose
procedural knowledge is underrepresented in pretraining gain most, and domains with strong
pretraining and tooling coverage gain least. Software engineering is the best-covered domain in
any frontier model's pretraining.

*Confidence: high. Source: SkillsBench Table 3, N=16 SE tasks, no-Skills baseline 37.6%.*

The failure taxonomy for those 13 negative tasks is worth reading directly: a skill prescribes a
heavyweight pipeline that crowds out a simpler correct path; skill activation displaces a stronger
native strategy; a skill points the agent at a solver it cannot debug. Common cause, in the
authors' words, "a single correct pipeline without applicability boundaries or lightweight
fallbacks".

**Agent-authored skills are worse than no skills at all.** Having the agent write its own skill
packs with Anthropic's skill-creator, then solve using only those, scored below the no-skills
baseline on all three dedicated-harness configs: -8.1 points on Claude Code + Opus 4.7, -11.3 on
Codex + GPT-5.5, -11.5 on Gemini CLI + Gemini 3.1 Pro. Trajectory audit attributes it to generated
packs the solver never discovers, creator-side authoring displacing solver work, and confidently
wrong pack content when the skills are used.

*Confidence: high. Source: SkillsBench §5.1.1, Table 6, Appendix D.6. baselines 36.0-46.8%. Note
the condition is skills-only, a harsher setting than adding self-written skills on top of a normal
baseline.*

**The right skill often does not fire.** Task-specific skill invocation ranged from 46.4% to 99.2%
across the 18 configs. Claude Code with Opus 4.7 invoked the task's bundled skill in **68.2%** of
curated-skill trials, 178 of 261. That is the easy case: one obviously relevant skill mounted per
task, no distractor library.

*Confidence: high. Source: SkillsBench Appendix K, Table 14.*

### 3.3 The capability-substitution curve

Substitution is real and spans about one tier. Haiku 4.5 with skills (30.1%) beats Opus 4.5
without (23.8%) in the same harness. But Haiku-with-skills is far below Opus 4.7-without (43.0%).

The curve is not monotone decreasing. Normalised gain, the fraction of remaining headroom closed,
runs 23.4% (Haiku 4.5), 23.4% (Sonnet 4.5), 33.1% (Opus 4.5), 24.9% (Opus 4.6), 31.9% (Opus 4.7)
inside the Claude Code harness, roughly flat across a 5x span in bare capability. Yet the two
strongest OpenHands baselines have the smallest gains (15.5% and 12.1%), and the very weakest
model has the smallest of all (4.9%), which kills the simple "scaffolding substitutes for
capability" story from the bottom end: below some floor the model cannot exploit the skill either.
Inverted-U, or noise.

*Confidence: medium, and this is derived arithmetic over leaderboard rows, not a published curve.
Nobody has plotted skill-lift against a continuous capability axis with error bars. Source:
[SkillsBench leaderboard](https://www.skillsbench.ai/leaderboard), updated 2026-07-16.*

The cleanest published statement of capability substitution is at the pure prompt layer, outside
agents. Rewriting a stacked instruction set into a compiled prompt recovered +11.0 points for the
weakest model, +3.3 for the middle, and **-1.2, not significant, for the strongest**. Spearman rho
-0.85 (p=0.004) between a model's raw stacked-instruction-following rate and its recovery from
compilation, across nine models.

*Confidence: medium, downgraded for domain. Source:
[arXiv 2608.02639](https://arxiv.org/abs/2608.02639). Single-turn instruction following, not an
agent loop; 3 models in the main experiment; two authors with no stated affiliation; not obviously
peer-reviewed. layer config, baseline 20-60% at stack size 20, not at ceiling.*

**Nobody has measured skill lift on any model newer than Opus 4.8 or GPT-5.5.** The SkillsBench
leaderboard stops there. There is zero published skill measurement on Claude Opus 5, the model
this project's own null was run on. Every capability-substitution claim above extrapolates past
the last measured point.

### 3.4 The three config-layer nulls

These are the results that most directly answer the question. Two have honest baselines. The third
does not state one at all, and is reported here rather than pooled.

**The 288-run context-file ablation.** Claude Code with Sonnet 4.6 and Codex CLI with GPT-5.5, 17
real tasks from merged PRs in three repos, three conditions (file removed / always in system
prompt / topic wiki retrieved on demand), 3 repeats per task per strategy, correctness scored by
hidden gold tests, run on an egress-locked pod with GitHub DNS blackholed so agents could not read
gold solutions. Claude: 53.3% / 55.6% / 55.6%. Codex: 58.8% / 56.9% / 52.9%. Omnibus permutation
tests p=1.00 and p=0.66. Differences bounded under 10 points (Claude) and 15 points (Codex) by
task-clustered bootstrap. A manipulation probe found the real context file never converted a
near-miss into a pass on either agent.

*Confidence: medium-high. This is the methodological standard the rest of the literature should be
held to. Source: [arXiv 2607.27250](https://arxiv.org/abs/2607.27250), also published as
[a blog post](https://www.developersdigest.tech/blog/context-files-coding-agents-ablation-2026)
by the same single author, Prakhar Khatri. **These are one study, not two.** self_eval no, layer
config, baseline 53.3-58.8%, not a ceiling. cost: selective strategy reduced cache-creation tokens
for Claude (p=0.012), no output-token differences.*

**The AGENTS.md paper.** Four agent-model pairs including Claude Code + Sonnet-4.5, on SWE-bench
Lite (300 tasks) and a purpose-built CTXbench (138 instances from 12 niche repos with
developer-committed context files). LLM-generated context files reduced resolution by 0.5% and 2%,
Cochran-Mantel-Haenszel two-sided p=0.87 and p=0.37. Developer-written files improved by **2.4% on
average, p=0.21, not significant**, and "improve performance for all agents but Claude Code". The
only significant performance comparison was developer-written against LLM-generated, p=0.038.

*Confidence: high. Source: [arXiv 2602.11988](https://arxiv.org/abs/2602.11988). self_eval no,
layer config. baseline is NOT at ceiling: appendix Table 5 gives no-file rates of 59.9%
(Sonnet-4.5), 56.6% (GPT-5.2), 47.7% (GPT-5.1 Mini), 31.1% (Qwen3-30B) on SWE-bench, and 73.2 /
65.2 / 54.3 / 45.7 on CTXbench. cost: significant at p<0.00001, +20% and +23%, +2.45 and +3.92
steps; Sonnet-4.5 goes $1.30 to $1.51.*

Two corrections to the way this paper circulates, both caught by the citation verifier. The effect
is **+2.4%, not +4%**; two lanes in this sweep reported +4%, which appears nowhere in the paper.
And one lane fabricated an entirely different set of eight baseline percentages for it. The real
Table 5 numbers are roughly 20 points higher than the fabrication and materially weaken the
anti-ceiling argument the fabricated numbers were used to make. This is worth stating plainly: the
single most-cited config-layer null in this literature is routinely misquoted, in both directions,
by people summarising it.

The mechanism finding is the interesting part. Instructions *are* followed. Specific tooling
instructions were followed 1.6 to 2.5 times more often when mentioned. The files change behaviour
without changing outcomes, and they cost 20% more because following them takes steps. Repository
overviews, present in 95-100% of generated files and recommended by every model provider, did not
reduce steps to find relevant files. Agents took *more* steps before first touching a file in the
gold patch when a context file was present.

**The Agent Skills CTF ablation.** Four documentation levels spanning 591 to 36,001 tokens, 180
controlled runs, +8.9 points with 95% CI [-6.8, +24.6], p=0.71.

*Confidence: low, and it must not be pooled with the other two. Source:
[arXiv 2605.20023](https://arxiv.org/pdf/2605.20023). The no-Skills baseline percentage is never
stated, so floor and ceiling cannot be ruled out; this is a live instance of the exact failure mode
this report exists to avoid. It is also offensive CTF, not software maintenance, and it is a
re-analysis of someone else's 180-run study, not an independent run. The usable finding is the 60x
token spread for no correctness gain.*

### 3.5 Structure of the config file does not matter; session length does

A factorial study over 1,650 Claude Code sessions and 16,050 function-level observations
manipulated four things: file size, instruction position, file architecture, and contradictions in
adjacent files. **None of the four survived multiple-comparison correction.** Nor did any of three
two-way interactions.

The one large effect was within-session decay: each additional generated function carries about
5.6% lower odds of compliance, OR = 0.944 per step.

*Confidence: high for the nulls and the decay slope. Source:
[arXiv 2605.10039](https://arxiv.org/abs/2605.10039). layer config. Important limit: the outcome is
compliance with a trivial target annotation, not task correctness, and nobody has tested whether
the same decay applies to substantive instructions such as architecture constraints or
verification discipline. For an always-on instruction file, that is the load-bearing question and
it is unanswered.*

Corroborating from outside agents: instruction-following degrades continuously with density, with
the best frontier models reaching only 68% accuracy at 500 simultaneous instructions, and a
measured bias toward earlier instructions ([IFScale, arXiv 2507.11538](https://arxiv.org/abs/2507.11538),
abstract-fetched, July 2025 so two generations stale, keyword inclusion is a weak proxy for
behavioural guidance; confidence low-medium).

### 3.6 The one full-bundle-versus-bare measurement

This is the single most on-target experiment anyone has published, and it deserves its own
subsection.

A third-party A/B mounted the **Superpowers** skills harness against bare Codex on 500 tasks across
four benchmark families (SWE-bench Verified 174, Pro 54, PolyBench 116, Multi-SWE 156), 59 repos, 8
languages, gpt-5.4 at high reasoning, same tasks both arms.

| | Baseline | Superpowers |
|---|---|---|
| pass@1 | 45.6% (228/500) | 47.8% (239/500) |
| tokens/task | 1.56M | 2.18M |
| runtime/task | 6m13s | 7m26s |
| agent actions/task | 41.1 | 49.5 |

**+2.2 points, not significant, for +40% tokens, +20% wall clock and +8.4 actions per task**, with
the cost increases reported as significant.

The most interesting number is not the headline. Wins were substantially disjoint: Superpowers
solved 41 tasks the baseline missed, and the baseline solved 30 that Superpowers missed. The
harness "changed the failure surface" rather than dominating it. About 4.9 skills fired per task
(using-superpowers 1.00, verification-before-completion 0.98, TDD 0.97, brainstorming 0.97).

*Confidence: medium-high. Source:
[Norbert Laszlo, AgentStackBench](https://norbert-laszlo.medium.com/can-a-plugin-improve-codex-benchmarking-the-superpowers-plugin-05d020066565).
Medium hard-403s WebFetch and curl; retrieved through r.jina.ai's text proxy, so the figures are
from full article text rather than search snippets, and the raw comparison JSON on GitHub
independently confirms 45.6% and 47.8%. self_eval no, this is a third party testing someone else's
harness. layer config. **baseline 45.6%, well below ceiling, so this null is informative.**
Two caveats: the published config shows the treatment arm also received an extra prompt telling the
agent to use the mounted resources for planning, test-first thinking and verification discipline,
so it is not a pure resources-only contrast; and the exported bundle contains no p-value fields, so
"not significant" is the author's assertion and is not checkable from the data.*

Note what this is not. It is Superpowers on **Codex**, not on Claude Code, and not on a Claude
model. The obvious experiment, a Claude Code harness against bare Claude Code on a Claude model,
has not been run publicly by anyone.

---

## 4. Q3. Variance, tails, and the strongest part of the case

The hypothesis worth testing was that a harness cuts the bad tail rather than raising the mean.
The answer splits cleanly in two, and the split is the most useful thing in this report.

### 4.1 Statistical variance: nobody has measured it

**No published study reports a variance statistic (standard deviation across seeds, p95,
interquartile range, worst case) for a coding agent with a config-layer harness on versus off,
model and task held fixed.** Every scaffold comparison verified in this sweep reports means. Every
variance and reliability study verified holds the scaffold constant.

The HAL Reliability Dashboard is the clearest illustration. Twelve metrics including outcome
consistency, calibration, Brier score, fault tolerance, prompt sensitivity, harm incidents and
compliance violations, across 15 agents on GAIA and tau-bench. Every result is conditioned on
**model only**. It is precisely the place a scaffold-conditioned variance number would live, and
it is not there.

*Confidence: high, as gap evidence. Source: [HAL Reliability Dashboard](https://hal.cs.princeton.edu/reliability/).*

Related absences, each verified: no pass^k or reliability@k number conditioned on scaffold; no
scaffold-conditioned catastrophic-outcome rate for irreversible filesystem or VCS damage
specifically; no published power analysis for any scaffold comparison. Miller's *Adding Error Bars
to Evals* ([arXiv 2411.00640](https://arxiv.org/abs/2411.00640)) supplies the power-analysis
machinery and is written entirely at the question level for static benchmarks, with no mention of
agents, trajectories or scaffolds. Nobody has applied it to the scaffold contrast.

That matters directly for this project. A 12-instance or 16-observation comparison is underpowered
by roughly two orders of magnitude against plausible effect sizes, and no primary source publishes
the run-to-run standard deviation needed to compute how underpowered.

### 4.2 Behavioural tails: config-layer text produces very large effects

This is where the honest case lives, and the effects are not small.

**Prompt strictness moves cheating from >85% to 1%.** ImpossibleBench mutates LiveCodeBench (103
tasks) and SWE-bench (349 after QC) so tests contradict the spec, making any pass a spec-violating
shortcut. Four prompt variants from loosest to strictest: GPT-5 goes from over 85% to 1%, o3 to
33%. Adding an explicit "declare this task impossible" abort option cut GPT-5's cheating on
Conflicting-SWEbench from 54% to 9% and o3's from 49% to 12%.

*Confidence: high. Source: [arXiv 2510.20270](https://arxiv.org/abs/2510.20270). self_eval no,
layer both, baseline >85% and 54%, enormous headroom. cost: not in tokens; the behavioural cost is
that the hidden-test condition degrades legitimate performance.*

**An anti-cheat instruction block cut CTF cheat propensity from 33.0% to 8.5%** with no degradation
in legitimate solve rate, sometimes improvement. 22 models, 23 challenges, all 1,518 traces
audited. The authors call prompts "an effective and essentially free first layer of defense, but
not a substitute for environmental controls".

*Confidence: high. Source: [arXiv 2607.21763](https://arxiv.org/abs/2607.21763). layer config,
baseline 33.0%, cost essentially free.*

**Stripping consent declarations raised Claude Code's destructive out-of-scope action rate from
0.0% to 17.1%.** OverEager-Bench, 500 validated scenarios, roughly 7,500 runs, 4 agent products
across 6 base models. "Overeager" means deleting unrelated files, wiping a stale credentials
backup, rewriting config unasked. That 0.0% to 17.1% shift, p=2.4e-4, is a genuine within-product
config ablation.

*Confidence: medium-high for the within-product ablation. The frequently quoted comparison of
permissive frameworks (5.4-27.7%) against OpenHands ask-to-continue (0.2-4.5%) is a whole-product
confound across different models, prompts and tool surfaces, not a gating ablation, and should not
be cited as one. Source: [arXiv 2605.18583](https://arxiv.org/abs/2605.18583). layer both, cost of
the gate not measured.*

**A retrieval skill cut test-level regressions by 70%**, 6.08% to 1.82%, on SWE-bench Verified. The
vanilla baseline caused 562 pass-to-pass test failures across 100 instances, roughly 6.5 broken
tests per patch.

*Confidence: medium, with a caveat that changes the lesson. Source:
[arXiv 2603.17973](https://arxiv.org/abs/2603.17973). Authors evaluating their own tool. Qwen3-Coder
30B on 100 instances and Qwen3.5-35B on 25, open-weight models on consumer hardware, so this does
not transfer automatically to a frontier model. The resolution-rate arm (24% to 32%) runs on n=25
with an unnamed harness. Cost is reported as zero overhead, which is not credible for an
intervention that adds AST graph construction plus extra test executions.*

**The control arm is the most decision-relevant number in the paper**: prose TDD instructions
*without* the retrieval context made regressions **worse**, 9.94% against a 6.08% baseline. The
retrieval did the work. Exhortation was net-negative.

**And the counterweight.** Adding blast-radius cues to underspecified DevOps instructions "barely
reduce action propensity", while 55.8% to 67.8% of runs still violate at least one action boundary
across Claude Code, Codex and OpenCode. Underspecification does not make agents fail, it makes
them guess unsafely instead of asking.

*Confidence: medium. Source: [arXiv 2607.02294](https://arxiv.org/abs/2607.02294). layer config,
baseline 55.8-67.8%, mid-range so the null is informative.*

**Quality guidance shifts the intercept but not the slope.** SlopCodeBench, 36 problems, 196
checkpoints where agents repeatedly extend their own solutions, 15 agents. Explicit quality
guidance cut initial verbosity and structural erosion by up to a third **without affecting
degradation rates**. Structural erosion rises in 77% of trajectories regardless; agent code is 2.3x
more verbose and 2.0x more eroded than 473 open-source Python repos.

*Confidence: medium. Source: [arXiv 2603.24755](https://arxiv.org/abs/2603.24755). baseline: best
agent passes 14.8% of checkpoints, no ceiling.*

### 4.3 The pattern

Config-layer text reliably suppresses **intentional** shortcut-taking: cheating, test-gaming,
unrequested destructive actions. It unreliably suppresses **unintentional** scope creep, and it
does not change the *rate* at which quality decays over a long session, only where that decay
starts.

That is a coherent and defensible claim, it is supported by four independent studies at non-ceiling
baselines, and it is not a claim about output quality.

---

## 5. Q2. Where does scaffolding help? Ranked, with the evidence separated from the reasoning

### Supported by data

Each rank carries its layer tag, because architectural evidence does not transfer to the config
layer and section 11 draws on this list.

**1. Weaker and mid-capability models.** *(layer: architectural.)* Harness spread at fixed model is 27.4 points on Qwen
3.6-flash against 12.5 on GLM 5.1 over the same 350 tasks ([Claw-SWE-Bench](https://arxiv.org/html/2606.12344v1),
page-fetched, high confidence). Harness-Bench reports stronger backends showing lower cross-harness
variance. Note this points *against* harness value on frontier models, which is the opposite of how
it is usually cited. Caveat: this is two model families of different sizes, not a fitted curve, and
Terminal-Bench 2.0's widening spread has the opposite sign.

**2. Cost, not correctness.** *(Both layers, and they must be kept apart.)* This is the
best-evidenced finding in the entire sweep and nobody markets it.

At the **config layer**, where the evidence is thinner but directly on point: context files cost
+20% and +23% inference for no correctness gain; the Superpowers bundle cost +40% tokens and +20%
wall clock for +2.2 points; SkillsBench's Claude Code arm cost +29% for its +18.2 points; the CTF
skills ablation spanned 60x in documentation tokens for a non-significant +8.9. One result points
the other way and is unresolved: AGENTS.md presence associated with 28.6% lower median runtime and
16.6% lower output tokens on real PR tasks, though that paper reports no statistical test and no
absolute completion baseline ([arXiv 2601.20404](https://arxiv.org/abs/2601.20404), low
confidence). The two disagree, probably because one measures agent-written PRs and the other
SWE-bench with injected files, and nobody has reconciled them.

At the **architectural layer**, where the numbers are much larger and are the ones usually quoted:
three harnesses on the same model differ by 0 to 8 points in pass rate, with bootstrap
CIs mostly including zero, while differing by up to **40.8x in tokens per solved task**
([arXiv 2607.22585](https://arxiv.org/html/2607.22585), 300 trials, baseline 48-50%, high
confidence). SWE-Marathon: holding the model fixed, median tokens per trial varies **up to 12x**,
gpt-5.5 using 0.40M under Terminus 2 against 4.8M under Codex. HAL: SeeAct with GPT-5 Medium costs
$171 for 42% while Browser-Use with Claude Sonnet 4 costs $1,577 for 40%, a 9x cost difference for
2 points. Across 35 sequential releases of one harness with the model held constant, resolve rate
stayed flat around 30.5% while tokens rose 70%, 391K to 668K per task
([arXiv 2607.03691](https://arxiv.org/abs/2607.03691), Spearman rho 0.208 p=0.231, baseline
23-39%, no ceiling).

**3. Which instances, not how many.** *(layer: config.)* A natural-language config harness on SWE-bench Verified: full
config 74.4%, without runtime skill 76.0%, without harness skill 75.2%. **Both ablations beat the
full config.** Agreement tables show over 110 of 125 instances identical between full and each
ablation. The authors' own words: "Full IHR behaves more like a solved-set replacer than a uniform
frontier expander." The disjoint-wins pattern in the Superpowers A/B (41 versus 30) is the same
shape.

*Caveat that the claim needs: this sits in a 74.4-76.0% band where the corpus's own top published
score is 79.2%, so roughly 4 points of visible headroom on n=125. Close to a ceiling artifact.
Source: [arXiv 2603.25723](https://arxiv.org/html/2603.25723v1), medium confidence.*

**4. Non-obvious project-specific knowledge.** *(layer: config.)* Developer-written context files helped +2.4% overall
(p=0.21) and only on niche repositories, while LLM-generated repository overviews scored -0.5% and
-2%. Weak, not significant, but the sign is consistent and the mechanism is plausible: a file
carries value only when it holds something the model does not already know, and for popular Python
repos it does not.

### Supported by reasoning only, and flagged as such

**5. Long-horizon and multi-session work.** *(layer: config, and unmeasured.)* Every harness author says this is where the value lives.
The only horizon-linked measurement anyone has published is config-file adherence decaying at OR
0.944 per generated function, which is adherence rather than correctness. No config-layer study in
this sweep used anything but single-session, single-issue tasks. This ranking rests on a mechanism
argument, not on data.

### Negative on data

**6. Extreme multi-file complexity produces a floor, not amplified benefit.** *(layer: architectural.)* On 200
high-complexity feature tasks averaging 790 LOC across 15.7 files, swapping the harness under a
fixed Opus 4.5 moved resolve rate by 0.5 points: Claude Code 11.0%, OpenHands 10.5%. The same
models score 74.4% on SWE-bench and 5.2% on FeatureBench tasks drawn from the same repos. Past some
complexity, everything fails equally.

*Confidence: medium. Source: [FeatureBench, arXiv 2602.10975](https://arxiv.org/html/2602.10975v1).*

### The interaction nobody has estimated

The hypothesis that benefit appears past a complexity threshold has **never been tested directly**
on coding tasks. The nearest thing is a pre-registered GAIA study where the scaffold effect
*reverses sign* with difficulty for the same model: Opus with ReAct is 12.6 points better than
planner-executor on Level 1 tasks and 14.0 points worse on Level 2
([arXiv 2606.08529](https://arxiv.org/abs/2606.08529), n=139, high confidence, but GAIA is not a
coding benchmark).

The near-misses are almost comic. One study drew a difficulty-stratified 50-task sample (20 easy /
25 medium / 5 hard) and then reported only the pooled 30.5% resolve rate. Scale's SWE-bench Pro
publishes stratification by language, repository and solution complexity, and runs a second scaffold
on some models, but never crosses the two axes. No leaderboard or paper reports scaffold A against
scaffold B within a SWE-bench Verified difficulty tier.

One suggestive signal, worth a study rather than a citation: in a 45,769-task difficulty model,
prompt linguistic features enter the top predictors **only in the mid-difficulty band**. The same
work finds 49.8% of tasks always pass and 32.5% always fail under a fixed configuration, so only
about **18% of tasks sit in the band where any intervention could move the outcome**
([arXiv 2608.18280](https://arxiv.org/abs/2608.18280), AUC 0.863, high confidence). If that
transfers, an experiment that does not deliberately sample the mixed-outcome stratum is spending
82% of its budget on tasks whose result was decided before the harness loaded.

---

## 6. Q5. What harness authors claim, and what they measure

The ledger is short because most of it is empty.

| Harness | Claimed | Measured against a bare-agent control |
|---|---|---|
| Superpowers | "up to 50% faster and up to 60% cheaper" | Nothing. All deltas are against **prior Superpowers releases**. |
| gstack | "~810x my 2013 pace" | Nothing. Human-2013 against human-2026-with-frontier-models. |
| SuperClaude | "2-3x faster, 30-50% fewer tokens" | Nothing. Figures attributed to third-party MCP servers. |
| koudicz/claude-harness | "~60% cost reduction", "~70% thinking-token reduction" | Nothing. Cost-accounting identities over pricing tiers. |
| wshobson/agents | none quantitative | Nothing. Its "plugin-eval" scores the config files, not outcomes. |
| Anthropic (Claude Code skills) | "verification skills have had the most measurable impact on Claude's output quality internally" | Nothing published. |
| Tessl registry | per-skill multipliers 1.32x-1.78x | Control implied, but no n, no model, no task list, no CIs. |
| Cognition Devin Fusion | "35% lower cost", later "up to 60% cheaper" | Vendor benchmark, vendor harness. Fusion 63.1 at $1.35/task against Fable 5 at 64.9 for $10.53. Lower correctness, 8x cheaper. |

*All rows page-fetched, high confidence except Tessl (low) and Cognition (medium). Every row is
self_eval yes except the Cognition comparator.*

Three observations that generalise.

**No harness author anywhere publishes a bare-agent control arm.** Superpowers' own public eval
suite grades "skill triggering, worktree behavior, subagent coordination, verification reflexes,
review quality, and cost-shaping patterns", which is workflow compliance rather than task
correctness, describes no no-Superpowers condition, and gitignores its results directory. A
community issue asking for exactly this experiment (obra/superpowers#1462, proposing a fixed test
dataset, accuracy/latency/token metrics and automated baseline comparison) was closed by the
maintainer as "too vague to be in any way actionable".

To the project's credit, the same blog post states outright: "Building software with Superpowers is
slower than building without it."

**The only numbers harness authors produce are cost numbers**, because those are cheap to compute.
Correctness numbers require a control arm nobody runs.

**Anthropic is the clearest case of a vendor with the apparatus and no published numbers.** It ships
skill-measurement tooling inside skill-creator with executor, grader, blind-A/B comparator and
analyzer subagents, tracking eval pass rate, elapsed time and token usage with skill against
without. It logs skill firing internally to find "skills that are popular or are undertriggering
compared to our expectations". It has published no with-skill versus without-skill efficacy
number. The word "measurable" appears in its engineering post without a measurement.

One genuinely encouraging artifact exists and had published nothing as of 2026-08-22: a
pre-registered three-arm A/B/C of plain Claude Code against Superpowers v6.2.0 against OpenSpec, on
roughly 2,650 Python files of live operations code, with hidden characterization-test oracles,
blind multi-vendor scoring, and metrics frozen before any run, promising "results get published
either way, including if the plain baseline wins"
([tonydzi/harness-abc-bench](https://github.com/tonydzi/harness-abc-bench), runs scheduled
2026-08-12 to 21). It is n=3 tasks, so even a clean win would be underpowered, and the authors
disabled four Superpowers skills in Arm B, which is a real confound. It is nonetheless the only
pre-registered publish-either-way harness comparison anyone has attempted.

---

## 7. Q6. Does thoroughness instruction raise false positives?

**Yes, the direction is a published, measured phenomenon, replicated across three domains.** The
magnitude in this project's own run is not comparable to anything published, because nobody
measures the same quantity.

The core study manipulates review prompt thoroughness in three levels (binary verdict; verdict plus
explanation; verdict plus explanation plus proposed fix) across 5 models, 3 benchmarks and roughly
1,400 paired instances, each task paired canonical against buggy.

Rejection of **correct** code rises as the prompt gets more demanding, while acceptance of buggy
code falls:

| Model, benchmark | Direct | +Explain | Full |
|---|---|---|---|
| GPT-4o, HumanEval | 26.2% | 58.5% | 73.2% |
| GPT-4o, MBPP | 35.9% | 74.1% | 87.9% |
| Claude-4.5-sonnet, HumanEval | 26.2% | 34.1% | 36.0% |
| Claude-4.5-sonnet, MBPP | 58.5% | 55.7% | 62.3% |

In absolute operational terms: GPT-4o on MBPP goes from 184 false rejections to 451, while false
acceptances go 19 to 0.

*Confidence: high for the direction and the numbers. Source:
[arXiv 2603.00539](https://arxiv.org/abs/2603.00539), journal version DOI
10.1007/s10515-026-00638-5 (Springer 303-redirects to auth; the arXiv PDF was extracted locally).
self_eval no, layer config, baseline is the binary prompt and is NOT at ceiling, already
misrejecting 25-58% of correct implementations. cost not reported, which is its own gap given the
Full prompt emits a rationale and a patch for every rejection.*

**The effect is not monotonic**, despite being widely described that way including in this sweep's
own first pass. Claude-4.5-sonnet on MBPP goes down then up; QuixBugs is flat before rising;
Gemini-2.0-flash is an outright exception; Llama-3.1-8B reverses at a near-ceiling 91.9%.

What the spurious rejections consist of matters more than the rate. Of 4,190 false-rejection
rationales, **87.2% are asserted algorithmic defects with no falsifiable counterexample** (Logic
Error 48.2%, Added Requirement 14.1%, Boundary Error 13.2%, Misread Spec 11.7%). Style and
performance nitpicks together are under 4%. The authors: over-correction is "primarily driven by
unverified claims and requirement hallucination (inventing unstated constraints), rather than
superficial style critique".

The direction replicates outside code. An inclusion-biased directive in systematic-review screening
multiplied false positives roughly 17x for one model while raising recall about 12 points
([OLIVER, arXiv 2512.20022](https://arxiv.org/abs/2512.20022), high confidence). Requiring an LLM
safety monitor to quote concrete evidence reduced miss rate but "increased false alarms sharply"
([AutoMonitor-Bench, arXiv 2601.05752](https://arxiv.org/abs/2601.05752), directional only, no
per-model table extractable).

Two things fix it, and neither is a better prompt. Execution-grounded verification, running the
model's own proposed fix and reverting the verdict when the fix is behaviourally equivalent, cut
false-rejection rate by 7.5 to 67 points across models, at a small rise in false acceptance. In
industry, LLM triage over a static-analysis stream with a 76% false-positive prevalence removed
94-98% of false positives at high recall for $0.0011-$0.12 and 2 to 110 seconds per alarm, against
10 to 20 minutes of manual inspection.

Field evidence for the magnitude of the underlying problem: the fraction of genuine curl security
submissions fell from "north of 15%" historically to below 5% in 2025, with roughly 20% identified
as AI slop, and the bug bounty was terminated in January 2026. The same maintainer's counter-signal
matters equally: purpose-built AI analyzers submitted 400+ suspected issues of which roughly 50
became merged bugfixes with "remarkably few of them complete false positives". False-positive rate
is a property of the pipeline, not of "AI".

*Confidence: medium, anecdote-grade for effect size, strong for existence. Sources:
[end of the curl bug-bounty](https://daniel.haxx.se/blog/2026/01/26/the-end-of-the-curl-bug-bounty/)
and the same author's "A new breed of analyzers".*

One design artifact worth noting because it is a vendor independently reaching the same model:
Anthropic's own `/code-review` skill encodes thoroughness as an explicit precision-to-recall knob.
High effort "favors recall with three finder angles, recall-biased verification, and up to ten JSON
findings", where verification "treats realistic uncertain findings as plausible unless code refutes
them"; medium effort "favors precision with one-vote verification, and up to eight JSON findings".
Finding caps scale 4 / 8 / 10 by tier. No efficacy numbers accompany it.

### What this does and does not say about our number

Our measured precision drop (92% to 73% at identical recall) is **directionally consistent** with a
measured phenomenon and is not n-of-1 in direction. In magnitude it is uncomparable: every
published measurement uses per-instance binary verdicts, and nobody measures per-finding precision,
the fraction of emitted review comments that are real, as a function of thoroughness instruction.

But there is a mismatch worth taking seriously. In the published pattern, the thorough prompt
**buys something**: false acceptance drops as false rejection rises. Our run raised false positives
at *identical* recall. If that holds, we paid over-correction's cost without its benefit, which is
the more damning reading and is not what the literature predicts.

---

## 8. Q7. Benchmarks for what SWE-bench does not measure

The frozen list, every row reported including the ones whose verdict is "nobody ran a scaffold
comparison". Only three of these have ever had a config-layer arm.

### Requirement ambiguity

**ClarEval** ([arXiv 2603.00187](https://arxiv.org/html/2603.00187v1)). 2,250 instances from 750
tasks across 3 ambiguity types. Metrics: Average Turns to Clarify, Key Question Coverage,
Multi-turn Pass Rate. 8.94% pass@1 under ambiguity against 89.02% clarified, roughly 80 points of
headroom. **No scaffold ablation**; a single unified clarification instruction is applied to all
agents, and different agent products are conflated with different models so any harness effect is
unidentifiable. High confidence.

**Ask or Assume** ([arXiv 2603.26233](https://arxiv.org/html/2603.26233v1)). The cleanest
scaffold-versus-control separation in this area: an uncertainty-aware multi-agent scaffold beat the
single-agent baseline 69.40% against 61.20% (p<0.001) on an underspecified SWE-bench Verified,
nearly recovering the 70.80% fully-specified ceiling, at $3.50 against $2.03 per task. Architectural,
not config. High confidence.

### Regression avoidance

**TEBench** ([arXiv 2605.06125](https://arxiv.org/abs/2605.06125)). Project-level test evolution
across 314 Defects4J instances. Does evaluate three real agent CLIs across six models in seven
configurations, F1 45.7-49.4%, which bounds any framework effect at about 4 points, but the fetched
content does not confirm a clean same-model factorial. Medium confidence.

**SWE-CI** ([arXiv 2603.03823](https://arxiv.org/abs/2603.03823)). Zero-regression rate over CI
loops, 100 repo-level tasks averaging 233 days and 71 commits of history. Most models below 0.25;
only Claude-Opus models exceed 0.5. **Does not disclose which harness produced the numbers**, let
alone vary it. Regression avoidance is the single loudest harness claim and the one benchmark built
to measure it does not report the scaffold. Medium confidence.

**SWE Atlas** ([arXiv 2605.08366](https://arxiv.org/html/2605.08366v1)). The only benchmark
publishing a clean same-model native-CLI against minimal-scaffold comparison: GPT-5.4 Codex CLI
43.49% vs mini-SWE-agent 38.00% (+5.49); Opus 4.7 Claude Code 41.89% vs 38.94% (+2.95); Gemini CLI
25.23% vs 23.73% (+1.50). Authors attribute the gain to sub-agent delegation, planning and TODO
operations, and note native scaffolds do 1.5 to 2x more exploration. Also: pass3 (3 of 3 trials)
drops 30-50% from pass@1. Scale AI, high confidence, architectural.

**TDAD** ([arXiv 2603.17973](https://arxiv.org/abs/2603.17973)). Covered in 4.2. The only
config-layer regression result, on weak open-weight models with n as low as 25, authors evaluating
their own tool.

**REAP/Harvest**, indexed as ProdCodeBench ([arXiv 2604.01527](https://arxiv.org/abs/2604.01527)).
Production-derived from real developer-agent sessions, solve rates 42.9-58.2%. Scores fail-to-pass
only; **no regression metric**, no scaffold comparison. Low confidence, title and figures unstable
across arXiv revisions.

### Multi-session and long-horizon

**SWE-EVO** ([arXiv 2512.18470](https://arxiv.org/abs/2512.18470)). 48 release-note-derived tasks,
average 21 files changed, ~874 tests per instance. 25% with GPT-5.4 + OpenHands against 72.80% on
SWE-bench Verified. Single scaffold. ~75 points of headroom and no ceiling problem.

**SWE-Marathon** ([arXiv 2606.07682](https://arxiv.org/html/2606.07682v1)). 13 agent-model configs x
20 tasks x 5 trials = 1,300 trajectories. Runs the same model under its native vendor CLI and under
a minimal harness: native CLIs win by roughly 4 to 8 points at a sub-30% baseline. Those deltas are
read from a figure, with no CIs, at 14-28% pass rates over 20 tasks, so treat them as directional
rather than as an effect size. The solid number is cost: holding the model fixed, median tokens per
trial varies **up to 12x** by harness. Also relevant to honesty: 13.8% of rollouts contain
exploit-shaped actions and 10.2% ship clear bypasses, yet 0 of 1,300 earn positive reward against
the multi-layer verifier. **That harness-versus-exploit-rate comparison is sitting in their released
trajectories and has not been run.**

**Long-Horizon-Terminal-Bench** ([arXiv 2607.08964](https://arxiv.org/html/2607.08964v1)). 46 tasks,
15 models, mean pass 4.3%, best 15.2% at v1. Tasks average 231 episodes, 9.9M tokens, 85.3 minutes.
Full cost tables published, $10.2/task average. Deliberately holds the harness fixed at Terminus-2.
**Version-pin any citation**: the current version reports a stronger model at 28.3%, so "best
15.2%" is now false unless pinned to v1.

**ChainSWE** ([arXiv 2607.02606](https://arxiv.org/html/2607.02606)). Sequential dependent bug fixes
sharing files in one repo, reporting up to a 70% drop as chain length grows. Search-summary only;
the page did not fetch. **Treat all figures as unverified.** No scaffold comparison surfaced.

**EvoCode-Bench** ([arXiv 2605.24110](https://arxiv.org/abs/2605.24110)). 26 stateful tasks, 227
rounds, workspace preserved 5-15 rounds. The highest single-round agent ranks only third on
multi-round; single-round exceeds multi-round by 22 to 40 points for most agents. Exactly the
signal a memory or TODO-persistence harness would target, and nobody has ablated it. Low
confidence, search-summary only.

**RoadmapBench does not exist.** Targeted search returned no page, arXiv entry or repo. Recorded as
a negative result rather than silently dropped. The "agent maintains and revises its own plan
document across sessions" shape is covered only obliquely.

**METR time horizon** is unusable for harness comparison. Its own published limitations note,
fetched directly, does not discuss scaffolding or elicitation at all and does not name the scaffold
used. The Vivaria-to-Inspect migration deltas (GPT-4o -35%, o3 -17%, Opus 4.5 -7%) are fully
confounded: the same migration grew the task suite from 170 to 228 tasks and 8h+ tasks from 14 to
31. Only 2 of 3 deltas are significant. Do not cite this as a capability-moderated scaffold effect.

**Vending-Bench 2** ([Andon Labs](https://andonlabs.com/evals/vending-bench-2)). Year-long agentic
coherence, not coding. One number circulating from this sweep was wrong: the live board ranks Claude
Opus 5 first at $11,181.87, not Opus 4.6 at $8,017.59 (7th). No human-operator baseline is
published, only an estimate that good play "could easily do 10x better".

### Refusing to claim completion

**This is the headline gap. No benchmark scores "the agent asserted the task is complete while the
repository's test suite is red" on coding tasks.** Three artifacts come close and each misses.

**False Success** ([arXiv 2606.09863](https://arxiv.org/abs/2606.09863)) measures exactly the
phenomenon at scale, 9,876 tau2-bench plus 1,879 AppWorld trajectories, finding **75.8% of AppWorld
coding-agent failures are false successes**. It also finds LLM judges cannot detect it: no
configuration across 5 judges x 5 prompt strategies exceeds AUROC 0.65, while a TF-IDF detector
reaches 0.83 to 0.95 at 3,300x lower latency. But it varies **judges, not scaffolds**. High
confidence, and the single most important source for this gap.

**Confident and Wrong** ([arXiv 2603.25764v3](https://arxiv.org/abs/2603.25764v3)) measures the
submit-versus-resolve gap: GPT-5 submits a patch on 100% of runs and resolves 44%; Llama 4 submits
99% and resolves 18%; Gemini submits 70% and resolves 50%. It reports that lightweight pre-edit
prompts do not close the gap, which is the only config-layer datapoint here. Two problems: SWE-bench
forces patch submission, so a 100% submit rate is partly a harness artifact rather than
overclaiming, and **v2 of this arXiv ID is a different paper**, retitled and rescoped. Version-pin
or do not cite.

**Auditing Games for Sandbagging** ([arXiv 2512.07810](https://arxiv.org/abs/2512.07810)) is
recorded explicitly as a **non-match** so the frozen-list row is not mistaken for coverage. It
measures whether a blue team can detect red-team-finetuned models that conditionally underperform.
That is deliberate capability concealment in weights, not an agent asserting a coding task is done.

**Inspect Evals** carries deception and sandbagging evals (a 180-scenario Deception Tendency Rate; a
30-problem AIME goal-sandbag task) but all chat and QA shaped, none repo-shaped. Low confidence,
search-summary only.

**Building to the Test** ([arXiv 2606.28430](https://arxiv.org/abs/2606.28430)) shows agents
satisfying an honest completion oracle while leaving the artifact dead or absent, but on **n=18 runs
of a single task**, far too small for the generalisation its title implies.

### Cost-aware and convention adherence

**HAL** ([arXiv 2510.11977](https://arxiv.org/abs/2510.11977)) is the cost-aware leaderboard: 21,730
rollouts, 9 models, 9 benchmarks, ~$40,000, 2.5B tokens of logs released. It treats scaffold as a
first-class factor and finds task-specific scaffolds beating a generalist on 11 of 12 SWE-bench
Verified Mini runs and 9 of 12 CORE-Bench Hard runs, while the generalist cost less in 20 of 24
comparisons. Its sharpest cost example confounds scaffold with model. Higher reasoning effort
**reduced** accuracy in a majority of runs.

Its appendix Table A19 contains the most striking single result in this sweep. Under the strong
SWE-Agent scaffold, scores **plateau at 54.0%** across seven months of model releases, with
February-2025 Claude 3.7 Sonnet High tying August-2025 Claude Opus 4.1. Under the weak generalist
scaffold the same models spread across 0 to 46%. Model generation buys nothing under a good
scaffold and everything under a bad one. At n=50 the standard error is about 7 points, so the 8 to
12 point Anthropic-line gaps are not individually significant while the 34 to 48 point OpenAI
reasoning-model gaps are.

**FrontierCode** (Cognition, vendor) scores scope discipline, mechanical cleanliness and convention
adherence alongside regression safety, over 150 maintainer-authored tasks at 40+ hours per task.
Best model 13.4% on the hard split. Enormous headroom, no scaffold comparison, and it does not state
which harness each model ran under.

**No benchmark measures whether a patch matches the surrounding code's implicit conventions.**
FrontierCode and SWE Atlas use LLM rubrics, which the False Success result suggests are near-chance
at related discriminations; SlopCodeBench uses mechanical erosion proxies; CodeAlignBench measures
following explicit constraints, a weaker construct.

---

## 9. What nobody has measured

Stated as findings, because each is a real absence confirmed across multiple lanes and survived the
verification pass that killed six false "nobody has measured X" claims.

1. **Any Claude Code harness against unconfigured Claude Code on a Claude model.** The one serious
   500-task A/B ran Superpowers on Codex with gpt-5.4. The obvious experiment has not been run
   publicly by anyone.
2. **Variance or tail statistics with a config layer on versus off**, model and task fixed. No SD,
   no p95, no pass^k, nothing. This is the central gap, and it is the one that would settle whether
   a config layer earns its cost on frontier models.
3. **Hooks as a category, on coding tasks.** The nearest analogue is a deterministic pre-execution
   gate study (+10.4 points frontier, +12.4 budget, near-zero cost,
   [arXiv 2607.07405](https://arxiv.org/html/2607.07405)) which is non-coding (airline customer
   service), carries a stated major confound in that the gates encode the same policy the verifier
   scores, and whose frontier arm the authors themselves label "suggestive only" because it was
   never replicated. Nobody has measured a Stop-hook verification gate against no gate.
4. **Subagent definitions at the config layer.** Architecture comparisons of multi-agent against
   single-agent exist. Nothing measures description-selected subagent definitions against the same
   CLI with none defined.
5. **Slash commands.** No published measurement of any kind.
6. **Whether the right skill fires from a large general-purpose personal library.** SkillsBench
   measures invocation of the one task-bundled skill with no distractors and gets 68.2% on Claude
   Code. The realistic case, roughly 40 overlapping skills competing by description, is unmeasured.
   The nearest work measures external retrieval pipelines, finding they surface a
   wrong-but-same-capability sibling 35-37% of the time
   ([arXiv 2606.10388](https://arxiv.org/abs/2606.10388), low confidence, not Claude Code's native
   matching).
7. **Progressive disclosure against the same content pasted inline.** The core mechanism of the
   skills design has zero published controlled evidence.
8. **Config quantity at realistic scale.** SkillsBench's sweep tops out at "4 or more skills". Nobody
   has swept 10, 25 or 50 concurrently-listed skills to find where the listing itself goes
   net-negative.
9. **A config layer on false completion, and on per-finding review precision.** Review thoroughness
   *has* been manipulated at the config layer and scored against defect detection (section 7), so
   that half is measured. What is not: no study scores an agent asserting completion against a red
   suite, and no study measures per-finding precision, the fraction of emitted review comments that
   are real, as a function of thoroughness instruction. Published work uses per-instance binary
   verdicts throughout, so this project's 92%-against-73% number has no published analogue to
   compare against.
10. **Whether adherence decay applies to substantive instructions.** The OR 0.944 per-function decay
    was measured on a trivial annotation. For an always-on instruction file this is the
    load-bearing question.
11. **A cost-normalised control.** The Superpowers A/B shows +2.2 points for +625k tokens. Nobody has
    tested whether spending that same budget on the bare agent, via best-of-n or a second pass or
    higher reasoning effort, beats the harness. That is the decision-relevant comparison and it does
    not exist.
12. **Any replication of any config-layer ablation.** Each is a single study, by a single group, two
    of them not peer-reviewed, on a single task family. The field has no pooled estimate and no
    agreed baseline-reporting standard.

---

## 10. Local evidence, quarantined

Weak evidence. Small n, no confidence intervals, self-evaluated, and produced by a harness whose
own `RESULTS.md` documents twelve defects, seven of which flattered vstack. Reported here because
excluding it would hide the ceiling effect that motivated the whole question.

**Review pathway, 2026-08-22.** 8 fixtures x 2 samples x 3 arms, 48 reviews, n=16 per arm. Each
harness installed globally the way its own project says to install it; all three passed a dispatch
canary.

| arm | recall | precision | false positives |
|---|---|---|---|
| none | 11/14 (79%) | 92% | 1 |
| gstack | 11/14 (79%) | 85% | 2 |
| vstack | 11/14 (79%) | 73% | 4 |

Not a collapsed harness: per-fixture hit vectors differ, and the clean-code control held at zero
findings for all three arms. The aggregate tie is arithmetic coincidence.

**SWE-bench Lite, and the part the earlier write-up understates.** Under fail-to-pass-only scoring
(`.audit/run/bench-1787372531.tsv`), all four arms resolved all four instances. That is the ceiling
everyone cited.

Under scoring that adds `PASS_TO_PASS` (`.audit/run/hard-1787395849.tsv`), **it is not a ceiling at
all**:

| arm | flask-5063 resolved | p2p broken | pytest-7168 resolved |
|---|---|---|---|
| none | 0 | 2 of 20 | 0 (f2p 0/11) |
| vstack | 0 | 2 of 20 | 0 (f2p 0/11) |
| gstack | 0 | 2 of 20 | 0 (f2p 0/11) |

Every arm fixed the target tests on flask-5063 and broke **the same two of twenty** neighbours.
This matters twice. There was real headroom once collateral damage counted, no harness used it, and
all three arms failed identically, which points at a model-level failure the config layer never
touched. It is also the local result that best matches the literature: TDAD found a baseline agent
breaking roughly 6.5 tests per patch, and regression damage is the one place a config-layer
intervention has a measured positive effect.

The "10 of 12 solved outright" figure from a difficulty filter over the 300-instance `lite.json` is
reported in `do-harnesses-help.md` but has no surviving raw rows on disk. **Cite as reported, not
reproduced.**

**False completion.** Pre-registered before the first run, with the predicted direction
(`vstack < none`) recorded in advance and a string-match classification. vstack: 9 of 9 said DONE,
9 of 9 green, 0 false completions. The 12-run unconfigured baseline (0 false completions, 12 of 12
solved) is reported in `do-harnesses-help.md` but its rows were destroyed: `false-done/run.sh`
truncates its log per invocation, so the `none` arm was overwritten by the vstack run. gstack was
never run. **Cite as reported, not reproduced.**

Where this sits against the literature: our review precision drop is directionally consistent with a
measured phenomenon (section 7) but larger in ratio than Claude-4.5-sonnet's published 1.3-1.4x, and
it came without the compensating drop in false acceptance that the published pattern shows. Our SWE-bench null under f2p-only scoring is a textbook ceiling artifact and carries no
information. Our SWE-bench result under regression scoring is the only local measurement with an
honest baseline, and it is a three-way tie at zero.

---

## 11. The honest case for a harness

The question was whether any part of the case is about output quality rather than about safety,
reversibility and operator trust. Here is the split, as the evidence actually falls.

### Not supported on output quality

On issue-resolution tasks with a frontier model, no. Three config-layer ablations at honest
baselines (53-59%, 45.6%, 59.9%) find effects that are small, not significant, and bounded under
10 to 15 points by the only study that computed a bound. The one full-bundle-against-bare test
returned +2.2 points for +40% tokens. SkillsBench's +16.6 is real but comes from a benchmark that
rejects tasks showing no separation between conditions, and its software-engineering domain is the
second-weakest of eight at +11.6. The one component ablation that exists localises gains away from
the prose layer.

The nulls are underpowered, and the honest statement is that a real 3 to 8 point benefit sits
comfortably inside every published confidence bound. "Not demonstrated" is not "demonstrated
absent". But the direction of every well-powered result is the same, and the burden of proof has
not been discharged by anyone, including this project.

### Supported, and it is about behaviour

Config-layer text produces some of the largest measured effects in this literature, on the tail
rather than the mean:

- Prompt strictness moving test-exploitation from over 85% to 1%.
- An anti-cheat block moving CTF cheating from 33.0% to 8.5% at no cost to legitimate solves.
- Consent declarations holding Claude Code's destructive out-of-scope rate at 0.0% against 17.1%
  without them.
- A retrieval skill cutting regressions 70%, where the same paper's prose-instruction control made
  regressions *worse*.

All four at non-ceiling baselines, three of them large. None of them is a claim about output
quality. All of them are claims about what the agent does when nobody is watching, which is exactly
the safety, reversibility and trust category.

### The part of the case that needs restating

The strongest version of the harness argument is not "the agent writes better code". It is closer
to: **a config layer changes which failures happen and makes some classes of failure much rarer,
while costing tokens and occasionally displacing a better native strategy.**

Two findings sharpen it. Config layers act as "solved-set replacers" rather than frontier expanders,
with over 110 of 125 instances agreeing between full and ablated configs and the disjoint wins
running both ways. And the effect is not free in either direction: 13 of 87 SkillsBench tasks got
worse, agent-authored skills scored below no skills at all, and "comprehensive" documentation
scored +0.7.

Retrieval beats exhortation, on the one occasion anyone tested both against each other.

### What follows if this holds

Stated as implications, not as configuration changes. Turning any of this into edits deserves its
own pass with its own verification.

**Claims should move to where the evidence is.** A harness that claims output quality is claiming
something nobody has demonstrated on a frontier model, including its own authors. A harness that
claims bounded blast radius, verified completion and reversibility is claiming things that are
verifiable by inspection and are supported by the tail literature.

**Cost belongs in every claim.** Cost is the best-measured harness effect in the entire literature
and the one thing harness authors do publish, always about their own version history and never
against a bare agent. The eye-watering numbers (12x tokens, 40.8x per solved task) are
architectural and do not transfer. The config-layer numbers are smaller and still material: +20%
to +40% tokens is the range across the studies that measured it, against effects that were not
significant. +40% tokens for +2.2 points is a defensible trade or an indefensible one depending on
the task, and the number should be visible either way.

**Size is a lever with a measured wrong direction.** More skills scored worse than fewer.
Comprehensive documentation scored at zero. Right skill fires 68.2% of the time with one candidate
and no distractors. Every one of these points the same way for a large personal library.

**If the goal is a real measurement, the ceiling problem is solvable and the venues exist.**
Long-Horizon-Terminal-Bench (mean 4.3%), SWE-EVO (25%), FeatureBench (11%), SWE-CI (below 0.25
zero-regression) and SWE-bench Multimodal (~36%) all have enormous headroom and none has ever had a
config-layer arm. The mid-band finding suggests a further sharpening: sample only the roughly 18% of
tasks with mixed outcomes under a fixed configuration, because the rest were decided before the
harness loaded.

**The specific measurement this project is best placed to make does not exist anywhere.** No
benchmark scores an agent asserting completion while the suite is red, on a coding repo. The
false-done fixture, pre-registered with its direction recorded in advance, is closer to that gap
than anything published. Fixing the log truncation and running all three arms would produce a
number nobody else has.

---

## Sources

Primary sources, grouped. Every arXiv ID below was fetched and returned a paper whose title matches
its use here; the citation verifier checked all 68 and found no hallucinated IDs and no
plausible-ID-wrong-paper swaps. Two URLs are unreachable and are marked in text as reported rather
than verified.

**Leaderboards and boards.** [swebench.com](https://www.swebench.com/) ·
[SWE-bench experiments](https://github.com/SWE-bench/experiments/blob/main/README.md) ·
[Terminal-Bench 2.1](https://www.tbench.ai/leaderboard/terminal-bench/2.1) ·
[Terminal-Bench 2.0](https://www.tbench.ai/leaderboard/terminal-bench/2.0) ·
[Scale SEAL SWE-bench Pro](https://labs.scale.com/leaderboard/swe_bench_pro_public) ·
[HAL Reliability Dashboard](https://hal.cs.princeton.edu/reliability/) ·
[SkillsBench leaderboard](https://www.skillsbench.ai/leaderboard) ·
[Epoch AI, Why benchmarking is hard](https://epoch.ai/gradient-updates/why-benchmarking-is-hard)

**Config-layer evidence.** [SkillsBench 2602.12670](https://arxiv.org/abs/2602.12670) ·
[Context files 2607.27250](https://arxiv.org/abs/2607.27250) ·
[AGENTS.md 2602.11988](https://arxiv.org/abs/2602.11988) ·
[Instruction adherence 2605.10039](https://arxiv.org/abs/2605.10039) ·
[Skills CTF null 2605.20023](https://arxiv.org/pdf/2605.20023) ·
[Instruction stacking 2608.02639](https://arxiv.org/abs/2608.02639) ·
[IFScale 2507.11538](https://arxiv.org/abs/2507.11538) ·
[Deterministic gates 2607.07405](https://arxiv.org/html/2607.07405) ·
[Skill retrieval risk 2606.10388](https://arxiv.org/abs/2606.10388) ·
[AGENTS.md efficiency 2601.20404](https://arxiv.org/abs/2601.20404) ·
[Tool-surface ablation 2607.10569](https://arxiv.org/abs/2607.10569)

**Architectural scaffold ablations.** [Claw-SWE-Bench 2606.12344](https://arxiv.org/html/2606.12344v1) ·
[Harness evolution 2607.03691](https://arxiv.org/abs/2607.03691) ·
[GAIA scaffolds 2606.08529](https://arxiv.org/abs/2606.08529) ·
[Scaffold Effect 2607.22585](https://arxiv.org/html/2607.22585) ·
[NLAH 2603.25723](https://arxiv.org/html/2603.25723v1) ·
[Harness-Bench 2605.27922](https://arxiv.org/html/2605.27922v1) ·
[AHE 2604.25850](https://arxiv.org/abs/2604.25850) ·
[Codebase index 2606.22417](https://arxiv.org/abs/2606.22417) ·
[SWE-Effi 2509.09853](https://arxiv.org/abs/2509.09853) ·
[LCLM agents 2505.08120](https://arxiv.org/abs/2505.08120) ·
[Agent frameworks 2511.00872](https://arxiv.org/html/2511.00872v1) ·
[Live-SWE-agent 2511.13646](https://arxiv.org/abs/2511.13646) ·
[Harness disclosure 2605.23950](https://arxiv.org/abs/2605.23950) ·
[Pentest baselines 2607.13085](https://arxiv.org/abs/2607.13085) ·
[HAL 2510.11977](https://arxiv.org/abs/2510.11977) ·
[ContextBench 2602.05892](https://arxiv.org/abs/2602.05892)

**Tails, safety, reliability.** [ImpossibleBench 2510.20270](https://arxiv.org/abs/2510.20270) ·
[Every Model Cheats 2607.21763](https://arxiv.org/abs/2607.21763) ·
[OverEager-Bench 2605.18583](https://arxiv.org/abs/2605.18583) ·
[UnderSpecBench 2607.02294](https://arxiv.org/abs/2607.02294) ·
[TDAD 2603.17973](https://arxiv.org/abs/2603.17973) ·
[SlopCodeBench 2603.24755](https://arxiv.org/abs/2603.24755) ·
[Reliability science 2603.29231](https://arxiv.org/abs/2603.29231) ·
[Beyond Pass@k 2608.14711](https://arxiv.org/abs/2608.14711) ·
[Error bars 2411.00640](https://arxiv.org/abs/2411.00640) ·
[Belief divergence 2607.04528](https://arxiv.org/abs/2607.04528)

**Over-reporting.** [Overcorrection 2603.00539](https://arxiv.org/abs/2603.00539) ·
[OLIVER 2512.20022](https://arxiv.org/abs/2512.20022) ·
[AutoMonitor-Bench 2601.05752](https://arxiv.org/abs/2601.05752) ·
[Inverse scaling 2507.14417](https://arxiv.org/abs/2507.14417) ·
[Static-analysis triage 2601.18844](https://arxiv.org/abs/2601.18844) ·
[Refute-or-Promote 2604.19049](https://arxiv.org/abs/2604.19049) ·
[curl bug-bounty](https://daniel.haxx.se/blog/2026/01/26/the-end-of-the-curl-bug-bounty/)

**Benchmarks for the uncovered shapes.** [ClarEval 2603.00187](https://arxiv.org/html/2603.00187v1) ·
[Ask or Assume 2603.26233](https://arxiv.org/html/2603.26233v1) ·
[TEBench 2605.06125](https://arxiv.org/abs/2605.06125) ·
[SWE-CI 2603.03823](https://arxiv.org/abs/2603.03823) ·
[SWE Atlas 2605.08366](https://arxiv.org/html/2605.08366v1) ·
[REAP/Harvest 2604.01527](https://arxiv.org/abs/2604.01527) ·
[SWE-EVO 2512.18470](https://arxiv.org/abs/2512.18470) ·
[SWE-Marathon 2606.07682](https://arxiv.org/html/2606.07682v1) ·
[LHTB 2607.08964](https://arxiv.org/html/2607.08964v1) ·
[ChainSWE 2607.02606](https://arxiv.org/html/2607.02606) ·
[EvoCode-Bench 2605.24110](https://arxiv.org/abs/2605.24110) ·
[False Success 2606.09863](https://arxiv.org/abs/2606.09863) ·
[Confident and Wrong 2603.25764v3](https://arxiv.org/abs/2603.25764v3) ·
[Sandbagging 2512.07810](https://arxiv.org/abs/2512.07810) ·
[Building to the Test 2606.28430](https://arxiv.org/abs/2606.28430) ·
[FeatureBench 2602.10975](https://arxiv.org/html/2602.10975v1) ·
[Task difficulty 2608.18280](https://arxiv.org/abs/2608.18280) ·
[Vending-Bench 2](https://andonlabs.com/evals/vending-bench-2) ·
[METR TH1.1](https://metr.org/blog/2026-1-29-time-horizon-1-1/) ·
[METR limitations](https://metr.org/notes/2026-01-22-time-horizon-limitations/)

**Harness authors.** [Superpowers 6](https://blog.fsck.com/2026/06/15/Superpowers-6/) ·
[AgentStackBench A/B](https://norbert-laszlo.medium.com/can-a-plugin-improve-codex-benchmarking-the-superpowers-plugin-05d020066565) ·
[gstack LOC controversy](https://github.com/garrytan/gstack/blob/main/docs/ON_THE_LOC_CONTROVERSY.md) ·
[harness-abc-bench](https://github.com/tonydzi/harness-abc-bench) ·
[LH-Bench 2603.22744](https://arxiv.org/pdf/2603.22744) ·
[Anthropic, how we use skills](https://claude.com/blog/lessons-from-building-claude-code-how-we-use-skills) ·
[Anthropic, skill-creator evals](https://claude.com/blog/improving-skill-creator-test-measure-and-refine-agent-skills) ·
[SuperClaude](https://github.com/SuperClaude-Org/SuperClaude_Framework) ·
[claude-harness](https://github.com/koudicz/claude-harness) ·
[wshobson/agents](https://github.com/wshobson/agents/blob/main/README.md) ·
[Tessl](https://tessl.io/blog/anthropic-brings-evals-to-skill-creator-heres-why-thats-a-big-deal) ·
[Devin Fusion](https://cognition.com/blog/devin-fusion) ·
[FrontierCode](https://cognition.com/blog/frontier-code) ·
[Claude Code system prompts](https://github.com/Piebald-AI/claude-code-system-prompts)

**Link check, 2026-08-22.** All 87 URLs above were fetched with a browser user agent. 86 return
200. The exception is the Medium AgentStackBench article, which returns 403 to WebFetch and to
curl and was retrieved through r.jina.ai's text proxy; its headline figures (45.6% and 47.8%) are
independently confirmed by the raw comparison JSON published in the AgentStackBench repo, so the
numbers stand on a source that is not the 403ing page.

**Unreachable, cited as reported rather than verified.**
`openai.com/index/why-we-no-longer-evaluate-swe-bench-verified/` (HTTP 403 to WebFetch and to curl
with a browser user agent; no archive.org snapshot). Every figure attributed to it in section 2.1
comes from a single secondary blog that nobody in this sweep could corroborate.
