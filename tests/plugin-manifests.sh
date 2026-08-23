#!/usr/bin/env bash
# tests/plugin-manifests.sh -- proves the plugin this repo ships actually loads: the CLI accepts
# .claude-plugin/marketplace.json and claude/.claude-plugin/plugin.json, and every skill, command,
# agent and hook script those manifests imply resolves to a real file on disk.
#
# Split out of .claude/verify.sh check 19 and tests/container-matrix.sh on purpose. Check 19
# proves the CLI *accepts* the manifests, on whatever machine runs verify.sh. Container-matrix
# never installs `claude` in its throwaway containers, so its "plugin manifests valid" lane
# reports UNMEASURABLE WITHOUT CREDENTIALS by design -- see container-matrix.sh check 3. This is
# the separate, by-hand, authenticated-machine harness that gap gets routed to, the way
# tests/auto-trigger.sh is auto-trigger's: run it yourself on a machine with `claude` installed
# and logged in, not in CI, not in a container.
#
# What check 19 does NOT do, and checks 3-6 below exist for: cross-reference what the CLI's
# plugin loader actually enumerates (`claude plugin details`) against what is really on disk. A
# skill directory with broken frontmatter that the loader silently drops, or a command file the
# loader never picked up, passes `claude plugin validate` every time -- validate checks the two
# manifest files, not the tree they point into.
#
# NO MODEL CALL ANYWHERE IN THIS FILE. `claude plugin validate` and `claude plugin details` are
# both static/local: confirmed by hand against an isolated, empty CLAUDE_CONFIG_DIR with no
# login configured at all -- both still answered correctly, in well under a second, no network
# activity. Login is still required to START this script (the preflight below) because a harness
# whose own header promises "needs an authenticated CLI" quietly running without one is exactly
# the kind of gap this repo exists to close -- not because the two subcommands this file actually
# calls need it. If a future check here needs something that genuinely requires auth, do not
# isolate CLAUDE_CONFIG_DIR for it -- patch ~/.claude/settings.json and restore it on EXIT
# instead, because pointing CLAUDE_CONFIG_DIR at a fresh directory has been measured on this
# machine to report loggedIn:false even for a real session (see the preflight below, which
# depends on exactly that finding to know it must run before isolation, not after).
#
# Never mutates the operator's real ~/.claude: the one call that must see real auth (the
# preflight `claude auth status`) is read-only and runs before CLAUDE_CONFIG_DIR is touched;
# every other call in this file runs under a fresh CLAUDE_CONFIG_DIR from mktemp -d, removed on
# exit via trap, including on failure and on kill.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
REPO=$(pwd)
SELF="$REPO/tests/plugin-manifests.sh"

# Declared checks, counted from this file's own section headers -- same convention as
# .claude/verify.sh -- so adding a check here cannot leave the accounting behind.
TOTAL=$(grep -c '^# --- [0-9]' "$SELF")
RAN=0
SKIPPED=0
FAIL=0

ok(){   printf 'ok    %s\n' "$1"; RAN=$((RAN+1)); }
bad(){  printf 'FAIL  %s\n%s\n' "$1" "${2:-}"; FAIL=1; RAN=$((RAN+1)); }

print_accounting(){
  echo
  printf 'checks: %d declared, %d ran, %d skipped\n' "$TOTAL" "$RAN" "$SKIPPED"
}

# Exit 2: could not run, or could not be trusted. Charges whatever is left of TOTAL to SKIPPED
# so the printed line always accounts for every declared check, even mid-abort.
abort(){ # <reason>
  local left=$((TOTAL - RAN - SKIPPED))
  [ "$left" -gt 0 ] && SKIPPED=$((SKIPPED + left))
  echo "ABORT: $1"
  print_accounting
  echo "PLUGIN MANIFESTS: COULD NOT RUN"
  exit 2
}

# --- preflight: the claude binary and real auth, before anything is isolated -------------------
CLAUDE_BIN=$(command -v claude 2>/dev/null || true)
if [ -z "$CLAUDE_BIN" ]; then
  abort "claude CLI absent from PATH -- this harness needs the real binary on PATH, not an interactive shell's wrapper function around it"
