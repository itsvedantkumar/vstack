#!/usr/bin/env bash
# tests/mandate-cases.sh -- the ONE fixture set for claude/hooks/skill-mandate.sh, shared by
# .claude/verify.sh check 27 (offline, repo-relative hook, every push) and
# tests/container-matrix.sh (installed hook, inside debian/alpine/ubuntu, release.yml only).
#
# Why this file exists: check 27 and container-matrix.sh each grew their own fixtures and drifted
# apart. v1.57.0 changed skill-mandate.sh, check 27's copy was updated, container-matrix.sh's was
# not, and the first signal was a failed release. Neither set was a superset of the other: check 27
# never covered prove-it-works or conversational-silence; container-matrix.sh never covered unslop
# or typescript-best-practices. This file is their union -- the set of case ids below is exercised
# by BOTH runners, so a rule change that only one fixture set catches cannot happen again.
#
# Provenance: a-q are check 27's original 17 cases, renumbered nowhere (same letters). 9b/10/11/12
# are the container-matrix.sh cases (its 8, 9, 9c) with three collapsed into existing check-27
# equivalents: container "8" ~= "i" (three dirs, zero dispatch), "9"
# ~= "o" (three dirs + swarm + a 2-agent batch + attribution, everything silent at once),
# "9c" ~= "q" (a dispatch with the swarm skill never called). Container's "9b" (breadth-eligible,
# swarm called, but only ONE serial dispatch -- the exact shape that shipped broken in v1.57.0),
# "10" (purely conversational, no tool_use at all), "11" (edit + completion claim, no verification)
# and "12" (same, but with a Bash call in the turn) had no check-27 equivalent and are added as-is.
#
# THIS FILE IS SOURCED, NEVER EXECUTED. It defines data and one pure decision function; it knows
# nothing about how either runner invokes the hook, writes counter files, or reports a result.
#
# --- the five functions every case answers ------------------------------------------------------
#   mandate_case_lines <id>          fixture transcript, one JSONL record per line, to stdout
#   mandate_case_expect <id>         "SILENT", "BLOCK:<substring>" or "WARN:<substring>" -- the substring must appear
#                                     literally (grep -F) somewhere in the hook's raw stdout
#   mandate_case_flags <id>          space-separated flags this case needs (see below), or nothing
#   mandate_case_judge <id> <out>    the ONLY place SILENT vs BLOCK:<substring> is decided; prints
#                                     one human-readable line, returns 0 on match / 1 on mismatch
#   mandate_case_desc <id>           short human label for the ok/res line
#
# --- flag vocabulary (exactly three; a runner that does not implement one must declare-and-skip
#     every case that needs it, never silently run it unflagged) ---------------------------------
#   STOP_ACTIVE   the hook's JSON input must carry "stop_hook_active":true for this one invocation
#                 instead of the default false. Proves the hook cannot be tricked into blocking a
#                 second time inside its own block (skill-mandate.sh line ~36).
#   NO_MANDATE    the hook must be invoked with VSTACK_NO_MANDATE=1 in its environment. Proves the
#                 escape hatch disables the gate before it even reads stdin.
#   PRIME2        before the judged invocation, invoke the hook TWICE MORE on the exact same
#                 transcript, discarding both outputs, and — this is the part that matters — all
#                 three invocations (the two primes and the judged call) MUST share the identical
#                 session id. The per-mandate strike counters skill-mandate.sh keeps are keyed on
#                 session id; two same-session strikes latch that one mandate open (silent) for
#                 the rest of the session, which is the exact behavior this case proves.
#
# --- session-id discipline (both runners already do this; stated so a new one does not skip it) -
#     Every case here must run under its own session id, distinct from every other case's, so one
#     case's strike counters cannot bleed into another's. A case with PRIME2 is the one exception
#     to "one invocation, one session id": its three calls share ONE session id (see above).
#
# --- constraints on this file itself --------------------------------------------------------------
#   bash 3.2 (macOS), Linux, Alpine/busybox. No mapfile, no associative arrays, no sort -V.
#   No jq dependency for the functions below -- fixtures are literal JSONL text, not built at
#   call time, so this file sources cleanly even on a host with no jq (the runners need jq to
#   invoke the hook at all, but this file does not).

