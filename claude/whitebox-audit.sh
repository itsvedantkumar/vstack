#!/usr/bin/env bash
# whitebox-audit.sh — the deep security lane. Runs every scanner installed on this machine that
# applies to this repository, normalises what they say into one findings file, and refuses to
# report a clean repository when nothing measured it.
#
# This is NOT claude/security-scan.sh. That one is the fast lane: five tools, seconds, wired into
# .claude/verify.sh and every Stop-hook gate, and it exits 0 when every scanner is missing so a
# machine without scanners can still ship. This one is the opposite trade: minutes, every
# ecosystem, and exit 2 when it could not measure. Read the exit codes before wiring it anywhere:
#
#   0  at least one scanner ran and none of them found anything
#   1  at least one scanner found something (findings.jsonl has the details)
#   2  nothing ran, or the tree could not be determined -- NOT a clean result
#
# Nothing here edits your code. Fixing is the caller's job (see the whitebox-pentest skill), and
# a scanner that reports is a scanner whose findings you can still argue with.
#
# Active-attack tools (nuclei, nikto, sqlmap, ffuf, zap) are off unless you pass BOTH --dast URL
# and --i-own-this-target. Pointing them at something you do not own is a crime in most places,
# and a flag you have to type twice is the cheapest possible speed bump.
set -u

VERSION=1

usage() {
  cat <<'EOF'
usage: whitebox-audit.sh [options]

Deep security audit of the current repository. Runs every applicable scanner that is installed,
skips (by name, with a reason) every one that is not, and writes machine-readable findings.

  --out DIR             where to write the report (default .whitebox-audit/<timestamp>)
  --only LIST           comma-separated tool names; run only these
  --skip LIST           comma-separated tool names; run everything but these
  --deep                also run the slow ones (codeql database build, trivy full fs scan)
  --dast URL            run the active-attack tools against URL (requires --i-own-this-target)
  --i-own-this-target   your assertion that you are authorised to attack --dast's target
  --quiet               only print the summary and the failures
  --list                print the tool matrix (installed / missing) and exit 0
  --help                this message

Exit: 0 clean (something ran), 1 findings, 2 nothing ran / could not measure.

Env:
  WHITEBOX_TIMEOUT   seconds per tool (default 600)
EOF
}

OUT=""
ONLY=""
SKIP=""
DEEP=0
DAST_URL=""
OWNED=0
QUIET=0
LIST=0
while [ $# -gt 0 ]; do
  case "$1" in
    --out) OUT="${2:-}"; shift 2 ;;
    --only) ONLY="${2:-}"; shift 2 ;;
    --skip) SKIP="${2:-}"; shift 2 ;;
    --deep) DEEP=1; shift ;;
    --dast) DAST_URL="${2:-}"; shift 2 ;;
    --i-own-this-target) OWNED=1; shift ;;
    --quiet) QUIET=1; shift ;;
    --list) LIST=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "whitebox-audit: unknown flag: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if root=$(git rev-parse --show-toplevel 2>/dev/null); then
  cd "$root" || exit 2
else
  root=$(pwd -P)
fi

TIMEOUT_S="${WHITEBOX_TIMEOUT:-600}"
timeout_bin=""
command -v timeout >/dev/null 2>&1 && timeout_bin="timeout"

n_ok=0; n_find=0; n_skip=0; n_err=0
declare_list=""

have() { command -v "$1" >/dev/null 2>&1; }
in_csv() { case ",$2," in *",$1,"*) return 0 ;; *) return 1 ;; esac; }

# wanted: should this tool run at all? --only wins over --skip; both are exact-name matches, so a
# typo silently running everything is not possible -- an unknown --only name runs nothing and the
# accounting at the end says so.
wanted() {
  declare_list="$declare_list $1"
  [ -n "$ONLY" ] && { in_csv "$1" "$ONLY" || return 1; }
  [ -n "$SKIP" ] && { in_csv "$1" "$SKIP" && return 1; }
  return 0
}