fi
AUTH_JSON=$(timeout 15 "$CLAUDE_BIN" auth status 2>&1)
AUTH_RC=$?
if [ "$AUTH_RC" -ne 0 ] || ! grep -q '"loggedIn": *true' <<<"$AUTH_JSON"; then
  abort "claude CLI unauthenticated -- 'claude auth status' said: $(printf '%s' "$AUTH_JSON" | tr '\n' ' ')"
fi
echo "preflight: claude CLI found at $CLAUDE_BIN, authenticated ($(grep -o '"email": *"[^"]*"' <<<"$AUTH_JSON"))"
echo

# From here on, nothing this script runs may touch the operator's real ~/.claude.
CONFDIR=$(mktemp -d "${TMPDIR:-/tmp}/vstack-plugin-manifests.XXXXXX")
trap 'rm -rf "$CONFDIR"' EXIT INT TERM HUP
export CLAUDE_CONFIG_DIR="$CONFDIR"

# --- 0a. positive control: the validator can be trusted on plugin.json's schema ----------------
# Before believing any clean answer below, prove the validator actually discriminates. A
# validator that says yes to everything is indistinguishable from a healthy repo; one that says
# no to everything is indistinguishable from a broken one. This repo has shipped the first kind
# once already (verify.sh check 19's own history): `claude plugin validate` exited 0 on CI
# against a manifest deliberately broken by the falsifiability suite, while the same CLI version
# rejected the same manifest locally. Require both directions, or stop rather than report someone
# else's silence as a finding about this repo.
ctl=$(mktemp -d)
mkdir -p "$ctl/good/.claude-plugin" "$ctl/bad/.claude-plugin"
printf '{"name":"probe","version":"0.0.1","description":"control","author":{"name":"control"}}\n' \
  > "$ctl/good/.claude-plugin/plugin.json"
printf '{"name":42,"version":"nope"}\n' > "$ctl/bad/.claude-plugin/plugin.json"
good_out=$("$CLAUDE_BIN" plugin validate --strict "$ctl/good" 2>&1); good_rc=$?
bad_out=$("$CLAUDE_BIN" plugin validate --strict "$ctl/bad" 2>&1); bad_rc=$?
rm -rf "$ctl"
if [ "$good_rc" -eq 0 ] && [ "$bad_rc" -ne 0 ]; then
  ok "positive control: plugin.json schema (accepted a good fixture, rejected name:42)"
else
  bad "positive control: plugin.json schema" \
    "good exit=$good_rc bad exit=$bad_rc -- validator does not discriminate$(printf '\n--good--\n%s\n--bad--\n%s' "$good_out" "$bad_out")"
  abort "control 0a did not bite -- reporting checks 1-6's answers would be reporting this validator's silence, not this repo's health"
fi

# --- 0b. positive control: the validator can be trusted on marketplace.json's schema -----------
# Same control, the other manifest's schema. plugin.json and marketplace.json are validated by
# different code paths inside the CLI (confirmed: "Validating plugin manifest" vs "Validating
# marketplace manifest" in its own output) so a validator that discriminates on one schema is not
# evidence it discriminates on the other.
ctl=$(mktemp -d)
mkdir -p "$ctl/good/.claude-plugin" "$ctl/good/plugin/.claude-plugin" "$ctl/bad/.claude-plugin"
printf '{"name":"probe","version":"0.0.1","description":"control","author":{"name":"control"}}\n' \
  > "$ctl/good/plugin/.claude-plugin/plugin.json"
printf '{"name":"probe-marketplace","owner":{"name":"control"},"metadata":{"description":"control"},"plugins":[{"name":"probe","source":"./plugin","version":"0.0.1","description":"control"}]}\n' \
  > "$ctl/good/.claude-plugin/marketplace.json"
printf '{"name":"probe-marketplace","owner":{},"plugins":[{"name":"probe","source":"./missing"}]}\n' \
  > "$ctl/bad/.claude-plugin/marketplace.json"
good_out=$("$CLAUDE_BIN" plugin validate --strict "$ctl/good" 2>&1); good_rc=$?
bad_out=$("$CLAUDE_BIN" plugin validate --strict "$ctl/bad" 2>&1); bad_rc=$?
rm -rf "$ctl"
if [ "$good_rc" -eq 0 ] && [ "$bad_rc" -ne 0 ]; then
  ok "positive control: marketplace.json schema (accepted a good fixture, rejected owner:{})"
else
  bad "positive control: marketplace.json schema" \
    "good exit=$good_rc bad exit=$bad_rc -- validator does not discriminate$(printf '\n--good--\n%s\n--bad--\n%s' "$good_out" "$bad_out")"
  abort "control 0b did not bite -- reporting checks 1-6's answers would be reporting this validator's silence, not this repo's health"
fi

# --- 1. claude CLI accepts this repo's marketplace manifest ------------------------------------
out=$("$CLAUDE_BIN" plugin validate "$REPO" 2>&1); rc=$?
if [ "$rc" -eq 0 ]; then
  ok "marketplace manifest accepted (.claude-plugin/marketplace.json)"
else
  bad "marketplace manifest accepted" "$out"
fi

# --- 2. claude CLI accepts this repo's plugin manifest ------------------------------------------
# Plain validate, not --strict: verify.sh check 19 already runs the stricter form (against a
# CLAUDE.md-stripped copy, to dodge one known, accepted, deliberate warning about CLAUDE.md at
# the plugin root). This check asks the plainer question this file's containers-can't-answer
# scope actually needs -- does the CLI accept the manifest at all -- against the real tree,
# warning and all.
out=$("$CLAUDE_BIN" plugin validate "$REPO/claude" 2>&1); rc=$?
if [ "$rc" -eq 0 ]; then
  ok "plugin manifest accepted (claude/.claude-plugin/plugin.json)"
else
  bad "plugin manifest accepted" "$out"
fi

# --- component inventory, shared by checks 3-5 --------------------------------------------------
PLUGIN_NAME=$(grep -m1 '"name"' "$REPO/claude/.claude-plugin/plugin.json" | sed -E 's/.*"name": *"([^"]*)".*/\1/')
details_out=$("$CLAUDE_BIN" --plugin-dir "$REPO/claude" plugin details "$PLUGIN_NAME" 2>&1)
details_rc=$?
skills_line=$(printf '%s\n' "$details_out" | grep '^  Skills (')
agents_line=$(printf '%s\n' "$details_out" | grep '^  Agents (')

fs_skills_file=$(mktemp)
{
  for d in "$REPO"/claude/skills/*/; do [ -d "$d" ] || continue; basename "$d"; done
  for f in "$REPO"/claude/commands/*.md; do [ -f "$f" ] || continue; basename "$f" .md; done
} | sort > "$fs_skills_file"

fs_agents_file=$(mktemp)
for f in "$REPO"/claude/agents/*.md; do [ -f "$f" ] || continue; basename "$f" .md; done \
  | sort > "$fs_agents_file"

# --- 3. every skill/command the loader reports exists on disk, and vice versa ------------------
# `claude plugin details` folds slash-commands into the same "Skills" inventory (43 = 28 skill
# directories + 15 command files here) because the loader exposes both the same way at runtime.
if [ "$details_rc" -ne 0 ] || [ -z "$skills_line" ]; then
  bad "loader inventory matches disk: skills+commands" \
    "'claude plugin details $PLUGIN_NAME' exit=$details_rc, no Skills line in its output: $details_out"
else
  cli_skills_file=$(mktemp)
  printf '%s\n' "$skills_line" | sed -E 's/^  Skills \([0-9]+\)  //' \
    | tr ',' '\n' | sed -E 's/^ +//; s/ +$//' | sort > "$cli_skills_file"
  if diff_out=$(diff "$cli_skills_file" "$fs_skills_file"); then
    ok "loader inventory matches disk: skills+commands ($(grep -c . "$fs_skills_file") on disk, all named by the loader)"
  else
    bad "loader inventory matches disk: skills+commands" "loader vs disk (< loader, > disk):$(printf '\n%s' "$diff_out")"
  fi
  rm -f "$cli_skills_file"
fi

# --- 4. every agent the loader reports exists on disk, and vice versa --------------------------
if [ "$details_rc" -ne 0 ] || [ -z "$agents_line" ]; then
  bad "loader inventory matches disk: agents" \
    "'claude plugin details $PLUGIN_NAME' exit=$details_rc, no Agents line in its output: $details_out"
else
  cli_agents_file=$(mktemp)
  printf '%s\n' "$agents_line" | sed -E 's/^  Agents \([0-9]+\)  //' \
    | tr ',' '\n' | sed -E 's/^ +//; s/ +$//' | sort > "$cli_agents_file"
  if diff_out=$(diff "$cli_agents_file" "$fs_agents_file"); then
    ok "loader inventory matches disk: agents ($(grep -c . "$fs_agents_file") on disk, all named by the loader)"
  else
    bad "loader inventory matches disk: agents" "loader vs disk (< loader, > disk):$(printf '\n%s' "$diff_out")"
  fi
  rm -f "$cli_agents_file"
fi
rm -f "$fs_skills_file" "$fs_agents_file"

# --- 5. every skill directory the loader counted carries a SKILL.md ----------------------------
missing=""
for d in "$REPO"/claude/skills/*/; do
  [ -d "$d" ] || continue
  [ -f "${d}SKILL.md" ] || missing="$missing ${d#"$REPO"/}"
done
if [ -z "$missing" ]; then
  ok "every claude/skills/*/ directory carries a SKILL.md"
else
  bad "every claude/skills/*/ directory carries a SKILL.md" "missing SKILL.md in:$missing"
fi

# --- 6. every hook script hooks.json references exists and is executable -----------------------
# The session hook and the Stop-gate hooks are the mechanism every other check in this repo's
# gate depends on; a manifest that validates cleanly while pointing hooks.json at a script that
# was renamed or never shipped would still pass checks 1-2 and would still install.
refs_file=$(mktemp)
grep -oE '\{CLAUDE_PLUGIN_ROOT\}/hooks/[A-Za-z0-9_.-]+\.sh' "$REPO/claude/hooks/hooks.json" \
  | sed -E 's#.*/##' | sort -u > "$refs_file"
if [ ! -s "$refs_file" ]; then
  bad "hooks.json script references resolve to files" \
    "no \${CLAUDE_PLUGIN_ROOT}/hooks/*.sh reference found in claude/hooks/hooks.json -- extraction pattern stale or file moved"
else
  missing=""
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    f="$REPO/claude/hooks/$name"
    if [ ! -f "$f" ]; then missing="$missing $name(missing)"
    elif [ ! -x "$f" ]; then missing="$missing $name(not-executable)"
    fi
  done < "$refs_file"
  if [ -z "$missing" ]; then
    ok "hooks.json script references resolve to files ($(grep -c . "$refs_file") scripts)"
  else
    bad "hooks.json script references resolve to files" "$missing"
  fi
fi
rm -f "$refs_file"

# --- accounting ----------------------------------------------------------------------------------
# Every declared check above must have reported ok or bad. RAN==0 here is the floor: a harness
# that ran nothing has not agreed with anything, and must never be read as a pass.
print_accounting
if [ "$RAN" -eq 0 ]; then
  echo "FLOOR VIOLATED: 0 of $TOTAL checks ran -- this harness verified nothing"
  echo "PLUGIN MANIFESTS: COULD NOT RUN"
  exit 2
fi
if [ "$((RAN + SKIPPED))" -ne "$TOTAL" ]; then
  echo "check accounting: $((TOTAL - RAN - SKIPPED)) declared check(s) reported nothing"
  echo "PLUGIN MANIFESTS: FAILED"
  exit 1
fi
if [ "$FAIL" -ne 0 ]; then
  echo "PLUGIN MANIFESTS: FAILED"
  exit 1
fi
echo "PLUGIN MANIFESTS: VERIFIED"
exit 0
