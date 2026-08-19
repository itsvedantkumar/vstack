# tests/

## What this proves

This setup's core property is that Claude Code skills fire on the situation
described in a prompt, without a slash command. That mechanism is the SKILLS
routing block in `claude/hooks/inject-session-context.sh` plus the
natural-language `description` field on each skill. It has already broken
silently once (0 of 4 test prompts fired a skill) with nothing to catch the
regression.

`auto-trigger.sh` is a black-box regression test for that property. It runs
`claude -p "<prompt>"` headlessly for four prompts that should each cause a
specific skill to auto-fire, inspects the `stream-json` transcript for
`Skill` tool_use blocks, and reports PASS/FAIL per case.

## Run the tests

```bash
tests/auto-trigger.sh
```

The script requires `claude` on `PATH`, `jq`, and an authenticated session
(`claude auth status` reporting `loggedIn: true`). If any is missing, the
script prints `SKIP: ...` and exits 0. That is a valid, non-failing outcome,
not a bug in the test.

Each case runs in its own `mktemp -d` under `/tmp` (never this repo), so
nothing here pollutes the working tree the model sees.

## Why this cannot run in GitHub Actions

1. **Headless auth.** `claude -p` needs a logged-in session
   (`claude auth status`). CI runners have no browser or OAuth flow and no
   long-lived credential this test can use, so `claude auth status` will
   never report `loggedIn: true` there. The script detects this and skips
   rather than failing the build.
2. **It would bill tokens.** Every case makes real API calls, up to 3 turns
   each across 4 cases. Running this on every push or pull request in CI
   would spend real money on a check that mostly guards against
   skill-routing regressions. Those regressions are infrequent. Run the
   script by hand instead, or schedule it on a machine that already has an
   authenticated session: local dev, or a scheduled job outside CI.

Run it by hand after touching `inject-session-context.sh`, a skill's
`description` frontmatter, or the skill-routing logic.

## Add a case

Edit `tests/auto-trigger.sh`:

1. If the prompt needs a file to react to, such as code to review, add a
   `setup_<name>()` function that writes it into `$1`, the case's temp dir.
2. Add a `run_case "name" "prompt" "expected_regex" "setup_fn_or_empty"` call
   in the "Test cases" section near the bottom. `expected_regex` is an
   extended regex matched against the set of skills that fired. One match
   is enough, so use `a|b` to accept either of two acceptable skills.
3. Run the script and confirm the new case prints `PASS`.

Write prompts the way a person would actually phrase the ask. Do not name
the skill directly. The point is to prove routing works from natural
language, not from an exact keyword match.
