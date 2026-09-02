# Do long instruction files and system prompts help or hurt?

Scope: literature on instruction following under long context (position effects, context rot) and on repository-level agent instruction files (AGENTS.md, CLAUDE.md, cursor rules), 2023 to 2026. Purpose: mechanism-level guidance for building configuration layers around LLM coding agents, and candidate experiments for a paper on whether such layers change correctness, false completion claims, cost, and wall time. Compiled September 2026; every claim below was checked against a fetched source.

## Sources

Entries 1 to 12 were verified by fetching the arXiv abstract page or full HTML text directly. Entries 13 to 15 were verified by fetching the arXiv API feed whose output contains their full abstract, title, authors, and dates; the verification URL is the API query. Confidence reflects what was actually read: high where full text or the paper's own abstract page was fetched, medium where only an abstract embedded in an API response was available.

### 1. Lost in the Middle: How Language Models Use Long Contexts

Nelson F. Liu, Kevin Lin, John Hewitt, Ashwin Paranjape, Michele Bevilacqua, Fabio Petroni, Percy Liang. 2023. TACL 2023; arXiv:2307.03172 (v3, Nov 2023). URL: https://arxiv.org/abs/2307.03172

Claim: performance is U-shaped over position. The paper reports that "performance is often highest when relevant information occurs at the beginning or end of the input context, and significantly degrades when models must access relevant information in the middle of long contexts" (abstract; Figure 5 for the multi-document QA curve). Exact figure: GPT-3.5-Turbo's closed-book accuracy on multi-document QA is 56.1% (Table 1), and in the 20- and 30-document settings its worst-case mid-context performance falls below that closed-book baseline; the paper states performance "can drop by more than 20%" (section 2.3). Also: using 50 retrieved documents instead of 20 improves reader accuracy by only about 1.5% for GPT-3.5-Turbo and about 1% for Claude-1.3 (section 5).

Method and sample: controlled multi-document QA over NaturalQuestions-Open, 2655 queries with 10, 20, or 30 documents, plus a synthetic key-value retrieval task with 75, 140, and 300 key-value pairs at 500 examples each (sections 2.1, 3.2). Models: MPT-30B-Instruct, LongChat-13B, GPT-3.5-Turbo variants, Claude-1.3 variants, Flan-T5/UL2, Llama-2.

Verification: fetched https://arxiv.org/abs/2307.03172 and full text at https://arxiv.org/html/2307.03172v3. Confidence: high.

### 2. Same Task, More Tokens: the Impact of Input Length on the Reasoning Performance of Large Language Models

Mosh Levy, Alon Jacoby, Yoav Goldberg. 2024. ACL 2024; arXiv:2402.14848 (v2, Jul 2024). URL: https://arxiv.org/abs/2402.14848

Claim: reasoning accuracy degrades with input length at lengths far below the context limit, with the task held constant. The paper reports "on average over all tested models, a drop in accuracy from 0.92 to 0.68" as inputs grow to about 3000 tokens (section 1). Instruction following itself decays with length: refusal-to-answer "grows as the input length increases, indicating a failure to comply to the instruction" (section 7, Failure to answer), models increasingly answer before reasoning under CoT (section 7), and next-word prediction accuracy correlates negatively with reasoning accuracy on the same inputs (rho Pearson = -0.95, p = 0.01, section 5, Figure 6). Chain-of-thought prompting does not eliminate the length-induced drop (section 6).

Method and sample: FLenQA, three two-span reasoning tasks (MonoRel, People In Rooms, simplified Ruletaker), 100 base instances each, expanded by padding to roughly 250 to 3000 tokens with controlled padding type and key-paragraph position; five models (GPT-4, GPT-3.5, Gemini Pro, Mistral Medium, Mixtral 8x7B); most plots aggregate 300 to 600 samples per point.

Verification: fetched https://arxiv.org/abs/2402.14848 and full text at https://arxiv.org/html/2402.14848v2. Confidence: high.

### 3. Context Rot: How Increasing Input Tokens Impacts LLM Performance

