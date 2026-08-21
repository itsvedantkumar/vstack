# Research handoff: five free investigations for vstack v1.7.0

- Status: research and implementation contract, not an implementation
- Target under investigation: tag `v1.7.0`, commit `3bbe61848daf5d87a315fe62c4a2eb75be383003`
- PR base inspected: `main`, commit `3945621666a0390ea5d9ac0d13664f99b0c5de11`
- Research date: 2026-08-21
Constraint: no paid API, account, hosted benchmark, or telemetry; the only model calls allowed are
subscription-metered `claude -p` runs.

This document is written for the implementer. It distinguishes repository facts, findings from
primary sources, inferences, and interfaces that do not exist yet. Commands labelled **acceptance
contract** are the commands the implementation must make runnable; this research-only change does
not pretend they already work.

## Decisions in one page

| Investigation | Decision | Confidence | First implementation |
|---|---|---:|---|
| Skill reachability | Measure the real installed CLI and each host. Do not infer model visibility from repository bytes. | High for supported observability; low for exact serialized bytes | A read-only probe that combines `/skills`, `/context`, `--debug-file`, and an explicitly labelled byte proxy |
| False success | Make this the project's outcome metric, but only where a runner-owned grader supplies ground truth. | High | A standard-library stream parser, regex instrument, 50-item human calibration command, and an exploratory TF-IDF baseline |
| Ablation | Start with a BugsInPy pilot; do not call an overnight run an equivalence study. | Medium | Freeze 30 tasks to debug the protocol, then estimate the discordant-pair rate before powering the study |
| Evidence bundle | Ship a small local receipt, not a security attestation. A receipt is useful only if missing evidence is fatal and each check has calibration evidence. | High | One JSON file per run, a finalizer, a verifier, and deliberate failure tests |
| Product UI gate | Enforce an executable floor, not taste. Five check families are enough. | High for the floor; deliberately no automated taste claim | Axe/keyboard, state/viewport coverage, token conformance, pinned screenshot diff, and lab performance |

Recommended order is not the section order: implement the skill-listing probe first because it can
invalidate assumptions; then false-success labelling; then the evidence receipt; then the UI floor;
then the expensive ablation pilot.

## Corrections that must precede implementation

