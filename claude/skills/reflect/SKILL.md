---
name: reflect
description: Use after a session where you were corrected, hit dead ends before finding the path, or worked out a workflow worth keeping — mines the transcript and turns each lesson into a concrete skill edit.
---

# Reflect

Mine the current conversation for durable learnings, then route each one into a skill edit. The output is edits to skills, not notes.

## When this fires

- The user said "reflect".
- The user corrected the approach mid-task — especially a correction they have made before.
- A complex task (5+ tool calls) just landed cleanly and the recipe is worth keeping.
- Dead ends were hit, the working path was found, and the path generalizes.
- A non-trivial workflow emerged that isn't captured anywhere.

Skip when the conversation is trivial, off-topic, or already covered by a skill that was followed correctly. One-offs are not learnings.

## The highest-value finding shape

A correction the user has already given in previous sessions, and is giving again, is worth more than any novel insight in the transcript. Repetition is the signal: it means the existing encoding failed.

The specific failure mode to watch for is **a rule that already lives in `~/.claude/CLAUDE.md` and still gets violated.** Adding a sixth restatement of it to a seventh file is not a fix; it is the thing that already didn't work. When a finding lands on an already-documented rule, do not accept a prose edit. Route it to a mechanism — a hook, a skill description that actually fires, a verification skill, a lint rule, a script — or send it to Backlog. This is what the **principle-encode-lessons-in-structure** skill is for, and step 4 enforces it.

## Process

### 1. Locate the active transcript

Claude Code writes transcripts to `~/.claude/projects/<slug>/<sessionId>.jsonl`, one JSON object per line. The slug is the absolute cwd with every non-alphanumeric character replaced by `-` (so `/Users/you/proj` → `-Users-you-proj`).

Glob **only that one directory.** Do not glob `~/.claude/projects/*/` — that crosses project boundaries and reads unrelated private sessions.

Most `.jsonl` files in a busy project directory are subagent sidechains, not parent sessions. Depending on the Claude Code version, sidechain turns either live in their own file or are interleaved into the parent's file; either way they are marked with `isSidechain: true` on the record. **Reflect wants the parent session** — the one containing the user's actual prompts and your replies.

```bash
DIR="$HOME/.claude/projects/$(pwd | sed 's/[^a-zA-Z0-9]/-/g')" python3 - <<'PY'
import json, os, glob, re
STRIP = re.compile(r"(?s)<system_instruction>.*?</system_instruction>|<system-reminder>.*?</system-reminder>")
d = os.environ["DIR"]
for p in sorted(glob.glob(d + "/*.jsonl"), key=os.path.getmtime, reverse=True)[:10]:
    n = side = 0; first = ""
    for line in open(p, errors="ignore"):
        try: r = json.loads(line)
        except Exception: continue
        if r.get("type") not in ("user", "assistant"): continue
        n += 1
        if r.get("isSidechain"): side += 1; continue
        if not first and r.get("type") == "user" and not r.get("isMeta"):
            c = r.get("message", {}).get("content")
            t = " ".join(x.get("text","") for x in c if isinstance(x, dict)) if isinstance(c, list) else str(c)
            first = " ".join(STRIP.sub("", t).split())[:120]
    if n and side / n > 0.9: continue          # sidechain-only file, skip
    print(f"msgs={n:<5} {p}\n    {first}\n")
PY
```

Pick the candidate whose opening prompt matches how this conversation actually began. Do not assume it is the newest file — a subagent you spawned two minutes ago can have a fresher mtime than the session you are in. Note that harness preambles (`<system_instruction>`, Conductor wrappers, `<system-reminder>`) sit in front of the real first prompt; the script strips them, but read past them if you inspect a file by hand.

If no candidate matches, write a tight digest of the session yourself and pass that to the reviewers instead of a path. This is a legitimate fallback, not a failure — say which one you used.

### 2. Spawn three reviewers, in one message

**One message, three Agent tool calls.** Not three messages. Sequential fan-out here buys nothing and costs three round-trips; if you are writing a second message containing a second reviewer, stop and batch them.