# shellcheck disable=SC2034  # read by callers that source this file (verify.sh check 27, tests/container-matrix.sh), not used within it
MANDATE_CASE_IDS="a b c d e f g h i j k l m n o p q 9b 9c 9d 9e 10 11 12 13 14 15 16 17 18"

# --- fixture records (shared building blocks, same literal shapes check 27 already proved) -------
_MC_W='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"/x/README.md"}}]}}'
_MC_T='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/x/App.tsx"}}]}}'
_MC_U='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"unslop"}}]}}'
_MC_P='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"/x/main.py"}}]}}'
_MC_TA='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Task","input":{"tool":"Skill"}},{"type":"text","text":"running"}]}}'
_MC_TB='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Task","input":{"tool":"Skill"}},{"type":"text","text":"qa (BETH J-42)"}]}}'
_MC_SW='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"swarm"}}]}}'
# Security mandate: a path whose job is to decide access, the skill that answers it, and the
# engine invoked directly. The last one exists because striking an agent that ran the audit but
# skipped the wrapper would teach it to call the skill and then do nothing.
_MC_SEC='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/x/src/auth.py"}}]}}'
_MC_WB='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"whitebox-pentest"}}]}}'
_MC_WBSH='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":".claude/whitebox-audit.sh --deep"}}]}}'
_MC_TWO='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Task","input":{"tool":"Skill"}},{"type":"tool_use","name":"Task","input":{"tool":"Skill"}},{"type":"text","text":"ZEEP and GLOOTIE"}]}}'
_MC_ON1='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Task","input":{"tool":"Skill"}},{"type":"text","text":"ZEEP"}]}}'
_MC_ON2='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Task","input":{"tool":"Skill"}},{"type":"text","text":"GLOOTIE"}]}}'
_MC_F1='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"fix/test1.sh","content":""}},{"type":"tool_use","name":"Write","input":{"file_path":"fix/test2.sh","content":""}},{"type":"tool_use","name":"Write","input":{"file_path":"fix/test3.sh","content":""}},{"type":"tool_use","name":"Write","input":{"file_path":"fix/test4.sh","content":""}},{"type":"tool_use","name":"Write","input":{"file_path":"fix/test5.sh","content":""}}]}}'
_MC_F2='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"a.sh","content":""}},{"type":"tool_use","name":"Write","input":{"file_path":"lib/b.json","content":""}},{"type":"tool_use","name":"Write","input":{"file_path":"src/c.py","content":""}}]}}'
_MC_F3='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":".editorconfig","content":""}},{"type":"tool_use","name":"Write","input":{"file_path":"home/.gitignore","content":""}},{"type":"tool_use","name":"Write","input":{"file_path":"proj/.npmrc","content":""}}]}}'
# 9b: 3 dirs / 3 extensions + swarm called + exactly ONE serial Task dispatch, with a call sign
# in the closing text. This blocked until 1.68.0, when the delegation breadth mandate was retired
# on measured cost (tests/evals/showcase/RESULTS.md, the routing-cost table); it is kept as the
# pin that a wide write-set with every dispatch rule satisfied now finishes in silence. Every
# other delegation mandate is deliberately satisfied here, so a block can only be breadth coming
# back. i and p are the same pin at two other shapes (zero dispatches; two serial ones).
_MC_9B_A='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"brs/a/x.sh","content":""}}]}}'
_MC_9B_B='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"brs/b/y.json","content":""}}]}}'
_MC_9B_C='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"brs/c/z.yaml","content":""}}]}}'
_MC_9B_TASK='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Task","input":{"tool":"Skill"}}]}}'
_MC_9B_TXT='{"type":"assistant","message":{"content":[{"type":"text","text":"RICK: dispatched MEESEEKS to verify, then moved on."}]}}'
# 9c/9d/9e: the serial-tail mandate. Three-plus Task/Agent dispatches with no parallel batch
# after the last one is a serial loop, whatever fanout_batches says about earlier history.
# 9c: three singleton dispatches, swarm called, RICK named, zero writes -- no other mandate
# can fire, tail=3 -> block. 9d: two singletons -> tail=2, below threshold, silent. 9e: a
# real 2-in-one-message batch FIRST, then three singletons -- fanout_batches=1 so the breadth
# rule can never complain again, but the tail since that batch is 3 -> block. 9e is the
# whole-transcript amnesty measured in real sessions (3ce9f899: 3 early batches, then 25
# serial dispatches, never blocked) that this mandate exists to close.
# 10: purely conversational, zero tool_use anywhere in the transcript.
_MC_10='{"type":"assistant","message":{"content":[{"type":"text","text":"Explaining how the retry loop computes exponential backoff."}]}}'
# 11/12: prove-it-works, unverified vs verified.
_MC_11_W='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"piw/fix.sh","content":""}}]}}'
_MC_DONE='{"type":"assistant","message":{"content":[{"type":"text","text":"The fix is done."}]}}'
_MC_12_W='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"piw2/fix.sh","content":""}}]}}'
_MC_12_BASH='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"bash piw2/fix.sh --selftest"}}]}}'
# 13/14/15: the register mandate. 13 is the positive direction: a turn whose text opens with a
# banned CLAUDE.md REGISTER phrase ("Let me ...") at line start; since 1.72.0 it must WARN (a
# systemMessage, no block -- a block cannot unsend the text and only bought Haiku an extra
# "Acknowledged" turn, see skill-mandate.sh). 14 and 15 are the two anchors
# that keep the pattern honest: 14 starts a line with "Right" but follows it with "-" (not in
# the [,! .] boundary class) -- "Right-sizing" is vocabulary, not an acknowledgement token; 15
# carries "Great," mid-line only, which the ^ anchor must ignore. Neither may block.
_MC_13='{"type":"assistant","message":{"content":[{"type":"text","text":"Let me check the logs first."}]}}'
_MC_14='{"type":"assistant","message":{"content":[{"type":"text","text":"Right-sizing the buffer comes later; the cap stays at 512."}]}}'
_MC_15='{"type":"assistant","message":{"content":[{"type":"text","text":"I ran it twice. Great, both runs agree."}]}}'

