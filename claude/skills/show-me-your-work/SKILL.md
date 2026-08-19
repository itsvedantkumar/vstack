---
name: show-me-your-work
description: "Use for long-running, autonomous, background, overnight or multi-phase work a human reviews after stepping away: keep an append-only TSV trail of each decision (what, why, evidence, result)."
---

# Show me your work

For work a human reviews after the fact, a decision trail lets them reconstruct what was decided, why, and on what evidence, without rerunning the work or reading the whole transcript. Keep one canonical log so the trail is consistent and a future agent can find it.

This matters most exactly where it is least likely to happen: background Bash runs, scheduled/cron tasks, launchd jobs, and unattended agent loops. Those produce output nobody watched. Without a trail there is nothing to review but the diff, and the diff never says why.

## The format

A single TSV file, one row per decision. TSV because GitHub renders it as a sortable table, `column -s$'\t' -t` and spreadsheets read it, and a row appends with one command. Cells stay single-line. Evidence is a pointer, not prose.

Copy `references/decision-log-template.tsv` (the header row) to start a clean log. Columns:

- **ts.** ISO8601 timestamp. The timeline axis.
- **phase.** The phase or workstream.
- **decision.** What was chosen or done, one line.
- **why.** The reason in plain words. If a principle drove it, say it plainly (`explored options first, this was a one-way door`), not as a jargon tag.
- **evidence.** A link or path that proves it: commit SHA, PR number, `file:line`, or an artifact, trace, or screenshot path. Never a paragraph.
- **result.** The outcome or predicate state: `tests green`, `reverted`, `pixel-diff 0`, `INCONCLUSIVE`, `open`.

An example, plain-spoken so a reviewer reads it at a glance. This is illustration only; don't copy these rows into a real log.

```
ts	phase	decision	why	evidence	result
2026-05-24T09:02:00Z	frame	counted the work first, about 100 components and roughly 75 hours	wanted to know the size before starting a long run	commit 3a9f1c2	found 5 things to sort out before starting
2026-05-24T09:40:00Z	harness	took screenshots of the old version before changing anything	so we can compare old against new and catch any visual change	scripts/snapshot.sh, baseline/	saved 120 reference screenshots
2026-05-24T11:15:00Z	widget	moved the widget styles over without changing how it looks	keep the change small and the result identical	commit 7c21e0a, pixel-diff 0	looks identical, tests pass
2026-05-24T12:30:00Z	widget	threw out a helper's work because its screenshots were blank	checked the real files instead of trusting its summary	worktree reset	reverted, tightened the instructions for next time
```

## Logging a row

Write each entry the way you'd tell a teammate what you did. Plain words, concrete actions, no AI speak or abstract jargon (the **unslop** skill applies to log text too). A reviewer should understand each row without decoding it.

Use the helper so rows stay well-formed:

```
~/.claude/skills/show-me-your-work/scripts/log.sh <logfile> <phase> <decision> <why> <evidence> <result>
```

Call it by absolute path (or `"$CLAUDE_PROJECT_DIR"/.claude/skills/... ` for a project-local copy) — a bare `scripts/log.sh` breaks the moment the working directory changes, which it does constantly in background and cron runs.

It stamps `ts`, writes the header on first use, strips stray tabs/newlines, and prefixes any cell starting with `=`, `+`, `-`, or `@` with a single quote so a reviewer opening the log in a spreadsheet doesn't trigger formula execution. A bare `printf` appending a row works too, but mind those same bytes if cells come from generated or user-supplied text.

Log decision points and checkpoints, not every action: a fork chosen, a unit completed with its verification result, a pivot or revert with its trigger, a blocker surfaced, a gate fixed. For loop runs, one row per iteration. Skip the trivial and self-evident.

**One writer per log.** If subagents are running, the parent logs on their behalf when they report back. Concurrent appends from several agents interleave unpredictably; give each agent its own `.audit/<slug>-worker-<n>.tsv` if they must log directly.

## Where it lives

By default the log is a working artifact, not committed. Keep it at `decisions.tsv` in the work dir, or `.audit/<task-slug>.tsv` when several efforts run at once, and leave it out of git. Most work doesn't need a committed trail; the local log still keeps the run honest and can be discarded after.

Commit it only when the work is ambitious enough that a reviewer needs the trail to trust the result: a large cross-language port, a multi-week migration, an unattended job that opens PRs against someone else's repo, anything where confidence has to be shown rather than assumed. A committed log renders as a table in the PR.

## Rules

- One row is one decision or checkpoint. If it doesn't fit on one line, the decision isn't crisp yet.
- Append-only. A wrong call gets a new row that supersedes it. Never edit or delete history.
- Prefer evidence produced by committed scripts over hand-made one-offs, so a reviewer can re-run it (the **principle-encode-lessons-in-structure** skill).

## Audit the log against the transcript

At the end of the run, before handing back, check the log told the truth. This run's transcript is the JSONL session file under `~/.claude/projects/<slugified-cwd>/`, where the slug is the absolute working directory with `/` and `.` replaced by `-`. Read only this project's directory and prefer the most recently modified `.jsonl`; don't glob across `~/.claude/projects/*/`, that reads unrelated private chats. Walk the log against what actually happened:

- Every row maps to a real action. Cut invented or aspirational entries.
- Each row's evidence resolves and shows what the row claims.
- A fork, pivot, or abandoned approach that shaped the work but isn't logged is a gap. Add it.
- Drop padding. If nobody would audit a row, it doesn't earn its place.

Fix the log, not the story. If the work diverged from what a row claims, the row is wrong.

## Fresh-eyes review of the trail

Before handing back, you must spawn a reviewer subagent on a **different model from the one that did the work**. Self-review is not a substitute; the point is eyes you cannot bring yourself.

```
Agent(subagent_type: "code-reviewer", model: 'sonnet' | 'haiku' | 'opus' | 'fable')
```

Pick a model slug different from the one running this session. `claude-opus-5` work → review with `claude-sonnet-5`; `claude-fable-5` work → review with `claude-opus-5`; cheap mechanical runs → `claude-haiku-4-5`.

**Be honest about what this buys.** In Claude Code every model is Anthropic's, so this is a different model in the same family — not the cross-vendor independence the method was originally designed around. Shared training lineage means shared blind spots: a reasoning error both models find natural will survive the review. Treat a clean review as "no obvious flags from a second pass," not as independent confirmation. Where a decision is genuinely one-way or expensive to unwind, get a human or another vendor's model on it.

Give the reviewer the log path and the transcript path. It reads them and flags what the user should pay attention to. Not a redo of the work, a scan for what's suboptimal or risky:

- Decisions logged with weak or absent evidence.
- Verification steps skipped or claimed without proof in the transcript.
- Choices that look risky in hindsight (premature, scope-creeping, papering over a symptom).
- Gaps the user would otherwise miss on a casual skim.

Every reply for a run that produced a trail ends with an "Attention" section. Lead with the reviewer's model on its own line (`reviewed by <model>`), then list each flag pointing to specific rows or moments. "No flags" is a valid value; the model name is not. The self-audit asks if the log told the truth; this asks what the user should still scrutinize even when it did.

## Reviewing the trail

Read top to bottom, follow the evidence pointers, spot-check. GitHub renders a committed TSV as a table; `column -s$'\t' -t decisions.tsv` renders it in a terminal. A row whose evidence doesn't resolve, or whose result is unverified, is the audit catching a gap.

## Composing this skill

Other skills route their audit trail here instead of inventing one. Reference it by name and let it own the format; don't restate the columns.