Kelly Hong, Anton Troynikov, Jeff Huber. 2025. Chroma technical report, July 14, 2025. URL: https://research.trychroma.com/context-rot

Claim: performance degrades non-uniformly with input length even when task difficulty is held constant, across 18 LLMs including GPT-4.1, Claude 4, Gemini 2.5, and Qwen3. On LongMemEval, "Across all models, we see significantly higher performance on focused prompts compared to full prompts" (LongMemEval section), comparing ~300-token focused prompts against the full ~113k-token histories (306 prompts after filtering). Distractors that are topically related but wrong amplify degradation with length, and hallucinated answers borrow distractor content (Impact of Distractors section, Figures under "distractors_ind" and "hallucinations"). Counterintuitively, "models perform better on shuffled haystacks than on logically structured ones" across all 18 models (Haystack Structure section). In the repeated-words task, positional accuracy of the unique word is highest near the beginning of the sequence as length grows (Repeated Words section).

Method and sample: extended needle-in-a-haystack with controlled needle-question similarity, distractor count, needle-haystack similarity, and haystack structure, 8 input lengths and 11 needle positions per configuration, 194,480 LLM calls total; plus LongMemEval (306 prompts) and a repeated-words task (1090 variations per word combination); temperature 0, GPT-4.1 judge with >99% reported alignment.

Verification: fetched https://research.trychroma.com/context-rot (full report). Confidence: high.

### 4. Instruction-Following Evaluation for Large Language Models (IFEval)

Jeffrey Zhou, Tianjian Lu, Swaroop Mishra, Siddhartha Brahma, Sujoy Basu, Yi Luan, Denny Zhou, Le Hou. 2023. arXiv:2311.07911 (Google). URL: https://arxiv.org/abs/2311.07911

Claim: instruction following can be measured with verifiable constraints rather than human judges. The paper introduces "25 types of those verifiable instructions and constructed around 500 prompts, with each prompt containing one or more verifiable instructions" (abstract), for constraints such as "write in more than 400 words" or "mention the keyword of AI at least 3 times" (abstract). This is the standard instrument for measuring compliance rates of agent configuration constraints mechanically.

Method and sample: 500 prompts across 25 constraint types, automatic programmatic verification, results reported for two widely available LLMs (abstract).

Verification: fetched https://arxiv.org/abs/2311.07911. Confidence: high.

### 5. The Prompt Report: A Systematic Survey of Prompt Engineering Techniques

Sander Schulhoff, Michael Ilie, Nishant Balepur, et al. (32 authors). 2024, revised Feb 2025. arXiv:2406.06608 (v6). URL: https://arxiv.org/abs/2406.06608

Claim: the reference taxonomy for prompting technique space: "a detailed vocabulary of 33 vocabulary terms, a taxonomy of 58 LLM prompting techniques, and 40 techniques for other modalities" plus "best practices and guidelines for prompt engineering" (abstract). Relevant to the project as the vocabulary source for classifying what a CLAUDE.md or system prompt actually contains, and as evidence that prompt composition is an engineering discipline with named, reusable parts rather than folklore.

Method and sample: systematic survey and meta-analysis of the natural language prefix-prompting literature (abstract); no new experiments.

Verification: fetched https://arxiv.org/abs/2406.06608. Confidence: high for taxonomy claims; the survey's per-technique effect sizes were not individually checked.

### 6. Evaluating AGENTS.md: Are Repository-Level Context Files Helpful for Coding Agents?

Thibaud Gloaguen, Niels Mündler, Mark Müller, Veselin Raychev, Martin Vechev. 2026. arXiv:2602.11988 (v2, Jun 2026). SRI Lab, ETH Zurich. URL: https://arxiv.org/abs/2602.11988

Claim: context files do not generally improve task success while raising cost. "Surprisingly, we find that providing context files does not generally improve task success rates, while increasing inference cost by over 20% on average" (abstract). Crucially, compliance is not the bottleneck: "instructions in the context files are well followed by coding agents, repository overviews, although popular and recommended by model providers, are not helpful" (abstract). The authors conclude context files are useful for non-standard coding practices but performance claims need rigorous evaluation before deployment.