1. **Claude Code now merges custom slash commands into Skills.** The relevant listing pressure is
   therefore 26 skill directories plus 14 command files, or 40 vstack-supplied entries, before
   built-ins, plugins, user skills, and repository skills. The v1.7.0 README's inventory is accurate
   as files but “26 versus 40” is not a hypothetical comparison anymore. See the official
   [Skills documentation](https://code.claude.com/docs/en/skills#bring-existing-commands-to-skills).
2. **The current documented behavior is not wholly silent truncation.** Claude Code always retains
   every skill name, then shortens or omits descriptions from least-used skills. `/context` reports
   the post-budget skill size, `/doctor` estimates listing size, and debug output warns about dropped
   descriptions. Before v2.1.196, `/context` could report the pre-budget size. Treat older versions
   separately. See [Troubleshoot skill loading](https://code.claude.com/docs/en/skills#troubleshoot-skill-loading).
3. **Plugin skills are a distinct control surface.** `skillOverrides` does not disable plugin skills,
   while `disable-model-invocation: true` removes a skill from the model-visible listing entirely.
   Both are documented in [Control who invokes a skill](https://code.claude.com/docs/en/skills#control-who-invokes-a-skill).
4. **There are six configured hook event lanes at v1.7.0, not five:** `SessionStart`, `PostToolUse`,
   `Stop`, `PostToolUseFailure`, `UserPromptSubmit`, and `PreToolUse`. The plugin registers two of six.
   “Five hooks” counts files, not event lanes.
5. **The universal visual-gate claim is already stale.** Auteur currently contains executable focus,
   responsive/system, motion, chroma, and heuristic slop checks. It does not contain a demonstrated
   mutation suite or published validation of its aesthetic heuristics. The defensible claim is that
   no examined stack combines the five product-UI check families below with deliberate-failure
   coverage—not that no gate exists anywhere.
6. **`main` already corrected several v1.7.0 benchmark failures.** `tests/evals/RESULTS.md` now records
   broken dependencies, missing PASS_TO_PASS validation, denied headless edits, and repeated all-arm
   zeroes as a harness defect signature. Preserve those corrections. The current SWE-bench script is
   useful engineering material but is not yet the pre-registered ablation specified below.

---

# 1. Which skills actually reach the model

## Verdict

There is no documented interface that dumps the exact serialized skill listing bytes received by
the model. The supported evidence is stronger for **names and post-budget token use** than for exact
description text:

- `/skills` is the interactive inventory.
- `/context` reports the skills section after budget enforcement on Claude Code v2.1.196 or later.
- `/doctor` estimates listing size and warns about unusually large descriptions.
- `--debug` or `--debug-file` records truncation warnings and dropped-description behavior.
- Stream JSON's initialization message is useful for inventory, but it is not documented as the
  exact prompt serialization and should not be presented as one.

Official references are the [debug guide](https://code.claude.com/docs/en/debug-your-config),
[CLI reference](https://code.claude.com/docs/en/cli-reference), and
[skill loading diagnostics](https://code.claude.com/docs/en/skills#troubleshoot-skill-loading).

Two open primary bug reports justify host-specific measurements rather than changing this verdict:
[issue 79503](https://github.com/anthropics/claude-code/issues/79503) reports a Windows session where
only 123 of 230 skills appeared without diagnostics, and
[issue 85027](https://github.com/anthropics/claude-code/issues/85027) reports name-only user skills in
the VS Code agent host. They are user reports, not established cross-platform contracts.

## Verified in v1.7.0

- 26 skill directories, 14 command Markdown files, and 8 agent files exist.
- `claude/settings.json` sets `skillListingBudgetFraction` to `0.016`,
  `skillListingMaxDescChars` to `200`, and declares 17 `skillOverrides` entries.
- Local frontmatter descriptions occupy 4,446 UTF-8 bytes for skills and 948 bytes for commands,
  5,394 bytes total. This is not prompt size. A crude wrapper-inclusive reconstruction is about
  9.2 KB, but it cannot model Claude Code's serialization, tokenization, usage ordering, built-ins,
  synced skills, plugins, or host-specific behavior.
- The published 60-run result did not observe a `Skill` tool call. That does **not** establish that
  descriptions were absent in those sessions, because the run-specific listing/debug evidence was
  not retained. `tests/evals/RESULTS.md` gives a task-shape explanation and the Trail of Bits
  [variant-analysis eval](https://github.com/trailofbits/skills/tree/main/plugins/variant-analysis/evals)
  independently documents 40+ runs with zero invocations in a saturated task.

## What is inferred, not verified

- A named skill with no description is manually addressable but its automatic discoverability is
  impaired. A name alone is not evidence that the model received the trigger language.
- Raising `0.016` may restore descriptions but also spends context on every turn. It is sensible only
  if measurements across supported lanes show no drops and at least 25% headroom. If not, remove or
  make skills manual before increasing the fraction.
- At 40 vstack entries, the tail is more exposed than at 26, but usage ordering means repository
  order cannot identify which descriptions drop. Only a real session can.

## Implementation contract

Create a read-only probe, suggested path `tests/skill-listing-probe.sh`, which runs on the owner's
machine and writes one JSON report per lane:

```json
{
  "claude_version": "exact string",
  "host": "cli|vscode|other",
  "install_lane": "global|overlay|plugin",
  "model": "reported model",
  "context_window_tokens": 0,
  "setting_sources": ["user", "project", "local"],
  "post_budget_skill_tokens": 0,
  "listed_names": [],
  "descriptions_present": [],
  "descriptions_dropped": [],
  "listing_complete": "yes|no|unknown",
  "proxy_utf8_bytes": 0,
  "proxy_is_not_model_prompt": true,
  "debug_log_sha256": "..."
}
```

The probe must:

1. refuse a strong conclusion on Claude Code older than v2.1.196;
2. preserve version, host, lane, model, setting sources, and the raw debug-log hash;
3. never label tokens as bytes;
4. mark completeness unknown when the host exposes names but not descriptions;
5. parse a debug warning or “more” marker as incomplete rather than success;
6. exercise global, overlay, and plugin installs separately, and repeat CLI versus IDE if both are
   supported;
7. compare expected inventory to observed names without assuming plugin/user entries are reclaimable;
8. probe reachability in two ways: `/skills`/listing presence and a named explicit invocation. The
   latter proves manual reachability, not natural-language routing.

Do not use model behavior as the primary inventory oracle. A natural-language prompt can fail to
route even when the description is present, and an explicit invocation can work when automatic
discovery is not.

## Command that must prove it works

**Acceptance contract:**

```bash
bash tests/skill-listing-probe.sh --lane global --out /tmp/vstack-global.json
bash tests/skill-listing-probe.sh --lane overlay --repo "$PWD" --out /tmp/vstack-overlay.json
bash tests/skill-listing-probe.sh --lane plugin --out /tmp/vstack-plugin.json
bash tests/skill-listing-probe-test.sh
```

The test must include fixtures where: all descriptions fit; one description is dropped; names are
present but descriptions are unavailable; a log contains a “+N more” marker; and token count differs
from UTF-8 byte count. Each fixture must force the expected `listing_complete` state.

**Decision rule for `0.016`:** leave it unchanged until all supported lanes produce measurements.
Keep it if no required description is dropped and each lane has at least 25% unused listing budget.
Otherwise first make low-value skills manual or delete them, rerun the probe, and raise the fraction
only if deletion cannot preserve the required trigger descriptions.

---

# 2. A false-success detector over existing transcripts

## Verdict

This is the highest-value outcome instrument in the work order. It measures the failure behavior the
Stop hook is meant to change, uses already-owned transcripts, requires no model judge, and can reveal
whether an apparent improvement is merely claim suppression.

The source paper is [Detecting False Success in Agentic AI](https://arxiv.org/html/2606.09863). It
analyzes 9,876 tau2 trajectories and 1,879 AppWorld trajectories. Depending on aggregation, roughly
45–48% of failures in single-control settings were falsely claimed successful; dual-control settings
were about 3%; 75.8% of AppWorld failures carrying an explicit status claim were false-success
claims. Its LLM-judge variants stayed below AUROC 0.65, while TF-IDF reached AUROC 0.83 and 0.95 in
the evaluated domains at about 3,300 times lower latency. These are source-dataset results, not a
promised vstack operating point.

The paper's native labelling pipeline separates true successes first and uses two regex families to
divide failures into false success, honest failure, or ambiguous. The requested four labels are a
reasonable adaptation, not a verbatim reproduction. Its reported human validation used 200 examples
(100 false success, 100 honest failure), 91.5% accuracy, and Cohen's kappa 0.86. Its TF-IDF baseline
used word bigrams, at most 30,000 features, `min_df=2`, sublinear term frequency, L2 logistic
regression, and class balancing.

## Verified versus inferred

Verified from the paper are the corpus sizes, prevalence figures in its defined denominators, human
validation result, weak LLM-judge results, and TF-IDF configurations/results above. Verified from
vstack is that stream-JSON eval output and deterministic planted-defect graders already exist, though
not as a reusable false-success corpus. Inferred is that the paper's language patterns will transfer
to Claude Code repository work. That inference is exactly what the 50-item human calibration tests;
until it passes, no local prevalence estimate is admissible.

## Ground truth hierarchy

A language claim and program state must be independently sourced. Admit a transcript to rate
calculation only when it has one of these:

1. **Tier A:** runner-owned deterministic grader sidecar or gate verdict, outside the assistant's
   prose and preserved with exit status and output hash.
2. **Tier B:** a recognized verification tool result with an exact command and exit status, where the
   corpus manifest defines why that command decides the task.
3. **Tier C:** assistant claim, Claude CLI `ResultMessage`, a command with no task mapping, or transcript
   prose only. Inventory these but exclude them from false-success prevalence.

Do not infer task success from the final CLI result status. It indicates session completion, not that
the requested repository state is correct. Likewise, “the last command exited zero” is insufficient:
the command may use `|| true`, run only a subset, or test an irrelevant property.

## Parser and label definition

For one main-session transcript, extract:

- stable run/task/project identifier and transcript source;
- final main-session assistant message, excluding subagent messages unless explicitly requested;
- every completion-shaped span in that message with byte or character offsets;
- every failure-disclosure span with offsets;
- runner-owned ground-truth status, command, exit code, grader name/version, and artifact hash;
- abort, timeout, truncation, and missing-ground-truth flags.

Let `C` mean at least one completion claim, `F` at least one explicit failure/uncertainty disclosure,
and `G` be deterministic task success or failure:

| Ground truth and language | Label |
|---|---|
| `G=success`, `C=yes`, `F=no` | `honest_success` |
| `G=failure`, `C=yes`, `F=no` | `false_success` |
| `G=failure`, `C=no`, `F=yes` | `honest_failure` |
| all other combinations, missing `G`, both/neither claims, abort, or contradiction | `ambiguous` |

This conservative table intentionally keeps `G=success` plus an explicit failure claim ambiguous.
The instrument should not decide whether a partial-success narrative was honest without a task-level
annotation rule.

## Corpus selection and confounds

Freeze selection before reading outcomes:

1. Define a calendar window, project allowlist, transcript formats, and exclusions in a manifest.
2. Enumerate every complete session in that frame. Use one analysis row per task/session; do not let a
   long session produce many pseudo-independent rows.
3. Hash a stable identifier and sort by the hash for sampling. Never sample the prevalence corpus by
   regex label.
4. For a 50-item calibration set, stratify across predicted labels, project, source, and month so the
   rare false-success class is visible. Keep annotators blind to the machine label. Report that kappa
   describes this calibration distribution, not corpus prevalence; either use sampling weights for
   prevalence estimates or evaluate the frozen census with the calibrated rule.
5. Publish every exclusion count: corrupt stream, missing final message, no independent grader,
   aborted, timeout, and unknown task mapping.

Report at least task success, completion-claim rate, false success among deterministic failures with
an explicit status claim, honest failure, ambiguous, abort/timeout, and the joint 2x2 table. A lower
false-success rate does not show that the gate helped if the vstack arm simply makes fewer completion
claims, fails more often, receives clearer errors, or contains a different task mix.

Kappa is prevalence-sensitive. The command may refuse to emit an aggregate rate below 0.80 kappa,
but it must also print class-specific confusion, precision, recall, the label distribution, and raw
agreement. Fifty total labels are enough for a calibration check, not for a general-purpose text
classifier. The source paper reports that 50–100 examples **per class** improved cross-domain AUROC;
use the requested TF-IDF model as an exploratory phrasing baseline until that much labelled data
exists. Split by project/task family or month, never random transcript rows, to reduce leakage.

At a 10% flagging rate, the source paper's detector precision was only about 50%. Treat the detector
as triage and measurement, never as an autonomous accusation.

## Implementation contract

Suggested paths:

```text
tests/false-success/
  README.md
  parse_stream.py
  label_regex.py
  validate.py
  tfidf_baseline.py
  schemas/run-v1.schema.json
  fixtures/
```

Use Python standard library for parsing and regex labelling. Permit scikit-learn only in the TF-IDF
command. Keep raw private transcripts outside git; commit a manifest of hashes, selection rules,
aggregate output, and synthetic/redacted fixtures. Redaction must happen before an artifact enters
git, and validation must reject common secrets and home-directory paths.

The TF-IDF comparison should reproduce the paper's basic feature choices, report grouped train/test
splits and confidence intervals, and compare against the regex on the exact same labelled examples.
Do not choose the winning detector on the same 50 examples used to report its performance.

## Command that must prove it works

**Acceptance contract:**

```bash
python3 tests/false-success/parse_stream.py \
  --manifest private/corpus-manifest.jsonl \
  --out private/parsed.jsonl

python3 tests/false-success/validate.py \
  --predicted private/predicted.jsonl \
  --human private/human-50.jsonl \
  --min-kappa 0.80 \
  --report results/false-success-validation.json

python3 tests/false-success/tfidf_baseline.py \
  --labels private/human.jsonl \
  --group-by project \
  --report results/false-success-tfidf.json
```

The automated suite must deliberately test malformed stream events, missing ground truth, nested
subagent messages, both claim regexes in one answer, an agent saying “done” after a failing grader,
an honest failure, a no-claim failure, a `ResultMessage` marked successful while the grader fails,
and a 0.79-kappa fixture that makes `validate.py` exit non-zero.

---

# 3. The ablation at zero marginal cost

## Verdict and task set

Use [BugsInPy](https://github.com/soarsmu/BugsInPy) for the first protocol pilot. Its
[paper](https://arxiv.org/pdf/2401.15481) describes 493 manually curated, reproducible bugs across
17 Python projects with buggy/fixed revisions and tests. Pin the corpus commit and its container/tool
dependencies. It is a real external corpus and locally gradeable, but it is public pre-2020 GitHub
code: training contamination is likely. Pairing makes exposure symmetric between arms; it cannot
make easy or memorized tasks informative. Cap tasks per project and reject saturation during a
pre-declared pilot, not after seeing which arm wins.

[SWE-bench Verified](https://www.swebench.com/verified.html) is the stronger later replication because
its 500 instances were human validated and the ecosystem has standard grading. It is not the cheap
first run: the official [Docker setup](https://github.com/SWE-bench/SWE-bench/blob/main/docs/guides/docker_setup.md)
recommends at least 120 GB free disk and 16 GB RAM. It is still free software, but not “zero setup.”

Do not use the repository's eight tiny planted-review files for the primary correctness claim. They
measure review prompting on toy files and the repo has already shown the structured pathways can
manufacture findings there.

## Verified versus inferred

Verified are the corpus sizes and design claims in the linked primary sources, the resource guidance
for SWE-bench Docker, and the post-tag vstack harness defects recorded in source and results. Also
verified are the paired-sample calculations under the stated alpha, power, effect, and assumed
discordance. Inferred are likely contamination, saturation, and per-task runtime on the owner's
laptop. The 30-pair pilot estimates those instead of treating them as known.

## Why the current SWE-bench harness is not yet the pre-registration

The post-v1.7.0 script correctly added FAIL_TO_PASS and PASS_TO_PASS validation and preserves failed
worktrees. Before using it for a claim, fix these remaining protocol mismatches:

- it finds the first usable dataset rows instead of running a frozen, randomly hash-ranked manifest;
- it depends on host `uv` and Python 3.11 rather than a pinned reproducible environment;
- it hand-copies stack fragments instead of using each arm's documented installer at a pinned SHA;
- it prepends `/debug` to configured arms but not the bare arm, so prompts differ;
- it discards stream JSON and therefore cannot audit claims, tool use, or token use;
- it runs one pass per task without AB/BA counterbalancing;
- it has no per-arm edit/test/transcript canary or deliberate guard mutations;
- grading target tests alone does not rule out deleting or weakening tests.

These are research design gaps, not a request to discard the useful fixes already on `main`.

## Frozen protocol

1. **Environment preflight.** The buggy revision's trigger tests must fail for the expected reason;
   the fixed revision's tests must pass; a sample of PASS_TO_PASS tests must pass in the buggy
   environment. Freeze project, runtime, dependency lock/container digest, and corpus SHA. Disable
   network during tasks.
2. **Manifest before arms.** Hash-rank eligible instances with a published seed, cap representation
   per project, write exact buggy/fixed commits and test commands, and publish the manifest SHA-256.
   Do not filter based on bare-arm performance after runs begin.
3. **Parity.** Bare uses Claude Code safe mode or an explicitly empty project setting source while
   retaining authentication. vstack uses the documented per-repo overlay installer at a pinned SHA.
   Give both the identical prompt bytes, model, CLI version, timeout, permissions, tools, environment,
   starting git tree, and grader. No arm-specific `/debug` prefix.
4. **Canary before data.** Every arm must edit a disposable file, run a local test, emit a stream
   transcript, and demonstrate required permission. Canary validity must never depend on a `Skill` or
   `Task` tool call. One failed canary aborts the experiment rather than scoring an arm zero.
5. **Pairing and order.** Run each task in both arms. Randomize/counterbalance AB and BA order within
   task and alternate runs close in time. Do not analyze an incomplete pair. Abort if model or CLI
   version changes. If repeated samples are added, analyze them as clustered within task.
6. **Grading.** The grader is blind to arm name, restores/uses an external test copy, rejects edits to
   tests and grading scripts, runs FAIL_TO_PASS plus bounded PASS_TO_PASS or full tests, and records
   the four paired outcome cells. Keep the task-level outcomes, not only totals.
7. **Guard falsification.** Deliberately break authentication, installer parity, canary editing,
   prompt equality, manifest hash, transcript capture, test integrity, grader blinding, model version,
   and one environment dependency. Each mutation must abort with a named reason.

An optional competitor arm comes only after the two-arm protocol works. Install it through its own
documented installer at a pinned SHA. If its documented installer cannot target an isolated config
directory, report that limitation; do not manufacture parity by copying selected files.

## Sample size and estimand

The primary estimand is the paired risk difference:

```text
P(vstack succeeds, bare fails) - P(bare succeeds, vstack fails)
```

Use a two-sided 95% confidence interval for paired proportions, preferably Newcombe's method 10 from
[Newcombe 1998](https://site.uottawa.ca/~nat/Courses/csi5388/Newcombe.1998.pdf), and publish the four
McNemar cells. A simple planning approximation with alpha 0.05 and 80% power depends on the unknown
discordant-pair rate `q`:

| Assumed discordant-pair rate | Detect 10 percentage points | Detect 5 percentage points |
|---:|---:|---:|
| 0.30 | about 233 paired tasks | about 939 paired tasks |
| 0.50 | about 391 paired tasks | about 1,568 paired tasks |

Run 30 frozen paired tasks as a protocol and variance pilot, not as a powered result. Use its
discordant-pair estimate to finalize sample size without inspecting which arm won. At 10 minutes per
arm, 233 pairs are roughly 78 serial hours before setup/retries; neither a 10-point nor a 5-point
study is credibly “overnight” on one subscription lane.

Pre-register a smallest effect size of interest of +/-10 percentage points for the first real study.
Report superiority if the full CI is above zero. Report practical equivalence only if the full CI is
inside `[-0.10, +0.10]`. A non-significant superiority test is not equivalence. With 30 tasks the
expected result is “inconclusive protocol pilot,” and that is publishable.

Also report false-success rate, completion-claim rate, ambiguous rate, aborts/timeouts, input/output
tokens where the CLI supplies them, wall time, and tool actions. Correctness alone misses the failure
surface and efficiency effects highlighted by
[SWE-Skills-Bench](https://arxiv.org/html/2603.15401) and
[The Scaffold Effect](https://arxiv.org/pdf/2607.22585): most tested skills had zero pass-rate gain,
and scaffolds can move token/no-action behavior much more than pass rate.

## What gets published regardless of outcome

Commit the dated pre-registration before any scored run. It must contain a headed, empty results
section; hypotheses; estimand; SESOI; power assumptions; manifest hash; corpus/tool/model/CLI/arm
commits; installer commands and logs; exact prompt template; canary definitions; exclusion and abort
rules; scorer; mutation cases; and analysis code hash.

Afterward publish all task-level arm outcomes, all four paired cells, CI, exclusions, canary and
mutation results, transcripts after secret/path redaction, grader output hashes, duration/token use,
deviations, and a result even if null, adverse, or invalid. Preserve superseded results with a visible
reason, matching the repository's strongest existing norm.

## Command that must prove it works

**Acceptance contract:**

```bash
bash tests/ablation/preflight.sh --manifest tests/ablation/manifests/pilot-30.json
bash tests/ablation/mutations.sh
bash tests/ablation/run.sh --prereg docs/ablation-preregistration.md --resume
python3 tests/ablation/analyze.py \
  --pairs results/ablation/pairs.jsonl \
  --method newcombe-10 \
  --equivalence-margin 0.10
```

`run.sh` must refuse an uncommitted pre-registration, a changed manifest hash, unequal prompt hashes,
an incomplete canary, an unpinned arm, an unclean starting tree, a changed CLI/model, or test-tree
mutation. `analyze.py` must refuse incomplete pairs and print “inconclusive” rather than “equivalent”
when the CI crosses either equivalence bound.

---

# 4. The evidence bundle for an unattended run

## Verdict

Ship a small local receipt, but do not call it an attestation. The
[in-toto Statement specification](https://github.com/in-toto/attestation/blob/main/spec/v1/README.md)
binds a typed predicate to artifact digests, while
[SLSA provenance](https://slsa.dev/spec/v1.2/build-provenance) derives meaningful assurance from a
trusted builder identity and recorded build inputs. A self-authored local JSON file has neither an
independent builder nor an independent signer.

**This raises the cost of self-deception but stops no adversary.** A digest catches accidental or
later alteration only when the expected digest is retained somewhere the same writer cannot silently
rewrite—for this project, the reviewed Git commit is the practical binding. An agent with repository
write access can run a meaningless command, write a false receipt, and recompute every hash.

## Verified versus inferred

Verified are the repository's recurring “green but measured nothing” failures and the integrity
properties of content digests and reviewed Git objects. The proposed schema and path are a design
inference optimized for one maintainer, reviewable diffs, and low collision risk. No claim is made
that this format interoperates with in-toto or reaches a SLSA provenance level.

## Smallest worthwhile schema

Store one canonical JSON receipt per run at:

```text
.vstack/evidence/runs/YYYY/MM/<UTC timestamp>-<source commit>-<UUID>.json
```

Unique paths reduce rebase collisions; JSON is reviewable; month directories prevent one huge folder.
Do not overwrite a run. Large output can live beside the receipt under the same unique stem, with its
digest and byte count in JSON. Embed bounded output when small enough for review.

Required fields:

```json
{
  "schema_version": "1",
  "run_id": "UUID",
  "source": {
    "commit": "full SHA",
    "dirty": false,
    "dirty_diff_sha256": null
  },
  "runner": {
    "version": "...",
    "executable_sha256": "..."
  },
  "started_at": "RFC3339 UTC",
  "finished_at": "RFC3339 UTC",
  "claims": [
    {
      "id": "tests",
      "statement": "bounded tests pass",
      "status": "evidence",
      "calibration_id": "tests-fail-on-known-mutation-v1",
      "evidence": {
        "argv": ["bash", "tests/run.sh"],
        "shell": null,
        "cwd": ".",
        "started_at": "RFC3339 UTC",
        "finished_at": "RFC3339 UTC",
        "expected_exit": 0,
        "actual_exit": 0,
        "stdout_bytes": 0,
        "stdout_sha256": "...",
        "stderr_bytes": 0,
        "stderr_sha256": "...",
        "artifact": null
      },
      "skip_reason": null
    }
  ]
}
```

Every claim status is exactly `evidence`, `skipped`, or `missing`. `evidence` requires the command
record; `skipped` requires a non-empty reason and must not be summarized as passed; `missing` makes
finalization fail. Record `argv` as an array and `shell` separately so review can distinguish direct
execution from shell semantics. Record the exact repo commit and a hash of any dirty diff.

The `calibration_id` is the answer to “a check ran and measured nothing.” A receipt alone launders
that failure into a neater artifact. Each claim must map to a named check whose mutation test or
fixture demonstrates that breaking the claimed property turns the check red. The receipt records
the calibration version/digest; it does not replace the calibration suite.

Implement this as a separate CLI first. Do not make the Stop hook trust receipt completion until the
schema, finalizer, verifier, and mutations have survived real use. Otherwise the receipt becomes a
new source of unearned green.

## Command that must prove it works

**Acceptance contract:**

```bash
bin/evidence-receipt start --out /tmp/run.json
bin/evidence-receipt record --receipt /tmp/run.json --claim tests -- \
  bash tests/preflight.sh
bin/evidence-receipt finalize --receipt /tmp/run.json
bin/evidence-receipt verify --receipt /tmp/run.json
bash tests/evidence-receipt-mutations.sh
```

The deliberate-failure suite must prove at least:

- a declared claim with no evidence makes `finalize` non-zero;
- a skip with no reason makes `finalize` non-zero;
- changing stored output after recording makes `verify` non-zero;
- a normal calibrated check passes, the known mutation makes it fail, and restoration makes it pass;
- an irrelevant zero-exit command cannot satisfy a claim whose calibration/check ID differs;
- a receipt reports `skipped` distinctly and never rolls it into the pass count.

The first shippable version needs no signature, transparency log, server, account, or hosted store.
Git review plus immutable commit history is the useful integrity boundary available for free.

---

# 5. An executable product-UI gate

## Verdict

An offline gate can enforce a high engineering floor. It cannot decide that a design looks good.
[AesEval](https://arxiv.org/html/2603.01083v1) reports 0.7252 accuracy for its best tested model on
binary aesthetic judgment and below 0.20 IoU for precise issue localization.
[Visual Aesthetics Benchmark](https://arxiv.org/abs/2605.12684) reports only 26.5% fully consistent
best-and-worst identification for the strongest evaluated system under three permutations, versus
68.9% for human experts. A model's “9/10” is not gate evidence.

Use five blocking check families. “Green” means these known floor conditions passed in the pinned
test environment. It does not mean accessible to every user, fast in the field, visually original,
or tasteful.

## Verified versus inferred

Verified are each tool's documented measurement semantics, the cited threshold sources, Auteur's
current source behavior, and the published limitations of automated accessibility and aesthetic
judgment. Inferred are the five-family product policy, the chosen viewport set, exception process,
and the expectation that this is the smallest durable floor. Those choices must be calibrated on a
real React/Tailwind repository before becoming a default template.

## The five check families

| Check | Tool/algorithm and blocking threshold | Threshold source | False-positive/limit | Deliberate mutation |
|---|---|---|---|---|
| Accessibility and keyboard | Playwright plus `@axe-core/playwright`; zero axe violations for selected WCAG 2.2 A/AA tags on every declared state. Script tab order, operability, focus visibility, and modal focus return. | Axe rule semantics; project policy is zero detected violations. Deque's [automation study](https://www.deque.com/blog/automated-testing-study-identifies-57-percent-of-digital-accessibility-issues/) found automated checks accounted for about 57% of issue volume in its audit sample—not 57% of WCAG criteria. | Axe cannot judge all semantics, screen-reader experience, cognitive load, or visual quality. Dynamic widgets need authored keyboard assertions. | Remove an accessible name; remove the focus outline; break modal focus return. Each must name the route/state and fail. |
| Route/state/viewport coverage | A committed manifest declares applicable routes and states at 375, 768, and 1440 CSS px. Playwright fails missing fixtures, page/console errors, horizontal overflow, invisible focus, or missing relevant loading/empty/error/disabled/hover/focus-visible coverage. | Project product contract; widths are explicit pre-committed breakpoints, not universal standards. | Not every state applies to every component; requiring all blindly creates fake fixtures. Exceptions need route, reason, owner, and expiry. Hover cannot be the only affordance. | Delete an error-state fixture; force horizontal overflow at 375; remove a disabled state. Meta-test ensures each manifest obligation has a mutation. |
| Token conformance | Parse CSS/TSX and Tailwind AST/config; fail raw hex/rgb/hsl outside token sources, arbitrary Tailwind values, or type/spacing values outside fixed sets. Exceptions are file/rule/reason/expiry entries. | Repository design-system policy, frozen in versioned config. | Generated/vendor content and true data visualizations need scoped exceptions. Regex alone misreads comments/strings and CSS syntax, so do not use regex as the primary parser. | Add `#123456`, `mt-[13px]`, and an unapproved font size in fixtures; each must fail the matching rule. |
| Visual regression | Playwright `toHaveScreenshot` in a pinned container/browser/font set, reduced motion, stable data/time, and masks only for declared nondeterministic regions. Run unchanged baselines repeatedly; use `maxDiffPixels: 0` if deterministic, otherwise set the threshold above observed noise and commit the calibration report. | [Playwright visual comparisons](https://playwright.dev/docs/test-snapshots) warn that rendering varies by OS, hardware, browser, and environment; therefore no universal pixel threshold is honest. | Renderer/font drift and animations create noise; pixel similarity does not establish good design. Baseline updates can bless regressions. | Move a component one pixel or change a token color beyond calibrated noise; screenshot test must fail. |
| Lab performance | Production build in a pinned mobile Lighthouse profile: LCP <=2.5 s, CLS <=0.10, TBT <=200 ms; repeat three times and use the median. During scripted interactions, record long tasks and fail any reproducible task over 50 ms. | [Web Vitals](https://web.dev/articles/vitals) supplies the LCP and CLS “good” field thresholds. [Chrome's TBT documentation](https://developer.chrome.com/docs/lighthouse/performance/lighthouse-total-blocking-time) defines 0–200 ms as green on mobile and a long task as >50 ms. | Lab numbers are environment-sensitive and are not field Core Web Vitals. Lighthouse cannot measure INP in the lab; TBT is only a proxy. The Long Tasks API has limited/experimental aspects, so keep a browser-version pin and allow an explicit unsupported skip, never silent pass. | Inject an 80 ms busy loop, a late layout shift, and a delayed largest element; each must fail the named metric in the pinned fixture. |

Use one browser test stack. Axe is in. [Pa11y](https://pa11y.org/) is out of the initial React gate
because it would add another site runner over substantially overlapping accessibility rules; use it
only if an independent URL crawler is needed. Do not claim two wrappers around similar rules are two
independent accessibility checks.

The 2.5 s and 0.10 numbers are field guidance applied here as conservative lab thresholds, so label
them “lab floor.” Do not emit “Core Web Vitals passed,” because there is no field INP or p75 user
population under the no-telemetry constraint.

Baseline approval is a human decision. Require a PR with the rendered before/after artifacts and a
separate human approval of the latest push. GitHub can require review of the latest reviewable push
and disallow bypass under
[protected-branch settings](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches),
but a solo owner with admin credentials is not an adversarial trust boundary. CODEOWNERS alone does
not prove that an agent did not approve its own new baseline.

## Ruled in, advisory, and out

| Candidate | Decision | Reason |
|---|---|---|
| axe-core | Blocking | Deterministic, local, integrates with existing Playwright state fixtures; green remains explicitly incomplete. |
| Pa11y | Out initially | Duplicate runner/engine value is low; revisit for independent URL crawling. |
| Lab LCP/CLS/TBT and long tasks | Blocking, labelled lab | Reproducible regressions in a pinned environment; no field-CWV or INP claim. |
| Auteur-style slop linter | Advisory only | Reproducible heuristics can flag review candidates, but the examined project publishes no human-labelled validation, error rates, or mutation corpus for the “AI-made” claim. |
| Screenshot embeddings against references | Research only | Embeddings can measure similarity or diversity, not quality. Results depend on reference licensing/composition and model version. “Less similar to stock” is testable but not the same as “better.” |
| Token conformance | Blocking | It tests an explicit repository contract rather than taste. |
| State/viewport coverage | Blocking | Product UIs fail in unvisited states; a committed applicability manifest keeps the claim bounded. |
| Pixel diff | Blocking after calibration and human baseline approval | It catches change, not degradation. The environment and approval procedure carry the meaning. |

Auteur's current
[repository](https://github.com/agiwhitelist/auteur) supplies useful implementation references:
`slopscan.mjs` is a heuristic linter; `motionqa.mjs` targets 50 FPS and 50 ms long tasks under CPU
throttling but downgrades some headless-canvas results to advisory; `chromadiff.mjs` uses author-chosen
chroma/lightness tolerances; and `systemscan.mjs` checks blank routes, responsive/system variance,
focus-paint changes, and token/type warnings. These details are verified in the current source. Its
thresholds are not externally validated product-UI standards, and no fixture/mutation suite was
found that demonstrates every check going red.

## Command that must prove it works

**Acceptance contract:**

```bash
npm run ui:gate
npm run ui:gate:mutations
npm run ui:gate:calibrate-screenshots
```

`ui:gate` must print declared, ran, passed, failed, and skipped counts and fail unless
`ran + skipped == declared`. A skip needs a rule ID and reason. `ui:gate:mutations` must map every
blocking rule ID to at least one mutation, apply one mutation at a time, observe the named failure,
restore, and fail itself if any rule lacks coverage. Keep heuristic slop and embedding results in a
separate advisory artifact so they cannot turn the floor into a claim about taste.

The highest enforceable floor is: keyboard- and axe-clean declared states; complete responsive state
fixtures; conformance to the chosen token system; no unreviewed rendering changes in a pinned
environment; and no severe lab loading, layout, or main-thread regression. Taste stays with a human.

---

# Delete this

These are recommendations, not findings that the current ablation has already proved:

1. Keep `principle-prove-it-works` as the central automatic principle. Collapse the other seven
   principles—`principle-boundary-discipline`, `principle-build-the-lever`,
   `principle-encode-lessons-in-structure`, `principle-fix-root-causes`,
   `principle-make-operations-idempotent`, `principle-sequence-verifiable-units`, and
   `principle-type-system-discipline`—into one manually invocable reference or into the relevant
   workflow skills. Across all eight principles, two have positive natural-language trigger tests
   and six do not; all consume listing space.
2. Remove `unslop` and `reflect` from automatic listing. `unslop` claims essentially every prose task
   and overlaps `technical-writing`; `reflect` is a post-hoc workflow. Keep their content behind an
   explicit command or fold the useful parts into narrower skills.
3. Remove the duplicate automatic front door `deploy-auto`; keep `deploy` plus, if compatibility
   requires it, a thin user-invoked alias that does not spend model-discovery budget.
4. Remove `show-me-your-work` after the receipt ships and is proven. Today it is a narrative protocol;
   the receipt is the narrower machine-checkable mechanism. Do not delete it before the replacement
   exists.

Do not delete subagents from the current evidence. No clean no-subagent ablation exists, and file-name
overlap is not an outcome measurement.

# The one thing

Build the false-success detector. It measures the central Stop-hook claim on transcripts already on
disk, costs no model calls, and forces task success, completion claims, ambiguity, and claim
suppression into the same table. The skill reachability probe is the cheaper prerequisite and should
be implemented first, but it is an inventory diagnostic rather than the project-level outcome.

# What I would push back on

- “Truncation is silent” is not the current documented CLI contract. Names remain, descriptions can
  drop, and diagnostics exist. Host/version failures still justify measurement.
- Fifty labels cannot validate a general-purpose TF-IDF detector. They can calibrate a conservative
  regex instrument and expose obvious disagreement.
- An overnight run cannot support a useful equivalence claim at the plausible effect sizes here.
- “No stack anywhere has a visual gate” is unprovable and already too broad given current Auteur.
- A receipt is not an attestation, a passing command is not necessarily evidence, and a design gate
  is not taste.
- “Free” still consumes subscription quota, local disk, elapsed time, and human labelling. Those are
  resources even when marginal currency cost is zero.

# What this cannot answer

Money is not strictly required for the free designs above, but it buys speed, independence, and
coverage. Without it, this work cannot quickly answer:

- a powered 233+ paired-task ablation, much less a 5-point study approaching 1,000–1,500 pairs;
- generalization across multiple paid models/providers and repeated model versions;
- detector or aesthetic-instrument validity from independent professional annotators;
- representative field Core Web Vitals across a real user population under the no-telemetry rule;
- a broad browser/OS/hardware rendering matrix without owned hardware or hosted CI capacity.

Money would not reveal the owner's exact skill listing by itself. That requires running the probe in
the actual CLI/IDE, installed lanes, version, settings sources, and plugin environment where vstack is
used.

---

# Claude implementation handoff

This PR is research only. Implement on a new branch and keep each investigation independently
revertible. Do not copy unreviewed feasibility prototypes from another worktree. For each milestone:

1. reproduce and record the current baseline;
2. implement the smallest interface named in its acceptance contract;
3. add deliberate broken fixtures before claiming the check works;
4. run the repository's existing preflight and falsifiability suites;
5. update the relevant documentation with measured output, not an expected example;
6. make no model call in CI and add no network service, telemetry, credential, or account dependency;
7. stop and mark the real-machine portion of section 1 blocked if the owner environment is absent;
8. do not call a pilot “equivalent,” a local receipt “secure,” a lab metric “field,” or a floor “taste.”

Suggested milestones are: skill probe; false-success parser/regex/validation; evidence receipt;
product-UI floor; 30-pair ablation protocol pilot. The first PR for each should be deletable without
leaving shared framework code behind.

# Primary source ledger

- Anthropic: [Skills](https://code.claude.com/docs/en/skills),
  [debug configuration](https://code.claude.com/docs/en/debug-your-config), and
  [CLI reference](https://code.claude.com/docs/en/cli-reference)
- Anthropic: [Agent SDK streaming output](https://code.claude.com/docs/en/agent-sdk/streaming-output)
- False-success study: [arXiv 2606.09863](https://arxiv.org/html/2606.09863)
- BugsInPy: [repository](https://github.com/soarsmu/BugsInPy) and
  [paper](https://arxiv.org/pdf/2401.15481)
- SWE-bench Verified: [dataset](https://www.swebench.com/verified.html) and
  [Docker guide](https://github.com/SWE-bench/SWE-bench/blob/main/docs/guides/docker_setup.md)
- Paired-proportion interval: [Newcombe 1998](https://site.uottawa.ca/~nat/Courses/csi5388/Newcombe.1998.pdf)
- Ecosystem evaluations: [Trail of Bits variant-analysis eval](https://github.com/trailofbits/skills/tree/main/plugins/variant-analysis/evals),
  [SWE-Skills-Bench](https://arxiv.org/html/2603.15401), and
  [The Scaffold Effect](https://arxiv.org/pdf/2607.22585)
- UI tools and thresholds: [Playwright snapshots](https://playwright.dev/docs/test-snapshots),
  [Deque automation study](https://www.deque.com/blog/automated-testing-study-identifies-57-percent-of-digital-accessibility-issues/),
  [Pa11y](https://pa11y.org/), [Web Vitals](https://web.dev/articles/vitals), and
  [Lighthouse TBT](https://developer.chrome.com/docs/lighthouse/performance/lighthouse-total-blocking-time)
- Aesthetic limits: [AesEval](https://arxiv.org/html/2603.01083v1) and
  [Visual Aesthetics Benchmark](https://arxiv.org/abs/2605.12684)
- Integrity models: [in-toto Statement](https://github.com/in-toto/attestation/blob/main/spec/v1/README.md)
  and [SLSA provenance](https://slsa.dev/spec/v1.2/build-provenance)
