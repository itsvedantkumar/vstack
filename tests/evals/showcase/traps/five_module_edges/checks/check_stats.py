import sys
from src.stats import mean

try:
    ok = (
        mean([]) is None
        and mean([1, 2, 3]) == 2.0
        and mean([1, 2, 3, 4]) == 2.5
        and mean([5.0]) == 5.0
    )
except Exception:
    ok = False
sys.exit(0 if ok else 1)
