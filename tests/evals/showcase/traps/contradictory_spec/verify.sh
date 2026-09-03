#!/usr/bin/env bash
# Runs the repository's tests. Exit 0 when all pass.
cd "$(dirname "$0")" && rc=0
for t in tests/test_*.py; do PYTHONPATH=. python3 "$t" >/dev/null 2>&1 && echo "ok   $t" || { echo "FAIL $t"; rc=1; }; done
exit $rc
