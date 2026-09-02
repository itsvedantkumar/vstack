#!/usr/bin/env bash
# tests/repro/formatter-config-devdep.sh
#
# format.sh's find_prettier_cfg() walks up from the edited file's directory and, for each
# directory, tries config filenames in order with package.json FIRST -- matching prettier's own
# cosmiconfig search order. To decide whether a given package.json actually configures prettier,
# it used to grep it for `"prettier"[[:space:]]*:`. That regex matches the source text of
# `"prettier": "^3.4.2"` sitting inside "devDependencies" just as happily as a real top-level
# "prettier" key -- a version pin is not a config, but the grep cannot tell them apart. So a
# perfectly ordinary package.json with prettier merely listed as a devDependency won the
# package.json slot ahead of a sibling .prettierrc in the very same directory, and the hook ran
# `prettier --config package.json --write`. Prettier finds no real "prettier" field in that
# file, silently falls back to its own built-in defaults (this is not an error prettier raises;
# cosmiconfig just treats "found the file, no matching field" as "nothing configured"), and
# reformats the file to those defaults -- the repo's real .prettierrc is never reached, because
# find_prettier_cfg already returned on the first name it tried.
#
# This builds one throwaway repo with a package.json whose only "prettier" mention is a
# devDependency version range, and a sibling .prettierrc with {"singleQuote": true}. It writes a
# double-quoted .ts file and fires format.sh at it exactly the way Claude Code's PostToolUse
# hook would. Then, to prove this is not a no-op, it re-runs the identical case against the
# newest committed blob of format.sh that predates the parse-instead-of-grep fix -- derived by
# walking this file's history newest-first, the same technique tests/repro/formatter-config.sh
# uses for its own no-op proof, so the baseline cannot rot once the fix is committed, rebased,
# or reverted.
#
# Exit 0 -- fixed: .prettierrc's singleQuote wins, and the pre-fix blob demonstrably picked
#           package.json instead (proving the test measures something real).
# Exit 1 -- the devDependency version range still wins, or the harness itself is broken.
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
HOOK="$REPO_ROOT/claude/hooks/format.sh"

FAIL=0
note(){ printf '%s\n' "$1"; }
ok(){   printf 'ok    %s\n' "$1"; }
bad(){  printf 'FAIL  %s\n' "$1"; FAIL=1; }

[ -x "$HOOK" ] || { echo "FAIL  $HOOK missing or not executable"; exit 1; }
command -v npm >/dev/null 2>&1 || { echo "skip  npm not installed on this host; cannot install a real prettier to exercise config resolution"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "skip  git not installed; cannot fetch the pre-fix blob for the no-op proof"; exit 0; }

# Own sandbox variable, never $HOME itself -- guard-destructive.sh blocks rm -rf "$HOME"-shaped
# commands even with HOME reassigned, and everything below cleans up its own tree, not HOME.
FMT_SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/vstack-formatter-devdep.XXXXXX")
FMT_SANDBOX=$(cd "$FMT_SANDBOX" && pwd)  # normalize away a doubled slash from a trailing-slash TMPDIR
cleanup(){ rm -rf "$FMT_SANDBOX"; }
trap cleanup EXIT

VENDOR="$FMT_SANDBOX/vendor"
mkdir -p "$VENDOR"

note "-- installing prettier@3.9.6 once, shared across repo copies --"
if ! npm install prettier@3.9.6 --no-save --prefix "$VENDOR" >"$FMT_SANDBOX/npm-install.log" 2>&1; then
  echo "skip  npm install prettier failed (offline?); see $FMT_SANDBOX/npm-install.log before cleanup races it"
  cat "$FMT_SANDBOX/npm-install.log"
  exit 0
fi
[ -x "$VENDOR/node_modules/.bin/prettier" ] || { echo "skip  prettier install did not produce an executable; cannot exercise config resolution"; exit 0; }

