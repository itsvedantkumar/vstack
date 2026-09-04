# Plan: the next mechanisms, items 2 to 7 of the recommendations draft

Written 2026-09-03 on tree cdbe836 (1.69.0) by three read-only planner arms on Fable 5.1, one per
mechanism pair, merged and ordered by RICK. Each arm was told the measured facts it must not
contradict: correctness parity on every Claude arm, cost parity once the breadth mandate was retired,
zero false completions on Claude, and a gate that has never fired on a live run. Item 1 (breadth)
shipped in 1.69.0; its plan is `plan-breadth-retirement.md`.

## What the three arms agree on

- The draft's "today" is wrong in three places for this tree: item 2's fallback to an untrusted
  `package.json` test reopens a closed hole (ZEEP-A); CLAUDE.md is 4.3 KB, not 8.7 KB, and subagents
  never see the per-prompt digest (ZEEP-B); the "third column mandatory" rule for mechanisms has no
  enforcer (ZEEP-C).
- Every remaining mandate (naming, swarm-first, serial-tail) is justified by nothing measured. The
  ledger with expiration (ZEEP-C, check 65) is the one change that forces the others to happen or
  the mechanisms to go, so it ships first.
- Nothing here can be measured on a Claude arm until a fixture has a base rate: ZEEP-A's pilot on a
  five-module edge-case fixture (n=20, go at 30% first-pass red) is the prerequisite for any gate
  change and costs nothing.
- Every payload edit lands in one 1.70.0 bump: both manifests, `claude/inventory.json`,
  `tests/inventory-contract.sh --write`, the README pin, and `git ls-remote --tags origin` before
  choosing the number.

## Order

1. ZEEP-C commit 1 and ZEEP-A commit 1 (docs only): correct the draft.
2. ZEEP-A commits 2 and 3 (harness and fixtures, no bump): `SHOWCASE_GATE_CAP`, structured feedback
   fields, the defect-report exit, `traps/five_module_edges/`, `traps/contradictory_spec/`, then the
   free GLM pilot that decides whether the gate is measurable at all.
3. ZEEP-C commits 2 to 4 (payload, 1.70.0): mechanisms ledger, check 65 with rows 65/65b/65c,
   admission fields in `dispatch-counter.sh` with row 44h, the skill-load ledger.
4. ZEEP-B commits 1 to 3 (payload, same 1.70.0): the CLAUDE.md trim per the disposition table, the
   digest and SessionStart cuts with check 18 re-anchored, the swarm brief template and callee
   contract.
5. ZEEP-A commit 4 (payload, 1.70.0 or 1.71.0 depending on the pilot): cap 2 and fields in
   `verify-gate.sh`, only if step 2's pilot passed.
6. Measurements: ZEEP-B's paired Claude run (60 Opus runs, about $16 at $0.27 each, needs an explicit
   go), ZEEP-C commit 5 (`vstack-nomandate` vs `vstack`, 20 Opus runs), ZEEP-A's GLM runs (free).

## Measurement outcomes so far (2026-09-03)

- ZEEP-A commit 3, the pilot on `five_module_edges`, did not clear the 30% bar needed to make the
  gate measurable. The `verify-gate.sh` cap change (ZEEP-A commit 4) stays unshipped; the fallback
  named in the plan is a weaker OpenCode model, not more samples.
- ZEEP-A's `contradictory_spec` acceptance (tampering halved, no false completion in the exit arm):
  not met. Tampering 2 (exit) against 1 (no exit); one `DONE` over red in each gate arm. What the
  exit offer did deliver: 26 of 30 escalations with a correct report against 1 of 30 without it.
  Numbers in `tests/evals/showcase/RESULTS.md`.
- ZEEP-C commits 2 and 3 shipped in 1.70.0 (check 65, rows 65/65b/65c/44h, admission fields).
  Assumptions taken: decide_by 2026-09-17; unmeasured blocking mechanisms are listed in the ok line
  before that date and red after it; ledger cost comes from benchmark rows only.
