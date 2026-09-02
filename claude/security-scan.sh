#!/usr/bin/env bash
# security-scan.sh — secret, static-analysis, and dependency scan for this repo.
#
# Run directly, or via .claude/verify.sh (which calls this if present). Prints one line per
# tool: `ok NAME`, `FAIL NAME` (+ up to 20 lines of output), or `skip NAME (reason)`. A tool
# that isn't installed is a skip, not a fail — this script never fails a repo for a missing
# scanner. Exit 1 iff at least one tool ran and failed; exit 0 otherwise.
set -u

usage() {
  cat <<'EOF'
usage: security-scan.sh [--staged]

Runs gitleaks, semgrep, osv-scanner, zizmor, and (conditionally) eslint against the
current repo and prints one result line per tool.

  --staged   scan staged changes only (gitleaks git --pre-commit --staged), instead of
             the full working tree.
  --help     print this message.

Env:
  SECURITY_SCAN_TIMEOUT   seconds allowed per tool before it's killed and reported as a
                           timeout failure (default 300). No-op if `timeout` isn't installed.
EOF
}

staged=0
for arg in "$@"; do
  case "$arg" in
    --staged) staged=1 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "security-scan: unknown flag: $arg" >&2; usage >&2; exit 2 ;;
  esac
done

if root=$(git rev-parse --show-toplevel 2>/dev/null); then
  cd "$root" || exit 1
fi

n_ok=0
n_fail=0
n_skip=0
ok(){   printf 'ok    %s\n' "$1"; n_ok=$((n_ok + 1)); }
bad(){  printf 'FAIL  %s\n' "$1"; printf '%s\n' "$2" | sed 's/^/  /'; n_fail=$((n_fail + 1)); }
skip(){ printf 'skip  %s (%s)\n' "$1" "$2"; n_skip=$((n_skip + 1)); }

timeout_bin=""
command -v timeout >/dev/null 2>&1 && timeout_bin="timeout"
scan_timeout="${SECURITY_SCAN_TIMEOUT:-300}"

# gl_tmp is the only cross-invocation tmp dir this script creates (for the gitleaks file-set
# copy below). One EXIT trap covers it regardless of where the script stops.
gl_tmp=""
cleanup() { [ -n "$gl_tmp" ] && rm -rf "$gl_tmp"; }
trap cleanup EXIT

# run_scan: execute "$@" under `timeout` (when available), capturing combined output into
# $scan_out and its exit code into $scan_rc. A no-op wrapper when timeout isn't installed —
# the command still runs, it just can't be killed early.
scan_out=""
scan_rc=0
run_scan() {
  if [ -n "$timeout_bin" ]; then
    scan_out=$("$timeout_bin" "$scan_timeout" "$@" 2>&1)
  else
    scan_out=$("$@" 2>&1)
  fi
  scan_rc=$?
}

# report_scan NAME: turn $scan_rc/$scan_out from the last run_scan into an ok/FAIL line.
# Exit 124 from GNU/BSD `timeout` means the tool was killed for running too long — call that
# out by name rather than dumping whatever partial output it left behind.
report_scan() {
  if [ "$scan_rc" -eq 0 ]; then
    ok "$1"
  elif [ "$scan_rc" -eq 124 ] && [ -n "$timeout_bin" ]; then
    bad "$1" "timed out after ${scan_timeout}s"
  else
    bad "$1" "$(printf '%s' "$scan_out" | tail -20)"
  fi
}

# --- 1. gitleaks: secrets in the files git can see ----------------------------------------------
if ! command -v gitleaks >/dev/null 2>&1; then
  skip "gitleaks" "not installed"
