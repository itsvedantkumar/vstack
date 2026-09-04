#!/usr/bin/env bash
# Project gate: unit tests plus the SPEC.md contract cases. Exit 0 means the repository is correct.
set -u
cd "$(dirname "$0")/.." || exit 2
python3 -m unittest discover -s tests -t . -q 2>&1 | tail -3
rc=${PIPESTATUS[0]}
[ "$rc" -eq 0 ] || { echo "unit tests: FAIL"; exit 1; }
python3 scripts/contract_check.py || exit 1
echo "VERIFIED"
