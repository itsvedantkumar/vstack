#!/usr/bin/env bash
# Stop: refuse to finish when the session did work that a skill is mandated for and never ran it.
#
# vstack already tells the model how to route: the SessionStart digest spells out "any prose you
# write -> unslop", and the skill descriptions carry their own triggers. Both are instructions,
# and an instruction is a probability. Measured over 12 prompts the routing lands, but "lands most
# of the time" is not the same claim as "always", and the second one is the one worth having.
#
# This closes the gap for the few rules where the situation is decidable from the transcript
# rather than from judgement. It reads what the session actually did -- which files were written,
# which skills were invoked -- and blocks Stop when a mandate went unmet. Nothing here guesses at
# intent: if the rule cannot be decided by looking at tool calls, it does not belong in this file.
#
# Escape hatch: VSTACK_NO_MANDATE=1 disables it entirely. A gate you cannot turn off gets deleted
# by the first person it inconveniences, which is worse than one that is on by default.
set -uo pipefail

[ "${VSTACK_NO_MANDATE:-0}" = "1" ] && exit 0

JQ=""
if [ -x /usr/bin/jq ]; then JQ=/usr/bin/jq
elif command -v jq >/dev/null 2>&1; then JQ=$(command -v jq); fi
# Without jq there is no way to read the transcript path or emit a block reason safely. Say
# nothing rather than guess: a mandate that misfires is worse than one that abstains.
[ -n "$JQ" ] || exit 0

input=$(cat 2>/dev/null || true)

# Claude Code sets this when Stop already fired once for this turn. Blocking again from inside a
# block is how a hook turns into an infinite loop.
[ "$(printf '%s' "$input" | "$JQ" -r '.stop_hook_active // false')" = "true" ] && exit 0

tr_=$(printf '%s' "$input" | "$JQ" -r '.transcript_path // empty')
[ -n "$tr_" ] && [ -f "$tr_" ] || exit 0

sid=$(printf '%s' "$input" | "$JQ" -r '.session_id // empty'); [ -n "$sid" ] || sid="pid$PPID"
cnt_file="${TMPDIR:-/tmp}/vstack-mandate-$sid"
lock_dir="$cnt_file.lock"
# Stop hooks from the same session can fire concurrently (parallel sub-agents finishing at once),
# and read-cat-then-write-echo on cnt_file is a classic unlocked read-modify-write: ten racing
# invocations all read the same starting count, each computes its own +1, and the last write
# wins -- the counter undercounts and the 2-strike cap never engages, so every invocation blocks
# instead of latching open after 2. Ported verbatim from verify-gate.sh's lock: `mkdir` is atomic
# on every POSIX filesystem (exactly one caller sees it succeed), which needs no GNU flock and no
# coreutils on stock macOS. A lock older than 30s is assumed abandoned by a killed sibling rather
# than honored forever, so a crash can't wedge the gate shut.
lock_acquired=0
i=0
while ! mkdir "$lock_dir" 2>/dev/null; do
  i=$((i + 1))
  if [ "$i" -ge 300 ]; then
    # stat -f (BSD/macOS) vs -c (GNU/Linux); `find -mmin` was tried first and dropped because
    # some `find` implementations (e.g. bfs) reject fractional minute arguments outright.
    lm=$(stat -f %m "$lock_dir" 2>/dev/null || stat -c %Y "$lock_dir" 2>/dev/null || echo 0)
    now=$(date +%s)
    if [ "$lm" -gt 0 ] && [ $((now - lm)) -ge 30 ]; then
      rm -rf "$lock_dir" 2>/dev/null
    fi
    i=0
  fi
  sleep 0.02 2>/dev/null || sleep 1
done
lock_acquired=1
trap '[ "$lock_acquired" = 1 ] && rmdir "$lock_dir" 2>/dev/null' EXIT

cnt=$(cat "$cnt_file" 2>/dev/null || echo 0)
# Same latch as the verify gate. A mandate the model cannot satisfy must not trap the session.
[ "$cnt" -ge 2 ] && exit 0