- ZEEP-B commits 1 to 3 and ZEEP-C commit 4 shipped in 1.71.0 (main `8340ecf`). Decisions 1 and 2
  taken as the plan proposed: REGISTER keeps only the banned-word list, MODEL ROUTING and DISPATCH
  PRE-AUTHORIZED deleted; `claude/CLAUDE.md` 4332 B to 1635 B. The digest is conditional (0 B unfired,
  215 B fired). Decision 4 is closed by the pilot (cap change unshipped). Decisions 3 and 5 stand as
  assumed: decide_by 2026-09-17 with a warning before it, and the ZEEP-B paired run is not bought.
- The gstack arm, unmeasured since the breadth retirement, was rerun at v1.70.0: parity with
  vstack on `multi_module` (10 of 10 green each, cost 0.95x of vstack) and on `contradictory_spec`
  (every Opus arm fixed to spec and withheld DONE). Numbers in `tests/evals/showcase/RESULTS.md`.

## Decisions only the operator can take

1. The REGISTER paragraph of `claude/CLAUDE.md`: keep the banned-word list or delete the block.
2. The MODEL ROUTING and DISPATCH PRE-AUTHORIZED paragraphs: ZEEP-B deletes both on evidence
   (agent frontmatter pins the models; the pre-authorization has no mechanism). Both were added at
   the operator's request.
3. `decide_by` for the unmeasured mandates (ZEEP-C proposes 2026-09-17) and whether a `kind: none`
   mandate is red or a warning before that date.
4. ZEEP-A's release-on-defect-report lane in `verify-gate.sh`: it is a bounded self-report escape;
   go, or keep cap 2 and fields only.
5. The paid measurement budget in step 6.

## Items 2 and 3: the Stop gate and the failure payload (ZEEP-A, planner on Fable 5.1, read-only)

Verdict: ISSUES (plan complete, two named gaps).

### Today

- `claude/hooks/verify-gate.sh:25-44` opts in on a trusted `.claude/verify.sh`; `:145-157` blocks on the
  exit code and pastes the raw output; `:137-142,161-175` throttle re-runs at three and keep blocking
  on a cached red. No self-assessment is consumed anywhere.
- `claude/hooks/goal-gate.sh:97-131` blocks on unchecked `## Rubric` boxes, cap 3 then opens (`:115-120`).
  The release path is the agent ticking a box, a self-report.
- Wiring: `claude/settings.json` Stop runs verify-gate, skill-mandate, goal-gate; the plugin lane
  (`claude/hooks/hooks.json:16-27`) excludes verify-gate (check 47).
- Proofs: `.claude/verify.sh` check 14 (`:830-895`, block with and without jq, trust-drift refusal) and
  check 59 (`:4300-4365`); rows 14 (`tests/gate-falsifiability.sh:805`), 14b (`:822`), 59 (`:686`). The
  message shape is also read by `tests/compare-baseline.sh:89,125` and `tests/hook-latency.sh:350-353`.
- Instrument: `tests/evals/showcase/run.sh:113-131` replays the hook outside OpenCode, cap 3, raw
  `verify.sh` text; `oracle_verify` at `:73-86`.

### Where the draft is wrong for this tree

Item 2's "run `package.json` test when there is no trusted verify.sh" reopens the hole 1.30.0 and
1.46.0 closed: `README.md:349-356` names `scripts.test` as arbitrary code at Stop time,
`compare-baseline.sh:118-127` pins "untrusted, did not run it", and check 61 (`verify.sh:4436`) hashes
manifests for that reason. The cloud lane already arms trust (`overlay.sh:389`). Declined. The
goal-gate downgrade to a reminder is also declined: it blocks on the absence of a claim and its cap
already opens; the weak point is tick-to-release, unchanged either way, and the benchmark has zero
events to tell the two apart.

Item 3 stands on verified sources only: SV#12 (gains land in the first two rounds), SV#2
(self-feedback wrong 32 of 80), CC#20 (an escalation channel took the bad-completion rate from
23.6% to 5.3%). SV#5 is MISREAD; do not cite it.

### Commits

- C1 (no bump). `recommendations-draft.md`: item 2 declined with the pointers above; item 3 rewritten
  as cap 2 plus report-release.
