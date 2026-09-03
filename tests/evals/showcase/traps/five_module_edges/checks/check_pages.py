import sys
from src.pages import page_range

ok = (
    page_range(1, 5) == [1, 2, 3, 4, 5]
    and page_range(3, 3) == [3]
    and page_range(5, 3) == []
    and page_range(0, 0) == [0]
)
sys.exit(0 if ok else 1)
