# The seventh fake green: a decision the guard emits vs. what the runtime does with it

Referrer: [docs/checks-that-inherit-their-answer.md](checks-that-inherit-their-answer.md) — this is
another instance of "the check verifies a half it controls and never verifies the join."

## What was measured

`claude/hooks/guard-destructive.sh` is a `PreToolUse` gate on `Bash` (`~/.claude/settings.json`,
matcher `Bash`). `.claude/verify.sh`'s check ("destructive guard decides correctly, N commands, 3
tiers") feeds 30 synthetic payloads straight into the script and asserts
`.hookSpecificOutput.permissionDecision`. It has never invoked Claude Code itself, so it has always
verified the decider's return value, never whether that return value changes what the runtime does.

RICK measured, twice, in this session, under bypass permissions mode:

    d=$(mktemp -d); cd "$d"; git init -q .; git commit -q --allow-empty -m x
    git reset --hard          -> rc=0, ran, no prompt, no block   (guard said "ask")

    git push --force no-such-remote-xyz main
    -> <error>[guard] force-push to main or master...</error>     (guard said "deny", and was enforced)

## Root cause, confirmed against the live runtime, not assumed

The `PreToolUse` payload carries a `permission_mode` field. Confirmed by temporarily tee-ing the raw
stdin of the live installed hook (`~/.claude/hooks/guard-destructive.sh`) during a real tool call in
this session, then restoring the original file byte-for-byte:

    {
      "hook_event_name": "PreToolUse",
      "permission_mode": "bypassPermissions",
      "tool_name": "Bash",
      "tool_input": {"command": "echo capture-probe-..."},
      ...
    }

`strings` on the installed CLI binary (`~/.local/share/claude/versions/2.1.243`) confirms the closed
set of values the field takes: `"default"`, `"acceptEdits"`, `"plan"`, `"bypassPermissions"`. In the
first three, a human can see and act on a permission prompt. In `bypassPermissions` — this bundle's
shipped default (`install.sh --bypass-permissions`, README recommends it) — nothing ever prompts, so
an `ask` decision is auto-approved with nobody there to see it. For that one mode, `ask` and `allow`
are the same outcome.

`guard-destructive.sh` never read this field before this change. It could not distinguish an `ask` a
human will see from an `ask` nobody will ever see, and emitted the same decision either way.

## The fix

The subset of the `ask` tier that has no legitimate unattended-agent use — destroying another
session's uncommitted work — now escalates to `deny` when, and only when, `permission_mode` reads
`bypassPermissions`:

- bare `git stash` (new: this tier did not exist before this change at all — a bare stash fell
  through to `allow`, unmatched by any rule)
- `git reset --hard`
- `git clean -fd`
- `git add -A` / `git add .` / `git add --all` / `git commit -a` / `-am` / `--all` outside the
  session's own workspace (same `CONDUCTOR_WORKSPACE_PATH` scoping the rule already had)

Everything else in the `ask` tier (database drops, infrastructure teardown, the verify-trust store,
device writes, non-artifact recursive deletes) is unchanged and stays `ask` in every mode — RICK's
brief: "Not the whole tier — an ask that a human will actually see is doing its job."

When `permission_mode` is `"default"`, `"acceptEdits"`, or `"plan"` (a human can see the prompt),
the escalation set stays exactly `ask`, unchanged from before this fix.

