import sys
from decimal import Decimal, ROUND_HALF_UP
from src.money import round_cents, to_cents
from src.report import total


def q(d):
    return str(Decimal(d).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP))


ok = True
ok &= round_cents(2.675) == "2.68" and round_cents(-0.125) == "-0.13" and round_cents(1.005) == "1.01"
for s in ["0.29", "1.10", "-4.35", "0.07", "19.99", "1.005", "0.285", "0.57", "8.2"]:
    ok &= to_cents(s) == int(Decimal(q(Decimal(s))) * 100)
for lines in [["0.7", "1.005"], ["1.2", "0.005"], ["0.3", "2.675"], ["0.1", "0.2", "0.3"], ["-0.125"],
              ["1.2", "0.285", "0.145"], ["0.7", "0.285"], ["0.2", "1.005"], ["0.3", "0.145"]]:
    ok &= total(lines) == q(sum(Decimal(a) for a in lines))
sys.exit(0 if ok else 1)