Set `subagent_type: "general-purpose"`, `run_in_background: false`, and an explicit `model:` on each. Reviewers need MCP tools to look up context the transcript references (tickets, issues, traces, `gh` state), which is why they run as general-purpose rather than a read-only agent type; the prompt forbids file writes and the parent applies every edit.

| Lens | `model` | Prompt template |
|---|---|---|
| Judgment | `opus` (`claude-opus-5`) | `references/judgment-reviewer.md` |
| Tooling | `sonnet` (`claude-sonnet-5`) | `references/tooling-reviewer.md` |
| Divergent | `fable` (`claude-fable-5`) | `references/divergent-reviewer.md` |

**All three reviewers are Anthropic models.** The original method relied on cross-vendor diversity so that three reviewers meant three genuinely different priors. That is not available here — Claude Code is Anthropic-only. What you have instead is *lens* diversity: three deliberately different reading instructions over the same transcript. So:

- Pass each template **verbatim**, substituting only the transcript path or digest. The templates are the diversity. Blurring them into one generic "find learnings" prompt collapses three reviewers into one expensive one.
- Treat convergence between two reviewers as a modest confidence bump, not proof. Shared lineage means they can be wrong together.
- Treat what *none* of them raised as unexamined rather than absent. If a whole category of the session (cost, verification, a skill that never fired) went unmentioned by all three, that is a gap in the panel, not a clean bill.

Reviewers return findings in the Agent response body.

### 3. Synthesize

One Agent call, `subagent_type: "general-purpose"`, `model: 'opus'`, `run_in_background: false`. The synthesizer spot-verifies citations, which can require MCP access. Use `references/synthesizer.md` verbatim with each reviewer's full output inlined where marked. It returns a structured Accepted / Rejected / Backlog list.

### 4. Structural enforcement check

Sanity-check the synthesizer's Accepted list yourself. Move to Backlog anything that a hook, lint rule, script, settings flag, or runtime check would enforce more reliably than prose. Skill text is for judgment calls; mechanisms are for rules.

Apply this hardest to findings about behaviors the user has already written down and still has to repeat. See **principle-encode-lessons-in-structure**.

### 5. Apply

Present the synthesizer's full Accepted / Rejected / Backlog output to the user and **wait for explicit approval before applying anything.** The user picks the subset and may redirect routings. Skill edits change the behavior of every future session, so this is one of the few places to stop and ask rather than proceed.

Backlog items are yours to file without approval — `gh issue create` in the repo the pattern belongs to, labeled `devex`, or appended to the repo's backlog file if issues are disabled. Those are tracker submissions, not skill edits. Only the Accepted list waits.

For each approved item, follow the Routing field exactly:

- **Trivial existing-skill edit** (a bullet, a tightened sentence, a stale fact corrected): do it directly with Edit.
- **Substantive existing-skill edit** (a new section, a pattern table, more than ~10 lines): invoke the **skill-creator** skill and run its draft / test / iterate loop against the target skill.
- **`tune description: <skill path>`** (the skill exists but didn't trigger when it should have): invoke **skill-creator** and run its description-optimization loop. Descriptions must trigger on how the user actually phrases things in natural language, not on slash-command names — a description that only fires on `/name` will almost never fire.
- **`new skill via skill-creator: <kebab-name>`**: hand creation to **skill-creator**. Do not invent the shape ad hoc.

Skills live in `.claude/skills/` (project), `~/.claude/skills/` (user), and plugin paths under `~/.claude/plugins/`. Edit the copy that actually loaded in this session; if the skill is a symlink into a plugin or a synced config repo, edit the source, not the link.

Before declaring done, re-read every SKILL.md you touched and confirm the frontmatter still parses (`name` and `description` present, description under ~200 characters).

### 6. Summarize

Short list, no preamble:

- Edits applied: `<skill path>` — what changed, one line each.
- New skills created: `<skill path>` — one line each (rare).
- Backlog filed: `<issue title>` and its URL — one line each.
- Dropped: one line per rejected finding plus the synthesizer's reason.