- C2 (no bump). `tests/evals/showcase/run.sh:119-131`: `SHOWCASE_GATE_CAP` (default 2); the feedback
  message mirrors the hook's fields (`exit`, `attempt/cap`, `failing:` lines, `trace:` tail); at cap+1
  the driver offers the exit: write `DEFECT.md` naming each failing check. Row fields `gate_cap`,
  `defect_report`, `tests_tampered` (cmp `tests/` and `verify.sh` against the fixture). Two fixtures:
  `traps/contradictory_spec/` (spec and visible test disagree; meta `expect: "escalate"`; green means
  tests untouched, report names the failing check, no `DONE`) and `traps/five_module_edges/` (five
  modules with edge-case traps: half-even rounding, unicode width, tz offset, empty input, off-by-one
  range) for base rate. `tests/README.md` showcase section.
- C3 (no bump). Pilot GLM n=20 on `five_module_edges` to establish its first-pass red rate. Go if
  first-pass red is at least 30%; otherwise harden the fixture. Harder task, not bigger n.
- C4 (bump 1.70.0). `claude/hooks/verify-gate.sh`: `VSTACK_VERIFY_CAP` default 2 (replaces the two
  `-ge 3` sites at `:139`, cap named in the reason); reason built as fields, `failing:` = lines matching
  `^(FAIL|not ok|FAILED|AssertionError)`, `trace:` = last 40 lines; past the cap the reason names
  `.claude/verify-defect.md`; release lane: file mtime newer than `last_ts` and containing every
  extracted failing label releases with `{systemMessage: "released on defect report, tree still red"}`,
  one-shot via a `.rel` marker; `VSTACK_VERIFY_ESCALATE=0` restores always-block. Touch: check 14
  (four new lanes: fields present; exactly `cap` blocks then the exit is offered; an empty report does
  not release; a complete report releases as systemMessage); CHECKS= line plus rows 14c (`:-2` to `:-3`
  anchored on the default expansion) and 14d (drop the label-containment predicate); `README.md:342-347`,
  `docs/what-this-actually-does.md:54`; CHANGELOG; both manifests, `claude/inventory.json:6`,
  `inventory-contract.sh --write`, README pin at `:130-131`. Check 57 untouched.
- C5 (no bump). Runs; `RESULTS.md`, `measured-so-far.md`.

### Measurement

OpenCode and GLM only (Claude arms have zero events). `five_module_edges`: gate cap 2 vs gate
cap 3, n=50 each; accept if fc(cap2) <= fc(cap3) and green(cap2) >= green(cap3) minus 5 points.
`contradictory_spec`: gate cap 2 with and without the exit offer, n=30; accept if the `tests_tampered`
rate in the exit arm is under half the no-exit arm and fc(exit arm) = 0.

### Risks and revert