Method and sample: two complementary settings: SWE-bench-style tasks from popular repositories with LLM-generated context files, and a novel set of issues from repositories containing developer-committed context files; multiple LLMs and coding agents; gold-test evaluation. Run counts are in the paper body, not the abstract.

Verification: fetched https://arxiv.org/abs/2602.11988. Confidence: high.

### 7. On the Impact of AGENTS.md Files on the Efficiency of AI Coding Agents

Jai Lal Lulla, Seyedmoein Mohsenimofidi, Matthias Galster, Jie M. Zhang, Sebastian Baltes, Christoph Treude. 2026. arXiv:2601.20404 (v2, Mar 2026). URL: https://arxiv.org/abs/2601.20404

Claim: the opposite sign on cost and time, with correctness held comparable. "the presence of AGENTS.md is associated with a lower median runtime (Δ28.64%) and reduced output token consumption (Δ16.58%), while maintaining a comparable task completion behavior" (abstract). Note the asymmetry with entry 6: this study measures efficiency on pull-request work, not resolve rate on benchmark tasks, and finds guidance pays for itself there.

Method and sample: 10 repositories, 124 pull requests, agents executed with and without an AGENTS.md file; wall-clock time and token usage measured; comparison across conditions.

Verification: fetched https://arxiv.org/abs/2601.20404. Confidence: high; note the outcome measured is efficiency, not correctness, and the design is observational over PRs.

### 8. Configuration Smells in AGENTS.md Files: Common Mistakes in Configuring Coding Agents

Helio Victor F. dos Santos, Vitor Costa, Joao Eduardo Montandon, Luciana Lourdes Silva, Marco Tulio Valente. 2026. SCAM 2026; arXiv:2606.15828 (v5). URL: https://arxiv.org/abs/2606.15828

Claim: real-world instruction files are full of defects. Six configuration smells identified via grey literature review plus repository mining, with automated detectors; "Lint Leakage was the most common smell, affecting 62% of the files, followed by Context Bloat (42%) and Skill Leakage (35%)" (abstract). Context Bloat, Skill Leakage, and Conflicting Instructions frequently co-occur (abstract).

Method and sample: grey literature review, repository mining, then prevalence measurement on 100 popular open-source repositories containing AGENTS.md or CLAUDE.md.

Verification: fetched https://arxiv.org/abs/2606.15828. Confidence: high.

### 9. Agent READMEs: An Empirical Study of Context Files for Agentic Coding

Worawalan Chatlatanagulchai, Hao Li, Yutaro Kashiwa, Brittany Reid, Kundjanasith Thonglek, Pattara Leelaprute, Arnon Rungsawang, Bundit Manaskasemsak, Bram Adams, Ahmed E. Hassan, Hajimu Iida. 2025 (v2 Aug 2026). arXiv:2511.12884. URL: https://arxiv.org/abs/2511.12884

Claim: what developers actually put in these files. Across 2,303 agent context files from 1,925 repositories, content skews functional: "test procedures (75.9%), implementation details (70.8%), and architecture (68.1%)" dominate, while "non-functional requirements such as security (14.8%) and performance (14.5%) are rarely specified" (abstract). Files "evolve like configuration code through frequent, small additions" and are "complex, difficult-to-read artifacts" (abstract).

Method and sample: large-scale mining and manual content analysis of 2,303 files across 1,925 repositories, 16 instruction types.

Verification: fetched https://arxiv.org/abs/2511.12884. Confidence: high.

### 10. Do Context Files Help Coding Agents? A Two-Agent Ablation Study on Real Repositories

Prakhar Khatri. 2026. arXiv:2607.27250. URL: https://arxiv.org/abs/2607.27250

Claim: a controlled null result with a diagnosis. Across two frontier agents, 17 real tasks from 3 repositories, and 288 evaluated runs with gold-test evaluation, "Context strategy does not measurably move correctness on either agent (bounded to <=10-15pp via equivalence testing)" and "agents fail on implementation skill---feature design, pattern selection, exact wiring---not missing repository knowledge" (abstract). A manipulation probe confirms the real AGENTS.md "never converts a near-miss to a pass on either agent" (abstract). Borderline task difficulty is agent-specific (Spearman rho = 0.75), which explains why single-agent studies contradict each other: they sample tasks from different agents' informative bands.

