# Review benchmark — results

Reproduce with:

```bash
GSTACK_DIR=/path/to/gstack tests/evals/run.sh --arms none,vstack,gstack --samples 5
```

## Run of 2026-08-21

4 fixtures × 5 samples × 3 arms = 60 model calls, Claude Opus 5, one file per review.

| arm | planted defects found | false positives | skills loaded | skill invocations |
|---|---|---|---|---|
| none (built-ins only) | 11 / 15 | 0 | 16 | 0 |
| vstack | 11 / 15 | 0 | 42 | 0 |
| gstack | 10 / 15 | 0 | 70 | 0 |

**No configuration outperformed the baseline.** The one-defect gap between arms is smaller than
the run-to-run variance we saw between pilots and means nothing at this sample size.

## Why, and why the result is not the harnesses' fault

The last column is the finding. **No skill was invoked in any of the 60 runs**, under any arm.
Verified two ways: the tool-use stream contains `Bash`, `Read` and `Write` calls and no `Skill`
call at all, and the same holds with the direct-work tools denied to force the model's hand.

The reason is that a single-file defect review does not route to a skill in any of these
configurations. vstack's review path is the `code-reviewer` **subagent**, reached through the
Task tool; gstack's is the `/review` **slash command**. Neither is a skill, and neither is
reached by asking a plain question about a file.

So this measured skills that were present and idle. It is a fair measurement of the question
"does having these skills installed change an ordinary review?" — the answer is no — and an
unfair measurement of "is one of these harnesses better at reviewing code", which it does not
address.

## What this does support

- The harness is real and reproducible: same prompt, same loading mechanism for every arm,
  ground truth with planted defects and decoys, scoring by line number rather than judgement.
- Every arm reports which skills it actually loaded, so an arm that silently failed to load its
  harness is marked INVALID instead of scored as a zero.
- On this task, installing 26 or 70 extra skills changed neither recall nor precision, and cost
  context on every session to do it.

## What it does not support

Any claim that one configuration reviews code better than another. Testing that fairly means
invoking each harness's actual review pathway — vstack's `code-reviewer` subagent against
gstack's `/review` command — which is a different and larger experiment.

## Two methodology failures worth publishing alongside the numbers

Both produced results that flattered this repository, and both were caught by checking rather
than by the numbers looking wrong.

1. **The first baseline was not authenticated.** It pointed `CLAUDE_CONFIG_DIR` at an empty
   directory, which removes credentials along with the configuration. Every baseline run
   returned "Not logged in", scored zero, and produced a 5/6-to-0/6 win for vstack over a CLI
   that had never logged in. The fix is `--setting-sources=project`, which drops user-scope
   config and keeps authentication.

2. **A shell bug scored an arm at zero.** Under `set -u`, bash 3.2 — which macOS ships — aborts
   on `"${arr[@]}"` when the array is empty. That killed every vstack run in one pilot and
   printed `0/6`, which reads like a catastrophic result rather than a broken loop.

A benchmark of your own project fails in your favour by default, and it fails quietly, because
a zero in the other column looks like a finding rather than a bug. The validity columns exist
because of these two.
