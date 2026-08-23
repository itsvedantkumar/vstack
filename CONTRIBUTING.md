# Contributing

The bar here is not code style, it is evidence. A change is ready when a command demonstrates it
works and another command demonstrates the first one could have failed.

## Before you open a pull request

```bash
./.claude/verify.sh               # must end VERIFIED, with 0 skipped
./tests/gate-falsifiability.sh    # must end FALSIFIABLE, tree unchanged
./tests/install-matrix.sh         # every environment lane
shellcheck -S warning <files>     # check 29 runs this over every shebang script
```

Run gates unpiped and read the exit code on its own line. `./verify.sh | tail` has produced a
false green here more than once, and `cmd | grep -q` under `set -o pipefail` returns 141 on a
match, which has inverted the logic of three checks so far.

Stage new files with `git add` before running the gates. Untracked files are invisible to the
secret scanners.

## Adding a check

Every check in `.claude/verify.sh` needs a matching row in `tests/gate-falsifiability.sh` that
breaks the repository in the specific way the check exists to catch. Check 16 fails if one is
missing, so this is enforced rather than requested.

Watch the check go red under its own mutation before you make it green. A check nobody has seen
fail cannot be told apart from a check that always passes, and this repository has shipped five
of those. Two of them passed because the mutation silently landed nowhere.

Adding a check changes the total, which changes counts that check 12 reads out of the README and
the manifests. Those edits belong in the same commit, because the tree is red in between.

## Adding a skill

Descriptions are the dispatch mechanism, not documentation. Check 3 fails a description over 200
characters because past that it is truncated in the listing and the skill silently stops being
selected. Write to the cap rather than trimming to it afterwards.

Add a case to `tests/auto-trigger.sh` and run it. Dispatch is a model decision, so the suite
retries up to three times and reports which attempt landed. If a skill will not fire, the
description is wrong; measure that rather than arguing about it.

A skill that tells the model to run something this repository does not vendor has to say so.
Check 22 enforces it.

## Ported skills

Record provenance in `claude/skills/ATTRIBUTION.md`: the source repository, its licence, the
author, and every deviation from upstream. If upstream ships something for another agent, drop
it. This bundle targets Claude Code and nothing else.

## Commit messages

Say what was broken, how you know, and what now catches it. Paste the measurement. A commit that
says "fix flaky check" is worth less than one that says which command returned 141 and why.

## Releases

Bump both manifests and write the changelog entry in the same commit as the change it describes,
then tag. Check 24 fails if the payload has moved past the tag the manifests name, or if a version
pinned in the docs is not a tag that exists.

## Conduct and formatting

[CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) applies to issues, pull requests and commit messages.
Its standard is the same one this repository applies to its own checks: a claim about someone's
work should carry the command or the `file:line` that supports it.

Editor settings are in [.editorconfig](.editorconfig) — LF, UTF-8, two spaces, final newline,
trailing whitespace stripped except in Markdown where it is a hard line break.

