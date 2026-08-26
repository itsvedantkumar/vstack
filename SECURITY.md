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

Two hooks in this repository run code that a cloned repository controls. Both are gated on the
same record, `~/.config/agents/verify-trust`, which stores the hash you approved.

**The `Stop` gate** runs a repository's own `.claude/verify.sh`, and will not execute a gate it
has not been shown. A changed gate has to be approved again. Since 1.46.0 that approval also
covers the build manifests the gate executes through — `package.json`, `pyproject.toml` with
`uv.lock`, `Cargo.toml` with `Cargo.lock` and `build.rs` — because a generated gate runs
`npm run test`, `uv run pytest` and `cargo test`, and before 1.46.0 editing `scripts.test` was
arbitrary code at Stop time in a repository you had already trusted, with the hash never moving.

**The `PostToolUse` formatter** (`claude/hooks/format.sh`) fires on every `Edit`, `Write` and
`MultiEdit`, not only at Stop. It refuses to load a Prettier `plugins` entry from a repository
that has not been trusted: a `plugins` array in an otherwise-static `.prettierrc.json` names a
local `.js` file that Prettier `require()`s at format time, so before 1.46.0 an ordinary edit in
a freshly cloned repository executed that file. Executable Prettier config (`prettier.config.js`
and its siblings) is never loaded at all, trusted or not, because Prettier 3 has no flag that
loads such a file without also executing it.

### What this does not cover

- Any edit to a tracked manifest re-arms the confirmation, including an unrelated dependency bump.
  Hashing only the `scripts` key would be stabler but is not enforceable: the hook compares
  whole-file content at a fixed path rather than a parsed subset.
- Local path dependencies. `{path = "../x"}` under `[tool.uv.sources]`, or a path entry in
  `Cargo.toml` or `[patch]`, is recorded by path and not by content hash in either lockfile, so
  editing files under a path dependency runs new code without touching anything hashed.
- Test files and `conftest.py`. "Run the test suite" has always meant running whatever test code
  is there; that is the cost of trusting a gate at all, not a gap this closes.
- A dynamically built path (`bash "$var.sh"`) inside `verify.sh` is invisible to any static scan.
- **The gate cannot defend against the agent it gates.** Both run as the same user with the same
  filesystem access, so an agent can rewrite `.claude/verify.sh` to `exit 0` and trust it itself.
  Closing that needs the check to run somewhere the agent cannot write. The gate is a guard
  against finishing on a red tree by accident, not against an adversary sharing your uid.

Cloning a hostile repository does not run that repository's code. Trusting one does, by design,
and the boundary above is the whole of what trusting means.

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
commands; check 23 tests every row of that list across three tiers, in both directions, and
prints the live count it tested rather than one written down here. Treat it as a
seatbelt, not a cage.