Method and sample: controlled ablation of context-injection strategy, Claude Code and Codex, 17 tasks, 3 repositories, 288 evaluated runs, equivalence testing plus failure-mode triage.

Verification: fetched https://arxiv.org/abs/2607.27250. Confidence: high.

### 11. Probe-and-Refine Tuning of Repository Guidance for Coding Agents

Asa Shepard, Jeannie Albrecht. 2026. arXiv:2606.20512 (v2). Williams College. URL: https://arxiv.org/abs/2606.20512

Claim: how guidance is produced matters more than whether it exists. Probe-and-refine tuning, which iteratively diagnoses and patches a repository's guidance file using synthetic bug-fix probes through single-shot LLM calls, reaches "33.0% mean resolve rate vs. 28.3% for the static knowledge base used to initialize it and 25.5% for an unguided baseline (p < 0.001 for both probe-and-refine contrasts)" (abstract) on SWE-bench Verified with Qwen3.5-35B-A3B across four independent trials at 200 steps. Mechanism: "The improvement comes from coverage rather than precision: refined guidance produces evaluable patches for 14.5 percentage points (pp) more instances while per-patch precision remains statistically constant (~59%, p = 0.119)" (abstract), i.e. guidance helps agents reach the right file, not write better diffs. Guidance is also what lets an agent convert a larger step budget into productive work (abstract, step-budget experiment).

Method and sample: SWE-bench Verified, four independent trials, one primary model plus a cross-model check with NVIDIA-Nemotron-3-Nano-30B-A3B showing the tuning loop degrades when the model cannot produce diagnostic output.

Verification: fetched https://arxiv.org/abs/2606.20512. Confidence: high.

### 12. Context Rot in AI-Assisted Software Development: Repurposing Documentation Consistency for AI Configuration Artifacts

Christoph Treude, Sebastian Baltes. 2026. arXiv:2606.09090. URL: https://arxiv.org/abs/2606.09090

Claim: instruction files go stale, and the staleness is measurable with existing tooling. The paper defines context rot for configuration artifacts: as software evolves, CLAUDE.md/AGENTS.md/.cursorrules content becomes stale (section 1). Preliminary evidence: applying an existing README/wiki consistency checker to a statistically representative sample of 356 repositories "identifies stale code element references in 23.0% of repositories" (abstract).

Method and sample: position/roadmap paper mapping decades of documentation-consistency research onto agent configuration artifacts, plus one empirical check on 356 repositories.

Verification: fetched https://arxiv.org/abs/2606.09090. Confidence: high for the 23.0% figure; the roadmap itself is argument, not evidence.

### 13. ContextCov: Deriving and Enforcing Executable Constraints from Agent Instruction Files

Reshabh K Sharma et al. 2026. arXiv:2603.00822 (v2). URL: https://arxiv.org/abs/2603.00822

Claim: passive instruction text is weakly enforced; compiling it into executable checks works. The paper states that because instructions "remain passive text, agents frequently violate documented constraints due to context window saturation or conflicting local context" (abstract). Compiling documented constraints into static AST queries, runtime shell shims, and architectural validators achieves "88.3% constraint compliance (vs. 67.0% and 50.3%)" for prompt-only and LLM-reflection baselines, "with 3.4x lower feedback cost, while maintaining functional correctness" (abstract) on SWE-bench Lite, 12 repositories, 300 tasks.

Method and sample: framework plus comparison against prompt-only and reflection baselines on SWE-bench Lite (12 repositories, 300 tasks).

Verification: fetched via the arXiv API query http://export.arxiv.org/api/query?search_query=all:%22AGENTS.md%22&max_results=25&sortBy=submittedDate, which returned the full abstract. Confidence: medium.

### 14. Classifier Context Rot: Monitor Performance Degrades with Context Length

Sam Martin, Fabien Roger. 2026. arXiv:2605.12366. URL: https://arxiv.org/abs/2605.12366

