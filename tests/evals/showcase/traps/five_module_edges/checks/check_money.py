import sys
from src.money import round_cents

ok = (
    round_cents(2.675) == "2.68"
    and round_cents(0.125) == "0.13"
    and round_cents(-0.125) == "-0.13"
    and round_cents(10) == "10.00"
    and round_cents(3.14159) == "3.14"
)
sys.exit(0 if ok else 1)