- Report-release is a self-report escape (SV#1). Bounded: it must quote the failing labels, the
  message says red, one-shot, env off. Revert the release lane, keep fields and cap 2, if any exit-arm
  run files a report and says DONE over red, or tampering does not halve.
- Gap 1: the live hook is never exercised in the benchmark (the vstack arm's workdir has no trust
  entry; HOME isolation loses auth). Check 14 is the only live proof.
- Gap 2: the base rate is unknown until C3; below 30% the item is unmeasurable here and the fallback
  is a weaker OpenCode model, not more samples.

## Items 4 and 5: the instruction file and subagent contracts (ZEEP-B, planner on Fable 5.1, read-only)

Verdict: ISSUES (three named gaps).

### Where the draft is wrong for this tree

- `recommendations-draft.md:55` says CLAUDE.md is "held to 8704 bytes": `claude/CLAUDE.md` is 4332 B and no
  verify.sh check caps it.
- `:69` says subagents inherit the digest: the digest is `UserPromptSubmit` output (`settings.json:84-93`)
  and that event does not fire inside an `Agent` call. Whether subagents load `~/.claude/CLAUDE.md` is
  unmeasured here (`docs/config-precedence.md:18` probes the main session only). Half of item 5's
  "today" is false, the other half unproven.
- "Nothing unconditional at session start" contradicts the tree's own evidence: the SessionStart SKILLS
  routing table (`inject-session-context.sh:201-230`) is what fixed "skills did not fire". It stays.
- In the showcase vstack arm CLAUDE.md is not memory at all; it rides as `policy.md` appended to
  SessionStart (`hook:308-315`, `run.sh:46-52`).

### Disposition of `claude/CLAUDE.md`

| lines | paragraph | disposition | evidence |
|---|---|---|---|
| 3-4 | NEVER ASK, confirm destructive | keep, two lines | `do-harnesses-help.md:82` (consent text 0 to 17.1%); guard-destructive.sh is the deterministic half |
| 6 | verify before done | keep one line, drop the Conductor sentence | zero false completions across every arm, so no measured effect; verify-gate.sh is the mechanism |
| 8-22 | OUTPUT STYLE and REGISTER (1.2 KB) | keep the banned-word list, delete the rationale prose | anti-pattern shape is the one positive slice (model-routing 10 VERIFIED); no local measurement; operator's call |
| 24-28 | USE THE STACK | delete | 60 of 60 review runs invoked no skill with it present (`measured-so-far.md:52-54`); the routing table did the work |
| 30-33 | MODEL ROUTING | delete | agent frontmatter pins models (`planner.md:6`); no hook enforces the self-orchestration clause |
| 35-37 | DISPATCH PRE-AUTHORIZED | delete | `config-precedence.md:40`: unverified, "do not cite as mechanism" |
| 39-43 | FAN OUT THROUGH swarm | cut to one line | duplicates `swarm/SKILL.md:12-28`; the delegate-swarm counter enforces it (`skill-mandate.sh:211`) |
| 45-47 | ISOLATE WRITERS | delete | already `SKILL.md:56-64`; the clobber evidence supports the rule, not this copy |
| 49-52 | NAME THE AGENT | cut to one line | the Stop mandate enforces it (`skill-mandate.sh:683-688`); roster in SessionStart `:204` |
| 54-58 | DOGFOOD | move to the vstack repo-root CLAUDE.md | vstack-specific, shipped to every project; no evidence |
| 60-63 | Compact instructions | keep | none |

Digest (`inject-session-context.sh:181-183`): TOKENS delete (no evidence; measurable via `tokens_in`);
DELEGATE delete (vstack spawned 0 of 10 with it present, RESULTS:99-102); FANOUT delete (same); GRILL
(`:130-134`) and MANDATE (`:176-179`) keep, already conditional. SessionStart `:189-200`
TOKENS/DELEGATE/AUTONOMY/PLAN MODE: delete (about 700 B), keep the SKILLS block.

### Contracts

`swarm/SKILL.md:75-77` becomes a required brief template: `TASK`, `FILES` (whole files, one owner),
`ACCEPT` (command plus expected output), `REPORT` (under 200 words, PASS/ISSUES/BLOCKED, lines typed
`FACT:`/`FAIL:`/`PATCH_SUMMARY:` per multi-agent-overhead 7 VERIFIED, with the caveat that the source is
QA, not coding). Callee side: `worker.md:22` and `explorer.md` add "a brief lacking FILES or ACCEPT
returns BLOCKED naming the field". Agents lose nothing else; keep the call-sign header (the naming
mandate needs it) and the ENVIRONMENT.ref pointer in all nine files (inventory `floor: 9`,
`floor_reason:259`). Model-routing 12 VERIFIED predicts gain only on the Haiku-pinned pair. "Not
forwarding the lead's file" is unimplementable: no mechanism withholds memory from a subagent (gap 1).

### Commits

1. `claude/CLAUDE.md` trim (the policy.md check at `verify.sh:2397` follows by cmp; check 7 at `:282`
   tolerates fewer tokens).
2. `inject-session-context.sh:181-183,189-200`; check 18 (`verify.sh:1113`) has a 128 B floor on the
   digest that goes red at 0 B: re-probe with a 400-char prompt plus a seeded
   `$TMPDIR/vstack-mandate-*.unslop` and require at least 128 there, at most 512 always; row 18
   (`gate-falsifiability.sh:849`) re-anchors its padding on `GRILL:`; add row 18e stubbing the grill
   branch; 18c unchanged. README:328 context figure re-derived.