mandate_case_lines() {
  case "$1" in
    a) printf '%s\n' "$_MC_W" ;;
    b) printf '%s\n' "$_MC_T" ;;
    c) printf '%s\n' "$_MC_W" "$_MC_U" ;;
    d) printf '%s\n' "$_MC_P" ;;
    e) printf '%s\n' "$_MC_W" ;;
    f) printf '%s\n' "$_MC_W" ;;
    g) printf '%s\n' "$_MC_W" ;;
    h) printf '%s\n' "$_MC_F1" ;;
    i) printf '%s\n' "$_MC_F2" ;;
    j) printf '%s\n' "$_MC_F3" ;;
    k) printf '%s\n' "$_MC_SW" "$_MC_TA" ;;
    l) printf '%s\n' "$_MC_SW" "$_MC_TB" ;;
    m) printf '%s\n' "$_MC_P" ;;
    n) printf '%s\n' "$_MC_TA" ;;
    o) printf '%s\n' "$_MC_F2" "$_MC_SW" "$_MC_TWO" ;;
    p) printf '%s\n' "$_MC_F2" "$_MC_SW" "$_MC_ON1" "$_MC_ON2" ;;
    q) printf '%s\n' "$_MC_TB" ;;
    9b) printf '%s\n' "$_MC_SW" "$_MC_9B_A" "$_MC_9B_B" "$_MC_9B_C" "$_MC_9B_TASK" "$_MC_9B_TXT" ;;
    9c) printf '%s\n' "$_MC_SW" "$_MC_9B_TASK" "$_MC_9B_TASK" "$_MC_9B_TASK" "$_MC_9B_TXT" ;;
    9d) printf '%s\n' "$_MC_SW" "$_MC_ON1" "$_MC_ON2" ;;
    9e) printf '%s\n' "$_MC_SW" "$_MC_TWO" "$_MC_9B_TASK" "$_MC_9B_TASK" "$_MC_9B_TASK" ;;
    10) printf '%s\n' "$_MC_10" ;;
    11) printf '%s\n' "$_MC_11_W" "$_MC_DONE" ;;
    12) printf '%s\n' "$_MC_12_W" "$_MC_12_BASH" "$_MC_DONE" ;;
    13) printf '%s\n' "$_MC_13" ;;
    14) printf '%s\n' "$_MC_14" ;;
    15) printf '%s\n' "$_MC_15" ;;
    16) printf '%s\n' "$_MC_SEC" ;;
    17) printf '%s\n' "$_MC_SEC" "$_MC_WB" ;;
    18) printf '%s\n' "$_MC_SEC" "$_MC_WBSH" ;;
    *) return 1 ;;
  esac
}