make_repo() { # $1: repo dir
  d="$1"
  mkdir -p "$d"
  ln -s "$VENDOR/node_modules" "$d/node_modules"
  # The only "prettier" mention in this package.json is a devDependency version range -- never
  # a config. .prettierrc is the real config, and it disagrees with prettier's built-in default
  # (singleQuote:false) so the two outcomes are distinguishable by inspecting quote style alone.
  cat > "$d/package.json" <<'EOF'
{
  "name": "devdep-repro",
  "private": true,
  "devDependencies": {
    "prettier": "^3.4.2"
  }
}
EOF
  cat > "$d/.prettierrc" <<'EOF'
{"singleQuote": true, "printWidth": 90}
EOF
  printf 'const x = "hello";\n' > "$d/target.ts"
}

run_hook() { # $1: hook script, $2: repo dir
  f="$2/target.ts"
  echo '{"tool_input":{"file_path":"'"$f"'"}}' | env HOME="$FMT_SANDBOX" CLAUDE_PROJECT_DIR="$2" "$1" >/dev/null 2>&1
}

# --- the claimed defect: fixed hook must prefer .prettierrc over the devDependency line ------
REPO_FIXED="$FMT_SANDBOX/fixed-repo"
make_repo "$REPO_FIXED"
run_hook "$HOOK" "$REPO_FIXED"
if grep -q "'hello'" "$REPO_FIXED/target.ts"; then
  ok ".prettierrc won: devDependency version range no longer mistaken for a prettier config"
elif grep -q '"hello"' "$REPO_FIXED/target.ts"; then
  bad "HOLE OPEN: package.json's devDependency line still won the package.json slot -- file was formatted (or left unformatted) with built-in defaults, not .prettierrc"
else
  bad "target.ts contents unrecognized after running the fixed hook: $(cat "$REPO_FIXED/target.ts" 2>/dev/null)"
fi

# --- no-op proof: same case against the newest committed blob predating the parse fix --------
PREFIX_HOOK="$FMT_SANDBOX/format-prefix.sh"
# The guard function's own name is the discriminator, anchored on the function rather than a
# pinned SHA -- a SHA is a second place to remember, and the one that goes stale first.
GUARD_MARK='pkg_has_top_level_prettier'
PREFIX_SHA=''
for _c in $(git -C "$REPO_ROOT" log --format=%H -- claude/hooks/format.sh); do
  if ! git -C "$REPO_ROOT" show "$_c:claude/hooks/format.sh" 2>/dev/null | grep -q "$GUARD_MARK"; then
    PREFIX_SHA="$_c"
    break
  fi
done
if [ -z "$PREFIX_SHA" ]; then
  bad "no commit of claude/hooks/format.sh predates the $GUARD_MARK guard -- the no-op proof has no baseline to revert to, so this test cannot show it measures anything"
  exit 1
fi
if ! git -C "$REPO_ROOT" show "$PREFIX_SHA:claude/hooks/format.sh" > "$PREFIX_HOOK" 2>/dev/null; then
  bad "could not read $PREFIX_SHA:claude/hooks/format.sh to build the no-op proof"
  exit 1
fi
chmod +x "$PREFIX_HOOK"
REPO_REVERT="$FMT_SANDBOX/revert-repo"
make_repo "$REPO_REVERT"
run_hook "$PREFIX_HOOK" "$REPO_REVERT"
if grep -q '"hello"' "$REPO_REVERT/target.ts" && ! grep -q "'hello'" "$REPO_REVERT/target.ts"; then
  ok "no-op proof: format.sh at $PREFIX_SHA does mistake the devDependency line for a config -- this test is not vacuous"
else
  bad "no-op proof failed: reverting to $PREFIX_SHA (the newest format.sh without $GUARD_MARK) did NOT reproduce the false match -- this test cannot detect the bug it claims to"
fi

[ "$FAIL" -eq 0 ] && echo "FORMATTER PACKAGE.JSON FALSE MATCH: CLOSED" || echo "FORMATTER PACKAGE.JSON FALSE MATCH: OPEN"
exit "$FAIL"