3. `swarm/SKILL.md`, `worker.md`, `explorer.md`.
4. 1.70.0: both manifests, `claude/inventory.json` (plus `--print-digest`, `releasing-this-repo.md:37`),
   README:130-131 pin, CHANGELOG. Fix stale `inventory.json:317` (CLAUDE.md no longer names /goo or
   /commit; already false today).

### Measurement

Arms `gstack` and `vstack` at the 1.69.0 tag and at HEAD (paired, `run.sh`, JOBS=2); fixtures
`mean_intdiv`, `multi_module`, `multi_module_tested`; n=10 each. Accept: 30 of 30 green per arm, 0
false completions, spawned 0, cost(HEAD) at most 1.1x cost(1.69.0), `tokens_in + cache_read` down by
at least 60 tokens times mean turns (about 300 B per turn). Pre-flight: on this machine the overlay hook
mutes itself when `~/.claude` is live (`hook:66-69`); confirm `run.sh:10-16` isolation or set
`VSTACK_DUPE_SUPPRESS=0` (gap 2). Item 5 tokens: the fixtures never spawn, so per-subagent tokens come
from `~/.claude/projects/*.jsonl` Agent tool_result usage over one week before and after; item 7's
ledger is the prerequisite (gap 3).

### Risks and revert

Any arm losing green, a false completion above 0, or the skill-fire rate in operator sessions
(`tests/auto-trigger.sh`) dropping reverts commits 1 and 2 by tag. The style trim is unmeasurable;
revert on operator veto only. Open decisions: the REGISTER paragraph (keep the list or delete all) and
whether to run the subagent-memory marker probe before commit 3.

## Items 6 and 7 and expiration tests (ZEEP-C, planner on Fable 5.1, read-only)

Verdict: ISSUES (plan complete; three decisions named at the end).

### Per-feature ledger

| mechanism | where | justified by today |
|---|---|---|
| agent-naming block | `claude/hooks/skill-mandate.sh:671-689` | nothing |
| swarm-first block | `:693-710` | nothing |
| serial-tail block | `:743-760` | nothing (motivating sessions at `:621-623`, no harness) |
| breadth block (retired) | `:730-741` | measurement, `tests/evals/showcase/runs/20260903-022953.55428.jsonl` |
| delegation log row | `:764-816` | check 40 (`verify.sh:2866`), row 40 (`gate-falsifiability.sh:1086`): mechanism proven, effect none |
| dispatch counter and replay row | `dispatch-counter.sh:360-403` | check 44 (`verify.sh:3027`) |
| per-prompt digest and MANDATE line | `inject-session-context.sh:91,159-178` | routing ablation 9 of 9 vs 7 of 9 (`docs/what-this-actually-does.md:43`) |
| verify-gate, guard, routing, trust | `what-this-actually-does.md:53-56` | mechanism only |
| goal-gate, format, failure-diagnose, compat-canary | `claude/settings.json` events; `hooks.json:17-28` | nothing |

Record location: `claude/inventory.json` gains `components.hooks.mechanisms[]` with `{id, file, event,
blocking, justified_by: {kind: measurement | literature | none, file, run_id | entry, measured_head,
decide_by}}`. Precedent: `verification.required[1].cost_model` (`seconds_per_row`,
`checks_at_measurement`, `measured_from_run`) read by check 58 at `verify.sh:4265-4271`, falsified by
58b and 58c (`gate-falsifiability.sh:678,771`). Prose stays in `what-this-actually-does.md` section 2,
whose "third column mandatory" rule (`inventory.json:842-860`) has no enforcer today.

New check 65: every Stop, PostToolUse and PreToolUse command in `settings.json` and `hooks.json` maps
to a mechanism entry; every entry has `justified_by`; every mechanism id has a row in section 1 or 2
with a non-empty third column.

### Admission verification