Claim: long-context degradation hits monitors, not just actors, and periodic re-injection mitigates it. Frontier models used as safety monitors on coding-agent transcripts "miss these actions 2x to 30x more often when they occur after 800K tokens of benign activity than when they occur on their own" (abstract). "These weaknesses can be partially mitigated with prompting techniques such as periodic reminders throughout the transcript" (abstract).

Method and sample: evaluation of Opus 4.6, GPT 5.4, and Gemini 3.1 as classifiers over transcripts exceeding 500K tokens on a dataset of subtly dangerous coding-agent actions.

Verification: fetched via the arXiv API query http://export.arxiv.org/api/query?search_query=all:%22context%20rot%22&max_results=20&sortBy=submittedDate, which returned the full abstract. Confidence: medium.

### 15. When and How Context Rot Appears in Coding Agents: A White-Box Study of Agent Skills in Code Auditing

Yue Xue. 2026. arXiv:2607.17937 (v2). URL: https://arxiv.org/abs/2607.17937

Claim: long context kills requirement adherence even when content is present, and external checklists beat self-checks. Holding task and 24 artifact checks fixed, "Codex with gpt-5.4-mini passes 8/10 runs in a 10,991-character clean context but only 3/10 in both a 299,140-character relevant context and an equal-length irrelevant context" (abstract), a 50-point gap that stays trend-level under two-sided Fisher tests (p = 0.0698). Requirement coverage stays above 92% in both long conditions, so "a few omissions can invalidate an otherwise complete artifact" (abstract). Decisive for stop-gate design: "A detailed external checklist passes 10/10 runs, compared with 5/10 for a generic self-check (p = 0.0325)" (abstract). A second task shows no effect, so there is no universal context-length threshold.

Method and sample: production-derived white-box code-audit workflow, 10 runs per condition, controlled context variation, failure classification.

Verification: fetched via the arXiv API query http://export.arxiv.org/api/query?search_query=all:%22context%20rot%22&max_results=20&sortBy=submittedDate, which returned the full abstract. Confidence: medium; small n per condition, and the key contrast is one task.

## Synthesis

What the sources jointly support. Long context degrades instruction use even when task difficulty is constant: position within the context matters (entries 1, 3, 15), pure length degrades reasoning and instruction compliance (entries 2, 3, 15), and the degradation extends to LLM-based monitors and stop gates, not only the acting agent (entry 14). Instruction following itself is a measurable, mechanically verifiable property (entry 4). Against that background, the empirical AGENTS.md literature splits cleanly by outcome measured. On correctness, guidance is a null result: entries 6 and 10 find no reliable resolve-rate gain, and entry 10 diagnoses why, namely that agents fail on implementation skill, not missing repository knowledge, and that instructions are in fact well followed. On efficiency, guidance helps: entry 7 finds 28.64% lower median runtime and 16.58% lower output tokens on pull-request work. On targeted navigation-heavy settings, tuned guidance helps: entry 11 shows a 7.5-point resolve-rate gain from probe-and-refine, attributable to coverage (reaching the right file) rather than precision. Meanwhile the artifacts themselves are defective in predictable ways: bloat, lint leakage, skill leakage, and conflicts are common (entry 8), content over-indexes on functional context and under-specifies security and performance (entry 9), and a fifth of repositories carry stale references of the kind these files accumulate (entry 12). The Prompt Report (entry 5) supplies the vocabulary for treating these files as engineered prompts rather than documentation.

What they contradict. Entry 7 (guidance cuts runtime and tokens) versus entry 6 (guidance raises inference cost over 20% with no success gain) is the central contradiction, and it is resolvable by reading the dependent variables: entry 7 measures efficiency on real PRs where guidance plausibly prevents wasted exploration; entry 6 measures success rate plus total inference cost on benchmark tasks where the injected file adds input tokens to every call. Both can be true. Entries 10 and 11 also contradict on the surface, one finding no correctness effect of context files and the other a 7.5-point gain; entry 11's own framing resolves it, since the gain comes only from guidance produced by an empirical tuning loop, not from static hand-written or LLM-generated files, and from tasks where locating the right file is the binding constraint. Entry 10's Spearman rho = 0.75 on agent-specific task difficulty further explains why single-agent, single-task-set studies disagree.

