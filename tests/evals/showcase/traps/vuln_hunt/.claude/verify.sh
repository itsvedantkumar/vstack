#!/usr/bin/env bash
# The project gate. It runs the service's test suite.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

fail=0
python3 -m unittest discover -s tests -t . -q || fail=1

if [ "$fail" -ne 0 ]; then
  echo "VERIFY FAILED"
  exit 1
fi
echo "VERIFIED"
