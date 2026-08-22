# Security

## Reporting

Report vulnerabilities through
[GitHub's private advisory form](https://github.com/itsvedantkumar/vstack/security/advisories/new).
Do not open a public issue for anything exploitable.

Expect an acknowledgement within a few days. This is a single-maintainer project, so there is no
paid response commitment.

## What this software does to your machine

`install.sh` writes to `~/.claude/`, `~/.config/agents/`, `~/.conductor/`, and appends sentinel
blocks to your shell rc files. It merges `settings.json` and `.claude.json` rather than replacing
them, and backs up every file it touches into `~/.config/agents/backups/` before writing.
`./uninstall.sh --yes` reverses all of it; one of the install-matrix cases asserts that
user-owned keys, overrides and MCP servers survive that.

## Executing code from repositories you clone

The `Stop` hook runs a repository's own `.claude/verify.sh`. It will not execute a gate it has not
been shown: `~/.config/agents/verify-trust` records the hash you approved, and a changed gate has
to be approved again. Cloning a hostile repository does not run that repository's code.

## Credentials

Secrets live in `~/.config/agents/secrets.env` at mode 600, and the wrappers in
`~/.config/agents/bin/` load it per-invocation rather than exporting it into every shell. One of
the install-matrix cases fails if an install leaks credentials into a shell rc file.

Windows is unsupported for this reason: a filesystem without POSIX permission bits cannot enforce
the 600-mode check.

The failure-diagnose hook feeds command output back into the transcript, so it redacts nine
credential shapes first. Check 25 tests every one of them, and tests that plain errors survive
unredacted.

## Scope

Skills and commands are prose that instructs a model. They are not a sandbox and give no security
guarantee about what the model does. The destructive-command guard denies a documented list of
commands; check 23 tests all sixteen across three tiers, in both directions. Treat it as a
seatbelt, not a cage.
