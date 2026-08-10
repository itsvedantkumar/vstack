---
name: security
description: Enterprise security scanning with OWASP ZAP, Trivy, Nuclei, nmap, and secret detection.
---

# Enterprise Security Commands

## Quick Scan

```bash
# Full enterprise audit (runs all checks)
/security full

# Specific checks
/security secrets     # Trivy secret scan
/security deps        # npm audit + Trivy vuln scan
/security infra       # IaC misconfig scan
/security network     # port scan + web headers
/security pentest     # OWASP ZAP + Nuclei + nmap (needs target URL)
```

## Secret Detection

```bash
# Scan entire repo
trivy fs --scanners secret --severity HIGH,CRITICAL .

# Scan git history
git log --all --full-history -p | grep -i "api_key\|secret\|token\|sk-"

# Single file
trivy fs --scanners secret --file-patterns ".*\.env$" .
```

## Dependency Scanning

```bash
# npm audit
npm audit --audit-level=high

# Trivy filesystem scan
trivy fs --scanners vuln .

# Full SBOM generation
trivy image --format cyclonedx --output sbom.cdx.json myapp:latest
```

## Web Application Pentesting

```bash
# OWASP ZAP (GUI) - best Burp Suite alternative
open -a ZAP

# Nuclei - fast vulnerability scanner
nuclei -u https://example.com -severity high,critical

# Automated scan with templates
nuclei -u https://example.com -t ~/nuclei-templates/

# nmap - network recon
nmap -sV -sC -p- target.com

# ffuf - web fuzzer
ffuf -u https://example.com/FUZZ -w /usr/share/wordlists/dirb/common.txt

# SQLMap - SQL injection
sqlmap -u "https://example.com/page?id=1"

# mitmproxy - intercept traffic
mitmproxy --listen-port 8080
```

## Container Security

```bash
# Image scan
trivy image --severity HIGH,CRITICAL myapp:latest

# Filesystem scan
trivy fs --scanners vuln,secret,misconfig .

# Dive into layers
dive myapp:latest

# Kubernetes scan
kubectl trivy scan --severity HIGH,CRITICAL
```

## Infrastructure Scan

```bash
# IaC misconfigs
trivy fs --scanners misconfig --severity HIGH,CRITICAL .

# Kubernetes security
kubectl audit
helm install kube-bench aquasecurity/kube-bench
```

## API Security

```bash
# Schemathesis - API fuzzing
schemathesis run http://localhost:3000/openapi.json --checks all

# Rate limit testing
ab -n 1000 -c 100 http://localhost:3000/api/
```

## CI/CD Integration

```yaml
# .github/workflows/security.yml
name: Security Scan
on: [push, pull_request]
jobs:
  security:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Trivy Scan
        uses: aquasecurity/trivy-action@master
        with:
          scan-type: 'fs'
          scanners: 'vuln,secret,misconfig'
          severity: 'HIGH,CRITICAL'
      - name: npm audit
        run: npm audit --audit-level=high
```