mandate_case_expect() {
  case "$1" in
    a) printf '%s\n' 'BLOCK:wrote prose' ;;
    b) printf '%s\n' 'BLOCK:wrote TypeScript' ;;
    c) printf '%s\n' 'SILENT' ;;
    d) printf '%s\n' 'SILENT' ;;
    e) printf '%s\n' 'SILENT' ;;
    f) printf '%s\n' 'SILENT' ;;
    g) printf '%s\n' 'SILENT' ;;
    h) printf '%s\n' 'SILENT' ;;
    i) printf '%s\n' 'SILENT' ;;
    j) printf '%s\n' 'SILENT' ;;
    k) printf '%s\n' 'BLOCK:agent naming' ;;
    l) printf '%s\n' 'SILENT' ;;
    m) printf '%s\n' 'SILENT' ;;
    n) printf '%s\n' 'SILENT' ;;
    o) printf '%s\n' 'SILENT' ;;
    p) printf '%s\n' 'SILENT' ;;
    q) printf '%s\n' 'BLOCK:the swarm skill' ;;
    9b) printf '%s\n' 'SILENT' ;;
    9c) printf '%s\n' 'BLOCK:serial dispatch tail' ;;
    9d) printf '%s\n' 'SILENT' ;;
    9e) printf '%s\n' 'BLOCK:serial dispatch tail' ;;
    10) printf '%s\n' 'SILENT' ;;
    11) printf '%s\n' 'BLOCK:prove-it-works' ;;
    12) printf '%s\n' 'SILENT' ;;
    13) printf '%s\n' 'WARN:register strike 1/2: banned opener' ;;
    14) printf '%s\n' 'SILENT' ;;
    15) printf '%s\n' 'SILENT' ;;
    16) printf '%s\n' 'BLOCK:whitebox-pentest' ;;
    17) printf '%s\n' 'SILENT' ;;
    18) printf '%s\n' 'SILENT' ;;
    *) return 1 ;;
  esac
}

mandate_case_flags() {
  case "$1" in
    e) printf '%s\n' STOP_ACTIVE ;;
    f) printf '%s\n' NO_MANDATE ;;
    n) printf '%s\n' NO_MANDATE ;;
    g) printf '%s\n' PRIME2 ;;
  esac
}

mandate_case_desc() {
  case "$1" in
    a) printf '%s\n' 'wrote prose without unslop and it did not block' ;;
    b) printf '%s\n' 'wrote TypeScript without the ts skill and it did not block' ;;
    c) printf '%s\n' 'blocked even though unslop had run' ;;
    d) printf '%s\n' 'blocked on a file no mandate covers' ;;
    e) printf '%s\n' 'blocked while stop_hook_active was already true' ;;
    f) printf '%s\n' 'ignored VSTACK_NO_MANDATE=1' ;;
    g) printf '%s\n' 'did not latch open after 2 unslop strikes in one session' ;;
    h) printf '%s\n' 'five fixtures in one dir blocked (nothing may block on the write-set spread since 1.68.0)' ;;
    i) printf '%s\n' 'three dirs with two-plus extensions blocked -- the retired multi-dir mandate is back' ;;
    j) printf '%s\n' 'three dotfiles across three dirs blocked (no extensions, and no breadth rule left anyway)' ;;
    k) printf '%s\n' 'Task call with no call sign did not block on the naming rule' ;;
    l) printf '%s\n' 'Task call with call sign (BETH) blocked anyway' ;;
    m) printf '%s\n' 'zero Task calls falsely blocked on naming rule' ;;
    n) printf '%s\n' 'VSTACK_NO_MANDATE=1 did not disable agent naming block' ;;
    o) printf '%s\n' 'a swarm-routed, named, 2-in-one-message batch over a three-dir spread blocked anyway' ;;
    p) printf '%s\n' 'two dispatches in SEPARATE messages blocked -- below the serial-tail threshold of 3, and breadth is retired' ;;
    q) printf '%s\n' 'dispatched without calling the swarm skill and it did not block' ;;
    9b) printf '%s\n' 'a three-dir spread + swarm called + ONE named dispatch blocked -- the retired breadth mandate is back' ;;
    9c) printf '%s\n' 'three serial dispatches with no batch did not trip the serial-tail mandate' ;;
    9d) printf '%s\n' 'two serial dispatches (below the tail-3 threshold) tripped the serial-tail mandate' ;;
    9e) printf '%s\n' 'an early parallel batch amnestied three later serial dispatches' ;;
    10) printf '%s\n' 'a purely conversational turn (no tool_use) blocked' ;;
    11) printf '%s\n' 'edit + completion claim with no verification did not block prove-it-works' ;;
    12) printf '%s\n' 'edit + completion claim WITH a Bash call in the turn blocked anyway' ;;
    13) printf '%s\n' 'a turn opening with "Let me" did not trip the register mandate' ;;
    14) printf '%s\n' 'a line starting "Right-" (no boundary char after the opener) tripped register anyway' ;;
    15) printf '%s\n' 'a mid-line "Great," tripped register anyway (the line anchor was lost)' ;;
    16) printf '%s\n' 'edited a file that decides access, never audited it' ;;
    17) printf '%s\n' 'edited a file that decides access, ran the whitebox-pentest skill' ;;
    18) printf '%s\n' 'edited a file that decides access, ran the audit engine directly' ;;
    *) return 1 ;;
  esac
}

