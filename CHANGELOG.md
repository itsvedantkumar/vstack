# Changelog

Versions follow [semver](https://semver.org). The version lives in two manifests,
`.claude-plugin/marketplace.json` and `claude/.claude-plugin/plugin.json`, and check 13 of
`.claude/verify.sh` fails when they disagree.

## 1.69.0 — 2026-09-03

- **The breadth retirement was measured, and held.** Paired rerun on the three-file fixture,
  Opus 5, ten per arm: vstack spawned nothing, twenty of twenty green, vstack $0.245 against bare
  $0.275 (`tests/evals/showcase/RESULTS.md`, "After retiring the breadth mandate").
- **The showcase harness gained `gate` and `oracle` arms and a fixture with visible tests.** Both
  arms run under the OpenCode engine only and play `verify-gate.sh`'s part from outside the
  process: run the agent, run a verifier, feed a red result back into the same session, cap 3.
  `gate` uses the fixture's own `verify.sh`; `oracle` uses the held-out check and reports only
  which one failed. Rows carry `gate_rounds`. `traps/multi_module_tested` is `multi_module` plus
  a visible `tests/` and `verify.sh`. Why: the only false completions measured so far were bare
  GLM on the test-less fixture, and vstack's hooks do not load in OpenCode
  (`docs/research/harness-effect/findings/opencode-stop-gate-feasibility.md`).
  Measured: with visible tests, 40 of 40 green and no round fed back; test-less, bare against
  oracle at 150 per arm, 299 of 300 green, no false completion, no round fed back. Bare GLM on
  that fixture is 2 false completions in 200 runs across batches; the gate has not yet been
  exercised on a live run.
- **The delegation breadth mandate is retired.** Since 1.66.0 the Stop hook forced a fan-out once
  a turn had written into two directories with two extensions. Measured against bare Claude on a
  three-file fix (`tests/evals/showcase/RESULTS.md`, the routing-cost table), the runs where it
  fired cost 3.6 to 4.4 times as much and took up to six times as long, for no correctness gain;
  the runs where it stayed silent matched bare cost. `skill-mandate.sh` keeps counting
  directories and extensions into its log row and no longer blocks on them. The rule that
  replaces it is the one the `swarm` skill already states and the per-prompt digest and
  `CLAUDE.md` now say: reads, searches and reviews fan out as wide as they split; edits stay
  serial on the lead, one writer per file. The naming, swarm-first and serial-tail mandates are
  unchanged; each fires only after a dispatch happened. Falsifiability row 27b goes with the
  condition it mutated; `tests/test-breadth-mandate.sh` and `tests/mandate-cases.sh` now pin
  silence where they pinned a block.
- **Orchestration and planning pin to Fable 5.1.** The `planner` agent's model is `fable`, and
  `CLAUDE.md` says the lead does phase sequencing, dispatch and synthesis on it; judgment agents
  stay on Sonnet, mechanical ones on Haiku.
- **A held-out benchmark against gstack and bare Claude, and its null.** `tests/evals/showcase/`
  runs bare, vstack and gstack arms scoped by project config under `claude -p`, scores each run
  against checks the agent never sees, and adds a bare GLM 5.3 Flash arm through OpenCode. Fifty-
  one Opus and Haiku runs: correctness parity, zero false completions in every arm, cost within
  noise unless vstack delegated. Seventy-five GLM runs: two of forty three-file runs said `DONE`
  on a red check, the first non-zero count. The README carries the table and the null; the
  literature behind the next changes sits in `docs/research/harness-effect/` with an adversarial
  second reading beside each file.

## 1.68.0 — 2026-09-03

- **`overlay.sh --check` reports drift without writing.** Every file the write path would
  touch is compared against the payload and reported as `stale`, `absent`, `legacy` or
  `differs (repo-owned)`; exit 1 on anything the next `overlay` run would change. Overlaid repos
  can now learn that the template moved. (#10)
- **`tests/inventory-contract.sh --write` re-points the inventory.** Replaces the hand-run jq
  after every payload commit; refuses on a dirty tree, re-validates, prints the commit line, and
  is a no-op when the contract already holds. (#9)

## 1.67.0 — 2026-09-02

- **A security toolchain ships with the overlay.** `claude/security-scan.sh` runs gitleaks,
  semgrep, osv-scanner, zizmor and eslint locally and is copied into every overlaid repo, where
  the `verify.sh` template calls it; a scanner that is not installed skips rather than failing, so
  the gate does not go red on a machine missing five binaries. `claude/security.yml.tmpl` and
  `claude/dependabot.yml.tmpl` are seeded once into `.github/workflows/security.yml` and
  `.github/dependabot.yml` and never overwritten — a second `vstack overlay .` reports whether the
  file still matches the template or has drifted from it, and names the file to diff against.
  `setup-machine.sh` installs the scanners by default.
- **Check 64 measures it in both directions.** The scan is run in a throwaway repo with
  `PATH=/usr/bin:/bin` (every tool must skip, exit 0) and again against a stub gitleaks that
  reports a finding (must exit 1 naming it), because a scan that can only ever skip passes the
  first lane perfectly. 64b requires every `uses:` in the workflow template to be pinned to a
  40-hex commit with its tag beside it, and requires README's Prod-ready gates table and the
  script to name the same tools. Falsifiability rows 64 and 64b delete the skip branch and unpin
  one action.

## 1.66.0 — 2026-09-02

Auto-enforcement tightened after measuring it. Across ten real sessions in the last ten days the
Stop gate got 94% compliance whenever it fired, but it fired on almost no turns: 72% of turns ran
with zero Agent and zero Skill, 65% of edit-turns had neither, and one active workspace ran with
the hooks not reaching it at all. The gate was not loose; it was retiring early and skipping cases.

- **Skill mandates now re-arm.** unslop, typescript-best-practices, prove-it-works and register
  used a plain counter with no window, so two misses latched each one silent for the rest of the
  session. They now re-arm after `VSTACK_SKILL_RESET_SECS` (default 1800), exactly the windowed
  reset the four delegation mandates have run on since 1.63.0 without over-firing. This is the
  mechanical cause of "the gate stops triggering."
- **The breadth mandate gates two-directory work.** The fan-out mandate required `dir>=3 AND
  ext>=2`; a two-directory, two-extension cross-cutting edit was never gated. Lowered to `dir>=2
  AND ext>=2`. The AND with the extension floor stays, so a three-file edit inside one file type
  is not gated, because a guard that nags a legitimately serial change gets switched off.
  `tests/test-breadth-mandate.sh` gains PROOFs 27 and 28 for the new boundary; `tests/
  delegation-drift.py`'s eligibility mirror tracks the same threshold.

## 1.65.1 — 2026-09-02

- **bootstrap.sh resolves the latest release without the GitHub API.** 1.65.0 made an unpinned
  bootstrap look up `releases/latest` on api.github.com, unauthenticated, and refuse when that
  returned nothing. On the first push after the release the Linux install-matrix job did exactly
  that: a shared Actions runner IP is rate-limited on that endpoint, the resolver came back
  empty, bootstrap refused, and main went red while the macOS job with identical code was
  green. The resolver now asks `git ls-remote --tags` first (git protocol, no API quota), picks
  the highest `vX.Y.Z` numerically (no `sort -V`, which busybox lacks), and falls back to the
  API only without git, sending `GITHUB_TOKEN`/`GH_TOKEN` when one is set. Refusal without a
  fallback to main stays. The install matrix's curl lane now carries bootstrap's last output
  lines into its FAIL line, because the cause of this red was captured and thrown away, and
  the three CI install-matrix steps pass `GITHUB_TOKEN` through.

## 1.65.0 — 2026-09-02

The public-readiness audit's three P2s, plus the leftovers it turned up.

- **bootstrap.sh no longer installs the default branch when unpinned.** It resolves the
  latest release tag from the GitHub releases API and refuses when that lookup fails, rather
  than falling back to `main`. A stranger who runs the one-liner now gets the version the
  manifests and changelog describe, not whatever landed since.
- **The context7 MCP server is pinned** (`@upstash/context7-mcp@4.0.4`) instead of floating on
  `npx`'s latest, so a re-install cannot silently pick up a different server than the one that
  was reviewed.
- **uninstall.sh leaves nothing behind.** It removes `vstack-compat-canary.json` (written by
  the compat-canary hook, so ownership follows the hook, not the installer) and `rmdir`s the
  now-empty `agents/reference`, `agents`, `commands`, `hooks` and `skills` directories,
  deepest first, so a directory holding anything foreign is left alone. The install matrix's
  `uninstall-clean` lane fires the real hook first so the file genuinely exists before it
  asserts on its absence.
- **The session baseline names the operator.** `inject-session-context.sh` derives the
  human's name from `git config vstack.operator`, falling back to `git config user.name`, and
  says that RICK is the lead's call sign, not theirs. A reply opening "Rick:" had been read as a salutation. Nothing shipped carries a
  literal name.
- **README puts the install command on the first screen** and states what distinguishes this
  repository before the counts.
- Repository settings: secret scanning and push protection enabled; three stale branches
  deleted.

- **install.sh no longer arms the Stop-hook verify gate on a non-interactive install with no
  opt-in.** It ran `bin/vstack trust "$SRC" --yes` unconditionally, so bootstrap.sh's
  `curl|bash` one-liner — which drives install.sh non-interactively — left a stranger who never
  read a line of the repo with standing unattended-execution rights over `.claude/verify.sh`
  (which itself runs `install.sh --dry-run` and `overlay.sh`). Every other repo's gate stays off
  until `vstack trust` runs there and its terminal confirmation is answered; a bare
  non-interactive install of this repo now gets the same refusal. Arms on an interactive
  terminal (`[ -t 0 ]`) or an explicit opt-in (`--trust`, or `VSTACK_TRUST=1`); otherwise prints
  how to arm it later. Check 61b in `.claude/verify.sh` proves the non-interactive,
  no-opt-in path leaves the trust store without this repo's entry — regression-tested against
  `git show origin/main:install.sh`, which fails the same assertion.

## 1.64.0 — 2026-09-02

- **format.sh no longer mistakes a prettier devDependency for a prettier config.** The grep
  for `"prettier":` matched the version pin in dependencies/devDependencies, won the
  package.json slot ahead of a sibling .prettierrc, and cosmiconfig silently fell back to
  built-in defaults — files reformatted to the wrong style. The hook now JSON-parses
  package.json for a genuine top-level key, falling through to .prettierrc when node is
  absent or the file does not parse. Repro: `tests/repro/formatter-config-devdep.sh`.
  (PR #7)

## 1.63.0 — 2026-09-01

Three branches merged in queue order: auto-enforcement, skill-autofire, register-mandate.

- **Delegation pressure is automatic.** The Stop hook gains a serial-tail mandate, the
  session-context hook a live escalation line, and the per-prompt digest re-pins fan-out.
  (`claude/hooks/skill-mandate.sh`, `claude/hooks/inject-session-context.sh`)
- **Skill descriptions re-keyed on measured fire rates.** 100 published model calls, Fisher
  tests, no early stop: executing-plans keyed on a-written-plan-exists (1/10 → 6/10,
  p=0.0573, moved but not significant), test-driven-development on about-to-write-code,
  writing-plans on nothing-written-down, swarm's quoted trigger strings dropped.
  Description-collision score 23 → 13, zero hard-fail pairs. Harness and run logs in
  `tests/evals/autofire/`; `tests/description-collision.sh` and
  `tests/dispatch-static.sh` gate the corpus offline.
- **REGISTER rule enforced.** New banned-opener mandate in the Stop hook: a reply opening
  with an acknowledgement token ("Let me", "Great", "You're right", …) draws a strike on
  the skill family's 2-strike latch, current turn only, both apostrophe forms. Fixtures
  in `tests/mandate-cases.sh` (cases 13–15), PROOFs 25–26.
- **Routing table matches the shipped descriptions.** `inject-session-context.sh` lines
  220–221 now key TDD and executing-plans the way the descriptions do; this closes the
  standing disagreement with the `executing-plans-checkpoints` fixture.

## 1.62.0 — 2026-09-01

### Coverage that reads the overlay, not the toml

**doctor's coverage verdict measured the wrong artifact.** The "active repos overlaid" predicate
was one line: `.conductor/settings.toml` exists. A repo with that file and no committed `.claude`
at all scored as covered, and a repo fully served by the global `~/.claude` lane scored as a
failure. Measured live before the change: `ok (8 scanned)` over eight repos of which zero were
cloud-ready. The check now classifies every active repo into the classes defined in
`docs/config-precedence.md` -- cloud-ready, half-covered, stale, hooks-disabled, local-only --
and the same live run reports every one of the eight for what it is. A vstack checkout itself
(claude/settings.json plus overlay.sh at the root) is the source, not a target, and is excluded.

**A repo-local `disableAllHooks` silences the whole global stack.** Established by experiment,
not docs: one committed line in `.claude/settings.json` stopped every user-scope hook in the
session, verify gate included. doctor now flags it as its own failure class. The experiment also
settled two standing questions: memory files load additively (global, root, and `.claude/`
CLAUDE.md all reach the session), and hook arrays merge across scopes rather than shadow, so an
overlaid repo with fewer per-event commands loses nothing. The protocol and raw artifacts are in
`docs/config-precedence.md`.

**overlay.sh bumps a stale conductor pin.** `.conductor/settings.toml` was written only when
absent, so its pinned vstack SHA never moved: five real repos carried four different pins, all
behind HEAD, and every new cloud sandbox bootstrapped an old vstack. A re-run now rewrites
exactly the `/vstack/<sha>/bootstrap.sh` substring to the overlaying checkout's HEAD. A setup
line the operator replaced wholesale has no such substring and stays byte-identical; a missing
`trust --yes` prints as a hint, never a rewrite.

## 1.61.0 — 2026-09-01

### Three defects this release shipped, found by the first CI run that could see them

The pre-tag red masked them. Every lane was already failing on "declared release is fetchable"
before it got far enough to fail on anything else, and the release workflow read that as a verdict
and deleted the candidate tag three times. Pushing the branch and the tag atomically closed the
window, and what was underneath was three real faults.

**The carve-out could never fire.** `bin/doctor` closes with `DRIFT ✖` whenever its fail count is
non-zero -- a generic summary that name-collides with a real drift banner and carries no
diagnostic content. `tests/container-matrix.sh` stripped the allowed finding's own line and left
that one, so with `declared release is fetchable` as the SOLE failure the residual was still
non-empty and every image reported `doctor exit=1; DRIFT ✖`. Row 62b proved the list and the
`bin/doctor` branch. Nothing proved the filter against real doctor output, which is the third time
here that both halves were tested and the join was not. Dropping the banner softens nothing, since
each finding prints its own `✖`, but the banner had been acting as an accidental guard, so the
guard is now explicit: the allowed finding must actually appear, or a doctor that fails while
printing nothing would pass.

**Check 63 could only ever skip in a container.** `tests/container-matrix.sh` installs bash, git,
jq, curl, ca-certificates and shellcheck, and never python3. The skip classifier accepts a reason
only if it matches `plugin manifest|authenticat|claude CLI`, so all three images failed on the
classification -- debian's gate printed VERIFIED and the lane still failed, which is the classifier
working correctly. Adding "python3 not on PATH" to that keyword list would have been a false label
on a skip that has nothing to do with credentials, and laundering a skip that way is the
regression `tests/container-skip-classify.sh` PROOF 4 exists to stop. The tool is provisioned
instead.

**Check 61 hid its own error.** It went red on Alpine and nowhere else, reporting only
`vstack trust failed` because the call ran with `>/dev/null 2>&1`. Two reproduction attempts
against a byte-identical image could not make it fail, and `shasum` was ruled out, all against
evidence discarded at the source. With stderr kept, Alpine said it in one line: `no vstack repo
found (checked $VSTACK_DIR, ~/.vstack, and this script's git root)`. The check redirects HOME so
each lane writes its own trust store, which also hides `~/.vstack` and the gitconfig holding
`actions/checkout`'s safe.directory exemption, so git refuses the checkout and `bin/vstack` exits
before `trust` runs. Naming `$VSTACK_DIR` settles it. The check's own environment, not a defect in
what it measures -- but a check that knows something is wrong and throws away the sentence saying
what belongs in the catalogue's subject matter, not beside it.

### The eighteenth entry in the catalogue, and the first that inherited a red

`tests/install-matrix.sh` asserts the installer leaves no trace of the machine that built it, with
`grep -rqI "$SRC"` over the installed `settings.json`. A substring search for a path matches every
path that merely starts with it. Running the suite from a worktree at `/tmp/rel61` with
`TMPDIR=/tmp/rel61tmp` turned five lanes red, all reporting `repo path leaked into settings`. The
installer had leaked nothing: the fake HOME lived under `/tmp/rel61tmp`, so every hook path in
`settings.json` carried `/tmp/rel61` as a prefix, and the check was recognising its own scratch
directory.

Seventeen entries in `docs/checks-that-inherit-their-answer.md` inherited a green. This one
inherited a red, and it cost the same thing: a verdict the check had not measured, acted on. A
release was held and an installer that was never broken was diagnosed for twenty minutes.

The match is now anchored on a path boundary -- the next character must be `/` or `"`, every shape
a leak takes in JSON and not the shape a sibling directory takes -- and `-F`, so a checkout path
containing a regex metacharacter is matched as itself. `assert_install` now also plants a `$SRC`
path in a scratch file and requires the detector to fire on it, because a narrowing that stops
detecting anything looks exactly like an installer that stopped leaking.

### install.sh armed the gate over code it had not trusted

`vstack trust` records `.claude/verify.sh` plus every literal `.sh` path that file executes, its
`source`/`.` refs and package manifests: 34 entries in this repository. `install.sh` recorded one.
`.claude/verify.sh` runs `./install.sh --dry-run` and `./overlay.sh`, so anyone who installed the
normal way armed a Stop-hook gate whose entry point was pinned and whose code was not.

The failure could not report itself. `verify-gate.sh` iterates the entries the store *has* and
compares each hash, so a file that was never recorded has no line to mismatch. It is not refused,
it is invisible. Only "trusted once, edited since" produces a refusal, which is the one case the
narrow writer could still handle. Editing `install.sh` or `overlay.sh` after installing ran
unattended on the next Stop with nothing raised.

Two writers for one boundary was the defect. `install.sh` now calls `vstack trust` and fails
closed with a named warning if it cannot. New check 61 asserts the delegation exists and then
exercises what it delegates to in both directions: a synthetic repo whose gate runs
`./scripts/ci.sh` must get `ci.sh` recorded, a repo whose gate runs nothing else must get exactly
one entry, and this repository must record `install.sh` and `overlay.sh` by name. The negative
lane is the load-bearing one: without it, lane 2 passes on a writer that records every `.sh` it
can find, which is a different boundary wearing the same output.

### The tag this release destroyed, twice

`bin/doctor`'s "declared release is fetchable" does a live `git ls-remote` for the version the
manifests declare. `verify.yml` triggers on the commit that declares it, and the tag is a separate
ref pushed seconds later, so `install-matrix` and `container-matrix` run inside a window where the
manifests already say v1.61.0 and origin does not yet carry the tag. On 2026-09-01 `install-alpine`
started three seconds after the tag push, re-queried origin later still, and went red. `resolve`
read `conclusion=failure`, called the gate decided, and `cleanup-on-failed-gate` deleted the tag
whose absence was the entire finding. Re-pushing the same tag object destroyed it a second time,
because the old conclusions still stood.

`require-checks-green.sh`'s staleness carve-out did not fire and was right not to: it excuses a run
that STARTED before the candidate existed, and this one started after. The margin is not the
defect. Asking a commit-triggered lane about a tag is.

`tests/pretag-findings.sh` names that one finding, and the two harnesses read it from there rather
than each spelling it. Fetchability is still gated in the lane that can answer without a race:
`release.yml`'s `resolve` exists because the tag was pushed, and `container-matrix` clones at the
tag. New check 62 requires the list to stay at one entry, both harnesses to keep reading it, and
`bin/doctor` to go on reporting the same label as a hard failure -- row 62b downgrades it inside
doctor and leaves the list alone, which is the mutation a check on the list by itself would miss.

Also corrected here: README said the parallel sweep takes "about 20 minutes". That is CI's figure
on seven runners. Locally it is 48 minutes, measured over 103 rows on 2026-09-01.

### The one path install.sh edits rather than creates

Check 20 models installed paths as copies of repo files or as runtime state. `~/.zshrc` and
`~/.zshenv` are neither: they already exist, belong to the user, and `install.sh` appends a fenced
block to each. A path the check could not express is a path README's "What lands where" table was
never asked about, so the table listed every rule the installer has and still omitted the one edit
a stranger would most want warned about. `install_appended` is now a third category, floored the
same way the second is: each entry must appear in `install.sh` as a literal append, and row 20d
deletes the append to prove the floor fires.

### Also

`README.md:51` described the plugin lane as shipping "two routing hooks". It ships three, and
`goal-gate.sh` gates rather than routes. The Credits link pointed at `pstack-dev/pstack`, which
404s; pstack is `cursor/plugins/tree/main/pstack`, © Lauren Tan, and the vendored
`claude/skills/LICENSE.pstack` is byte-identical to upstream's.

## 1.60.0 — 2026-09-01

### The lane that was added to close a rot was itself unproven

1.59.0 taught check 12 the noun "falsifiability rows", after four releases of README and three
other files publishing a row count that was 6 to 9 short of the live one. Row 12 breaks a README
*table* cell, so it exercises only the table extractor. The prose extractor, `want_for`'s noun
map, and the count each noun resolves to are a separate lane, and nothing broke it. New row 12b
falsifies the prose claim directly, anchored on the phrase rather than on the number, since the
number is the thing that moves.

Adding the row moved the row count, which the new noun then caught in five files at once. That is
the check working, and it is the reason the number is worth deriving rather than writing down.

## 1.59.0 — 2026-09-01

### Three files published three different counts for the same catalogue

`README.md` said eighteen, `docs/what-this-actually-does.md` said thirteen, and
`docs/checks-that-inherit-their-answer.md` headed its own list "The seventeen". All three were
live claims about one document, and the gate was green through all of it. Check 12 compares
published counts against the tree, but its extractor matches digit+noun only, so a spelled-out
number is invisible to it, and this figure has no tree to count anyway: its subject is prose.

The real count is seventeen. Sixteen of those entries printed `ok`; the seventeenth printed an
accurate `FAIL` that the release workflow then acted on by deleting the tag whose absence was the
finding. The catalogue disagreed with itself by one because a coverage-gap note about
`tests/install-matrix.sh` sat among the instances and was counted as one. That note now lives
under its own `## Named, not counted` heading, so the instance boundary is a property of the
document's structure rather than an exclusion someone has to remember.

New check 60 derives the number from the catalogue and requires every marked publication site to
agree. Publication sites carry an HTML-comment marker, and the check states its own hole: a new
doc that publishes the figure without the marker escapes lane 2. Lane 3 closes that for the file
that matters by requiring the marker in `README.md`. Row 60 plants an extra entry in the counted
section, anchored on the section boundary rather than on the spelled number, since the number is
the thing that moves.

Also corrected: `CODE_OF_CONDUCT.md` said eighteen, which no reviewer had spotted.

## 1.58.0 — 2026-09-01

### The goal command shipped without its reader

`claude/commands/goal.md` has always described itself as "Only stops when fully verified". It
could not do that. A command is text injected the moment you type it, and nothing read the
`.goal/<slug>/goal.md` file it writes: `grep -rn '\.goal' claude/hooks/` returned zero matches.
The writer shipped and the reader never did, so a recorded goal had no effect on any later turn
and the agent stopped as soon as the immediate request was answered. Four releases carried the
promise; none carried the mechanism.

- **New Stop hook `claude/hooks/goal-gate.sh`.** Blocks finishing while a `.goal/*/goal.md` has
  unchecked items under its `## Rubric` heading. Wired into both lanes: `claude/settings.json`
  for the full install and `claude/hooks/hooks.json` for the plugin. It reads markdown and never
  executes anything out of the repo, so unlike `verify-gate.sh` it needs no `vstack trust` entry,
  which is why it can live in the plugin lane at all.
- **Three narrowings, each load-bearing.** Only the `## Rubric` section is read, because a
  `## Residuals` box is by definition work its author handed to a human. A goal whose `Status:`
  says complete is never reopened. An item tagged `(needs: user)` is reported and never blocks.
  Without these the gate blocks forever on work the agent cannot do, which is a livelock, not
  persistence.
- **The 3-block cap goes open, not shut** — deliberately opposite to `verify-gate.sh`'s B-12 fix.
  A red test is always fixable by the agent, so that gate keeps blocking. An unchecked box may
  not be, so this one stands down with a `systemMessage` naming what is still open. Different
  asymmetry, different direction.
- **`mkdir` is the attempt counter.** Numbered directories claimed atomically, so concurrent
  Stops from parallel sub-agents each take a distinct number. `verify-gate.sh` had to grow a
  spin-lock around an unlocked read-modify-write to get the same property.
- **Check 59** drives the hook on five synthetic repos and asserts the decision each time, plus
  the cap engaging at exactly 3 and both lanes naming the hook. Falsifiability row `59` inverts
  the gate's one predicate, flipping both directions at once.

## 1.57.0 — 2026-08-31

### A mandate for delegation that one serially-dispatched agent satisfied

`skill-mandate.sh` blocks when work spreads across three directories and two file types and no
subagent was dispatched. The condition was `task_count -eq 0`, a flat count of every Task/Agent
block anywhere in the transcript, so one agent sent on its own cleared a rule whose entire subject
is doing the work concurrently. A serial loop and a parallel batch produced identical counts, and
check 27 never built a fixture with more than one dispatch in it, so nothing could tell them apart.

It now counts batches. `fanout_batches` folds the transcript into maximal runs of CONSECUTIVE
assistant records sharing a non-null `.message.id` and counts runs holding two or more dispatches.
Consecutive matters: in one 29701-line transcript, 3097 distinct ids spanned 3105 contiguous runs
because 8 ids reappear thousands of lines later after compaction, so a global grouping would merge
two unrelated turns into one inflated batch.

The same shape defeats measurement from outside. Claude Code streams each tool_use block as its own
JSONL record, so counting Agent blocks per record scores a four-agent batch as four solo dispatches
and returns 0.0 fan-out on every input ever. Measured both ways over the same 1008 dispatches: 0.0
per record, 53.0% per run.

> **AMENDMENT, 2026-09-01 (v1.61.0), left in place rather than edited.** `tests/transcript-census.sh`
> now exists and recomputes these figures. The 0.0-per-record half reproduces exactly and is
> structural, as claimed. **The 53.0% per-run half does not reproduce under any denominator.**
> Over the corpus today: 4.8% of dispatching turns were batches, 12.3% of dispatches went out in
> a batch, 8.6% of dispatching sessions contained one, 5.4% per turn when subagent leaves are
> folded back in. The dispatch count reproduces only with those leaves included (1040 today
> against 1008 then, consistent with corpus growth), so the published denominator was
> leaf-inclusive and this paragraph does not say so.
>
> No denominator was searched for until one flattered the figure; all four are printed by the
> instrument on every run, which is why the disagreement is visible at all. What 53.0% measured is
> unrecoverable -- the number was published with no instrument, so there is nothing to re-run.
> That is the whole argument for `docs/checks-that-inherit-their-answer.md`, turned on this
> repository's own changelog: a figure nobody can recompute cannot be wrong in public, and this
> one was wrong for two weeks.

### Every dispatch now routes through the swarm skill, and the mandates stopped sharing a fuse

Measured across 2536 transcripts and 20508 assistant tool-using messages: 516 Skill invocations,
2.52 per 100. (Reproduced 2026-09-01 by `tests/transcript-census.sh`: 2536
transcript files, 21114 tool-using messages, 520 Skill invocations, 2.46 per 100, `brainstorming`
still exactly 23, the three named skills still exactly 0.) Three skills shipped by this repository have never fired once -- `writing-plans`,
`test-driven-development`, `executing-plans` -- and they are links 2, 3 and 4 of a single chain the
session digest stated in one line. Link 1, `brainstorming`, fired 23 times. Routing took the first
step and stopped, so the line is now four lines with mutually exclusive preconditions: nothing
written down, written with no test, failing test against a plan.

`swarm` joined the mandate. Dispatching without calling it now blocks. The latch that would have
undone this is split per mandate: it was one counter per family, and f4f5468 already measured that
bleed one level up, where two early skill mandates disarmed the delegation mandate for a whole
session while a forced re-scan read dir_count=36, ext_count=61, task_count=90. Adding `swarm` as a
fourth sibling on a shared counter would have meant two unrelated naming strikes silencing it.

### A guard anchored on another file's prose, disarmed by editing that prose

The `VSTACK_PROFILE=skills` branch carried two `sed -e` clauses quoting the routing heredoc's own
sentences verbatim. Rewriting those sentences orphaned both patterns: the sed still ran, matched
nothing, changed nothing, and every gate stayed green. Three things touch that branch and none
reads what it emits -- check 18 and `compare-baseline.sh` count its bytes, check 47 asserts exit 0
and valid JSON. The dead clauses are gone. Nothing yet asserts that a substitution keyed to prose
still matches that prose; that check is designed and deliberately not shipped here.

### The policy budget had one byte left and said nothing about it

Check 34 caps the session block an overlaid repo pays on every session. The cap was 7168 with a
comment claiming ~280 B of headroom from a 6886 B reading. Measured at v1.56.0: **7167 B**. Every
one of those 280 bytes had been spent across intervening releases while the check reported `ok`,
because a threshold reads the same at 1 byte of margin as at 280 and can only speak once the margin
is gone. The headroom is now printed on every run, so erosion is visible while it happens. The cap
is 8704, carrying this release's two policy rules (+825 B after compression) with ~625 B left.

### Isolation became observable; batch membership is not, and is not faked

`dispatch-counter.sh` recorded nothing about whether a dispatch was concurrent or where it worked,
so two rules this release states in policy were unmeasurable after the fact. It now records `cwd`,
`isolation` and `run_in_background`, all confirmed present in the PostToolUse payload against the
CLI's own schema rather than assumed, plus one field named `derived_prev_dispatch_gap_s` that is
labelled derived because it is. A parent-message identifier is NOT on that payload -- verified
twice against the object literal that constructs it -- so batch membership still cannot be
recovered from the shipped logs. It travels on `PostToolBatch`, a different event this matcher
never receives. Recording something plausible in its place was the available shortcut and is
exactly the defect this repository exists to catch.

Row width grew 223->313 B minimal and 251->394 B realistic, putting post-rotation size at ~1.5-1.9
MB against a documented 1-1.5 MB. The comment stating the old figure is corrected in the same diff
that invalidated it. Rotation stays bounded at 2 MB; the slack it runs on is smaller.

### The tag this version first tried to ship on

`v1.57.0` reached origin, `container-matrix` failed in all three container lanes, `publish` was
skipped, and `cleanup-on-failed-gate` deleted the tag. That is the designed behaviour: the tag is a
candidate, and a failed required job cannot produce a published tag. This section describes the
re-cut.

The fixture that failed asserted that breadth plus ONE dispatch leaves the mandate hook silent,
which is precisely what this version's two new mandates block. Two fixture sets cover this hook,
check 27 in `.claude/verify.sh` and `tests/container-matrix.sh`. Only check 27's was updated when
the hook changed, so the maintained copy went green and the stale copy was the one that runs in no
workflow except `release.yml`. The first signal available was a cancelled release.

Case 9 now calls `swarm` and dispatches two Agent blocks in one assistant record, the only shape
`fanout_batches` counts. `9b` and `9c` add the blocking direction for each rule. Both were watched
failing under a mutation before being trusted.

**Still open, stated rather than fixed.** `container-matrix` runs only in `release.yml`. This
release was verified by running it by hand against `main`, which the harness supports because it
clones from published GitHub at `$VSTACK_REF` rather than from a working tree. Nothing yet stops
the next hook change from repeating this.

### The log did not record the variable the hook decides on

Moving the breadth mandate onto `fanout_batches` left the delegation log writing only `task_count`.
`tests/delegation-drift.py` reads that log, so its primary metric scored a session as delegated on
`task_count>=1` while the live hook blocked that same session for having no batch. The study and
the hook it studies could not be reconciled, and no gate said so.

`fanout_batches` now travels on both log rows, passed as an existing shell variable into the
existing `jq` call, no new fork. The latched row carries `null`, matching its siblings. Missing,
`null` and `0` are three different facts and the source says so.

The study is amended, not rewritten. The pre-registered sentence stays, marked stale and dated;
`delegated()` becomes `any_dispatch()` so the published series keeps one name for one computation;
the metric keyed to the real suppression condition is added over only the rows carrying the field,
printing its own N. Rows without it are excluded, never scored zero, because every row written
before the field existed lacks it and counting those as "no batch" would print a collapse that is
an artifact of when the field was added. The live run reports n=0 with 94 windows excluded.

The invalidation list covered changes to dir/ext counting but not to the suppression condition
itself, which is how this went unnoticed. It covers that now.

### The sweep harness orphaned its own children

`tests/falsify-parallel.sh` backgrounded N shards and never killed them. A dead parent left them
running the gate with nobody collecting results; one orphan was measured alive 3h22m against a
comparable 20 minute run. The old trap made it worse by deleting the workdir the shards were still
running inside.

`kill_tree` walks the `ps` pid/ppid table and kills leaves first, escalating to KILL after a one
second grace only when a TERM was actually delivered, so the normal path does not pay a second per
shard. `INT` and `TERM` get handlers that call `exit`: a single `trap ... EXIT INT TERM` runs its
body on a signal and then resumes the interrupted statement, so Ctrl-C reaped the shards and then
left the script polling inside a directory it had just deleted.

`FALSIFY_TIMEOUT_S` bounds the run, 3600 by default, and reports `NOT RUN` with exit 2 rather than
any verdict. A sweep whose parent has died is otherwise indistinguishable from one still working,
and that, not the wasted CPU, is what makes it dangerous. `tests/falsify-parallel-reap.sh` proves
it in about half a minute without running the real sweep.


## 1.56.0 — 2026-08-31

### The release gate waited two hours for a job that now takes eighteen minutes

`REQUIRE_CHECKS_WAIT_SECONDS` bounds how long `resolve` waits for `verify` to decide. It has been
wrong twice in this repository, both times because the falsifiability suite grew and the comment
beside the number did not: 1500s against runs of 27 to 70 minutes, then 5400s against runs of 63
to 93, where v1.51.0 gave up eight seconds before the run it was waiting for went green.

1.55.0 sharded the sweep and `verify` fell to 17m49s (run 33361832175, whole-run wall clock,
against 82-98 minutes unsharded). That left 7200s stale in the other direction: a hung run cost
two hours before anyone was told. It is now 3600s.

Re-deriving it by hand is what failed twice, so check 58 derives the floor from the tree instead.
The slowest falsify shard runs `ceil(rows/shards)` mutation rows plus the 3 rows every shard
repeats, at 75s each after 300s of checkout and install, and the ceiling must clear twice that.
Both historical failures go red under it: unsharding the sweep demands 15000s, and doubling the
row count demands 5100s. The 75s comes from the slowest shard of that run, 1034s over 16 rows.

The re-derivation query in release.yml's comment was itself stale, which is the same defect one
level up. It read the job named `verify`, and since 1.55.0 that job is a 4-second join over the
shards, so it reported 4s. It now reads the run.

The first draft of check 58 hardcoded PER_ROW=75 and FIXED=300 from that run, and two independent
reviews said the same thing: a constant inside the checker, justified by a run that already
happened, is the defect being fixed, moved one level down into the thing doing the checking. One
of them named the mechanism that makes it bite. Every falsifiability row runs the WHOLE gate, so
per-row cost is a function of the gate's own size, and this repository adds a check most releases.

So PER_ROW is no longer a constant. `claude/inventory.json` records the measurement with the run
id AND the check count it was taken at (65s per row at 58 checks), and check 58 scales it by the
gate size it finds. Adding checks to `.claude/verify.sh` now raises the floor it derives, without
anyone remembering to. Rows 58b and 58c falsify both halves: raise the recorded per-row cost and
the check must go red, remove the check count it was measured at and it must refuse rather than
silently freeze at the size it was measured on.

FIXED stays an assumption and is now labelled one. A single run gives one equation for two
unknowns, and that run's two 16-row shards took 1034s and 690s, so per-row cost varies by row and
fixed cost is not separable from it.

### The sweep that gates every release took two hours to run locally

`tests/falsify-parallel.sh` runs `gate-falsifiability.sh` across isolated clones on the same
round-robin split CI uses: about 20 minutes instead of over two hours. The clones are not an
optimisation. Rows mutate tracked files in place, so two sweeps sharing a tree would each read the
other's mutation as a concurrent edit and the restore-integrity guard would refuse, correctly.

It refuses on a dirty tree, because a clone carries HEAD and the verdict would silently be about a
different tree than the one you are looking at. And it reconciles the row ids the shards printed
against the derived list, so N shards each green over a partial list fails instead of passing.

`tests/README.md` claimed the sweep "runs offline in about 30 seconds". Same class as the ceiling.

### A latency budget in milliseconds is a claim about the machine, not the code

`dispatch-counter.sh`'s header stated a "~25ms p95 budget this hook is held to" and recorded that
folding three `jq` calls into one restored it. Nothing re-derived that figure, and it does not
hold: `tests/hook-latency.sh` measures the hook at 26-123ms p95 depending only on what else the
machine is doing.

The first version of that suite gated on absolute milliseconds and duly reported three hooks over
budget while seven falsifiability shards ran on the same box. `skill-mandate.sh` moved 171ms to
858ms with no code change. That is this repository's founding defect holding a stopwatch: a verdict
correct about the question it asked, where the question was scoped to the machine it ran on.

Budgets are now in fork-cost units, each hook's cost over a single `jq` fork timed immediately
before that same sample, interleaved rather than once up front so a mid-run spike moves both. Two
back-to-back runs under identical load: raw means moved 1.6x, normalized means moved 1.01-1.02x.
The old millisecond figures are kept as non-gating reference values purely to report divergence,
and this run reported two hooks where the ms budget would fail and the unit budget passes.

Disclosed rather than smoothed: `skill-mandate.sh` forks several `jq` processes per call, so under
heavy contention its tail inflates super-linearly against a single-fork baseline, and one run put
it over budget on p95 alone. The budget was not loosened in response.

### dispatch-counter.sh's log rotation had never been executed by a test

It and `skill-mandate.sh` carry independent copies of the same 2MB cap and `tail -n 5000` rewrite.
PROOF 5 of `tests/delegation-drift.sh` pins its hook variable to `skill-mandate.sh`, so one copy
was exercised and the other only read. PROOF 13 drives the other one.

Two things a naive fixture would get wrong, both read off the hook's source rather than assumed.
It is a PostToolUse hook, so stdin is a tool payload and not a transcript fixture. And its size
check is sampled every 20th dispatch rather than run on every write, so the counter is pre-seeded
to land the dispatch on a checked count instead of silently skipping the path under test.

It asserts more than "the file shrank": the padding rows carry an incrementing sequence, so a
rotation that kept the OLDEST rows fails, and the freshly appended row must survive, so one that
dropped the append while keeping old padding fails too. Both pass a bare size check while
destroying exactly the data rotation exists to protect.

## 1.55.0 — 2026-08-31

### v1.54.0's own check 50 hung CI for 78 minutes by running the gate inside the gate

v1.54.0 taught check 50 to admit a job that is fanned into a required check rather than named by
it, and to prove each one by execution: extract the required job's `run:` script, fill the
`${{ needs.X.result }}` templates with success except for the job under test, and require a
non-zero exit.

It executed the first `run:` block of *every* required job. `install-macos`'s first `run:` block
is `./.claude/verify.sh`. So the gate ran itself, once per candidate job, and each nested gate did
it again.

It passed locally and shipped. `$RUNNER_TEMP` is unset on a workstation, so that block's
`> "$RUNNER_TEMP/gate-macos.txt"` redirect failed and the line never executed. On a runner
`RUNNER_TEMP` is set; an extracted block carries no `set -e`, so a missing `brew` on ubuntu simply
carried on into the recursion. All seven falsify shards and `verify-core` sat in progress for 78
minutes before the run was cancelled. v1.54.0 was tagged but never published.

Two fixes, because the second is what makes the first checkable. A required job whose script never
mentions `needs.<x>.result` cannot be gating on one, so it is refused without being run; and every
extracted script now runs under a 20-second watchdog, since a real join is still someone else's
shell and this gate must not be the thing that hangs.

Check 50 now self-checks its own executor before trusting it to answer anything: it calls the
executor with `install-macos` against a sandboxed `RUNNER_TEMP` and requires both a refusal and an
empty sandbox afterwards. The empty sandbox is the part that matters. Returning the right number
while still having run the block is exactly the bug that shipped, and only the sentinel can tell
those apart.

Row 50d narrows the guard rather than deleting it. A deleted guard would recurse inside the
falsifiability suite too, and a row has to make the gate go red, not make it never return.

## 1.54.0 — 2026-08-31

### The falsifiability sweep took 63-93 minutes because every row re-ran the whole gate

`tests/gate-falsifiability.sh` mutates one file per row and then runs all 57 checks to see which
one goes red. At 92 rows that is O(rows x checks) wall clock for O(rows) of information, and it
was the whole reason the `verify` job took over an hour. `REQUIRE_CHECKS_WAIT_SECONDS` has been
set below that job twice, and one of those came eight seconds from failing a release.

The scoping mechanism already existed (`VSTACK_FALSIFY_ROWS`, documented in the script since it
was written) and CI called the script bare. `verify` is now a join over `verify-core` and a
7-way `falsify` matrix, which should put the workflow around 18-20 minutes.

Sharding a gate whose entire purpose is complete coverage invites the failure this repository
exists to catch: N shards each reporting green while some row ran in no shard at all. The shard
assignment is derived from the one `CHECKS=` line check 16 already polices, round-robin so every
index lands in exactly one shard with no remainder bucket, and `falsify-reconcile` re-derives
that list independently and diffs it against the union of ids the shards' own output says they
ran. Not the ids the matrix intended to send: the ids the tool reported.

### A job could be fanned into a required check without being gated by it

`verify` cannot require the shards by name. `falsify` is a matrix job, so its check-runs are
named `falsify (0, ...)` and a required context spelled `falsify` matches nothing, which
`require-checks-green.sh` reports as MISSING forever. That is the deadlock check 50's second
direction already exists to prevent, so the join has to be admitted to the model.

It is not admitted on the strength of a `needs:` edge. A job can sit in `needs:` and have its
result ignored: with `if: always()` the dependent runs regardless, and echoing a result reads it
without acting on it. Check 50 now proves each one by execution. It extracts the required job's
own `run:` script, fills the `${{ needs.X.result }}` templates with success everywhere except
the job under test, and requires a non-zero exit. The all-success run is the positive control,
without which a join hardwired to `exit 1` would "prove" every job gated.

Falsified both ways: deleting one job's assertion from the join reports exactly that job, and
changing the join's final `exit "$rc"` to `exit 0` reports all four.

### install-matrix counted doctor's failures off the rendered display

Three predicates, three wrong answers. `grep -c '✖'` counted the trailing `DRIFT ✖` verdict
alongside the findings it summarises, reporting one real failure as two. `grep -c '✖.'` skipped
the verdict only because its glyph happens to land at end-of-line, and dropped a real failure
besides: drift has no finding line at all, its only appearance in the display *is* the verdict.
Measured on one checkout, `failCount` 1 and `drift.status` "drift" -- two failures, counted as
one.

`bin/doctor --json` already published `checks[]`, `failCount`, `drift`, `healthy` and `exitCode`,
so the display is not parsed any more. The count is `failCount` plus drift deliberately:
`bin/doctor` sets `EXIT_CODE=1` on `$FAIL -ne 0 OR DRIFT_STATUS = drift`, but `failCount` carries
only `$FAIL`, so a drift-only failure is a real red that `failCount` alone reports as zero. An
absent or unparseable `--json` is reported as unknown, never as green.

## 1.53.0 — 2026-08-29

### Two readers of the trust store reported "trusted" on a checkout the gate refuses to run

`vstack trust` records more than `.claude/verify.sh`. It records every `install.sh`, `overlay.sh`,
`uninstall.sh` and `bootstrap.sh` at the repo root, plus every path verify.sh sources, because
verify.sh is the entry point and not the blast radius. `claude/hooks/verify-gate.sh` re-hashes all
of them before it lets anything run.

`bin/doctor` and `claude/statusline.sh` hashed the entry point alone. Append one line to
`install.sh` and the gate refused with `install.sh changed since it was trusted`, while doctor
printed `trusted` and the statusline rendered its green `shield` on every turn. The report and the
decision it claims to describe disagreed, and the operator reads the report.

Check 57 could not see it: its fixture only ever wrote `.claude/verify.sh`, so all three programs
were being asked about the one file they agreed on. It now also plants a recorded companion, in
both directions (recorded and unchanged must still read trusted). Its gate classifier matched only
the `skipped untrusted` refusal and read the `refused to run` refusal as trusted, which is how a
disagreement got reported as a broken fixture.

Both readers now re-check the gate's whole recorded set, skipping absent files exactly as the gate
does. One extra spawn regardless of file count: `shasum` takes many operands and emits the store's
own format, so one `grep -vxF` against the store lists precisely the drifted files.

### A failed timestamp lookup could delete the release tag

`.github/workflows/release.yml` read the candidate run's `created_at` with
`$(gh api ... 2>/dev/null || true)`. That timestamp is what tells a pre-tag conclusion apart from a
live verdict. A transient failure of that one unretried call emptied it, and the 2026-08-27
incident shape then resolved `FAILED` instead of `STALE`, which returns `DELETE` and force-pushes
`git push origin :refs/tags/$TAG`. The fix for that incident had a path straight back into it.
The lookup now follows the convention `require-checks-green.sh` already used two files over: a
failed read is `UNDECIDED`, exit 2, tag kept, and the log names the call that failed.

`should-delete-candidate-tag.sh` also modelled only `container-matrix = failure`. A job hitting its
own `timeout-minutes: 45` reports `cancelled` and fell through to a `no required job failed` line
that was not true. The verdict stays KEEP, deliberately: a timeout is an ambiguous non-answer, not
evidence the images are broken. Only the log was lying.

### The replay log recorded dispatch descriptions verbatim

`claude/hooks/dispatch-counter.sh` byte-counts prompt and result because a replay log full of
verbatim text is a place secrets land. `description` was carved out on the reasoning that it is a
label, not content. Nothing enforced that: it is unconstrained free text on the Task schema, and a
dispatch described as `rotate credential sk-ant-...` put the credential in the log. It is now
`description_bytes`, like its two neighbours. Redaction was rejected: any pattern list is
incomplete, and an incomplete filter ships false confidence where a byte count cannot leak at all.

### `uninstall.sh` silently removed no MCP servers when `$HOME` contained `&` or `|`

Third instance of one defect. `$HOME` was interpolated into a `sed` *replacement*, where `&`
expands to the match and `|` was the delimiter. A `|` made sed exit 1, the downstream
`jq -s ... 2>/dev/null` parsed nothing, and vstack's MCP entries stayed registered while uninstall
reported success. Fixed the way `install.sh:841` and `bin/doctor` already were.

The first version of that test passed with the bug still in place: this machine has the real
`claude` binary on PATH, so `install.sh`'s plugin probe pre-creates `~/.claude.json`, and
uninstall's unrelated whole-file restore wiped the MCP servers no matter what the sed did. The
lane now strips `claude` from PATH so the incremental removal path is the only one running.

### A component family with no derivation was checked by nothing

`tests/inventory-contract.sh` dropped any `components` family lacking a
`regeneration.derivations` entry with a bare `continue`, and drove its member checks from twelve
hardcoded names. A planted family with `floor: 999` and a bogus member list still produced
every check clean and exit 0. The floor loop now fails and names the family, and the member
checks are driven from `.components | keys[]`, so a new family is covered by construction rather
than by remembering two separate registrations.

## 1.52.0 — 2026-08-29

### `vstack explain` printed a by-family breakdown with no families in it, on macOS only

The ownership-receipt section reports how many paths vstack claims and breaks them down by
family. The breakdown came from a `sed` using BRE alternation:

```
sed -n 's#.*/\(hooks\|agents\|commands\|skills\)/.*#\1#p' "$EX_REC"
```

`\|` is a GNU extension. BSD sed matches nothing at all with it, so on macOS the command printed

```
3 path(s) recorded as installed by vstack. by family:
  1 other (CLAUDE.md, statusline.sh, bin/*, conductor settings, ...)
```

A header promising a breakdown, an empty breakdown, and directly below it an "other" count that
was right — because the very next line uses `grep -vE`. Two adjacent lines written in two dialects
and disagreeing on one platform. Measured on `/usr/bin/sed` against a three-line fixture receipt: the BRE form
returns nothing at all, the `-nE` form returns a counted line for each family present in it.

The existing test asserted the total and the "other" count, both produced by grep, and never the
lines the sed produced. It passed on macOS against a breakdown that was never printed. It now
requires every family it plants to come back named. A repo-wide sweep of every tracked file found
no other sed relying on BRE alternation.

### A failure message named the README without reading it

`bin/doctor`'s release-reachability check reads the declared version from
`claude/.claude-plugin/plugin.json` and asks origin whether that tag exists. Its failure message
said the version was "declared and pinned in the README" -- borrowing check 24's conclusion
without running check 24. In the window between a version bump and its tag, which is exactly when
this check fires, the two disagree: the manifests said v1.52.0 while the README still pinned
v1.51.0, and the message named a version the README did not contain. It now reports what it
measured.

### An unreadable run log rendered as no run log

`vstack explain`'s run-log section piped `tail` into `jq` with `2>/dev/null` and never read the
exit code, so a log truncated by a killed process printed the section header with nothing under
it — visually identical to "no runs yet", one line below a header promising recent entries. The
section already knew how to say UNKNOWN when the file is absent; it now says UNREADABLE when the
file is present and will not parse, and still prints whichever lines did parse.

## 1.51.0 — 2026-08-29

### Two of the three things that report on the trust store disagreed with it

`vstack trust` writes one record and four things read it. Only one of them decides anything:
`claude/hooks/verify-gate.sh`, which runs a repository's own script unattended on Stop. The other
three report on that decision to a human, and two of them reported something else.

Measured against the real programs on one sandbox store:

| store | verify-gate.sh | bin/doctor | claude/statusline.sh |
|---|---|---|---|
| armed, hash current | trusted | trusted | trusted |
| verify.sh edited since trusting | untrusted | untrusted | **trusted** |
| record names a neighbouring file | untrusted | **trusted** | **trusted** |

`statusline.sh` looked for the path and never hashed anything, so a `verify.sh` edited after
`vstack trust` ran still rendered its green `shield` while the gate skipped that repository. It
renders on every turn, which makes it the most-read of the three, and its own comment said shield
means "it is trusted, so Stop actually blocks". The reason it did not hash was cost: no subprocess
on a per-turn render. Measured here, `shasum -a 256` over this repository's `verify.sh` takes 9 ms
against the 12 ms `git` call the same script already makes, so the saving bought a wrong answer
for less than one spawn.

`bin/doctor` matched with `grep -qF` where the gate uses `-qxF`, so a record for
`<path>/verify.sh.orig` contains the query for `<path>/verify.sh` and satisfied it.

Both now make the gate's query. `claude/hooks/format.sh` already did.

### Check 57, every reader of the trust store answers the gate's question

Runs the three programs for real against one store, three ways, and fails when any of them lands
somewhere the gate does not. It asserts agreement rather than spelling, so any of them may be
rewritten freely. The armed row is the positive control: without it, readers hardwired to
`untrusted` would agree on both negative rows and pass. `format.sh` is excluded and the check says
why — it shows no verdict, so there is no report to disagree with.

### An older install's credential export was removed by code nothing tested

`install.sh` states that it also takes out the `set -a`/`secrets.env` line earlier versions wrote,
so the fix reaches machines that already have it. Only the half that proves the installer does not
*add* the line had a test. The new `secrets-removal` lane in `tests/install-matrix.sh` seeds the
line into two rc files of a real installed home and requires both halves: `doctor` classifies it
as vstack's own regression, and a re-run deletes it. Falsified in both directions before landing.

## 1.50.0 — 2026-08-28

### Check 56 recognised bash 3.2's wording for an aborted script, and no other

The check runs every shipped hook with HOME, TMPDIR, USER and LANG absent and asserts that none
of them emits a shell-level error, because a hook that stops on one has not allowed or blocked
anything. It decided that by matching the text bash prints. macOS bash 3.2 says `parameter null
or not set`; bash 5 says `parameter not set`. Only the first was in the list.

So row 56b -- which breaks `format.sh` on purpose to prove the census reaches every file -- passed
on every Linux runner against a hook that aborts on line 36. It passed here too, for a different
reason: the falsifiability suite refuses to start while the gate is red, the gate was red on the
pre-tag pin, and the row was proved by hand instead. Hand-proving has no no-op detector. CI found
it on the first run where both halves could execute, and the v1.50.0 tag was withdrawn for it.

The rule is now derived rather than enumerated. A runtime error from the shell is reported as
`<the script as invoked>: line N: ...`, and nothing a hook chooses to print carries that prefix,
because it names the path this check invoked it by. Matching the prefix asks whether the shell
stopped the script instead of whether we recognise the complaint. The old substrings stay as a
union, not as the criterion: they cover a message a CHILD process wrote to the same stderr, which
carries the child's prefix and not the hook's.

Measured with the fix, three arms on both platforms: unmutated `ok`; `format.sh` broken, FAIL
naming `parameter not set` on Ubuntu and `parameter null or not set` on macOS; `verify-gate.sh`
restored to a bare `$HOME`, FAIL naming `unbound variable`.

### An ampersand in your home directory silently unregistered every MCP server

`install.sh` and `bin/doctor` both expanded `$HOME` into a sed REPLACEMENT, where `&` means the
matched text, `\` escapes, and `|` was the delimiter:

    sed "s|__HOME__|$HOME|g" mcp/servers.json

Measured 2026-08-28: a home directory whose name contains `&` registers every server with a
command path where the ampersand has been replaced by the literal text `__HOME__` -- a directory
that does not exist, so the server never starts and nothing says why. A `|` in the same position
makes sed exit with `bad flag in substitute command`. The
install side is the one that matters -- it writes the file Claude Code reads -- and doctor's copy
then compared against an equally corrupted expectation, so the two agreed and reported no drift.

Both now escape the three characters before substituting. Found by `opencode/big-pickle` reading
`bin/doctor`; it named doctor's copy, and install.sh's turned up because the new lane stayed red
after doctor was fixed.

### doctor told you a file of yours was safe to remove, if its name had a space in it

The leftover list was built by string concatenation on spaces and then re-split on whitespace, so
`~/.claude/skills/my skill` became `skills/my` and `skill`. That list decides which of two things
the operator is told: a leftover the repo used to ship and dropped, printed with "safe to remove",
or a file the repo has never had, presumed theirs. Both halves of a split name fail the git-history
lookup, so a genuine leftover with a space in it is never reported at all, and a user's own file
lands in whichever bucket the fragments fall into.

Newline-separated now, read back with `while IFS= read -r` from a here-string rather than a pipe,
because a pipe puts the loop in a subshell and both accumulators would be discarded when it exits.

New lane `install-matrix.sh doctor-names` proves all three, in a home directory that really
contains an ampersand -- asserting against a fixture string would not have caught it, because the
corruption happens in the expansion of `$HOME` itself. Falsifiable per fix: revert `install.sh`
alone and it reddens on `__HOME__`; revert `bin/doctor` alone and it reddens on both splits.

### One failed fetch retired `vstack update` on a pinned install

`update` repairs the shape `VSTACK_REF=vX.Y.Z bash bootstrap.sh` leaves behind: a shallow clone
whose only fetch refspec is the pinned tag, with no `refs/remotes/origin/main` to compare against.
It widened the refspec, unshallowed, and if that one fetch did not work, gave up.

It does not reliably work on git 2.54. With two shallow roots grafted, the pinned tag plus main's
tip from a later shallow fetch, `--unshallow` rewrites `.git/shallow` and then fails re-reading
it: `fatal: shallow file has changed since we read it`. The identical next fetch succeeds, because
the second read sees the file the first pass wrote. Debian stable-slim and Ubuntu latest ship older
git and never hit it, which is why container lane 26 failed on exactly one image of three, and why
the 1.49.0 tag was withdrawn.

Worse than the single attempt was what gated it. The fetch ran only `if [ -z "$repair_err" ]`,
where `repair_err` held the *output* of `git config remote.origin.fetch`. One warning on that
call and the repair was skipped in full, then the error below reported that origin/main could not
be resolved after a repair that had never been attempted.

Success is now origin/main resolving, not any one git command exiting 0. Four attempts in order,
stopping at the first that resolves it: unshallow, unshallow again, plain fetch, then an explicit
`+refs/heads/main:refs/remotes/origin/main` which does not need the shallow boundary dropped at
all. The last one leaves the repo shallow, so `git merge --ff-only` further down may refuse for
want of ancestry, and that refusal is a message the operator reads rather than a guess this code
makes on their behalf.

The regression test does not depend on having git 2.54. A shim ahead of git on PATH fails the
first `--unshallow` and passes everything else through, so `install-matrix.sh update-shallow` runs
offline on any git and tests the retry rather than the bug. Measured against the real repo in
alpine:latest afterwards: `rc=1`, three `full diff,` headers, the non-gate filename present, and
the checkout fully unshallowed.

### `rm -rf $HOME/*` was an ask, and `rm -rf ~/*` was a deny

Same directory, same outcome, opposite verdict, decided by which way the operator happened to
type it. `guard-destructive.sh` matched the home directory against nine literal spellings --
`/`, `/*`, `~`, `~/`, `~/*`, `$HOME`, `"$HOME"`, `$HOME/`, `${HOME}` -- and four more that erase
exactly the same tree reached only the ask tier:

    rm -rf $HOME/*      rm -rf "$HOME"/*      rm -rf "${HOME}"      rm -rf ${HOME}/*

Enumerating spellings loses to whoever thinks of a tenth one, so the guard now reduces the token
before comparing: drop every quote wherever it sits, fold `${HOME}` onto `$HOME`, then remove one
trailing `/*` or `/`. Check 23 gains those four as deny rows, watched red first, and its decision table
is now 41 rows across 3 tiers. `$HOME/Downloads` still asks, and `node_modules`, `./dist` and `/tmp/x`
still pass without a prompt: the tier that keeps the guard installed is unmoved.

Found by `opencode/muse-spark-1.2-contributor-free`. Its four BusyBox portability claims against
`failure-diagnose.sh` and `compat-canary.sh` were falsified by running the gate on a real Alpine
with no coreutils, grep or sed installed: every check but the two that legitimately skip ran,
credential redaction green, and a payload digest byte-identical to the macOS one.

Quoting the path used to change the verdict in the other direction too, and that direction is
the corrosive one. The whitelist compared the token as typed, so `node_modules` matched and
`"node_modules"` did not: every quoted build-artifact delete drew a confirmation prompt.

    rm -rf node_modules      allow          rm -rf "node_modules"    ask
    rm -rf ./dist            allow          rm -rf "./dist"          ask
    rm -rf /tmp/x            allow          rm -rf "/tmp/x"          ask

That is the tier this file's own comment calls the one that keeps the guard installed, and an
agent that quotes its paths met a dialog on every artifact delete. Both tiers now compare through
one `_gd_unquote()` helper that removes quote characters wherever they sit, which is what handles
a quote in the middle of a token. Pure parameter expansion, no subshell: this runs ahead of every
Bash command. Check 23 is 44 rows across 3 tiers.

Reported as a `TMPDIR` quoting bug by `opencode/muse-spark-1.2-contributor-free`, in the opposite
direction to the measurement. Its two heredoc claims predicted a bypass -- a delimiter with a dash
or a dot, extra spaces, `<<-` with a tab -- and all four still deny a trailing `rm -rf /`, as does
`bash <<EOF` with the delete inside the body.

### Two hooks aborted instead of deciding when HOME was absent

Check 23 runs one hook under `env -u TMPDIR -u HOME -u USER -u LANG`, because
`guard-destructive.sh` once read `$TMPDIR` with no default. Seven other hooks ship beside it and
none had ever been run that way. Two died: `compat-canary.sh` and `verify-gate.sh` both expand a
bare `$HOME` under `set -u`.

`verify-gate.sh` is the Stop hook, and the line that died is the trust-store lookup deciding
whether this repo's `verify.sh` may run unattended. Aborting there is not a wrong answer, it is no
answer: the runtime gets a shell error where a decision belongs. Both now read `${HOME:-}`, so with
no HOME the lookup resolves to a path that does not exist and nothing is trusted, which is the
direction that gate has to fail in.

`compat-canary.sh` also wrote its state file with `> "$STATE_FILE" 2>/dev/null`, which does not
silence a failed redirection: the shell opens the target and reports the failure itself, before
`printf` exists to have its stderr redirected. It now writes through a temp file and renames, so a
PreToolUse hook firing twice at once cannot leave a half-written record either.

### Check 56, every shipped hook decides with a stripped environment

Census derived from the tree, and the EVENT derived from `claude/settings.json`. The first draft
sent every hook the same `PreToolUse` payload; `format.sh` returns immediately on an event it is
not registered for, so its body never ran and its row stayed green under a mutation that broke it
outright. The second draft gave each hook its real event but an empty project directory, and both
`verify-gate.sh` and `format.sh` return early on that too, so both rows went quiet again. The
fixture now plants a `.claude/verify.sh` and a source file, and the rows bite.

The check also reports that `compat-canary.sh` appears in no `settings.json` event at all.

Rows 56 and 56b: restore the bare `$HOME` in the Stop hook, and break a hook that never had the
problem, so a census that stops reaching every file cannot stay green.

### Asking for a ref that does not exist installed a different one and called it that

`bootstrap.sh` had two lanes that disagreed about the same input. Without git, `VSTACK_REF=v9.9.9`
resolved to a `/archive/v9.9.9.tar.gz` URL, 404'd, and exited 1 naming the URL. With git, the
clone's stderr went to `/dev/null`, the `||` fell through to `git clone` of the default branch,
and the run exited 0.

Then it planted `refs/vstack/synced-v9.9.9` on that commit. That watermark exists to answer one
question -- has anything been added since bootstrap last touched this checkout for `$REF` -- so
from that point on every run compared HEAD against a mark that had never described `$REF`.

`git clone --branch` resolves a tag as readily as a branch, and `$REF` defaults to `main`, so the
fallback fired only when the ref genuinely did not exist. That is exactly the case where quietly
substituting another one is the wrong answer. It is gone; the lane now reports git's own error,
names the ref, and exits 1, which is what the tarball lane has done since 1.5.0.

New `bootstrap-badref` lane in `tests/install-matrix.sh`, both directions and entirely offline:
a ref that does not exist must exit non-zero, must name the ref, and must not leave a watermark;
a ref that does exist must still clone and must still plant one. Watched red both ways.

Found by `opencode/mimo-v2.5-free` reading `bootstrap.sh` and `overlay.sh`. Five of its six
findings were rejected on inspection -- one contradicted an explicit `SC2086` disable whose
comment states the word-splitting is required, and three called it a defect that an empty
`$SRC/claude/hooks/` aborts the overlay, which is the correct answer to a broken source tree.

## 1.49.0 — 2026-08-28

Tagged and withdrawn. `container-matrix` failed lane 26 on alpine:latest and the release
workflow deleted the tag, correctly: the gate rendered a real verdict against the commit.
The commits below are on main and ship in 1.50.0, which carries the fix for that lane.

### `stat -f %m` measures the filesystem on Linux, and exits 0 doing it

`stat -f` means "file status" on BSD and macOS. On GNU coreutils and BusyBox it means *filesystem*
status: it ignores `%m`, prints five lines about the mount the path sits on, and exits 0. So the
familiar

    m=$(stat -f %m "$p" 2>/dev/null || stat -c %Y "$p" 2>/dev/null || echo 0)

never reaches its second branch on Linux. The `||` was written for a `stat` that fails. This one
succeeds, with the wrong answer, in the wrong units, across five lines.

Measured on 2026-08-28 in `alpine:latest` and `postgres:16`. Both printed `File: "/tmp"` first;
the BusyBox shell then died on the comparison with `1781368758: out of range`, and bash's `[`
called it too many arguments and returned false.

Four files shipped that ordering. One picks the newest nvm install for `bin/claude-task.sh`, where
the cost is a `PATH` missing its node bin under cron. The other three are the stale-lock reclaims
in `claude/hooks/verify-gate.sh`, `claude/hooks/skill-mandate.sh` and
`claude/hooks/dispatch-counter.sh`, and there the cost is worse than a wrong number: their
`while ! mkdir "$lock_dir"` loop has no other exit. On Linux an abandoned lock directory was never
reclaimed, so every later invocation of that hook spun forever. macOS self-healed after 30
seconds and never showed it.

All four now call `mtime_of()`, which asks GNU first -- `stat -c` on macOS is a usage error with an
empty stdout, which is the honest failure the `||` was written for -- and then rejects anything
that is not a bare integer, whatever exited 0. Four copies is deliberate: hooks are installed
standalone and source nothing.

### Check 55, the mtime probe returns an integer on every documented platform

Checked by execution, not by grep. Three stubs reproduce the measured behaviour of BSD, GNU and a
`stat` that cannot answer at all, and every copy of `mtime_of()` in the tree is run against all
three. A stat mtime call outside `mtime_of()` fails the census, so a fifth hand-written copy
cannot be added quietly, and a census of length zero fails rather than passing on nothing.

Same class as check 53, one step harder: 53 asks whether both spellings are named, 55 asks what
the code actually returns.

Rows 55, 55b and 55c: restore the shipped ordering inside the function, add an inline copy outside
it, and rename the tool everywhere to empty the census.

## 1.48.0 — 2026-08-27

### A verdict decided before the tag existed no longer deletes the tag

The release gate has two ways to say no, and only one of them was safe.

Exit 2, "nothing has decided yet", was taught not to delete the candidate tag after that deadlocked
`v1.46.0`. Exit 1, "a required check decided against this commit", still deletes -- and on
2026-08-27 that deleted `v1.47.0` twice within an hour, over verdicts the candidate never had a
chance to earn.

`bin/doctor`'s "declared release is fetchable" and check 24's pin loop both assert that the version
`README.md` pins is a tag a stranger can fetch. Before the tag is pushed, those checks are required
to be red, and they are right to be. Push the tag, and `resolve` reads those pre-tag conclusions
three minutes later, calls them a decision against the candidate, and deletes the tag that would
have turned them green. The retry starts from the same state and reproduces it exactly.

`require-checks-green.sh` now takes `CANDIDATE_CREATED_AT` -- when origin first had the tag, which
for a tag-push run is that workflow run's own `created_at`, the push's own receipt. A required
check whose run *started* before that moment and failed is reported `STALE` and counted undecided.

`started_at`, not `completed_at`, and that distinction is the fix rather than a detail of it. The
first version keyed on `completed_at` and was then replayed against the incident's real
timestamps: `verify` started 15:57:44 and finished 16:00:02, thirty-nine seconds before the tag
appeared at 16:00:41, so it happened to read as stale. `install-macos` started one second later
and finished at 16:02:31, because it is the slow lane -- same checkout, same missing tag, same
reason for failing, and `completed_at` calls it a real verdict and deletes the tag anyway. The
rule would not have saved the release it was written for, and the one lane it did save it saved
by thirty-nine seconds of luck. A job checks out as its first step, so a run that started before
the tag existed cannot have had the tag in its tree, whatever time it finished.

The narrowness is the point. A stale red does not become green; it becomes exit 2, which still
withholds publication, so nothing red ships through this door. The only behaviour that changes is
that the destructive remedy stops firing on a verdict about a repository that did not contain the
release. A red decided after the tag exists still exits 1 and still deletes, and with the variable
unset every path behaves exactly as before.

### Check 13 covers every file that declares the version, derived from the file that names them

`claude/inventory.json` carries a third copy of the version in `product.version` and names the two
plugin manifests in its own `product.version_source` array -- a written claim that its number comes
from theirs. Nothing compared it, and it drifted: the manifests were at 1.48.0 while inventory said
1.46.0, wrong across two shipped releases. `inventory.json` is payload, so that number is what a
stranger reads to find out what they installed, and `tests/inventory-contract.sh` validated the rest
of the file while walking past it.

A field that documents where its truth comes from and is never checked against that source is the
same defect as a check that names what it measures and does not measure it.

Check 13 now derives its file set from `version_source` rather than naming the two manifests
inline, and compares inventory's own claim against them. Add a fourth manifest to that array and it
is covered from that moment. An empty or unreadable `version_source` is refused rather than passed
as agreement over a list of length zero. Rows 13b and 13c watch both lanes.

### Check 54, the release gate's inputs are supplied by the workflow

The fix above has the two-halves problem this repo keeps finding.
`tests/require-checks-green.sh` proves the gate honours `CANDIDATE_CREATED_AT` by setting it
itself. Nothing in that test can notice that `release.yml` never sets it in production, and the
gate reads it through a `:-` default, so unwired it is silently empty and the whole rule is inert
behind a green suite.

Check 54 derives the census rather than listing it: every environment variable
`require-checks-green.sh` reads with a default must be named in `release.yml` or carry an
exemption with a stated reason. A knob added to the gate is therefore unwired-and-red by
construction instead of unwired-and-quiet. `REQUIRE_CHECKS_POLL_SECONDS` is the one exemption, on
the grounds that it changes how often the gate asks and never what answer it gets.

Rows 54 and 54b watch it fail in both directions: rename the variable in the workflow, and break
the extractor so the derived census empties.

Also catalogued as the seventeenth entry in `docs/checks-that-inherit-their-answer.md`, where it
is the first one that runs the other way -- nothing printed `ok`. Four checks printed `FAIL`,
correctly, and the damage was in what the workflow did with an accurate red. A check can inherit a
red as easily as a green, and a red wired to a destructive remedy is the one that costs you
something on the way past.

## 1.47.0 — 2026-08-27

### `bin/doctor`'s CI check answered for the branch, not for your commit

    gh run list --branch main --limit 1 --json conclusion,status,displayTitle,databaseId

`--branch main` is a moving reference and `--limit 1` takes whatever is newest under it. The
projection carried no `headSha`, so nothing downstream could have filtered by commit even if it
had wanted to. Standing on a commit whose CI had never run, or had failed, printed

    CI (main: an OLDER commit that passed)   ✔

which is a true statement about a different commit. `--limit 1` also picked one workflow
arbitrarily when several run per commit: this repo runs `verify` and `release`, and on 2026-08-27
`release` completed with a failure while `verify` was still going, so which one spoke for the
commit depended on timing.

`.github/workflows/release.yml`'s own header warns against precisely this -- "a moving branch ref
answers 'is the newest thing on this branch green', which silently drifts to a different commit"
-- and the check whose job is to stop a release going out over red CI reproduced it. Three
defects reached `main` in one day because a remote verdict went unread; this is the check that was
supposed to catch that, reporting green about somebody else's commit.

It now reads every run recorded against `HEAD` and orders the answer: a decided failure outranks
any number of runs still going, in-progress is a note, and **no run for this commit is a note, not
a pass**. An unpushed commit has no CI verdict and the newest run on the branch is not a stand-in
for one.

**Check 49** gates the decision offline, through a `gh` stub, five cases, both directions. The
network call stays in `bin/doctor` -- `.claude/verify.sh` is hermetic by design, which is why the
CI and release-reachability questions live there in the first place. What belongs in the gate is
the decision, and now it is falsifiable: row 49 deletes the commit filter and check 49 goes red.
Also pinned by `tests/repro/ci-lane-answers-for-head.sh`, which was watched failing on exactly two
of its five cases before the fix.


### Check 49 graded a checkout it was not testing

`resolve_vstack_repo()` prefers `~/.config/agents/vstack-repo`, wherever `install.sh` last ran
from, over the location of `bin/doctor` itself. So check 49 computed this checkout's `HEAD` and
wrote its `gh` stub for it, while doctor answered about the installed tree. The two agreed for
exactly as long as they were the same directory. Running the gate from an isolated clone
separated them: three of five cases went red, including both positive controls. Pinned with
`VSTACK_DIR`.

### Check 18 published a figure only one directory could reproduce

The session hook splices `$root` twice, `$branch` once and `$base` three times into the block
check 18 measures. The cap lane was normalized for the first two and deliberately left `$base`
in, reasoning that the remote's default branch "does not vary with this checkout" -- it varies
with the remote. The published-figure lane was never normalized at all and compared the README
against the raw count. Measured 4077 B at a 25-character checkout path on `main`, which is
3.9 KB and inside the 0.15 KB tolerance, against 4163 B in a clone three characters longer whose
`origin/HEAD` named a 24-character branch, which is 4.1 KB and outside it. Same commit, same
prose. All three splices are now subtracted; the invariant count is 3990 B in every checkout
tested, and that is what the README publishes. Row 18d splices `$base` a fourth time so the
correction cannot fall behind the hook again.

### A CI job nothing requires is a verdict nobody reads

`REQUIRED_CHECKS` was a hand-maintained list of four names sitting beside a workflow that
defines four jobs, with nothing connecting them. Add a lane and it can be red on every commit
while the release publishes over it, which is not hypothetical: `install-macos` was added, went
red on its first run, and the failure was found by reading a job log by hand. Check 50 asserts
both directions -- a job missing from the list is an unread verdict, a name with no job behind
it leaves the release gate UNDECIDED forever.

### The only step that destroys something had the only decision nobody could run

`cleanup-on-failed-gate` force-deletes a candidate tag from origin, and its entire rule lived in
a GitHub Actions `if:` expression, which no test can execute. It was wrong in production earlier
the same day. The rule now lives in `.github/scripts/should-delete-candidate-tag.sh` with exit
codes 0/10/2 so a crash cannot be mistaken for a verdict; `tests/release-cleanup.sh` is its
truth table, including two join assertions so a tested decider the workflow does not call cannot
pass. The job's `if:` is now deliberately broader than the rule and carries no part of it.

### The bin-scripts suite had never been watched fail

`tests/bin-scripts.sh` printed "38 passed, 0 failed" and nothing had asked whether it can print
anything else -- in a file that shipped claiming it never reaches the real `claude` CLI while
two of its cases did. Check 52 runs its `bg-args` case against a two-file copy both ways, and
refuses if the control mutation stops matching. `tests/install-matrix.sh` gets no equivalent and
that is stated rather than skipped: its cheapest case measures 2m10s and it was red for an
unrelated reason, so a control against it would have passed without measuring anything.

### A missing hasher wrote the empty string

macOS ships `shasum` and no `sha256sum`; BusyBox ships the reverse. Both write nothing to stdout
when absent, so a caller naming only one gets the empty string rather than an error.
`tests/inventory-contract.sh` computed an empty payload digest on Alpine. The same bug in
`tests/gate-falsifiability.sh`'s no-op-mutation detector compares an empty before-hash against
an empty after-hash, and two empty strings are equal: a detector whose whole job is to notice
that a mutation landed, reporting that none of them did. All three callers now try both and
refuse by name. The recomputed digest is byte-identical, so the refactor changed no measurement.
Check 53 requires any shell file naming one hasher to name the other.

### The README pinned a tag that never shipped

README pinned `v1.46.0` while the manifests declared `v1.47.0`. Check 24 caught it on CI and not
locally, because this machine still held a local `v1.46.0` tag the remote did not: the gate read
a tag that exists nowhere a stranger can reach. A related trap, worth writing down: with
`push.followTags` set globally, `git push origin <branch>` republishes that local tag on every
push, which restarted the release workflow on a red commit four times in an hour.

### Two published measurements had no surviving artifact

`CHANGELOG.md` cited "80 samples" for the skill-collision suppression finding and "a uniform 0/5
across five fixtures" as the motivation for the 1.43.0 replay log. Neither number can be re-read.
There is no 80-sample runlog in git history or on this machine; the only collision arm on record
is 55 samples on `col-11` alone (`tests/README.md:188`), and its instrument was an uncommitted
edit to `tests/dispatch-fleet.sh` — the fence comment at line 180 of that file already said so.
Its runlog at `/private/tmp/vstack-dispatch-pilot-col.jsonl` no longer exists. The 0/5 figure is
worse than unsourced: the harness cannot produce that shape at all, because at
`tests/dispatch-fleet.sh:678-688` only `kind=="skill"` and `kind=="none"` fixtures receive a
numeric `k`, so a `CHAIN:` or `AMBIGUOUS:` fixture returns `{k: null}` and never prints a
fraction. Two of the five fixtures in that arm are exactly those kinds.

This is the repository's own subject applied to its own evidence base. A check that inherits its
answer returns a true statement about the wrong question; a citation whose artifact is gone is the
same defect one level up — it reads as measured, and there is nothing left to disagree with. Both
lines are kept in place with a retraction note attached rather than deleted, which is how
`tests/evals/RESULTS.md` already handles its retracted pathway run. The direction each arm reported
stands as what it reported. The n is withdrawn from both.

### Replacement arm, pre-registered before it runs

`tests/evals/collision/PREREGISTRATION.md`. The question is deliberately not "why did those
fixtures score zero" — that is unanswerable now — but the one a single arm structurally cannot
answer: when a skill fails to fire on a collision-framed prompt, was it the collision, or does that
skill not fire under this harness on any prompt? Matched pairs, 5 arms × n=5 = 25 model calls:
`swarm` and `principle-encode-lessons-in-structure` each on their clean `pos-*` fixture and their
`col-*` fixture, plus `col-01` ("Tear this apart.") which is a literal trigger string in both
`grill-me`'s and `interrogate`'s descriptions.

Thresholds, void conditions and named invalidators are fixed in that file before the first sample.
The fixture file is pinned by `sha256`, not by path, because `~/vstack-dispatch/` is not a git
repository and the path alone does not identify what ran. `tests/dispatch-fleet.sh` is **not
edited**: every parameter goes through the committed env overrides, which exist precisely because
a source edit is what destroyed the previous arm. The runlog is written to a tracked path in the
repository and committed with the results, and `KEEP_WORKDIRS=1` retains the transcripts.

The arm also bears on H11 at no extra cost. `swarm`'s affordance is the `Agent` tool, which the
harness's own guard (`dispatch-fleet.sh:195-224`) requires to be denied;
`principle-encode-lessons-in-structure` produces prose and needs no denied tool. If `swarm` is
silent on both its fixtures while the prose skill fires on its positive, the fence explains that
zero and collision does not. This does not discharge the publication gate at
`dispatch-fleet.sh:277-283`; arm A5 of `tests/evals/build-the-lever/PREREGISTRATION.md` remains its
named condition, and no fleet-wide figure is derived here.

### The arm reported, and the collision explanation did not survive it

25 samples, every one `subtype=success`, no fence violations, `--score-only` reproduces every figure
from the committed runlog with no model calls. `tests/evals/collision/RESULTS.md` carries the full
report; `tests/evals/collision/runlog-2026-08-27.jsonl` is committed beside it.

`swarm` fired 0/5 on its clean positive fixture and 0/5 on its collision fixture.
`principle-encode-lessons-in-structure` did the same. `col-01`, whose prompt is a literal trigger
string in two competing skill descriptions, fired `interrogate` once in five and nothing in the
other four. One `Skill` call in 25 samples. H-C2 falsified for both skills; H-C3 confirmed for both.

`KEEP_WORKDIRS=1` kept all 25 transcripts, which is the thing the lost arm could not do, and they
name the mechanism. The harness runs every sample in an empty `mktemp -d`, so a prompt that refers
to a repository, a diff or a prior turn has no referent: all five `pos-19` samples globbed, found no
packages and asked which repository held them. The fence denies `Write`, so a skill whose action is
to write a file gets as far as the attempt: all five `pos-11` samples called `Write` and were
refused. The routing was never missing. The model named `swarm` in prose without calling it in 7 of
10 `swarm` samples, and named `interrogate` or `grill-me` in 4 of 5 `col-01` samples.

One mechanism therefore explains both arms of the anomaly, and it is the instrument.
`tests/dispatch-fleet.sh` records `fired=[]` identically for "the dispatcher did not route" and "the
model asked which repository you meant", and it deleted the transcripts that tell them apart until
`KEEP_WORKDIRS` existed. Every dispatch rate taken through it inherits that confound.

H11 is confirmed wider than it was registered. The publication gate asks whether denying `Write`
suppresses skills whose output is an artifact. This arm picked
`principle-encode-lessons-in-structure` as the fence-immune control because its output is prose, and
5 of 5 samples disproved that premise by calling `Write`. The gate stays closed and its priority
goes up.

**H-C1's threshold was mis-specified, in the pre-registration written to prevent that.** It was a
bare bound on one arm: empty in ≥4/5 confirms suppression. `col-01` returned empty in 4/5, so the
threshold was met, and it means nothing, because both controls returned empty in 5/5 and empty was
the modal outcome of every fixture in the run. Written without a control clause, H-C1 returns
CONFIRM on any run in which nothing fires at all. That is the fourteenth instance of the defect in
`docs/checks-that-inherit-their-answer.md`, and it is in the instrument written to measure the
thirteenth. The corrected form is recorded in `tests/evals/collision/RESULTS.md` and is not applied
retroactively to score this run.

### The whole evidence base, as one document

`docs/research/fake-greens-2026-08.md`. What was measured, what the numbers do not support, and the
thirteen checks that passed while measuring nothing, each with the path and date it came from.
Numbers without a surviving artifact are marked unsourced and support nothing.

A `code-reviewer` pass against the tree caught four wrong figures in the draft before it landed:
`guard-quote-aware-split.sh` is 18/18 and not 15/15, the SWE-bench row is 4 instances and not 3, the
catalogue grew by six in the 2026-08-26/27 window and not seven, and the "true statement read as the
answer to a different question" sub-shape covers two entries and not three. The same pass found that
`docs/research/` is excluded by construction from check 12's doc-count extractor and check 38's
path-existence scan, so neither gate would have caught any of them. A document about checks that
measure nothing is not covered by the checks.

### A red gate has never failed CI on macOS or Alpine

Two of the three platform lanes ran the gate as `./.claude/verify.sh | tee "$RUNNER_TEMP/gate.txt"`.
GitHub's default shell for a `run:` block is `bash -e` with no `pipefail`, so the step's exit status
is `tee`'s, and `tee` succeeds whatever the gate did. Measured both directions on 2026-08-27 against
a seeded gate that prints `FAIL` and exits 1: `bash -e -c 'gate | tee f'` exits **0**, the same
command unpiped exits **1**. The one downstream step that reads the captured log,
`.github/scripts/require-no-unexpected-skips.sh`, exits **0** on a log full of `FAIL` lines, because
it only inspects skip lines. So a failing gate on macOS or Alpine passed the job, passed the audit,
and was never visible.

This is the rule the repository already wrote down after a local `./verify.sh | tail` produced a
false green, applied everywhere except the two lanes that needed it. Both now redirect to a file,
capture the status with `|| rc=$?` so `-e` cannot exit before the code is read, print the log, and
`exit "$rc"` on its own line.

The macOS lane also stopped linting. `macos-latest` no longer ships `shellcheck`, so check 29
skipped, and the lane's approved-skip list did not cover it. That skip is what the lane's own audit
caught, and it is the reason this was found at all. Fixed by installing `shellcheck` rather than by
approving the skip, matching the alpine lane, whose comment already says a check that skips is
measuring nothing. Approving it would have left 71 scripts unlinted on the one platform whose BSD
tools this job exists to exercise, with the lane still green.

### v1.46.0 was tagged locally and never pushed

CI had been red on `main` for three commits for one reason: `install-macos` and `install-linux` both
failed `doctor is green on a clean install` with "v1.46.0 is declared and pinned in the README but is
not on origin". The tag existed at `cc5bf690`, which is `origin/main`'s own head, so pushing it
published no commits and turned the lane green. Read from `gh run list --json conclusion`, not from
a local exit code, which is the only way this class of failure is visible at all.

### Stale counts in `docs/what-this-actually-does.md`

The document stated 44 gate checks and falsifiability totals of `60 declared` and `61 declared`.
The tree declares 54 checks and 85 falsifiability rows (82 mutation + 3 fixed). The old figures
were true on their run dates and are now marked as superseded with those dates attached, rather
than replaced with a number nobody re-ran for this document — the document's own rule is that no
claim appears without a source and a date.


## 1.46.0 — 2026-08-27

### claude-mem removed

It injected nothing. Measured against the shipped `hooks.json`, not inferred:

| Hook | Command | Returns |
|---|---|---|
| `UserPromptSubmit` | `session-init` | `{}` — 2 bytes, no `additionalContext`, on fresh and repeat session ids, with a cwd holding 660 stored observations |
| `SessionStart` | `worker-service.cjs start` | 3 bytes (a daemon starter) |

The 10,577-byte context payload the plugin can produce comes from `hook claude-code context`, and
no hook in its `hooks.json` invokes it. Across 16 log files, all 613 lines matching `Injected` are
OAuth tokens going into spawned subprocesses; not one is a context injection into a session. The
read path is a skill, `mem-search`, which would arrive with 18 others — `do`, `make-plan`,
`smart-explore`, `learn-codebase` — sharing trigger frames with `executing-plans`, `writing-plans`
and `find-skills`. Colliding triggers were measured over 80 samples to suppress both skills, not
one, so the trade was working skills for a store nothing read back.

> **Retraction note added in 1.47.0: the "80 samples" above is unsourced.**
> No 80-sample runlog exists in git history or on this machine. The only collision arm on record
> is 55 samples on `col-11` alone (`tests/README.md:188`), produced by an uncommitted edit to
> `tests/dispatch-fleet.sh` — its own fence comment at line 180 says so — and its runlog at
> `/private/tmp/vstack-dispatch-pilot-col.jsonl` is gone. The direction of the finding is what
> that arm reported; its n is withdrawn. Replacement arm pre-registered at
> `tests/evals/collision/PREREGISTRATION.md`.

Removed from `setup-machine.sh` (the plugin list and the whole `hooks.json` async-flipper),
`install.sh` (the `enabledPlugins` presence probe; the entry is now deleted unconditionally),
`bin/doctor` (both checks), `claude/statusline.sh` (the indicator), `README.md` and
`docs/how-skills-fire.md`. `uninstall.sh` keeps restoring the `hooks.json.vstack-orig` sidecar
older versions left behind: a version that stops making an edit does not get to stop undoing it.

`bin/doctor` had been printing `claude-mem UserPromptSubmit async ✔` over a plugin throwing
`ERR_INVALID_PACKAGE_CONFIG` on every hook call, because it graded the lexically-last version
directory rather than the one Claude Code resolves, and asserted a flag inside `hooks.json`
without ever checking the plugin could execute. That is this repository's founding defect class,
in its own doctor. The check is gone rather than fixed — there is nothing left for it to grade.

### `uninstall.sh` could not uninstall

`install → install → uninstall` left every hook, skill, agent and command on disk while printing
that it had removed them. `install → uninstall` on a machine with no prior `settings.json` left
`hooks` and `statusLine` pointing at seven scripts it had just deleted. Two independent causes,
both fixed here.

**The backup laundered the payload.** `back()` copied the file it was about to overwrite into
this run's backup directory without checking whether that file was vstack's own from last time.
On a second install the backup therefore held vstack's payload, and `uninstall.sh`, which reads
"present in the backup" as "the user had this before", restored it. `back()` now takes the repo
file as a second argument and skips the backup when the two are byte-identical; the per-skill
directory backup does the same with `diff -rq`. The trade is stated in the source: a user file
whose bytes exactly equal vstack's is treated as vstack's and is deleted, and what is lost is
content this repo still ships verbatim.

**Both ownership branches were dead code.** `uninstall.sh` derived the hook basenames it owns
from `claude/settings.json`, whose commands are spelled `"$CLAUDE_PROJECT_DIR/.claude/hooks/x.sh"`
with embedded quotes for project scope. Splitting those on `/` produced `format.sh"` — trailing
quote — which `endswith("/hooks/" + $b)` never matched against an installed unquoted path. The
statusLine branch was dead for a different reason: the template has no `statusLine` at all,
`install.sh` writes it, so the guard `$shipsl != ""` was never true. Both now derive from the
same authority `install.sh` uses, the files under `claude/hooks/` and `claude/statusline.sh`.

This is the reader/writer join again: `install.sh:381` builds its basenames from the hook object
it constructs inline and is correct; `uninstall.sh` copied the idiom and pointed it at a source
the writer never uses. Check 45 passed over all of it, because its sandbox had a pre-existing
`settings.json` and the literal-restore path cleaned up before the branch under test could fail.

Reproduction: `tests/repro/lifecycle.sh`, 9 assertions over 6 install/uninstall sequences, 4 red
before this change and 0 after.

### The Stop gate ran in a lane that claimed to have no hooks

`claude/hooks/hooks.json` is auto-discovered by the plugin lane, and it wired `verify-gate.sh`
into `Stop`. A plugin install therefore ran a cloned repository's own `.claude/verify.sh` on every
Stop, with none of the full install's surrounding machinery, while `README.md` said the lane
shipped no hooks at all and `bin/doctor` told plugin users the same. Four artefacts in this
repository, two answers, and nothing able to see the disagreement: check 12 resolves one number
per noun for the whole tree, and README states its counts per lane, so the plugin rows passed by
coincidence and the row that genuinely differed did not match the table regex at all.

`hooks.json` now carries routing only. The lane ships two hooks, `SessionStart` and the skill
mandate on `Stop`, and README says so.

**Check 47** executes every script `hooks.json` names under `env -i`, with `PATH` scrubbed of both
wrapper directories, and asserts each exits 0, emits valid JSON or nothing, and never tells a
plugin-lane user to run a command that lane does not install. Its positive control plants a hook
emitting `run vstack trust` and requires the check to catch it. Its fixture seeds a failing
`.claude/verify.sh` in the sandbox, because the first version of it passed over the regression:
an empty cwd meant the gate hook exited silently, which is indistinguishable from correct.

README also gained a section stating five things `vstack trust` does not cover.

### The formatter executed cloned repositories' JavaScript

`SECURITY.md` said cloning a hostile repository does not run that repository's code. False for any
repository carrying a static `.prettierrc.json` with a `plugins` entry: Prettier `require()`s the
named local `.js` at format time, and `format.sh` fires on `PostToolUse` for every `Edit`, `Write`
and `MultiEdit`. Not at `Stop`, so the `verify-trust` record never entered the picture. An ordinary
edit in a freshly cloned repository executed attacker-controlled JavaScript.

`format.sh` now refuses a `plugins`-declaring config from an untrusted repository and says why in
its `systemMessage`. Executable Prettier config is never loaded, trusted or not: Prettier 3 has no
flag that reads `prettier.config.js` without executing it.

`SECURITY.md` now describes both hooks that run repository-controlled code, and adds a section
naming what the trust boundary does not cover: path dependencies recorded by path rather than
content hash, test files, dynamically built paths inside a gate, and the fact that the gate cannot
defend against an agent sharing its uid.

### Releases were gated on the machine that ran the gate

`release.yml` now resolves the commit the tag names and reads that exact SHA's check runs from the
GitHub API, once at resolve and again immediately before `gh release create`. Never a local exit
code, never `main`'s tip. Six releases here shipped over red CI because every gate asked the
machine it ran on. Verified against v1.45.1's commit (four of four `success`) and against a null
SHA (fails). `container-matrix` runs between resolve and publish; a failed required job deletes the
tag it arrived on, so a red gate cannot leave a tag behind.

Branch and tag protection rulesets are prepared in `.github/` and deliberately **not applied**.
`branch-protection.md` carries both `gh api` commands and the reasoning, including why tag deletion
stays open.

### Three CI lanes reported green while proving less than one

CI trusted `.claude/verify.sh`'s exit code alone, and a skip never moves that. Alpine had no
shellcheck, so check 29 skipped there every run. `install-macos` and `install-alpine` checked out
shallow, so check 24 could not read a tag and skipped too. `require-no-unexpected-skips.sh` now
reads the gate's output against a per-lane allow-list and fails the job naming any skip that is not
on it. Alpine installs shellcheck with no fallback; both install lanes fetch depth 0. Actions and
the Claude CLI are pinned to exact SHAs and versions. `tests/bin-scripts.sh` was in the repository
and invoked by nothing; it runs now.

`tests/dispatch-static.sh` was the same defect one directory over: a missing parser and a file with
nothing to parse landed in the same skip bucket, and the summary only checked that no case failed.
On a runner without node, twenty-eight of thirty-five fixtures were never parsed and it printed
`ok`. Real validators are wired for `.ts`, `.go`, `.html` and `.css`; prose files stay a named skip;
every other extension and every missing binary is now a failure naming it. Measured both
directions: full `PATH`, twenty-five parsed and exit 0; without the four validators, fifteen named
failures and exit 1. `verify.yml` installs them, because that suite now needs them to prove
anything.

`tests/install-matrix.sh` gained `reinstall-uninstall` and `version-upgrade-uninstall`, both of
which fail at v1.45.1 and pass at HEAD. The obvious version pairing was rejected first: v1.45.1 and
`86d19a3` ship byte-identical hooks, so that lane would have passed pre-fix on the `cmp -s`
shortcut alone and proved nothing.

### A repro's own control inverted when its fix landed

`tests/repro/formatter-config.sh` proved it was not vacuous by reverting to
`HEAD:claude/hooks/format.sh` and requiring the attack to reproduce. The moment the fix was
committed, HEAD became the fixed hook, the attack stopped reproducing, and the repro reported the
hole OPEN because its control had gone green. Caught by running all six repros after committing,
not by reading them.

The baseline is derived now: walk `format.sh`'s history newest-first and take the first blob
without the guard. No SHA to remember, and no baseline is a loud failure rather than a comparison
of the fix against itself.

All six reproductions are green.

### The destructive guard's `ask` tier was inert for every unattended agent

`guard-destructive.sh` returns `ask` for the commands that destroy uncommitted work, and check 23
verifies it returns exactly that across thirty commands and three tiers, both directions. Under
`bypassPermissions` — the mode every unattended agent runs in — an `ask` decision is auto-approved.
Measured live: `git clean -fd` ran unprompted and deleted an untracked file with the guard live and
answering `ask`, while a `deny` for a force-push to main blocked the entire tool call in the same
session. Both halves correct for months; the join never tested.

Not hypothetical. On the day this was found, four agents' uncommitted files were taken by a bare
stash and a fifth agent's work was destroyed by a hard tree reset from another process, and the
guard had answered `ask` for both.

`permission_mode` is on the PreToolUse payload — confirmed by capturing the live hook's stdin
during a real tool call, with the enum read out of the installed CLI binary. Under
`bypassPermissions` the subset that destroys other people's uncommitted work now escalates to
`deny`: bare `git stash`, hard tree resets, `git clean -fd`, and the already-workspace-scoped
wildcard staging and no-pathspec commit. A bare stash was not in the file at all before and fell
through to a silent allow. Every other rule in the tier — database drops, infrastructure teardown,
the verify-trust store, device writes — is untouched, because an `ask` a human will actually see is
doing its job. When the mode is absent the decision stays `ask` and the reason says plainly that it
could not confirm anyone will see it.

The join itself cannot be asserted offline: proving it requires driving Claude Code's own
tool-execution loop, which is a model-call test. `tests/repro/guard-bypass-escalation.sh` covers the
decider, and `docs/guard-enforcement-gap.md` states what that does and does not prove rather than
letting check 23's label imply coverage it does not have.

Known limitation, found immediately by the guard blocking a commit describing the guard: it matches
syntax, not semantics, so a commit message quoting destructive flag syntax as prose is denied along
with the whole tool call.

### `vstack self-test`, `explain`, `recover`, and a local run log

`self-test` answers "is this installation working" in one command, for an installed machine rather
than a repo checkout. Its total is derived from the file's own section markers rather than
maintained by hand, and a run where nothing executed fails on its own bar — `ran + skipped ==
declared` holds at zero, which is precisely the accounting a gate that measured nothing satisfies.

`explain` reads the live machine: which lane is installed, which paths vstack claims, which hooks
are wired to which events, which repositories are trusted, and why a hook did or did not fire.
Anything it cannot read is `UNKNOWN` and names the field.

`recover` gives a partial install a way back. It delegates the restore to `uninstall.sh` rather
than reimplementing one — a second blind restore is the shape that already destroyed two agents'
work here — and refuses when the marker does not parse, names a path outside the backup root, names
a directory that does not exist, or names a backup that is not the newest on disk. `install.sh`
writes that marker after the backup directory is created and removes it as the last action before
its own successful exit, so a marker that survives the process is the signal that the process did
not finish.

The run log at `~/.config/agents/vstack-runlog.jsonl` records one entry per `self-test` and
`verify`. It is **not** an attestation and not a receipt: unsigned plaintext, editable by anything
running as the user, and the file says so in its own schema note. Every field that cannot be
determined serialises as `UNKNOWN`, never as a fabricated zero.

### An inventory contract, and check 48

`claude/inventory.json` records what this repository ships, every list and count derived by command
rather than typed. Nothing reads it at run time, and `install.sh` in particular does not: the glob
in the installer and the list in the contract are worth having only as two independent derivations
of the same fact, and an installer that read the contract would turn "does the inventory match what
installs" into a question that answers itself. `contract_version` is the hand-bumped schema version
and an unrecognised value fails loudly; every count is derived and diffed.

Check 48 runs `tests/inventory-contract.sh` against the tree, with floors per family stated
alongside the claim that becomes false below each one.

### The release gate picked whichever check-run the API returned last

`require-checks-green.sh` reduced the check-runs for one name and one SHA with
`sort_by(.name) | last`, applied to an array already filtered to that single name. A stable sort on
a constant key returns input order, so it selected whatever GitHub happened to place last —
observed live, that API returns newest first, which makes `last` the oldest. A check re-run to green
would have been read as the earlier failure, and an earlier success could have been read over a
later failure. That is publishing over red, inside the script written to prevent publishing over
red. The projection had also discarded every timestamp, so no ordering was possible even in
principle.

The selection moved to `latest-check-run.jq` so its test runs the real program rather than a
restatement of the rule, and there is deliberately no environment seam for injecting fake check-run
JSON: a release gate with a bypass is not a gate. The caller now prints the attempt count and the
earlier conclusions when a SHA carries more than one run, and refuses with `UNKNOWN` when several
runs exist and none carries a timestamp.

`tests/require-checks-green.sh` covers ten cases in both directions. One of them caught a defect in
the fix while it was being written: ordering on `completed_at` first put an in-flight re-run below
the finished run it was re-running, so the gate would have read the stale result while the real
check was still going. `started_at` is the right primary key because every run carries one.

### A compatibility canary, worktree collision detection, and a failure-aware ledger

Every hook parsed Claude Code's payload with `jq ... // empty` and no else branch, so a renamed
field or an unrecognised event degraded to the same silent exit as nothing happening, and nothing
checked the Claude version at all. `compat-canary.sh` reports `KNOWN` or `UNKNOWN`, names every
field it could not read, and writes to stderr rather than stdout because the session hook has four
bytes of headroom under check 18's cap.

`tests/lib-collision-guard.sh` gives harnesses a save/restore that refuses to overwrite a file
changed since it was written, and a report naming which worktree, which PID and which lock file is
holding a collision. The falsifiability lock moved from `git rev-parse --git-dir`, which returns a
different path inside every linked worktree, to `--git-common-dir`, which resolves identically from
all of them.

The delegation ledger records `task_fail_count` alongside `task_count`, correlating each dispatch's
`tool_use` id against a later error result. A ledger that cannot tell a verified fix from an agent
that died after thirty seconds cannot support any claim about the routing layer, and this
repository makes claims about the routing layer.

### The ownership record claimed paths no run had installed

`seed_owned_paths()` exists so a machine installed before 1.46.0, from a version with no ownership
tracking, can still be uninstalled. It fingerprints such a machine by counting vstack hook
basenames at the destination. Its five seeding loops then walked the repository instead, calling
`own()` on every agent, reference, command, and skill the tree ships, whether or not that profile's
run had written it. A `core`, `team`, or `ui` install on a fingerprinted machine came out of it
claiming the whole repository.

`uninstall.sh` then acted on that claim. Its skills loop matched a directory by name and removed it,
with none of the byte-identity discipline `plan_file_removal` already applies to files, so a user
directory sharing a name with a shipped skill was deleted unread. `brainstorming` is not a name
anyone has to work to collide with. The loop now runs `diff -rq` against the repository first and
reports a mismatch as `KEPT_COLLISION` rather than removing it. Seeding tests the destination, the
way the fingerprint loop above it already did. It is deliberately not gated on the current run's
profile: a file genuinely on disk from an earlier install should stay adoptable no matter which
profile runs next, and gating on profile would leave real artifacts permanently untrackable.

Two smaller ones alongside. `own()` was reached through a path that checked for the file before
recording ownership, so a first-ever install recorded almost nothing and `uninstall.sh` fell back
to treating none of it as vstack's. And the `.statusLine` merge overwrote whatever the user had;
it now claims the key only when it is unset or already points at vstack's own `statusline.sh`.
`install.sh` writes and clears `~/.config/agents/install-state` around the run, which is the marker
`vstack recover` documents and had never been given.

`tests/profiles.sh` is the regression: 83 assertions over per-profile install and uninstall round-trips,
the seeding over-claim under a non-default profile, ownership disagreeing with content, and byte
identity between `opinionated` and the no-argument default. Each fix was reverted alone and watched
turn exactly one check red.

### The catalogue goes from six to thirteen

`docs/checks-that-inherit-their-answer.md` closed by predicting a seventh instance next month. It
got four in a day, five weeks early: the guard decision nothing downstream honoured, check 18's cap
clearing by one byte because the injected block embeds the absolute repository path, a reproduction
whose no-op control inverted the moment its own fix was committed, and an ownership record that
read the repository's contents as a report of what had been installed.

Then three more. The first two are a different shape from the first ten. Neither was a check that
measured the wrong thing. Both were a **true statement read as the answer to a different
question**, which no mutation can catch and which the falsifiability suite was green throughout.

Eleven: `git status --porcelain` is blind to empty directories, because git does not track
directories. `tests/inventory-fixture.sh` planted a defect, restored it, and proved the restore by
diffing porcelain before and after — while leaving behind a `mkdir -p` that `do_unplant()` never
removed. Every family's plant contaminated the next family's baseline, and `tests/plugin-manifests.sh`
was recorded as blind six times for failures the harness itself had caused. What caught it was a
positive control running an unrelated gate, not the tree-unchanged check written for that exact
purpose, which passed. `tree_fingerprint()` now pairs porcelain with a sorted list of empty
directories; verified on BSD `find` and BusyBox `find` 1.37.0.

Twelve: `.claude/verify.sh` refuses to run while another process holds the falsifiability lock. It
prints `REFUSED`, explains why, and exits 2 — correct on every count — and its last line was "Wait
for it to finish". Output that ends with no verdict is indistinguishable from a clean run to anyone
who tails the last lines or counts `FAIL` lines, which is how gate output is actually read. That
reading reached a commit message here as `VERIFIED`, in a commit about labels overstating what they
assert. The exit code was right the whole time; nothing read it. Refusals now end with `NOT RUN` in
the position a real run puts `VERIFIED`, and check 14 asserts the refusal's *last* line, not just
its first. **A discipline that has to be remembered is not a control.**

Thirteen: `install.sh` backed up nothing, and said otherwise on its last line. `back()` calls
`own "$1"`, which writes the path into the ownership record, and then asks that record whether an
earlier install claimed the path. It had, two lines up, in this run. Every call matched and
returned before its `cp`. The backup directory was still created, still announced as
`backup: <path>`, and empty; `abort_note` still promised that every file the run touched was copied
there first. `tests/install-matrix.sh` caught it on all three platforms within fifteen minutes of
the push and was read fourteen hours later. Pinned by `tests/repro/backup-self-claim.sh`, which
asserts the copy's bytes rather than its existence, and which was watched going red against the
unfixed `install.sh` in a detached worktree before the fix landed.

### `claude-bg.sh` and `claude-task.sh` overrode the caller's PATH

Both hardened PATH by *prepending* `$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:...`. The
comment gives the reason as "so a cron-shaped minimal PATH still finds claude", which appending
serves just as well, because a minimal PATH has no `claude` on it to win the race. Prepending also
does something the comment does not mention: it overrides the caller. A `claude` someone
deliberately put first -- a wrapper, a pinned version, a test stub -- lost to whatever sits in
`/usr/local/bin`. For a script cron and launchd invoke unattended, silently running a different
binary than the one the operator installed is the least debuggable failure available. Both now
append.

`tests/bin-scripts.sh` had never passed on CI. It was added to `verify.yml` in `e666f6c`, whose
subject was killing three CI skips, and it went red on its first execution and stayed red: three
`claude-bg.sh` cases reporting `no dispatch reached the stub`. The prepend is why. The CI log also
carries the line `Not logged in - Please run /login`, which is the real Claude CLI answering a
prompt from a suite whose header states that "every `claude` in here is a local stub script, never
the real CLI". That was a description of the intent with no mechanism behind it; on a logged-in
machine it is a real model call. A poison `claude` now sits first on the PATH every case inherits,
so a case reaching no stub of its own gets `exit 97` and a loud line instead of the operator's real
CLI -- with a positive control that watches the poison outrank the machine's actual `claude`,
because a safety net nobody has seen hold anything is the shape this repository is about.

Two `claude-task.sh` cases turned red under the fix and were not weakened to make them pass. Both
test argument handling and cwd independence, and both reached their stub only via the prepend. They
now name their own `PATH` explicitly. Resolution order still has two cases of its own, unchanged.

### `back()` asked a question it had already answered

Separate from the catalogue entry, because the fix is worth stating on its own: the ordering is the
whole bug. `own()` must run above the `[ -f "$1" ] || return 0` guard -- a first-ever install has
nothing at `$1` yet, and returning there without recording ownership is what left `uninstall.sh`
keeping every hook, agent and command a `--yes` uninstall was supposed to remove. The ownership
*question* must run above `own()`. Those two constraints are not in conflict and the first
revision satisfied only one of them. `back()` now reads the record into `_pre_owned` before
claiming anything, so "an earlier install owns this" means an earlier install.

Reaching this needed a `git worktree` at `HEAD`: the repo's own guard refuses a bare `git stash`,
correctly, because this checkout is shared.

### `payload_digest` hashed no bytes, and read its own recipe out of the file it was checking

Two independent holes in the same field, both reproduced before being accepted.

The recipe hashed `git ls-files -s` (index blob ids) plus `git status --porcelain` (status letters
and paths, never contents), so two different unstaged edits to the same payload file produced the
same digest, and so did two different untracked files at the same path:

    clean  923c92b7...
    dirtyA fe75bb39...   <- different bytes
    dirtyB fe75bb39...   <- same digest

`payload_digest_compute()` in `tests/inventory-contract.sh` now hashes working-tree bytes, tracked
and untracked-not-ignored, with the exec bit and path, NUL-delimited, with a gitlink arm so a
future submodule does not hash as `absent` forever. What it does *not* see is stated in place:
`--exclude-standard` skips ignored files, and `install.sh` copies directories, so an ignored file
sitting in one reaches the installed tree unhashed.

The validator used to `eval` the recipe string out of `claude/inventory.json`, on the reasoning
that the two "can never drift apart". That is the defect: the artifact supplied its own oracle, so
editing the recipe and the digest together passed while measuring nothing — and eval'ing a string
out of the file under test is arbitrary code execution from the artifact. The recipe lives in the
independent half now; the file names where (`digest_recipe_source`), a check requires that pointer
to resolve to a function that file defines, and reintroducing an executable `digest_recipe` is
itself a failure. `tests/inventory-contract.sh --print-digest` is the only supported recompute.

### A server vstack stopped shipping stayed installed forever

`run_drift()` iterated the keys `mcp/servers.json` declares *today*, so a server removed from the
repo was not among them and no lane ever looked at it again. It cannot be inferred from
`.claude.json` either: the user's own servers live in the same map. `install.sh` now records
`mcpServers:<key>` lines in the ownership record it already maintains, and doctor reads from the
installed side. Machines installed by earlier versions carry no such lines and gain the coverage on
their next install, not retroactively — no record, no claim.

### Three labels that described more than their check asserted

Check 2 said "every JSON file parses" and named five paths against a tree of twelve; both
`.github` protection rulesets, `brand.schema.json`, `claude/inventory.json` and three ground-truth
fixtures were outside it. Derived from `git ls-files` now. `.jsonl` is excluded on purpose and says
so: `truncated.jsonl` is invalid by design.

Checks 3 and 10 said "loadable" and asked only whether *some* line in the file began with `name:`
or `description:`. That passes a file with no frontmatter, one whose block never closes, and one
whose only `description:` sits in a fenced example halfway down. `fm_block()` requires `---` on
line 1 and reads to the closing `---`. The `disable-model-invocation` probe moved into the block
too — it scanned the whole file, so a skill whose prose *discusses* the flag failed, and this repo
ships one that does.

### Three falsifiability rows ran two mutations under one oracle

Rows 1, 20 and 29 each edited two files and accepted one shared failure label, so either edit alone
turned the check red and carried the row while the other lane stayed unproven — precisely the state
each row had been widened to fix. Row 29's own comment said "one mutation per lane, or half the
selector stays unproven", and then ran both lanes in one row. Split into 1/1b, 20/20c, 29/29b.

Rows went 57 to 70 across this release. New: 2b (a JSON file the old five-path list never covered),
3b and 10b (frontmatter block, not its contents), 14c (the refusal terminator), 35b through 35g
(each of doctor's drift decisions on its own).

## 1.45.1 — 2026-08-24

**`doctor --drift` printed `no drift ✔ (74 item(s) compared)` over a tree containing a file it
never compared.** 1.45.0 shipped `claude/agents/reference/ENVIRONMENT.ref` through all three
install lanes and added checks for both of them, and then doctor's drift families still globbed
`agents/*.md` only. The reference nine agent prompts point at could be edited, truncated or left
behind by a downgrade and doctor would keep saying the installation matched the repo.

Caught by reading the count rather than the verdict: 74 items before the file shipped, 74 after.
A number that does not move when the tree grows is the whole tell, and it is only visible because
1.14.0 made doctor print the count instead of a bare `no drift ✔`.

It is its own family rather than another entry in the `*.md` loop, because the glob genuinely
differs and the reason it differs is the point: a reference named `.md` installs as a nameless
agent. The stale-file scan gained the same directory, so a `.ref` this repo stops shipping is now
reported as a leftover instead of sitting there forever.

Adding the family turned check 41 red on the way in, which is the check working. Its positive
control builds a stub tree with one member in every drift family and requires doctor to green it;
doctor grew a family, the stub did not, and the control failed over a tree that was in fact
identical. The stub now derives its members from the same list, so a future family cannot pass by
being absent from the fixture.

## 1.45.0 — 2026-08-24

**Nine agents now carry a pointer to `claude/agents/reference/ENVIRONMENT.ref`, and the extension
is load-bearing.** Claude Code walks an agent directory recursively and loads every `*.md` at any
depth. Confirmed against the shipped binary rather than inferred:

    if(d.isDirectory())return a(p,[...c,d.name]);if(d.isFile()&&d.name.toLowerCase().endsWith(".md")

`marketplace.json` sets `"source": "./claude"`, so writing that reference as
`claude/agents/reference/ENVIRONMENT.md` would have installed it as a plugin agent called
`vstack:reference:ENVIRONMENT`, description auto-filled `"Agent from vstack plugin"`. A nameless
entry in the dispatcher's list, manufactured by the audit that was looking for exactly that shape.
**Check 46** holds the line in both directions: no `*.md` below the top level of `claude/agents/`,
and a planted one must be found, so the detector cannot quietly stop detecting.

The reference shipped free on the plugin lane and on no other, so `install.sh`, `overlay.sh` and
`uninstall.sh` now carry it too. Check 45 gained the install-lane assertion and check 46 the
overlay one, both reading the destination rather than the installer's exit code: the overlay copy
ends in `2>/dev/null || true`, which is silent by construction, and row 46 points it at a decoy
directory to prove the check notices.

Contents are commands run on this machine, not recalled. Two facts this repo has been repeating in
agent briefs were wrong, and both were caught by running them:

- **`grep -q` under `pipefail` does not always return 141.** `printf 'a\nb\nc\n' | grep -q a`
  exits 0; `seq 1 2000000 | grep -q '^1$'` exits 141. It fires only when the producer still has
  more than a pipe buffer to write. That conditionality is the whole trap: green on a fixture,
  141 on a corpus. The flat rule made the failure mode invisible.
- **`sort -V` works here.** `/usr/bin/sort` is 2.3-Apple and orders `1.9` before `1.10`. It had
  been listed with the genuine bash 3.2.57 gaps, which are `mapfile` and `declare -A`.

Cost: about 90 tokens per dispatch for the pointer, about 1,750 more only if an agent reads the
file. What it cannot do is make any agent read it, and this repo has already measured that
instructions in context do not reliably change behaviour. The claim is that a rediscovery cost
moved, not that a correctness floor rose. Falsifiable: sample the next 30 dispatches to the nine
pointed agents; if `| tail`, unguarded `grep -q`, and exit-code-instead-of-`conclusion` do not
fall against the same corpus's baseline, and reads of the reference stay under 20%, delete the
pointers and keep the file as human documentation.

**`design-reviewer` and `accessibility-auditor` both claimed a running UI before shipping.** Same
trigger, same object, and design-reviewer's phase 4 audited WCAG 2.1 AA while accessibility-auditor
audits 2.2 A+AA, so two agents reviewed the same screen to two different bars and a dispatcher had
no way to choose. This is the shape that measured *both* skills failing to fire rather than one
winning. WCAG conformance is now accessibility-auditor's alone; design-reviewer notes what it
cannot miss and hands off. Its missing `tools:` field also got a comment saying why it is missing:
omitting it is the only way the agent inherits ToolSearch and the browser tools, and a future
tightening that adds the field would remove browser access while the agent kept filing reports.

Audited by MEESEEKS M-7 (28 skills), NOOBNOOB N-2 (15 commands), JAGUAR J-1 (install lanes),
ZEEP Z-4 (14 agents), MORTY M-8 (command rewrites).

## 1.44.0 — 2026-08-24

**`uninstall.sh` deleted the user's own hook entries and reported that it had removed vstack's.**
Ownership was decided by directory prefix: any entry in `settings.json` whose command started with
`~/.claude/hooks` was treated as vstack's. That directory is the conventional place for a person's
own hook scripts, and vstack installs into it rather than owning it. So a stranger who kept
personal hooks there ran `uninstall.sh --yes` and lost every entry pointing at them, while the
scripts themselves stayed on disk and the tool printed `cleaned ... (vstack hooks, overrides and
unedited policy keys removed)`. A destructive step reporting a narrower scope than the one it
performed, which is worse than the deletion: the operator has no reason to go looking.

The correct signal was already in this repo. `install.sh` derives the basenames vstack ships and
matches `endswith("/hooks/" + name)`; the merge half had it right and the removal half never
asked. `.statusLine` had the same defect for the same reason. Both now match on shipped filenames.
Recoverable in the old behaviour only via `$BK/pre-uninstall/`, which the tool never mentioned.

Found by exercising a real install-then-uninstall under a throwaway `HOME` with a foreign hook
seeded first, not by reading the jq. Reading it is how it passed review the first time.

**Check 45, `uninstall keeps foreign settings, drops its own`.** Both directions against the real
scripts under a temp `HOME`: the user's `Notification` entry and their `statusLine` must survive,
and every hook this repo ships must be gone. A fix that removes nothing passes the user's half
trivially, which is why the second direction is not optional. Row 45 reverts the one line to the
prefix test and the check goes red naming itself.

**Check 20's extractor was an allow-list wearing a scanner's clothes.** It matched only
`~/.claude`, `~/.config/agents` and `~/.conductor`. `/push` told the model to run
`~/.100xprompt/hooks/pre-push.sh`, another tool's template path, in a command this repo installs.
The check written to catch exactly that could not see it, because the string did not begin with
one of three blessed prefixes. The check that exists because `/bootstrap` pointed at a script
nobody installs was blind to `/push` pointing at a script nobody installs, one namespace over.

It now reads every `~/`-rooted path. A path outside the installed namespaces has to be declared in
`external_path()` with a reason; today that list has one entry, the repo checkout itself. Turning
it on surfaced five references across four commands. Row 20 only ever mutated inside a blessed
prefix, so it proved the half that already worked; **row 20b** adds the foreign-namespace lane.

**Five of fifteen commands were reference documents wearing a command's frontmatter.**
`push.md`, `observability.md`, `deploy.md`, `release.md` and `security.md` shipped in the initial
commit from a foreign template (`## Usage` and `## Implementation` sections, tool tables, code
samples) with no imperative instruction to the assistant anywhere in the body, and were never
touched again. Between them they documented six argument interfaces (`/deploy vercel`,
`/release patch`, `/security network`, `/security full` and others) whose `case` statements lived
inside fenced blocks describing hypothetical standalone scripts at `~/.local/bin/deploy` and
`~/.local/bin/release` that this repo has never installed, plus `~/nuclei-templates`. All five are
now numbered instructions against tools that exist: `push` runs the real gate and names the
`vstack trust` step, `deploy` defers to `bin/deploy-auto.sh`, `release` defers to the
`release-manager` subagent it duplicated, `security` marks its external scanners as user-supplied.
`observability.md` also had a PostHog JS snippet fenced as `bash`, so it failed `bash -n`.

**`doctor --drift` filed vstack's own logs under "presumed yours".**
`vstack-delegation-log.jsonl` and `vstack-replay-log.jsonl` are written by shipped hooks and were
absent from `RUNTIME_TOP`, so on any machine that had actually used vstack, doctor told the
operator its own output might be a stranger's leftover. The names are now derived from the shipped
hooks rather than listed by hand. The replay log arrived in 1.43.0 and a hand-kept list would
have gone stale the same afternoon. Cosmetic: `DRIFT` was never set by it.

## 1.43.0 — 2026-08-24

**`vstack-delegation-log.jsonl` recorded only per-Stop aggregate counts, never which subagent ran
or how it went.** A session that fanned out to two dozen helpers and got a uniform 0/5 across
five fixtures could not be diagnosed afterward, because no record of the individual dispatches
survived past the transcript. `claude/hooks/dispatch-counter.sh` (PostToolUse, matcher
`Agent|Task`) now also appends one row per dispatch to
`${CLAUDE_CONFIG_DIR:-$HOME/.claude}/vstack-replay-log.jsonl` -- a single well-known file,
`VSTACK_REPLAY_LOG` overridable, findable without knowing a session id, never the same file as
the delegation log. Each row carries `ts`, `session_id`, `dispatch_index` (the same per-session
counter that already drives the statusline), `tool_name`, `subagent_type`, `description`, and,
instead of the prompt/result text itself, `prompt_bytes`/`result_bytes` (size only -- a replay
log full of verbatim prompts is a secret-leak surface, and oh-my-claudecode's own friction report
uses the same instinct to analyse context bloat without exposing prompts). `duration_ms` and
`tool_use_id` are carried too: both are already present on the real PostToolUse payload (confirmed
by reading this CLI build's own hook-input constructor, not assumed) and cost nothing extra to
record -- `duration_ms` is the field that actually answers "how did it go" without touching
content at all. Rotation reuses skill-mandate.sh's existing `_delegation_log_row()` cap (2MB,
keep last 5000 lines) rather than inventing a second policy. `VSTACK_NO_REPLAY_LOG=1` disables the
replay row alone; `VSTACK_NO_DISPATCH_COUNT=1` (pre-existing) disables it along with everything
else in this hook. First version of this change added the row via three more jq calls plus two
`wc -c` pipes per dispatch and measured 72.8ms mean / 74.9ms p95 (n=30) against this hook's own
24.1ms/27.3ms baseline -- almost entirely macOS fork+exec overhead, and well past the ~25ms p95
this hook is held to. Folded into the SAME single jq call the hook already spent on
tool_name/session_id, plus a `[ -d ]` guard before `mkdir -p` and sampling the rotation `stat`
check to 1 dispatch in 20: re-measured back to back against a stashed pre-change baseline on the
same machine, mean=24.5ms/p95=26.8ms against baseline mean=24.8ms/p95=25.9ms -- statistically
flat. Verified end to end against the wired hook, not a hand-made fixture: real dispatch-shaped
payloads (Task and Agent tool names, a Write tool call that must be ignored, a malformed dispatch
with no `tool_input` at all, and a non-ASCII description/prompt) produced exactly the rows
expected, with `~/.claude/vstack-delegation-log.jsonl` (a live 92-row measurement corpus)
unchanged in line count before and after every run, and `~/.claude/vstack-replay-log.jsonl` never
created by any test in this suite. One gap stated rather than left to be discovered: this hook's
matcher never sees `PostToolUseFailure`, which carries `error` instead of `tool_response`, so a
dispatch that *failed* is invisible to the replay log. The rows record what ran, not what broke.

> **Retraction note added in 1.47.0: the "uniform 0/5 across five fixtures" above is unsourced.**
> No runlog, no transcripts and no fixture list survive for that arm, and the harness cannot
> produce that shape: at `tests/dispatch-fleet.sh:678-688` only `kind=="skill"` and
> `kind=="none"` fixtures receive a numeric `k`, so a `CHAIN:` or `AMBIGUOUS:` fixture returns
> `{k: null}` and can never print `0/5`. The defect this paragraph describes is real and the fix
> shipped; the measurement quoted as its motivation cannot be re-read. Kept with the reason
> attached rather than deleted, as `tests/evals/RESULTS.md` keeps its retracted run.

## 1.42.0 — 2026-08-23

**The cloud sandbox gate has never armed, and has shipped inert since v1.30.0.** `overlay.sh`
generates the sandbox setup line as `bootstrap.sh | bash && vstack trust`. Commit `5922ccf` gave
`trust` a TTY confirmation prompt; a sandbox bootstrap has no terminal, so every cloud sandbox
since then has hit `no terminal to confirm on; re-run with --yes to accept unseen`, exited 1, and
never written the trust hash. Without that hash `verify-gate.sh`'s Stop hook stays unarmed
permanently, which means the mechanism commit `757f3c9` was written specifically to guarantee -- a
failing `.claude/verify.sh` blocks the agent -- has been dead on arrival on every real sandbox for
twelve releases. The setup line now passes `--yes`, which is what the comment above it already
argued for: a line committed to a file, in a repo somebody deliberately dispatched work to, is the
consent, and the prompt exists for the case where nobody read it. `tests/install-matrix.sh`'s
cloud-gate lane was calling `trust` without `--yes` and so was testing a command the setup line
does not run; it now mirrors the generated line exactly. Matrix 23 passed, 0 failed.
(SCARY-TERRY T-1.)

**Nothing in this repository ever read the CI conclusion, so GitHub Actions failed on `main` for
six consecutive runs across two releases without anyone noticing.** The lane that catches the
defect above was correct and red the entire time. The gap was never the test: `bin/doctor`,
`.claude/verify.sh` and the release flow all inspect local same-machine state, and a falsifiable
gate still gets ignored when nothing puts its result in front of whoever is shipping. `bin/doctor`
now reads the `conclusion` field for the last run on `main`, never an exit code, and fails the
overall verdict on `failure`, `cancelled` or `timed_out` while naming the run and printing the
command to read its logs. A run still in progress carries a null conclusion and is reported as
neither pass nor failure. Every reason the check cannot run -- no `gh`, no auth, no network, no
remote -- prints which dependency is missing rather than a bare skip. Five-second timeout.
(PICKLE-RICK P-5.)

**Two more cleanup globs disarmed by the same refactor.** The mandate latch split in `f4f5468`
inserted a `ckpt-` segment into the counter filenames, and every glob anchored before that point
stopped matching. `.claude/verify.sh`'s check 27 swept `vstack-mandate-vfy-*`, which matches none
of the `vstack-mandate-ckpt-vfy-*` files the hook now creates, and the comment directly above that
line documents it as the fix for contamination already found once -- a guard explaining why it
matters while matching nothing. Check 40 was missing the `.delegate`, `.delegate-ts` and
`.delegate-scan` siblings the hook hangs off the counter. Both are now anchored on both ends, and
`tests/test-breadth-mandate.sh` got the identical fix in `76d2366`. That makes five guards one
refactor disarmed in a single day, counting the three falsifiability rows in v1.41.0, none of which
went red.

The leak turned out to be inert to check 27's assertions, and the reason it was inert is worth more
than the fix: the leaked file feeds only the delegation-log row, which that check disables. But
seeding a *pre-latched* counter before the first call makes all three probes return empty and the
check still passes, because case `g` asserts only on the third probe and pipes the first two to
`/dev/null`. A session that never blocked once is indistinguishable from one that hit the latch
legitimately. Recorded rather than fixed; the fix belongs with the assertion, not the cleanup.
(BIRDPERSON B-7 fixed the globs and found the weakness; NOOBNOOB N-1 fixed the sibling glob.)

## 1.41.0 — 2026-08-23

**The statusline's dispatch counter had a reader and no writer.** `claude/statusline.sh` renders
`RICK ·N▸` from `${TMPDIR:-/tmp}/vstack-dispatch-count-<session_id>`, and nothing in the shipped
tree ever created that file. The segment was verified against a counter created by hand, so it
passed its own test while rendering nothing in production, for every session, forever. The reader
was written to a contract its author also specified, which is the failure: both halves were
correct against a document and neither was correct against the other. `claude/hooks/dispatch-counter.sh`
is the missing half. It runs on `PostToolUse` with matcher `Agent|Task`, takes the `mkdir` lock
already proven in `skill-mandate.sh` rather than a new one, never opens the transcript, and creates
the file on first dispatch rather than at session start -- absence is how a session that has not
delegated renders nothing instead of a confident `·0▸`. Measured at 15.2 ms mean, 21 ms p95 over
n=30 against a real dispatch, and proven end to end rather than in halves: twenty parallel
dispatches land a counter reading exactly twenty, and the unmodified statusline renders that number
from the writer's own file. Wired into the project lane and into `install.sh`'s user-lane rebuild,
which is the lane that also installs the statusline. Deliberately **not** wired into the plugin
lane: that lane ships routing and the verify gate and does not install a statusline, so a counter
there would be the same defect pointing the other way. `VSTACK_NO_DISPATCH_COUNT=1` turns it off.
(POOPYBUTTHOLE P-4 built the reader and found the cost; MORTY M-5 built the writer.)

**The delegation mandate went deaf for whole sessions, silently.** `skill-mandate.sh` carried one
two-strike latch shared by every mandate family, so two early unrelated skill mandates in a session
disarmed the delegation breadth mandate for the rest of it. Measured on the session that prompted
this: all seven Stops between 12:34 and 13:38 logged `latched:true` with every count null, while a
forced re-scan of the same session measured `dir_count=36 ext_count=61 task_count=90`. The latch is
now split. The skill family keeps its two strikes per session with no re-arm. The delegation family
gets its own counter that re-arms after `VSTACK_DELEGATE_RESET_SECS` (default 1800), plus a re-scan
cooldown, `VSTACK_DELEGATE_SCAN_COOLDOWN_SECS` (default 60), so a session latched on skills and
never eligible for breadth does not pay the 1.4-2.1 s transcript scan on every Stop. That cost is
measured, not assumed: 1438 ms mean at 17.5 MB and 2009 ms at 39.1 MB, which is also why sampling
was rejected. A latched Stop now writes a row carrying `latched:true` and explicit nulls instead of
writing nothing, because a Stop that was never measured and a Stop that measured zero breadth are
different facts and the log could not previously tell them apart. The breadth message names up to
three of the directories it actually found. (MEESEEKS M-4, MORTY M-5.)

**A per-prompt mandate line.** `inject-session-context.sh` now prints `MANDATE skill=N/2
delegate=M/2` on each prompt, read from the two counter files rather than by parsing the
transcript, and silent at `0/0`. Steady state costs 305 B of the 512 B budget, worst case 470 B.
Until now the only way to discover a latched mandate was to read the log after the fact. (MORTY M-5.)

**`tests/delegation-drift.py` crashed on the rows the fix above started writing, and reported
success while doing it.** `eligible()`, `delegated()` and `detect_broken_extraction()` all used
`.get(key, 0)`, which returns the default only when a key is *absent*; a latched row carries an
explicit `null`, so each raised `TypeError` on live data -- 13 of 76 real rows by the time it was
found. The harness printed the traceback and exited 0. Both halves are fixed. A latched row is now
excluded from every pool by a named `measured()` predicate rather than silently counted as
zero-breadth or not-delegated, and the number excluded is printed unconditionally in the accounting
line, since a silent zero here is the same shape as the bug. On failure the harness now prints an
unmissable banner to stdout, which survives a caller's `2>/dev/null` or `| tail`. Proven by
mutation against the actual pre-fix analyser. (GLOOTIE G-5.)

**Three falsifiability rows had stopped mutating anything, and this release is what broke them.**
Rows 23, 27 and 40 anchored their `sed` patterns on lines that the latch split and the destructive
guard's refactor moved or deleted, so the mutation applied cleanly, changed nothing, and the checks
they guard were green with no evidence behind them. The suite's own shasum no-op detector is what
caught it, which is the detector doing the single job it was added for. Row 23 now no-ops every
`emit deny` call site, including the inline duplicate the refactor created, and leaves ask and allow
alone. Row 27 makes the mandate's decision gate unconditional. Row 40 skips only the row-write
inside the latch, so the latch still exits and only the logging claim is falsified. Each was watched
red under its new anchor and restored shasum-identical. The anchors were chosen on the decision
logic each check asserts rather than on whatever line was unique that day, which is what let all
three rot through a single refactor. `VSTACK_FALSIFY_ROWS=27 ./tests/gate-falsifiability.sh` now
runs a subset, because a twenty-minute sweep is why nobody notices a rotted row for four
releases. That selector shipped with the defect it exists to catch: a row id with no mutation
arm mutated nothing and then reported `did NOT fail when broken`, which is the one sentence
this suite must never say about a check it did not test. An unknown id is now a hard error
naming the id and stating that nothing was mutated, a comma-separated value is rejected with
the accepted spelling, and the header and footer count the same rows instead of disagreeing
about whether the baseline probe is one of them.
(BIRDPERSON B-4 built check 44; BIRDPERSON B-5 found and repaired all three rows.)

The two entries below landed before the tag and are gate machinery rather than shipped
payload, which is why they carried no version bump of their own.

**Closed two holes in `tests/auto-trigger.sh`'s tool fence, both found in live transcripts rather
than by reading.** `Workflow` was never denied, and it is `Agent`'s capability class — a sample
called it, and it launched in the background, wrote a generator script into `~/.claude/projects/`
and fanned out to eight parallel subagents each told to edit a fixture. The denial did propagate
and nothing was touched, which is exactly the guarantee the fence's own `Agent` comment says
cannot be relied on: the safe outcome came from an implementation detail. `Workflow` is now
denied, along with `Explore` and `Task` on the same reasoning, after an audit of every tool name
in the CLI binary with a written verdict per name — the two confirmed by transcript are recorded
separately from the two denied defensively at zero cost. Second, `fence_violations()` compared the
file *listing* before and after, so an in-place `Edit` or a `Write` over an existing path left it
byte-identical and it reported clean while 32 edit attempts were made against seeded fixtures. It
now hashes fixture contents and names the modified file. The regression test was checked against
the old logic, which returns nothing on the same mutation. Writes outside the work directory stay
outside what this function sees, stated in the comment rather than left to be assumed: hashing a
peer's live working set in a shared checkout is its own hazard, and the tool denial is what
actually stood between that sample and the write. (EVIL-MORTY E-44.)

**Added `tests/dispatch-fleet.sh`**, the fleet-wide dispatch measurement over the 54 frozen
fixtures in `~/vstack-dispatch/`. `auto-trigger.sh` measures recall per skill and nothing else;
this scores the four classes separately, because a harness that fires everything scores perfectly
on recall alone. Precision comes from the eight `neg-*` fixtures where the correct answer is no
skill at all, the fifteen `col-*` fixtures probe the overlap clusters found by reading the
descriptions rather than by measurement, and the six `var-*` fixtures restate the same intent
with none of the description's literal trigger words, so a library working as a keyword index
scores well on `pos-*` and collapses on `var-*`. One sample is one raw non-retrying invocation;
the retry-based case run this repo used before stops at the first success and measures "did it
ever fire" rather than a rate. Raw k/n with two-sided 95% Wilson intervals, never a bare point
estimate: at n=10 that separates "never fires" from "fires at least about half the time" and
nothing finer.

Proven against stubs with no model calls spent. Both directions of the oracle control bite — an
all-firing stub scores `75/75` recall against `0/24` precision, a never-firing stub the exact
reciprocal — and the bad-selector guard was verified by reproducing the historical
`0 passed, 0 failed, exit 0` defect under mutation. Resumption is guarded: the run log header
pins model, turn budget, fence and fixture path, and a resume whose parameters disagree refuses
by naming the field rather than silently mixing two arms into one k/n. `ToolSearch` is logged
rather than denied, since denying it moves the measured environment away from the one real
sessions run in, and `Skill` can never enter the fence — a runtime guard exits 2 at startup if it
does, because denying it removes the skill listing from context entirely and the harness would
measure a fleet that is not mounted. No fleet-wide figure may be published until arm A5 of
`tests/evals/build-the-lever/PREREGISTRATION.md` reports, since the fence this harness inherits
may itself suppress every skill whose output is an artifact. (SUMMER S-3.)

## 1.40.0 — 2026-08-23

**The instrument built to measure long-session delegation drift went blind in exactly the sessions
it exists to measure.** `skill-mandate.sh`'s 2-strike latch — `[ "$cnt" -ge 2 ] && exit 0`, the
guard that stops a mandate the model cannot satisfy from trapping a session — sat above both the
checkpoint counter and the delegation logger. Once a session accumulated two mandate strikes every
later Stop exited before logging, permanently. Long, multi-directory sessions are the ones that
latch, and long, multi-directory sessions are the entire population `tests/delegation-drift.sh`
was built to describe, so the log was not merely sparse: it was filtered against its own subject.
Proven by a synthetic 3-Stop drive rather than inferred from an empty file — Stop 1 gives cnt=1,
ckpt=1, one row; Stop 2 gives cnt=2, ckpt=2, two rows; Stop 3 latches and leaves both frozen.
The checkpoint counter moved above the latch, and a latched Stop now emits
`{latched:true, dir_count:null, ...}` before exiting; the full-evaluation row carries
`latched:false`. Both paths share one `_delegation_log_row()`, so there is one rotation policy
instead of two copies to drift apart. Blocking behaviour is untouched. Check 40 now drives the
real hook through a synthetic multi-Stop session and asserts both directions, so this cannot
regress silently again. (MEESEEKS M-4; check 40 and row 40, BIRDPERSON B-3.)

Logging the full counts on a latched Stop was proposed and rejected on measurement, not taste.
The full evaluation path costs ~116ms on a one-line synthetic, which reads as affordable; on this
machine's real transcripts it is 1438ms mean / 1536ms p95 at 17.5MB, and 2009ms / 2114ms at
39.1MB, because the mandate pipeline scans the transcript five-plus separate times. Sampling one
latched Stop in ten would still stall the end of a long session by 1.4-2.1 seconds, on precisely
the population this latch exists to protect. The reasoning and the bar for revisiting it — a
measured p99 under 200ms against this file's own real transcripts, not another synthetic — are
recorded at the latch.

**Both drift instruments counted subagent sub-transcripts as independent sessions.** 965 of 3292
files under `~/.claude/projects` are per-subagent leaves nested inside a parent session, and an
unbounded `find` admitted each as a top-level session at equal weight. Live, not theoretical: 15
of 51 replayed sessions were leaves of two parents, 13 of them from one. A session that fans out
that fanned out to thirteen leaves counted as fourteen. For `delegation-drift.sh` the exclusion is outright — a leaf's turn
1 is not the parent's turn 1, so it has no position in the lifetime being measured, and the parent
transcript already records the `Task`/`Agent` call that spawned it, so counting the leaf counts
one delegation twice. For `compaction-effect.py` the reasoning is different and is written down as
different: a compaction inside a subagent is a real event, excluded from the primary for pooling
independence rather than validity, and the excluded count now prints on its own line so a zero is
stated instead of assumed. Neither instrument's current numbers moved — `contributing_sessions`
held at 3 because the leaves were already failing the single-checkpoint filter, and all 8 compact
boundaries were independently confirmed top-level. The defect had not yet reached a printed
number. It would have. (GLOOTIE G-5.)

`tests/compaction-effect.sh` crossed from NOT EVALUATED to a result: **no signal.** `is_error`
across 3 qualifying auto boundaries reads 1/45 pre against 0/45 post (ratio 0.00x), and across 6
manual boundaries 5/90 against 7/90 (ratio 1.40x), both under a 1.5x threshold. `autoCompactWindow`
at 300k neither helps nor hurts the error rate at the sample available on this machine. The corpus
that unblocked it was boundary count and pooled calls, not session count. `delegation-drift.sh`
remains honestly NOT EVALUATED at 2 and 3 eligible windows against a floor of 8, and its secondary
block now carries the contributing-session count and no-verdict qualifier on the rate lines
themselves rather than in a header a reader can skim past. (GLOOTIE G-5.)

**Added `tests/plugin-manifests.sh`**, the by-hand authenticated-machine harness for the one lane
`tests/container-matrix.sh` structurally cannot measure, because a throwaway container never
installs `claude`. Eight checks, both positive controls biting: a validator that stops
discriminating aborts the run at rc=2 rather than reporting its silence as health, and neutered
`ok`/`bad` helpers trip the `ran == 0` floor. It covers what check 19 never did — cross-referencing
`claude plugin details`'s live component inventory against disk, every skill, command and agent
entry matched, plus SKILL.md presence and `hooks.json` script resolution. A skill directory with broken
frontmatter that the loader silently drops passes `claude plugin validate` and fails here. Also
disproved a standing assumption while building it: `plugin validate` and `plugin details` are
static and local, answering correctly under an empty unauthenticated config dir. (BETH C-3.)

**Pre-registered the `principle-build-the-lever` investigation** at
`tests/evals/build-the-lever/PREREGISTRATION.md`, with thresholds written before any run: confirm
at k>=8/10, falsify at k<=2/10, 3-7 reported as nothing else, whole run void if the control drops
below 7/10. Stage 0 spent 3 calls to establish that the skill description reaches the model
verbatim at `MODEL=sonnet` — byte-identical, 171/171 — killing the worry that
`skillListingBudgetFraction` was truncating the listing on the model the suite actually pins, and
establishing that the six dead hypotheses were tested against text the model really saw. Two
findings about the harness came out of the discarded probes. `ToolSearch` is absent from
`auto-trigger.sh`'s `--disallowedTools` and this build has a deferred-tool registry: two turns
went to tool discovery returning `No matching deferred tools found`, which is the entire budget of
a case at the suite default of 3. That is not evidence any case has lost turns; it is evidence
nobody has looked. And `Skill` must never be denied in any harness — deny it and the skill listing
is not in context at all, so the harness measures a fleet that is not mounted. (ZEEP Z-3.)


## 1.39.0 — 2026-08-23

**The headline curl-pipe installed three Claude Code plugins and edited another vendor's config
file, with no disclosure and no opt-out.** `bootstrap.sh`'s one-liner ran `setup-machine.sh`,
which installed `claude-mem` (`thedotmack/claude-mem`, third-party), `frontend-design`
(Anthropic's own, but not vstack's to enable) and `typescript-lsp`
(`anthropics/claude-plugins-official`) unconditionally, and — whenever `claude-mem` was found on
disk — flipped `claude-mem`'s own `UserPromptSubmit` hook from sync to async directly inside
`claude-mem`'s `hooks.json`, a file this repo does not ship. Found by SCARY-TERRY's
stranger-README audit of v1.38.0. All three plugins now require `--with-plugins` or
`VSTACK_PLUGINS=1`; the default path names what it is skipping instead of silently doing it. The
`hooks.json` edit stays, because `claude-mem` ships that hook synchronous and it blocks every
prompt otherwise, but it is now gated on the plugin actually being present (idempotent
maintenance of something already opted into, not an install triggered by this run) and reversible:
the first edit leaves a `hooks.json.vstack-orig` sidecar that `./uninstall.sh --yes` restores. A
real bug surfaced while testing this: the maintenance loop ran even under `--dry-run`/`--check`,
which both promise to touch nothing — fixed in the same commit. `uninstall.sh` also stopped
leaving `mcpServers.cloudflare-mcp` and `.context7` dangling in `~/.claude.json` after removing
the `cloudflare-mcp` wrapper (Claude Code then tried to spawn a command that no longer existed);
ownership of each entry is now decided from the install-time backup, so an entry the operator
edited since, or added themselves — like their own `context7` — survives removal. (`e7fd56c`,
GLOOTIE G-4; README hunks in the same commit carry POOPYBUTTHOLE P-3's per-lane "what lands
where" and "confirm it worked" sections.)

**`/doctor` reported a healthy plugin-marketplace install as broken.** Both `bin/doctor` and
`claude/commands/doctor.md` assumed the full `git clone` + `./install.sh` layout —
`~/.claude/{hooks,agents,skills}` — so a `claude plugin marketplace add itsvedantkumar/vstack &&
claude plugin install vstack@vstack` install, whose payload lives under
`~/.claude/plugins/cache/vstack/vstack/<version>/`, failed every check that assumes hooks, CLI
wrappers or a shell lane exist, which that lane never installs by design. Both now detect which
lane actually landed — preferring `plugins/installed_plugins.json`'s recorded install path, and
falling back to the newest cache directory by mtime rather than a hardcoded version — and check
the right location, or say plainly that no install was found at all. Verified against a real
plugin-marketplace install, a real full install, and no install, in throwaway
`HOME`/`CLAUDE_CONFIG_DIR` directories. (`d129d3d`, POOPYBUTTHOLE P-3.)

**`enabledPlugins` claimed `typescript-lsp` was on for every install, and the default install no
longer installs it.** This is the same defect class `CHANGELOG.md`'s v1.29.0 entry fixed for
`claude-mem`: `claude/settings.json` carried `"typescript-lsp@claude-plugins-official": true`
unconditionally, and that was true when `setup-machine.sh` installed the plugin by default, but
`e7fd56c` (above) made it opt-in, so a default install now ships a settings file asserting a
plugin is enabled that the toolchain never installs. `typescript-lsp` is official
(`anthropics/claude-plugins-official`), not third-party like `claude-mem`, but that difference is
immaterial to this defect — the failure mode is "settings claims enablement, install path does
not deliver it" either way, not a supply-chain question. `claude/settings.json`'s `enabledPlugins`
is now `{}`, asserting no plugin is enabled by default, matching what the default install
actually does for all three plugins. No hard dependency on the key's prior value was found —
`bin/doctor`'s `enabledPlugins` reference checks the key exists at all (for the overlay's
project-key gate), not what it names; `tests/install-matrix.sh`'s `overlay-preserves` case uses a
fictitious `theirs@x` plugin name, not `typescript-lsp`; `claude/settings.project-keys` lists
`enabledPlugins` among the keys deliberately never overlaid into another repo, unaffected by its
value.

Fixing this exposed a second, related defect in `install.sh`'s settings merge, present since the
`claude-mem` fix and reproduced for `typescript-lsp` the moment its key was added there too:
`del(.enabledPlugins["claude-mem@thedotmack"]?)` ran unconditionally on every `./install.sh`, so a
user who opted in with `--with-plugins`/`VSTACK_PLUGINS=1` — and therefore has the plugin for
real — had their own explicit choice silently undone on the next reinstall, because `install.sh`
cannot see a flag passed to `setup-machine.sh` in an earlier, separate run. `e7fd56c`'s commit
body named this and left it for `install.sh` to decide. Fixed here rather than left standing:
`install.sh` now runs `claude plugin list` — the same presence check `setup-machine.sh` already
uses — before the merge, and only strips a plugin's `enabledPlugins` entry when it is not actually
installed; an entry backed by a real install survives every future reinstall. Verified in a
throwaway `HOME` both ways: a live install with the plugin present keeps its entry across a
reinstall, and a stale claim with nothing backing it (no plugin cache, as on any fresh
`--with-plugins`-less machine) is stripped, in both cases leaving an unrelated foreign
`enabledPlugins` key untouched.

## 1.38.0 — 2026-08-23

**`principle-type-system-discipline` almost never fired. Rewriting its description around the
nouns a user actually types moved it from 1/10 to 9/10 at n=10 — matching the control's rate.
The same rewrite method applied to `principle-build-the-lever` did not move it.**

The shipped description read "Apply when designing types or a function signature in TypeScript,
Rust, Go, or other statically-typed code" — mechanism vocabulary, not language a prompt actually
contains. Rewritten to name the concrete shapes instead: "Apply when a struct, enum, or type can
hold an invalid combination of fields that shouldn't compile," dispatched at 9/10, matching the
control. `principle-build-the-lever` got the identical treatment — surfacing its own literal
nouns in place of mechanism language — and it did not move: 2/10, sitting exactly on the
pre-registered falsification floor, and the rewrite was reverted rather than shipped. A method
that fixes one skill's dispatch rate and fails to fix another is a real finding about the limits
of the description-rewrite lever, not a pattern to repeat blind — record both halves or the
failure gets silently forgotten the next time someone reaches for the same trick.

**`skill-mandate.sh` now logs delegation counts per Stop, for measuring the breadth mandate's
effect on delegation behaviour going forward instead of only its blocks.**

The Stop hook already computes `dir_count`/`ext_count`/`task_count`/`named` to decide whether to
block; this appends one line per evaluated Stop to a JSONL log (`session_id`,
`checkpoint_index`, the four counts, `ts`). Counts only — no paths, no file contents, matching
the discipline the mandates already apply before anything reaches a block message. Logs
unconditionally, blocks conditionally, so the log reflects the rate the mandate is trying to
move rather than only the cases it already caught. Opt-out `VSTACK_NO_DELEGATION_LOG=1`, same
shape as the existing `VSTACK_NO_MANDATE` escape hatch; `VSTACK_DELEGATION_LOG` overrides the
destination. Capped at ~2MB with `tail`-and-atomic-`mv` rotation to the last 5000 lines, checked
with one O(1) `stat` per Stop rather than a line count. Measured latency: 28.3ms with the logger
active vs 28.6ms without, over 60 samples at σ≈1.9ms — indistinguishable from zero.
`tests/delegation-drift.sh` (+ `delegation-drift.py`) is the accompanying analyser: pre-registered
thresholds, states its own reverse-causality confound, and reports NOT EVALUATED rather than a
rate below its eligible-window floor — the correct, expected result on day one, confirmed
against this machine's own data.

## 1.37.0 — 2026-08-23

**The delegation and agent-naming mandates counted a tool name that does not exist in this
build.**

`skill-mandate.sh`'s `task_count` matched only `tool_use` blocks named `Task`, the classic Claude
Code CLI's dispatch-tool name. This build's SDK calls the same tool `Agent`. Measured against a
real 15MB transcript: 70 `Agent` dispatches, 0 `Task` matches. Two mandates read that count: the
breadth/delegation mandate reported "zero subagents" over a session that ran 70 of them, and the
agent-naming mandate -- gated on that same count being >= 1 -- was structurally unable to ever
fire and had never fired in any install since it shipped, despite call-sign naming being a
specific, standing request from the repo owner. The enforcement was inert and silent, and silence
reads like compliance. Fixed by counting `Task` or `Agent`. `TaskCreate` was checked and
deliberately excluded: its `.input` shape is `{subject, description, activeForm}`, a checklist
item, not a dispatch call.

Second defect in the same hook: the Bash-write path extractor added in v1.36.0 was reading
write-shaped lines out of heredoc *bodies* as if this session had performed them, and treating
any `$VAR`-containing redirect target as a real file. A `cat > /tmp/check35.sh <<'CHK' ... CHK`
block whose fixture body happened to contain `$g_empty/app/src/C.tsx` was reported as TypeScript
someone had written. On the same transcript: dir_count 53 -> 34, ext_count 83 -> 60, extracted
paths 345 -> 241, and the breadth mandate goes from firing on phantom writes to completely silent
on a session that made one real edit. `emit()` now drops any candidate containing an unexpanded
`$`, and a heredoc body is suppressed only once its opening line already matched a write rule --
so `cat >file <<EOF` (body is inert file content) is suppressed but `python3 - <<PY` (body is
executed and its real `open(..., 'w')` call is a genuine write) still counts. Latency cost: +74ms
(+13%) on the same transcript.

Also added: `prove-it-works`, a Stop-hook check on the assistant's own closing claim.
`principle-prove-it-works` scored 0/10 on its own fixture prompt because its trigger -- "apply
before declaring any task or fix done" -- is a condition on the assistant's forthcoming speech
act, not on anything in the user's prompt a skill matcher can score against. The equivalent check
now runs directly in the Stop hook, at the moment that condition is actually about: a turn that
edits a file and closes with a completion claim ("done", "it works now", "all tests pass", and
similar bounded phrasings), with zero Bash/Read/Task/Agent tool_use anywhere in the turn to back
it up, blocks naming `prove-it-works`. Deliberately generous in the silent direction -- any Bash
or Read call counts as evidence regardless of what it did or when in the turn it ran, relative to
the edit -- because a mandate that produces a false block teaches users to disable the whole gate.

Falsification: `tests/test-breadth-mandate.sh` PROOFs 7-9 cover prove-it-works (blocks on zero
evidence; silent after a real Bash call; silent on a purely conversational claim with no edit).
PROOFs 10-12 cover the two dispatch-hook fixes (Agent dispatch suppresses the breadth mandate the
same as Task; zero Task AND zero Agent still trips it; a `$VAR`-containing Bash write target is
not counted). All 12 proofs pass; the pre-fix hook was falsified by hand against the same
fixtures and restored byte-identical.

## 1.36.0 — 2026-08-23

**The breadth mandate counted Write, Edit and NotebookEdit tool calls and nothing else, so every
edit made through Bash was invisible to it -- which is most edits, in the one mode where the
model is told to prefer Bash over the dedicated file tools.**

Cutting v1.35.0 itself was the proof: six files across five directories and three extensions,
edited entirely with `sed -i` and `python3 - <<PY` heredocs, zero Task calls, and the
multi-directory mandate never fired. Bypass-permissions sessions are explicitly instructed to
"make file changes with sed, heredocs, or short scripts, rather than using the dedicated Read,
Edit, or Write tools" -- so the mandate was blind in precisely the mode where an agent is most
autonomous and least supervised.

`claude/hooks/skill-mandate.sh` now also scans every `Bash` tool_use block's `.input.command` for
a bounded set of write shapes -- `sed -i`/`sed -i.bak` targets, `>`/`>>`/`&>` redirection and
`tee`, `cp`/`mv` destinations, and Python `open(PATH, 'w'...)` calls with a literal string path
(which is what a `python3 - <<'PY' ... PY` heredoc writer looks like once flattened to one
string) -- and folds anything it recognizes into the same path set the breadth, prose and
TypeScript mandates already read. `grep`, `cat`, `ls`, `git add`, and `find` without `-delete`
still match nothing, so ordinary read-heavy Bash work stays silent; a guard that cries wolf on
reads gets disabled by the first person it inconveniences.

This is not a shell parser and does not claim to be one. Documented, not chased with more regex:
quoted paths with spaces truncate at the first space; a multi-target `sed -i`/`cp`/`mv`/`tee`
only yields its last target; commands invoked by full path, `sudo`, `xargs`, `eval`, or
`find -exec` are not recognized at all; a Python write through a variable, an f-string, or
`Path.write_text(...)` is invisible; and a literal `>` inside a quoted string on the same line
(`echo "a > b" > out`) or a `[[ "$x" > "$y" ]]` string comparison can add a spurious token to the
path set -- checked by hand before shipping, and both are bounded to a bare `$var`-shaped token
with no `/` and no `.`, which cannot alone supply the second directory or second extension the
conjunctive threshold needs.

Falsification: `tests/test-breadth-mandate.sh` PROOF 5 (three Bash-only writes via `sed -i`,
`sed -i ""`, and a `python3` heredoc, spanning three directories and three extensions, zero Task
calls) blocks naming `multi-directory work --`; PROOF 6 (five Bash-only reads -- `grep`, `cat`,
`git add`, `find`, `ls` -- across five directories) stays completely silent. Disabling the
`sed -i` rule alone turns PROOF 5 red; widening the `cp`/`mv` rule to also match `cat` turns
PROOF 6 red. Both proven on an isolated `/tmp` copy of the tree and restored byte-identical.

## 1.35.0 — 2026-08-23

**Eight routing entries pointed at skills that do not exist, and the check that exists to catch
exactly that was rewriting the names to make them resolve.**

The session hook's PRINCIPLES line routed eight situations to `prove-it-works`,
`fix-root-causes`, `encode-lessons-in-structure`, `type-system-discipline`,
`boundary-discipline`, `make-operations-idempotent`, `sequence-verifiable-units` and
`build-the-lever`. Every one of those is missing the `principle-` prefix the actual skill
directories carry. A model told to invoke `fix-root-causes` cannot resolve that against a listing
containing only `principle-fix-root-causes`, so where the description alone was not strong enough
to carry the match, no skill fired at all. That is 8 of 28 skills, 28.6% of the library, sharing
one broken clause.

Check 7 (`referenced skills exist`) scanned that prose and reported it clean, because it tried
`claude/skills/$tok` and then `claude/skills/principle-$tok`. The gate was more forgiving than the
runtime: it supplied the prefix the model has no way to supply. Its comment described this as
intended behaviour, which is why it survived review. Names must now resolve verbatim.

Found by running `tests/auto-trigger.sh`, the only suite that measures whether skills actually
fire, which nothing in CI runs and nobody had run since the descriptions changed. Four of the
eight principle skills were firing nothing at all.

Falsification: reverting one name to its short form makes check 7 print
`prove-it-works: referenced in prose but no such skill/agent/command`.

Not yet measured: whether fixing the names makes those four cases fire. That needs a re-run of
the eight principle cases, roughly 24 headless calls, and it has not been authorised.

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
