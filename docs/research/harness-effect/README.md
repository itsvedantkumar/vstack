# Does a configuration layer change what a coding agent does?

Working folder for one question with two customers. First, make vstack functionally better: every
recommendation that survives verification becomes a change to a hook, a skill, an agent's model
setting or the instruction file, with a check that can fail. Second, a paper, once the first
customer has been served and the measurements are preregistered.

## Layout

- [`literature/`](literature/) one file per topic. Each was drafted by GLM 5.3 Flash through OpenCode against a
  brief that forbids unverified citations and requires the fetched URL per source. Treat every
  entry as unconfirmed until its `status` line in the table below says otherwise; a model that
  can fetch can still misread.
- [`findings/`](findings/) what this repository has measured itself, with pointers to the raw rows and the
  harness that produced them ([`findings/measured-so-far.md`](findings/measured-so-far.md)), and
  the provisional change list the literature implies
  ([`findings/recommendations-draft.md`](findings/recommendations-draft.md)). These are the facts
  the literature has to explain or contradict.

## Literature files and their verification status

| file | topic | drafted | status |
|---|---|---|---|
| [`literature/scaffold-ablation.md`](literature/scaffold-ablation.md) | scaffold versus model on SWE-bench | GLM 5.3 Flash | 15 verified, 0 misread |
| [`literature/false-completion.md`](literature/false-completion.md) | reward hacking, overclaimed completion | GLM 5.3 Flash | unverified |
| [`literature/instruction-files.md`](literature/instruction-files.md) | long instruction files, context rot | GLM 5.3 Flash | unverified |
| [`literature/multi-agent-overhead.md`](literature/multi-agent-overhead.md) | when delegation pays | GLM 5.3 Flash | 16 verified, 0 misread |
| [`literature/model-routing.md`](literature/model-routing.md) | cascades and routers | GLM 5.3 Flash | 13 verified, 0 misread |
| [`literature/self-verification.md`](literature/self-verification.md) | limits of self-repair | GLM 5.3 Flash | 14 verified, 1 misread |
| [`literature/benchmark-methodology.md`](literature/benchmark-methodology.md) | error bars, contamination, preregistration | GLM 5.3 Flash | 15 verified, 0 misread |
| [`literature/capability-scaling.md`](literature/capability-scaling.md) | scaffold benefit versus model strength | GLM 5.3 Flash | 12 verified, 1 misread |
| [`literature/competitor-claims.md`](literature/competitor-claims.md) | claims audit of public Claude Code bundles | GLM 5.3 Flash | 20 verified, 2 misread |
| [`literature/publishing-null.md`](literature/publishing-null.md) | venues and framing for a null result | GLM 5.3 Flash | 20 verified, 0 misread |

Each file's second reading sits beside it as `literature/<topic>.verification.md`, one row per
entry. The counts above are the second reader's verdicts, run 2026-09-03 by a separate GLM 5.3 Flash
session per file with an adversarial brief: re-fetch every source, mark VERIFIED, MISREAD or
UNREACHABLE. A misread is an overstatement or a wrong attribution, not a missing source; every
misread so far is listed with its correction at the foot of the matching verification file.
Across the eight checked files: 125 entries verified, 4 misread, 0 unreachable. Nothing in
`literature/` is quoted in the README or the paper until its file has a verification beside it.

## Earlier work this folder builds on

- `../harness-value-literature-2026-08.md`, the first survey, done by hand.
- `../do-harnesses-help.md`, the question as it stood in August with the false-done harness.
- `../what-we-changed-2026-08-22.md`, what that survey changed in the tree.
- `../fake-greens-2026-08.md`, six gates that reported success without measuring, the pattern
  every check in this repository is now shaped against.