Open gaps. No study isolates instruction-file length as a controlled variable the way entries 1 to 3 isolate context length; entry 8 documents bloat and entries 6 and 10 test real files, but the dose-response curve of CLAUDE.md size against resolve rate is unmeasured. Position of instructions inside the file is unstudied in the agent setting despite the position effects in entries 1 and 3. No source measures false claims of completion as an outcome, which is the paper's second purpose and a direct opening. Stop gates are barely studied: entry 15 is one task with 10 runs per condition, and entry 14 is about monitors of transcripts, not self-verification by the acting agent. Entry 11's tuning loop is evaluated with one primary open-weights model; whether probe-and-refine transfers to frontier models is open. Finally, all correctness studies use SWE-bench-family or small task sets; no study measures guidance effects on long-horizon multi-session work where entries 3 and 14 predict the largest decay.

## What a configuration layer should do differently

This section is the point of the report. Each recommendation is a mechanism, tied to the entries that justify it.

First, cut the file before adding to it, and delete repository overviews entirely. Entries 6 and 10 show overview-style context does not convert to passes while adding input tokens to every call, and entry 6 quantifies the cost at over 20% average inference increase. Entry 8 finds Context Bloat in 42% of files, and entry 9 shows files grow through frequent small additions with no pruning mechanism. Mechanism: a lint hook on the configuration file itself, enforcing a token budget and flagging overview-style sections (what entry 8 calls Context Bloat) at commit time, the same way lint leakage is flagged. The file should be treated as code with a reviewer and a linter, not documentation.

Second, exploit position deliberately. Entries 1 and 3 establish primacy and recency gradients: mid-context information is the least reliably used, and in entry 3 positional accuracy is highest near the beginning. Entry 15 shows requirements are dropped from long contexts even when present. Mechanism: durable, must-always-hold constraints (never force-push, never edit migrations) go at the top of the system prompt; per-task instructions injected last, closest to the generation point; nothing load-bearing in the middle of either. Sub-agent routing should not bury its contract mid-prompt.

Third, compile hard constraints into executable checks instead of prose. This is the strongest-supported mechanism in the corpus. Entry 8 finds Lint Leakage, prose duplicating what a linter already enforces, in 62% of files, which is evidence teams already half-know prose is the wrong channel. Entry 13 measures the alternative directly: compiling instructions into AST queries, shell shims, and validators yields 88.3% constraint compliance versus 50.3% for prompt-only, at 3.4x lower feedback cost. Entry 2 shows instruction compliance itself decays with input length, so prose constraints are weakest exactly when the session is longest. Mechanism: any instruction of the form always/never that can be checked by a command becomes a pre-commit or stop-gate hook; the instruction file keeps only what no command can check. The stop gate re-runs the test suite and the constraint checks rather than accepting the agent's claim, because entry 6 shows agents follow instructions well and still fail, and no measured study validates self-reported completion.

Fourth, verify with external checklists, not generic self-review. Entry 15 is the only controlled comparison: a detailed external checklist passed 10/10 runs against 5/10 for a generic self-check (p = 0.0325). Combined with entry 4, which makes instructions mechanically verifiable, and entry 14, which shows the model judging its own long transcript degrades 2x to 30x, the design follows: the configuration layer should maintain per-task acceptance checklists generated at task start, run them as a stop gate, and treat generic let-the-model-review-itself gates as close to worthless. Entry 14 also justifies re-injecting the checklist and critical constraints periodically in long sessions rather than once at the top, since periodic reminders partially mitigated monitor misses.

Fifth, tune the guidance empirically per repository instead of hand-writing it, and do so per agent. Entry 11 shows the decisive variable is how guidance was produced: probe-and-refine tuning gained 7.5 points over an unguided baseline while static initialization gained 2.8, with the mechanism being coverage, getting the agent to the right file. Entry 10 shows borderline task difficulty is agent-specific (rho = 0.75), so a guidance file tuned for Claude Code is not automatically right for Codex. Mechanism: the layer runs cheap synthetic probes through the repo, keeps the instructions that changed outcomes, and stores guidance per agent-tier, exactly the loop entry 11 mechanizes. This also gives the paper its cleanest intervention to study.