# mandate_case_judge <id> <hook_stdout> -- the ONE place SILENT vs BLOCK vs WARN:<substring> is decided.
# Prints one human-readable line to stdout; returns 0 on match, 1 on mismatch. Substring matching
# is fixed-string (grep -F): several expected substrings carry literal parentheses
# ("2 subagent call(s)") that would otherwise be read as regex.
mandate_case_judge() {
  _mcj_id="$1"
  _mcj_out="$2"
  _mcj_exp=$(mandate_case_expect "$_mcj_id") || { printf '%s: unknown case id\n' "$_mcj_id"; return 1; }
  case "$_mcj_exp" in
    SILENT)
      if [ -z "$_mcj_out" ]; then
        printf '%s: silent as expected\n' "$_mcj_id"
        return 0
      fi
      printf '%s: expected silence, got: %s\n' "$_mcj_id" "$(printf '%s' "$_mcj_out" | tr '\n' ' ' | cut -c1-200)"
      return 1
      ;;
    BLOCK:*)
      _mcj_sub=${_mcj_exp#BLOCK:}
      if printf '%s' "$_mcj_out" | grep -qF '"decision":"block"' \
         && printf '%s' "$_mcj_out" | grep -qF -- "$_mcj_sub"; then
        printf '%s: blocked, naming "%s" as expected\n' "$_mcj_id" "$_mcj_sub"
        return 0
      fi
      printf '%s: expected block naming "%s", got: %s\n' "$_mcj_id" "$_mcj_sub" \
        "$(printf '%s' "$_mcj_out" | tr '\n' ' ' | cut -c1-200)"
      return 1
      ;;
    WARN:*)
      # A strike that must NOT block and must still be visible: no "decision":"block" anywhere,
      # a systemMessage carrying the substring. The register mandate is the one WARN today.
      _mcj_sub=${_mcj_exp#WARN:}
      if ! printf '%s' "$_mcj_out" | grep -qF '"decision":"block"' \
         && printf '%s' "$_mcj_out" | grep -qF '"systemMessage"' \
         && printf '%s' "$_mcj_out" | grep -qF -- "$_mcj_sub"; then
        printf '%s: warned without blocking, naming "%s" as expected\n' "$_mcj_id" "$_mcj_sub"
        return 0
      fi
      printf '%s: expected a non-blocking warning naming "%s", got: %s\n' "$_mcj_id" "$_mcj_sub" \
        "$(printf '%s' "$_mcj_out" | tr '\n' ' ' | cut -c1-200)"
      return 1
      ;;
    *)
      printf '%s: malformed expectation %s\n' "$_mcj_id" "$_mcj_exp"
      return 1
      ;;
  esac
}
