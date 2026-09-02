# Does a configuration layer change what a coding agent does?

Working folder for one question with two customers. First, make vstack functionally better: every
recommendation that survives verification becomes a change to a hook, a skill, an agent's model
setting or the instruction file, with a check that can fail. Second, a paper, once the first
customer has been served and the measurements are preregistered.

## Layout

- `literature/` one file per topic. Each was drafted by GLM 5.3 Flash through OpenCode against a
  brief that forbids unverified citations and requires the fetched URL per source. Treat every
  entry as unconfirmed until its `status` line in the table below says otherwise; a model that
  can fetch can still misread.
- `findings/` what this repository has measured itself, with pointers to the raw rows and the
  harness that produced them. These are the facts the literature has to explain or contradict.

## Literature files and their verification status

| file | topic | drafted | status |
|---|---|---|---|
| `literature/scaffold-ablation.md` | scaffold versus model on SWE-bench | GLM 5.3 Flash | unverified |
| `literature/false-completion.md` | reward hacking, overclaimed completion | GLM 5.3 Flash | unverified |
| `literature/instruction-files.md` | long instruction files, context rot | GLM 5.3 Flash | unverified |
| `literature/multi-agent-overhead.md` | when delegation pays | GLM 5.3 Flash | unverified |
| `literature/model-routing.md` | cascades and routers | GLM 5.3 Flash | unverified |
| `literature/self-verification.md` | limits of self-repair | GLM 5.3 Flash | unverified |
| `literature/benchmark-methodology.md` | error bars, contamination, preregistration | GLM 5.3 Flash | unverified |
| `literature/capability-scaling.md` | scaffold benefit versus model strength | GLM 5.3 Flash | unverified |
| `literature/competitor-claims.md` | claims audit of public Claude Code bundles | GLM 5.3 Flash | unverified |
| `literature/publishing-null.md` | venues and framing for a null result | GLM 5.3 Flash | unverified |

A file moves to `verified` when a second reader has fetched every cited source and struck the
ones that do not say what the entry claims. Until then nothing in `literature/` is quoted in the
README or the paper.

## Earlier work this folder builds on

- `../harness-value-literature-2026-08.md`, the first survey, done by hand.
- `../do-harnesses-help.md`, the question as it stood in August with the false-done harness.
- `../what-we-changed-2026-08-22.md`, what that survey changed in the tree.
- `../fake-greens-2026-08.md`, six gates that reported success without measuring, the pattern
  every check in this repository is now shaped against.