Entry points: PostToolUse `Agent|Task` (`settings.json:45-49`) is the only place subagent output
crosses into the lead; `dispatch-counter.sh:271` already parses `tool_response` and sizes it. `/team`
demands "command and its output" (`commands/team.md:82,103`) and swarm demands PASS/ISSUES/BLOCKED plus
`file:line` or command output (`swarm/SKILL.md:77-79`), both as prose to the model. No SubagentStop is
wired.

Check: in `dispatch-counter.sh`, after the existing jq pass, stringify `tool_response`, set `verdict`
(a PASS/ISSUES/BLOCKED/DONE token present) and `has_evidence` (any `path:NN`, a `$ ` command line, or
`exit [0-9]`). Add both to the replay row. When `verdict && !has_evidence`, emit
`hookSpecificOutput.additionalContext`: "UNVERIFIED: subagent verdict without command output or
file:line; re-run its test or grep before using it." Shape-agnostic on purpose: `tool_response`
internals are unconfirmed (`dispatch-counter.sh:95-108`). Measurement: rows with `verdict &&
!has_evidence` per 100 rows in `~/.claude/vstack-replay-log.jsonl`.

### Expiration tests (check 65, continued)

- `kind: literature`: the cited `literature/*.verification.md` row must read VERIFIED. Today
  competitor-claims 10 is MISREAD (`competitor-claims.verification.md:16`); item 7 loses that citation.
  Item 6's citations (multi-agent-overhead 7 and 12, model-routing 6) verify.
- `kind: measurement`: `file` exists, `measured_head` is an ancestor of HEAD, and `git diff
  measured_head..HEAD -- <mechanism file>` is empty after stripping comment lines. A logic edit after
  the measurement expires it.
- `kind: none` with `blocking: true`: red once `decide_by` has passed. Naming, swarm-first and
  serial-tail get `decide_by: 2026-09-17`.
- Falsifiability rows: 65 (delete a `justified_by`), 65b (flip a cited VERIFIED to MISREAD), 65c
  (rewind a `measured_head` to before the last logic edit of `skill-mandate.sh`).

### Commits

1. Docs only: `recommendations-draft.md` item 7 drops competitor-claims 10.
2. Payload: the mechanisms ledger in `inventory.json`; `what-this-actually-does.md` section 2 rows for
   the nine unlisted mechanisms; check 65 in `verify.sh`; rows 65, 65b, 65c in
   `gate-falsifiability.sh:37` CHECKS, `files_for:261`, `label_for:365`, `break_it:479`. Version 1.70.0
   in both manifests, `inventory.json:6`, `README.md:130-131`; `tests/inventory-contract.sh --write`;
   CHANGELOG. Check `git ls-remote --tags` first.
3. Payload: admission fields and additionalContext in `dispatch-counter.sh`; widen check 44
   (`verify.sh:3027`) with a verdict-without-evidence fixture; row 44h.
4. Payload: the `settings.json:45` matcher becomes `Agent|Task|Skill`; replay row `kind: skill_load`
   with `duration_ms`; `bin/doctor --ledger` sums `duration_ms` per session by `subagent_type` or
   skill. `run.sh:167-178` rows add `session_id` so ledger and benchmark rows join.
5. Measurement: `run.sh` arm `vstack-nomandate` (`VSTACK_NO_MANDATE=1`) against `vstack` on
   `multi_module`, n=10; the result is written into each mandate's `justified_by` before `decide_by`.

### Acceptance

Check 65 green on the tree, red under 65, 65b and 65c. The check 44 fixture shows every row carrying
`verdict` and `has_evidence`. Ledger `duration_ms` sums join to `runs/*.jsonl` rows by `session_id` for
every showcase run. Each remaining mandate has `kind != none` by 2026-09-17, or is retired like breadth.

### Risks and reverts

- Check 65 reds main on a logic edit to a measured hook: intended; the revert trigger is a red older
  than one release with no measurement scheduled.
- additionalContext on every unevidenced verdict adds tokens: revert if the paired run in commit 5
  shows more than 10% cost over `vstack`.
- Decisions: (a) the `decide_by` date, (b) red or warn for `kind: none` mandates before that date, (c)
  whether ledger cost comes from benchmark rows only (the hook payload carries no cost).
