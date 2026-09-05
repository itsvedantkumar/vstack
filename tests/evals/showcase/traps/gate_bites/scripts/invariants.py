"""SPEC.md section 1 at every boundary. Exit 1 on the first failure, naming it."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from src.rates import rate_for  # noqa: E402

# (units, rate) straight off the SPEC table, including both sides of both boundaries.
CASES = [(0, 0.10), (1, 0.10), (999, 0.10),
         (1000, 0.08), (1001, 0.08), (4999, 0.08),
         (5000, 0.05), (5001, 0.05), (100000, 0.05)]

fails = []
for units, want in CASES:
    got = rate_for(units)
    if got != want:
        fails.append(f"rate_for({units}) = {got}, SPEC says {want}")
if fails:
    print("invariants: FAIL")
    for f in fails:
        print("  " + f)
    sys.exit(1)
print("invariants: ok")