elif ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  skip "gitleaks" "not a git repo"
else
  # A repo-tracked .gitleaks.toml changes what counts as a leak (allowlists, custom rules).
  # Report which one applied so a reviewer sees when an allowlist is in play.
  if [ -f .gitleaks.toml ]; then gl_cfg_label=".gitleaks.toml"; else gl_cfg_label="default"; fi

  if [ "$staged" = 1 ]; then
    run_scan gitleaks git --pre-commit --staged --no-banner --redact
    if [ "$scan_rc" -eq 0 ]; then
      ok "gitleaks (config: $gl_cfg_label)"
    elif [ "$scan_rc" -eq 124 ] && [ -n "$timeout_bin" ]; then
      bad "gitleaks" "timed out after ${scan_timeout}s"
    else
      bad "gitleaks" "$(printf '%s' "$scan_out" | tail -20)"
    fi
  else
    # `gitleaks dir .` has no concept of .gitignore and will happily scan build output
    # (.next, dist, node_modules, coverage, ...) as if it were source, reporting "leaks" that
    # are really just bundled/minified vendor code. Scan only what git itself would see: the
    # tracked files plus anything untracked that isn't ignored. Copy that file set into a
    # throwaway directory (preserving paths) so gitleaks' target is exactly that set, then
    # strip the tmp-dir prefix back out of anything we print.
    gl_tmp=$(mktemp -d)
    while IFS= read -r -d '' f; do
      d=$(dirname "$f")
      mkdir -p "$gl_tmp/$d" 2>/dev/null || continue
      cp -p "$f" "$gl_tmp/$f" 2>/dev/null || true
    done < <(git ls-files -co --exclude-standard -z)

    gl_cmd=(gitleaks dir --no-banner --redact -v)
    if [ "$gl_cfg_label" = ".gitleaks.toml" ] && [ -f "$gl_tmp/.gitleaks.toml" ]; then
      gl_cmd+=(--config "$gl_tmp/.gitleaks.toml")
    fi
    gl_cmd+=("$gl_tmp")

    run_scan "${gl_cmd[@]}"
    # Physical path too: mktemp's dir can sit behind a symlink (macOS /var -> /private/var),
    # and gitleaks reports whichever form it resolved, not necessarily the one we hold.
    gl_tmp_phys=$(cd "$gl_tmp" 2>/dev/null && pwd -P || true)
    scan_out=$(printf '%s' "$scan_out" | sed -e "s|$gl_tmp/||g" -e "s|${gl_tmp_phys:-$gl_tmp}/||g")

    if [ "$scan_rc" -eq 0 ]; then
      ok "gitleaks (config: $gl_cfg_label)"
    elif [ "$scan_rc" -eq 124 ] && [ -n "$timeout_bin" ]; then
      bad "gitleaks" "timed out after ${scan_timeout}s"
    else
      bad "gitleaks" "$(printf '%s' "$scan_out" | tail -20)"
    fi

    rm -rf "$gl_tmp"
    gl_tmp=""
  fi
fi

# --- 2. semgrep: static analysis ----------------------------------------------------------------
if ! command -v semgrep >/dev/null 2>&1; then
  skip "semgrep" "not installed"
else
  configs=(--config p/owasp-top-ten)
  if [ -f package.json ]; then
    configs=(--config p/typescript --config p/owasp-top-ten)
    grep -q '"next"' package.json 2>/dev/null && configs+=(--config p/nextjs)
  fi
  if [ -f pyproject.toml ]; then
    configs+=(--config p/python)
  fi
  run_scan semgrep scan "${configs[@]}" --error --quiet --metrics=off \
    --exclude node_modules --exclude .next --exclude dist .
  report_scan "semgrep"
fi

# --- 3. osv-scanner: known vulnerabilities in dependencies ---------------------------------------
lockfile=""
for f in package-lock.json pnpm-lock.yaml yarn.lock uv.lock poetry.lock Cargo.lock go.sum; do
  [ -f "$f" ] && { lockfile="$f"; break; }
done
if ! command -v osv-scanner >/dev/null 2>&1; then
  skip "osv-scanner" "not installed"
elif [ -z "$lockfile" ]; then
  skip "osv-scanner" "no lockfile in repo"
else
  run_scan osv-scanner scan source --lockfile "$lockfile"
  report_scan "osv-scanner"
fi

# --- 4. zizmor: GitHub Actions workflow audit -----------------------------------------------------
if ! command -v zizmor >/dev/null 2>&1; then
  skip "zizmor" "not installed"
elif [ ! -d .github/workflows ]; then
  skip "zizmor" "no .github/workflows in repo"
else
  run_scan zizmor --min-severity medium .github/workflows
  report_scan "zizmor"
fi

# --- 5. eslint: only when verify.sh's own `lint` script won't cover it -------------------------
has_eslint_config=0
for f in eslint.config.js eslint.config.mjs eslint.config.cjs eslint.config.ts \
  .eslintrc .eslintrc.js .eslintrc.cjs .eslintrc.json .eslintrc.yml .eslintrc.yaml; do
  [ -f "$f" ] && has_eslint_config=1
done
has_lint_script=0
if [ -f package.json ]; then
  node -e "process.exit(require('./package.json').scripts?.lint?0:1)" 2>/dev/null && has_lint_script=1
fi
if [ "$has_eslint_config" = 0 ]; then
  skip "eslint" "no eslint config in repo"
elif [ "$has_lint_script" = 1 ]; then
  skip "eslint" "covered by npm run lint"
elif ! command -v npx >/dev/null 2>&1; then
  skip "eslint" "not installed"
else
  run_scan npx --no-install eslint .
  report_scan "eslint"
fi

echo "security-scan: $n_ok ok, $n_fail fail, $n_skip skip"
[ "$n_fail" -eq 0 ]
