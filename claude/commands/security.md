---
name: security
description: Run security checks (secrets, dependencies, optional: external scanning).
---

Run security checks on this project. **$ARGUMENTS**

Mandatory for any repo that is public or serves prod traffic.

1. **Run the scanner.**
   ```bash
   bash .claude/security-scan.sh
   ```
   Runs gitleaks, semgrep, osv-scanner, and zizmor (eslint too, if a config exists and
   `npm run lint` doesn't already cover it). Prints one line per tool: `ok NAME`, `FAIL NAME`
   (with findings), or `skip NAME (reason)`. A `skip ... (not installed)` means the tool is
   missing — run `./setup-machine.sh` (gitleaks, semgrep, osv-scanner, and zizmor install by
   default there now). Report every line, not just the failures.

2. **`npm audit` for dependency vulnerabilities** (only if `package-lock.json` exists):
   ```bash
   npm audit --audit-level=high
   ```
   Report findings.

3. **History sweep** (catches a secret that's already committed, not just in the working tree):
   ```bash
   gitleaks git --log-opts="--all" --no-banner --redact .
   ```
   A hit here needs `git filter-repo` (or BFG) and a force-push, not a new commit — the secret
   is still in history either way.

4. **Confirm CI is wired.** Check `.github/workflows/security.yml` and `.github/dependabot.yml`
   exist. If either is missing, run `vstack overlay .` to seed them, then report what landed.

5. **Post-deploy scan** (optional — only run this if the user has supplied a deployed
   preview/prod URL; skip otherwise):
   ```bash
   nuclei -u <url> -severity medium,high,critical -silent
   docker run --rm -t zaproxy/zap-stable zap-baseline.py -t <url>
   ```
   If the repo ships a container, also run `trivy fs --scanners vuln,secret,misconfig .`.

6. **Report summary** as a table:

   | Tool | Result | Action |
   |---|---|---|
   | gitleaks | ok / FAIL / skip | ... |
   | semgrep | ok / FAIL / skip | ... |
   | osv-scanner | ok / FAIL / skip | ... |
   | zizmor | ok / FAIL / skip | ... |
   | npm audit | ok / FAIL / skip | ... |
   | nuclei | ok / FAIL / n/a | ... |
   | ZAP baseline | ok / FAIL / n/a | ... |
