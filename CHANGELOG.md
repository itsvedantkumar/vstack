# Changelog

Versions follow [semver](https://semver.org). The version lives in two manifests,
`.claude-plugin/marketplace.json` and `claude/.claude-plugin/plugin.json`, and check 13 of
`.claude/verify.sh` fails when they disagree.

## Unreleased

## 1.9.1 — 2026-08-22

**A fresh bootstrap ended on a red line.** setup-machine.sh installs claude-mem, bin/doctor has
checked that the plugin's UserPromptSubmit hooks are async for several versions, and nothing ever
set the flag. So the lane installed the plugin and then left the machine in a state its own doctor
called drift, telling the operator to re-apply something that had never been applied once.

The install-matrix doctor-stranger case could not see it. That case exercises install.sh, and the
plugin only arrives through setup-machine.sh, which only the bootstrap lane runs. It was found by
running the README quickstart verbatim into a scratch HOME, which is the point of running it
verbatim rather than reading it.

setup-machine.sh now sets the flag, idempotently: it reads first and rewrites only when the flag
is not already set, because claude-mem auto-updates rewrite hooks.json and revert it. Measured on
a scratch HOME: doctor goes from one red line and DRIFT to 23 ok, 0 red, 6 notes.

**doctor --drift deleted an unpushed release tag.** It ran a bare `git fetch` in the vstack
checkout to work out how far behind the remote it was. A bare fetch is not read-only: it does
whatever ~/.gitconfig says, and with fetch.prune and fetch.pruneTags set true it deletes every
local tag and remote-tracking branch the remote does not have. During this audit it destroyed the
v1.9.1 tag seconds after it was created, and the release check then reported ok for a version
whose tag was already gone.

Every flag is spelled out now, so ambient config cannot turn an inspection into an edit. The new
doctor-no-mutate case in the install matrix clones a real checkout, sets that config pairing
locally, plants an unpushed tag and asserts it survives. It carries three controls, because the
first version of the case bailed before reaching the fetch and passed against the unfixed doctor.

v1.9.0 is tagged and describes a payload carrying the claude-mem defect. It is left in place
rather than moved, because a tag somebody may have fetched is not a thing to rewrite. Use v1.9.1.

## 1.9.0 — 2026-08-22

An audit pass. Every finding below is a green that measured nothing, which is the fifth time
that class has shipped here, so each one leaves behind a check and a mutation row rather than
just a fix.

**Check 24 said ok over a comparison it never ran.** A version declared by the manifests but not
yet tagged has no payload to diff against, and that branch printed ok. The tagless branch one
elif below already knew better. It now skips with a reason, so the skip census can see it.

**A pinned quickstart that 404s.** The README's "pin a release" lane pinned v1.8.0, the manifests
said v1.8.0, and no such tag existed. The check compared the two strings, found them equal, and
was satisfied. Measured: HTTP 404. A pin now has to name a tag that is actually there.

**shellcheck was linting a hand-maintained list.** `git ls-files '*.sh' bin/doctor bin/vstack`
never included bin/cloudflare-mcp, a #!/bin/sh script with no .sh suffix. An unquoted expansion
appended to it made shellcheck exit 1 while the gate printed "ok shellcheck clean (29 scripts)".
Selection is by shebang now, the way check 1 already did it, and the count is 30. Row 29 mutates
that file specifically, so it proves the linter runs over everything rather than that it runs.

**The count check dropped nouns on the floor.** `want_for()` resolved eight nouns and the
extractor carried a separate grep alternation, so a claim could be extractable-but-unresolvable
or the reverse, silently either way. Both come from one list now, with a positive control that
fails if the extractor looks for a noun `want_for` cannot resolve. Adding "shell scripts"
surfaced a stale CHANGELOG claim, and CHANGELOG's current-version section is now in the scan.

**A suppression-reason rule that only lived in a comment.** Check 29's header had claimed it for
several versions while bootstrap.sh carried a naked disable=SC2086. Check 30 enforces it.

**Two files nothing pointed at.** A launchd wrapper around the doctor, which install.sh never
installed and uninstall.sh never removed, and the eval-loop driver. The wrapper is deleted; the
driver now has a real referrer in tests/README.md. Check 31 makes an unreferenced file a failure.

**An uninstall that left Conductor pinning policy.** install.sh writes ~/.conductor/settings.toml
and settings.managed.toml; uninstall.sh had no reference to conductor at all, so both survived
removal, and the managed file is the one that pins models and plan mode.

**The 141 that hid all of it.** tests/gate-falsifiability.sh probed for a check's skip with
`verify.sh | grep -q`. Under `set -o pipefail` grep -q exits on the first match, verify dies of
SIGPIPE, and the pipeline returns 141, which reads as "did not skip". Measured: rc=141 with
pipefail, rc=0 without. Four sites now capture first and grep a here-string.

The gate is 33 checks. Two of the new ones defeated themselves before they worked: naming a file
in the check that hunts unnamed files gives it a referrer, and so does naming the probe in the
mutation row.

## 1.8.0 — 2026-08-22

**Two skill routings are mandatory now, not merely instructed.** Everything vstack did to route
skills was instruction: the SessionStart digest spells out "any prose you write -> unslop", and
descriptions carry their own triggers. `auto-trigger.sh` measures that landing on 12 cases, which
is a weaker claim than "always". `claude/hooks/skill-mandate.sh` runs on Stop, reads the
transcript for what actually happened, and blocks the turn when a rule went unmet. Writing
`.md` requires `unslop`; writing `.ts` requires `typescript-best-practices`. Two rules, not
twenty: the bar for a third is that the situation is decidable from a tool call rather than from
judgement. It blocks at most twice a session and `VSTACK_NO_MANDATE=1` turns it off.

**Windows is gone.** It had been green through Git Bash for three commits, but `secrets.env` is
protected by a 600-mode check and a filesystem without POSIX permission bits cannot enforce it.
The lane could be made to pass; it could not be made to be true. Check 26 now requires the runner
names in CI and the platform names in the README to be the same set, in both directions.

**The README says outright that this is for Claude Code and nothing else.** Not Cursor, not
Codex, not a local model behind a compatibility shim. Every mechanism here is Claude Code's own
and there is no adapter layer.

**shellcheck is a gate.** This bundle is shell scripts and almost nothing else. Warning level,
and where a warning is wrong the suppression carries its reason on the line above. It found a
pattern in the destructive guard that could never match, a variable in `doctor` computed for a
check nobody ever wrote, and two dead assignments.

**doctor checks the MCP lane, and that check immediately found that the lane never ran.** The
merge required `~/.claude.json` to already exist, which is never true on a machine that has not
started Claude Code yet — exactly the machine running the installer. A first install printed
"run claude once, then re-run this", so every stranger who followed the README once, as
instructed, finished with no MCP servers at all while the README said they ship. The file is
created when absent now.

## 1.8.0 (earlier entries) — 2026-08-21

A fourth external audit found four ways this bundle destroyed configuration it did not own. All
four are fixed, each with a test that fails without the fix.

**Conductor managed policy was overwritten with no backup.** `settings.managed.toml` is always
replaced by design — a managed layer the installer leaves alone is just a second preferences
file — but it was the one file replaced *unrecoverably*. Anyone already using Conductor managed
settings lost machine-wide policy on first install with nothing to restore from. It is backed up
now, and uninstall puts it back.

**Uninstall left a broken install rather than no install.** A fresh install followed by a fresh
uninstall left six hook commands pointing at scripts that had just been deleted, plus vstack's
model policy and all seventeen skillOverrides still in force. It now unpicks its own entries
from `settings.json` by exact value — a hook whose command runs a script from vstack's hooks
directory, an override whose value still matches what vstack shipped, a top-level key the user
has not edited — and leaves everything else. It also removes the trust store and its own shell
blocks.

**Overlay deleted settings the target repository owned.** It removed every key vstack ships that
is not on the project allowlist, on the theory that it was cleaning up its own past overlays. It
has no way to know that: a repo that independently set `enabledPlugins`, `theme` or
`forceLoginMethod` lost all three, because the deletion keyed on vstack's vocabulary rather than
on provenance. It writes the allowlisted keys and leaves the rest alone.

**Two smaller ones.** `deploy-auto.sh` continued in the caller's directory after a failed `cd`,
so a stale path could deploy whatever project the shell was sitting in. And the hook merge used
the config path as a regular expression, so a home directory containing `[ ] ( ) + .` never
matched its own previous hooks and every reinstall appended another copy.

**The gate was asserting one of these defects as correct.** Check 17 demanded that a `theme` key
be *absent* after an overlay, which is what made the overlay delete it. "Ships nothing personal"
is a claim about what gets written. It had been implemented as a claim about what survives, and
those are different. The check now asserts the target's keys are still there, and the
falsifiability row arming it mutates the behaviour rather than the allowlist.

**Credentials in the failure tail.** `PostToolUseFailure` re-injects the tail of a failed command
as context, so whatever that command printed stays in the conversation permanently. Measured
against nine real credential shapes, the redactor guarding that path masked two. It knew
`NAME=value` and a list of token prefixes. JSON, YAML, HTTP headers, `key = value` with spaces,
and URL userinfo all went through verbatim, which is most of what a failing command actually
prints. No check had ever handed the hook a secret, so nothing could see it. Check 25 does that
now, through the real hook, and it also asserts an ordinary error line still comes back intact.

**A gate that skipped everything reported success.** The template in `create-verification-skill`
is npm-shaped. In a Go, Rust or Python repo every check it emits printed `skip` and the script
exited 0, so `VERIFIED` meant nothing had run. It refuses to pass now until at least one check
has actually executed.

**Silent merge failures.** All three `settings.json` and MCP merges wrote with
`jq -e . "$tmp" && cat "$tmp" > "$dest"` and then announced "merged" no matter what happened.
When the merge produced nothing usable, the destination kept its old contents and the install
still exited 0. A merge that did not happen looked exactly like one that did. Failure is named
now, points at the backup, and reaches the exit code. A hard abort mid-install says the same
thing instead of leaving a raw `jq` error as the last word.

**The scorer could zero its own denominator.** In the review benchmark, a scoring failure returned
`planted: 0` alongside `hits: 0`, so an arm whose scorer crashed on every fixture finished at 0/0.
That reads as "there was nothing to find" rather than "the measurement broke". The denominator
comes from ground truth regardless now, and the row is marked INVALID.

**doctor told a clean install it was broken.** It mixed what vstack installs with what the
operator happens to have: their Claude plan, their `~/Projects` layout, their optional plugins.
On a fresh machine eight checks went red at once and no reinstall could clear one of them. Those
are notes now, and what vstack ships still fails hard. The repo-coverage scan also printed a tick
after scanning zero repositories, and `claude auth status` returning `loggedIn: false` was read as
"may be billing API credits" on a machine that had never made a request.

**The trust boundary was vstack-shaped.** `vstack trust` hashed `.claude/verify.sh` plus a
hardcoded list of this repo's four root scripts. Any other repository's gate, one calling
`./scripts/ci.sh`, had its entry point pinned while the code it executes floated free. That list
is read out of `verify.sh` itself now. A path the script builds at runtime is still invisible,
and the comment where the boundary is drawn says so rather than implying otherwise.

**The falsifiability suite could pass over a broken repo.** A crashed row once left its mutation
on disk. The next run backed that file up as its own baseline, restored the break, and printed
FALSIFIABLE. Every row asserts "the gate goes red when I break this", and a row already red
before its mutation passes for free. The suite refuses to start now unless the gate is green.

## 1.7.0 — 2026-08-21

**The reviewer stops padding short diffs.** `code-reviewer.md` listed "naming, dead code,
missing tests, style" as things to report and ran a TypeScript hard-check list — no `any`, no
`console.log` — against whatever language it was handed. On a small Python change it duly
produced typing nits and "no tests here", which crowds out the finding that matters. Findings
are proportional to the change now, "no findings" is a complete review, and the hard checks only
apply where the language has them.

Found by benchmark rather than by opinion: a plain review request kept beating the harness on
precision, and the reason was in the reviewer's own instructions.

**A SWE-bench Lite harness** at `tests/evals/swebench/`. Real repositories, real bug reports,
scored by the project's own FAIL_TO_PASS tests — SWE-bench's criterion, unchanged. The agent
gets the problem statement and the repo, never the tests, the golden patch or the hints field.
Instances whose environment will not build, or whose tests already pass, are excluded before any
arm runs rather than counted as failures.

## 1.6.0 — 2026-08-21

**A review benchmark, and its result: no difference.** `tests/evals/` sends an identical prompt
under three arms — Claude Code's built-ins alone, plus vstack's skills, plus gstack's — against
fixtures with planted defects and decoys that look suspicious and are correct. Every arm loads
skills the same way, so the only variable is which skills are present. 60 model calls returned
11/15, 11/15 and 10/15 with zero false positives each. No configuration beat the baseline.

The explanation is in the validity column: zero skill invocations across all sixty runs. A
single-file defect review does not route to a skill in any of these harnesses — vstack reviews
through a subagent, gstack through a slash command — so this measured skills that were present
and idle. `tests/evals/RESULTS.md` publishes the numbers, the reason, and two methodology
failures that both flattered this repository before being caught.

**The deploy tier is opt-in.** `setup-machine.sh` installed vercel and wrangler by default,
which made one author's deployment stack look like a requirement of the product. It is behind
`--with-deploy` now, and the default install is smaller.

**`bin/cloudflare-mcp` explains itself instead of crashing.** It points at a server this repo
does not vendor, so on anyone else's machine it died with a raw "Cannot find module" that read
like vstack was broken. It now says what is missing, what to set, and exits cleanly.

## 1.5.0 — 2026-08-20

A second external review, of the improvements rather than the bugs. Its headline finding was
that the cloud lane's central promise was inert, and it was right.

**The Stop gate never ran in a cloud sandbox.** `overlay.sh` installs `.claude/verify.sh` and
wires the hook, but `verify-gate.sh` refuses to execute a repo's gate without a machine-local
trust entry — and a fresh sandbox has none. Installed, wired, silently skipping on every Stop,
in the one lane that exists for cloud work. The sandbox setup line now runs `vstack trust`.
Local protection is unchanged: an untrusted repo cloned to your laptop still runs nothing until
you type it yourself.

**Credentials are no longer exported into your shells.** `install.sh` sourced `secrets.env` into
`.zshenv` with `set -a`, and the bash lane extended that to `.bashrc` and `.profile`. One token
reached every child process of every shell: every script in every repo, every package
postinstall. Every wrapper in `bin/` already loads what it needs. The installer now removes the
line it previously wrote, and leaves any other spelling alone.

**A destructive-command guard, armed by default.** vstack had no pre-execution interception at
all, which is a strange gap for a setup that recommends `--bypass-permissions` — bypassing
permissions is exactly what removes the prompt that would catch `rm -rf /`. Adapted from
gstack's `careful` skill (MIT, Garry Tan) with two differences: it is always armed rather than
opt-in per session, and its decisions are tested. Sixteen commands across deny, ask and allow,
plus a stripped-environment run.

**The pinned bootstrap worked for branches and not tags** — `archive/refs/heads/$REF` 404s for
`VSTACK_REF=v1.4.0`, the exact value the README tells people to pin. And a no-git install could
not be converted once git returned, which was the recovery that path itself recommends. It now
marks its own tarball installs, converts them by moving aside rather than deleting, and refuses
outright to touch a directory it did not create.

**Skills stopped pointing at skills that are not here.** Six `superpowers:` references across
three skills instructed the model to invoke tooling this port does not vendor. Check 7 could not
see them — its token pattern skips the namespace prefix.

**First contact leads with the narrow thing.** The plugin lane is the headline now, with an
invitation to stop after thirty seconds. The workstation setup follows, labelled as one person's
whole environment, with the pinned and readable path before the unpinned one-liner. The plugin
lane also stopped mandating a four-skill chain for every change, which was operating policy in
the one profile whose job is stripping operating policy.

**New checks.** 22 extended to cover skills as well as scripts. 23 tests the guard's decisions.
24 fails when the payload moves ahead of the version the manifests declare — which it caught on
its first run, and which is why this release exists.

## 1.4.0 — 2026-08-20

An external adversarial audit of 1.3.0 by a different model returned twelve findings and a
NO-GO. Seven were reproducible; all seven were real, and two of them were bugs introduced by
the audit that shipped 1.3.0. This release fixes every one.

**Three ways a user could lose configuration they owned.**

- Uninstalling with `CLAUDE_CONFIG_DIR` outside `$HOME` deleted the live `CLAUDE.md` instead of
  restoring it. `install.sh` records those paths under `files_abs/` because they have no
  home-relative form, and `uninstall.sh` never read that directory — it treated it as a legacy
  flat name and then classified the real external files as removable.
- Installing over a lived-in config destroyed the user's hooks and `skillOverrides`, because the
  merge replaced both maps wholesale. Ownership decides now: a hook command pointing into this
  install's hooks directory is vstack's to rebuild, anything else is the user's to keep, and
  overrides merge with vstack winning only on collision.
- Uninstalling under a home path containing a space removed the skills and left every hook,
  command, agent and wrapper in place while printing "restore complete". The removal lists
  joined absolute paths with spaces; they are newline-delimited now.

**The no-jq install was inert.** It reported success and wired every hook to
`$CLAUDE_PROJECT_DIR/.claude/hooks/...`, which does not exist at user scope — exit 127 on every
session start, stop and tool failure, on exactly the sandboxes that path exists to serve. Hook
paths are rewritten to the real config dir, and the matrix now executes the configured command
rather than checking the files were copied.

**The headline bootstrap required git before it could install git.** On a fresh Mac git arrives
with the Xcode command line tools, the prerequisite it claims to remove. It falls back to the
source tarball using curl and tar, states that the result is not a git checkout and what that
costs, and names the install command per platform when it has neither. It also hard-reset a
dirty checkout, silently discarding tracked edits; it refuses now unless `VSTACK_FORCE=1`.

**Backups could overwrite each other.** Directories are named to the second and were created
with `mkdir -p`, so two installs in the same second shared one and the second overwrote the
first's only copy of the user's files.

**`setup-machine.sh --check` exited 0 with the Claude CLI missing**, so bootstrap carried on and
modified config and shell startup files for an agent that could not run.

**Upstream MIT notices are vendored.** MIT requires the copyright and permission notice travel
with the work; neither obra/superpowers nor ehmo/platform-design-skills had one here. Both are
in `LICENSE.mit-upstream`, fetched from source. The badge reads MIT + Apache-2.0.

**New: check 22** — a skill may reference tooling this port does not vendor, but it has to say
so in the file doing the referencing. It immediately found an instance the audit missed:
brainstorming's visual companion told the model to run three scripts that are not here.

**CI covers the last unproven lane.** The plugin marketplace case ran only in jobs without the
Claude CLI, so it skipped everywhere while every check stayed green. It runs for real now, and
the job fails if it regresses to skipping.

Two meta-fixes worth naming: check 11's guard against the retired notifier grepped for the word
and fired on the code that removes it, and check 11's falsifiability probe had silently stopped
mutating anything when the merge program was reindented — a mutation that lands nowhere reports
a check as unfalsifiable while proving nothing about it.

## 1.3.0 — 2026-08-20

A pre-launch audit against two claims: that the repo and an installed machine agree both
ways, and that a stranger with none of this machine's context can install any lane and get a
working setup. The first largely held. The second did not, and most of this release is what
that turned up.

**Installs where Claude Code actually looks.** `install.sh` hardcoded `~/.claude`, but Claude
Code reads `$CLAUDE_CONFIG_DIR` when it is set. Anyone with it pointed elsewhere — containers,
VMs, separate profiles — got all 26 skills and every hook written into a directory Claude Code
never opens, with hook paths baked to match, and a success message. `install.sh`, `uninstall.sh`
and `doctor` now resolve it, and `.claude.json` follows it.

**bash users get the environment.** The shell lane only ever wrote `.zshrc` and `.zshenv`, so a
default Debian, Ubuntu or Alpine box — every cloud VM and nearly every container — installed
cleanly and then ran without the 1h prompt cache, tool concurrency, streaming or task support.
The `claude` wrapper is zsh and cannot travel; the environment can, and now does, and the
installer says which half you are getting.

**`/bootstrap` worked on exactly one machine.** It called a script that is not in this repo and
that no lane installs; it survived locally as a pre-vstack leftover. It now uses `overlay.sh`,
and check 20 fails on any `~/.claude` or `~/.config/agents` path named in prose that no lane
creates.

**`uninstall.sh` reverses everything it installed**, not just skills, and keeps any file you
have edited since — naming what it kept rather than deleting quietly.

**The licensing was wrong.** `LICENSE` said every skill came from pstack; 8 of 26 do not. The
Apache 2.0 text for `impeccable` and `agent-browser` is vendored with a `NOTICE`, and
`ATTRIBUTION.md` now installs alongside `LICENSE.pstack`.

**CI stopped lying twice.** It had never validated the plugin manifests: the npm shim's native
binary never downloaded, every `claude plugin validate` errored, and check 19 parsed output for
a bullet character a non-TTY never prints, so it read the error as no findings. And it had never
run on macOS at all. It now runs on Linux, macOS, Windows (Git Bash) and Alpine, all gating.

**`tests/install-matrix.sh`** installs into throwaway HOMEs and asserts the resulting tree
across eleven environments, including an install over a home that already holds someone else's
skills, settings and MCP servers, and the curl and marketplace lanes against the published repo.

**`doctor --drift`** reads `settings.json` keys back and reports files under the config dir the
repo does not ship, separating "the repo dropped this and the delete never reached you" from
"you wrote this" using git history.

Also: personal residue removed from a README-linked doc, `component-registry` added to the
README roster it was missing from, and several doc counts corrected that had evaded the count
check by being spelled out as words.

- Native OS-level Bash sandboxing was evaluated end to end and rejected on live evidence:
  its write boundary is the session workspace, and this setup's daily pattern is cross-repo
  writes from Conductor workspaces (editing vstack from any workspace, `install.sh` from
  agent Bash). The full trail, including what a scratch test proved and what only a live
  trial could, is in `docs/provenance/research-2026-08.md`.
- Conductor gets the same "edit the repo, never the GUI" treatment as `~/.claude`:
  `conductor/settings.managed.toml` pins model, fast mode, and plan mode at Conductor's
  highest-precedence layer; install.sh always overwrites it and `doctor --drift` compares it.
  Plan mode is pinned off globally (per-session plan mode still works) — the rationale lives
  in the file.
- Orchestration audit closed its one gap: `swarm` and the session digest now route
  deterministic multi-stage pipelines to the native Workflow tool (proven live: 2 parallel
  agents, 1.8 s, both probes returned) instead of hand-rolled Agent chains. The homegrown
  `orchestrate` command remains deleted; the stale installed copy died with the drift fix.

## 1.2.0 — 2026-08-20

Phases 3 and 4 of the hardening plan: a researched adoption pass, the update path made
reviewable, and the incubator repo merged in and archived with a pointer.

- New skill `component-registry` (26 total): pull vetted primitives from shadcn-compatible
  registries before hand-writing UI components, with a routing line and a strict auto-trigger
  case. The survey behind it — four research agents over skill packs, design tooling,
  Conductor features, and hook patterns, with every adoption, deferral, and rejection reasoned
  — is `docs/provenance/research-2026-08.md`.
- `debugger` subagent: three-failed-fixes stop rule and anti-rationalization red flags,
  adapted from obra/superpowers systematic-debugging (MIT).
- `interrogate` and `review` now post findings as inline Conductor diff comments
  (`mcp__conductor__DiffComment`) when running in a workspace, so verdicts land in the Checks
  panel next to the merge decision. `claude/CLAUDE.md` notes that open todos block Conductor's
  merge button.
- Overlay `.conductor/settings.toml` template documents `scripts.archive`,
  `[environment_variables]`, and `.worktreeinclude`.
- `vstack update` now fetches, shows the incoming commits and the full diff of every script
  the gate executes, and asks before merging and re-recording trust hashes; `--yes` for
  automation, refusal without a terminal.
- Check 19: both plugin manifests now pass `claude plugin validate --strict` on every gate
  run, with the one known benign warning (`CLAUDE.md` at the plugin root) named and pinned.
  The falsifiability suite proves it bites by corrupting a manifest key; where the claude CLI
  is absent it skips visibly instead of failing wrongly, and CI installs the CLI so the check
  runs for real there.
- CI derives expected install counts from the repo tree instead of hardcoding them — the
  literal `25` failed the first green tree that added a skill.
- `agent-browser` skill: documents which browser tool to reach for when (claude-in-chrome vs
  headless agent-browser), the Node 24 floor, and WCAG 2a/2aa checks via axe-core.
- `ui-iterate` skill: the self-critique loop now measures instead of eyeballing — pixel-diff
  against a baseline screenshot at a fixed viewport (`--threshold 0.02`, `networkidle`).
- README: source-by-surface matrix (what local, Conductor, Remote Control, and cloud sessions
  can each read) and the two env vars that silently break Remote Control. Design history from
  the conductor-setup incubator is preserved under `docs/provenance/`.

## 1.1.0 — 2026-08-20

An audit of the verification machinery, prompted by a simple question: does the gate that says
VERIFIED actually check anything? It largely did not. Every defect below has the same shape — a
check that reported success without having run — and each fix ships with the mutation that
proves the check now bites.

### The gate was not measuring what it reported

- Three checks were wrapped in a bare `if command -v jq` with no `else`. On a host without jq
  they printed nothing at all, so `VERIFIED` meant 8 of 13 checks had run. Added a toolchain
  preflight that fails rather than skips, `else` branches everywhere, and a
  declared/ran/skipped tally that fails when the three do not add up.
- Check 11 was labelled "both lanes" and read two of three. It never opened
  `claude/hooks/hooks.json`. Its user-lane test was `grep -q "$ev" install.sh`, which matches
  prose and lets `PostToolUse` match the `PostToolUseFailure` line — deleting the whole
  `PostToolUse` block still passed. Now reads all three lanes and anchors on the object key.
- Check 12 asserted a correct number appeared *somewhere*, for two nouns in two files. It
  could not see a wrong number beside a right one, so "15 commands" shipped against a tree of
  14. Now derives 7 counts from the tree and reads every claim back, in prose and table form,
  whitespace-normalised.
- Checks 4–6 were negative greps with `2>/dev/null`, so a grep that *errored* produced empty
  output and passed. They also scanned ignored files, which had the gate red over a `.context/`
  scratch note. Now scan `git ls-files` and read grep's exit status.

### The Stop gate did not always stop anything

- `verify-gate.sh` called `/usr/bin/jq` by absolute path — a macOS path. Everywhere else the
  block decision was never emitted, so a failing `verify.sh` let the agent finish while the
  gate looked installed. Same bug in `inject-session-context.sh` was worse: it emitted **zero
  bytes** off macOS, meaning skill routing was entirely dead on Linux.
- Trust covered `.claude/verify.sh` alone, while that script executes `install.sh` and
  `overlay.sh`. A byte-identical `verify.sh` passed with swapped scripts underneath. `vstack
  trust` now records the repo-root scripts and the gate re-checks all of them.
- The per-session block counter fell back to a literal `"nosess"`, putting every such session
  on one shared file — three failures anywhere latched the gate off machine-wide.

### doctor reported passes for things it never looked at

- The coverage check returned a tick when its cutoff date failed to compute and nothing was
  scanned at all.
- `[ -d "$r/.git" ]` is false inside a git worktree, so every Conductor workspace was invisible
  to a check whose job is finding uncovered repos. `overlay.sh` had the identical bug and
  refused to run in a worktree — the one place the cloud lane most needs it.
- `--drift` never compared `claude/CLAUDE.md`, the file `install.sh` itself calls most likely
  to have been hand-edited.
- `check_item` ignored `diff`'s exit status, so an unreadable directory read as clean.

### Config that looked like a control and was not

- Deleted 38 `skillOverrides` entries covering 19 `claude-mem` skills in two spellings. Claude
  Code resolves listing mode before reading the setting for plugin-supplied skills, so none of
  them ever had any effect. Check 15 now rejects any key containing `:` or `@`.
- `overlay.sh` copied all 27 settings keys into every repo it touched, including theme,
  notification channel, login method and plugin list — into the git history of anyone who
  cloned them. Now ships 10, listed in `claude/settings.project-keys`, and strips the rest from
  repos overlaid under the old behaviour.
- The Conductor setup pin was a hardcoded SHA that had drifted behind main, so new sandboxes
  bootstrapped an old vstack. Resolves HEAD at overlay time.

### Added

- `tests/gate-falsifiability.sh` — one row per check, breaking exactly what it watches and
  requiring the gate to go red naming it. Check 16 fails when a check has no row.
- CI now installs for real on Linux and fires the hooks, because the worst bug here was
  Linux-only and invisible on the machine it was written on.
- Two negative controls in `tests/auto-trigger.sh`, which previously could not detect a skill
  that fires on everything, plus a hit-rate table so erosion shows before a case goes red.
- Check 18 bounds what the session hook injects: 305 bytes per prompt, 3,446 at session start.
- `claude/verify.sh.tmpl`, seeded into overlaid repos that have no gate of their own.

### Changed

- `default_plan_mode` is now `false`. Installing `bypassPermissions` to stop approving tool
  calls and then blocking every session on approving a plan is the same interruption moved one
  level up.
- `tests/auto-trigger.sh` preflight exits 2 locally instead of 0. A run that tested nothing
  read exactly like a pass.
- `readme-writing` no longer accepts `unslop`, whose own description is "Must always apply" and
  which therefore made the case unable to fail.

### Measured

| | before | after |
|---|---|---|
| gate checks | 13, 3 of them silent without jq | 20, all falsifiable |
| doctor scan reach | 5 repos | 27 repos and worktrees |
| settings keys the overlay ships | 27 | 10 |
| routing suite | 9 cases, no negative controls | 11 cases, 11 passing |
| session token surface | unmeasured | 15,857 bytes, ~3,964 tokens |

## 1.0.0

First public release: 25 skills, 8 subagents, 14 commands, the SessionStart routing hook, the
Stop-hook verify gate, and the three install lanes.