say()  { [ "$QUIET" = 1 ] || printf '%s\n' "$*"; }
ok()   { n_ok=$((n_ok+1));   say "ok      $1"; }
find_() { n_find=$((n_find+1)); printf 'FINDING %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | head -20 | sed 's/^/  /'; }
skip() { n_skip=$((n_skip+1)); say "skip    $1 ($2)"; }
err()  { n_err=$((n_err+1));  printf 'ERROR   %s (%s)\n' "$1" "$2"; }

# --- stack detection ----------------------------------------------------------------------------
# Every later decision keys off these. Detection is by file, never by guessing from a directory
# name: a repo with a vendored go.sum and no Go source still gets govulncheck pointed at it, and
# that is the correct conservative answer.
has_py=0;  [ -f pyproject.toml ] || [ -f requirements.txt ] || [ -f setup.py ] || [ -f Pipfile ] || compgen -G "*.py" >/dev/null 2>&1 && has_py=1
has_js=0;  [ -f package.json ] && has_js=1
has_go=0;  [ -f go.mod ] && has_go=1
has_rs=0;  [ -f Cargo.toml ] && has_rs=1
has_rb=0;  [ -f Gemfile ] && has_rb=1
has_php=0; [ -f composer.json ] && has_php=1
has_java=0; { [ -f pom.xml ] || [ -f build.gradle ] || [ -f build.gradle.kts ]; } && has_java=1
has_docker=0; { [ -f Dockerfile ] || compgen -G "*/Dockerfile" >/dev/null 2>&1; } && has_docker=1
has_iac=0; { compgen -G "*.tf" >/dev/null 2>&1 || [ -d k8s ] || compgen -G "*.yaml" >/dev/null 2>&1; } && has_iac=1
has_gha=0; [ -d .github/workflows ] && has_gha=1
has_sh=0;  git ls-files '*.sh' 2>/dev/null | head -1 | grep -q . && has_sh=1

if [ "$LIST" = 1 ]; then
  printf 'whitebox-audit tool matrix (v%s)\n\n' "$VERSION"
  printf '%-16s %-10s %s\n' TOOL STATUS APPLIES
  # Exactly the binaries the lanes below invoke. A matrix that lists a tool this script never
  # runs is a promise it does not keep, and the first thing a reader would check it against.
  for t in gitleaks trufflehog detect-secrets semgrep codeql bandit ruff pip-audit \
           npm npx retire gosec govulncheck staticcheck cargo clippy brakeman bundle-audit \
           phpstan psalm shellcheck hadolint trivy grype syft checkov terrascan kics \
           zizmor actionlint osv-scanner nuclei nikto docker; do
    if have "$t"; then st=INSTALLED; else st=MISSING; fi
    printf '%-16s %-10s\n' "$t" "$st"
  done
  exit 0
fi

if [ -z "$OUT" ]; then OUT=".whitebox-audit/$(date +%Y%m%d-%H%M%S)"; fi
mkdir -p "$OUT/raw" || exit 2
FINDINGS="$OUT/findings.jsonl"
: > "$FINDINGS"

# run: execute a tool, capture combined output to $OUT/raw/<name>.txt, set $rc.
# Every tool's raw output is kept whatever the verdict. A finding you cannot re-read is a finding
# you cannot argue with, and the triage step downstream reads these files, not this script's
# stdout.
rc=0
run() { # <name> <cmd...>
  local name="$1"; shift
  local f="$OUT/raw/$name.txt"
  if [ -n "$timeout_bin" ]; then
    "$timeout_bin" "$TIMEOUT_S" "$@" > "$f" 2>&1
  else
    "$@" > "$f" 2>&1
  fi
  rc=$?
  return 0
}

# verdict: turn an exit code into one of ok / FINDING / ERROR, given which codes this tool uses
# for "found something". Tools disagree wildly: semgrep --error uses 1, npm audit uses 1, trivy
# needs --exit-code 1 to say anything at all, and shellcheck uses 1 for both a finding and a
# usage error. Passing the finding codes in per call is the only honest way to read them.
# aborted: did this tool fail to run, rather than run and find something? Several scanners exit
# with their finding code when they could not start at all -- trivy answers a failed vulnerability-DB
# download with exit 1, the same code it uses for "found a CVE" -- so reading the code alone files
# an infrastructure failure as a security finding and, worse, leaves the errored count at zero. That
# is coverage loss reported as work done. Signatures only, and narrow ones: each is a line a tool
# prints when it is giving up, none of them is a finding format.
aborted() { # <raw_output_file>
  [ -f "$1" ] || return 1
  /usr/bin/grep -qE '(^|[[:space:]])(FATAL|Fatal error)([[:space:]]|$)|failed to download|error getting credentials|could not (connect|resolve|open)|panic: runtime error|Traceback \(most recent call last\)|command not found|no such host' "$1"
}

verdict() { # <name> <finding_codes_csv>
  local name="$1" codes="$2"
  local f="$OUT/raw/$name.txt"
  if [ "$rc" -eq 124 ] && [ -n "$timeout_bin" ]; then
    err "$name" "timed out after ${TIMEOUT_S}s"
  elif [ "$rc" -eq 0 ]; then
    ok "$name"
  elif aborted "$f"; then
    err "$name" "exit $rc but the output says it could not run, see raw/$name.txt"
  elif in_csv "$rc" "$codes"; then
    find_ "$name" "$(tail -20 "$f" 2>/dev/null)"
    printf '{"tool":"%s","status":"finding","rc":%s,"raw":"%s"}\n' "$name" "$rc" "raw/$name.txt" >> "$FINDINGS"
  else
    err "$name" "exit $rc, see raw/$name.txt"
  fi
}

say "whitebox-audit v$VERSION on $root"
say "stack: py=$has_py js=$has_js go=$has_go rust=$has_rs ruby=$has_rb php=$has_php java=$has_java docker=$has_docker iac=$has_iac gha=$has_gha sh=$has_sh"
say ""

# --- secrets ------------------------------------------------------------------------------------
if wanted gitleaks; then
  if ! have gitleaks; then skip gitleaks "not installed"
  elif ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then skip gitleaks "not a git repo"
  else
    run gitleaks gitleaks dir --no-banner --redact --report-format json --report-path "$OUT/raw/gitleaks.json" .
    verdict gitleaks 1
  fi
fi
if wanted gitleaks-history; then
  if ! have gitleaks; then skip gitleaks-history "not installed"
  elif ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then skip gitleaks-history "not a git repo"
  else
    # The working tree is the smaller half of the question. A key deleted in the commit that
    # "removed" it is still in the history, still fetchable, and still valid until rotated.
    run gitleaks-history gitleaks git --no-banner --redact --log-opts=--all .
    verdict gitleaks-history 1
  fi
fi
if wanted trufflehog; then
  if have trufflehog; then run trufflehog trufflehog filesystem . --no-update --fail; verdict trufflehog 183
  else skip trufflehog "not installed (brew install trufflehog)"; fi
fi
if wanted detect-secrets; then
  if ! have detect-secrets; then skip detect-secrets "not installed (uv tool install detect-secrets)"
  else
    # `detect-secrets scan` exits 0 whether or not it found anything -- it emits a baseline, and
    # the non-zero exit belongs to `detect-secrets audit` against that baseline. Wiring this lane
    # to its exit code would have shipped a scanner that can never report, which is the same
    # defect as a gate that greps its own success line. Read the results object instead.
    run detect-secrets detect-secrets scan --all-files
    if [ "$rc" -ne 0 ]; then
      err detect-secrets "exit $rc, see raw/detect-secrets.txt"
    elif ds_n=$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(sum(len(v) for v in d.get("results",{}).values()))' "$OUT/raw/detect-secrets.txt" 2>/dev/null) && [ "${ds_n:-0}" -gt 0 ]; then
      find_ detect-secrets "$ds_n potential secret(s); see raw/detect-secrets.txt"
      printf '{"tool":"detect-secrets","status":"finding","rc":0,"count":%s,"raw":"raw/detect-secrets.txt"}\n' "$ds_n" >> "$FINDINGS"
    else
      ok detect-secrets
    fi
  fi
fi

# --- generic static analysis --------------------------------------------------------------------
if wanted semgrep; then
  if have semgrep; then
    cfg=(--config p/owasp-top-ten --config p/secrets)
    [ "$has_js" = 1 ] && cfg+=(--config p/typescript --config p/javascript)
    [ "$has_py" = 1 ] && cfg+=(--config p/python)
    [ "$has_go" = 1 ] && cfg+=(--config p/golang)
    [ "$has_rb" = 1 ] && cfg+=(--config p/ruby)
    [ "$has_php" = 1 ] && cfg+=(--config p/php)
    [ "$has_java" = 1 ] && cfg+=(--config p/java)
    [ "$has_docker" = 1 ] && cfg+=(--config p/dockerfile)
    run semgrep semgrep scan "${cfg[@]}" --error --quiet --metrics=off \
        --json-output "$OUT/raw/semgrep.json" \
        --exclude node_modules --exclude .next --exclude dist --exclude vendor .
    verdict semgrep 1
  else skip semgrep "not installed (brew install semgrep)"; fi
fi
if wanted codeql; then
  if ! have codeql; then skip codeql "not installed"
  elif [ "$DEEP" != 1 ]; then skip codeql "needs --deep (builds a database, minutes)"
  else
    cql_lang=""
    [ "$has_py" = 1 ] && cql_lang=python
    [ "$has_js" = 1 ] && cql_lang=javascript
    [ "$has_go" = 1 ] && cql_lang=go
    [ "$has_java" = 1 ] && cql_lang=java
    if [ -z "$cql_lang" ]; then skip codeql "no language codeql covers detected"
    else
      run codeql-db codeql database create "$OUT/codeql-db" --language="$cql_lang" --source-root=. --overwrite
      if [ "$rc" -ne 0 ]; then err codeql "database build failed, see raw/codeql-db.txt"
      else
        run codeql codeql database analyze "$OUT/codeql-db" --format=sarif-latest \
            --output="$OUT/raw/codeql.sarif" --download
        verdict codeql 1
      fi
    fi
  fi
fi

# --- python ---------------------------------------------------------------------------------------
if [ "$has_py" = 1 ]; then
  if wanted bandit; then
    if have bandit; then run bandit bandit -r . -f json -o "$OUT/raw/bandit.json" -q \
        -x ./node_modules,./.venv,./venv,./tests; verdict bandit 1
    else skip bandit "not installed (uv tool install bandit)"; fi
  fi
  if wanted ruff-security; then
    if have ruff; then run ruff-security ruff check --select S --output-format json .; verdict ruff-security 1
    else skip ruff-security "ruff not installed"; fi
  fi
  if wanted pip-audit; then
    if have pip-audit; then run pip-audit pip-audit --progress-spinner off; verdict pip-audit 1
    else skip pip-audit "not installed (uv tool install pip-audit)"; fi
  fi
else
  skip python-lane "no python project files"
fi

# --- javascript / typescript ------------------------------------------------------------------
if [ "$has_js" = 1 ]; then
  if wanted npm-audit; then
    if have npm; then run npm-audit npm audit --audit-level=high --json; verdict npm-audit 1
    else skip npm-audit "npm not installed"; fi
  fi
  if wanted eslint-security; then
    esl_cfg=0
    for f in eslint.config.js eslint.config.mjs eslint.config.cjs eslint.config.ts \
             .eslintrc .eslintrc.js .eslintrc.cjs .eslintrc.json .eslintrc.yml .eslintrc.yaml; do
      [ -f "$f" ] && esl_cfg=1
    done
    if [ "$esl_cfg" = 0 ]; then skip eslint-security "no eslint config in repo"
    elif ! have npx; then skip eslint-security "npx not installed"
    else run eslint-security npx --no-install eslint . --format json; verdict eslint-security 1; fi
  fi
  if wanted retire; then
    if have retire; then run retire retire --outputformat json --path .; verdict retire 13
    else skip retire "not installed (npm i -g retire)"; fi
  fi
else
  skip javascript-lane "no package.json"
fi

# --- go ---------------------------------------------------------------------------------------
if [ "$has_go" = 1 ]; then
  if wanted gosec; then
    if have gosec; then run gosec gosec -fmt json -out "$OUT/raw/gosec.json" -quiet ./...; verdict gosec 1
    else skip gosec "not installed (brew install gosec)"; fi
  fi
  if wanted govulncheck; then
    if have govulncheck; then run govulncheck govulncheck ./...; verdict govulncheck 3
    else skip govulncheck "not installed (go install golang.org/x/vuln/cmd/govulncheck@latest)"; fi
  fi
  if wanted staticcheck; then
    if have staticcheck; then run staticcheck staticcheck ./...; verdict staticcheck 1
    else skip staticcheck "not installed (go install honnef.co/go/tools/cmd/staticcheck@latest)"; fi
  fi
else
  skip go-lane "no go.mod"
fi

# --- rust --------------------------------------------------------------------------------------
if [ "$has_rs" = 1 ]; then
  if wanted cargo-audit; then
    if have cargo-audit || cargo audit --version >/dev/null 2>&1; then
      run cargo-audit cargo audit --json; verdict cargo-audit 1
    else skip cargo-audit "not installed (cargo install cargo-audit)"; fi
  fi
  if wanted cargo-deny; then
    if have cargo-deny || cargo deny --version >/dev/null 2>&1; then
      run cargo-deny cargo deny check advisories bans licenses; verdict cargo-deny 1
    else skip cargo-deny "not installed (cargo install cargo-deny)"; fi
  fi
  if wanted clippy; then
    if cargo clippy --version >/dev/null 2>&1; then
      run clippy cargo clippy --all-targets -- -D warnings; verdict clippy 101,1
    else skip clippy "not installed (rustup component add clippy)"; fi
  fi
else
  skip rust-lane "no Cargo.toml"
fi

# --- ruby / php --------------------------------------------------------------------------------
if [ "$has_rb" = 1 ]; then
  if wanted brakeman; then
    if have brakeman; then run brakeman brakeman -q -f json -o "$OUT/raw/brakeman.json"; verdict brakeman 3
    else skip brakeman "not installed (gem install brakeman)"; fi
  fi
  if wanted bundler-audit; then
    if have bundle-audit || have bundler-audit; then
      run bundler-audit sh -c 'bundle-audit check --update || bundler-audit check --update'
      verdict bundler-audit 1
    else skip bundler-audit "not installed (gem install bundler-audit)"; fi
  fi
else
  skip ruby-lane "no Gemfile"
fi
if [ "$has_php" = 1 ]; then
  if wanted phpstan; then
    if have phpstan; then run phpstan phpstan analyse --level max --error-format json .; verdict phpstan 1
    else skip phpstan "not installed (composer global require phpstan/phpstan)"; fi
  fi
  if wanted psalm; then
    if have psalm; then run psalm psalm --taint-analysis --output-format=json; verdict psalm 1,2
    else skip psalm "not installed (composer global require vimeo/psalm)"; fi
  fi
else
  skip php-lane "no composer.json"
fi

# --- shell -------------------------------------------------------------------------------------
if wanted shellcheck; then
  if ! have shellcheck; then skip shellcheck "not installed (brew install shellcheck)"
  elif [ "$has_sh" = 0 ]; then skip shellcheck "no tracked shell scripts"
  else
    # -S info, not -S warning. The two defects this lane exists for -- SC2086 unquoted word
    # splitting and SC2046 unquoted command substitution, the shell's injection primitives --
    # are INFO severity in shellcheck, so a -S warning run reports a script with `rm -rf $1` in
    # it as clean. Measured: the fixture below was green at -S warning.
    run shellcheck sh -c 'git ls-files "*.sh" -z | xargs -0 shellcheck -S info -f gcc'
    verdict shellcheck 1
  fi
fi

# --- containers and IaC ------------------------------------------------------------------------
if [ "$has_docker" = 1 ]; then
  if wanted hadolint; then
    if have hadolint; then run hadolint sh -c 'hadolint -f json $(git ls-files "*Dockerfile*")'; verdict hadolint 1
    else skip hadolint "not installed (brew install hadolint)"; fi
  fi
else
  skip docker-lane "no Dockerfile"
fi
if wanted trivy-fs; then
  if ! have trivy; then skip trivy-fs "not installed (brew install trivy)"
  elif [ "$DEEP" != 1 ]; then skip trivy-fs "needs --deep (full filesystem scan)"
  else run trivy-fs trivy fs --scanners vuln,secret,misconfig --exit-code 1 --format json \
       --output "$OUT/raw/trivy-fs.json" --quiet .; verdict trivy-fs 1; fi
fi
if wanted trivy-config; then
  if have trivy; then run trivy-config trivy config --exit-code 1 --quiet --format json \
       --output "$OUT/raw/trivy-config.json" .; verdict trivy-config 1
  else skip trivy-config "trivy not installed"; fi
fi
if wanted checkov; then
  if ! have checkov; then skip checkov "not installed (uv tool install checkov)"
  elif [ "$has_iac" = 0 ]; then skip checkov "no IaC files detected"
  else run checkov checkov -d . --compact --quiet -o json --output-file-path "$OUT/raw"; verdict checkov 1; fi
fi
if wanted terrascan; then
  if ! have terrascan; then skip terrascan "not installed (brew install terrascan)"
  elif [ "$has_iac" = 0 ]; then skip terrascan "no IaC files detected"
  else run terrascan terrascan scan -d . -o json; verdict terrascan 3,4,5; fi
fi
if wanted kics; then
  if ! have kics; then skip kics "not installed (brew install kics)"
  elif [ "$has_iac" = 0 ]; then skip kics "no IaC files detected"
  else run kics kics scan -p . --report-formats json -o "$OUT/raw" --no-progress; verdict kics 40,50,60,70; fi
fi
if wanted grype; then
  if have grype; then run grype grype dir:. -o json --file "$OUT/raw/grype.json" --fail-on high; verdict grype 1
  else skip grype "not installed (brew install grype)"; fi
fi
if wanted syft-sbom; then
  if have syft; then
    # Not a finding source. An SBOM is the artefact that makes tomorrow's CVE answerable for
    # today's build, which is why it runs even on a clean repo.
    run syft-sbom syft dir:. -o cyclonedx-json="$OUT/sbom.cyclonedx.json" -q
    if [ "$rc" -eq 0 ]; then ok "syft-sbom (wrote sbom.cyclonedx.json)"; else err syft-sbom "exit $rc"; fi
  else skip syft-sbom "not installed (brew install syft)"; fi
fi

# --- dependencies and CI -----------------------------------------------------------------------
if wanted osv-scanner; then
  lock=""
  for f in package-lock.json pnpm-lock.yaml yarn.lock bun.lock uv.lock poetry.lock Cargo.lock go.sum Gemfile.lock composer.lock; do
    [ -f "$f" ] && { lock="$f"; break; }
  done
  if ! have osv-scanner; then skip osv-scanner "not installed (brew install osv-scanner)"
  elif [ -z "$lock" ]; then skip osv-scanner "no lockfile in repo"
  else run osv-scanner osv-scanner scan source --lockfile "$lock" --format json; verdict osv-scanner 1; fi
fi
if wanted zizmor; then
  if ! have zizmor; then skip zizmor "not installed (uv tool install zizmor)"
  elif [ "$has_gha" = 0 ]; then skip zizmor "no .github/workflows"
  else run zizmor zizmor --min-severity medium --format json .github/workflows; verdict zizmor 13,14; fi
fi
if wanted actionlint; then
  if ! have actionlint; then skip actionlint "not installed (brew install actionlint)"
  elif [ "$has_gha" = 0 ]; then skip actionlint "no .github/workflows"
  else run actionlint actionlint -format '{{json .}}'; verdict actionlint 1; fi
fi

# --- dynamic, opt-in, owned targets only --------------------------------------------------------
if [ -n "$DAST_URL" ]; then
  if [ "$OWNED" != 1 ]; then
    err dast "--dast given without --i-own-this-target; refusing to send traffic at $DAST_URL"
  else
    say ""
    say "DAST against $DAST_URL (you asserted you own this target)"
    if wanted nuclei; then
      if have nuclei; then run nuclei nuclei -u "$DAST_URL" -silent -severity low,medium,high,critical \
           -jsonl -o "$OUT/raw/nuclei.jsonl"; verdict nuclei 1
      else skip nuclei "not installed"; fi
    fi
    if wanted nikto; then
      if have nikto; then run nikto nikto -h "$DAST_URL" -ask no -nointeractive; verdict nikto 1
      else skip nikto "not installed"; fi
    fi
    if wanted zap; then
      if have docker; then run zap docker run --rm -t ghcr.io/zaproxy/zaproxy:stable \
           zap-baseline.py -t "$DAST_URL" -I; verdict zap 1,2
      else skip zap "docker not installed"; fi
    fi
  fi
else
  skip dast-lane "no --dast URL (active-attack tools stay off by default)"
fi

# --- accounting ---------------------------------------------------------------------------------
# The whole point of this block. A security report that says "clean" because every scanner was
# missing is worse than no report: it is a false assurance with a timestamp on it. Exit 2 and say
# what was not measured.
# ran counts every lane that reached a verdict; produced counts the lanes that reached a verdict
# ABOUT THE CODE. An errored scanner measured nothing, so a run of twelve errors and no results is
# not clean -- and with n_find at zero the old floor (ran -eq 0) let it print CLEAN.
ran=$((n_ok + n_find + n_err))
produced=$((n_ok + n_find))
{
  printf 'whitebox-audit v%s\n' "$VERSION"
  printf 'repo: %s\n' "$root"
  printf 'when: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'ran: %s   produced a result: %s   findings: %s   errors: %s   skipped: %s\n' "$ran" "$produced" "$n_find" "$n_err" "$n_skip"
} > "$OUT/summary.txt"

say ""
printf 'whitebox-audit: %d scanner(s) ran, %d with findings, %d errored, %d skipped -> %s\n' \
  "$ran" "$n_find" "$n_err" "$n_skip" "$OUT"

if [ "$produced" -eq 0 ]; then
  if [ "$n_err" -gt 0 ]; then
    printf 'NOT MEASURED: %d scanner(s) errored and none produced a result, so this repository has not been audited. Fix the errors above (raw output is under %s/raw) before believing any verdict here.\n' "$n_err" "$OUT"
  else
    printf 'NOT MEASURED: no scanner ran, so this repository has not been audited. Install at least one (see --list) before believing any verdict here.\n'
  fi
  echo "NOT MEASURED" >> "$OUT/summary.txt"
  exit 2
fi
if [ "$n_find" -gt 0 ]; then
  printf 'FINDINGS: %d tool(s) reported. Triage them from %s before shipping.\n' "$n_find" "$FINDINGS"
  echo "FINDINGS" >> "$OUT/summary.txt"
  exit 1
fi
printf 'CLEAN: %d scanner(s) produced a result and none reported (%d errored, %d skipped). That is a statement about these %d tools, not about this code.\n' "$produced" "$n_err" "$n_skip" "$produced"
echo "CLEAN" >> "$OUT/summary.txt"
exit 0