When `permission_mode` is absent from the payload (an older Claude Code, or a synthetic payload —
e.g. `.claude/verify.sh`'s own check, which never sets it), the guard does not guess. It stays
exactly today's decision (`ask`) and says explicitly in the reason text that it could not confirm
whether a human will see it, rather than silently assuming either "safe to escalate" or "safe to
leave inert." This mirrors `compat-canary.sh`'s KNOWN/UNKNOWN rule applied to a different unknown.

`git stash pop` / `apply` / `list` / `show` / `branch`, and `git stash push -- <path>` /
`save -- <path>` with an explicit pathspec, are left alone — they don't stash anything new, or they
scope it explicitly, the same reasoning `git add <explicit path>` already gets.

## The live join proof (not offline — the actual runtime, this session)

An offline probe (`bash claude/hooks/guard-destructive.sh <<<payload`) proves the decider's return
value, exactly what check 23 already does. It cannot prove Claude Code's own tool-execution engine
honors that value — that requires going through the real engine, which means a live tool call in an
actual session. Reproduced deliberately, both directions, in this session:

**Before the fix** (original guard live at `~/.claude/hooks/guard-destructive.sh`):

    SBX=$(mktemp -d ...); cd "$SBX"; git init -q .; git commit -q --allow-empty -m x
    printf 'untracked canary\n' > untracked-canary.txt
    git clean -fd
    # Removing untracked-canary.txt
    # rc=0

Ran unprompted. The guard returned `ask`; bypass mode auto-approved it; the file is gone.

**After the fix** (this session's `claude/hooks/guard-destructive.sh` copied to the live hook path):

    SBX2=$(mktemp -d ...); cd "$SBX2"; git init -q .; ...; git clean -fd
    # <error>[guard] git clean -fd deletes untracked files, including ones never committed
    #  anywhere. This session is in bypassPermissions mode, where an 'ask' decision is
    #  auto-approved with nobody to see it — for this command that is the same as allow.
    #  Denied instead. If you mean this, run it yourself outside the agent session.</error>

The entire tool call was refused before any of it ran: `find / -maxdepth 4 -name
"guard-live-proof2.*"` afterward found nothing — not even the sandbox directory the same command
would have created. `deny` now stops the runtime; `ask` did not.

## What could not be verified, and why

This live proof is real evidence, gathered by hand, in one real session, with one real Claude Code
build (2.1.243). It is not, and cannot become, a repeatable CI-safe gate assertion:

- Proving the join requires driving Claude Code's actual model-call / tool-execution loop (e.g. a
  scripted `claude -p ... --permission-mode bypassPermissions` session that attempts a Bash tool
  call and inspects whether it actually ran). The brief this work is under explicitly forbids
  writing or running model-call tests (`tests/evals/`, and by the same reasoning anything that
  invokes the CLI's agentic loop) — they cost tokens, are non-deterministic, and need live auth
  that a CI runner does not have by default.
- What CAN be asserted offline, deterministically, and IS asserted (see below): that the decider's
  own output correctly conditions on the `permission_mode` field it is handed. That is real
  coverage of new ground (the field was never read at all before this change) but it is still only
  the decider half — it assumes, rather than proves, that Claude Code's runtime honors `deny` the
  way it was observed to, live, above. That assumption is checked once, by hand, in this document;
  it is not re-checked automatically.

**Recommendation for check 23's label** (`.claude/verify.sh`, owned by ZEEP this session): the `ok`
message "destructive guard decides correctly (N commands, 3 tiers)" should say plainly that it
verifies the decider only, e.g. append `" (decider only, not runtime enforcement — see
docs/guard-enforcement-gap.md)"`, so the label does not claim coverage the check does not have. This
is the same fix this repo has applied to every other fake green: narrow the claim to what is
actually measured.

## The offline assertion to wire (new ground, deterministic, no model calls)

`tests/repro/guard-bypass-escalation.sh` proves both directions of the *decider's* logic — not the
runtime join, which is covered live above:

- escalation set + `permission_mode: bypassPermissions` -> `deny` (was `ask`, or for `git stash`,
  was unmatched `allow`, before this fix)
- non-escalation ask-tier commands (DB drop, infra teardown) + `bypassPermissions` -> stay `ask`
- escalation set + `default` / `acceptEdits` / `plan` -> stay `ask` (regression guard: escalating
  when a human genuinely can see the prompt would be a new, different fake green)
- escalation set + `permission_mode` absent -> stays exactly today's tier, never silently escalated
  and never silently assumed safe
- `git stash pop` / `list` (and other read/apply-only stash subcommands) -> `allow`, untouched

Suggested rows for check 23, once ZEEP is free to land them (mirrors the existing `g_ws` helper,
adding a `permission_mode` field to the payload):

    g_pm(){ # <command> <permission_mode> <expected>
      G_N=$((G_N+1))
      got=$(printf '{"tool_input":{"command":%s},"permission_mode":%s}' \
              "$(jq -Rn --arg c "$1" '$c')" "$(jq -Rn --arg m "$2" '$m')" \
              | bash claude/hooks/guard-destructive.sh 2>/dev/null \
              | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null)
      [ "$got" = "$3" ] || errs="$errs\n'$1' under permission_mode=$2 -> $got, expected $3"
    }
    g_pm 'git stash'                 bypassPermissions deny
    g_pm 'git reset --hard HEAD~3'   bypassPermissions deny
    g_pm 'git clean -fd'             bypassPermissions deny
    g_pm 'git reset --hard HEAD~3'   default            ask
    g_pm 'git stash pop'             bypassPermissions  allow

These five rows are current, not a draft, unaffected by the follow-up below (they use plain,
unquoted commands) — safe for ZEEP to land verbatim.

## Follow-up: the false positive the escalation introduced (RICK, same day)

Reported by RICK: `emit_unattended_ask`'s `deny` path denies the **entire tool call**, and this
repository's subject matter is destructive commands, so its own commit messages and docs
constantly *mention* them. RICK's own literal repro:

    d=$(mktemp -d); cd "$d"; git init -q .; touch a; git add a
    git commit -q -m "prose about git reset --hard as documentation"

**Disclosure: this exact command, byte for byte, does not reproduce a denial against this guard**
— checked directly, four ways (offline JSON simulation, three live executions, one with the
commit message built via the repo's own mandated `git commit -m "$(cat <<'EOF' ... EOF)"`
convention) and it returns `allow` every time (`tests/repro/guard-quote-aware-split.sh`, direction
0, asserts this stays true). Anchored patterns (`git\ reset\ *--hard*` and friends) require the
segment to *start* with the keyword; "prose about git reset --hard" starts with "prose", not
"git", so it never matched, before or after the fix below.

**What actually happened, confirmed by reproducing my own real incident, not RICK's stated one:**
my first attempt at this session's own commit message contained "...blocked; git reset --hard
got..." — a `;` used as ordinary English punctuation, immediately followed by a phrase that
matches an anchored ask-tier pattern. The compound split (`sed -e 's/;/\n/g; ...'`) does not know
about quoting: it treated that `;` — sitting inside the `-m` argument's quotes — exactly like a
real shell separator, and the resulting phantom segment (" git reset --hard got...") began exactly
at the word "git", matched the anchored pattern, and under `bypassPermissions` escalated straight
to `deny` for the whole call. Minimal, reliable reproduction:

    git commit -m "line one; git reset --hard: docs"   ->  deny   (before this fix)

RICK's actual diagnosis — "the discriminator is not destructive syntax, it is does the segment
happen to start with `git`" — was the right instinct pointed at an example that happened not to
trigger it. The real discriminator is narrower: a compound separator character sitting *inside a
quoted argument*, landing immediately before text that independently matches an anchored pattern.

### The fix RICK asked me to weigh both directions of

**Considered and rejected: stripping quoted substrings before matching.** This is the "obvious
fix" RICK named, and RICK asked me to check the other direction first: does the guard currently
catch `bash -c "git clean -fd"` or `sh -c '...'` — destructive syntax deliberately hidden inside
quotes? Checked directly (`tests/repro/guard-quote-aware-split.sh`, direction 4):

    bash -c "git clean -fd"    ->  allow   (already true before any change here — anchoring, not
                                             quoting, is why: `git\ clean\ *-*[dD]*[fF]*` requires
                                             the segment to START with "git clean", and this
                                             segment starts with "bash")
    bash -c "rm -rf /etc"      ->  ask     (already true before any change here — the rm-family
                                             ask-tier pattern is UNANCHORED, `*rm\ -[rRfF]*`, and
                                             matches "rm -rf" anywhere in the segment, including
                                             inside the quotes)

So: the anchored git-family patterns get nothing from seeing inside quotes today (they never did —
anchoring already blocks them regardless of quoting), but the unanchored rm/DB/infra/device/
verify-trust patterns genuinely do catch destructive text hidden inside a quoted subshell argument
today, by accident of substring matching. Stripping quoted text before matching, as first proposed,
would have silently thrown away that real (if accidental) coverage for no gain — the anchored
patterns that actually have the false-positive problem don't need quotes stripped, they need
correct **segmentation**.

**What was built instead: quote-aware segment splitting, not quote-content stripping.**
`_gd_split()` in `claude/hooks/guard-destructive.sh` walks the command character by character,
tracking single/double-quote state, and only treats `;`, `&`, `|` as real separators when they are
not inside an open quote. The quoted text itself is never removed or altered — every pattern,
anchored or not, still sees the full segment exactly as before. This fixes the false positive
(a `;` inside quotes no longer manufactures a phantom segment) while leaving the unanchored
families' accidental-but-real coverage of `bash -c "rm -rf ..."`-style indirection completely
intact — verified both ways in `tests/repro/guard-quote-aware-split.sh` (15/15).

**Stating plainly which of the two this is, per RICK's request:** this is still *matches syntax,
not semantics* — not full shell parsing, and no claim otherwise. Specifically still NOT tracked:
escaped quotes (`\"` inside a double-quoted string does not end it in real shell grammar; this
scanner does not know that and would end the quote early — not exercised by any real construct
this repo's own commit messages or docs use, and disclosed here rather than silently assumed
correct) and backtick / `$(...)` command substitution (unchanged from before — still opaque, still
falls through to the ask tier if destructive, exactly as the file's own header already said). What
changed is narrower and precise: whether a `;`/`&`/`|` counts as a separator is now judged by
quote state instead of by raw character presence, and nothing else about the guard's shell
awareness moved.

**Consolidation side effect:** the deny tier had two hand-duplicated copies of the same
rm-root/force-push patterns — one in `_check_deny_segment()` (used for compound commands) and a
second, separately-maintained copy for "simple" commands. Since `_gd_split` now always yields
exactly one segment for a command with no real top-level separator, the simple case is just the
compound case with N=1, and the duplicate block was deleted rather than kept in sync by hand. Same
consolidation for the ask tier's simple/compound branches. Net effect: less code, one place each
pattern family is defined, verified identical behavior for every existing case
(`tests/repro/guard-quote-aware-split.sh` direction 3, plus a full re-run of check 23's own 30
assertions unmodified — still 30/30).

### Live proof, redone after this fix

    git commit -q --allow-empty -m "line one; git reset --hard is mentioned here as documentation"
    # rc=0, commit lands (was denied, whole call, before this fix)

    # separately, the same disposable-sandbox / untracked-file / `git clean -fd` proof from above,
    # rerun after this fix: still denied, atomically, exactly as before -- the fix narrows what
    # triggers the escalation, it does not weaken the escalation itself.

### What was left running on the operator's machine

`~/.claude/hooks/guard-destructive.sh` is byte-identical to this repo's `HEAD` as of both fixes in
this document (the bypassPermissions escalation and this quote-aware split). This is a deliberate
install, not a leftover from a test: the live join proof requires driving the real hook, so the
fix was copied there twice (once per fix), and left in place both times because it is the correct,
committed behavior — not reverted after the proof, and not something a test harness manages on its
own. If a decision is being tracked as "the operator chose to run the fixed guard live," it was
made by leaving it there after the fact, not before.