# Every file this session wrote or edited, and every skill it invoked. Both come from the
# transcript, so this measures what happened rather than what was asked for.
paths=$(
  "$JQ" -r 'select(.type=="assistant") | .message.content[]?
            | select(.type=="tool_use" and (.name=="Write" or .name=="Edit" or .name=="NotebookEdit"))
            | .input.file_path // empty' "$tr_" 2>/dev/null | sort -u
)
skills=$(
  "$JQ" -r 'select(.type=="assistant") | .message.content[]?
            | select(.type=="tool_use" and .name=="Skill") | .input.skill // empty' "$tr_" 2>/dev/null \
  | sed 's/.*://' | sort -u
)

# Write/Edit/NotebookEdit tool_use blocks are not the only way a session changes a file. In
# bypass-permissions mode the model is explicitly told to prefer Bash -- sed, heredocs, short
# scripts -- over the dedicated Edit/Write tools, and every one of those edits was invisible to
# every mandate above: a v1.35.0 release cut six files across five directories and three
# extensions entirely through `sed -i` and `python3 - <<PY` heredocs, and the breadth mandate
# never fired. This scans every Bash tool_use block's .input.command for a bounded set of write
# patterns and folds anything it recognizes into $paths below it, so the breadth mandate (and,
# as a side effect, the prose/TypeScript ones, which key off the same $paths) see Bash-mediated
# edits the same way they see Edit/Write ones.
#
# Recognized, in order: `sed -i` / `sed -i.bak` (the last whitespace-separated argument is taken
# as the target file); `>` / `>>` / `&>` output redirection and `tee [-a]` (this also covers
# `cat > path <<EOF`-style heredoc writers, since it is the redirect that is matched, not the
# heredoc body); `cp` / `mv` (the last non-flag argument is taken as the destination); and Python
# `open(PATH, 'w'...)` / `'a'...` / `'x'...` calls with a literal string path, anywhere in the
# command text -- which is what a `python3 - <<'PY' ... PY` heredoc writer looks like once jq has
# flattened it to one string.
#
# Residual blind spots, left uncaught on purpose rather than chased with more regex:
#   - a quoted path containing a space truncates at the first space (`> "a b.txt"` yields `a`)
#   - a `sed -i` / `cp` / `mv` / `tee` invocation naming more than one target file only yields
#     the last one (`sed -i '' -e s/a/b/ x.sh y.sh` sees only y.sh)
#   - commands invoked by full path (`/bin/cp`, `/usr/bin/sed -i`), via `sudo`, `xargs`, `eval`,
#     `find -exec`, or with a `VAR=val cmd` prefix are not recognized as the command at all
#   - a Python write via a variable, an f-string, `pathlib.Path(...).write_text(...)`, or any
#     open() call whose path is not a literal string is invisible
#   - `touch`, `mkdir`, `install`, `rsync`, `dd`, and redirection to a process substitution or an
#     fd number are not treated as writes
#   - a literal `>` inside a quoted string earlier on the same line (`echo "a > b" > out`) can be
#     misread as its own redirect target -- this is the price of not tokenizing the shell, and it
#     is a false *addition* to $paths, not a false mandate-met: it can only make the breadth
#     mandate name a Bash line it otherwise would not have, never suppress one that is real
#   - the same trap in the mirror: `[[ "$x" > "$y" ]]` and `[ "$a" > "$b" ]` are lexicographic
#     string comparisons, not redirects, and the redirect scan cannot tell the difference -- it
#     reads `$y`/`$b` off as a write target. This used to be dismissed here as inert noise on the
#     theory that a bare `$var` has neither `/` nor `.` to supply a second directory or extension
#     on its own. That theory was wrong, measured against a real 15MB transcript: combined with
#     heredoc-body leakage (below), unexpanded-`$` candidates were not inert, they were the
#     dominant term behind a reported 53 directories / 83 extensions for a session that had
#     written one real file. `emit()` now drops any candidate containing `$` outright rather
#     than trusting it to stay harmless -- cheap, and it removes this whole family in one place
#     regardless of which rule produced the candidate.
#   - a line inside an open heredoc body is skipped entirely (tracked by the in_hd/hd_delim state
#     machine in emit()'s caller), so `cat > new-check.sh <<'EOF'` counts only new-check.sh, not
#     every `>`/`cp`/`mv`/`open()`-shaped line the generated script's own body happens to contain.
#     Before this, a test-fixture generator that wrote fixture code containing its own example
#     `printf ... > path` was read as this session performing that write too -- the other half of
#     the 53/83 measurement above. Residual within this fix: two heredocs opened on the same
#     physical line, or a delimiter line that also carries trailing content after it, are not
#     modeled -- both are rare enough in practice that chasing them was not worth it here.
#   - a same-line `>` used as a comparison/arithmetic/format-string character *outside* a heredoc
#     body -- `awk '{if (a>b) ...}'`, a `printf` format token like `%.3f` that happens to follow a
#     stray `>` earlier on the line -- is still misread as a redirect target exactly as before.
#     Suppressing heredoc bodies removed most of this family's real-world volume (it is what most
#     of these lines were embedded in), and the survivors are short, extension-poor, non-slash
#     tokens (`9.9`, `1{print`, `>>>>>`) that read the same way the existing extension-less-token
#     analysis above already argues is bounded -- left as a known, disclosed miss rather than
#     chased with a real shell tokenizer, which this file has never tried to be.
# None of this is a shell parser. It is a best-effort net over write shapes that are actually
# common in this repo's own history, traded deliberately against reads: `grep`, `cat`, `ls`,
# `git add`, `find` without `-delete`, and command substitution never match any rule below, so
# ordinary read-heavy Bash work stays silent -- a guard that cries wolf on reads gets disabled.
bash_write_paths=""
AWK_BIN=""
if [ -x /usr/bin/awk ]; then AWK_BIN=/usr/bin/awk
elif command -v awk >/dev/null 2>&1; then AWK_BIN=$(command -v awk); fi
if [ -n "$AWK_BIN" ]; then
  bash_cmds=$(
    "$JQ" -r 'select(.type=="assistant") | .message.content[]?
              | select(.type=="tool_use" and .name=="Bash") | .input.command // empty' "$tr_" 2>/dev/null
  )
  if [ -n "$bash_cmds" ]; then
    # emit() is the one gate every extracted candidate passes through before it can become a
    # path: empty, and -- new -- anything still carrying an unexpanded shell variable. A path
    # like $g_empty/app/src/C.tsx never resolved to a real file; it is a fixture literal (this
    # repo writes exactly that shape in its own test-generator scripts) or a template a later
    # command substitutes into, and either way this hook has no value to substitute it with, so
    # counting it as a directory/extension is pure noise, not a conservative guess.
    #
    # Heredoc-body suppression is the second half. `cat > new-check.sh <<'CHK' ... CHK` writes
    # exactly one real file -- new-check.sh, captured by the `>` rule on the opening line, same
    # as always -- but every line *inside* that heredoc's body is script source being written
    # to disk, not a command running in this turn. Before this fix the same `>>?` / `cp`/`mv`
    # regexes ran over body lines too, so a generated test fixture that itself contained
    # `printf ... > "$g_empty/app/src/C.tsx"` or `mv .github/workflows/verify.yml /tmp/...`
    # inside its own body text was read as a second, third, fourth real write by *this*
    # session -- confirmed against a real 15MB transcript, where it was the dominant term
    # behind a reported 53 directories / 83 extensions that should have been ~1. The state
    # machine below tracks whether the current physical line is inside an open heredoc body
    # (in_hd) and skips all extraction there, resuming only once a line equal to the opening
    # delimiter (optionally indented, for `<<-`) is seen. It does not attempt to track nested
    # heredocs inside a body -- while in_hd, every line is skipped outright, including one that
    # looks like it opens another heredoc, which is correct: it is body text either way, and the
    # only delimiter that matters is the outer one already being waited for.
    #
    # A here-string (`cmd <<<"$x"`) does not falsely open heredoc-suppression: after consuming
    # `<<` plus an optional `-` plus optional spaces, the next character is still the third `<`,
    # which matches neither the stripped-quote branch nor a bareword delimiter, so the match
    # fails and in_hd is never set. A bitshift (`$((1 << 3))`) fails the same way -- the char
    # after `<<` is a digit, not `[A-Za-z_]`. Checked by hand against both shapes before shipping.
    #
    # Suppression only engages when the SAME physical line also matched one of the write rules
    # above (line_had_write) -- this is not incidental, it is the line separating an inert
    # heredoc from an executed one. `cat > file <<EOF` and `tee file <<EOF` both write the body
    # to a file verbatim; the body never runs, so any `>`/`cp`/`open()`-shaped text inside it
    # describes what the generated file contains, not what this Bash call did. `python3 - <<PY`
    # and `bash <<EOF`, by contrast, pipe the body to an interpreter that executes it immediately
    # in this same tool call -- neither line matches any write rule on its own (no redirect, no
    # cp/mv, nothing), so line_had_write is 0 and the body is scanned normally, meaning
    # `open("config/c.json", "w")` inside that body is still counted, correctly, as a real write.
    # Gating on line_had_write rather than on the presence of `<<` alone is what tells these two
    # shapes apart without knowing what command is on the line -- the first version of this fix
    # suppressed both alike and silently broke the one fixture (test-breadth-mandate.sh PROOF 5)
    # that depends on a `python3 - <<PY` heredoc's write being seen.
    bash_write_extract='
    function emit(f) {
      if (f == "" || f ~ /\$/) return
      print f
    }
    BEGIN { in_hd = 0; hd_delim = "" }
    {
      line = $0
      line_had_write = 0
      if (in_hd) {
        d = line
        gsub(/^[ \t]+/, "", d)
        if (d == hd_delim) { in_hd = 0; hd_delim = "" }
        next
      }
      if (match(line, /(^|[;&|]| )sed[ \t]+-i[^ \t]*[ \t]+/)) {
        line_had_write = 1
        rest = substr(line, RSTART + RLENGTH)
        n = split(rest, toks, /[ \t]+/)
        if (n >= 1) {
          f = toks[n]
          gsub(/^["'"'"']|["'"'"';]+$/, "", f)
          if (f !~ /^-/) emit(f)
        }
      }
      work = line
      while (match(work, />>?[ \t]*[^ \t;&|)]+/)) {
        line_had_write = 1
        tgt = substr(work, RSTART, RLENGTH)
        work = substr(work, RSTART + RLENGTH)
        sub(/^>>?[ \t]*/, "", tgt)
        gsub(/^["'"'"']|["'"'"']$/, "", tgt)
        if (tgt !~ /^&/ && tgt !~ /^\/dev\//) emit(tgt)
      }
      if (match(line, /(^|[;&|]| )tee[ \t]+(-a[ \t]+)?/)) {
        line_had_write = 1
        rest = substr(line, RSTART + RLENGTH)
        n = split(rest, toks, /[ \t]+/)
        for (i = 1; i <= n; i++) {
          t = toks[i]
          if (t ~ /^-/) continue
          gsub(/^["'"'"']|["'"'"']$/, "", t)
          emit(t)
          break
        }
      }
      if (match(line, /(^|[;&|]| )(cp|mv)[ \t]+/)) {
        line_had_write = 1
        rest = substr(line, RSTART + RLENGTH)
        n = split(rest, toks, /[ \t]+/)
        if (n >= 2) {
          f = toks[n]
          gsub(/^["'"'"']|["'"'"']$/, "", f)
          if (f !~ /^-/) emit(f)
        }
      }
      s = line
      while (match(s, /open\([ \t]*["'"'"'][^"'"'"']+["'"'"'][ \t]*,[ \t]*["'"'"'][waxWAX][^"'"'"']*["'"'"']/)) {
        line_had_write = 1
        m = substr(s, RSTART, RLENGTH)
        s = substr(s, RSTART + RLENGTH)
        if (match(m, /["'"'"'][^"'"'"']+["'"'"']/)) {
          emit(substr(m, RSTART + 1, RLENGTH - 2))
        }
      }
      if (line_had_write && match(line, /<<-?[ \t]*/)) {
        rest2 = substr(line, RSTART + RLENGTH)
        gsub(/^["'"'"']/, "", rest2)
        if (match(rest2, /^[A-Za-z_][A-Za-z0-9_]*/)) {
          hd_delim = substr(rest2, RSTART, RLENGTH)
          in_hd = 1
        }
      }
    }
    '
    bash_write_paths=$(printf '%s\n' "$bash_cmds" | "$AWK_BIN" "$bash_write_extract" 2>/dev/null | sort -u)
  fi
fi
# Fold into the same $paths every mandate below reads, so a Bash-mediated write counts exactly
# like a Write/Edit/NotebookEdit one everywhere downstream -- breadth, prose, and TypeScript alike.
[ -n "$bash_write_paths" ] && paths=$(printf '%s\n%s' "$paths" "$bash_write_paths" | sed '/^$/d' | sort -u)

fired(){ printf '%s\n' "$skills" | grep -qxF "$1"; }

unmet=""
# --- the mandates -----------------------------------------------------------------------------
# Each one needs a situation decidable from a tool call, and a skill that is the answer to it
# every single time. That second half is the strict part: a rule that is right nine times out of
# ten belongs in the digest as guidance, not here as a gate.

# Prose. Any Markdown that is not a machine-written log or a vendored file.
prose=$(printf '%s\n' "$paths" | grep -iE '\.(md|mdx)$' \
        | grep -viE '(CHANGELOG\.md|node_modules|\.audit/|/(dist|build|vendor)/)' | head -5)
if [ -n "$prose" ] && ! fired unslop; then
  unmet="$unmet
  unslop -- you wrote prose and it never ran: $(printf '%s' "$prose" | tr '\n' ' ')"
fi

# TypeScript. Reading one is judgement; writing one is not.
ts=$(printf '%s\n' "$paths" | grep -E '\.(ts|tsx)$' | grep -v node_modules | head -5)
if [ -n "$ts" ] && ! fired typescript-best-practices; then
  unmet="$unmet
  typescript-best-practices -- you wrote TypeScript and it never ran: $(printf '%s' "$ts" | tr '\n' ' ')"
fi

# Multi-directory, multi-type work without delegation. Detects work that spans parts by
# measuring breadth: distinct parent directories AND distinct file extensions. Both must be
# present to trigger, avoiding false blocks on mechanical repetition.
#
# Why not count files? Because 5 test fixtures (fixtures/case1.json through case5.json) is
# 1 directory and 1 extension — mechanical repetition, not multi-part work. But a real change
# (hook.sh, test/hook.test.sh, doc/HOOK.md, manifest.json) spans 4 directories and 3 types —
# that is work with parts, and is what subagents exist for.
#
# Edge cases that stay silent by design:
# - 6 .md files across 6 directories: 6 dirs, 1 extension → no block (single type is focused).
# - 10 .js files in src/: 1 directory, 1 extension → no block (single directory is cohesive).
# - 3 dotfiles (.editorconfig, .gitignore, .npmrc) across 3 dirs: 3 dirs, 0 extensions → no block.
#
# Dotfile handling: a file starting with . and containing no further . has no extension
# (it is pure name, not name + type). .eslintrc.json yields json; .eslintrc yields nothing.
#
# Dispatch-tool name: the subagent-launch tool is called "Task" in the classic Claude Code CLI
# and "Agent" in the Claude Agent SDK build this hook was actually dogfooded against -- a real
# 15MB transcript logged 70 "Agent" tool_use blocks and zero "Task" ones, which meant this
# counter read 0 and both the delegation mandate and the agent-naming mandate below misfired on
# every session running that build: the former claimed "zero subagents" over 70 of them, the
# latter (gated on task_count>=1) was structurally unable to ever fire. Counting both names is
# not future-proofed against a third rename; a build using neither counts 0 and this hook falls
# back to its existing bias (say nothing rather than guess) rather than accusing a session that
# genuinely delegated under a name this file does not yet know.
#
# "TaskCreate" is deliberately NOT included here. It exists in this same build and looked like a
# third dispatch-tool alias at a glance, but its recorded .input is {subject, description,
# activeForm} -- a todo/checklist item, the same shape as TodoWrite -- not {prompt,
# subagent_type} like Task/Agent. Counting it would credit a session for delegating work it only
# planned. Confirmed against 3 real transcripts on this machine before excluding it, not assumed.
task_count=$( "$JQ" -s '[.[] | select(.type=="assistant") | .message.content[]?
            | select(.type=="tool_use" and (.name=="Task" or .name=="Agent"))] | length' "$tr_" 2>/dev/null )

# Agent naming: if Task/Agent count >= 1, one of the roster must appear in assistant text.
# Extract all assistant message text.
if [ "$task_count" -ge 1 ]; then
  assistant_text=$( "$JQ" -r 'select(.type=="assistant") | .message.content[]?
            | select(.type=="text") | .text' "$tr_" 2>/dev/null | tr '\n' ' ' )
  # Roster: RICK MEESEEKS MORTY SUMMER ZEEP GLOOTIE JAGUAR BETH BIRDPERSON EVIL-MORTY NOOBNOOB PICKLE-RICK SCARY-TERRY POOPYBUTTHOLE UNITY
  if printf '%s' "$assistant_text" | grep -qiE '\b(RICK|MEESEEKS|MORTY|SUMMER|ZEEP|GLOOTIE|JAGUAR|BETH|BIRDPERSON|EVIL-MORTY|NOOBNOOB|PICKLE-RICK|SCARY-TERRY|POOPYBUTTHOLE|UNITY)\b'; then
    :  # at least one call sign found, mandate met
  else
    unmet="$unmet
  agent naming -- $task_count subagent call(s) dispatched but no attribution found (name one: RICK MEESEEKS MORTY SUMMER ZEEP GLOOTIE JAGUAR BETH BIRDPERSON EVIL-MORTY NOOBNOOB PICKLE-RICK SCARY-TERRY POOPYBUTTHOLE UNITY)"
  fi
fi

parent_dirs=$( printf '%s\n' "$paths" | sed -E '
  s#/[^/]*$##
  t end
  s#^.*$#.#
  :end
' | sort -u )
dir_count=$( [ -z "$parent_dirs" ] && echo 0 || printf '%s\n' "$parent_dirs" | grep -c . )
extensions=$( printf '%s\n' "$paths" | sed -E '
  s#^.*/##
  /^\.[^.]*$/d
  s/^.*\.([^.]*)$/\1/
  t success
  d
  :success
  /^$/d
' | sort -u )
ext_count=$( [ -z "$extensions" ] && echo 0 || printf '%s\n' "$extensions" | grep -c . )
if [ "$dir_count" -ge 3 ] && [ "$ext_count" -ge 2 ] && [ "$task_count" -eq 0 ]; then
  unmet="$unmet
  multi-directory work -- touched $dir_count directories with $ext_count file types, zero subagents (try /team, or dispatch one directly: code-reviewer, qa, worker, planner, test-writer)"
fi

# Prove it works: a completion claim closing this turn with zero evidence produced in it.
#
# Every mandate above asks "did a skill run against a file this session touched", which the
# matcher above can answer because both halves -- the file, the skill invocation -- are things
# that already happened. This one is different in kind. principle-prove-it-works's trigger is
# "before declaring any task or fix done": a condition on the assistant's own next speech act,
# not on anything in the user's prompt. Skill dispatch scores the user's text against skill
# descriptions, so no description can reach a condition that names the assistant's own
# forthcoming output -- measured at 0/10 on its fixture prompt, the worst score of any principle
# skill, and not for lack of vocabulary overlap (its description contains both of the prompt's
# literal tokens). The thing that needs catching is not in the text being matched.
#
# This hook already runs on Stop, which is exactly the moment the condition is about: the turn
# is over, and whatever the assistant said last is what it is about to leave standing. So instead
# of asking a skill matcher to catch a property of unwritten text, this reads the transcript for
# it directly, the same way the mandates above read it for file writes.
#
# "This turn" is bounded by the transcript itself, not guessed: a real human turn starts at a
# "type":"user" entry whose content is a plain string, or an array with a "text" block and no
# "tool_result" block (a tool result is also logged as type "user" -- that is Claude Code's
# transcript format, not a human reply, and must not reset the boundary). Everything after the
# LAST such entry is this turn. A transcript with no such entry at all (every fixture in this
# repo's own test suites, which build a transcript as one bare assistant block with no user
# line) falls back to treating the whole file as the turn, which is what the two-line file this
# hook actually sees in a real session with a fresh session_id effectively already reduces to.
#
# Within that turn: did the closing remark claim completion, and did the turn edit a file while
# producing zero evidence? Both conditions gate the trigger, not either alone.
#
#   claim   -- the LAST assistant "text" block in the turn (i.e. the words actually left standing
#              when the turn ends, not something said and then acted past) matches a bounded list
#              of completion phrasings below.
#   edit    -- at least one Write/Edit/NotebookEdit tool_use happened in the turn. Without this,
#              a completion claim is conversational, not a claim about code, and the false-block
#              cost of guessing otherwise is worse than the miss (see the false-positive note by
#              the pattern list below).
#   silent  -- ANY Bash, Read, or Task/Agent tool_use anywhere in the turn, in any order relative to
#              the edit. This is deliberately generous in both directions: a Bash call is treated
#              as evidence whether or not it happens to be a test invocation, and a Read is
#              treated as evidence even if it came before the edit (i.e. was investigation of the
#              bug, not verification of the fix) rather than after it. Both loosen the trigger
#              past what "prove it works" strictly asks for. That is the intended trade: this
#              fires on every Stop of every install, so the cost of a rule this hook cannot
#              satisfy is not "the model tries again", it is "the mandate gets disabled" -- and
#              a disabled mandate catches nothing, including the 9 times it would have been
#              right. Ordering the Bash/Read calls against the edit to tighten this further was
#              considered and dropped: the added jq is not free, and the case it would catch (an
#              investigative Read with no verification after) is already the rarer shape.
#
# Known false-positive shape, disclosed rather than chased: a turn that Writes a genuinely
# unverifiable artifact -- a poem, a note, a scratch file with no "works" to check -- and closes
# with a plain "Done." trips this exactly like an unverified code fix would, because file-write
# plus closing "done" plus no Bash/Read/Task/Agent in the same turn is indistinguishable from here.
# Scoping the edit check to code-like extensions was considered and rejected: it would have
# meant maintaining an extension allowlist this hook has no way to keep current, trading one
# false-positive shape for a false-negative one (a `.sh` fix that never runs is exactly the case
# this exists to catch). Left as a known, bounded miss in the direction this file always prefers.
# A two-pass version of this was tried first: stream the file once in jq's default per-line
# mode to find which line the turn starts on (matching how every other mandate above reads the
# transcript), then hand only the tail after that line to a second, small jq call, on the theory
# that avoiding a whole-file `-s` slurp would be the cheaper path. Measured on a 37MB real
# session transcript it was slower, not faster -- +520ms over the streaming mandates alone in
# this hook, roughly triple this one-pass version's cost. The reason: shelling out to `tail -n
# +N` to extract that tail is not free on this platform. BSD `tail`'s from-line mode measured at
# ~400ms on this repo's own darwin box to extract an 11-line, 33KB tail from that same 1782-line
# file -- line-oriented access apparently is not the fast path GNU tail's implementation makes
# it look like elsewhere. jq's own `-s` slurp-then-slice of the same whole file measured ~170ms,
# faster than just the `tail` step of the "optimization" meant to beat it. Reverted to the
# simpler single-pass slurp below in favor of the version that is both less code and faster.
turn_json=$(
  "$JQ" -sc '
    . as $all
    | ( $all
        | to_entries
        | map(select(.value.type == "user"
                     and (
                       (.value.message.content | type) == "string"
                       or ((.value.message.content // []) | map(.type) | index("tool_result")) == null
                     )))
        | last | .key
      ) as $ts
    | ($all[(($ts // -1) + 1):] | map(select(.type == "assistant"))) as $turn
    | {
        final_text: ( [ $turn[] | .message.content[]? | select(.type == "text") | .text ] | last // "" ),
        bash_n: ( [ $turn[] | .message.content[]? | select(.type == "tool_use" and .name == "Bash") ] | length ),
        read_n: ( [ $turn[] | .message.content[]? | select(.type == "tool_use" and .name == "Read") ] | length ),
        task_n: ( [ $turn[] | .message.content[]? | select(.type == "tool_use" and .name == "Task") ] | length ),
        edit_n: ( [ $turn[] | .message.content[]? | select(.type == "tool_use" and (.name == "Write" or .name == "Edit" or .name == "NotebookEdit")) ] | length )
      }
  ' "$tr_" 2>/dev/null
)
[ -n "$turn_json" ] || turn_json='{}'
piw_final_text=$(printf '%s' "$turn_json" | "$JQ" -r '.final_text // ""' 2>/dev/null)
piw_bash_n=$(printf '%s' "$turn_json" | "$JQ" -r '.bash_n // 0' 2>/dev/null)
piw_read_n=$(printf '%s' "$turn_json" | "$JQ" -r '.read_n // 0' 2>/dev/null)
piw_task_n=$(printf '%s' "$turn_json" | "$JQ" -r '.task_n // 0' 2>/dev/null)
piw_edit_n=$(printf '%s' "$turn_json" | "$JQ" -r '.edit_n // 0' 2>/dev/null)
: "${piw_bash_n:=0}"; : "${piw_read_n:=0}"; : "${piw_task_n:=0}"; : "${piw_edit_n:=0}"

# Bounded, not exhaustive -- the examples the mandate names ("done", "fixed", "works now", "all
# tests pass", "that should do it") plus their closest paraphrases. The unescaped `.` inside
# "that.s done" is a one-char wildcard standing in for whatever apostrophe got typed (straight
# ', curly ', or none at all -- "thats done"), so the pattern needs no quote-escaping at all.
piw_pattern='\bit works( now)?\b|\bthat works( now)?\b|\bworks now\b|\ball tests? (pass(ing|es)?|passed)\b|\bthat should do it\b|\bshould (work|be fixed) now\b|\bthe (fix|bug) is (fixed|done|complete|resolved)\b|\bthis (is|should be) (fixed|done|complete|resolved)\b|\b(task|issue|problem) is (fixed|done|complete|resolved)\b|\ball (set|good|done)\b|\bfixed\b|\bthat.s done\b|^done[.!]*$'

piw_claims=0
if [ -n "$piw_final_text" ] && printf '%s' "$piw_final_text" | grep -qiE "$piw_pattern"; then piw_claims=1; fi

if [ "$piw_edit_n" -ge 1 ] && [ "$piw_claims" -eq 1 ] \
   && [ "$piw_bash_n" -eq 0 ] && [ "$piw_read_n" -eq 0 ] && [ "$piw_task_n" -eq 0 ]; then
  unmet="$unmet
  prove-it-works -- this turn edited a file and closed claiming it is done, with no Bash/Read/Task/Agent call in the turn to back it up"
fi

[ -n "$unmet" ] || { rm -f "$cnt_file"; exit 0; }

echo $((cnt+1)) > "$cnt_file"
reason="A vstack skill mandate went unmet (attempt $((cnt+1))/2). These fire every time, not when they seem relevant:
$unmet

Run each named skill with the Skill tool against the files listed, apply what it says, then finish.
For prove-it-works: run the command that proves the change, read its actual output, then restate
the claim with that evidence -- or state the real status if the output disagrees with it.
Set VSTACK_NO_MANDATE=1 to disable this gate."
"$JQ" -cn --arg r "$reason" '{decision:"block",reason:$r}'
exit 0
