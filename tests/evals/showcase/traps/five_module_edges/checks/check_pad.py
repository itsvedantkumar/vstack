import sys
from src.pad import pad_right

ok = (
    pad_right("ab", 5) == "ab" + " " * 3
    and pad_right("あ", 4) == "あ" + " " * 2
    and pad_right("！", 4) == "！" + " " * 2
    and pad_right("hello", 3) == "hello"
    and pad_right("A", 3) == "A" + " " * 2
)
sys.exit(0 if ok else 1)
