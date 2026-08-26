# Required branch/tag protection for release enforcement

Phase 2's acceptance criteria ("a failed required job cannot produce a tag or GitHub release")
are enforced by `.github/workflows/release.yml` from inside CI, but CI enforcement alone still
lets someone with push access merge to `main` past a red `verify` run, or force-move a tag after
the fact. Neither is currently blocked at the GitHub API level: `gh api
repos/itsvedantkumar/vstack/branches/main/protection` returns 404 (no branch protection) and
`gh api repos/itsvedantkumar/vstack/rulesets` returns `[]` (no rulesets), both checked live on
2026-08-26.

**Not applied.** Two ruleset bodies are prepared in this directory; apply them with the commands
below only with explicit approval, never as part of this change.

## 1. `main` requires all four platform jobs

`.github/branch-protection-ruleset.json` — blocks non-fast-forward pushes and branch deletion,
and requires the four job-level check-runs `.github/workflows/verify.yml` produces (`verify`,
`install-linux`, `install-macos`, `install-alpine`) to report `success` for the exact commit
before it can land on `main`. `strict_required_status_checks_policy: true` means the branch must
also be up to date with `main` before the checks are considered current.

Four jobs, three unique platforms: `verify` and `install-linux` both run on `ubuntu-latest`; the
other two are `macos-latest` and the `alpine:latest` container. README.md and check 26 of
`.claude/verify.sh` assert three *documented platforms* match the three unique runner values in
`verify.yml` -- that check is unaffected by this ruleset, which requires four *job* names, not a
fourth platform. Do not read the "four" in the operator brief as license to invent a fourth
platform; the repo does not run one.

```
gh api --method POST repos/itsvedantkumar/vstack/rulesets \
  --input .github/branch-protection-ruleset.json
```

(Creation is `POST /repos/{owner}/{repo}/rulesets`. To edit an existing ruleset instead of
creating a second one, look up its id with `gh api repos/itsvedantkumar/vstack/rulesets --jq
'.[] | select(.name=="main: require the four platform jobs") | .id'` and `PUT` to
`repos/itsvedantkumar/vstack/rulesets/<id>`.)

## 2. Release tags cannot be force-moved

`.github/tag-protection-ruleset.json` — blocks `update` (force-move) on any `refs/tags/v*` ref.
Deletion is deliberately left unrestricted: `release.yml`'s `cleanup-on-failed-gate` job deletes
the candidate tag it just watched fail required checks, and release-manager's own rollback path
(cut a new version rather than force-push) also deletes a bad tag rather than moving one. Blocking
`update` and not `deletion` is what makes both of those still possible while still making the one
thing Phase 2 asks for -- "no workflow step publishes from a moving branch reference" -- true for
tags as a GitHub-enforced fact, not just a comment in `release-manager.md`.

```
gh api --method POST repos/itsvedantkumar/vstack/rulesets \
  --input .github/tag-protection-ruleset.json
```

## Verifying after applying

```
gh api repos/itsvedantkumar/vstack/rulesets --jq '.[].name'
gh api repos/itsvedantkumar/vstack/branches/main/protection 2>&1   # still 404 by design -- this repo uses rulesets, not classic branch protection
```

## What this does not cover

- Requiring a review before merge is not included. The repo currently merges directly to `main`
  per the user's own `vedant-owns-the-repos` convention; add a `pull_request` rule to the first
  ruleset if that changes.
- Neither ruleset restricts who can push a *new* tag in the first place -- that stays with repo
  push access, same as today. The gate is on what a tag can turn into (a publication), not on who
  may name a candidate.
