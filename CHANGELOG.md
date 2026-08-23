# Changelog

Versions follow [semver](https://semver.org). The version lives in two manifests,
`.claude-plugin/marketplace.json` and `claude/.claude-plugin/plugin.json`, and check 13 of
`.claude/verify.sh` fails when they disagree.

## 1.34.0 — 2026-08-23

**The grill nudge was displacing the skills it sits next to.** `tests/auto-trigger.sh` had never
run in CI and, as far as the log shows, never run at all. Run locally against v1.31.0 it scored 19
of 28. Nine of the failures were long prompts where the expected skill never fired, and in nine
attempts across those cases the thing that fired instead was `grill-me`.

The cause was in the nudge, not in any skill. It triggers on character count alone, 320 characters
or 120 on the first prompt of a session, and it said "run the grill-me skill on this request now,
before any code or plan. Not optional." An unconditional imperative attached to a length threshold
fires on essentially every substantive request and outranks situation matched routing, so
`principle-boundary-discipline`, `impeccable`, `create-verification-skill` and
`principle-sequence-verifiable-units` lost to it on prompts that were about none of those things.

The nudge now yields: it runs when no skill matches the situation more specifically, and says so.
Re run after the change, same suite, same fixtures: 22 of 28, and grill-me hijacks went from nine
to zero. Stated honestly, one case moved the other way, `principle-build-the-lever` passed before
and failed after, and skill dispatch is a model decision, so a single paired run carries noise. The
hijack count going to zero is the part that is not noise.

Six failures remain and they are a different defect: nothing fires at all, `(none)` in every
attempt, and four of the six are `principle-*` skills. The principles lane is not being displaced,
it is not being reached. Not fixed here.

**How often 1.30.0's 300K window actually binds, measured.** 120 real session transcripts under
`~/.claude/projects` were scanned for peak context occupancy. 20 percent of sessions exceed 230K,
which is where the 300K setting really triggers. 7 percent exceed 680K, where the old unset default
would have triggered. The two largest peaked at 999,445 and 997,674 tokens, and several sessions
sat at 905K, 906K and 765K having never compacted at all. So the change is neither inert nor
constant: it alters behaviour on about one session in five, and the sessions it catches are the
ones that were previously running the entire way at 900K of context.

**The synthetic A/B was abandoned, and why is the interesting part.** Three attempts to drive a
session past the window failed because this configuration prevented it. The digest tells the model
to batch independent tool calls, so one step went from 40K to 321K with no turn boundary in
between. The same digest says never read whole files and prefer grep with line ranges, so an arm
built to read 359K of source instead grep'd it and peaked at 32K across three turns. The config is
extremely good at keeping context small, which is the reason compaction is rare here, and it is
also the reason a synthetic harness cannot reproduce the conditions it is meant to measure. The
transcript scan above replaced it and answers the same question from real data.

## 1.33.0 — 2026-08-23

**Two shipped defects found by the first real-container install matrix against published
GitHub tags (debian:stable-slim, alpine:latest, ubuntu:latest, no credentials mounted).**

- `bin/doctor` exited 1 on a clean, correct install on Alpine. The "active repos overlaid"
  check computed a 45-day cutoff with `date -v-45d` (BSD/macOS) falling back to
  `date -d '45 days ago'` (GNU) — BusyBox date, Alpine's only date, understands neither, so
  `cutoff` came back empty and the check hard-failed with "could not compute a cutoff date"
  instead of scanning. Replaced both relative-time forms with arithmetic on `date +%s`
  (universal across BSD/GNU/BusyBox), then formatted the epoch with `date -r SECONDS` (BSD)
  falling back to `date -d @SECONDS` (GNU/BusyBox) — a strict superset of the two cases the
  old code handled, so nothing else needs to stay. The empty-cutoff hard-fail is preserved for
  the case `date +%s` itself fails.
- `vstack update` told a user pinned to a release tag they were up to date, forever, even when
  dozens of commits ahead. The README's own pin quickstart (`VSTACK_REF=vX.Y.Z bash
  bootstrap.sh`) clones with `--depth 1 --branch vX.Y.Z`, which sets `remote.origin.fetch` to
  fetch *only that tag* — `refs/remotes/origin/main` never exists. `update` resolved the
  upstream via `@{u}`, fell back to the literal string `origin/main` when that failed, and
  compared `HEAD..origin/main` — an unresolvable ref that failed silently (stderr discarded)
  and produced empty stdout, read identically to "nothing to update". Fixed by repairing the
  fetch refspec and unshallowing before comparing, rather than refusing outright: a shallow
  fetch of just `main`'s tip would fix the drift check but leave `merge --ff-only` unable to
  prove ancestry across two disconnected shallow histories, so the repair drops the shallow
  boundary entirely. If the upstream still cannot be resolved after repairing — wrong remote,
  `main` renamed, network unreachable — `update` now exits 1 with an explicit message and a
  re-clone command, never silence.

## 1.32.0 — 2026-08-23

**The three `bin/` wrappers claimed success when nothing happened.** `tests/bin-scripts.sh`
(new) ran them for the first time ever, off local stubs, and found 17 failures across all
three: the exact "green gate that measures nothing" class this repository exists to catch,
shipped in its own payload.

- `claude-task.sh`'s exit code never reflected the inner `claude -p` run — a hard failure
  (crash, `--max-turns`, auth error) still exited 0, so cron/launchd could never learn a
  scheduled run failed. It now propagates the inner exit code.
- `claude-task.sh` silently exited 0 with no output and no log on a missing task directory, a
  task directory with no `SKILL.md`, `--help`, and any bogus flag (previously a flag fell
  through and was treated as a task name). All four now exit non-zero with an authored
  message on stderr.
- `claude-task.sh` discarded the caller's `PATH` and substituted a hardcoded list, so a
  `claude` install anywhere else on the caller's own `PATH` was invisible to it. The known
  locations are now prepended to the inherited `PATH` instead of replacing it; if `claude` is
  still unresolvable, the script fails loudly rather than proceeding.
- `claude-task.sh`'s no-arg case emitted raw bash parameter-expansion text
  (`line 24: 1: task name required`) instead of an authored message. Fixed, and the SC2012
  `ls -dt | head` in the nvm-detection fallback is now a glob ranked by `stat` mtime.
- `claude-bg.sh` did no `PATH` hardening at all: under a cron-shaped minimal `PATH` it printed
  `dispatched → …/log (pid N)` and exited 0 while the backgrounded job died with
  `command not found`, surfaced nowhere. It now hardens `PATH` the same way and refuses to
  dispatch (non-zero, authored message) when `claude` cannot be resolved.
- `~/.config/agents/bg/` was never created by `install.sh`, so the first invocation on a fresh
  install failed the log redirection before the subshell even started — after already printing
  `dispatched`. Fixed in both places: `install.sh` now creates the directory, and
  `claude-bg.sh` creates it and verifies the log is writable before printing any success line.
- `claude-bg.sh` forwarded `--help` and bogus flags to the model as literal prompt text,
  spending a real headless call on a typo. Both scripts now recognise `--help`/`-h` and any
  `-*` argument before dispatch and refuse with an authored message instead.
- `deploy-auto.sh`'s `cd` failures leaked the builtin's own stderr
  (`line 7: cd: -x: invalid option`) ahead of its authored "cannot enter" message. `cd --` plus
  a suppressed builtin stderr fixes both the flag-shaped-argument and nonexistent-path cases.
- All three now warn (not silently drop) extra positional arguments, and implement `--help`.

`tests/bin-scripts.sh` is green (37/0) and stable across repeated runs; nothing in this release
touches what ships to `claude plugin install` beyond these three wrapper scripts.

## 1.31.0 — 2026-08-23

**`git add -A` in a tree you do not own now asks first.** On 2026-08-23 two sessions were writing
`~/Projects/vstack` at once. One of them ran `git add -A`, swept the other's uncommitted security
fixes into a commit whose message described only a documentation change, and pushed it. The code
was correct and the release notes were not: three security fixes reached origin unversioned and
unchangelogged, and the catch-up release had to say so in its own tag. Nothing prevented it and
nothing detected it. `git status` was clean when the committing session last looked.

The guard now asks on `git add -A`, `git add .`, `git add --all`, `git commit -a`, `git commit -am`
and `git commit --all`, but only when `CONDUCTOR_WORKSPACE_PATH` is set and the working directory
sits outside it. That is exactly the case where another session may be mid-edit. Inside your own
workspace it stays silent, because that is the normal case and a guard that fires on every commit
is a guard that gets uninstalled. Explicit paths are never touched: `git add bin/doctor` passes.

Both directions are asserted in check 30, including two rows that must NOT fire. One of them is
`git commit -m "add a thing"`, which exists because the obvious glob for the `-a` flag also matches
the letter sequence in a commit message and would have made the guard fire on ordinary commits.

**The guard's own row count stopped being written down.** Check 23's label carried a literal that
had gone 16, then 22, then 24, while `SECURITY.md` still said sixteen. Both were prose about a
table that nothing re-derived. The label now counts the table as it runs and prints what it
actually tested, 30 rows, and `SECURITY.md` no longer names a number at all. Same defect this repo
keeps finding in its own documentation, this time in the file whose job is finding it.

Worth stating plainly, since the fix is narrower than the lesson: the guard reduces the blast
radius, it does not make a shared worktree safe. Two agents editing one checkout will still
interleave. The durable rule is to stage explicit paths whenever another session might be in the
tree, and the guard only enforces it where the environment says which tree is yours.

## 1.30.0 — 2026-08-23

security-auditor closed the three findings raised against 1.28.0. What follows is what was
wrong and how it is known to be fixed, not a list of feature names.

**`vstack update` diffed a hardcoded five-path list and called the rest of the merge invisible.**
`TRUSTED="install.sh overlay.sh uninstall.sh bootstrap.sh .claude/verify.sh"` was the entire
review surface, and the command printed "(no changes to the scripts the gate executes)" while
`install.sh` deploys nearly the whole repository — `claude/hooks/*.sh`, `claude/settings.json`,
`bin/vstack` itself — none of which that list named. A commit weakening
`guard-destructive.sh` or neutering `verify-gate.sh`'s hash check could land under that
reassurance at the exact moment the prompt exists to be trusted. Found by security-auditor
EVIL-MORTY C-137 against a throwaway local remote: the old code printed the all-clear while
`guard-destructive.sh` itself was the file being changed. Fixed by diffing the full
`HEAD..upstream` range instead of expanding the list — a hand-maintained set has to track
`install.sh`'s deploy surface exactly, and every missed entry silently reopens the hole, which is
how this one happened; a full diff cannot drift out of sync with a surface it never tries to
describe. The five gate-executing paths survive as a named warning banner on top of that full
diff, not as a filter that hides the rest.

**`vstack trust` armed unattended script execution with no confirmation of its own.** "Trusted"
meant only that a line existed in `~/.config/agents/verify-trust`, and `verify-gate.sh`'s Stop
hook runs whatever hashes to that line forever after, with nothing checking it again.
`bin/vstack:172` stated the intent — "the boundary is anchored on a human reading the script
before running this command" — and nothing enforced it, so a hostile `CONTRIBUTING.md` telling an
agent to run `vstack trust .` turned the gate meant to stop unreviewed execution into the
delivery mechanism for it. Found by security-auditor EVIL-MORTY C-137. `update` had already
solved this exact shape one command above — refuse without a TTY, require `--yes` for automation
— so that pattern is ported rather than invented twice, plus a prompt asking whether the human
has actually read the script just now. `install.sh`'s self-trust path is unaffected: it writes
the store directly and never calls the CLI. `guard-destructive.sh` also gained an ask-tier rule
for any segment naming `vstack trust` or `verify-trust`, matched broadly rather than narrowed to
writes, because the guard's own header disclaims semantic detection and a narrow match is exactly
where a bypass would live.

**`format.sh` executed repo-supplied JavaScript with no confirmation, on every edit.**
`npx --no-install prettier` ran against any covered file whenever a prettier config was present,
and prettier's own config loader treats `prettier.config.js`/`.prettierrc.js` (and the `.cjs`,
`.mjs`, `.ts` variants) as ordinary JavaScript, `require()`-ing it the moment it resolves config.
Hooks sit outside the permission system, so a hostile repo shipping one of those with `execSync`
at module load got code execution the instant the agent edited any covered file — proven, not
theoretical: security-auditor EVIL-MORTY C-137 demonstrated the pre-fix script running the
payload. `--config` does not close it, because prettier still requires a JS config file even when
told which one to load. Fixed by refusal: the hook now replicates prettier's own config search
far enough to classify which file would win, and if that file ends `.js`/`.cjs`/`.mjs`/`.ts`,
prettier is never invoked at all. Static-format winners are still passed explicitly via
`--config`, bypassing prettier's own search entirely, so a bug in the classifier can only make it
too cautious, never permissive. Residual risk is documented in the file rather than silently
closed: a static config's own `plugins` array can still name a local `.js` file that prettier
will load, and prettier 3 has no flag to refuse plugin loading outright.

**The same lines paid full Node module resolution to fail on a fresh clone.** Measured by
performance-engineer PICKLE-RICK P-92: a repo with a prettier config but no `npm install` yet —
the state of every clone before its first install — sent `npx --no-install` through full
resolution before giving up, at 639, 494 and 464 milliseconds across three repeated edits. The
rewrite above looks for the formatter binary directly under `node_modules/.bin`, walking up the
same way the config search does, and only runs it when it is actually installed rather than
trying to fetch it: 63, 65 and 64 milliseconds on the same three edits.

**The destructive-command guard's decision table grew by one rule.** `guard-destructive.sh`
gained the ask-tier match for the trust-store name above, and the falsifiability suite that
exercises it grew from 22 entries to 24, covering both `vstack trust .` and a direct
`verify-trust` append, asserted in both directions. Independently re-verified against the rest
of the table: no existing verdict moved — `npm test` and `rm -rf node_modules` still allow,
`rm -rf /` and a compound force-push still deny.

**Flagged, not fixed: `SECURITY.md:43` undercounts the guard it describes.** It reads "check 23
tests all sixteen across three tiers" — a claim that was already stale before this release, since
the guard's table had grown past sixteen some time before this audit, and is stale by a larger
margin now that it has grown again. Nothing ties that sentence to the real count: it is the same
gap check 12 exists to close everywhere else in this repo's docs, except this sentence spells the
number out in words rather than digits, which was never in check 12's extraction grammar, so it
passes unmeasured rather than being caught by it. Left as a stated defect rather than a quiet
correction, because a corrected number with nothing enforcing it only looks fixed until the table
grows by one more entry.

**The compaction numbers in 1.29.0 were reasoned, and now they are measured.** Two things that
release asserted turn out to be wrong, and one turns out to be right. Method: a headless session
driven past the window on Claude Code v2.1.241, once with `--autocompact 100k` and once with
`autoCompactWindow` pinned in settings and no flag, reading the transcript's `compact_boundary`
records rather than inferring from token counts.

Right: the knob is honored, by both paths. Four `trigger: auto` compactions fired where the
configuration said they should. The open issues alleging `autoCompactWindow` is ignored do not
reproduce on this version, so vstack's pin is real rather than decorative.

Wrong, first: compaction does not fire at the window, it fires at 68 to 81 percent of it. Measured
triggers were 68,251, 75,625, 78,089 and 81,083 tokens against a 100K window. The headroom is not
a constant and not a clean fraction, since it moves with the size of the request waiting to be
sent. The 300K pin therefore compacts near 230K in practice. That is close enough to the intent to
leave alone, but the setting is not the trigger and this file should not have implied it was.

Wrong, second: the release said an uncompacted session takes a "roughly 200:1 squeeze", which
assumed the summary is a fixed ~5K no matter the input. It is not. Measured `postTokens` were
5,958, 17,199, 20,900 and 22,852, so the summary scales with what it summarizes and the real
ratios were 3.5:1 to 11.5:1. Extrapolating 200:1 to a 967K session was arithmetic on an assumption
that does not hold. The compression ratio argument for a middling window still stands directionally
because Governance Decay's loss term grows with ratio, but the magnitude quoted was invented.

Unpriced until now: each compaction cost 33 to 81 seconds of wall time. A window set too low
thrashes, and 100K produced three compactions inside an eight turn session, which is the cycle
count term of the same paper working against the ratio term. That tension is the real argument for
a value in the middle, and it is a better one than the ratio figure that shipped.

Also worth recording, because it confounded the first attempt at this measurement: vstack's own
digest tells the model to batch independent tool calls into one message. That makes context grow in
large jumps rather than gradually. A single batched step took a session from 40K to 321K, clearing
any window in one bound with no turn boundary in between for compaction to fire at. The batching
instruction and the compaction threshold are in tension, and nothing in the config says so.

## 1.29.0 — 2026-08-23

**Compaction ran at the model's context limit, and nothing said so.** `autoCompactWindow` was
never set, so Claude Code compacted only when a session reached the window — about 967K of Opus
5's 1M — squeezing the whole conversation roughly 200:1 in one event. Compaction loss scales with
both the compression ratio and the number of cycles (arXiv 2606.22528), so a single late squeeze
is the worst arrangement on offer. It is pinned to 300K, holding the ratio near 60:1. That number
is chosen from the shape of the evidence, not measured: nobody, Anthropic included, has published
a quality curve against context length for Opus 5, and every figure circulating for the 200K–1M
band traces to commercial blogs with no method. Cost did not drive it and does not object — the
long context premium was removed in March, and a cached 500K turn costs a third of one cold 150K
turn, so cache hit rate is the cost variable, not context size.

**The operating policy did not survive its own compaction.** The session baseline is injected by
the SessionStart hook, which puts it in the conversation layer — precisely what compaction
replaces. Only the per-prompt digest refires, so a long session kept 60 tokens of digest and lost
the routing table, the roster, and every constraint set before the squeeze. `CLAUDE.md` now
carries a `# Compact instructions` section naming what to carry across, and doctor fails when it
is absent.

**The statusline reported dollars and not tokens.** It could not answer the question behind all
of the above — how full is the context — so the threshold was unobservable and therefore
untunable. It renders occupancy against the compaction window rather than against the 1M, because
300K measured against 1M looks like nothing. Writing that field surfaced an older bug in the same
file: fields were read with `IFS=$'\t'`, and tab is IFS whitespace, so bash coalesced runs of it
and one empty field shifted every field after it. A session with no `output_style` rendered its
token count in the cost position. The separator is now US, which cannot occur in a display name,
path or number. doctor asserts the statusline threshold equals the setting, since a statusline
warning at a number the runtime does not use is a green that measures nothing.

**Plan mode silently bypassed the roster.** The routing table never mentioned it, while plan
mode's own workflow forces the builtin Explore and Plan agents and bars writes — so MORTY and
ZEEP were unreachable and `/team` could not run, with nothing reporting the substitution. The
baseline states it now.

**vstack claimed to enable claude-mem, and the toolchain never installs it.** `enabledPlugins`
in `claude/settings.json` carried `"claude-mem@thedotmack": true`, which is false on any install
that has not separately run `claude plugin install claude-mem@thedotmack`. This is strictly
worse than commit eb22605's removed *disabled* entry: a disabled line is inert, but an enabled
one for a plugin the toolchain never installs misrepresents a fresh install's state until the
user acts on their own. Flagged from the product side by `product-owner` (enabling it
conditionally from `install.sh` was considered and rejected — that puts vstack in the business
of maintaining a third-party plugin's install path it does not own) and independently from the
supply-chain side by `security-auditor`: an unpinned third-party plugin identity trusted by bare
name, no `extraKnownMarketplaces` entry declaring its origin, under `autoUpdatesChannel:
"latest"`. Existing users are migrated rather than left half-done — `install.sh`'s settings-merge
jq program gained `del(.enabledPlugins["claude-mem@thedotmack"]?)`. `worker` found this could not
use the `RETIRED` mechanism: `RETIRED` deletes top-level keys and check 21 validates only
top-level key history, so a nested plugin name would fail that gate against no history to check
— hence the targeted `del` instead. Verified empirically: before
`{"claude-mem@thedotmack":true,"typescript-lsp@claude-plugins-official":true}`, after
`{"typescript-lsp@claude-plugins-official":true}`, an unrelated user key survives the merge, and
a fresh install carries zero references. Kept deliberately, because "remove every reference"
would have been the wrong read: `bin/doctor`'s filesystem-based `[ -d "$HOME/.claude-mem" ]`
note, its async-flag guard (the plugin's `UserPromptSubmit` hook must stay async or it blocks
every prompt, and the plugin self-updates and reverts the flag), the conditional statusline
indicator, and every historical mention in this file, `docs/provenance/` and
`docs/how-skills-fire.md` — vstack removed a claim it was making, not support for a tool a user
chooses.

**A comment counted to 27 while the file held 28.** The retired-keys note in `install.sh`
hardcoded the number of top-level settings keys, and had already drifted stale by one. It now
says to compare the two counts against each other rather than against a number written in the
comment — the only form of that claim that cannot rot.


## 1.28.0 — 2026-08-23

Six auditors and five fixers went through this repository in one day. What follows is what was
wrong and how it is known to be fixed, attributed to the agent that found or fixed it — not a
list of feature names.

**CRITICAL: the destructive-command guard's deny tier was gated behind a heuristic that any
compound command defeated.** `SIMPLE` dropped to 0 the instant `$CMD` contained `;`, `&&`, `||`,
`|`, a backtick or `$(`, and only a `SIMPLE=1` command ever reached deny — the one tier that can
refuse outright, with no floor under it if it is skipped. Measured: `git push --force origin
main` denied; `true && git push --force origin main` allowed. The ask tier had no git-push
pattern at all, so the compound form did not even prompt. A second hole in the same check:
`git push -f origin HEAD:refs/heads/main` was allowed, because the branch match
(`*\ main*|*:main*`) tested substrings and a full refspec destination never contained one. Found
by `security-auditor`; fixed by `worker`, who now splits `$CMD` on `;`, `&&`, `||` and `|` and
judges every resulting segment against the deny patterns independently, and matches refspec
destinations (`:refs/heads/main`) alongside the short forms. Check 23's `g_want` table grew from
16 rows to 22, adding both the compound and the refspec deny cases.

**Declined, and stated here as a limit rather than left implicit: `RMFLAGS=-rf; rm $RMFLAGS /`
still passes.** The guard reads syntax, not semantics — there is no shell interpreter behind it
— and evaluating variable expansion to catch this would need real shell evaluation, which
produces false positives on ordinary variable use worse than the bypass it would close. This is
recorded in `guard-destructive.sh` itself as an explicit out-of-scope case, not silently accepted.

**`skill-mandate.sh` shipped to every user's `~/.claude/hooks/` and `install.sh` wired it to
nothing.** `grep -c skill-mandate ~/.claude/settings.json` returned 0 after a fresh install.
Every mandate the hook enforces — unslop, typescript-best-practices, delegation, agent-naming —
was inert for anyone who installed with `install.sh`; the hook was wired only in this
repository's own `claude/settings.json`, which reaches a project solely through `overlay.sh`,
the developer lane. Found by `performance-engineer`; fixed by `debugger`.

Check 11, named `hook wiring`, was green over this twice. It unioned the plugin-lane references
(`claude/hooks/hooks.json`) with the user-lane references and asked "is this wired anywhere",
which the plugin lane alone satisfied. A first rewrite that read only production lanes still
passed, because it kept testing membership against the same union. It now asserts coverage per
lane, with a named `USER_LANE_EXEMPT` allowlist for anything legitimately plugin-only — empty
today, because every shipped hook belongs in the user lane. Watched failing before being
believed: removing the wiring line now produces `skill-mandate.sh: shipped in claude/hooks/ but
not wired in the USER lane`. `bin/doctor` reported `hooks ✔` throughout, because it checked file
presence under `~/.claude/hooks/`, never whether anything referenced the file.

**BLOCKER: `bin/vstack:73` ran a bare `git fetch`.** `fetch.prune` and `fetch.pruneTags` are
both `true` globally on this machine — the same configuration that destroyed five unpushed
release tags during the v1.9.1 audit, which is why `bin/doctor:260` was hardened afterward — on
the one command in this repository whose entire job is pulling code. That hardening never
reached `bin/vstack`. Found by `code-reviewer`; now runs `git fetch --no-tags --no-prune
--no-write-fetch-head` against an explicit remote.

**`install.sh` exited 0 on a failed install.** A failed `jq` settings merge sets `DEGRADED=1`,
which also makes the trailing `doctor` call fail — but the doctor-failure branch called `exit 0`
before the `DEGRADED` check below it ever ran, so a degraded install still reported success.
Found by `code-reviewer`.

**`rm -rf /*` fell through to `ask` instead of `deny`.** An unquoted `for tok in $CMD`
pathname-expanded the glob before the `case` statement ever saw a literal `/*`, so the pattern
naming the deny case never matched. GNU `rm --preserve-root` blocks a bare `rm -rf /` but not
`rm -rf /*`, which made this the more dangerous of the two phrasings and the one the guard
missed. Found by `code-reviewer`; fixed with `set -f` around the token loop.

**`doctor` hung 77.5 seconds against an unreachable remote, with no timeout on the call**, and
`install.sh` runs `doctor` last, so a new user's first command looked hung for over a minute.
Found by `qa`; fixed by `debugger`, whose own first attempt still hung — killing `git ls-remote`
orphaned the `git-remote-http` helper it forks, which held the output pipe open for the remote's
full connect timeout regardless of which process was killed. The working fix backgrounds the
call in its own process group and kills the group, not the child. `doctor` now returns in 7.3s
against the same unreachable remote. macOS ships neither `timeout` nor `gtimeout`, so there is a
manual fallback for hosts with neither.

**Moving `$HOME` left dead hook entries in `settings.json` permanently.** `install.sh`'s
reinstall cleanup decided which `Stop`/`SessionStart` entries were "ours" by testing
`startswith($h)` against the *current* `$HOME` — a `settings.json` copied from a different
machine, or a renamed account, had its old vstack entries read as user-authored forever, since
they no longer started with the new `$h`. Every reinstall then appended another duplicate.
Ownership is now decided by shape: a command whose immediate parent directory is literally
`hooks` and whose filename is one this repository ships.

**`uninstall.sh --yes` run twice copied its own safety backup into `$HOME/pre-uninstall`.**
`restore_pairs()` excluded its `files`/`files_abs` bookkeeping directories from restoration but
not `pre-uninstall/`, the directory the script writes its own undo copy into — a second run
mapped that directory through the generic legacy-name rule and planted a permanent, ever-growing
copy in the user's home.

**`install.sh` claimed "every file this run touched was copied to backup first" even when no
backup directory existed.** The guard was `[ "${BK:-}" = "" ]`, and `$BK` is assigned
unconditionally near the top of the script, so it is never empty — a run that died before
`mkdir "$BK"` succeeded (unwritable `$HOME`, a full disk, no permission on `~/.config`) still
printed the claim, pointing at a path that was never created. Now gated on a `BK_CREATED` flag
set only after the `mkdir` succeeds.

**An unlocked counter race in `verify-gate.sh` and `skill-mandate.sh` let concurrent invocations
undercount instead of overcount.** Ten racing sessions reading, incrementing and writing the
same block-count file with no lock left the file at 1 instead of 10 — every writer read the same
stale value before any of them wrote — so the strike cap that is supposed to latch the gate open
after repeated failures never engaged, and every one of the ten invocations blocked instead.
Found by `qa`; fixed by `debugger` with an `mkdir`-based lock (atomic on any POSIX filesystem, no
GNU `flock` required) and a 30-second stale-lock steal for a lock left behind by a killed
sibling. Proven against the fixed version: with the cap set to 2, exactly 2 of 10 concurrent
invocations block.

**A session that dispatches subagents must now attribute the work by call sign, or the `Stop`
hook blocks.** `skill-mandate.sh` gained an agent-naming mandate: a `Task` call with no
call-sign string (`RICK C-137`, `BETH J-42`, ...) anywhere in the transcript blocks at `Stop`,
naming the rule. `VSTACK_NO_MANDATE=1` disables it, same as every other mandate this hook already
runs. Added by `worker`. Check 27's case table grew from 10 rows to 14.

Three checks caught defects introduced during the audit itself, each in a check that had been
repaired earlier the same day and had previously reported green over the thing it now names:
check 18 caught the published context-figure claim going stale by 204 bytes after the session
block grew (3.6 -> 3.8 KB full, 2.1 -> 2.3 KB plugin, both now updated); check 11 caught a wiring
entry pointing at `hooks/statusline.sh`, a file that does not exist; check 12 caught
`ATTRIBUTION.md`'s skill count, which had drifted to 26 while the tree carries 28.

**What this release does not fix, stated plainly rather than implied away:**
- `vstack update`'s `TRUSTED` diff list omits `claude/hooks/*.sh` and `settings.json`, so it can
  print "no changes to the scripts the gate executes" while installing a modified guard.
- `vstack trust` is a plain CLI command any agent can run; a hostile `CONTRIBUTING.md` that says
  "run `vstack trust .`" turns the gate into a delivery mechanism for the thing it exists to stop.
- `format.sh` runs `npx prettier`, and Prettier's `cosmiconfig` executes `prettier.config.js` as
  JavaScript.
- The gate costs 46.6s per `Stop`; 19.02s of that is 39 sequential `shellcheck` spawns. Batching
  them measured at 9.88s.
- Three shipped scripts nothing exercises: `bin/claude-bg.sh`, `bin/claude-task.sh`,
  `bin/deploy-auto.sh`.

## 1.27.0 — 2026-08-23

**`skill-mandate.sh` gained a delegation mandate.** A session that touches 3 or more distinct
parent directories with 2 or more distinct file extensions and dispatches zero `Task` calls now
blocks at `Stop`, naming the directory and extension counts and suggesting `/team` or a specific
subagent. Five fixtures written to one directory does not trigger it — one directory, one
extension, mechanical repetition. A hook.sh plus test/hook.test.sh plus doc/HOOK.md plus
manifest.json does — four directories, three extensions, actual multi-part work with nobody
delegated to. `VSTACK_NO_MANDATE=1` disables it, same as every other mandate this hook already ran.

It took three attempts to hold. The first version counted distinct *files*, not directories, and
false-blocked five fixture writes to a single `fixtures/` directory as if five files were five
kinds of work. The second version split on the first `.` in a filename to find an extension, so
three dotfiles in three different directories — `.editorconfig`, `home/.gitignore`,
`proj/.npmrc` — read as three distinct file types and blocked a session that had touched nothing
but config. Both were caught by `qa`, not by the gate: check 27, `skill mandate decides
correctly`, stayed green through both rejections, because its case table had no dotfile case and
no multi-directory case to catch either bug. That is this repository's founding defect —
a check that passes while the thing it names is broken — landing in the same feature that was
supposed to make delegation harder to skip. Check 27's case table grew from seven rows to ten: the
shipped version counts breadth (distinct parent directories, distinct extensions with dotfiles
read as having none unless a second `.` follows), and cases h, i and j hold the fixture-directory shape,
the real multi-directory shape, and the dotfile shape as permanent regressions. `test-breadth-mandate.sh`
under `tests/` is the scratch harness that found both bugs, kept as a fast no-gate way to
reproduce a mandate decision by hand.

**All 14 agents in `claude/agents/` were renamed** from occupational call signs (`MULE`, `PROOF`,
`REDLINE`, `SCOUT`, ...) to Rick and Morty characters (`BIRDPERSON`, `BETH`, `MEESEEKS`,
`EVIL-MORTY`, ...), and the instance-handle format changed from an adjective+animal
(`SwiftFalcon`) to a dimension code (`C-137`). The lead invoked by `/team` is now `RICK`, signing
as `RICK C-137`. `design-reviewer.md` briefly carried two call signs mid-edit; the stale one was
removed before this landed.

## 1.26.0 — 2026-08-23

**The README was 345 lines and never said what this is.** The category noun — a Claude Code
configuration bundle — did not appear in the file, and the first plain statement of what you
receive was 185 lines down. Section one was a 45-line teardown of a competitor, so a reader who
had never heard of that project had to learn it before they could evaluate this one. Six negations
arrived before one positive statement. The voice was first-person memoir.

It is 188 lines now: name, one-line description, badges, requirements, install, and the
differentiator stated concretely by line 20 rather than argued for over three sections. The
competitor forensics and the null-result essays keep every word, in `docs/`, where a reader who
wants them can find them and a reader deciding whether to install is not made to read them first.

**The repository layout is documented, because two of its directory names are traps.** `claude/`
is the shipped payload and `.claude/verify.sh` is this repository's own gate; `conductor/` and
`.conductor/` collide the same way. That distinction was written down in exactly one place — a
comment inside the check that depends on it. The rule is now a table on the front page: the dotted
one is always this repository holding itself to something, the undotted one is what you receive.

**Root went from 17 tracked files to 16**, and two of the survivors are new. Three `LICENSE*` files at root was the loudest
disorder signal; `LICENSES/Apache-2.0.txt` and `LICENSES/MIT-upstream.txt` now sit together with
`LICENSE` and `NOTICE` left at root where convention and Apache-2.0 §4(d) put them. `.gitkeep` was
deleted — zero bytes, keeping no directory alive, and surviving check 31 only because a provenance
document happened to contain the string as a substring. An accidental referrer is the same class
of defect as an accidental green.

`CODE_OF_CONDUCT.md` and `.editorconfig` added.

**Check 38's document set is derived rather than listed.** It scanned 8 documents from a hardcoded
pathspec; it scans 15 now. `CONTRIBUTING.md`, `SECURITY.md`, `CODE_OF_CONDUCT.md` and
`claude/CLAUDE.md` were all invisible to it. A hand-maintained list narrows silently, which is the
failure this repository documents against itself, and check 12 already derived its set the right
way three checks over.

**Two rules in the shipped policy.** Work routes through the configuration rather than around it —
multi-phase work through `/team`, reviews to `code-reviewer`, verification to `qa`. And delegated
work is reported with the agent named and its call sign, in reasoning as well as in the final
table, because a verdict with no author cannot be challenged and separate contexts are worth
routing to only because they can disagree.

Both rules had to be paid for. Adding them pushed the sandbox policy block 398 bytes over check
34's 6144 cap, so the register ban list was compressed from 1757 bytes to 839 while keeping all
five banned classes. Context is a budget and this file is inside it.

## 1.25.0 — 2026-08-23

**Presentation is a phase with an owner.** `/team` gained phase 6b, run before ship for any change
a stranger could see: is the README's first screen still accurate, do the counts still match the
tree, did anything land loose at the repository root, does every new file sit somewhere a stranger
would guess, do the docs still point at what exists.

The lead owns it because no phase agent does. `code-reviewer` reads the diff, `qa` exercises the
feature, and neither looks at whether the front page still describes the thing that shipped. The
same rule is in the shipped `CLAUDE.md` so it applies outside `/team` as well.

A feature that works and leaves the project looking abandoned is not done. Presentation is not
polish applied afterwards.

## 1.24.0 — 2026-08-23

**The four bundled reference modes shipped in 1.23.0 are deleted.** They were four sites measured
in detail and frozen into the skill, which is a taste snapshot: it rots, it knows nothing about the
surface in front of you, and it drags every build toward whatever those four did on the day. That
is the same defect as a count nobody re-derives, one layer up — an answer shipped in place of the
thing that produces answers.

`scripts/extract-brand.sh` ships instead. It points a headless browser at any URL the user names
and returns the rendered type scale, tracking per size in em, leading per size, measure in ch,
resolved ink and ground with a hue count, a spacing census with base-unit conformance, transition
duration and easing frequencies, and the radius set. Colour is resolved by painting one pixel and
reading it back rather than parsing the string, because `getComputedStyle` returns `oklch()` on
modern sites and both a digit regex and `canvas.fillStyle` hand back nonsense for it.

The pipeline it feeds is requirements first, then references the user names, then measurement,
then reconciliation with disagreements put to the user rather than averaged, then mockups
screenshotted and approved before a component is written, then optional handoff to Claude Design,
then build with the gate armed. Nothing fires without a `.impeccable/brand.json` in the target.

What survives from 1.23.0 is the list of what to read off a reference and why each item earns its
place — every one is measurable, survives into a gate, and differed between expensive builds and
default ones.

## 1.23.0 — 2026-08-23

**Four visual modes, measured rather than described.** `impeccable` described the bar in
adjectives, which cannot produce it. The only head-to-head anyone has run on config-layer
interventions found prose instruction without retrieval made outcomes worse than none — 9.94%
regression rate against a 6.08% baseline — while the same instruction with retrieval context
reached 1.82%. So the bar now ships as numbers read off live sites: computed styles, pixel
histograms, canvas autocorrelation, font-outline measurement.

`reference/modes/` carries `pixel`, `plate`, `editorial` and `scrollfield`, each with its
signature mechanism written out as implementable CSS. What held across all four is separated from
what distinguishes them, because the distinguishing properties contradict each other directly —
base unit 2px against 4px, grain against none, binary radius against a three-step set — and
averaging them resolves every contradiction toward the stock default.

The invariants are enforceable claims, not taste: weight 400 for all display and body with
hierarchy carried by size and tracking; tracking as a monotonic function of size locked in `em`,
crossing zero at 15–20px; line-height inverting with size; one accent hue or none; motion in two
bands with nothing between 300 and 420ms.

**Opt-in per project.** A `.impeccable/brand.json` selects the mode and declares tokens.
`ui-gate/rules/tokens.sh` already reads its `type.scale` and fails a build off it. With no such
file nothing fires. A skill that decides on its own whether something deserves to be beautiful
would fire wrongly and constantly; a file in the repo is a decision somebody made.

**Claude Design documented as a publishing lane.** `/design-sync` and `/design-login` are built
into the CLI binary at 2.1.239 with a seven-operation `DesignSync` tool. Flow is one way — push a
design system up, export by hand to come back — so it is not a generation lane and should not be
planned around as one. Where the account lacks access, say so and tell the user to enable it
rather than working around the absence.

Two defects were recorded from the references rather than copied: a 12px consent line failing AA
at 4.34:1, and a scroll-driven site whose `prefers-reduced-motion` coverage misses its own hero.

## 1.22.0 — 2026-08-23

**Register rule tightened after it failed once.** v1.21.0 banned commentary on the facts and did
not stop discourse openers, narrated process, or empty hedging. The correction arrived a second
time, which is the trigger for encoding a rule as a specific list rather than restating an
intent. Five banned classes now, each with its own examples: openers and acknowledgement tokens,
commentary, narrated process, information-free hedging, and restating the question. Plus the
deletion test — if a sentence survives removal without changing what the reader does next, it
goes.

**Six ui-gate rules came back from the dead.** They were unconditional skips carrying "playwright
is not vendored here", and nothing in that file ever checked for a browser. vstack ships
`agent-browser`, a Rust binary driving Chrome over CDP, already installed and already the
documented answer for headless work in parallel workspaces. Two thirds of the UI enforcement layer
was inert for a stated cause that had expired, announcing that cause in every run.

`COV-VIEWPORT` fails on horizontal overflow at 375px. `A11Y-KEYBOARD` requires the first tab stop
to carry a visible focus indicator, read from computed style rather than CSS source. `A11Y-AXE`
runs axe-core 4.12.1, which `agent-browser` vendors and executes offline — a rule this same commit
had first written off as "axe-core is not vendored", a second remembered fact that turned out
false minutes later. Capability probes beat recollection.

`TOK-TYPE-SCALE` stops enforcing a scale nobody derived. `12|14|16|20|24|32|48` was typed into the
file, and a project stepping 1.333 from 18px failed on every heading. It reads
`.impeccable/brand.json` when the target ships one, and reports which scale it used and where that
came from.

Mutation coverage went from 3 falsifiable rules to 6. The three still skipping name what they
need: a state fixture convention, a baseline image store, a declared lab budget.

## 1.21.0 — 2026-08-23

**Register constraint added to the shipped policy.** Reports now read as a CTO reporting to a CTO:
the fact, the number, the consequence. No commentary on the facts, which means no "funny", no
"ironic", no "the good news is", and no remarking that a defect is apt. Aptness is not a finding.
The rule applies to reasoning as well as to output, because narrating amusement costs tokens and
adds nothing to the decision.

## 1.20.0 — 2026-08-23

**Every skill now has a case asserting it fires.** `tests/auto-trigger.sh` covered half of them. The
uncovered half included `unslop` and `principle-prove-it-works`, which the shipped policy leans on
hardest — one claims to apply to every text you write, the other gates every claim of done — and
neither had ever been shown to fire. Twenty-eight cases now.

Prompts are written the way a developer would type them rather than naming the skill, because a
prompt that says "use the unslop skill" tests nothing about whether the description matches a real
situation. Eleven of the fourteen are unverified by execution and the commit says so; three were
run end to end, chosen as the pairs this repo had just disambiguated, and each fired correctly.

**The configuration is now developed with itself, as a rule.** Added to the shipped `CLAUDE.md`:
an error you hit while working in this repo is an error a stranger will hit, so it gets fixed here
and pushed rather than worked around locally. A workaround in your session is a bug report you
decided not to file. The rule earned itself inside the same run — check 12 caught this release's
own documentation still quoting the old case count against a tree of 28.

Carried forward, unfixed: `principle-prove-it-works` overlaps `create-verification-skill`,
`maintain-verification-skill` and `principle-sequence-verifiable-units`, separated only by scope.
That is a fragile axis for a model to route on and it is written down rather than quietly left.

## 1.19.0 — 2026-08-23

**`/team` writes its handoff trail, and something checks it held the bar.** The command has always
said "you route it and hold the bar" and "decide whether the next phase can start". Nothing
verified it ever did, and an orchestrator that proceeds past a failed verify is a tech lead
claiming done while the tests are red.

The trail is mandatory now and written as the run goes rather than at the end, because a log
written afterwards is a summary and a summary is what you would have said anyway. The row that
matters is the one where a phase came back broken and the lead rejected it. A log that only ever
records `proceed` is decoration.

`tests/fixtures/team-fail/` plants work that fails three of its five acceptance criteria, with no
pytest dependency so it runs on every lane. That gives ground truth without judgement: whether a
delegation was good is a matter of taste, whether the lead stopped when told the work was broken
is a fact. `tests/team-gating.sh` opens with a control, so a fixture that accidentally passes
refuses the run instead of reporting a vacuous green.

**Two things you can now see.** `bin/vstack receipt` renders the last trail. The statusline gained
a gate indicator with three states: green `shield` when this repo has a `.claude/verify.sh` and it
is trusted, yellow `gate open` when a gate exists but nothing armed it, and silence when there is
no gate rather than an implication of safety. Two of the three states are bad news, which is the
point. An indicator that only ever reports "protected" is a green that measures nothing, moved to
somewhere harder to audit.

Honest about what the trail is: it makes work visible that already happened. It does not make the
work better, and the first real one recorded seven rejections across thirteen handoffs, including
a reviewer catching a docstring that lied and a lead's own sweep finding 434 of 16142 inputs
non-idempotent. That is worth looking at. It is not evidence the configuration improves output,
and this entry does not claim it is.

## 1.18.0 — 2026-08-23

**Six skill descriptions claimed each other's work.** The descriptions are what Claude Code
matches a prompt against, so two skills sharing a trigger phrase is not a documentation problem,
it is a dispatch problem. The worst pair carried the same two literal strings: `grill-me` and
`interrogate` both said "tear this apart" and both said "what am I missing", which gives a
description matcher no way to choose. Nothing was deleted. Each pair does genuinely different
work and the defect was in the wording.

Every rewrite puts the discriminator in the first clause, because that is the part a matcher
weighs hardest and in each case it was buried or absent:

- **Does the artifact exist yet.** `grill-me` is "before the thing exists" and keeps grill me,
  poke holes, what am I missing. `interrogate` is "after the thing exists" and keeps tear this
  apart. Neither phrase is now claimed twice.
- **Before drafting versus after drafting.** `technical-writing` picks structure before a word is
  written; `unslop` is the last pass over prose already on the page. Previously
  `technical-writing`'s entire scope was a subset of `unslop`'s "any text you write".
- **Nothing exists yet versus something has drifted.** `create-verification-skill` and
  `maintain-verification-skill` had that distinction buried mid-sentence.
- **Chain order, stated as first, second, third.** `brainstorming` now excludes itself from a
  bugfix or any change whose shape is known, which is what dragged it into work it had no
  business in. `writing-plans` is second, `test-driven-development` third and explicitly includes
  bugfixes.
- **`principle-prove-it-works` generates nothing.** It said "prove this works", which reads the
  same as the skill that writes a verify.sh. It now says it is a habit, not a generated gate.
- **UI timing foregrounded.** `component-registry` before writing a component, `ui-iterate` after
  editing one with a dev server up, `impeccable` while polishing something that already renders.

Total description bytes went from 4798 to 4721, a net reduction of 77, because descriptions are
listed into every session and a disambiguation that costs context every turn is not free. Every
description stays inside the 200-character cap check 3 enforces.

What this does not claim: nothing here is measured. The collisions were found by reading the 28
descriptions, and the fixture set at `~/vstack-dispatch/fixtures.jsonl` that would measure them
has no harness yet, so there is no before-and-after activation rate and this entry does not
report one. The justification is structural — a trigger phrase now belongs to one skill instead
of two — and that is a weaker claim than a measurement.

## 1.17.0 — 2026-08-22

**Merged with `doctor`'s release-reachability check.** The v1.15.0 audit concluded that check 24
structurally cannot tell whether the tag it verifies is fetchable by a stranger, because the only
honest answer needs a network call and a gate that needs the network to be honest is a gate that
gets disabled. That conclusion was right about check 24 and wrong about the system. The
constraint is that `.claude/verify.sh` stays hermetic, not that nobody may ask, and `doctor`
already talks to the network — so the question moved there.

The distinction is worth keeping, because it applies to the other two timing dependencies as
well. Two of check 24's three are unfixable *in check 24* and neither is unfixable outright: the
remote one moves to a tool allowed to make network calls, and ref durability moves further out
still, to a git config on the machine (`fetch.prune` and `fetch.pruneTags`, both true globally)
that no check in any repository can defend against. The useful question is not whether something
can be checked but which tool is allowed to check it, and a gate that must stay hermetic is not
the whole system.

`doctor` reads DRIFT on this machine until the tags are pushed. That is the check working.

## 1.16.0 — 2026-08-22

**Check 18's anchor moved to the row's label.** Two sessions revived this check independently on
the same afternoon and the merge kept the better half of each: the floors (128 / 1024 / 512
against measured 305 / 3655 / 2178, far below the caps because they answer "did the hook say
anything at all") and the two-figure comparison from one side, the label anchor from the other.

It keys on `| Context spent per session ` and parses the figures out of that row, rather than
keying on the figures themselves. The figures are exactly what people edit — the anchor moved
twice, the second time during this audit while the fix was being written, in a commit titled
"put back the anchor my own mutation test moved". The label states what the row means and
outlives a rewrite of what the row says. Three outcomes now carry three messages: row missing,
row present with unparseable figures, figures present and wrong. Conflating the first two sends
the next reader looking for a row that is in front of them.

Row 18c is the floor's mutation. The floors were proven by a hand-run, which by this
repository's own standard is not evidence; the row stubs the hook to `exit 0` and requires all
three floors to name it.

**Dead code removed.** `declare_base() { :; }` in `tests/evals/swebench/run.sh` was defined,
empty, and called from nowhere — a stub left behind when the PASS_TO_PASS baseline moved inline.
A sweep of every tracked shell file for functions defined and never called found this one and
nothing else; the other candidates were dispatched by name from a quoted list, which the first
version of the sweep could not see.

## 1.15.0 — 2026-08-22

**The falsifiability suite had no accounting of its own.** It printed `N passed, 0 failed /
FALSIFIABLE` with no declared count and no skip line, so rows 19 and 24 could `continue` out and
the summary read exactly like a run that had proved every row. That is verify.sh's own founding
lesson, never applied to the suite that proves verify.sh. It reports `declared, passed, failed,
skipped` now and fails when they do not add up.

Its no-op detector also fingerprinted a row's files together rather than separately. Rows 1, 18
and 29 each mutate two files now — two lanes of a check that makes two promises — and a combined
hash goes on matching as long as either lane still lands, which is the exact rot the detector
exists to catch, one level finer. Per file, and it names the file that stopped changing.

**Check 16 asserted that an id was listed, not that a row existed.** An id could be added to
`CHECKS=` with no `break_it` and no `label_for` and check 16 stayed green; the omission surfaced
only when somebody ran the suite, which is the thing check 16 exists to make unnecessary. All
three arms are required now, counting an environment branch as a mutation — check 0's row strips
jq from `PATH` rather than editing a file, and that is a real way to break a check. It found a
gap on its first run.

**Check 21 printed `ok` over an empty list.** `RETIRED` ships empty, which is correct — nothing
is retired — so its loop never ran and `ok (0 entries)` read like a measurement of zero rather
than the absence of one. Skipping would have been honest and would still have measured nothing,
so it measures the decider instead, the way checks 23, 27, 32 and 37 do: a key the repository
ships right now must be seen as still shipped, and a key it has never shipped must not be
reported as having shipped.

**The last two `| grep -q` pipes in the unsafe direction.** Under `set -o pipefail` a `grep -q`
that matches early kills the writer with SIGPIPE and the pipeline returns 141. Most instances
here fail in the safe direction — 141 reads as "no match" and invents a failure somebody
investigates. Check 32's escape-hatch probe was the exception: a 141 on a match would skip the
`&&` and report a broken `VSTACK_NO_GRILL` as green. Its payload is one short line, so it never
fired, which is precisely why it would have survived until the payload grew.

**Check 31 matched basenames, so a file nobody names could pass by sharing a name with one
everybody does.** Every `README.md` in the tree counted as referenced by any mention of any
`README.md`. It matches paths now. Demonstrated with an orphan planted under `ui-gate/` whose
basename collides with a file named in eighteen places: the basename match called it referenced,
the path match does not. The path is deliberately not written out here — doing so in an earlier
draft of this entry gave the planted probe a referrer and made row 31 report "did NOT fail when
broken" while the mutation was working perfectly. Row 31's probe is now assembled as
`ui-gate/$(basename bin/doctor)` so it proves exactly that, and so the literal never appears in
the file — a name spelled out here is itself a referrer.

The tightening found one real orphan. `bin/claude-task.sh` is copied onto every machine by
`install.sh` (which ships `bin/*` wholesale) and was named by nothing in the repository, so
nothing checked it either: installed everywhere, findable nowhere. `bin/doctor` reports on it
now, beside `claude-bg.sh`. The eval corpora under `tests/evals/fixtures`, `holdout` and
`*/fixture` are excluded instead, because those genuinely load by directory — `run-pathways.sh`
points `FIX` at the directory and globs it, so adding a fixture is meant to be a file drop.

**Checks 26 and 28 answered "skip" to a missing tracked file.** Neither `.github/workflows/verify.yml`
nor `docs/` is an environment dependency that may reasonably be absent on a runner; they are
files in this repository. The workflow being gone means CI is gone and the README's platform
promise has no evidence behind it; `docs/` being gone silently retires this check and two rows
inside check 12. Both are failures now. Legitimate skips are unchanged: check 19 when the Claude
CLI is absent, check 24 with no tags, check 29 without shellcheck — each names the missing
dependency, and each is a thing a runner may honestly lack.

**Check 24 could only fail after it was too late to act on.** It compared `v$version..HEAD`, so
before a commit HEAD *was* the tag, the diff was empty, and it printed `ok declared version
matches what installs (v1.14.0)` with modified payload files sitting in the working tree. After
the commit — identical file contents — it went red. Nothing about the artefact changed between
those two runs, only which side of the commit boundary the person stood on. Both directions
observed on this branch and independently by a second session on main the same afternoon.

It reads the working tree now, staged and unstaged and untracked, so it bites while the bump is
still cheap. A `git stash` still hides payload from it; that is stated in the ok line rather
than solved, because the only honest answer to "somebody hid the evidence" is to say what was
looked at. The ok line also now says the tag is local and that no remote was consulted — the
check verifies the tag exists here, not that the URL the README hands a stranger resolves.

**`tests/evals/run.sh` is deleted rather than repaired.** Its gstack arm used `find "$GSTACK_DIR"
-maxdepth 2 -name SKILL.md`, which matches gstack's root SKILL.md at depth 1 and copies the whole
repository in as one nested skill, and it installed gstack at project scope where its references
to a global skills directory are all command-not-found. Two other harnesses had already been
fixed; this one was missed.

It was not repaired because its question is answered and the answer is recorded — 11/15, 11/15,
10/15 across none, vstack and gstack, with zero skill invocations in sixty runs.
`run-pathways.sh` exists specifically to record that this result is spent: a neutral prompt about
a single file reaches neither harness's front door, because vstack ships `/review` as a command
and gstack ships it as a slash-triggered skill. Repairing it means porting `activate_arm`,
`deactivate_all`, `backup_machine`/`restore_machine` and the positive control, producing a third
copy of the block that mutates the operator's real `~/.claude` — the most dangerous code here —
to serve a benchmark that still could not answer the question. It also lacks the
`FIXTURES=dev|holdout` selector `optimize.sh` drives, so it cannot join the optimisation loop.
The finding stays in RESULTS.md; the harness does not need to stay runnable for it to stay true.

Check 38 is what makes that deletion bite. Check 20 already asserts that `~/`-rooted install
paths named in prose exist; the repo-relative direction never had a check, so a doc could point
at a script that is not there and nothing would say so. Confirmed against the real deletion:
with `tests/README.md` at its pre-deletion content, check 38 reports `names evals/run.sh, which
is not in this repository`.

**The optimiser had never run, and its scorer could not tell zero from no data.** `--try`
hard-exits without `.opt-state`, and `.opt-state` has never existed, so the accept/revert/noise
branch and the `MIN_GAIN` threshold beneath it had never once executed. `MIN_GAIN` is now
labelled what it is: a stated default of 0.05, uncalibrated, described in the header as "wider
than the run-to-run spread observed here" when no run in this repository measured that spread.
Calibrating it means three unchanged `--measure` runs; with `SAMPLES=3` over 8 fixtures a single
f1 step is about 0.029, so 0.05 is the right order of magnitude and that is the most that can
honestly be said for it.

The scorer collapsed three situations into `0 0 0`: a run that genuinely scored zero, a run that
produced no rows, and a run whose fixtures planted no defects. Only the first is a result. The
other two read as f1 0.0000, which makes the delta hugely negative, trips the revert branch, and
tells you a good change made things measurably worse — a broken harness arguing against a
correct edit. They are distinct verdicts now and the three call sites refuse to score them.

Check 37 drives both halves offline, at no model cost, and found a real defect in the boundary
while doing it: `0.55 - 0.50` is `0.050000000000000044`, so a bare `d > g` called exactly
`+MIN_GAIN` a keep. Which side of the threshold a change landed on depended on the bit pattern
of two decimals rather than on the measurement.

**Check 12 scanned eight files, chosen by hand.** The list had grown by hand every time somebody
noticed a miss — `tests/README.md` and `docs/how-skills-fire.md` were both late additions, and
`tests/evals/RESULTS.md` was the next one waiting to be noticed. That is the shape check 29
removed one check over: a list you have to remember to update is a list that goes stale silently,
and the remembering is the part that fails. It is derived now, from every tracked markdown and
manifest: 8 files to 133.

Two trees are excluded, under one rule — a document whose numbers are evidence about something
other than this tree's shape today. `docs/provenance/**` is dated internal handoffs;
`docs/research/**` is published evidence about other systems, where a sentence counting the
agents in somebody else's benchmark is not a claim about this tree, and holding it to this
repository's count is a category error rather than a finding. That is still an exclusion somebody maintains, and it is two directories with a stated
rule instead of eight filenames with none — an improvement, not a solution.

A derived set can shrink to nothing and pass by scanning nothing, which is the failure this
check exists to catch turned on itself, so the set is asserted before it is used. The prose
extractor also gained a `$`-guard: `claude/commands/release.md` contains `TYPE=$1` above `case
$TYPE in`, which normalises to `$1 case` and matched `[0-9]+ case` against a tree of 14.

**compare-baseline printed six comparisons and made five.** Its `row()` took an expected value
that could be spelled `-` meaning "assert nothing", and exactly one row used it: the per-session
context cost, which is the number the README publishes and therefore the row that most deserved
an expectation. A row proving nothing printed identically to a row proving something, and
`exit "$FAIL"` stayed 0 however far the number drifted.

The escape hatch is deleted rather than fixed, because a ceiling inside `row()` would need a
fifth grammar parsed out of a display string — `~3.6 KB full / ~2.1 KB plugin` is not a number
and never will be. `row()` displays and counts; `expect` and `expect_max` assert and count; the
footer fails when the two counts disagree. The cost row now carries a real ceiling on the raw
byte count (`CTX_MAX`, default 6144), leaving the rounded KB figures for display only.

The accounting found a seventh row nobody had noticed was unasserted, on its first run.

**Three eval harnesses opened their run log by destroying it.** `printf '<header>\n' >
"$RUNLOG"` truncates unconditionally. That is harmless for the default, where `RUNLOG` lands in a
fresh mktemp directory, and destructive the moment a caller passes `RUNLOG=` to accumulate across
arms — which is required, because one model-calling arm does not fit in a single invocation. Each
arm overwrote the arm before it, exit status stayed 0, and the summary reported the survivor as
the whole experiment.

It has already cost data rather than merely risked it. `.audit/run/falsedone-*.tsv` retains nine
rows, all `arm=vstack`; the twelve-run `none` baseline quoted in
[do-harnesses-help.md](docs/research/do-harnesses-help.md) has no surviving raw rows. Nothing
noticed, because destroying data and succeeding look identical from outside.

`tests/evals/lib/runlog.sh` now owns the opening: empty counts as new (`optimize.sh` passes a
freshly `mktemp`'d file, so a refusal keyed on `[ -f ]` rather than `[ -s ]` would break the
optimiser on its first call), a matching header appends, a foreign header refuses with rc 2.
Check 36 exercises all four and then bans the truncating redirect outright under `tests/evals/`,
because the line was copied into three harnesses and the thing worth preventing is the fourth.

## 1.14.0 — 2026-08-22

**ui-gate reported OK over nothing, and doctor --drift reported no drift over nothing.**
`./ui-gate/ui-gate.sh docs` printed `9 declared, 0 ran, 0 passed, 0 failed, 9 skipped` and then
`UI GATE OK`, exit 0 — the accounting rule above it is satisfied at RAN=0, and FAILED is 0
because nothing ran to fail. That is the defect the file's own header says this repository
exists to catch, reproduced in the summary written to catch it. The floor is RAN, not PASSED:
browser rules skipping for want of playwright is honest, but every rule skipping means the
target has no interface in it, and a UI gate over a target with no UI is a category error rather
than a pass. It now prints `UI GATE NOT RUN` and exits 2, following the file's own precedent
where 2 is "could not run" and 1 is "rules failed".

`doctor --drift` had the same shape one tool over. Its five family globs are each `[ -e "$f" ]
|| continue` guarded, so a `$REPO` that resolves but ships no skills — a moved checkout, a
partial clone, a stale pointer — compared 28 installed skills against nothing and printed
`no drift ✔`. Measured: against a stub whose families are all empty, the old code exits 0
saying no drift; the new code names all five families and exits 1. It also reports the count
now (`no drift ✔ (73 item(s) compared)`), because a comparison that does not say what it
compared cannot be audited. The resolve-failure branch one layer up had already learned this;
the loops beneath it had not.

Check 35 holds both, in both directions, because a gate that always refuses is worth exactly as
much as one that never does. `ui-gate/mutations.sh` gained the same control beside its clean-
fixture baseline.

**Check 18 published two promises and kept one.** The half that compares the README's context-cost
figure against the live byte count was guarded by a grep for `~N KB full / ~N KB plugin` — a
sentence that `cc76ba8` reworded into a table row in the same commit that severed it. An `if` with
no `else` does not go red when its anchor stops matching; it goes quiet. The assertion was
unreachable for four releases while the check kept printing `ok`. It was also check 18's only
lower bound: every other assertion is an upper cap, so a hook emitting zero bytes satisfied all
three and printed `ok injected context bounded (digest 0 B, baseline 0 B)`. The anchor is now the
current table row, a missing anchor is a failure rather than silence, and both bounds are
asserted. The published 3.6 KB figure was, as it happens, still accurate — which is the point:
nothing had been checking, and nobody could have known.

**Check 29 read its delegate's silence as success.** `shellcheck ... 2>/dev/null` inside a command
substitution discarded stderr and never read the exit status. `shellcheck -S nonsense -f gcc
install.sh` writes nothing to stdout and exits 4, so a shellcheck that could not run at all
produced `ok shellcheck clean (33 scripts)`. It now reads the exit status per file — 0 and 1 are
answers, anything else means the question was never asked — and carries the two-way positive
control check 19 uses, linting a known-bad script and refusing to believe a clean result unless
the linter can still find that defect.

**One file selector where there were four.** Checks 1, 12, 29 and 30 each spelled "the shell
scripts in this repository" separately, as a copied shebang scan. All four missed
`ui-gate/rules/browser.sh` and `ui-gate/rules/tokens.sh` — real bash, sourced by `ui-gate.sh`,
carrying a `# shellcheck shell=` directive and no shebang because they are never executed
directly. Nothing in the gate parsed them and nothing linted them, in the one subtree that exists
to catch a gate reporting OK over nothing. This is the second miss for that predicate;
`bin/cloudflare-mcp` was the first, and is why the shebang scan replaced a hand-maintained list.
The fix is not a third spelling. `sh_files()` covers suffix, shebang and directive, and the
selector went from 33 files to 35.

Rows 1, 18 and 29 of `tests/gate-falsifiability.sh` now mutate both lanes each, so no half of a
two-part check can rot unproven the way check 18's figure comparison did.

What this does not yet support: the three fixes above were each watched going red under their own
mutation before being made green, but the falsifiability suite fingerprints a row's files
together, so it detects both lanes of a widened row rotting and not one of them. Per-file
fingerprinting is not in this release.

## 1.13.5 — 2026-08-22

**`doctor` now asks whether a stranger can actually fetch the release we claim to ship.** Check 24
proves the declared version is tagged *in this repository*. It cannot prove the tag exists on the
remote, because that means a network call and the gate has to stay offline and hermetic. So the
question moved to `doctor`, which already talks to the network.

It was not academic. Every tag from v1.13.2 on lived only on this machine while README.md handed
strangers a URL built from it — check 24 green and the documented install path a 404, at the same
moment, for four releases. Two true statements about different things, and nothing compared them.

An unreachable network is a note, never a pass and never a failure. Being offline is not drift,
and it is not evidence that the release is fetchable either. No remote configured is also a note:
a repo can be local by design.

## 1.13.4 — 2026-08-22

**Two skills stopped requiring skills that are not installed.** `executing-plans` and
`writing-plans` each opened with a caveat saying sibling `superpowers:*` skills are not vendored
here, then went on to issue `**REQUIRED SUB-SKILL:** Use superpowers:<name>` eight times in their
bodies. Nothing in `~/.claude/skills` matches and no superpowers plugin is installed, so every one
of those pointed at nothing.

The wasted turn is the cheap part. The expensive part is that an agent told something is REQUIRED,
which then turns out not to exist, learns that REQUIRED is soft, and carries that inference into
every other mandatory instruction in the set. A word that means "you must" has to be reserved for
things that are there. Where the target is vendored here the prefix is simply dropped
(`superpowers:writing-plans` becomes `writing-plans`); where it is not, the directive is now plain
prose describing the work to do.

**The README publishes its context cost in a form the gate can still read.** Check 18 compares two
published figures against a live probe of the session hook, guarded by a grep for
`~N KB full / ~N KB plugin` with no `else` branch. The README stopped using that phrasing at
cc76ba8 and the comparison silently stopped happening, while the check went on printing `ok` for
eleven commits. The figures are back, verified falsifiable, and the cell now carries a comment
naming what depends on it. That is a mitigation; the missing `else` is the actual bug and is not
fixed here.

Also newly stated: the per-prompt digest costs 305 B on every turn, which over a long session
costs more than the session baseline does once, and both published figures are measured outside
Conductor. Inside a workspace the baseline is 712 B smaller, because the hook skips its
workspace-conventions block when `CONDUCTOR_WORKSPACE_PATH` is set.

**Research.** [docs/research/harness-value-literature-2026-08.md](docs/research/harness-value-literature-2026-08.md)
surveys roughly 70 published sources on whether a configuration-layer harness beats an unconfigured
agent. On frontier models nothing published says it improves correctness, and two independent nulls
at honest baselines say it does not; what the config layer measurably moves is cost and behaviour.
[docs/research/what-we-changed-2026-08-22.md](docs/research/what-we-changed-2026-08-22.md) records
what that licensed and, more usefully, the changes it did not.

## 1.13.3 — 2026-08-22

**The policy document no longer ships as a second CLAUDE.md.** v1.13.2 stopped the hooks from
firing twice but left this: `~/.claude/CLAUDE.md` and a repo's `.claude/CLAUDE.md` held identical
bytes, one loaded as user memory and one as project memory, so the whole document sat in context
twice in every overlaid repo. Nothing could dedupe it from inside — Claude Code reads both files
itself and no hook runs in between.

So the overlay ships `.claude/hooks/policy.md`, which is not a memory path and is read by nothing
but the session hook, and the copy that already knows whether it is the only voice in the room
decides whether to speak it. A sandbox has no `~/.claude`, so the overlay carries the policy
there; on a machine with the user-scope install it appends nothing. `overlay.sh` deletes any
`.claude/CLAUDE.md` it finds, because an overlay that merely stops writing leaves every repo it
already touched duplicating forever.

The condition is "is the user-scope copy live", not "is suppression on". `VSTACK_DUPE_SUPPRESS=0`
exists to get the digest back while debugging; if it also handed back a second policy it would
hand back the bug.

Check 34 is now "the policy document reaches a session exactly once", asserted in both
directions — zero copies in a sandbox is a repo that lost its operating policy silently, two on
this machine is what started this. `VSTACK_OVERLAY_CLOUD` is gone with the heuristic it gated.

## 1.13.2 — 2026-08-22

**The overlay was injecting itself twice.** Claude Code merges hook arrays across settings layers
rather than overriding them, so every repo carrying the committed `.claude/` overlay ran
`~/.claude`'s injector and its own: session baseline, per-prompt digest and the whole of
`CLAUDE.md`, twice per turn. Seven repos on this machine were doing it, and nothing caught it —
`install.sh` dedupes within user scope and has no way to see across scopes.

Deleting the committed copy is not available: a cloud sandbox clones the repo and has no
`~/.claude`, so that copy is the only lane config reaches it by. The project copy stands down
instead, and only while the user-scope copy is registered and doing the job. Escape hatch:
`VSTACK_DUPE_SUPPRESS=0`.

`CLAUDE.md` cannot be handled that way — Claude Code loads both files itself and no hook runs in
between. So `overlay.sh` writes the project copy only where a sandbox could ever clone it, and
clears a stale one otherwise. An overlay that merely stops writing leaves every repo it already
touched duplicating forever. Override with `VSTACK_OVERLAY_CLOUD=1|0`.

`doctor` gains `── hook scope overlap ──`, which runs both copies for real instead of grepping for
the guard, and asserts the user-scope one still speaks — testing only the silent side would rate a
wholly broken script as healthy. It looks at worktrees as well as main checkouts: coverage is a
property of the committed tree, double-firing is a property of the file on disk.

Checks 33 and 34, both falsifiable. 36 total.

## 1.13.1 — 2026-08-22

**Instance handles on every agent**, adapted from [oh-my-pi](https://github.com/can1357/oh-my-pi).
Its `generateTaskName()` gives each spawned task a two-word `AdjectiveAnimal` identifier so its
agent roster can tell concurrent instances apart. That is a different axis from a call sign: the
call sign says which role spoke, the handle says which instance. When `/team` runs five reviewers
over one diff, both are needed. Each agent now coins a handle at the start of a run and signs
`REDLINE · SwiftFalcon`.

**First head-to-head run on a fair gstack arm.** Four arms, four SWE-bench Lite instances, arms
installed one at a time in the real home the way each project says to install it.

| arm | resolved | median | total |
|---|---|---|---|
| none | 4/4 | 83s | 474s |
| gstack | 4/4 | 94s | 492s |
| vstack | 4/4 | 97s | 536s |
| vstack-default | 4/4 | 103s | 924s |

Every arm resolved every instance, which by this project's own rule is a harness problem rather
than a finding: four arms agreeing perfectly means the instances do not discriminate. The
pre-flight admits an instance when its environment builds and its target tests genuinely fail, and
that is not a difficulty filter. No harness beat the unconfigured baseline, and all three added
latency to it.

The one signal worth keeping is that it is recorded and not believed yet: `vstack` on the Concise
output style totalled 536s against `vstack-default` on Default at 924s. A single instance supplies
almost all of that gap (273s against 572s), so it is one observation, not a result.

## 1.13.0 — 2026-08-22

**The engineering team is code now, not copy.** Six new subagents bring it to 14: `product-owner`
writes acceptance criteria and an explicit out-of-scope list, `qa` exercises the real artifact
against them, `ui-engineer` builds to the tokens already in the repo, `accessibility-auditor` runs
axe per state and walks the tab order by hand, `performance-engineer` measures before and after and
reverts anything inside the noise floor, and `release-manager` refuses to ship unverified work.

`/team <goal>` runs the loop and holds the bar between phases. It will not let work reach
`release-manager` until `qa` has exercised it, because a passing unit test is a different claim.

The mechanism is the argument. A virtual engineering team built as Markdown instructions to one
conversation is one context that can talk itself out of its own findings. Fourteen subagents each
have their own context window, tool allowlist and model, so a reviewer cannot be argued down by the
conversation that produced the code.

**Each agent carries its own standards.** Not a shared checklist: a dossier of what that role
judges against and what it rejects. `ui-engineer` has a type scale, a 4px spacing base, semantic
colour tokens, motion durations, and a list of things to reject in its own output.
`accessibility-auditor` has the WCAG 2.2 AA rules that actually come up, in frequency order.
`performance-engineer` has budgets with numbers and a rule that anything inside the measured noise
floor is not a result. `code-reviewer`, `security-auditor`, `qa` and `design-reviewer` likewise.
The point is opinionated defaults a reader can disagree with specifically, rather than a general
instruction to do good work.

**Call signs.** Each agent signs its report: SCOPE, ATLAS, SCOUT, PIXEL, MULE, HARNESS, PROOF,
REDLINE, WARDEN, LOUPE, RAMP, STOPWATCH, ROOT, SHIPWRIGHT. The frontmatter `name` stays functional,
because that is what dispatch routes on and a human name carries no routing signal. The call sign
makes a report attributable and a follow-up routable.

**Concise output style, and auto-upgrade.** `outputStyle` is now `Concise` and
`autoUpdatesChannel` is `latest`. Concise needs CLI 2.1.237 or later, which the stable channel did
not have. It lives in the system prompt, so it is cached, unlike the per-prompt register line it
replaces, and it keeps error reports and destructive-action confirmations verbatim.

## 1.12.1 — 2026-08-22

`bin/doctor` classifies `autoMode`, `editorMode` and `verbose` as user-scope. The CLI sets them,
not this repo, so `--drift` was right to notice them and wrong to leave them unclassified.

Community health files: CONTRIBUTING, SECURITY, a pull-request template, dependabot for actions,
and CODEOWNERS. `LICENSE` is pure MIT text again, with the mixed-license note moved to `NOTICE`,
so GitHub classifies the repository as MIT rather than "other". GitHub Releases now exist for
every tag; six were bare.

The benchmark's arm switching was rebuilt and is now testable for free with `SELFTEST=1`. Three
defects came out of that, described in the commit: `./uninstall.sh` does not deactivate, the
backup was 1.6 GB per run, and restoring `~/.claude` alone left the CLI wrappers missing.

## 1.12.0 — 2026-08-22

**README rewritten, 469 lines to 226.** It now opens on the comparison against
[gstack](https://github.com/garrytan/gstack), which is the closest comparable project and the
obvious thing a reader is deciding between.

The comparison names four differences that are checkable rather than asserted: vstack configures
the machine rather than only the prompt, its gate is mutation-tested so a check cannot be added
without proof it can fail, uninstalling restores what was there, and it publishes its own broken
measurements. It also says plainly what gstack does better, which is breadth, multi-agent support
and a conventional unit-test suite.

What it does not do is claim a benchmark win. The only vstack-versus-gstack number this repo ever
produced came from a gstack arm whose helper scripts did not exist on the machine that ran it, and
a README is not the place to launder a retracted result.

The gate rejected four things in the first draft, which is the argument for having it: two
sentences whose phrasing collided with the documented-count scanner, an omission of the
`alpine:latest` runner that check 26 requires the platform claim to name, and a docs link that
check 28 needed and the rewrite had dropped.

## 1.11.0 — 2026-08-22

**grill-me fires on its own.** Two triggers, both decidable in the UserPromptSubmit hook without
judgement: the first substantive prompt of a session (120 characters or more, so "fix this typo"
does not open an interview), and any prompt of 320 characters or more, on the grounds that a
prompt that long is a plan whether or not it says so. `VSTACK_NO_GRILL=1` turns it off,
`VSTACK_GRILL_CHARS` moves the long threshold.

Deliberately not a Stop-hook mandate. Blocking the end of every long-prompt turn that did not
grill would fire constantly, and this setup already records the rule it runs on: a guard that nags
gets switched off, which is worse than one that is merely probable.

Check 32 tests it on its decisions in both directions, the way checks 23 and 27 test the
destructive guard and the skill mandate. It also measures the fired digest, because check 18 only
ever probed the unfired one — a grill line that blew the 512-byte budget would have gone unseen.
Measured at 312 bytes. The fixtures are built to length rather than written and hoped over: the
first draft came in at 120 and 169 characters against thresholds of 120 and 320, and the check
reported two failures that were its own.

**Non-Claude harness instructions removed.** `impeccable`'s hook and live references carried
Cursor, Codex and GitHub Copilot branches; `brainstorming`'s visual companion carried Copilot and
Gemini CLI launch paths; `executing-plans` named Codex as an alternative; the doctor command's
description advertised Codex glue. This bundle targets Claude Code and nothing else, so an adapter
branch is not a feature, it is a claim the repo does not honour. Attribution mentions stay: those
record where a skill came from, which is a different thing.

**LICENSE detects as MIT again.** The file carried a mixed-license attribution paragraph after the
MIT text, which defeats GitHub's SPDX classifier — the repo showed "other" rather than MIT. The
paragraph moved to NOTICE, which already exists for exactly this.

## 1.10.0 — 2026-08-22

**Two skills added, both wired to fire on their situation.**

`grill-me`, from [mattpocock/skills](https://github.com/mattpocock/skills) (MIT). A round-based
interview that maps a plan as a decision tree and works the frontier one round at a time, asking
every currently-answerable question with a recommended answer attached.

Upstream splits it in two: a seven-line `grill-me` stub that sets the frontmatter flag opting a
skill out of model invocation, forwarding to a `grilling` skill that holds the method. A skill
opted out of model invocation cannot auto-fire — it is reachable only by typing the slash command
— so porting the stub would have shipped the one thing it is carried here to do. The method ships
directly under the name the marketplace page uses, and check 3 fails if that flag ever comes back.

`find-skills`, from [vercel-labs/skills](https://github.com/vercel-labs/skills) (MIT). Searches
the open agent-skills ecosystem when the user asks whether something can be done, so a capability
that already exists is not written from scratch. It drives `npx skills`, which this repo does not
vendor; the port says so at the top of the skill, which is what check 22 requires.

Both descriptions were written to the 200-character listing cap rather than trimmed to it
afterwards. The first drafts came in at 238 and 261 and check 3 caught both: a description past
the cap is truncated in the listing, which is exactly how a skill silently stops firing.
`claude/CLAUDE.md` names the two situations directly, since that file is the always-on routing
line. Upstream's `agents/openai.yaml` files are dropped from both — this bundle targets Claude
Code and nothing else.

Both are measured, not assumed. `tests/auto-trigger.sh` grows to 14 cases, and the find-skills
case is the interesting one. The obvious prompt to write was "Find a skill for reviewing pull
requests"; it fires 3 of 3 on opus and 0 of 3 on sonnet, which is the model the suite pins,
because sonnet routes it to `review-pr` — the domain in the sentence names an installed skill and
the request reads as asking for the work rather than for the search. A domain with no competing
skill lands 3 of 3 on both. That limit of description-based dispatch is written into the case
rather than hidden by a blander prompt.

Skill count 26 → 28. Test cases 12 → 14.

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
descriptions carry their own triggers. `auto-trigger.sh` measures that landing on 14 cases, which
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
VMs, separate profiles — got all 28 skills and every hook written into a directory Claude Code
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
