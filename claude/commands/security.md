---
name: security
description: Run security checks (secrets, dependencies, optional: external scanning).
---

Run security checks on this project. **$ARGUMENTS**

vstack ships with built-in security checks in the verification gate. External security tools (OWASP ZAP, Trivy, Nuclei, nmap) are optional and can be installed separately if desired.

1. **Run the built-in verification gate.**
   ```bash
   bash ./.claude/verify.sh
   ```
   This checks for:
   - Hardcoded secrets (API keys, tokens, credentials): reads against real token shapes (sk-ant-, sk-proj-, github_pat-, etc.)
   - Hardcoded home paths or infrastructure identifiers
   - Committed files that look like credentials
   - No other files in the repo are checked — only git-tracked files via `git grep`.
   Report the results.

2. **Run npm audit for dependency vulnerabilities** (JavaScript/Node projects only):
   ```bash
   npm audit --audit-level=high
   ```
   This scans `package-lock.json` and `package.json` for known vulnerabilities in your dependency tree. Report findings.

3. **Scan git history for secrets** (optional, catches mistakes that slipped through):
   ```bash
   git log --all --full-history -p | grep -iE 'api_key|secret|token|sk-' | head -20
   ```
   This searches commit history for patterns that look like credentials. If found, use `git filter-branch` or `git-filter-repo` to remove them and force-push.

4. **For advanced scanning (optional, tools not shipped):** If the user has installed external tools and wants to use them:
   - Trivy (filesystem/image/SBOM scanning): `trivy fs --scanners vuln,secret,misconfig .`
   - npm's audit CI mode (CI/CD pipelines): `npm audit --audit-level=high --production`
   - Container image scans (if building images): `trivy image myapp:latest`
   
   These tools are not provided by vstack; the user must install them separately and provide their own configuration.

5. **Report summary.** Built-in gate status (pass/fail), npm audit findings (if any), git history scan (if run), and status of any optional external tools the user has installed.
