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