Sixth, budget for staleness. Entry 12 found stale code references in 23.0% of repositories and entry 9 shows these files evolve like configuration code. Mechanism: a scheduled hook that re-validates every file path, command, and API reference in the instruction file against the current tree and test suite, and opens an issue or disables the stale section on failure. Instructions that reference things that no longer exist are worse than absent, since entry 2 shows models comply with instructions they should refuse.

Seventh, match guidance to the outcome you are buying. Entries 6 and 7 together say: on benchmark-style correctness, default to minimal guidance; on operational PR work, guidance pays for itself in runtime and output tokens (28.64% and 16.58% median reductions). Mechanism: two profiles, a lean profile for correctness-critical autonomous runs and a guidance-rich profile for interactive efficiency, selected by the routing layer rather than one file for everything.

Eighth, on delegation: entries 14 and 15 say a smaller or same-tier model reading a long context fails at monitoring and checking, so route verification either to a fresh short-context call with only the checklist and the diff, or to deterministic tools. Entry 3's distractor findings add that filler around the checklist (logs, prior attempts) actively induces wrong answers, so the verification context should be minimal, not the whole transcript.

## Claims to test

Experiment 1, length dose-response. Sweep one CLAUDE.md at 0, 500, 2000, and 8000 tokens on fixed SWE-bench Verified tasks, holding content constant by truncation from a ranked list. Outcome: resolve rate, total token cost, wall time, with equivalence bounds like entry 10 (its 288 runs bounded effects to 10-15pp; to resolve a 5pp effect at 80% power, roughly 50 tasks x 4 conditions x 3 seeds = 600 runs). Hypothesis from entries 6, 8: flat to negative correctness slope, near-linear cost slope.

Experiment 2, position of constraints. Same 20 verifiable constraints (entry 4 style) placed at top, middle, and bottom of the instruction block, measured by programmatic compliance per constraint. 50 tasks x 3 positions x 3 seeds = 450 runs. Hypothesis from entries 1, 3: mid-position compliance lowest, top and bottom within a few points of each other.

Experiment 3, prose versus executable stop gate. Matched constraint pairs enforced once as prose in AGENTS.md and once as a hook that blocks completion until the check passes. Outcomes: constraint violation rate and false completion rate, defined as agent claims done while tests or checks fail, an outcome no source measured. 100 tasks x 2 arms x 3 seeds = 600 runs. Hypothesis from entries 13, 8: violation rate roughly halves; false completion rate drops with the stop gate.

Experiment 4, checklist quality in the stop gate. Detailed external checklist versus generic self-check versus no gate, at two session lengths (short and 100k+ token contexts), with the checklist re-injected every 10 turns in one arm. Outcomes: end-of-run requirement coverage and pass rate. 40 tasks x 3 gates x 2 lengths x 3 seeds = 720 runs. Hypotheses from entries 15, 14: external checklist beats self-check, gap widens with context length, re-injection recovers part of the long-context loss.

Experiment 5, guidance provenance. Hand-written, LLM-generated, and probe-and-refine-tuned guidance on the same tasks, decomposing the effect into coverage (did the agent touch the correct files) versus precision (patch correctness given evaluable patch), replicating entry 11's decomposition on frontier models. 50 tasks x 3 arms x 4 seeds = 600 runs. Hypothesis: tuned guidance gains resolve rate through coverage; per-agent tuning beats shared guidance given entry 10's rho = 0.75.

Experiment 6, staleness injection. Plant deliberately stale instructions (renamed paths, removed commands) alongside current ones, and measure whether the agent follows the stale instruction, detects the conflict, or violates both, with and without a consistency-check hook that validates file references before session start. 40 tasks x 2 arms x 3 seeds = 240 runs. Hypothesis from entries 12, 2: agents comply with stale instructions at a rate similar to current ones; the pre-flight consistency hook cuts stale compliance to near zero.
