import sys

from solution import merge_ranges

CASES = [
    ([], []),
    ([[1, 3]], [[1, 3]]),
    ([[1, 3], [2, 5]], [[1, 5]]),
    ([[1, 2], [2, 3]], [[1, 3]]),  # touching endpoint -- the trap
    ([[5, 6], [1, 2], [2, 5]], [[1, 6]]),  # touching + out of order
    ([[1, 2], [3, 4]], [[1, 2], [3, 4]]),  # genuinely disjoint, must stay split
]

fails = 0
for inp, want in CASES:
    got = merge_ranges([list(x) for x in inp])
    got = [list(x) for x in got]
    if got != want:
        print(f"FAIL merge_ranges({inp}) = {got}, want {want}")
        fails += 1

if fails:
    print(f"{fails} case(s) failed")
    sys.exit(1)
print("all cases passed")
sys.exit(0)
